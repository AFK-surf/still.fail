// Feishu apps made by a scan (docs/feishu.md「建机器人」): Feishu's one-click app registration, an OAuth device flow
// (RFC 8628) as its SDKs' `register_app` runs it. The person opens the link (or scans it as a QR code) in Feishu and
// confirms; the station asks until the app's id and secret come back, and keeps them for the connect made of them.
// Registrations live in memory: one not finished within its ten minutes, or across a restart, is begun again.
import { randomBytes } from "node:crypto";
import { gzipSync } from "node:zlib";
import { Clock, Effect, Exit, FiberSet, Result, Scope } from "effect";
import { liveClock } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { type Domain, accountsBase } from "./web.ts";

type Json = any;

const ENDPOINT = "/oauth/v1/app/registration";

/// What a connect's app is given, as the person confirms it (docs/feishu.md).
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
    ],
  },
  events: { items: { tenant: ["im.message.receive_v1"] } },
  callbacks: { items: ["card.action.trigger"] },
};

/// The addons as the registration's link takes them: JSON, gzipped, base64url without padding.
export const encodeAddons = (addons: Json): string => gzipSync(Buffer.from(JSON.stringify(addons))).toString("base64url");

export type RegistrationState = "waiting" | "done" | "denied" | "expired" | "failed";

export type Registration = {
  id: string;
  by: string;
  url: string;
  expiresAt: number;
  state: RegistrationState;
  error: string | null;
  domain: Domain;
  app: { appId: string; appSecret: string; openId: string | null } | null;
};

/// What the overview shows of one (never its secret).
export const shownRegistration = (r: Registration) => ({ id: r.id, url: r.url, expiresAt: r.expiresAt, state: r.state, error: r.error, appId: r.app?.appId ?? null, domain: r.domain });

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

  constructor(options: { clock?: Clock.Clock; post?: Post } = {}) {
    this.clock = options.clock ?? liveClock;
    this.post = options.post ?? post;
    this.scope = Effect.runSync(Scope.make());
    const run = Effect.runSync(Scope.provide(FiberSet.makeRuntimePromise<never, void, never>(), this.scope));
    this.run = (effect) => run(effect.pipe(Effect.provideService(Clock.Clock, this.clock)));
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

  of(by: string): Registration[] {
    return [...this.all.values()].filter((r) => r.by === by);
  }

  get(id: string): Registration | undefined {
    return this.all.get(id);
  }

  /// Begins one for `by`: its link once Feishu gave it; the station asks on from then.
  async begin(by: string, domain: Domain, name: string | null): Promise<Registration> {
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
    const r: Registration = { id: randomBytes(6).toString("hex"), by, url: link.toString(), expiresAt: now + expiresIn * 1000, state: "waiting", error: null, domain, app: null };
    // Earlier ones of theirs not finished are dropped: one link at a time.
    for (const old of this.of(by)) if (old.state !== "done") this.all.delete(old.id);
    this.all.set(r.id, r);
    this.changed();
    void this.run(this.ask(r, deviceCode, typeof begun?.interval === "number" ? begun.interval : 5)).catch(() => {});
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
        if (!Result.isSuccess(said)) {
          log.warn("feishu", "feishu registration not asked", { error: said.failure.message });
          continue;
        }
        const d = said.success;
        if (typeof d?.client_id === "string" && typeof d?.client_secret === "string") {
          r.app = { appId: d.client_id, appSecret: d.client_secret, openId: typeof d?.user_info?.open_id === "string" ? d.user_info.open_id : null };
          return self.end(r, "done", null);
        }
        if (d?.user_info?.tenant_brand === "lark" && !switched && r.domain !== "lark") {
          switched = true;
          r.domain = "lark";
          continue;
        }
        const error = typeof d?.error === "string" ? d.error : "";
        if (error === "authorization_pending" || error === "") continue;
        if (error === "slow_down") every += 5;
        else if (error === "access_denied") return self.end(r, "denied", null);
        else if (error === "expired_token") return self.end(r, "expired", null);
        else return self.end(r, "failed", `${error} ${d?.error_description ?? ""}`.trim());
      }
    });
  }

  private end(r: Registration, state: RegistrationState, error: string | null) {
    r.state = state;
    r.error = error;
    log.info("feishu", "feishu registration ended", { id: r.id, state, ...(r.app ? { app: r.app.appId } : {}) });
    this.changed();
  }

  /// A finished one's app, taken for a connect: it is gone from the list then.
  take(id: string, by: string): Registration | null {
    const r = this.all.get(id);
    if (!r || r.by !== by || r.state !== "done" || r.app === null) return null;
    this.all.delete(id);
    this.changed();
    return r;
  }

  cancel(id: string, by: string): boolean {
    const r = this.all.get(id);
    if (!r || r.by !== by) return false;
    this.all.delete(id);
    this.changed();
    return true;
  }

  async close() {
    await Effect.runPromise(Scope.close(this.scope, Exit.void));
  }
}
