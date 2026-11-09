import { DurableObject } from "cloudflare:workers";
import { header } from "./compat";
import { EVENTS_PROTOCOLS, sockets, type Delivery } from "./directory";
import type { Env } from "./env";
import { noted, type SpanNotes } from "./tracing";
import { extendPersonal, type PersonalEntry } from "./personal-lock";
import { ACCESS_TTL_SEC, REFRESH_RETRY_SEC, SESSION_IDLE_SEC, SESSION_TTL_SEC, bearerToken, denied, digest, limited, nowSeconds, randomSecret, readJson, reply, seal, signToken, unseal, validId, verifyToken, type Claims, type Identity, type Tokens } from "./auth";

const LIMITS = { sessions: 16, requestsPerMinute: 120 };
type Retry = { hash: string; request: string; until: number; response: string };
/** Why a session ended, kept a while (the last 32) for the span of a refresh that finds it gone. */
type Ended = { id: string; at: number; why: "reused" | "logout" | "logout_all" | "removed" | "blocked" };
const ENDED_KEPT = 32;
type Session = {
  id: string;
  name: string;
  created: number;
  expires: number;
  idle: number;
  generation: number;
  refreshHash: string;
  retry?: Retry;
  /** When it last rotated (absent before it first did, and in sessions from before it was kept). */
  rotated?: number;
};
type AccountData = Identity & { blocked: boolean; sessions: Session[]; ended?: Ended[] };
/** What `live` says of an access token: its session is live, over its requests a minute, or not let in where it asks. */
export type Live = boolean | "limited" | "not_beta";
/**
 * One account's sessions, and its devices' `/v1/events` sockets (hibernatable, so idle ones cost nothing), on which
 * what the Directory tells it is sent (directory.ts #deliver). What it may reach is the Directory's business.
 */
export class Account extends DurableObject<Env> {
  /** How many times it was told whether it is let into the test channel while this object lives (`beta`). */
  #betaTold = 0;
  /** Events sockets opening now (the Directory counts them already: `events`), and what it was told for them meanwhile. */
  #opening = 0;
  #toldMeanwhile: string[] = [];

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
    if (sockets.where(env) === "primary") this.handBack();
  }

  /** Rolled back (directory.ts `sockets`): its devices' sockets closed as a restarting service's, to reconnect onto the Directory. */
  protected handBack(): void {
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.close(1012, "moved");
      } catch {
        // Closed already.
      }
    }
  }

  private data(): AccountData | undefined {
    return this.ctx.storage.kv.get<AccountData>("account");
  }
  private save(data: AccountData) {
    this.ctx.storage.kv.put("account", data);
  }
  private session(data: AccountData | undefined, claims: Claims): Session | undefined {
    const now = nowSeconds();
    return data && !data.blocked && data.sub === claims.sub ? data.sessions.find((s) => s.id === claims.sid && s.expires > now && s.idle > now) : undefined;
  }
  private charge(): boolean {
    const minute = Math.floor(nowSeconds() / 60);
    const old = this.ctx.storage.kv.get<{ minute: number; requests: number }>("quota");
    const quota = old?.minute === minute ? old : { minute, requests: 0 };
    if (quota.requests >= LIMITS.requestsPerMinute) return false;
    quota.requests++;
    this.ctx.storage.kv.put("quota", quota);
    return true;
  }

  /** The person's own lock (personal-lock.ts): kept whole, read and written by themselves. */
  personalLock(): PersonalEntry[] {
    return this.ctx.storage.kv.get<PersonalEntry[]>("personal-lock") ?? [];
  }

  /** Entries brought to it; the code it refuses them with, or the whole lock now. */
  appendPersonalLock(sub: string, entries: unknown): { entries: PersonalEntry[] } | { refused: string } {
    try {
      const next = extendPersonal(sub, this.personalLock(), entries);
      this.ctx.storage.kv.put("personal-lock", next);
      return { entries: next };
    } catch (error) {
      return { refused: (error as Error).message };
    }
  }

  /** A new access credential for the session. */
  private async access(data: AccountData, session: Session): Promise<{ access_token: string; expires_at: number }> {
    const now = nowSeconds();
    const expires = Math.min(now + ACCESS_TTL_SEC, session.expires, session.idle);
    const claims = { sub: data.sub, email: data.email, name: data.name ?? "", sid: session.id };
    return { access_token: await signToken(this.env, "access", claims, expires, now), expires_at: expires };
  }

  private async mint(data: AccountData, session: Session): Promise<Tokens> {
    const now = nowSeconds();
    const claims = { sub: data.sub, email: data.email, name: data.name ?? "", sid: session.id };
    const { access_token: access, expires_at: expires } = await this.access(data, session);
    const refresh = await signToken(
      this.env,
      "refresh",
      {
        ...claims,
        gen: session.generation,
        nonce: randomSecret(),
      },
      session.expires,
      now,
    );
    return {
      access_token: access,
      refresh_token: refresh,
      token_type: "Bearer",
      subject: data.sub,
      email: data.email,
      name: data.name ?? "",
      session_id: session.id,
      expires_at: expires,
      session_expires_at: session.expires,
      refresh_expires_at: session.idle,
    };
  }

  /** `shared`: an account several people sign in to (App Store review's, password.ts): a new session ends its oldest
   * when there are as many as it may have, rather than being refused. */
  async create(identity: Identity, id: string, name: string, shared = false): Promise<Response> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const now = nowSeconds();
      const data = this.data() ?? { ...identity, blocked: false, sessions: [] };
      if (data.sub !== identity.sub || !validId(id) || name.length > 80) return denied();
      if (data.blocked) return reply({ error: "account_blocked" }, 403);
      this.prune(data);
      if (shared)
        for (const old of [...data.sessions].sort((a, b) => a.created - b.created).slice(0, Math.max(0, data.sessions.length - LIMITS.sessions + 1)))
          await this.revoke(data, old.id, "removed");
      if (data.sessions.length >= LIMITS.sessions || !this.charge()) return limited();
      data.email = identity.email;
      data.name = identity.name;
      data.picture = identity.picture;
      await this.env.DIRECTORY.getByName("primary").upsertUser(identity);
      const session: Session = {
        id,
        name,
        created: now,
        expires: now + SESSION_TTL_SEC,
        idle: now + SESSION_IDLE_SEC,
        generation: 0,
        refreshHash: "",
      };
      const tokens = await this.mint(data, session);
      session.refreshHash = await digest(tokens.refresh_token);
      data.sessions.push(session);
      this.save(data);
      await this.schedule(data);
      return reply(tokens);
    });
  }

  async refresh(token: string, requestId: string): Promise<Response> {
    const claims = await verifyToken(this.env, token, "refresh");
    if (!claims || !validId(requestId)) return denied();
    const hash = await digest(token);
    // Its span says whose session it was and what became of the refresh (signing out).
    const notes: SpanNotes = { "stillfail.account": claims.sub, "stillfail.session": claims.sid, "stillfail.auth.presented_generation": claims.gen ?? -1 };
    const outcome = (response: Response, what: string, more: SpanNotes = {}) => noted(response, { ...notes, "stillfail.auth.outcome": what, ...more });
    return this.ctx.blockConcurrencyWhile(async () => {
      const data = this.data();
      const session = this.session(data, claims);
      if (!session || !data) return outcome(denied(), "no_session", this.gone(data, claims));
      if (!this.charge()) return outcome(limited(), "limited");
      const now = nowSeconds();
      const rotated: SpanNotes = session.rotated === undefined ? {} : { "stillfail.auth.rotated_ago": now - session.rotated };
      // The credential that just rotated, while what it rotated to has not been used (that would have rotated again and
      // replaced this retry): an interrupted rotation, or another client of the same device (a second tab's core, say)
      // racing this one. Both get the same new credentials; not reuse. Later than the retry window too: a phone that
      // slept with the answer on its way sends the same request again minutes later (2026-10-03, 142 s), and it never
      // got the credential it is now offered, so nobody else can have used it. Its access credential is made again.
      if (session.retry?.hash === hash) {
        const answer = await unseal(this.env, session.retry.response);
        if (session.retry.until > now) return outcome(reply(answer), "retried", rotated);
        return outcome(reply({ ...answer, ...(await this.access(data, session)) }), "retried_late", rotated);
      }
      if (session.refreshHash !== hash || session.generation !== claims.gen) {
        // A validly signed older refresh credential outside the exact retry is
        // evidence of reuse. Revoke the family, including its access credentials.
        await this.revoke(data, session.id, "reused");
        return outcome(reply({ error: "refresh_reused" }, 401), "reused", { "stillfail.auth.generation": session.generation, ...rotated });
      }
      session.generation++;
      session.rotated = now;
      // A session in use lives on: its lifetime counts from its last refresh, not from signing in, so one used every
      // day is never signed out in the middle of it (2026-10-31). Unused, it still ends after SESSION_IDLE_SEC.
      session.expires = now + SESSION_TTL_SEC;
      session.idle = Math.min(session.expires, now + SESSION_IDLE_SEC);
      const tokens = await this.mint(data, session);
      session.retry = {
        hash,
        request: requestId,
        until: nowSeconds() + REFRESH_RETRY_SEC,
        response: await seal(this.env, tokens, session.expires),
      };
      session.refreshHash = await digest(tokens.refresh_token);
      this.save(data);
      await this.schedule(data);
      return outcome(reply(tokens), "rotated", { "stillfail.auth.generation": session.generation, ...rotated });
    });
  }

  /** Why a refresh found no live session, for its span. */
  private gone(data: AccountData | undefined, claims: Claims): SpanNotes {
    if (!data) return { "stillfail.auth.gone": "no_account" };
    if (data.blocked) return { "stillfail.auth.gone": "blocked" };
    const now = nowSeconds();
    const ended = [...(data.ended ?? [])].reverse().find((e) => e.id === claims.sid);
    if (ended) return { "stillfail.auth.gone": ended.why, "stillfail.auth.ended_ago": now - ended.at };
    const session = data.sessions.find((s) => s.id === claims.sid);
    if (session) return { "stillfail.auth.gone": session.expires <= now ? "expired" : "idle" };
    // Pruned once it expired or idled out, or ended before endings were kept.
    return { "stillfail.auth.gone": "unknown" };
  }

  /** Ends one session, or all of them; the stations of the account's workspaces stop taking their credentials too. */
  private async revoke(data: AccountData, id: string | undefined, why: Ended["why"]) {
    const now = nowSeconds();
    const ending = id ? data.sessions.filter((s) => s.id === id) : data.sessions;
    data.ended = [...(data.ended ?? []), ...ending.map((s) => ({ id: s.id, at: now, why }))].slice(-ENDED_KEPT);
    data.sessions = id ? data.sessions.filter((s) => s.id !== id) : [];
    this.save(data);
    await this.env.DIRECTORY.getByName("primary").revokeSessions(data.sub, id ? [id] : null);
  }

  async logout(token: string, all: boolean): Promise<Response> {
    const claims = await verifyToken(this.env, token, "refresh");
    if (!claims) return denied();
    // Even a previously rotated credential may revoke its own session; it may
    // revoke other sessions only while it is the current refresh credential.
    const hash = await digest(token);
    const data = this.data();
    if (!data || data.sub !== claims.sub) return denied();
    const session = this.session(data, claims);
    if (all && (!session || session.refreshHash !== hash)) return denied();
    await this.revoke(data, all ? undefined : claims.sid, all ? "logout_all" : "logout");
    await this.schedule(data);
    return reply({ revoked: true, scope: all ? "account" : "session" });
  }

  /** The account deleted itself (DELETE /v1/me, once the Directory let it go): every session ends and nothing of it is kept. */
  async erase(): Promise<void> {
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
  }

  async administer(blocked: boolean): Promise<Response> {
    const data = this.data();
    if (!data) return reply({ error: "account_not_found" }, 404);
    data.blocked = blocked;
    if (blocked) await this.revoke(data, undefined, "blocked");
    else this.save(data);
    await this.schedule(data);
    return reply({ blocked: data.blocked });
  }

  private prune(data: AccountData) {
    const now = nowSeconds();
    data.sessions = data.sessions.filter((s) => s.expires > now && s.idle > now);
    this.save(data);
  }
  private async schedule(data: AccountData) {
    const deadlines = data.sessions.flatMap((s) => [s.expires, s.idle]);
    if (deadlines.length) await this.ctx.storage.setAlarm(Math.max(Date.now() + 1000, Math.min(...deadlines) * 1000));
    else await this.ctx.storage.deleteAlarm();
  }
  async alarm() {
    const data = this.data();
    if (data) {
      this.prune(data);
      await this.schedule(data);
    }
  }

  /**
   * Whether an access token's session is still live (not logged out, blocked or expired); `limited` when it is, but
   * over its requests a minute; on the test channel (`testChannel`), `not_beta` for an account not let in.
   */
  async live(claims: Claims, testChannel = false): Promise<Live> {
    if (!this.session(this.data(), claims)) return false;
    if (testChannel && !(await this.beta(claims.sub))) return "not_beta";
    return this.charge() ? true : "limited";
  }

  /** Whether it is let into the test channel: asked of the Directory once, then told as it changes (`deliver`). */
  private async beta(sub: string): Promise<boolean> {
    const kept = this.ctx.storage.kv.get<boolean>("beta");
    if (kept !== undefined) return kept;
    const told = this.#betaTold;
    const beta = await this.env.DIRECTORY.getByName("primary").isBeta(sub);
    if (told === this.#betaTold) this.ctx.storage.kv.put("beta", beta);
    return beta;
  }

  /** What the Directory tells it (directory.ts #deliver): sent on its devices' sockets; whether it holds any. */
  deliver(_sub: string, body: Delivery): { live: boolean } {
    if (body.beta !== undefined) {
      this.#betaTold++;
      this.ctx.storage.kv.put("beta", body.beta);
    }
    const open = this.ctx.getWebSockets().filter((ws) => ws.readyState === WebSocket.OPEN);
    for (const ws of open) this.#send(ws, body.frames ?? []);
    // One opening is told as it opens, and is a socket already to the Directory, which would else stop telling it.
    if (this.#opening > 0) this.#toldMeanwhile.push(...(body.frames ?? []));
    return { live: open.length > 0 || this.#opening > 0 };
  }

  #send(ws: WebSocket, frames: string[]): void {
    for (const frame of frames) {
      try {
        ws.send(frame);
      } catch {
        // Closing already; its device reconnects and reads it all again.
      }
    }
  }

  /**
   * A device's events socket, which the Worker checked the access token's signature of (its session, `x-stillfail-sub`
   * and `-sid`, is checked here; the subprotocol to select in `-protocol`; `-channel` beta on the test channel).
   * The Directory notes the device was seen, and tells this object what its devices are to hear from then on.
   */
  private async events(request: Request): Promise<Response> {
    const claims = { sub: header(request, "sub") ?? "", sid: header(request, "sid") ?? "" } as Claims;
    if (!this.session(this.data(), claims)) return denied();
    if (header(request, "channel") === "beta" && !(await this.beta(claims.sub))) return reply({ error: "not_beta" }, 403);
    if (!this.charge()) return limited();
    this.#opening++;
    let gen: number;
    try {
      gen = await this.opened(claims.sub);
    } catch (error) {
      if (--this.#opening === 0) this.#toldMeanwhile = [];
      throw error;
    }
    this.#opening--;
    // The latest opening's, whichever answer came last.
    this.ctx.storage.kv.put("events-gen", Math.max(gen, this.ctx.storage.kv.get<number>("events-gen") ?? 0));
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1]);
    pair[1].serializeAttachment({ sub: claims.sub });
    this.#send(pair[1], this.#toldMeanwhile);
    if (this.#opening === 0) this.#toldMeanwhile = [];
    return new Response(null, { status: 101, webSocket: pair[0], headers: { "sec-websocket-protocol": header(request, "protocol") ?? EVENTS_PROTOCOLS[0] } });
  }

  /** The Directory notes a socket opening here, and says which opening it is (a test makes its answer late). */
  protected async opened(sub: string): Promise<number> {
    return this.env.DIRECTORY.getByName("primary").seen(sub);
  }

  async webSocketClose(ws: WebSocket, code: number): Promise<void> {
    try {
      ws.close(code === 1005 || code === 1006 ? 1000 : code);
    } catch {
      // The runtime completed the close.
    }
    await this.#closed(ws);
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    await this.#closed(ws);
  }

  /** Its last socket gone: the Directory need not tell it what is for them (the latest opening's, so not one after). */
  async #closed(gone: WebSocket): Promise<void> {
    if (this.ctx.getWebSockets().some((ws) => ws !== gone && ws.readyState === WebSocket.OPEN)) return;
    const { sub } = gone.deserializeAttachment() as { sub: string };
    const gen = this.ctx.storage.kv.get<number>("events-gen");
    if (gen !== undefined) await this.env.DIRECTORY.getByName("primary").closed(sub, gen);
  }

  async fetch(request: Request): Promise<Response> {
    if (new URL(request.url).pathname === "/events") return this.events(request);
    const token = bearerToken(request);
    const claims = token ? await verifyToken(this.env, token, "access") : null;
    const data = this.data();
    if (!claims || !this.session(data, claims)) return denied();
    if (!this.charge()) return limited();
    const path = new URL(request.url).pathname;
    if (path === "/v1/auth/session" && request.method === "GET")
      return reply({
        subject: claims.sub,
        email: data!.email,
        name: data!.name ?? "",
        picture: data!.picture ?? "",
        session_id: claims.sid,
        expires_at: claims.exp,
      });
    if (path === "/v1/auth/sessions" && request.method === "GET")
      return reply({
        sessions: data!.sessions
          .filter((s) => s.expires > nowSeconds() && s.idle > nowSeconds())
          .map((s) => ({
            id: s.id,
            name: s.name,
            created_at: s.created,
            expires_at: s.expires,
            refresh_expires_at: s.idle,
            current: s.id === claims.sid,
          })),
      });
    const target = /^\/v1\/auth\/sessions\/([0-7][0-9A-HJKMNP-TV-Z]{25})$/.exec(path)?.[1];
    if (target && request.method === "DELETE") {
      await this.revoke(data!, target, "removed");
      await this.schedule(data!);
      return reply({ revoked: true });
    }
    return reply({ error: "not_found" }, 404);
  }
}
