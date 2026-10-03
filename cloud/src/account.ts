import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";
import { noted, type SpanNotes } from "./tracing";
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
/** One Google account's sessions. What it may reach is the Directory's business. */
export class Account extends DurableObject<Env> {
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

  async create(identity: Identity, id: string, name: string): Promise<Response> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const now = nowSeconds();
      const data = this.data() ?? { ...identity, blocked: false, sessions: [] };
      if (data.sub !== identity.sub || !validId(id) || name.length > 80) return denied();
      if (data.blocked) return reply({ error: "account_blocked" }, 403);
      this.prune(data);
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
    // Its span says whose session it was and what became of the refresh (docs/telemetry.md, signing out).
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
      session.idle = Math.min(session.expires, nowSeconds() + SESSION_IDLE_SEC);
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

  /** Whether an access token's session is still live (not logged out, blocked or expired). */
  live(claims: Claims): boolean {
    return Boolean(this.session(this.data(), claims)) && this.charge();
  }

  async fetch(request: Request): Promise<Response> {
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
