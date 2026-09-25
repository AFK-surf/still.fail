// The admin API behind /admin. Local visits are trusted; visits through the
// Cloudflare tunnel must carry a valid Access identity (see access.ts).
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import type { IncomingMessage, ServerResponse } from "node:http";
import type { Connections } from "../connections.ts";
import type { ConnectMode, RawConfig, RawConnect, RawProfile, RuntimeKind } from "../config.ts";
import type { Hub } from "../hub.ts";
import type { LoginManager } from "../login.ts";
import type { MeshStatus } from "../mesh.ts";
import type { ProfileQuota } from "../quota.ts";
import type { Profile } from "../config.ts";
import { INTERNAL_CONNECT } from "../chat/internal.ts";
import { appIdOf, applySettings, rotateConfigToken, SLACK_GROUP_IDS, SlackApiError, slackAppLinks, SlackApps, settingsOf, type SlackAppSettings } from "../chat/slack-apps.ts";
import { log } from "../log.ts";
import type { Settings } from "../settings.ts";
import type { Store } from "../store.ts";
import { checkProfile, loginCommand, type ProfileCheck } from "../profiles.ts";
import { readTimeline, readUsage, transcriptPath } from "../transcript.ts";
import { AccessDenied, AccessGate, viewerId, viewerName, type Viewer } from "./access.ts";
import { verifySlackTokens } from "../chat/slack.ts";
import { createAppUrl, slackManifest } from "./slack-manifest.ts";
import type { Creator, Overview, SessionDetail, SessionSummary } from "./types.ts";

const SECRET_KEY = /KEY|TOKEN|SECRET|PASSWORD|AUTH/i;

export interface AdminDeps {
  settings: Settings;
  store: Store;
  hub: Hub;
  connections: Connections;
  logins: LoginManager;
  /** Display names of people seen through ember cloud, by email; shared with ember's own chat. */
  names: Map<string, string>;
  /** ember-mesh's shared secret, and its state for the page. */
  mesh?: { secret(): string | null; status(): MeshStatus };
  /** A profile's allowance; absent where nobody can ask (tests). */
  quota?: (profile: Profile) => Promise<ProfileQuota>;
  /** How a profile is checked; tests replace it so no real CLI runs. */
  checkProfile?: typeof checkProfile;
  /** Slack's app API; defaults to one using the configuration token in the config. */
  slackApps?: SlackApps;
  /** Decides who may use the API; defaults to Cloudflare Access per the config. */
  gate?: AccessGate;
}

class HttpError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export function mask(value: string): string {
  if (!value) return "";
  return value.length <= 8 ? "••••" : `${value.slice(0, 5)}…${value.slice(-4)}`;
}

async function body(req: IncomingMessage): Promise<Record<string, any>> {
  let text = "";
  req.setEncoding("utf8");
  for await (const chunk of req) {
    text += chunk;
    if (text.length > 1_000_000) throw new HttpError(413, "request too large");
  }
  if (!text) return {};
  try {
    return JSON.parse(text) as Record<string, any>;
  } catch {
    throw new HttpError(400, "invalid JSON");
  }
}

function send(res: ServerResponse, status: number, value: unknown): void {
  res.writeHead(status, { "content-type": "application/json", "cache-control": "no-store" }).end(JSON.stringify(value));
}

/** Memory of each recorded runtime process group, from ps. */
function processMemory(pgids: number[]): Map<number, number> {
  const rss = new Map<number, number>();
  if (pgids.length === 0) return rss;
  try {
    const out = execFileSync("ps", ["-axo", "pgid=,rss="], { encoding: "utf8" });
    for (const line of out.trim().split("\n")) {
      const [pgid, kb] = line.trim().split(/\s+/).map(Number) as [number, number];
      if (pgids.includes(pgid)) rss.set(pgid, (rss.get(pgid) ?? 0) + kb);
    }
  } catch {
    // ps unavailable: memory is simply not shown
  }
  return rss;
}

export class AdminApi {
  readonly #deps: AdminDeps;
  readonly #gate: AccessGate;
  readonly #checks = new Map<string, ProfileCheck>();
  readonly #quotas = new Map<string, ProfileQuota>();
  readonly #quotaPending = new Set<string>();
  readonly #apps: SlackApps;
  readonly #appIds = new Map<string, string>();

  constructor(deps: AdminDeps) {
    this.#deps = deps;
    this.#gate = deps.gate ?? new AccessGate(() => deps.settings.config.adminAccess, undefined, () => deps.mesh?.secret() ?? null);
    this.#apps = deps.slackApps ?? new SlackApps(
      () => deps.settings.config.slackConfigToken,
      (token) => deps.settings.update((raw) => {
        const { slackConfigToken: _old, ...rest } = raw;
        return token ? { ...rest, slackConfigToken: token } : rest;
      }),
    );
    // A finished sign-in changes what the profile can do; check it again right away.
    deps.logins.changes.on("change", (id: string) => {
      if (deps.logins.get(id)?.state === "done") void this.#check(id).catch((error) => log.warn("check after login failed", { profile: id, error }));
    });
  }

  /** Handles /admin/api/*; returns false for other paths. */
  async handle(req: IncomingMessage, res: ServerResponse): Promise<boolean> {
    const url = new URL(req.url ?? "/", "http://ember");
    if (!url.pathname.startsWith("/admin/api/")) return false;
    const path = url.pathname.slice("/admin/api".length);
    try {
      let viewer: Viewer;
      try {
        viewer = await this.#gate.check(req);
      } catch (error) {
        if (error instanceof AccessDenied) throw new HttpError(403, error.message);
        throw error;
      }
      if (viewer.via === "mesh" && viewer.name) this.#deps.names.set(viewer.email, viewer.name);
      await this.#route(req, res, url, path, viewer);
    } catch (error) {
      const status = error instanceof HttpError ? error.status : 500;
      if (status === 500) log.error("admin request failed", { path, error });
      if (!res.headersSent) send(res, status, { error: error instanceof Error ? error.message : String(error) });
    }
    return true;
  }

  async #route(req: IncomingMessage, res: ServerResponse, url: URL, path: string, viewer: Viewer): Promise<void> {
    const method = req.method ?? "GET";
    const parts = path.split("/").filter(Boolean).map(decodeURIComponent);
    const [resource, id, action] = parts;

    if (method === "GET" && path === "/overview") return send(res, 200, this.#overview(viewer));
    if (method === "GET" && path === "/events") return this.#events(req, res);
    if (method === "GET" && path === "/sessions") return send(res, 200, await this.#sessions(url.searchParams.get("connect")));
    if (resource === "sessions" && id && !action && method === "GET") return send(res, 200, await this.#session(id));
    if (resource === "sessions" && id && action === "stop" && method === "POST") {
      await this.#deps.hub.stop(id);
      return send(res, 200, { ok: true });
    }
    if (resource === "sessions" && id && action === "evict" && method === "POST") {
      await this.#deps.hub.evict(id);
      return send(res, 200, { ok: true });
    }
    if (resource === "connects" && id && !action && method === "PUT") return send(res, 200, this.#putConnect(id, await body(req), viewer));
    if (resource === "connects" && id && !action && method === "DELETE") return send(res, 200, this.#deleteConnect(id, viewer));
    if (resource === "connects" && id && action === "session" && method === "POST") {
      const input = await body(req);
      const target = typeof input.session === "string" && input.session ? input.session : null;
      const key = this.#deps.hub.bindSingle(id, target, typeof input.title === "string" ? input.title : undefined, viewerId(viewer));
      log.info("single-session binding changed from the admin page", { connect: id, session: key, by: viewerId(viewer) });
      return send(res, 200, { session: key });
    }
    if (resource === "sessions" && id && action === "chats" && method === "POST") {
      const input = await body(req);
      if (!this.#deps.store.getSession(id)) throw new HttpError(404, `unknown session ${id}`);
      const title = typeof input.title === "string" && input.title.trim() ? input.title.trim().slice(0, 80) : null;
      return send(res, 200, { threadTs: this.#deps.hub.openChat(id, viewerId(viewer), title) });
    }
    if (resource === "chats" && id && action === "messages" && method === "POST") {
      const input = await body(req);
      const text = String(input.text ?? "").trim();
      if (!text) throw new HttpError(400, "消息是空的");
      if (!this.#deps.store.getChat(id)) throw new HttpError(404, `unknown chat ${id}`);
      await this.#deps.hub.sayInChat(id, viewerId(viewer), text);
      return send(res, 200, { ok: true });
    }
    if (resource === "sessions" && id && action === "title" && method === "POST") {
      const input = await body(req);
      if (!this.#deps.store.getSession(id)) throw new HttpError(404, `unknown session ${id}`);
      this.#deps.store.setTitle(id, typeof input.title === "string" && input.title.trim() ? input.title.trim().slice(0, 80) : null);
      return send(res, 200, { ok: true });
    }
    if (resource === "connects" && id && action === "reconnect" && method === "POST") {
      await this.#deps.connections.reconcile(this.#deps.settings.config);
      return send(res, 200, { ok: true });
    }
    if (resource === "profiles" && id && !action && method === "PUT") {
      const overview = this.#putProfile(id, await body(req), viewer);
      this.#check(id).catch((error) => log.warn("profile check failed", { profile: id, error })); // report the new state once known
      return send(res, 200, overview);
    }
    if (resource === "profiles" && id && action === "check" && method === "POST") return send(res, 200, await this.#check(id));
    if (resource === "profiles" && id && action === "quota" && method === "POST") return send(res, 200, await this.#refreshQuota(id));
    if (resource === "profiles" && id && action === "login") {
      const profile = this.#deps.settings.config.profiles.find((p) => p.id === id);
      if (!profile) throw new HttpError(404, `unknown profile ${id}`);
      if (method === "GET") return send(res, 200, { job: this.#deps.logins.get(id) });
      if (method === "DELETE") {
        this.#deps.logins.cancel(id);
        return send(res, 200, { job: this.#deps.logins.get(id) });
      }
      if (method === "POST") {
        if (profile.access.kind !== "subscription") throw new HttpError(400, "只有订阅账号需要登录");
        log.info("login started from the admin page", { profile: id, by: viewerId(viewer) });
        return send(res, 200, { job: this.#deps.logins.start(profile) });
      }
    }
    if (resource === "profiles" && id && action === "login-code" && method === "POST") {
      const input = await body(req);
      try {
        return send(res, 200, { job: this.#deps.logins.submitCode(id, String(input.code ?? "")) });
      } catch (error) {
        throw new HttpError(400, error instanceof Error ? error.message : String(error));
      }
    }
    if (resource === "profiles" && id && !action && method === "DELETE") return send(res, 200, this.#deleteProfile(id, viewer));
    if (method === "POST" && path === "/slack/verify") {
      // Blank tokens fall back to the stored ones of `connect`, so replacing one token can be checked alone.
      const input = await body(req);
      const stored = typeof input.connect === "string" ? this.#deps.settings.config.connects.find((c) => c.id === input.connect)?.slack : undefined;
      const pick = (field: "appToken" | "botToken") =>
        typeof input[field] === "string" && input[field].trim() ? input[field].trim() : stored?.[field] ?? "";
      return send(res, 200, await verifySlackTokens({ appToken: pick("appToken"), botToken: pick("botToken") }));
    }
    // Development only (EMBER_DEV=1, local visits): hand ember a chat message as if the connect had received it.
    if (method === "POST" && path === "/dev/inject" && process.env.EMBER_DEV === "1" && viewer.via === "local") {
      const input = await body(req);
      const ts = String(input.ts);
      await this.#deps.hub.accept(String(input.connect), {
        channel: String(input.channel), threadTs: String(input.threadTs ?? ts), ts, user: String(input.user), text: String(input.text), addressed: input.addressed !== false,
      });
      return send(res, 200, { ok: true });
    }
    if (path === "/slack/config-token") {
      if (method === "GET") return send(res, 200, this.#configTokenView());
      if (method === "PUT") {
        const input = await body(req);
        const refresh = String(input.refreshToken ?? "").trim();
        if (!refresh.startsWith("xoxe-")) throw new HttpError(400, "Refresh token 应该以 xoxe- 开头（不是 xoxe.xoxp- 开头的那个）");
        const token = await rotateConfigToken(refresh).catch((error) => { throw new HttpError(400, `Slack 没接受这个 token：${error instanceof Error ? error.message : String(error)}`); });
        this.#deps.settings.update((raw) => ({ ...raw, slackConfigToken: token }));
        log.info("slack configuration token set", { team: token.teamId, by: viewerId(viewer) });
        return send(res, 200, this.#configTokenView());
      }
      if (method === "DELETE") {
        this.#deps.settings.update((raw) => {
          const { slackConfigToken: _old, ...rest } = raw;
          return rest;
        });
        return send(res, 200, this.#configTokenView());
      }
    }
    if (resource === "connects" && id && action === "slack-app") {
      if (method === "GET") return send(res, 200, await this.#slackApp(id));
      if (method === "PUT") return send(res, 200, await this.#putSlackApp(id, await body(req), viewer));
      if (method === "POST") return send(res, 200, await this.#createSlackApp(id, await body(req), viewer));
    }
    if (method === "GET" && path === "/slack/create-app-url") {
      const name = url.searchParams.get("name")?.trim();
      if (!name) throw new HttpError(400, "name is required");
      return send(res, 200, { url: createAppUrl(name) });
    }
    throw new HttpError(404, `no route ${method} ${path}`);
  }

  // ── Slack apps ──────────────────────────────────────────────────────────

  #configTokenView() {
    const token = this.#deps.settings.config.slackConfigToken;
    return { configured: Boolean(token), teamId: token?.teamId ?? null };
  }

  async #appId(connectId: string): Promise<string | null> {
    const connect = this.#deps.settings.config.connects.find((c) => c.id === connectId);
    if (!connect) throw new HttpError(404, `unknown connect ${connectId}`);
    if (connect.slack.appId) return connect.slack.appId;
    const cached = this.#appIds.get(connectId);
    if (cached) return cached;
    if (!connect.slack.botToken) return null;
    const appId = await appIdOf(connect.slack.botToken);
    this.#appIds.set(connectId, appId);
    return appId;
  }

  async #slackApp(connectId: string) {
    let appId: string | null;
    try {
      appId = await this.#appId(connectId);
    } catch (error) {
      if (error instanceof HttpError) throw error;
      // The bot token no longer works, so the app cannot be looked up; the Slack section says why.
      return { state: "no_app" as const, appId: null, links: null, settings: null, groups: SLACK_GROUP_IDS, error: slackError(error) };
    }
    if (!appId) return { state: "no_app" as const, appId: null, links: null, settings: null, groups: SLACK_GROUP_IDS };
    const links = slackAppLinks(appId);
    if (!this.#apps.configured) return { state: "no_config_token" as const, appId, links, settings: null, groups: SLACK_GROUP_IDS };
    try {
      return { state: "ok" as const, appId, links, settings: settingsOf(await this.#apps.exportManifest(appId)), groups: SLACK_GROUP_IDS };
    } catch (error) {
      return { state: "error" as const, appId, links, settings: null, groups: SLACK_GROUP_IDS, error: slackError(error) };
    }
  }

  async #putSlackApp(connectId: string, input: Record<string, any>, viewer: Viewer) {
    const appId = await this.#appId(connectId);
    if (!appId) throw new HttpError(400, "这个连接还没有 Slack app");
    const edit: Partial<SlackAppSettings> = {};
    for (const field of ["name", "displayName", "description", "longDescription", "backgroundColor"] as const) {
      if (typeof input[field] === "string") edit[field] = input[field];
    }
    if (input.groups && typeof input.groups === "object") edit.groups = input.groups;
    if (edit.name !== undefined && !edit.name.trim()) throw new HttpError(400, "名字不能为空");
    if (edit.backgroundColor && !/^#[0-9a-fA-F]{6}$/.test(edit.backgroundColor.trim())) throw new HttpError(400, "背景色要写成 #RRGGBB");
    let permissionsUpdated = false;
    try {
      const current = await this.#apps.exportManifest(appId);
      ({ permissionsUpdated } = await this.#apps.updateManifest(appId, applySettings(current, edit)));
    } catch (error) {
      throw new HttpError(400, `Slack 没接受这次修改：${slackError(error)}`);
    }
    let iconError: string | null = null;
    if (typeof input.icon === "string" && input.icon) {
      try {
        await this.#apps.setIcon(appId, Buffer.from(input.icon.replace(/^data:image\/png;base64,/, ""), "base64"));
      } catch (error) {
        iconError = error instanceof SlackApiError && error.code === "app_not_owned_by_manager_app"
          ? "Slack 只允许给用 API 创建的 app 换图标。这个 app 是在 Slack 网页上建的，请在 Slack 的 app 设置页上传图标。"
          : slackError(error);
      }
    }
    log.info("slack app updated from the admin page", { connect: connectId, appId, permissionsUpdated, by: viewerId(viewer) });
    return { permissionsUpdated, iconError, links: slackAppLinks(appId) };
  }

  /** Creates the connect's Slack app with the configuration token, so only installing it is left to do in Slack. */
  async #createSlackApp(connectId: string, input: Record<string, any>, viewer: Viewer) {
    const connect = this.#deps.settings.config.connects.find((c) => c.id === connectId);
    if (!connect) throw new HttpError(404, `unknown connect ${connectId}`);
    if (await this.#appId(connectId)) throw new HttpError(400, "这个连接已经有 Slack app 了");
    const name = typeof input.name === "string" && input.name.trim() ? input.name.trim() : connect.name;
    let appId: string;
    try {
      ({ appId } = await this.#apps.createApp(slackManifest(name)));
    } catch (error) {
      throw new HttpError(400, `Slack 没能创建 app：${slackError(error)}`);
    }
    this.#save(viewer, `create slack app for ${connectId}`, (raw) => ({
      ...raw,
      connects: (raw.connects ?? []).map((c) => (c.id === connectId ? { ...c, slack: { ...c.slack, appId } } : c)),
    }));
    return { appId, links: slackAppLinks(appId) };
  }

  // ── reads ───────────────────────────────────────────────────────────────

  #overview(viewer: Viewer): Overview {
    const { config } = this.#deps.settings;
    const sessions = this.#deps.store.listSessions();
    const processes = this.#deps.store.listProcesses();
    const memory = processMemory(processes.map((p) => p.pgid));
    return {
      viewer,
      mesh: this.#deps.mesh?.status() ?? null,
      connects: config.connects.map((c) => ({
        id: c.id, name: c.name, enabled: c.enabled, kind: c.kind, mode: c.mode, requireMention: c.requireMention,
        bind: { runtime: c.bind.runtime, profiles: c.bind.profiles, model: c.bind.model ?? null },
        slack: { appToken: mask(c.slack.appToken), botToken: mask(c.slack.botToken) },
        connection: this.#deps.connections.state(c),
        createdBy: c.createdBy ?? null,
        sessions: sessions.filter((s) => s.connect === c.id).length,
        session: c.mode === "single-session" ? this.#deps.store.binding(c.id) ?? null : null,
      })),
      profiles: config.profiles.map((p) => ({
        id: p.id, name: p.name, runtime: p.runtime, access: { kind: p.access.kind, key: mask(p.access.key) },
        home: p.home, homeExists: existsSync(p.home), model: p.model ?? null,
        env: Object.entries(p.customEnv).map(([key, value]) => ({ key, secret: SECRET_KEY.test(key), value: SECRET_KEY.test(key) ? mask(value) : value })),
        usedBy: config.connects.filter((c) => c.bind.profiles.includes(p.id)).map((c) => c.id),
        loginCommand: loginCommand(p.runtime, p.home),
        check: this.#checks.get(p.id) ?? null,
        login: this.#deps.logins.get(p.id),
        quota: this.#quotaFor(p),
      })),
      processes: processes.map((p) => ({ ...p, rssMb: memory.has(p.pgid) ? Math.round(memory.get(p.pgid)! / 1024) : null })),
      counts: {
        sessions: sessions.length,
        running: sessions.filter((s) => this.#deps.hub.processState(s.key) === "running").length,
        warm: sessions.filter((s) => this.#deps.hub.processState(s.key) === "warm").length,
      },
    };
  }

  #summary(key: string, stats = this.#deps.store.sessionStats(), bindings = this.#deps.store.listBindings()): SessionSummary {
    const row = this.#deps.store.getSession(key);
    if (!row) throw new HttpError(404, `unknown session ${key}`);
    const { token: _token, ...visible } = row;
    return {
      ...visible, boundTo: bindings.get(key) ?? [], process: this.#deps.hub.processState(key),
      ...(stats.get(key) ?? { turns: 0, pending: 0, firstText: null, lastTurn: null }),
    };
  }

  async #sessions(connect: string | null): Promise<SessionSummary[]> {
    const stats = this.#deps.store.sessionStats();
    const bindings = this.#deps.store.listBindings();
    const summaries = this.#deps.store.listSessions().filter((s) => !connect || s.connect === connect).map((s) => this.#summary(s.key, stats, bindings));
    const participants = this.#deps.store.participants();
    return Promise.all(summaries.map(async (s) => ({
      ...s,
      creator: await this.#creator(s.createdBy),
      participants: await this.#people(participants.get(s.key) ?? []),
    })));
  }

  /** Several people, once each: one person may write through Slack and ember's chat under the same email. */
  async #people(refs: string[]): Promise<Creator[]> {
    const seen = new Set<string>();
    const out: Creator[] = [];
    for (const person of await Promise.all(refs.map((r) => this.#creator(r)))) {
      if (!person) continue;
      const id = person.email ?? person.id;
      if (seen.has(id)) continue;
      seen.add(id);
      out.push(person);
    }
    return out;
  }

  /** A creator reference in words: who, and their email where known (to match an ember cloud account). */
  async #creator(ref: string | null): Promise<Creator | null> {
    if (!ref) return null;
    if (ref === "local") return { id: "local", name: "本机管理页", email: null, via: "local" };
    const slack = /^slack:([^:]+):(.+)$/.exec(ref);
    if (slack) {
      const chat = this.#deps.connections.chats.get(slack[1]!);
      const [name, email] = await Promise.all([chat?.userName?.(slack[2]!) ?? null, chat?.userEmail?.(slack[2]!) ?? null]);
      return { id: ref, name: name ?? slack[2]!, email, via: "slack" };
    }
    return { id: ref, name: this.#deps.names.get(ref) ?? ref, email: ref, via: "cloud" };
  }

  async #session(key: string): Promise<SessionDetail> {
    const summary = this.#summary(key);
    const inbound = this.#deps.store.listInbound(key);
    // Names come from the connect each message arrived through.
    const internalNames = { userName: async (user: string) => this.#deps.names.get(user) ?? (user === "local" ? "管理员" : user), channelName: async () => null };
    const chatOf = (connect: string) => connect === INTERNAL_CONNECT ? internalNames : this.#deps.connections.chats.get(connect) ?? this.#deps.connections.chats.get(summary.connect);
    const people: Record<string, string> = {};
    const channels: Record<string, string> = {};
    const users = [...new Map(inbound.map((m) => [m.user, m.connect])).entries()];
    const chans = [...new Map(inbound.map((m) => [m.channel, m.connect])).entries()];
    await Promise.all([
      ...users.map(async ([id, via]) => { const n = await chatOf(via)?.userName?.(id); if (n) people[id] = n; }),
      ...chans.map(async ([id, via]) => { const n = await chatOf(via)?.channelName?.(id); if (n) channels[id] = n; }),
    ]);
    const profile = this.#deps.settings.config.profiles.find((p) => p.id === summary.profile);
    const path = profile && summary.runtimeSessionId ? transcriptPath(summary.runtime, profile.home, summary.runtimeSessionId) : undefined;
    return {
      session: { ...summary, creator: await this.#creator(summary.createdBy), participants: await this.#people(this.#deps.store.participants().get(key) ?? []) },
      people,
      channels,
      threads: this.#deps.store.listThreads(key),
      chats: await Promise.all(this.#deps.store.listChats(key).map(async (c) => ({
        ...c, creator: await this.#creator(c.createdBy), messages: this.#deps.store.chatMessages(c.threadTs),
      }))),
      turns: this.#deps.store.listTurns(key),
      inbound,
      transcript: path ? { path, timeline: readTimeline(summary.runtime, path), usage: readUsage(summary.runtime, path) } : null,
    };
  }

  #events(req: IncomingMessage, res: ServerResponse): void {
    res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-store", connection: "keep-alive", "x-accel-buffering": "no" });
    res.write("retry: 3000\n\n");
    const onSession = (key: string) => res.write(`event: session\ndata: ${JSON.stringify({ key })}\n\n`);
    const onConfig = () => res.write("event: config\ndata: {}\n\n");
    const onLogin = (profile: string) => res.write(`event: login\ndata: ${JSON.stringify({ profile })}\n\n`);
    this.#deps.logins.changes.on("change", onLogin);
    this.#deps.store.changes.on("session", onSession);
    const unsubscribe = this.#deps.settings.onChange(onConfig);
    const ping = setInterval(() => res.write(": ping\n\n"), 25_000); // keep proxies from closing an idle stream
    req.on("close", () => {
      clearInterval(ping);
      this.#deps.store.changes.off("session", onSession);
      this.#deps.logins.changes.off("change", onLogin);
      unsubscribe();
    });
  }

  // ── writes ──────────────────────────────────────────────────────────────

  #save(viewer: Viewer, what: string, edit: (raw: RawConfig) => RawConfig): Overview {
    try {
      this.#deps.settings.update(edit);
    } catch (error) {
      throw new HttpError(400, error instanceof Error ? error.message : String(error));
    }
    log.info("config changed from the admin page", { what, by: viewerId(viewer) });
    return this.#overview(viewer);
  }

  #putConnect(id: string, input: Record<string, any>, viewer: Viewer) {
    return this.#save(viewer, `connect ${id}`, (raw) => {
      const connects = raw.connects ?? [];
      const existing = connects.find((c) => c.id === id);
      const token = (field: "appToken" | "botToken"): string | undefined => {
        const given = input.slack?.[field];
        return typeof given === "string" && given.trim() ? given.trim() : existing?.slack?.[field];
      };
      const appToken = token("appToken");
      const botToken = token("botToken");
      const bind = input.bind ?? {};
      const model = bind.model === undefined ? existing?.bind.model : bind.model;
      const next: RawConnect = {
        id,
        ...ownerOf(existing?.createdBy, input.owner, viewer),
        name: typeof input.name === "string" && input.name.trim() ? input.name.trim() : existing?.name ?? id,
        enabled: typeof input.enabled === "boolean" ? input.enabled : existing?.enabled ?? true,
        kind: input.kind ?? existing?.kind ?? "slack",
        mode: (input.mode ?? existing?.mode ?? "multi-session") as ConnectMode,
        requireMention: typeof input.requireMention === "boolean" ? input.requireMention : existing?.requireMention ?? true,
        ...(appToken || botToken || existing?.slack?.appId
          ? { slack: { ...(appToken ? { appToken } : {}), ...(botToken ? { botToken } : {}), ...(existing?.slack?.appId ? { appId: existing.slack.appId } : {}) } }
          : {}),
        bind: {
          runtime: (bind.runtime ?? existing?.bind.runtime) as RuntimeKind,
          profiles: Array.isArray(bind.profiles) ? bind.profiles.map(String) : existing?.bind.profiles ?? [],
          ...(typeof model === "string" && model.trim() ? { model: model.trim() } : {}),
        },
      };
      return { ...raw, connects: existing ? connects.map((c) => (c.id === id ? next : c)) : [...connects, next] };
    });
  }

  #deleteConnect(id: string, viewer: Viewer) {
    return this.#save(viewer, `delete connect ${id}`, (raw) => {
      if (!raw.connects?.some((c) => c.id === id)) throw new Error(`unknown connect ${id}`);
      return { ...raw, connects: raw.connects.filter((c) => c.id !== id) };
    });
  }

  #putProfile(id: string, input: Record<string, any>, viewer: Viewer) {
    return this.#save(viewer, `profile ${id}`, (raw) => {
      const profiles = raw.profiles ?? [];
      const existing = profiles.find((p) => p.id === id);
      // env: a string sets the value; null removes the key; an omitted key keeps it (so masked secrets survive edits).
      const env: Record<string, string> = { ...existing?.env };
      for (const [key, value] of Object.entries((input.env ?? {}) as Record<string, unknown>)) {
        if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) throw new Error(`invalid environment variable name ${key}`);
        if (value === null) delete env[key];
        else if (typeof value === "string") env[key] = value;
      }
      const kind = input.access?.kind ?? existing?.access?.kind;
      const givenKey = typeof input.access?.key === "string" ? input.access.key.trim() : "";
      const keepKey = kind === existing?.access?.kind ? existing?.access?.key : undefined;
      const key = givenKey || keepKey;
      const name = typeof input.name === "string" ? input.name.trim() : existing?.name;
      const next: RawProfile = {
        id,
        ...(name ? { name } : {}),
        runtime: (input.runtime ?? existing?.runtime) as RuntimeKind,
        ...(kind ? { access: { kind, ...(key ? { key } : {}) } } : {}),
        home: typeof input.home === "string" && input.home.trim() ? input.home.trim() : existing?.home ?? `homes/${id}`,
        env,
      };
      const model = input.model === undefined ? existing?.model : input.model;
      if (typeof model === "string" && model.trim()) next.model = model.trim();
      if (existing && existing.runtime !== next.runtime && raw.connects?.some((c) => (c.bind.profiles ?? []).includes(id))) {
        throw new Error(`profile ${id} is used by a connect; its runtime cannot change`);
      }
      return { ...raw, profiles: existing ? profiles.map((p) => (p.id === id ? next : p)) : [...profiles, next] };
    });
  }

  /** The cached allowance; asks again in the background once it is five minutes old. */
  #quotaFor(profile: Profile): ProfileQuota | null {
    const cached = this.#quotas.get(profile.id);
    if (this.#deps.quota && (!cached || Date.now() - cached.checkedAt > 5 * 60_000)) void this.#refreshQuota(profile.id).catch(() => undefined);
    return cached ?? null;
  }

  async #refreshQuota(id: string): Promise<ProfileQuota | null> {
    const profile = this.#deps.settings.config.profiles.find((p) => p.id === id);
    if (!profile) throw new HttpError(404, `unknown profile ${id}`);
    if (!this.#deps.quota || this.#quotaPending.has(id)) return this.#quotas.get(id) ?? null;
    this.#quotaPending.add(id);
    try {
      const quota = await this.#deps.quota(profile);
      this.#quotas.set(id, quota);
      this.#deps.settings.touch(); // pages refresh the overview
      return quota;
    } finally {
      this.#quotaPending.delete(id);
    }
  }

  async #check(id: string): Promise<ProfileCheck> {
    const profile = this.#deps.settings.config.profiles.find((p) => p.id === id);
    if (!profile) throw new HttpError(404, `unknown profile ${id}`);
    const check = await (this.#deps.checkProfile ?? checkProfile)({ runtime: profile.runtime, kind: profile.access.kind, key: profile.access.key, home: profile.home, env: process.env });
    this.#checks.set(id, check);
    this.#deps.settings.touch();
    return check;
  }

  #deleteProfile(id: string, viewer: Viewer) {
    return this.#save(viewer, `delete profile ${id}`, (raw) => {
      const users = (raw.connects ?? []).filter((c) => (c.bind.profiles ?? []).includes(id)).map((c) => c.id);
      if (users.length > 0) throw new Error(`profile ${id} is used by ${users.join(", ")}`);
      if (!raw.profiles?.some((p) => p.id === id)) throw new Error(`unknown profile ${id}`);
      return { ...raw, profiles: raw.profiles.filter((p) => p.id !== id) };
    });
  }
}

/** Slack's error codes in words people can act on. */
function slackError(error: unknown): string {
  if (!(error instanceof SlackApiError)) return error instanceof Error ? error.message : String(error);
  const known: Record<string, string> = {
    invalid_auth: "配置 token 无效，请重新填写",
    token_expired: "配置 token 过期了，请重新填写",
    invalid_refresh_token: "refresh token 已失效，请重新生成配置 token",
    not_allowed_token_type: "这不是 App 配置 token",
    app_not_found: "Slack 找不到这个 app；配置 token 可能属于别的工作区",
    invalid_manifest: "manifest 不合法",
  };
  const details = Array.isArray(error.details) ? (error.details as { message?: string; pointer?: string }[]).map((d) => `${d.pointer ?? ""} ${d.message ?? ""}`.trim()).join("；") : "";
  return [known[error.code] ?? error.code, details].filter(Boolean).join("：");
}



/**
 * Who a connect belongs to: whoever added it, unless `requested` hands it to
 * someone else. Only the station itself, a workspace owner or admin, or the
 * current owner may do that.
 */
function ownerOf(current: { id: string; name: string } | undefined, requested: unknown, viewer: Viewer): { createdBy?: { id: string; name: string } } {
  const base = current ?? (requested === undefined ? { id: viewerId(viewer), name: viewerName(viewer) } : undefined);
  if (requested === undefined) return base ? { createdBy: base } : {};
  const r = requested as { id?: unknown; name?: unknown } | null;
  const id = typeof r?.id === "string" ? r.id.trim().toLowerCase() : "";
  if (id !== "local" && !/^[^\s@]+@[^\s@]+$/.test(id)) throw new Error("所属用户要写成邮箱");
  const allowed = viewer.via === "local" || (viewer.via === "mesh" && (viewer.role === "owner" || viewer.role === "admin")) || (current !== undefined && current.id === viewerId(viewer));
  if (!allowed) throw new Error("只有 workspace 的 owner、管理员或者当前所属用户能改所属用户");
  return { createdBy: { id, name: typeof r?.name === "string" ? r.name.slice(0, 120) : id } };
}
