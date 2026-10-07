// The accounts signed in on this device (accounts.rs). Each keeps its own still.fail cloud session: a short access
// token and a rotating refresh token. Tokens are refreshed at most once at a time per account (every caller waits on
// the same refresh).
//
// Wire: POST /v1/auth/token {code, code_verifier, redirect_uri}, POST /v1/auth/refresh (Bearer refresh)
// {request_id: ULID}, POST /v1/auth/logout (Bearer refresh) {all:false}; tokens answer {access_token, refresh_token,
// subject, email, name?, expires_at}. Sign-in starts at GET /v1/auth/google/start?state&code_challenge&…&name.
//
// Storage (the Rust core's, so either core reads the other's): `accounts` is a JSON array of StoredAccount
// (`access_expires` in epoch seconds), `login` the sign-in in progress.
import { Deferred, Effect } from "effect";
import { CoreError, HostError, asCoreError } from "./error.ts";
import type { Host, HttpResponse } from "./host.ts";
import { t } from "./i18n.ts";
import { Kind, type Tracer } from "./trace.ts";
import { HEDGE } from "./wake.ts";
import { base64url, isObject, parseJson, pointer, sha256, toJsonBytes, utf8 } from "./util.ts";

export const STORAGE_KEY = "accounts";
export const LOGIN_KEY = "login";
const APPLE_LOGIN_KEY = "login/apple";
const DELETED_KEY = "accounts/deleted";

export type StoredAccount = {
  sub: string;
  email: string;
  name: string;
  picture: string;
  access: string;
  refresh: string;
  /// Epoch seconds.
  access_expires: number;
};

/// What UIs see of an account: never its tokens.
export type AccountView = { sub: string; email: string; name: string; picture: string };

export function view(a: StoredAccount): AccountView {
  return { sub: a.sub, email: a.email, name: a.name, picture: a.picture };
}

type PendingLogin = { verifier: string; state: string; return_to: string; redirect_uri: string; epoch?: number };
type AppleAttempt = { attempt: string; nonce: string; state: string; epoch: number };

/// serde's reading of a StoredAccount: every field there, of its type (else the whole list is dropped, as
/// `unwrap_or_default` does in the Rust core).
function readStored(raw: unknown): StoredAccount[] | null {
  if (!Array.isArray(raw)) return null;
  const out: StoredAccount[] = [];
  for (const a of raw) {
    if (!isObject(a)) return null;
    const { sub, email, name, picture, access, refresh, access_expires } = a;
    if ([sub, email, name, picture, access, refresh].some((v) => typeof v !== "string") || typeof access_expires !== "number") return null;
    out.push({ sub, email, name, picture, access, refresh, access_expires } as StoredAccount);
  }
  return out;
}

function stored(a: StoredAccount): StoredAccount {
  return { sub: a.sub, email: a.email, name: a.name, picture: a.picture, access: a.access, refresh: a.refresh, access_expires: a.access_expires };
}

type Tokens = { access_token: string; refresh_token: string; subject: string; email: string; name?: string | null; expires_at: number };

function readTokens(raw: unknown): Tokens | null {
  if (!isObject(raw)) return null;
  const { access_token, refresh_token, subject, email, name, expires_at } = raw;
  if ([access_token, refresh_token, subject, email].some((v) => typeof v !== "string") || typeof expires_at !== "number") return null;
  if (name !== undefined && name !== null && typeof name !== "string") return null;
  return raw as unknown as Tokens;
}

export class Accounts {
  readonly #host: Host;
  #list: StoredAccount[];
  #listeners: (() => void)[] = [];
  /// The refresh under way per account: every caller waits on the one.
  readonly #refreshing = new Map<string, Deferred.Deferred<string, CoreError>>();
  #tracer: Tracer | null = null;
  /// Since when (monotonic ms) a refresh has had no answer.
  #unanswered: number | null = null;
  #epoch = 0;
  readonly #deleted = new Map<string, number>();

  private constructor(host: Host, list: StoredAccount[]) {
    this.#host = host;
    this.#list = list;
  }

  /// Loads the stored accounts.
  static load(host: Host): Effect.Effect<Accounts> {
    return Effect.gen(function* () {
      const bytes = yield* Effect.orElseSucceed(host.storageGet(STORAGE_KEY), () => null);
      const fence = parseJson(yield* Effect.orElseSucceed(host.storageGet(DELETED_KEY), () => null));
      const accounts = new Accounts(host, readStored(parseJson(bytes)) ?? []);
      if (isObject(fence)) for (const [sub, until] of Object.entries(fence)) {
        if (typeof until === "number" && Number.isFinite(until) && until > host.nowMs() / 1000) accounts.#deleted.set(sub, until);
      }
      accounts.#list = accounts.#list.filter((a) => !accounts.#deleted.has(a.sub));
      return accounts;
    });
  }

  setTracer(tracer: Tracer): void {
    this.#tracer = tracer;
  }

  list(): AccountView[] {
    return this.#list.map(view);
  }

  refreshing(): number {
    return this.#refreshing.size;
  }

  /// Called after every change to the list.
  onChange(listener: () => void): void {
    this.#listeners.push(listener);
  }

  /// Starts a sign-in: stores the PKCE verifier and state, returns the URL to open.
  beginSignIn(redirectUri: string, returnTo: string, deviceName: string): Effect.Effect<string, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const verifier = this.#secret();
      const state = this.#secret();
      const pending: PendingLogin = { verifier, state, return_to: returnTo, redirect_uri: redirectUri, epoch: this.#epoch };
      yield* Effect.mapError(this.#host.storageSet(LOGIN_KEY, toJsonBytes(pending)), asCoreError);
      const query = (
        [
          ["state", state],
          ["code_challenge", challenge(verifier)],
          ["code_challenge_method", "S256"],
          ["redirect_uri", redirectUri],
          ["name", deviceName],
        ] as [string, string][]
      )
        .map(([k, v]) => `${k}=${encodeComponent(v)}`)
        .join("&");
      return `${this.#host.cloudOrigin()}/v1/auth/google/start?${query}`;
    });
  }

  /// Finishes a sign-in from the callback's query string. Returns the account and where to go next.
  completeSignIn(query: string): Effect.Effect<[AccountView, string], CoreError> {
    return Effect.gen({ self: this }, function* () {
      const params = parseQuery(query);
      const param = (k: string) => params.find(([n]) => n === k)?.[1];
      // A login is good for one try, whatever its outcome.
      const raw = parseJson(yield* Effect.orElseSucceed(this.#host.storageGet(LOGIN_KEY), () => null));
      const pending = isObject(raw) && ["verifier", "state", "return_to", "redirect_uri"].every((k) => typeof raw[k] === "string") ? (raw as unknown as PendingLogin) : null;
      yield* Effect.ignore(this.#host.storageDelete(LOGIN_KEY));
      const error = param("error");
      if (error !== undefined && error !== "") {
        return yield* Effect.fail(error === "login_cancelled" ? new CoreError("login_cancelled", t("core-logic.accounts.login.cancelled")) : new CoreError("login_failed", t("core-logic.accounts.login.failed")));
      }
      if (!pending || param("state") !== pending.state) return yield* Effect.fail(new CoreError("login_state_mismatch", t("core-logic.accounts.login.state_mismatch")));
      const expired = () => new CoreError("login_expired", t("core-logic.accounts.login.expired"));
      const body = { code: param("code") ?? null, code_verifier: pending.verifier, redirect_uri: pending.redirect_uri };
      const response = yield* Effect.mapError(this.#post("/v1/auth/token", null, body, null), expired);
      if (!ok(response)) return yield* Effect.fail(expired().withStatus(response.status));
      const tokens = readTokens(parseJson(response.body));
      if (!tokens) return yield* Effect.fail(expired());
      if ((pending.epoch ?? 0) !== this.#epoch || this.#deleted.has(tokens.subject)) return yield* Effect.fail(new CoreError("login_superseded", "账号状态已改变，请重新登录"));
      const account: StoredAccount = {
        sub: tokens.subject,
        email: tokens.email,
        name: tokens.name ?? "",
        picture: "",
        access: tokens.access_token,
        refresh: tokens.refresh_token,
        access_expires: tokens.expires_at,
      };
      yield* this.#put(account);
      // The picture comes with the profile; fetched once, best effort.
      const picture = yield* this.#picture(account.access);
      if (picture !== null && (pending.epoch ?? 0) === this.#epoch && this.#get(account.sub)) {
        account.picture = picture;
        yield* Effect.ignore(this.#put(account));
      }
      const returnTo = pending.return_to === "" || pending.return_to.startsWith("/auth/") ? "/" : pending.return_to;
      return [view(account), returnTo] as [AccountView, string];
    });
  }

  appleBegin(): Effect.Effect<Omit<AppleAttempt, "epoch">, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const epoch = this.#epoch;
      const value = yield* Effect.flatMap(this.#post("/v1/auth/apple/challenge", null, {}, null), (r) => this.#authResponse(r)).pipe(Effect.mapError(asCoreError));
      if (!isObject(value) || ["attempt", "nonce", "state"].some((k) => typeof value[k] !== "string" || value[k].length !== 43)) {
        return yield* Effect.fail(new CoreError("apple_login_failed", "Apple 登录挑战无效"));
      }
      if (epoch !== this.#epoch) return yield* Effect.fail(new CoreError("login_superseded", "账号状态已改变"));
      const pending: AppleAttempt = { attempt: value.attempt as string, nonce: value.nonce as string, state: value.state as string, epoch };
      yield* Effect.mapError(this.#host.storageSet(APPLE_LOGIN_KEY, toJsonBytes(pending)), asCoreError);
      return { attempt: pending.attempt, nonce: pending.nonce, state: pending.state };
    });
  }

  appleComplete(attempt: string, identityToken: string, authorizationCode: string, name: string | null, state: string | null): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const pending = parseJson(yield* Effect.mapError(this.#host.storageGet(APPLE_LOGIN_KEY), asCoreError));
      if (!isObject(pending) || typeof pending.state !== "string") return yield* Effect.fail(new CoreError("login_expired", "请重新发起 Apple 登录"));
      if (pending.attempt !== attempt || pending.epoch !== this.#epoch || (state !== null && state !== pending.state)) {
        return yield* Effect.fail(new CoreError("login_state_mismatch", "Apple 登录状态不匹配"));
      }
      yield* Effect.mapError(this.#host.storageDelete(APPLE_LOGIN_KEY), asCoreError);
      const response = yield* Effect.mapError(this.#post("/v1/auth/apple/token", null, { attempt, identityToken, authorizationCode, name: name ?? "", state: pending.state }, null), asCoreError);
      const tokens = readTokens(yield* this.#authResponse(response));
      if (!tokens) return yield* Effect.fail(new CoreError("apple_login_failed", "Apple 登录回复无效"));
      if (pending.epoch !== this.#epoch || this.#deleted.has(tokens.subject)) return yield* Effect.fail(new CoreError("login_superseded", "账号状态已改变，请重新登录"));
      const account: StoredAccount = { sub: tokens.subject, email: tokens.email, name: tokens.name ?? "", picture: "", access: tokens.access_token, refresh: tokens.refresh_token, access_expires: tokens.expires_at };
      yield* this.#put(account);
      return { account: view(account), accounts: this.list() };
    });
  }

  deletionSummary(sub: string): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const access = yield* this.accessToken(sub);
      return yield* this.#authResponse(yield* Effect.mapError(this.#post("/v1/auth/deletion-summary", access, {}, null), asCoreError));
    });
  }

  deleteAccount(sub: string): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const access = yield* this.accessToken(sub);
      const receipt = yield* this.#authResponse(yield* Effect.mapError(this.#post("/v1/auth/delete-account", access, {}, null), asCoreError));
      if (!isObject(receipt) || receipt.deleted !== true || receipt.state !== "completed" || receipt.account !== sub ||
          typeof receipt.fence_expires_at !== "number" || !Number.isFinite(receipt.fence_expires_at) || receipt.fence_expires_at <= this.#host.nowMs() / 1000) {
        return yield* Effect.fail(new CoreError("deletion_incomplete", "服务器尚未完成账号删除"));
      }
      this.#epoch++;
      this.#deleted.set(sub, receipt.fence_expires_at);
      yield* Effect.mapError(this.#host.storageSet(DELETED_KEY, toJsonBytes(Object.fromEntries(this.#deleted))), asCoreError);
      yield* Effect.ignore(this.#host.storageDelete(LOGIN_KEY));
      yield* Effect.ignore(this.#host.storageDelete(APPLE_LOGIN_KEY));
      yield* this.#forget(sub);
      return receipt;
    });
  }

  #authResponse(response: HttpResponse): Effect.Effect<unknown, CoreError> {
    const value = parseJson(response.body);
    if (ok(response)) return Effect.succeed(value);
    const raw = isObject(value) ? value.error : undefined;
    const code = typeof raw === "string" && /^[a-z_]{1,80}$/.test(raw) ? raw : "auth_failed";
    const messages: Record<string, string> = {
      apple_not_configured: "Apple 登录尚未配置，请使用 Google 登录",
      deletion_coverage_incomplete: "远端个人数据删除尚未支持，账号未被删除",
      reauth_required: "请重新登录后再删除账号",
      last_owner: "请先转移所有权或单独删除工作区",
    };
    return Effect.fail(new CoreError(code, messages[code] ?? "请求未完成，请重试", response.status));
  }

  /// A usable access token, refreshing it when it expires within a minute (once at a time per account). A refused
  /// refresh forgets the account.
  accessToken(sub: string): Effect.Effect<string, CoreError> {
    return Effect.suspend(() => {
      const now = this.#host.nowMs() / 1000;
      const a = this.#get(sub);
      if (!a) return Effect.fail(CoreError.signedOut(t("core-logic.accounts.signed_out")));
      if (a.access_expires - 60 > now) return Effect.succeed(a.access);
      const existing = this.#refreshing.get(sub);
      if (existing) return Deferred.await(existing);
      const done = Deferred.makeUnsafe<string, CoreError>();
      this.#refreshing.set(sub, done);
      // The refresh runs to its end whoever waits (it rotates the session): a fiber of its own.
      Effect.runFork(
        this.#refresh(sub).pipe(
          Effect.exit,
          Effect.flatMap((exit) =>
            Effect.sync(() => {
              this.#refreshing.delete(sub);
              Deferred.doneUnsafe(done, exit);
            }),
          ),
        ),
      );
      return Deferred.await(done);
    });
  }

  signOut(sub: string): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const account = this.#get(sub);
      if (account) yield* Effect.ignore(this.#post("/v1/auth/logout", account.refresh, { all: false }, null));
      yield* this.#forget(sub);
    });
  }

  /// Takes over the accounts a page kept before the core existed (camelCase fields). An account already here is
  /// replaced only by a newer session.
  migrate(accounts: unknown): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      let raw = accounts;
      if (typeof raw === "string") {
        const parsed = parseJson(raw);
        if (parsed === undefined) return yield* Effect.fail(CoreError.invalid(t("core-logic.accounts.invalid_json")));
        raw = parsed;
      } else if (raw === null) return;
      if (!Array.isArray(raw)) return yield* Effect.fail(CoreError.invalid(t("core-logic.accounts.not_array")));
      let changed = false;
      for (const item of raw) {
        if (!isObject(item)) continue;
        const { sub, email, access, refresh, accessExpires } = item;
        if (typeof sub !== "string" || typeof email !== "string" || typeof access !== "string" || typeof refresh !== "string" || typeof accessExpires !== "number") continue;
        if (this.#deleted.has(sub)) continue;
        const name = item.name === undefined ? "" : item.name;
        const picture = item.picture === undefined ? "" : item.picture;
        if (typeof name !== "string" || typeof picture !== "string") continue;
        const account: StoredAccount = { sub, email, name, picture, access, refresh, access_expires: accessExpires };
        const existing = this.#list.findIndex((a) => a.sub === sub);
        if (existing < 0) this.#list.push(account);
        else if (this.#list[existing].access_expires < accessExpires) this.#list[existing] = account;
        changed = true;
      }
      if (changed) yield* this.#save();
    });
  }

  /// Takes the stored credentials of `sub` when another core wrote newer ones; their access token when still good.
  #adoptStored(sub: string): Effect.Effect<string | null> {
    return Effect.map(Effect.orElseSucceed(this.#host.storageGet(STORAGE_KEY), () => null), (bytes) => {
      const theirs = readStored(parseJson(bytes))?.find((a) => a.sub === sub);
      const ours = this.#get(sub);
      if (!theirs || !ours || this.#deleted.has(sub) || theirs.refresh === ours.refresh) return null;
      const good = theirs.access_expires - 60 > this.#host.nowMs() / 1000;
      const i = this.#list.findIndex((a) => a.sub === sub);
      if (i >= 0) this.#list[i] = theirs;
      return good ? theirs.access : null;
    });
  }

  #get(sub: string): StoredAccount | undefined {
    const a = this.#list.find((a) => a.sub === sub);
    return a ? { ...a } : undefined;
  }

  /// Tests: the stored account itself.
  stored(sub: string): StoredAccount | undefined {
    return this.#get(sub);
  }

  #refresh(sub: string): Effect.Effect<string, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const epoch = this.#epoch;
      // Another core on the same storage may have refreshed already: its credentials are the current ones.
      const adopted = yield* this.#adoptStored(sub);
      if (adopted !== null) return adopted;
      const account = this.#get(sub);
      if (!account) return yield* Effect.fail(CoreError.signedOut(t("core-logic.accounts.signed_out")));
      const body = { request_id: ulid(this.#host) };
      // Every refresh is a trace of its own, recorded whatever the sampling.
      const span = this.#tracer?.always("auth.refresh", Kind.Client) ?? null;
      if (span && this.#unanswered !== null) span.set("stillfail.auth.unanswered_ago_ms", Math.trunc(this.#host.monotonicMs() - this.#unanswered));
      const traceparent = span ? span.context.traceparent() : null;
      this.#unanswered = this.#host.monotonicMs();
      const sent = yield* Effect.result(Effect.mapError(this.#post("/v1/auth/refresh", account.refresh, body, traceparent), asCoreError));
      if (sent._tag === "Failure") {
        if (span) {
          span.set("error.type", sent.failure.code);
          span.fail();
          span.end();
        }
        return yield* Effect.fail(sent.failure);
      }
      const response = sent.success;
      this.#unanswered = null;
      if (span) {
        span.set("http.response.status_code", response.status);
        if (!ok(response)) {
          const code = parseJson(response.body);
          span.set("error.type", isObject(code) && typeof code.error === "string" ? code.error : `http_${response.status}`);
          span.fail();
        }
        span.end();
      }
      if (response.status === 401) {
        yield* Effect.ignore(this.#forget(sub));
        return yield* Effect.fail(CoreError.signedOut(t("core-logic.accounts.session_expired", { email: account.email })).withStatus(401));
      }
      if (!ok(response)) return yield* Effect.fail(new CoreError("refresh_failed", t("core-logic.accounts.refresh_failed", { status: response.status }), response.status));
      const tokens = readTokens(parseJson(response.body));
      if (!tokens) return yield* Effect.fail(new CoreError("refresh_failed", t("core-logic.accounts.refresh_unreadable")));
      if (epoch !== this.#epoch || this.#deleted.has(sub) || !this.#get(sub)) return yield* Effect.fail(CoreError.signedOut(t("core-logic.accounts.signed_out")));
      const name = tokens.name ? tokens.name : account.name;
      // The new tokens are good even if they cannot be written down.
      yield* Effect.ignore(this.#put({ ...account, access: tokens.access_token, refresh: tokens.refresh_token, access_expires: tokens.expires_at, name }));
      return tokens.access_token;
    });
  }

  #picture(access: string): Effect.Effect<string | null> {
    return this.#host.fetch({ method: "GET", url: `${this.#host.cloudOrigin()}/v1/me`, headers: [["authorization", `Bearer ${access}`]], body: null }).pipe(
      Effect.map((response) => {
        const picture = pointer(parseJson(response.body), "/user/picture");
        return typeof picture === "string" && picture !== "" ? picture : null;
      }),
      Effect.orElseSucceed(() => null),
    );
  }

  #post(path: string, bearer: string | null, body: unknown, traceparent: string | null): Effect.Effect<HttpResponse, HostError> {
    const headers: [string, string][] = [["content-type", "application/json"]];
    if (traceparent !== null) headers.push(["traceparent", traceparent]);
    if (bearer !== null) headers.push(["authorization", `Bearer ${bearer}`]);
    // A refresh asked twice with its one `request_id` is answered the same: it may go again beside one gone quiet.
    if (path === "/v1/auth/refresh") headers.push([HEDGE, "1"]);
    return this.#host.fetch({ method: "POST", url: `${this.#host.cloudOrigin()}${path}`, headers, body: toJsonBytes(body) });
  }

  /// Adds or replaces an account, keeping its place in the list.
  #put(account: StoredAccount): Effect.Effect<void, CoreError> {
    return Effect.suspend(() => {
      if (this.#deleted.has(account.sub)) return Effect.fail(CoreError.signedOut(t("core-logic.accounts.signed_out")));
      const i = this.#list.findIndex((a) => a.sub === account.sub);
      if (i >= 0) this.#list[i] = stored(account);
      else this.#list.push(stored(account));
      return this.#save();
    });
  }

  #forget(sub: string): Effect.Effect<void, CoreError> {
    return Effect.suspend(() => {
      const before = this.#list.length;
      this.#list = this.#list.filter((a) => a.sub !== sub);
      return this.#list.length === before ? Effect.void : this.#save();
    });
  }

  /// Writes the list and tells the listeners. Memory is updated first, so a failed write still changes this session.
  #save(): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const written = yield* Effect.result(this.#host.storageSet(STORAGE_KEY, toJsonBytes(this.#list)));
      for (const listener of [...this.#listeners]) listener();
      if (written._tag === "Failure") return yield* Effect.fail(asCoreError(written.failure));
    });
  }

  #secret(): string {
    const bytes = new Uint8Array(32);
    this.#host.randomBytes(bytes);
    return base64url(bytes);
  }
}

function ok(response: HttpResponse): boolean {
  return response.status >= 200 && response.status < 300;
}

/// PKCE S256: base64url(sha256(verifier)).
export function challenge(verifier: string): string {
  return base64url(sha256(utf8(verifier)));
}

/// A ULID, which still.fail cloud wants as the id of each refresh request.
export function ulid(host: Host): string {
  const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
  let time = Math.trunc(host.nowMs());
  const out: string[] = new Array(26);
  for (let i = 9; i >= 0; i--) {
    out[i] = ALPHABET[time % 32];
    time = Math.floor(time / 32);
  }
  const random = new Uint8Array(16);
  host.randomBytes(random);
  for (let i = 0; i < 16; i++) out[10 + i] = ALPHABET[random[i] % 32];
  return out.join("");
}

/// Percent-encodes everything but RFC 3986 unreserved characters.
export function encodeComponent(text: string): string {
  let out = "";
  for (const b of utf8(text)) {
    const c = String.fromCharCode(b);
    if (/[A-Za-z0-9\-_.~]/.test(c)) out += c;
    else out += `%${b.toString(16).toUpperCase().padStart(2, "0")}`;
  }
  return out;
}

export function decodeComponent(text: string): string {
  const bytes = utf8(text);
  const out: number[] = [];
  for (let i = 0; i < bytes.length; i++) {
    const b = bytes[i];
    if (b === 0x2b) out.push(0x20);
    else if (b === 0x25 && i + 2 < bytes.length) {
      const h = String.fromCharCode(bytes[i + 1], bytes[i + 2]);
      if (/^[0-9A-Fa-f]{2}$/.test(h)) {
        out.push(parseInt(h, 16));
        i += 2;
      } else out.push(0x25);
    } else out.push(b);
  }
  return new TextDecoder().decode(new Uint8Array(out));
}

/// A query string (with or without its leading `?`) as name/value pairs.
export function parseQuery(query: string): [string, string][] {
  return query
    .replace(/^\?+/, "")
    .split("&")
    .filter((p) => p !== "")
    .map((p) => {
      const at = p.indexOf("=");
      return at >= 0 ? [decodeComponent(p.slice(0, at)), decodeComponent(p.slice(at + 1))] : [decodeComponent(p), ""];
    });
}
