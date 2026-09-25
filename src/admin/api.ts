// The admin API behind /admin. Every route but login requires the admin token,
// as a cookie (set by login) or an Authorization: Bearer header.
import { execFileSync } from "node:child_process";
import { timingSafeEqual } from "node:crypto";
import { existsSync } from "node:fs";
import type { IncomingMessage, ServerResponse } from "node:http";
import type { BotConnections } from "../bots.ts";
import type { RawBot, RawConfig, RawProfile, RuntimeKind } from "../config.ts";
import type { Hub } from "../hub.ts";
import { log } from "../log.ts";
import type { Settings } from "../settings.ts";
import type { Store } from "../store.ts";
import { readTimeline, transcriptPath } from "../transcript.ts";
import { createAppUrl } from "./slack-manifest.ts";

const COOKIE = "ember_admin";
const SECRET_KEY = /KEY|TOKEN|SECRET|PASSWORD|AUTH/i;

export interface AdminDeps {
  settings: Settings;
  store: Store;
  hub: Hub;
  bots: BotConnections;
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

function sameToken(given: string, expected: string): boolean {
  const a = Buffer.from(given);
  const b = Buffer.from(expected);
  return a.length === b.length && expected.length > 0 && timingSafeEqual(a, b);
}

function cookieToken(req: IncomingMessage): string {
  for (const part of (req.headers.cookie ?? "").split(";")) {
    const [name, ...rest] = part.trim().split("=");
    if (name === COOKIE) return decodeURIComponent(rest.join("="));
  }
  return "";
}

function isHttps(req: IncomingMessage): boolean {
  return req.headers["x-forwarded-proto"] === "https" || req.headers["cf-visitor"]?.includes("https") === true;
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

  constructor(deps: AdminDeps) {
    this.#deps = deps;
  }

  /** Handles /admin/api/*; returns false for other paths. */
  async handle(req: IncomingMessage, res: ServerResponse): Promise<boolean> {
    const url = new URL(req.url ?? "/", "http://ember");
    if (!url.pathname.startsWith("/admin/api/")) return false;
    const path = url.pathname.slice("/admin/api".length);
    try {
      if (path === "/login" && req.method === "POST") {
        const { token } = await body(req);
        if (typeof token !== "string" || !sameToken(token, this.#deps.settings.config.adminToken)) throw new HttpError(401, "wrong token");
        const secure = isHttps(req) ? "; Secure" : "";
        res.setHeader("set-cookie", `${COOKIE}=${encodeURIComponent(token)}; HttpOnly; SameSite=Strict; Path=/admin; Max-Age=2592000${secure}`);
        send(res, 200, { ok: true });
        return true;
      }
      if (path === "/logout" && req.method === "POST") {
        res.setHeader("set-cookie", `${COOKIE}=; HttpOnly; SameSite=Strict; Path=/admin; Max-Age=0`);
        send(res, 200, { ok: true });
        return true;
      }
      const bearer = (req.headers.authorization ?? "").replace(/^Bearer\s+/i, "");
      if (!sameToken(cookieToken(req) || bearer, this.#deps.settings.config.adminToken)) throw new HttpError(401, "sign in required");
      await this.#route(req, res, url, path);
    } catch (error) {
      const status = error instanceof HttpError ? error.status : 500;
      if (status === 500) log.error("admin request failed", { path, error });
      if (!res.headersSent) send(res, status, { error: error instanceof Error ? error.message : String(error) });
    }
    return true;
  }

  async #route(req: IncomingMessage, res: ServerResponse, url: URL, path: string): Promise<void> {
    const method = req.method ?? "GET";
    const parts = path.split("/").filter(Boolean).map(decodeURIComponent);
    const [resource, id, action] = parts;

    if (method === "GET" && path === "/overview") return send(res, 200, this.#overview());
    if (method === "GET" && path === "/events") return this.#events(req, res);
    if (method === "GET" && path === "/sessions") return send(res, 200, this.#sessions(url.searchParams.get("bot")));
    if (resource === "sessions" && id && !action && method === "GET") return send(res, 200, this.#session(id));
    if (resource === "sessions" && id && action === "stop" && method === "POST") {
      await this.#deps.hub.stop(id);
      return send(res, 200, { ok: true });
    }
    if (resource === "sessions" && id && action === "evict" && method === "POST") {
      await this.#deps.hub.evict(id);
      return send(res, 200, { ok: true });
    }
    if (resource === "bots" && id && !action && method === "PUT") return send(res, 200, this.#putBot(id, await body(req)));
    if (resource === "bots" && id && !action && method === "DELETE") return send(res, 200, this.#deleteBot(id));
    if (resource === "bots" && id && action === "reconnect" && method === "POST") {
      await this.#deps.bots.reconcile(this.#deps.settings.config);
      return send(res, 200, { ok: true });
    }
    if (resource === "profiles" && id && !action && method === "PUT") return send(res, 200, this.#putProfile(id, await body(req)));
    if (resource === "profiles" && id && !action && method === "DELETE") return send(res, 200, this.#deleteProfile(id));
    if (method === "GET" && path === "/slack/create-app-url") {
      const name = url.searchParams.get("name")?.trim();
      if (!name) throw new HttpError(400, "name is required");
      return send(res, 200, { url: createAppUrl(name) });
    }
    throw new HttpError(404, `no route ${method} ${path}`);
  }

  // ── reads ───────────────────────────────────────────────────────────────

  #overview() {
    const { config } = this.#deps.settings;
    const sessions = this.#deps.store.listSessions();
    const processes = this.#deps.store.listProcesses();
    const memory = processMemory(processes.map((p) => p.pgid));
    return {
      bots: config.bots.map((bot) => ({
        id: bot.id, name: bot.name, enabled: bot.enabled, runtime: bot.runtime, profiles: bot.profiles, model: bot.model ?? null,
        slack: { appToken: mask(bot.slack.appToken), botToken: mask(bot.slack.botToken) },
        connection: this.#deps.bots.state(bot),
        sessions: sessions.filter((s) => s.bot === bot.id).length,
      })),
      profiles: config.profiles.map((p) => ({
        id: p.id, runtime: p.runtime, home: p.home, homeExists: existsSync(p.home), model: p.model ?? null,
        env: Object.entries(p.env).map(([key, value]) => ({ key, secret: SECRET_KEY.test(key), value: SECRET_KEY.test(key) ? mask(value) : value })),
        usedBy: config.bots.filter((b) => b.profiles.includes(p.id)).map((b) => b.id),
      })),
      processes: processes.map((p) => ({ ...p, rssMb: memory.has(p.pgid) ? Math.round(memory.get(p.pgid)! / 1024) : null })),
      counts: {
        sessions: sessions.length,
        running: sessions.filter((s) => this.#deps.hub.processState(s.key) === "running").length,
        warm: sessions.filter((s) => this.#deps.hub.processState(s.key) === "warm").length,
      },
    };
  }

  #summary(key: string, stats = this.#deps.store.sessionStats()) {
    const row = this.#deps.store.getSession(key);
    if (!row) throw new HttpError(404, `unknown session ${key}`);
    const { token: _token, ...visible } = row;
    return { ...visible, process: this.#deps.hub.processState(key), ...(stats.get(key) ?? { turns: 0, pending: 0, lastTurn: null }) };
  }

  #sessions(bot: string | null) {
    const stats = this.#deps.store.sessionStats();
    return this.#deps.store.listSessions().filter((s) => !bot || s.bot === bot).map((s) => this.#summary(s.key, stats));
  }

  #session(key: string) {
    const summary = this.#summary(key);
    const profile = this.#deps.settings.config.profiles.find((p) => p.id === summary.profile);
    const path = profile && summary.runtimeSessionId ? transcriptPath(summary.runtime, profile.home, summary.runtimeSessionId) : undefined;
    return {
      session: summary,
      turns: this.#deps.store.listTurns(key),
      inbound: this.#deps.store.listInbound(key),
      transcript: path ? { path, timeline: readTimeline(summary.runtime, path) } : null,
    };
  }

  #events(req: IncomingMessage, res: ServerResponse): void {
    res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-store", connection: "keep-alive", "x-accel-buffering": "no" });
    res.write("retry: 3000\n\n");
    const onSession = (key: string) => res.write(`event: session\ndata: ${JSON.stringify({ key })}\n\n`);
    const onConfig = () => res.write("event: config\ndata: {}\n\n");
    this.#deps.store.changes.on("session", onSession);
    const unsubscribe = this.#deps.settings.onChange(onConfig);
    const ping = setInterval(() => res.write(": ping\n\n"), 25_000); // keep proxies from closing an idle stream
    req.on("close", () => {
      clearInterval(ping);
      this.#deps.store.changes.off("session", onSession);
      unsubscribe();
    });
  }

  // ── writes ──────────────────────────────────────────────────────────────

  #save(edit: (raw: RawConfig) => RawConfig) {
    try {
      this.#deps.settings.update(edit);
    } catch (error) {
      throw new HttpError(400, error instanceof Error ? error.message : String(error));
    }
    return this.#overview();
  }

  #putBot(id: string, input: Record<string, any>) {
    return this.#save((raw) => {
      const bots = raw.bots ?? [];
      const existing = bots.find((b) => b.id === id);
      const token = (field: "appToken" | "botToken"): string | undefined => {
        const given = input.slack?.[field];
        return typeof given === "string" && given.trim() ? given.trim() : existing?.slack?.[field];
      };
      const appToken = token("appToken");
      const botToken = token("botToken");
      const next: RawBot = {
        id,
        name: typeof input.name === "string" && input.name.trim() ? input.name.trim() : existing?.name ?? id,
        enabled: typeof input.enabled === "boolean" ? input.enabled : existing?.enabled ?? true,
        runtime: (input.runtime ?? existing?.runtime) as RuntimeKind,
        profiles: Array.isArray(input.profiles) ? input.profiles.map(String) : existing?.profiles ?? (existing?.profile ? [existing.profile] : []),
        ...(appToken || botToken ? { slack: { ...(appToken ? { appToken } : {}), ...(botToken ? { botToken } : {}) } } : {}),
      };
      const model = input.model === undefined ? existing?.model : input.model;
      if (typeof model === "string" && model.trim()) next.model = model.trim();
      return { ...raw, bots: existing ? bots.map((b) => (b.id === id ? next : b)) : [...bots, next] };
    });
  }

  #deleteBot(id: string) {
    return this.#save((raw) => {
      if (!raw.bots?.some((b) => b.id === id)) throw new Error(`unknown bot ${id}`);
      return { ...raw, bots: raw.bots.filter((b) => b.id !== id) };
    });
  }

  #putProfile(id: string, input: Record<string, any>) {
    return this.#save((raw) => {
      const profiles = raw.profiles ?? [];
      const existing = profiles.find((p) => p.id === id);
      // env: a string sets the value; null removes the key; an omitted key keeps it (so masked secrets survive edits).
      const env: Record<string, string> = { ...existing?.env };
      for (const [key, value] of Object.entries((input.env ?? {}) as Record<string, unknown>)) {
        if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) throw new Error(`invalid environment variable name ${key}`);
        if (value === null) delete env[key];
        else if (typeof value === "string") env[key] = value;
      }
      const next: RawProfile = {
        id,
        runtime: (input.runtime ?? existing?.runtime) as RuntimeKind,
        home: typeof input.home === "string" && input.home.trim() ? input.home.trim() : existing?.home ?? `homes/${id}`,
        env,
      };
      const model = input.model === undefined ? existing?.model : input.model;
      if (typeof model === "string" && model.trim()) next.model = model.trim();
      if (existing && existing.runtime !== next.runtime && raw.bots?.some((b) => (b.profiles ?? [b.profile]).includes(id))) {
        throw new Error(`profile ${id} is used by a bot; its runtime cannot change`);
      }
      return { ...raw, profiles: existing ? profiles.map((p) => (p.id === id ? next : p)) : [...profiles, next] };
    });
  }

  #deleteProfile(id: string) {
    return this.#save((raw) => {
      const users = (raw.bots ?? []).filter((b) => (b.profiles ?? [b.profile]).includes(id)).map((b) => b.id);
      if (users.length > 0) throw new Error(`profile ${id} is used by ${users.join(", ")}`);
      if (!raw.profiles?.some((p) => p.id === id)) throw new Error(`unknown profile ${id}`);
      return { ...raw, profiles: raw.profiles.filter((p) => p.id !== id) };
    });
  }
}
