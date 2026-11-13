// Feishu apps made by a scan (「建机器人」): Feishu's one-click app registration, an OAuth device flow
// (RFC 8628) as its SDKs' `register_app` runs it. The person opens the link (or scans it as a QR code) in Feishu and
// confirms; the station asks until the app's id and secret come back, and keeps them for the connect made of them.
// The station keeps the device flow and the chosen connect settings until the app has been saved. A restart can then
// resume polling or retry the save without asking Feishu to create another app.
import { randomBytes } from "node:crypto";
import { mkdirSync, renameSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { gzipSync } from "node:zlib";
import { Clock, Effect, Exit, FiberSet, Result, Scope } from "effect";
import type { Viewer } from "../mesh/credential.ts";
import { liveClock } from "../ops/fibers.ts";
import type { Lang } from "../ops/i18n.ts";
import { readJsonFile } from "../ops/json-file.ts";
import { log } from "../ops/log.ts";
import { type Domain, accountsBase } from "./web.ts";

type Json = any;

const ENDPOINT = "/oauth/v1/app/registration";

/// What a connect's app is given, as the person confirms it.
export const ADDONS = {
  scopes: {
    tenant: [
      "im:message",
      "im:message:send_as_bot",
      "im:message.group_msg",
      "im:message.p2p_msg:readonly",
      "im:message.group_at_msg:readonly",
      "im:resource",
      "im:chat:readonly",
      "im:chat.members:read",
      "contact:user.base:readonly",
      "contact:user.email:readonly",
      "contact:user.id:readonly",
      "cardkit:card:write",
      "tenant:tenant:readonly",
      // What people hand the bot or ask of it through feishu_api: documents, wikis, files, sheets and Bases it was
      // shared (read and write), their comments and media, reactions, and reading calendars, tasks and Minutes.
      "docx:document",
      "docx:document:readonly",
      "docs:doc:readonly",
      "wiki:wiki",
      "wiki:wiki:readonly",
      "drive:drive",
      "drive:drive:readonly",
      "sheets:spreadsheet",
      "sheets:spreadsheet:readonly",
      "bitable:app",
      "bitable:app:readonly",
      "docs:document.media:download",
      "docs:document.media:upload",
      "docs:document.comment:read",
      "docs:document.comment:create",
      "docs:permission.member:create",
      "board:whiteboard:node:read",
      "search:docs:read",
      "im:message.reactions:read",
      "im:message.reactions:write_only",
      "calendar:calendar:readonly",
      "task:task:read",
      "minutes:minutes:readonly",
    ],
  },
  events: { items: { tenant: ["im.message.receive_v1"] } },
  callbacks: { items: ["card.action.trigger"] },
};

/// The addons as the registration's link takes them: JSON, gzipped, base64url without padding.
export const encodeAddons = (addons: Json): string => gzipSync(Buffer.from(JSON.stringify(addons))).toString("base64url");

export type RegistrationState = "waiting" | "done" | "denied" | "expired" | "failed";

export type RegistrationContext = { viewer: Viewer; lang: Lang; input: Record<string, unknown> };

export type Registration = {
  id: string;
  by: string;
  url: string;
  expiresAt: number;
  state: RegistrationState;
  error: string | null;
  domain: Domain;
  app: { appId: string; appSecret: string; openId: string | null } | null;
  appId: string | null;
  deviceCode: string | null;
  interval: number;
  workspace: string | null;
  context: RegistrationContext | null;
  connectId: string | null;
};

/// What the overview shows of one (never its secret).
export const shownRegistration = (r: Registration) => ({ id: r.id, url: r.url, expiresAt: r.expiresAt, state: r.state, error: r.error, appId: r.app?.appId ?? r.appId, domain: r.domain });

type Post = (domain: Domain, form: Record<string, string>) => Promise<Json>;

const post: Post = async (domain, form) => {
  const got = await fetch(accountsBase(domain) + ENDPOINT, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(form), signal: AbortSignal.timeout(30_000) });
  const text = await got.text();
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`feishu registration: HTTP ${got.status} ${text.slice(0, 200)}`);
  }
};

export class Registrations {
  private all = new Map<string, Registration>();
  private listeners = new Set<() => void>();
  private scope: Scope.Closeable;
  private run: (effect: Effect.Effect<void>) => Promise<void>;
  private clock: Clock.Clock;
  private post: Post;
  private file: string | undefined;
  private create: ((r: Registration) => Promise<string>) | null = null;
  private completing = new Map<string, Promise<string>>();
  private started = false;

  constructor(options: { clock?: Clock.Clock; post?: Post; file?: string } = {}) {
    this.clock = options.clock ?? liveClock;
    this.post = options.post ?? post;
    this.file = options.file;
    this.scope = Effect.runSync(Scope.make());
    const run = Effect.runSync(Scope.provide(FiberSet.makeRuntimePromise<never, void, never>(), this.scope));
    this.run = (effect) => run(effect.pipe(Effect.provideService(Clock.Clock, this.clock)));
    if (this.file !== undefined) {
      try {
        const saved = readJsonFile(this.file);
        if (!Array.isArray(saved)) throw new Error("invalid feishu registration store");
        for (const r of saved as Registration[]) this.all.set(r.id, r);
      } catch (e) {
        if ((e as NodeJS.ErrnoException).code !== "ENOENT") throw e;
      }
    }
  }

  private persist() {
    if (this.file === undefined) return;
    mkdirSync(dirname(this.file), { recursive: true });
    const tmp = `${this.file}.tmp-${process.pid}`;
    writeFileSync(tmp, `${JSON.stringify([...this.all.values()])}\n`, { mode: 0o600 });
    renameSync(tmp, this.file);
  }

  /// Set once the routes are ready, then resume unfinished registrations from before a restart.
  start(create: (r: Registration) => Promise<string>) {
    this.create = create;
    if (this.started) return;
    this.started = true;
    for (const r of this.all.values()) {
      if (r.state === "waiting" && r.deviceCode !== null) void this.run(this.ask(r, r.deviceCode, r.interval)).catch(() => {});
      else if (r.state === "done" && r.app !== null && r.context !== null) void this.run(this.autoSave(r)).catch(() => {});
      else if (r.state !== "waiting" && r.app === null) this.expireLater(r);
    }
  }

  onChange(listener: () => void) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private changed() {
    for (const l of this.listeners) {
      try {
        l();
      } catch {}
    }
  }

  of(by: string, workspace?: string): Registration[] {
    return [...this.all.values()].filter((r) => r.by === by && (workspace === undefined || r.workspace === null || r.workspace === workspace));
  }

  get(id: string): Registration | undefined {
    return this.all.get(id);
  }

  /// Begins one for `by`: its link once Feishu gave it; the station asks on from then.
  async begin(by: string, domain: Domain, name: string | null, context: RegistrationContext | null = null, workspace: string | null = null): Promise<Registration> {
    const init = await this.post(domain, { action: "init" });
    const methods: unknown[] = Array.isArray(init?.supported_auth_methods) ? init.supported_auth_methods : [];
    if (!methods.includes("client_secret")) throw new Error("feishu registration: client_secret is not offered");
    const begun = await this.post(domain, { action: "begin", archetype: "PersonalAgent", auth_method: "client_secret", request_user_info: "open_id" });
    const deviceCode = typeof begun?.device_code === "string" ? begun.device_code : "";
    const uri = typeof begun?.verification_uri_complete === "string" ? begun.verification_uri_complete : "";
    if (deviceCode === "" || uri === "") throw new Error(`feishu registration: ${begun?.error_description ?? begun?.error ?? "no device code"}`);
    const link = new URL(uri);
    link.searchParams.set("from", "sdk");
    link.searchParams.set("tp", "sdk");
    link.searchParams.set("source", "still.fail");
    if (name !== null && name !== "") link.searchParams.set("name", name);
    link.searchParams.set("addons", encodeAddons(ADDONS));
    const now = Effect.runSync(Clock.currentTimeMillis.pipe(Effect.provideService(Clock.Clock, this.clock)));
    const expiresIn = typeof begun?.expires_in === "number" ? begun.expires_in : 600;
    const r: Registration = { id: randomBytes(6).toString("hex"), by, url: link.toString(), expiresAt: now + expiresIn * 1000, state: "waiting", error: null, domain, app: null, appId: null, deviceCode, interval: typeof begun?.interval === "number" ? begun.interval : 5, workspace, context, connectId: null };
    this.all.set(r.id, r);
    try {
      this.persist();
    } catch (e) {
      this.all.delete(r.id);
      throw e;
    }
    this.changed();
    void this.run(this.ask(r, deviceCode, r.interval)).catch(() => {});
    return r;
  }

  private ask(r: Registration, deviceCode: string, interval: number): Effect.Effect<void> {
    const self = this;
    return Effect.gen(function* () {
      let every = interval;
      let switched = false;
      for (;;) {
        yield* Effect.sleep(every * 1000);
        if (self.all.get(r.id) !== r) return;
        const now = yield* Clock.currentTimeMillis;
        if (now >= r.expiresAt) return self.end(r, "expired", null);
        const said = yield* Effect.result(Effect.tryPromise({ try: () => self.post(r.domain, { action: "poll", device_code: deviceCode }), catch: (e) => e as Error }));
        if (self.all.get(r.id) !== r) return;
        if (!Result.isSuccess(said)) {
          log.warn("feishu", "feishu registration not asked", { error: said.failure.message });
          continue;
        }
        const d = said.success;
        if (typeof d?.client_id === "string" && typeof d?.client_secret === "string") {
          r.app = { appId: d.client_id, appSecret: d.client_secret, openId: typeof d?.user_info?.open_id === "string" ? d.user_info.open_id : null };
          r.appId = r.app.appId;
          r.deviceCode = null;
          r.state = "done";
          // Do not lose the only copy if the journal cannot be written yet. Keep retrying before attempting the save.
          for (;;) {
            try {
              self.persist();
              break;
            } catch (e) {
              log.warn("feishu", "feishu registration not stored; retrying", { id: r.id, error: (e as Error).message });
              yield* Effect.sleep(5000);
            }
          }
          self.end(r, "done", null);
          if (r.context !== null) yield* self.autoSave(r);
          return;
        }
        if (d?.user_info?.tenant_brand === "lark" && !switched && r.domain !== "lark") {
          switched = true;
          r.domain = "lark";
          try { self.persist(); } catch (e) { log.warn("feishu", "feishu registration not stored", { id: r.id, error: (e as Error).message }); }
          continue;
        }
        const error = typeof d?.error === "string" ? d.error : "";
        if (error === "authorization_pending" || error === "") continue;
        if (error === "slow_down") {
          every += 5;
          r.interval = every;
          try { self.persist(); } catch (e) { log.warn("feishu", "feishu registration not stored", { id: r.id, error: (e as Error).message }); }
        }
        else if (error === "access_denied") return self.end(r, "denied", null);
        else if (error === "expired_token") return self.end(r, "expired", null);
        else return self.end(r, "failed", `${error} ${d?.error_description ?? ""}`.trim());
      }
    });
  }

  private end(r: Registration, state: RegistrationState, error: string | null) {
    r.state = state;
    r.error = error;
    if (state !== "waiting") r.deviceCode = null;
    try { this.persist(); } catch (e) { log.warn("feishu", "feishu registration not stored", { id: r.id, error: (e as Error).message }); }
    log.info("feishu", "feishu registration ended", { id: r.id, state, ...(r.app ? { app: r.app.appId } : {}) });
    this.changed();
    if (state !== "done") this.expireLater(r);
  }

  /// Finished receipts and failed scans need not retain links indefinitely. Unsaved apps never expire here.
  private expireLater(r: Registration) {
    const self = this;
    void this.run(Effect.gen(function* () {
      const now = yield* Clock.currentTimeMillis;
      yield* Effect.sleep(Math.max(0, r.expiresAt + 24 * 60 * 60_000 - now));
      while (self.all.get(r.id) === r && r.app === null) {
        self.all.delete(r.id);
        try {
          self.persist();
          self.changed();
          return;
        } catch (e) {
          self.all.set(r.id, r);
          log.warn("feishu", "feishu registration not removed", { id: r.id, error: (e as Error).message });
          yield* Effect.sleep(60_000);
        }
      }
    })).catch(() => {});
  }

  cancel(id: string, by: string, workspace?: string): boolean {
    const r = this.all.get(id);
    if (!r || r.by !== by || (workspace !== undefined && r.workspace !== null && r.workspace !== workspace) || r.state === "done" || r.context !== null) return false;
    this.all.delete(id);
    try { this.persist(); } catch (e) { this.all.set(id, r); throw e; }
    this.changed();
    return true;
  }

  /// One save at a time, shared by the background worker and requests from older clients. Keep the app on any failure.
  async complete(id: string, by: string, workspace: string, save: (r: Registration) => Promise<string>): Promise<string | null> {
    const r = this.all.get(id);
    if (!r || r.by !== by || (r.workspace !== null && r.workspace !== workspace) || r.state !== "done") return null;
    if (r.connectId !== null) return r.connectId;
    if (r.app === null) return null;
    const running = this.completing.get(id);
    if (running) return running;
    const work = (async () => {
      const connectId = await save(r);
      const app = r.app;
      const context = r.context;
      const url = r.url;
      r.connectId = connectId;
      r.app = null;
      r.context = null;
      r.url = "";
      try {
        this.persist();
      } catch (e) {
        r.connectId = null;
        r.app = app;
        r.context = context;
        r.url = url;
        throw e;
      }
      this.changed();
      this.expireLater(r);
      return connectId;
    })();
    this.completing.set(id, work);
    try { return await work; } finally { this.completing.delete(id); }
  }

  private autoSave(r: Registration): Effect.Effect<void> {
    const self = this;
    return Effect.gen(function* () {
      let retryMs = 5000;
      while (self.all.get(r.id) === r && r.context !== null && r.connectId === null) {
        if (self.create === null) return;
        const result = yield* Effect.result(Effect.tryPromise({
          try: () => self.complete(r.id, r.by, r.workspace ?? "", self.create!),
          catch: (e) => e as Error,
        }));
        if (Result.isSuccess(result)) return;
        log.warn("feishu", "feishu connect not saved; retrying", { id: r.id, error: result.failure.message });
        yield* Effect.sleep(retryMs);
        retryMs = Math.min(retryMs * 2, 300_000);
      }
    });
  }

  async close() {
    await Effect.runPromise(Scope.close(this.scope, Exit.void));
  }
}
