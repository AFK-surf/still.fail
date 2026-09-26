// The admin API behind /admin. Local visits are trusted; visits through the
// Cloudflare tunnel must carry a valid Access identity (see access.ts).
//
// Clients follow GET /events instead of asking again on a timer: every change
// to what the API shows is announced there (see docs/station-storage.md).
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import type { EventEmitter } from "node:events";
import { createReadStream, createWriteStream, existsSync, mkdirSync, renameSync } from "node:fs";
import { mkdir, readdir, rm, stat } from "node:fs/promises";
import { basename, extname, join, resolve, sep } from "node:path";
import type { IncomingMessage, ServerResponse } from "node:http";
import type { Connections } from "../connections.ts";
import type { ConnectMode, RawConfig, RawConnect, RawProfile, RuntimeKind } from "../config.ts";
import type { Hub } from "../hub.ts";
import type { LoginManager } from "../login.ts";
import type { MeshStatus } from "../mesh.ts";
import type { Attachment, AuthorKind, EntryRow, MessageRow, Quote, ThreadSummary } from "../store.ts";
import { hostInfo, type HostInfo } from "../host.ts";
import type { ProfileQuota } from "../quota.ts";
import type { Profile } from "../config.ts";
import { INTERNAL_CONNECT } from "../chat/internal.ts";
import { EMBER_SURFACE } from "../store.ts";
import { appIdOf, applySettings, rotateConfigToken, SLACK_GROUP_IDS, SlackApiError, slackAppLinks, SlackApps, settingsOf, type SlackAppSettings } from "../chat/slack-apps.ts";
import { log } from "../log.ts";
import { parseTraceparent, route, serverSpan } from "../tracing.ts";
import type { Settings } from "../settings.ts";
import type { Store } from "../store.ts";
import { checkProfile, loginCommand, type ProfileCheck } from "../profiles.ts";
import { AccessDenied, AccessGate, viewerId, viewerName, type Viewer } from "./access.ts";
import { verifySlackTokens } from "../chat/slack.ts";
import { createAppUrl, slackManifest } from "./slack-manifest.ts";
import { previewTarget, proxyPreview } from "./preview.ts";
import { serves } from "../pool.ts";
import type { ChatRow, ChatRowAgent, Creator, EntryView, MessageView, Overview, ProcessState, SessionDetail, SessionSummary, StationEvents, ThreadEntries, ThreadView } from "./types.ts";

const SECRET_KEY = /KEY|TOKEN|SECRET|PASSWORD|AUTH/i;

export interface AdminDeps {
  settings: Settings;
  store: Store;
  hub: Hub;
  connections: Connections;
  logins: LoginManager;
  /** Display names of people seen through ember cloud, by email; shared with ember's own chat. */
  names: Map<string, string>;
  /**
   * ember-mesh's shared secret, and its state for the page; `changes` emits "change" when the state does. `span`
   * takes a request's span (OTLP JSON) to send with ember-mesh's own, when traces are on.
   */
  mesh?: { secret(): string | null; status(): MeshStatus; changes?: EventEmitter; span?(span: object): void };
  /** A profile's allowance; absent where nobody can ask (tests). */
  quota?: (profile: Profile) => Promise<ProfileQuota>;
  /** How a profile is checked; tests replace it so no real CLI runs. */
  checkProfile?: typeof checkProfile;
  /** Slack's app API; defaults to one using the configuration token in the config. */
  slackApps?: SlackApps;
  /** Decides who may use the API; defaults to Cloudflare Access per the config. */
  gate?: AccessGate;
  /** Check every profile shortly after start (the real station; tests leave it off). */
  checkOnStart?: boolean;
}

/** How often quotas are asked again while someone follows /events, and host info sampled while someone asks for it. */
const QUOTA_MS = 5 * 60_000;
const HOST_MS = 10_000;
/** Keeps proxies (the tunnel) from closing an idle event stream. */
const PING_MS = 25_000;
/** How much of a chat's last message the sidebar gets. */
const LAST_CHARS = 200;

interface Client {
  res: ServerResponse;
  viewer: Viewer;
  /** Wants host samples. */
  host: boolean;
  /** The sidebar rows last sent to it, by id (as JSON); null until they are read. */
  rows: Map<string, string> | null;
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
  const text = JSON.stringify(value);
  res.writeHead(status, { "content-type": "application/json", "cache-control": "no-store", "content-length": Buffer.byteLength(text) }).end(text);
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
  /** Open /events streams (for the keepalive). */
  readonly #clients = new Set<Client>();
  readonly #streams = new Set<ServerResponse>();
  /** Requests whose span is still open: a stream's ends once it is open (`stream`), anything else's when it is answered. */
  readonly #spans = new WeakMap<ServerResponse, (stream: boolean) => void>();
  /** Timers that run only while someone follows: quotas, host samples, keepalives. */
  #quotaTimer: ReturnType<typeof setInterval> | null = null;
  #hostTimer: ReturnType<typeof setInterval> | null = null;
  #pingTimer: ReturnType<typeof setInterval> | null = null;
  #lastHost = "";
  /** Changes waiting to be sent, gathered so a burst becomes one event each. */
  readonly #dirtySessions = new Set<string>();
  #overviewDirty = false;
  /** Viewers whose sidebar rows may have changed; `#rowsDirtyAll`: everyone's. */
  readonly #rowsDirty = new Set<string>();
  #rowsDirtyAll = false;
  #flushing = false;
  /** Events go out in order, though some take a lookup (names) first. */
  #outbox: Promise<void> = Promise.resolve();
  /** The process state last announced per session; the overview counts them. */
  readonly #processStates = new Map<string, ProcessState>();

  constructor(deps: AdminDeps) {
    this.#deps = deps;
    // What the last run learned about profiles shows until they are checked again.
    for (const [id, status] of deps.store.profileStatus()) {
      if (status.check) this.#checks.set(id, status.check);
      if (status.quota) this.#quotas.set(id, status.quota);
    }
    // The account pool picks profiles by what their checks and allowances say.
    deps.hub.setProfileHealth?.((id) => ({ check: this.#checks.get(id) ?? null, quota: this.#quotas.get(id) ?? null }));
    // Check every profile once after a start, so the pool and the model menus know them as they are now.
    if (deps.checkOnStart) {
      setTimeout(() => {
        for (const p of deps.settings.config.profiles) void this.#check(p.id).catch((error) => log.warn("profile check failed", { profile: p.id, error }));
      }, 3000).unref();
    }
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
      this.#overviewChanged();
      if (deps.logins.get(id)?.state === "done") void this.#check(id).catch((error) => log.warn("check after login failed", { profile: id, error }));
    });
    // The sidebar names connects and their Slack workspaces.
    deps.settings.onChange(() => {
      this.#overviewChanged();
      this.#rowsChanged();
    });
    deps.connections.changes.on("change", () => {
      this.#overviewChanged();
      this.#rowsChanged();
    });
    deps.mesh?.changes?.on("change", () => this.#overviewChanged());
    const { changes } = deps.store;
    changes.on("session", (key: string) => {
      this.#dirtySessions.add(key);
      this.#rowsChanged();
    });
    changes.on("session-removed", (key: string) => {
      this.#dirtySessions.delete(key);
      this.#processStates.delete(key);
      this.#emit("session-removed", { key });
      this.#overviewChanged();
      this.#rowsChanged();
    });
    changes.on("thread", (change: { id: number; entries: EntryRow[] }) => {
      if (this.#clients.size === 0) return;
      this.#emitLater("thread", this.#entryViews(change.id, change.entries).then((entries) => ({ id: change.id, entries })));
      this.#rowsChanged();
    });
    changes.on("thread-removed", (removed: StationEvents["thread-removed"]) => {
      this.#emit("thread-removed", removed);
      this.#rowsChanged();
    });
    changes.on("read", (read: StationEvents["read"]) => {
      this.#emit("read", read, (c) => viewerId(c.viewer) === read.viewer);
      this.#rowsChanged(read.viewer);
    });
    // Who the viewer is on Slack: their overview says it, and their rows count it.
    changes.on("identities", (viewer: string) => {
      this.#overviewChanged();
      this.#rowsChanged(viewer);
    });
    changes.on("processes", () => this.#overviewChanged());
  }

  /** Handles /admin/api/*; returns false for other paths. */
  async handle(req: IncomingMessage, res: ServerResponse): Promise<boolean> {
    const url = new URL(req.url ?? "/", "http://ember");
    if (!url.pathname.startsWith("/admin/api/")) return false;
    const path = url.pathname.slice("/admin/api".length);
    // What each request cost here, to tell the station's share of a slow page from the network's; a span of the
    // caller's trace when it records one.
    const started = performance.now();
    const startedAt = Date.now();
    // What went out on the connection (head and body): headers given to writeHead cannot be read back.
    const written = req.socket.bytesWritten;
    const sent = () => req.socket.bytesWritten - written || undefined;
    const parent = parseTraceparent(req.headers.traceparent);
    let who = "?";
    const mesh = this.#deps.mesh;
    if (parent?.sampled && mesh?.span) {
      const span = (stream: boolean) => {
        this.#spans.delete(res);
        mesh.span!(serverSpan(parent, `${req.method} ${route(url.pathname)}`, startedAt, performance.now() - started, {
          "http.request.method": req.method, "url.path": route(url.pathname), "http.response.status_code": res.statusCode,
          "http.response.size": stream ? undefined : sent(), "ember.stream": stream || undefined, "ember.via": who,
        }, res.statusCode >= 500));
      };
      this.#spans.set(res, span);
    }
    res.on("close", () => {
      this.#spans.get(res)?.(false);
      log.info("admin request", { method: req.method, path: url.pathname.slice("/admin/api".length) + url.search, status: res.statusCode, ms: Math.round(performance.now() - started), bytes: sent(), via: who });
    });
    try {
      let viewer: Viewer;
      try {
        viewer = await this.#gate.check(req);
      } catch (error) {
        if (error instanceof AccessDenied) throw new HttpError(403, error.message);
        throw error;
      }
      who = viewer.via;
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

    const preview = previewTarget(path);
    if (preview) return proxyPreview(req, res, preview.port, preview.path + url.search);
    if (method === "GET" && path === "/host") return send(res, 200, await hostInfo(this.#deps.settings.config.dataDir));
    if (method === "GET" && path === "/overview") return send(res, 200, this.#overview(viewer));
    if (method === "GET" && path === "/events") {
      // `live=<key>&from=<n>`, repeated: those sessions as they run, on this same stream (see #events).
      const keys = url.searchParams.getAll("live");
      const froms = url.searchParams.getAll("from");
      const live = keys.map((key, i) => ({ key, from: Math.max(0, Number(froms[i]) || 0) })).filter(({ key }) => {
        try {
          this.#sessionRow(key);
          return true;
        } catch {
          return false;
        }
      });
      return this.#events(req, res, viewer, url.searchParams.get("host") === "1", live);
    }
    if (method === "GET" && path === "/sessions") return send(res, 200, await this.#sessions(url.searchParams.get("connect"), url.searchParams.get("archived") === "1"));
    if (method === "POST" && path === "/sessions") {
      // A new chat: its session and its thread are made first, so files can be uploaded into it before the first message.
      const input = await body(req);
      const runtime = String(input.runtime ?? "");
      if (runtime !== "claude" && runtime !== "codex") throw new HttpError(400, "runtime 必须是 claude 或 codex");
      let made;
      try {
        made = this.#deps.hub.newSession({
          runtime, createdBy: viewerId(viewer),
          ...(typeof input.profile === "string" && input.profile ? { profile: input.profile } : {}),
          ...(typeof input.model === "string" && input.model ? { model: input.model } : {}),
          ...(typeof input.effort === "string" && input.effort ? { effort: input.effort } : {}),
          ...(typeof input.title === "string" ? { title: input.title.slice(0, 120) } : {}),
        });
      } catch (error) {
        throw new HttpError(400, error instanceof Error ? error.message : String(error));
      }
      return send(res, 200, { key: made.key, thread: await this.#thread(made.thread.id, viewer) });
    }
    if (resource === "sessions" && id && !action && method === "GET") return send(res, 200, await this.#session(id, viewer));
    if (resource === "sessions" && id && !action && method === "DELETE") {
      this.#sessionRow(id);
      await this.#deps.hub.deleteSession(id);
      log.info("session deleted from the admin page", { session: id, by: viewerId(viewer) });
      return send(res, 200, { ok: true });
    }
    if (resource === "sessions" && id && action === "archive" && (method === "POST" || method === "DELETE")) {
      this.#sessionRow(id);
      this.#deps.hub.archive(id, method === "POST");
      return send(res, 200, await this.#summary(id));
    }
    if (resource === "sessions" && id && action === "stop" && method === "POST") {
      await this.#deps.hub.stop(id);
      return send(res, 200, { ok: true });
    }
    if (resource === "sessions" && id && action === "evict" && method === "POST") {
      await this.#deps.hub.evict(id);
      return send(res, 200, { ok: true });
    }
    if (method === "GET" && path === "/chats") return send(res, 200, await this.#chats(viewer));
    // "这是我" / "不是我" on a Slack user's name: taken at the viewer's word.
    if (resource === "me" && id === "slack" && action && !parts[3] && (method === "PUT" || method === "DELETE")) {
      this.#deps.store.setSlackIdentity(viewerId(viewer), action, method === "PUT");
      return send(res, 200, this.#overview(viewer));
    }
    if (method === "GET" && path === "/threads") {
      const session = url.searchParams.get("session");
      return send(res, 200, await this.#threads(viewer, session ?? undefined));
    }
    if (method === "POST" && path === "/threads") {
      // Another chat on ember's page with a session in it.
      const input = await body(req);
      const session = String(input.session ?? "");
      this.#sessionRow(session);
      const title = typeof input.title === "string" && input.title.trim() ? input.title.trim().slice(0, 80) : null;
      return send(res, 200, await this.#thread(this.#deps.hub.openChat(session, viewerId(viewer), title).id, viewer));
    }
    if (resource === "threads" && id) {
      const threadId = Number(id);
      const thread = Number.isInteger(threadId) ? this.#deps.store.getThread(threadId) : undefined;
      if (!thread) throw new HttpError(404, `unknown thread ${id}`);
      if (!action && method === "GET") return send(res, 200, await this.#thread(threadId, viewer));
      if (action === "entries" && method === "GET") return send(res, 200, await this.#entries(threadId, url.searchParams));
      if (action === "messages" && method === "POST") {
        if (thread.surface !== EMBER_SURFACE) throw new HttpError(400, "只能在 ember 自己的对话里发消息");
        const input = await body(req);
        const text = String(input.text ?? "").trim();
        const attachments = this.#attachments(threadId, input.attachments);
        const quotes = quotesOf(input.quotes);
        if (!text && attachments.length === 0 && quotes.length === 0) throw new HttpError(400, "消息是空的");
        return send(res, 200, { n: this.#deps.hub.say(threadId, viewerId(viewer), text, attachments, quotes) });
      }
      if (action === "read" && method === "PUT") {
        const input = await body(req);
        const n = Number(input.n);
        if (!Number.isInteger(n) || n < 0) throw new HttpError(400, "n 必须是整数");
        return send(res, 200, { viewer: viewerId(viewer), thread: threadId, n: this.#deps.store.setRead(viewerId(viewer), threadId, n) });
      }
      if (action === "sessions" && method === "POST") {
        const input = await body(req);
        const session = String(input.session ?? "");
        this.#sessionRow(session);
        try {
          this.#deps.hub.addToThread(threadId, session);
        } catch (error) {
          throw new HttpError(400, error instanceof Error ? error.message : String(error));
        }
        return send(res, 200, await this.#thread(threadId, viewer));
      }
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
    if (resource === "sessions" && id && action === "warm" && method === "POST") {
      if (!this.#deps.store.getSession(id)) throw new HttpError(404, `unknown session ${id}`);
      void this.#deps.hub.warm(id).catch((error) => log.warn("warming failed", { session: id, error }));
      return send(res, 202, { ok: true });
    }
    if (resource === "sessions" && id && action === "files" && method === "GET") {
      // A file sent to the session, for previews: only from its upload directory.
      const session = this.#deps.store.getSession(id);
      if (!session) throw new HttpError(404, `unknown session ${id}`);
      const uploads = resolve(session.workspace, "uploads") + sep;
      const path = resolve(uploads, basename(url.searchParams.get("name") ?? ""));
      if (!path.startsWith(uploads) || !existsSync(path)) throw new HttpError(404, "没有这个文件");
      const type = MIME[extname(path).toLowerCase()] ?? "application/octet-stream";
      res.writeHead(200, { "content-type": type, "cache-control": "private, max-age=3600" });
      createReadStream(path).pipe(res);
      return;
    }
    if (method === "POST" && path === "/uploads") {
      // Files wait here, in no chat, until a message takes them into its chat (#attachments): choosing a file for a
      // new chat makes nothing.
      const dir = this.#staged();
      await sweepStaged(dir);
      return send(res, 200, await saveUpload(req, dir, url.searchParams.get("name") ?? "file"));
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
        bind: { runtime: c.bind.runtime, model: c.bind.model ?? null, effort: c.bind.effort ?? null },
        slack: { appToken: mask(c.slack.appToken), botToken: mask(c.slack.botToken) },
        connection: this.#deps.connections.state(c),
        createdBy: c.createdBy ?? null,
        sessions: sessions.filter((s) => s.connect === c.id).length,
        session: c.mode === "single-session" ? this.#deps.store.binding(c.id) ?? null : null,
      })),
      profiles: config.profiles.map((p) => ({
        id: p.id, name: p.name, runtime: p.runtime, access: { kind: p.access.kind, key: mask(p.access.key) },
        home: p.home, homeExists: existsSync(p.home), model: p.model ?? null, models: p.models,
        env: Object.entries(p.customEnv).map(([key, value]) => ({ key, secret: SECRET_KEY.test(key), value: SECRET_KEY.test(key) ? mask(value) : value })),
        // Connects whose sessions can run on it: of its runtime, and its models have theirs.
        usedBy: config.connects.filter((c) => c.bind.runtime === p.runtime && serves(p, c.bind.model ?? null)).map((c) => c.id),
        loginCommand: loginCommand(p.runtime, p.home),
        check: this.#checks.get(p.id) ?? null,
        login: this.#deps.logins.get(p.id),
        quota: this.#quotas.get(p.id) ?? null,
      })),
      processes: processes.map((p) => ({ ...p, rssMb: memory.has(p.pgid) ? Math.round(memory.get(p.pgid)! / 1024) : null })),
      counts: {
        sessions: sessions.length,
        running: sessions.filter((s) => this.#deps.hub.processState(s.key) === "running").length,
        warm: sessions.filter((s) => this.#deps.hub.processState(s.key) === "warm").length,
      },
      slackUsers: this.#deps.store.slackIdentities(viewerId(viewer)),
      // Whether ember can make and edit Slack apps itself (the workspace's app configuration token).
      slackConfig: this.#configTokenView(),
    };
  }

  #sessionRow(key: string) {
    const row = this.#deps.store.getSession(key);
    if (!row) throw new HttpError(404, `unknown session ${key}`);
    return row;
  }

  /** A session for lists and events: its row (without the token), process state, counts and people. */
  async #summary(key: string, stats = this.#deps.store.sessionStats(key), bindings = this.#deps.store.listBindings(), participants = this.#deps.store.participants(key)): Promise<SessionSummary> {
    const { token: _token, ...visible } = this.#sessionRow(key);
    return {
      ...visible, boundTo: bindings.get(key) ?? [], process: this.#deps.hub.processState(key),
      ...(stats.get(key) ?? { turns: 0, pending: 0, firstText: null, lastTurn: null }),
      creator: await this.#creator(visible.createdBy),
      participants: await this.#people(participants.get(key) ?? []),
    };
  }

  /** Sessions shown in lists, or only the archived ones. */
  async #sessions(connect: string | null, archived: boolean): Promise<SessionSummary[]> {
    const stats = this.#deps.store.sessionStats();
    const bindings = this.#deps.store.listBindings();
    const participants = this.#deps.store.participants();
    const rows = this.#deps.store.listSessions().filter((s) => (!connect || s.connect === connect) && (s.archivedAt !== null) === archived);
    return Promise.all(rows.map((s) => this.#summary(s.key, stats, bindings, participants)));
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
      // Never waits on Slack: what is known now, the rest arrives with the next update.
      const person = chat?.knownPerson?.(slack[2]!) ?? null;
      return { id: ref, name: person?.name || slack[2]!, email: person?.email || null, via: "slack" };
    }
    return { id: ref, name: this.#deps.names.get(ref) ?? ref, email: ref, via: "cloud" };
  }

  async #session(key: string, viewer: Viewer): Promise<SessionDetail> {
    return {
      session: await this.#summary(key),
      threads: await this.#threads(viewer, key),
      turns: this.#deps.store.listTurns(key),
    };
  }

  // ── threads ─────────────────────────────────────────────────────────────

  async #threads(viewer: Viewer, session?: string): Promise<ThreadView[]> {
    return Promise.all(this.#deps.store.listThreads(viewerId(viewer), session === undefined ? {} : { session }).map((t) => this.#threadView(t)));
  }

  async #thread(id: number, viewer: Viewer): Promise<ThreadView> {
    const [thread] = this.#deps.store.listThreads(viewerId(viewer), { thread: id });
    if (!thread) throw new HttpError(404, `unknown thread ${id}`);
    return this.#threadView(thread);
  }

  async #threadView(t: ThreadSummary): Promise<ThreadView> {
    const chat = this.#threadChat(t.id);
    const names = this.#authorNames(t.id);
    const [channelName, creator, lastMessage, people] = await Promise.all([
      t.surface === EMBER_SURFACE ? null : chat?.knownChannel?.(t.channel) ?? null,
      this.#creator(t.createdBy),
      t.lastMessage ? this.#messageView(t.lastMessage, names) : null,
      this.#people(t.people),
    ]);
    return { ...t, channelName, creator, lastMessage, people };
  }

  // ── the sidebar ─────────────────────────────────────────────────────────

  /**
   * The viewer's sidebar: one kind of item, an agent (a shown session) merged
   * with its internal chat. An agent in an internal chat is that chat's item;
   * one with none yet is an item without a chat, whose chat is made with its
   * first message. A Slack thread is no item: it lends its agent's item a
   * title (while the chat has no words of its own), the connect and the origin.
   */
  async #chats(viewer: Viewer): Promise<ChatRow[]> {
    const { store, hub } = this.#deps;
    const isMine = this.#isMine(viewer);
    const stats = store.sessionStats();
    const shown = new Map(store.listSessions().filter((s) => s.archivedAt === null).map((s) => [s.key, s]));
    const agent = (key: string): ChatRowAgent => {
      const s = shown.get(key)!;
      const stat = stats.get(key);
      return { key, runtime: s.runtime, model: s.model, effort: s.effort, process: hub.processState(key), pending: stat?.pending ?? 0, lastTurn: stat?.lastTurn ?? null };
    };
    // Each thread's latest message and the viewer's unread count come from the store (lastMessage, unreadCount).
    const threads = store.listThreads(viewerId(viewer));
    // Per agent: the Slack thread it came from (the latest one it is in), and whether it has an internal chat.
    const origins = new Map<string, ThreadSummary>();
    const chatted = new Set<string>();
    for (const t of threads) {
      for (const m of t.sessions) {
        if (t.surface === EMBER_SURFACE) chatted.add(m.session);
        else if (!origins.has(m.session)) origins.set(m.session, t);
      }
    }
    const chats = threads.filter((t) => t.surface === EMBER_SURFACE && t.sessions.some((m) => shown.has(m.session))).map(async (t): Promise<ChatRow> => {
      const from = t.sessions.map((m) => origins.get(m.session)).find((o) => o !== undefined);
      const agents = t.sessions.filter((m) => shown.has(m.session)).map((m) => agent(m.session));
      const [origin, creator, people, last, starters] = await Promise.all([
        from ? this.#origin(from) : null,
        this.#creator(t.createdBy),
        this.#people(t.people),
        t.lastMessage ? this.#messageView(t.lastMessage, this.#authorNames(t.id)) : null,
        Promise.all(agents.map((a) => this.#creator(shown.get(a.key)?.createdBy ?? null))),
      ]);
      return {
        // An item is its agent's, from its first moment to its last: the session key is its id, chat or no chat.
        id: agents[0]!.key, session: agents[0]!.key, thread: t.id,
        title: hasWords(t) || !from ? chatTitle({ ...t, channelName: null }) : chatTitle({ ...from, channelName: origin!.channelName }),
        agents,
        last: last && {
          seq: last.seq, authorKind: last.authorKind, author: last.author, authorName: last.authorName,
          // Something to show when there are no words: a message that only quotes says so.
          text: [...(last.text.trim() || (last.quotes?.length ? "引用了一条消息" : ""))].slice(0, LAST_CHARS).join(""), createdAt: last.createdAt,
        },
        unread: t.unread > 0,
        // Mine: the viewer takes part in the chat, or started one of its sessions (through a connect or on ember).
        mine: isMine(creator) || people.some(isMine) || starters.some(isMine),
        lastActiveAt: Math.max(t.createdAt, t.lastMessage?.createdAt ?? 0),
        connect: from ? slackConnectOf(from) : null,
        origin,
      };
    });
    const agents = [...shown.values()].filter((s) => !chatted.has(s.key)).map(async (s): Promise<ChatRow> => {
      const from = origins.get(s.key);
      const [origin, creator] = await Promise.all([from ? this.#origin(from) : null, this.#creator(s.createdBy)]);
      return {
        id: s.key, session: s.key, thread: null,
        title: s.title?.trim() || (from ? chatTitle({ ...from, channelName: origin!.channelName }) : NO_WORDS),
        agents: [agent(s.key)],
        last: null,
        unread: false,
        // No chat yet: mine only if the viewer started the session; others in its Slack thread do not count.
        mine: isMine(creator),
        lastActiveAt: s.lastActiveAt,
        connect: s.connect === INTERNAL_CONNECT ? null : s.connect,
        origin,
      };
    });
    return Promise.all([...chats, ...agents]);
  }

  /** Whether a person is the viewer: by id, by email, or as a Slack user the viewer said is them. */
  #isMine(viewer: Viewer): (person: Creator | null) => boolean {
    const id = viewerId(viewer);
    const email = viewer.via === "local" ? null : viewer.email.toLowerCase();
    const slack = new Set(this.#deps.store.slackIdentities(id));
    return (person) => person !== null && (person.id === id || (email !== null && person.email?.toLowerCase() === email)
      || (person.via === "slack" && slack.has(person.id.slice(person.id.lastIndexOf(":") + 1))));
  }

  /** Where a Slack thread is, for the connect icon's tip: the Slack workspace, the channel. */
  async #origin(t: ThreadSummary): Promise<NonNullable<ChatRow["origin"]>> {
    const connect = this.#deps.settings.config.connects.find((c) => c.id === slackConnectOf(t));
    const state = connect ? this.#deps.connections.state(connect) : null;
    const teamName = state && (state.state === "connected" || state.state === "reconnecting") ? state.workspace?.team || null : null;
    const channelName = this.#threadChat(t.id)?.knownChannel?.(t.channel) ?? null;
    return { teamName, channel: t.channel, channelName, threadTs: t.threadTs };
  }

  /**
   * GET /threads/:id/entries: `after` (an n) gives what came since; `before`
   * pages back (`limit` entries); `from` and `to` a gap (both included);
   * none of them the latest page.
   */
  async #entries(thread: number, params: URLSearchParams): Promise<ThreadEntries> {
    const store = this.#deps.store;
    const number = (name: string): number | undefined => {
      if (!params.has(name)) return undefined;
      const value = Number(params.get(name));
      if (!Number.isInteger(value) || value < 0) throw new HttpError(400, `${name} 必须是整数`);
      return value;
    };
    const [after, before, from, to] = [number("after"), number("before"), number("from"), number("to")];
    const limit = Math.min(Math.max(Number(params.get("limit")) || 50, 1), 500);
    if ((from === undefined) !== (to === undefined)) throw new HttpError(400, "from 和 to 要一起给");
    const last = store.lastEntry(thread);
    const entries = after !== undefined ? store.entriesAfter(thread, after)
      : from !== undefined ? store.entriesBetween(thread, from, to!)
      : store.entriesBefore(thread, before, limit);
    return { last, entries: await this.#entryViews(thread, entries) };
  }

  /** A connection that can name the thread's people and channel: that of a session taking part. */
  #threadChat(thread: number) {
    for (const m of this.#deps.store.threadSessions(thread)) {
      const chat = m.connect === INTERNAL_CONNECT ? undefined : this.#deps.connections.chats.get(m.connect);
      if (chat) return chat;
    }
    return undefined;
  }

  /** Who wrote in a thread, in words: each author asked once. */
  #authorNames(thread: number): (kind: AuthorKind, author: string) => Promise<string | null> {
    const t = this.#deps.store.getThread(thread);
    const chat = this.#threadChat(thread);
    const members = this.#deps.store.threadSessions(thread);
    const names = new Map<string, Promise<string | null>>();
    const nameOf = (kind: AuthorKind, author: string): Promise<string | null> => {
      if (kind === "ember") return Promise.resolve("ember");
      if (kind === "agent") {
        // An agent goes by the name of the connect it posts through (on the page, of the connect that started it).
        const session = this.#deps.store.getSession(author);
        const via = members.find((x) => x.session === author)?.connect;
        const connect = via === INTERNAL_CONNECT || !via ? session?.connect : via;
        return Promise.resolve(this.#deps.settings.config.connects.find((c) => c.id === connect)?.name ?? session?.title ?? null);
      }
      if (t?.surface === EMBER_SURFACE) return Promise.resolve(author === "local" ? "管理员" : this.#deps.names.get(author) ?? author);
      return Promise.resolve(chat?.knownPerson?.(author)?.name || null);
    };
    return (kind, author) => {
      const key = `${kind}:${author}`;
      if (!names.has(key)) names.set(key, nameOf(kind, author));
      return names.get(key)!;
    };
  }

  /** Entries with their authors' names. */
  async #entryViews(thread: number, entries: EntryRow[]): Promise<EntryView[]> {
    const names = this.#authorNames(thread);
    return Promise.all(entries.map(async (e) => ({ ...e, authorName: await names(e.authorKind, e.author) })));
  }

  /** A merged message as lists show it (a thread's latest), with its author's name. */
  async #messageView(m: MessageRow, names: (kind: AuthorKind, author: string) => Promise<string | null>): Promise<MessageView> {
    return {
      seq: m.n, thread: m.thread, ts: m.ts, authorKind: m.authorKind, author: m.author, authorName: await names(m.authorKind, m.author),
      text: m.text, attachments: m.attachments, quotes: m.quotes, declared: m.declared, createdAt: m.createdAt, editedAt: m.editedAt,
    };
  }

  // ── event streams ───────────────────────────────────────────────────────

  /**
   * What changed, as it changes: see StationEvents. `host` adds host samples; `live`, those sessions as they run
   * (their transcript from `from` on, steps and phase), each message a `live` event — in the one order with the
   * rest, so a client sees an agent's activity and its messages as they happened.
   */
  #events(req: IncomingMessage, res: ServerResponse, viewer: Viewer, host: boolean, live: { key: string; from: number }[] = []): void {
    res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-store", connection: "keep-alive", "x-accel-buffering": "no" });
    res.write("retry: 3000\n\n");
    // A stream's span ends once it is open: it may stay open for hours.
    this.#spans.get(res)?.(true);
    const client: Client = { res, viewer, host, rows: null };
    this.#clients.add(client);
    this.#streams.add(res);
    // What its sidebar shows now: later changes are told against it.
    this.#outbox = this.#outbox.then(async () => {
      client.rows = new Map((await this.#chats(viewer)).map((row) => [row.id, JSON.stringify(row)]));
    }).catch((error) => log.warn("sidebar rows not read", { error }));
    if (host) void this.#sampleHost(client);
    const stops = live.map(({ key, from }) => this.#deps.hub.live.subscribe(key, from, (message) => {
      // Behind whatever is on its way already (a thread's entries being read), never ahead of it.
      this.#outbox = this.#outbox.then(() => {
        if (this.#clients.has(client)) this.#write(client, "live", { key, ...message });
      });
    }));
    this.#timers();
    req.on("close", () => {
      for (const stop of stops) stop();
      this.#clients.delete(client);
      this.#streams.delete(res);
      this.#timers();
    });
  }

  /** Starts what runs only while someone follows, and stops it when nobody does. */
  #timers(): void {
    const following = this.#clients.size > 0;
    if (following && !this.#quotaTimer && this.#deps.quota) {
      this.#quotaTimer = setInterval(() => this.#refreshQuotas(), QUOTA_MS);
      this.#refreshQuotas(); // whatever is older than a round
    } else if (!following && this.#quotaTimer) {
      clearInterval(this.#quotaTimer);
      this.#quotaTimer = null;
    }
    const sampling = [...this.#clients].some((c) => c.host);
    if (sampling && !this.#hostTimer) this.#hostTimer = setInterval(() => void this.#sampleHost(), HOST_MS);
    else if (!sampling && this.#hostTimer) {
      clearInterval(this.#hostTimer);
      this.#hostTimer = null;
      this.#lastHost = "";
    }
    if (this.#streams.size > 0 && !this.#pingTimer) {
      this.#pingTimer = setInterval(() => { for (const res of this.#streams) res.write(": ping\n\n"); }, PING_MS);
    } else if (this.#streams.size === 0 && this.#pingTimer) {
      clearInterval(this.#pingTimer);
      this.#pingTimer = null;
    }
  }

  /** Sends host info to `only`, or to every client asking for it when it changed. */
  async #sampleHost(only?: Client): Promise<void> {
    let info: HostInfo;
    try {
      info = await hostInfo(this.#deps.settings.config.dataDir);
    } catch (error) {
      log.warn("host sample failed", { error });
      return;
    }
    if (only) {
      this.#write(only, "host", info);
      return;
    }
    const { checkedAt: _at, uptimeSec: _up, ...shown } = info;
    const key = JSON.stringify(shown);
    if (key === this.#lastHost) return;
    this.#lastHost = key;
    this.#emit("host", info, (c) => c.host);
  }

  #refreshQuotas(): void {
    for (const p of this.#deps.settings.config.profiles) {
      const cached = this.#quotas.get(p.id);
      if (cached && Date.now() - cached.checkedAt < QUOTA_MS - 1000) continue;
      void this.#refreshQuota(p.id).catch((error) => log.warn("quota refresh failed", { profile: p.id, error }));
    }
  }

  #write<E extends keyof StationEvents>(client: Client, event: E, data: StationEvents[E]): void {
    client.res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  }

  #emit<E extends keyof StationEvents>(event: E, data: StationEvents[E], to: (client: Client) => boolean = () => true): void {
    this.#emitLater(event, Promise.resolve(data), to);
  }

  /** Queues an event whose data takes a moment to make, keeping the order events were raised in. */
  #emitLater<E extends keyof StationEvents>(event: E, data: Promise<StationEvents[E]>, to: (client: Client) => boolean = () => true): void {
    data.catch(() => undefined); // reported where the outbox awaits it
    this.#outbox = this.#outbox.then(async () => {
      const value = await data;
      for (const client of this.#clients) if (to(client)) this.#write(client, event, value);
    }).catch((error) => log.warn("event not sent", { event, error }));
  }

  #overviewChanged(): void {
    this.#overviewDirty = true;
    this.#schedule();
  }

  /** The sidebar rows of `viewer` (everyone's when absent) may have changed. */
  #rowsChanged(viewer?: string): void {
    if (viewer === undefined) this.#rowsDirtyAll = true;
    else this.#rowsDirty.add(viewer);
    this.#schedule();
  }

  /**
   * Reads the rows of the viewers `pick` chooses again, once per viewer, and tells each of their streams what
   * changed since its last rows: `chat` for a new or changed row, `chat-removed` for one gone.
   */
  #sendRows(pick: (viewer: string) => boolean): void {
    const clients = [...this.#clients].filter((c) => pick(viewerId(c.viewer)));
    if (clients.length === 0) return;
    this.#outbox = this.#outbox.then(async () => {
      const read = new Map<string, Promise<ChatRow[]>>();
      for (const client of clients) {
        if (!client.rows || !this.#clients.has(client)) continue;
        const id = viewerId(client.viewer);
        if (!read.has(id)) read.set(id, this.#chats(client.viewer));
        const rows = await read.get(id)!;
        const before = client.rows;
        client.rows = new Map(rows.map((row) => [row.id, JSON.stringify(row)]));
        for (const row of rows) if (before.get(row.id) !== client.rows.get(row.id)) this.#write(client, "chat", row);
        for (const gone of before.keys()) if (!client.rows.has(gone)) this.#write(client, "chat-removed", { id: gone });
      }
    }).catch((error) => log.warn("sidebar rows not sent", { error }));
  }

  /** Gathers the changes of this turn of the event loop into one event per session, one overview and one round of rows. */
  #schedule(): void {
    if (this.#flushing) return;
    this.#flushing = true;
    setImmediate(() => {
      this.#flushing = false;
      const keys = [...this.#dirtySessions];
      this.#dirtySessions.clear();
      for (const key of keys) {
        if (!this.#deps.store.getSession(key)) continue;
        const state = this.#deps.hub.processState(key);
        if (this.#processStates.get(key) !== state) {
          this.#processStates.set(key, state);
          this.#overviewDirty = true; // the overview counts running and warm sessions
        }
        if (this.#clients.size > 0) this.#emitLater("session", this.#summary(key));
      }
      if (this.#overviewDirty) {
        this.#overviewDirty = false;
        if (this.#clients.size > 0) {
          // One overview for everyone; only who is looking differs.
          const [first] = this.#clients;
          const overview = this.#overview(first!.viewer);
          for (const client of this.#clients) {
            const own = { ...overview, viewer: client.viewer, slackUsers: this.#deps.store.slackIdentities(viewerId(client.viewer)) };
            this.#emitLater("overview", Promise.resolve(own), (c) => c === client);
          }
        }
      }
      if (this.#rowsDirtyAll || this.#rowsDirty.size > 0) {
        const all = this.#rowsDirtyAll;
        const viewers = new Set(this.#rowsDirty);
        this.#rowsDirtyAll = false;
        this.#rowsDirty.clear();
        this.#sendRows((viewer) => all || viewers.has(viewer));
      }
    });
  }

  // ── writes ──────────────────────────────────────────────────────────────

  /** Files named in a message: only ones uploaded into a session of the thread (POST /sessions/:key/files). */
  /** Where uploaded files wait for the message that sends them. */
  #staged(): string {
    return join(this.#deps.settings.config.dataDir, "uploads");
  }

  /**
   * Files named in a message: ones waiting in the uploads (they move into the upload directory of the chat's first
   * session, where its agents read them), or ones already in the upload directory of one of its sessions.
   */
  #attachments(thread: number, input: unknown): Attachment[] {
    const dirs = this.#deps.store.threadSessions(thread)
      .map((m) => this.#deps.store.getSession(m.session))
      .filter((s) => s !== undefined)
      .map((s) => resolve(s.workspace, "uploads") + sep);
    const staged = resolve(this.#staged()) + sep;
    return (Array.isArray(input) ? input : []).slice(0, 20).map((a: Record<string, unknown>) => {
      let path = resolve(String(a.path ?? ""));
      if (path.startsWith(staged) && dirs[0]) {
        const into = join(dirs[0], basename(path));
        // Sent again (a retry after the first try got here): it has moved already.
        if (existsSync(path)) {
          mkdirSync(dirs[0], { recursive: true });
          renameSync(path, into);
        }
        path = into;
      }
      const uploads = dirs.find((d) => path.startsWith(d));
      if (!uploads || !existsSync(path)) throw new HttpError(400, "附件不在上传目录里");
      const w = Number(a.width), h = Number(a.height);
      return {
        name: String(a.name ?? path.slice(uploads.length)).slice(0, 200), path, size: Number(a.size) || 0,
        ...(Number.isInteger(w) && Number.isInteger(h) && w > 0 && h > 0 && w < 100_000 && h < 100_000 ? { width: w, height: h } : {}),
      };
    });
  }

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
      const effort = bind.effort === undefined ? existing?.bind.effort : bind.effort;
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
          // A connect's runtime is chosen when it is made: its sessions and their history belong to it.
          runtime: (existing?.bind.runtime ?? bind.runtime) as RuntimeKind,
          ...(typeof model === "string" && model.trim() ? { model: model.trim() } : {}),
          ...(typeof effort === "string" && effort.trim() ? { effort: effort.trim() } : {}),
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
      const models = input.models === undefined ? existing?.models : input.models;
      if (Array.isArray(models) && models.length) next.models = [...new Set(models.map(String).map((m) => m.trim()).filter(Boolean))].slice(0, 200);
      if (existing && existing.runtime !== next.runtime) lastOfRuntime(raw, existing.runtime, id);
      return { ...raw, profiles: existing ? profiles.map((p) => (p.id === id ? next : p)) : [...profiles, next] };
    });
  }

  async #refreshQuota(id: string): Promise<ProfileQuota | null> {
    const profile = this.#deps.settings.config.profiles.find((p) => p.id === id);
    if (!profile) throw new HttpError(404, `unknown profile ${id}`);
    if (!this.#deps.quota || this.#quotaPending.has(id)) return this.#quotas.get(id) ?? null;
    this.#quotaPending.add(id);
    try {
      const quota = await this.#deps.quota(profile);
      this.#quotas.set(id, quota);
      this.#deps.store.setProfileQuota(id, quota);
      this.#overviewChanged();
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
    this.#deps.store.setProfileCheck(id, check);
    this.#overviewChanged();
    return check;
  }

  #deleteProfile(id: string, viewer: Viewer) {
    return this.#save(viewer, `delete profile ${id}`, (raw) => {
      const profile = raw.profiles?.find((p) => p.id === id);
      if (!profile) throw new Error(`unknown profile ${id}`);
      lastOfRuntime(raw, profile.runtime, id);
      return { ...raw, profiles: (raw.profiles ?? []).filter((p) => p.id !== id) };
    });
  }
}

/** A profile leaving its runtime (deleted, or moved to another): refused when it is the last one of a runtime that connects run. */
function lastOfRuntime(raw: RawConfig, runtime: RuntimeKind, id: string): void {
  if ((raw.profiles ?? []).some((p) => p.id !== id && p.runtime === runtime)) return;
  const users = (raw.connects ?? []).filter((c) => c.bind.runtime === runtime).map((c) => c.name ?? c.id);
  if (users.length) throw new Error(`它是最后一个 ${runtime} 的 Profile，${users.join("、")} 还要用它运行`);
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
const NO_WORDS = "（还没有消息）";

/** The connect a Slack thread came in through: the first of its sessions' that is not ember's own. */
function slackConnectOf(t: ThreadSummary): string | null {
  return t.sessions.map((m) => m.connect).find((c) => c !== INTERNAL_CONNECT) ?? null;
}

/** Whether a chat has a title of its own, or something a person said in it to take one from. */
function hasWords(t: Pick<ThreadSummary, "title" | "firstText">): boolean {
  return Boolean(t.title?.trim() || t.firstText?.trim());
}

/**
 * What a thread is called: its title, else the first line a person wrote in it (Slack mentions left out, spaces
 * collapsed), else its Slack channel (`#name`, 私信 for a direct message).
 */
function chatTitle(t: Pick<ThreadSummary, "title" | "firstText" | "surface" | "channel"> & { channelName: string | null }): string {
  const title = t.title?.trim();
  if (title) return title;
  const first = (t.firstText ?? "").replace(/<@[A-Z0-9]+>/g, "").split("\n").map((line) => line.split(/\s+/).filter(Boolean).join(" ")).find((line) => line);
  if (first) return first;
  if (t.channelName?.trim()) return `#${t.channelName.trim()}`;
  if (t.surface !== EMBER_SURFACE && t.channel.startsWith("D")) return "私信";
  return NO_WORDS;
}

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

/** Quotes as the page sends them, bounded. */
function quotesOf(input: unknown): Quote[] {
  return (Array.isArray(input) ? input : []).slice(0, 20).map((q: Record<string, unknown>): Quote => ({
    author: String(q.author ?? "消息").slice(0, 100), text: String(q.text ?? "").slice(0, 4000), comment: String(q.comment ?? "").slice(0, 4000),
    ...(typeof q.ts === "string" && /^\d+\.\d+$/.test(q.ts) ? { ts: q.ts } : {}),
    ...(q.role === "agent" || q.role === "person" ? { role: q.role as "agent" | "person" } : {}),
  })).filter((q) => q.text.trim());
}

const MAX_UPLOAD = 50 * 1024 * 1024;
const MIME: Record<string, string> = {
  ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp", ".svg": "image/svg+xml",
  ".pdf": "application/pdf", ".txt": "text/plain; charset=utf-8", ".md": "text/markdown; charset=utf-8", ".json": "application/json",
};

/** Streams one uploaded file into <workspace>/uploads under a name that cannot escape it. */
/** Files that waited in the uploads a day without a message taking them are dropped. */
const STAGED_FOR_MS = 24 * 3600_000;

async function sweepStaged(dir: string): Promise<void> {
  const now = Date.now();
  for (const name of await readdir(dir).catch(() => [] as string[])) {
    const path = join(dir, name);
    const info = await stat(path).catch(() => null);
    if (info?.isFile() && now - info.mtimeMs > STAGED_FOR_MS) await rm(path, { force: true });
  }
}

/** Saves a request's body in `dir` under its name, made safe and unique. */
async function saveUpload(req: IncomingMessage, dir: string, name: string): Promise<Attachment> {
  const safe = basename(name.replace(/\\/g, "/")).replace(/[\\/\u0000-\u001f]/g, "_").replace(/^\.+/, "").slice(0, 120) || "file";
  await mkdir(dir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const path = join(dir, `${stamp}-${randomBytes(3).toString("hex")}-${safe}`);
  let size = 0;
  const out = createWriteStream(path, { flags: "wx" });
  try {
    for await (const chunk of req) {
      size += (chunk as Buffer).length;
      if (size > MAX_UPLOAD) throw new HttpError(413, "文件太大了，最多 50 MB");
      if (!out.write(chunk)) await new Promise<void>((r) => out.once("drain", () => r()));
    }
    await new Promise<void>((resolveDone, reject) => out.end((error?: Error | null) => (error ? reject(error) : resolveDone())));
  } catch (error) {
    out.destroy();
    await rm(path, { force: true });
    throw error;
  }
  return { name: safe, path, size };
}
