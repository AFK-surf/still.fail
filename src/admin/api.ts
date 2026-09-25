// The admin API behind /admin. Local visits are trusted; visits through the
// Cloudflare tunnel must carry a valid Access identity (see access.ts).
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import type { IncomingMessage, ServerResponse } from "node:http";
import type { Connections } from "../connections.ts";
import type { ConnectMode, RawConfig, RawConnect, RawProfile, RuntimeKind } from "../config.ts";
import type { Hub } from "../hub.ts";
import type { LoginManager } from "../login.ts";
import { log } from "../log.ts";
import type { Settings } from "../settings.ts";
import type { Store } from "../store.ts";
import { checkProfile, loginCommand, type ProfileCheck } from "../profiles.ts";
import { readTimeline, readUsage, transcriptPath } from "../transcript.ts";
import { AccessDenied, AccessGate, type Viewer } from "./access.ts";
import { verifySlackTokens } from "../chat/slack.ts";
import { createAppUrl } from "./slack-manifest.ts";
import type { Overview, SessionDetail, SessionSummary } from "./types.ts";

const SECRET_KEY = /KEY|TOKEN|SECRET|PASSWORD|AUTH/i;

export interface AdminDeps {
  settings: Settings;
  store: Store;
  hub: Hub;
  connections: Connections;
  logins: LoginManager;
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

  constructor(deps: AdminDeps) {
    this.#deps = deps;
    this.#gate = deps.gate ?? new AccessGate(() => deps.settings.config.adminAccess);
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
    if (method === "GET" && path === "/sessions") return send(res, 200, this.#sessions(url.searchParams.get("connect")));
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
      const key = this.#deps.hub.bindSingle(id, target, typeof input.title === "string" ? input.title : undefined);
      log.info("single-session binding changed from the admin page", { connect: id, session: key, by: viewer.via === "access" ? viewer.email : "local" });
      return send(res, 200, { session: key });
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
        log.info("login started from the admin page", { profile: id, by: viewer.via === "access" ? viewer.email : "local" });
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
    if (method === "GET" && path === "/slack/create-app-url") {
      const name = url.searchParams.get("name")?.trim();
      if (!name) throw new HttpError(400, "name is required");
      return send(res, 200, { url: createAppUrl(name) });
    }
    throw new HttpError(404, `no route ${method} ${path}`);
  }

  // ── reads ───────────────────────────────────────────────────────────────

  #overview(viewer: Viewer): Overview {
    const { config } = this.#deps.settings;
    const sessions = this.#deps.store.listSessions();
    const processes = this.#deps.store.listProcesses();
    const memory = processMemory(processes.map((p) => p.pgid));
    return {
      viewer,
      connects: config.connects.map((c) => ({
        id: c.id, name: c.name, enabled: c.enabled, kind: c.kind, mode: c.mode, requireMention: c.requireMention,
        bind: { runtime: c.bind.runtime, profiles: c.bind.profiles, model: c.bind.model ?? null },
        slack: { appToken: mask(c.slack.appToken), botToken: mask(c.slack.botToken) },
        connection: this.#deps.connections.state(c),
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

  #sessions(connect: string | null): SessionSummary[] {
    const stats = this.#deps.store.sessionStats();
    const bindings = this.#deps.store.listBindings();
    return this.#deps.store.listSessions().filter((s) => !connect || s.connect === connect).map((s) => this.#summary(s.key, stats, bindings));
  }

  async #session(key: string): Promise<SessionDetail> {
    const summary = this.#summary(key);
    const inbound = this.#deps.store.listInbound(key);
    // Names come from the connect each message arrived through.
    const chatOf = (connect: string) => this.#deps.connections.chats.get(connect) ?? this.#deps.connections.chats.get(summary.connect);
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
      session: summary,
      people,
      channels,
      threads: this.#deps.store.listThreads(key),
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
    log.info("config changed from the admin page", { what, by: viewer.via === "access" ? viewer.email : "local" });
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
        name: typeof input.name === "string" && input.name.trim() ? input.name.trim() : existing?.name ?? id,
        enabled: typeof input.enabled === "boolean" ? input.enabled : existing?.enabled ?? true,
        kind: input.kind ?? existing?.kind ?? "slack",
        mode: (input.mode ?? existing?.mode ?? "multi-session") as ConnectMode,
        requireMention: typeof input.requireMention === "boolean" ? input.requireMention : existing?.requireMention ?? true,
        ...(appToken || botToken ? { slack: { ...(appToken ? { appToken } : {}), ...(botToken ? { botToken } : {}) } } : {}),
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

  async #check(id: string): Promise<ProfileCheck> {
    const profile = this.#deps.settings.config.profiles.find((p) => p.id === id);
    if (!profile) throw new HttpError(404, `unknown profile ${id}`);
    const check = await checkProfile({ runtime: profile.runtime, kind: profile.access.kind, key: profile.access.key, home: profile.home, env: process.env });
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
