// The Comma account provider (contract v1 §4–5; account-provider.ts): the core's account is whoever the embedding
// app's Comma session is. The app gives either `bearer()` (its session token, e.g. from Electron's main-process
// credential lease) or `transport`, requests the app sends with its session itself, so this core never holds the
// token (Comma's client core, whose host puts the credential on); there is no sign-in here. What Comma answers is put in still.fail cloud's shapes, so the rest of the core
// keeps, shows and connects as it always does: `/v1/comma/stations/me` as `/v1/me`, a workspace's stations as
// `/v1/workspaces/:id`, its SSE events as `/v1/events` frames. Member credentials are kept and reused as still.fail
// cloud's are (sync/cloud.ts): a day, then asked again, the kept one serving until it expires while Comma is away.
import { Effect, Queue, type Scope } from "effect";
import type { AccountProvider, AccountProviderFactory, AccountSessions, Feature } from "./account-provider.ts";
import type { AccountView } from "./accounts.ts";
import { cloudError, readCredential, type Credential } from "./cloud.ts";
import { CoreError, HostError, asCoreError } from "./error.ts";
import type { Host, HttpRequest, HttpResponse, Pull, StreamResponse } from "./host.ts";
import { t } from "./i18n.ts";
import { SseParser } from "./station/sse.ts";
import { CLOUD, cloudWhat, type Status } from "./status.ts";
import { isObject, parseJson, toJsonBytes } from "./util.ts";

/// Requests to Comma that the app sends with its session (it adds the credential); plain promises, so an app that
/// bundles its own Effect can give them. A stream's `next` resolves null once it ended; `close` lets it go.
export type CommaTransport = {
  fetch(request: HttpRequest): Promise<HttpResponse>;
  fetchStream(request: HttpRequest): Promise<{
    status: number;
    headers: [string, string][];
    next(): Promise<Uint8Array | null>;
    close(): void;
  }>;
};

export type CommaOptions = {
  /// Comma's backend, e.g. https://api.cue.surf (no trailing slash).
  origin: string;
} & (
  | {
      /// The app's Comma session token, now; rejects when signed out.
      bearer: () => Promise<string>;
      transport?: undefined;
    }
  | {
      /// Requests the app sends with its session; the token never reaches this core.
      transport: CommaTransport;
      bearer?: undefined;
    }
);

/// Where the account is kept: who the session was last (so the core starts with it, and what it kept, offline).
export const COMMA_ACCOUNT_KEY = "comma/account";
/// A workspace-less account's events: a heartbeat this often, and anew this often (in case workspaces came).
const HEARTBEAT_MS = 25_000;
const IDLE_REOPEN_MS = 300_000;

const unsupported = (what: string) => new CoreError("unsupported", t("core-misc.comma.unsupported", { what }));

/// Comma's `/v1/comma/stations/me` in still.fail cloud's `/v1/me` shape.
export function meOf(answer: unknown): Record<string, unknown> | null {
  if (!isObject(answer) || !isObject(answer.user) || typeof answer.user.id !== "string") return null;
  const relays = Array.isArray(answer.relay_urls) ? answer.relay_urls.filter((u): u is string => typeof u === "string") : [];
  const workspaces = (Array.isArray(answer.workspaces) ? answer.workspaces : []).flatMap((w) =>
    isObject(w) && typeof w.id === "string" ? [{ id: w.id, name: typeof w.name === "string" ? w.name : "", role: typeof w.role === "string" ? w.role : "member" }] : [],
  );
  const user = answer.user;
  return {
    user: { id: user.id, email: typeof user.email === "string" ? user.email : "", name: typeof user.name === "string" ? user.name : "", picture: "" },
    workspaces,
    invitations: [],
    relay_urls: relays,
    ...(relays.length > 0 ? { relay_url: relays[0] } : {}),
  };
}

/// A workspace's stations (`GET /v1/comma/workspaces/:id/stations`) as still.fail cloud's workspace, named as `me` has it.
export function workspaceOf(id: string, answer: unknown, me: unknown): Record<string, unknown> {
  const listed = isObject(me) && Array.isArray(me.workspaces) ? me.workspaces.find((w) => isObject(w) && w.id === id) : undefined;
  const stations = (isObject(answer) && Array.isArray(answer.stations) ? answer.stations : []).filter((s) => isObject(s) && typeof s.id === "string");
  return {
    id,
    name: isObject(listed) && typeof listed.name === "string" ? listed.name : "",
    role: isObject(listed) && typeof listed.role === "string" ? listed.role : "member",
    stations,
    members: [],
    invitations: [],
  };
}

/// Comma's credential answer (relays as a list) as still.fail cloud's.
export function credentialOf(answer: unknown): Credential | string {
  if (!isObject(answer)) return readCredential(answer);
  const relays = Array.isArray(answer.relay_urls) ? answer.relay_urls.filter((u): u is string => typeof u === "string") : [];
  return readCredential({ ...answer, relay_url: typeof answer.relay_url === "string" ? answer.relay_url : (relays[0] ?? "") });
}

/// The one account: the host's session's user.
class CommaAccounts implements AccountSessions {
  #account: AccountView | null;
  #listeners: (() => void)[] = [];
  readonly #host: Host;
  readonly #bearer: () => Promise<string>;

  constructor(host: Host, bearer: () => Promise<string>, account: AccountView | null) {
    this.#host = host;
    this.#bearer = bearer;
    this.#account = account;
  }

  list(): AccountView[] {
    return this.#account ? [{ ...this.#account }] : [];
  }
  onChange(listener: () => void): void {
    this.#listeners.push(listener);
  }
  setTracer(): void {}
  refreshing(): number {
    return 0;
  }

  accessToken(sub: string): Effect.Effect<string, CoreError> {
    if (this.#account?.sub !== sub) return Effect.fail(CoreError.signedOut(t("core-logic.accounts.signed_out")));
    return Effect.tryPromise({ try: () => this.#bearer(), catch: () => CoreError.signedOut(t("core-logic.accounts.signed_out")) });
  }

  beginSignIn(): Effect.Effect<string, CoreError> {
    return Effect.fail(new CoreError("unsupported", t("core-misc.comma.sign_in")));
  }
  completeSignIn(): Effect.Effect<[AccountView, string], CoreError> {
    return Effect.fail(new CoreError("unsupported", t("core-misc.comma.sign_in")));
  }
  passwordSignIn(): Effect.Effect<AccountView, CoreError> {
    return Effect.fail(new CoreError("unsupported", t("core-misc.comma.sign_in")));
  }
  migrate(): Effect.Effect<void, CoreError> {
    return Effect.fail(new CoreError("unsupported", t("core-misc.comma.sign_in")));
  }

  /// Forgets the account here; the app's own session is the app's.
  signOut(sub: string): Effect.Effect<void, CoreError> {
    return this.#account?.sub === sub ? this.set(null) : Effect.void;
  }

  /// The session's user (as Comma says it), or none; told when it changed.
  set(account: AccountView | null): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (JSON.stringify(account) === JSON.stringify(this.#account)) return;
      this.#account = account;
      const written = yield* Effect.result(account === null ? this.#host.storageDelete(COMMA_ACCOUNT_KEY) : this.#host.storageSet(COMMA_ACCOUNT_KEY, toJsonBytes(account)));
      for (const listener of [...this.#listeners]) listener();
      if (written._tag === "Failure") return yield* Effect.fail(asCoreError(written.failure));
    });
  }
}

function readAccount(raw: unknown): AccountView | null {
  if (!isObject(raw) || typeof raw.sub !== "string" || typeof raw.email !== "string") return null;
  return { sub: raw.sub, email: raw.email, name: typeof raw.name === "string" ? raw.name : "", picture: "" };
}

/// The Comma provider for `Options.account`.
export const commaAccountProvider =
  (options: CommaOptions): AccountProviderFactory =>
  ({ host, status }) =>
    Effect.gen(function* () {
      const origin = options.origin.replace(/\/+$/, "");
      const kept = readAccount(parseJson(yield* Effect.orElseSucceed(host.storageGet(COMMA_ACCOUNT_KEY), () => null)));
      const transport = options.transport;
      // With a transport the app puts the session on; the "token" is only who it is for.
      const accounts = new CommaAccounts(host, options.transport ? () => Promise.resolve("") : options.bearer, kept);
      const toHost = (e: unknown) => (e instanceof HostError ? e : new HostError(e instanceof Error ? e.message : String(e)));
      /// One request: through the app's transport, or this host's fetch with the token on it.
      const send = (bearer: string, request: HttpRequest): Effect.Effect<HttpResponse, HostError> =>
        transport
          ? Effect.tryPromise({ try: () => transport.fetch(request), catch: toHost })
          : host.fetch({ ...request, headers: [["authorization", `Bearer ${bearer}`], ...request.headers] });
      const open = (bearer: string, request: HttpRequest): Effect.Effect<StreamResponse, HostError, Scope.Scope> =>
        transport
          ? Effect.map(
              Effect.acquireRelease(
                Effect.tryPromise({ try: () => transport.fetchStream(request), catch: toHost }),
                (stream) => Effect.sync(() => stream.close()),
              ),
              (stream): StreamResponse => ({
                status: stream.status,
                headers: stream.headers,
                body: { take: Effect.tryPromise({ try: () => stream.next(), catch: toHost }) },
              }),
            )
          : host.fetchStream({ ...request, headers: [["authorization", `Bearer ${bearer}`], ...request.headers] });
      /// The last `/v1/me` of each account, for naming its workspaces.
      const mes = new Map<string, Record<string, unknown>>();

      /// One call to Comma with the session: JSON, errors as still.fail cloud's codes are (cloud.ts `cloudError`).
      const call = (token: Effect.Effect<string, CoreError>, method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> =>
        Effect.gen(function* () {
          const bearer = yield* token;
          const headers: [string, string][] = [];
          if (body !== undefined && body !== null) headers.push(["content-type", "application/json"]);
          const waiting = status.begin(CLOUD, cloudWhat(method, path), false);
          const response = yield* send(bearer, { method, url: `${origin}${path}`, headers, body: body === undefined || body === null ? null : toJsonBytes(body) }).pipe(
            Effect.mapError(asCoreError),
            Effect.ensuring(Effect.sync(() => waiting.end())),
          );
          waiting.received(response.body.length);
          const parsed = parseJson(response.body);
          const data = parsed === undefined ? {} : parsed;
          if (response.status < 200 || response.status >= 300) {
            const code = isObject(data) && typeof data.error === "string" ? data.error : `http_${response.status}`;
            return yield* Effect.fail(response.status === 401 ? CoreError.signedOut(t("core-logic.accounts.signed_out")).withStatus(401) : cloudError(code, response.status));
          }
          return data as unknown;
        });
      const as = (sub: string, method: string, path: string, body: unknown = null) => call(accounts.accessToken(sub), method, path, body);

      /// Who the session is: the account it is, as it changes (another user signed in to the app: another account).
      const identify = (answer: Record<string, unknown>) => {
        const user = answer.user as { id: string; email: string; name: string };
        return accounts.set({ sub: user.id, email: user.email, name: user.name, picture: "" });
      };

      const me = (sub: string) =>
        Effect.gen(function* () {
          const answer = meOf(yield* as(sub, "GET", "/v1/comma/stations/me"));
          if (answer === null) return yield* Effect.fail(new CoreError("bad_response", t("core-misc.cloud.bad_response", { brand: "Comma", error: "no user" })));
          mes.set(sub, answer);
          if ((answer.user as { id: string }).id !== sub) yield* Effect.ignore(identify(answer));
          return answer as unknown;
        });

      const workspace = (sub: string, id: string) =>
        Effect.gen(function* () {
          const listed = yield* as(sub, "GET", `/v1/comma/workspaces/${id}/stations`);
          if (!mes.has(sub)) yield* Effect.ignore(me(sub));
          return workspaceOf(decodeURIComponent(id), listed, mes.get(sub)) as unknown;
        });

      const credential = (sub: string, ws: string, device: string): Effect.Effect<Credential, CoreError> =>
        Effect.flatMap(as(sub, "POST", `/v1/comma/workspaces/${encodeURIComponent(ws)}/station-credential`, { device }), (answer) => {
          const c = credentialOf(answer);
          return typeof c === "string" ? Effect.fail(new CoreError("bad_response", t("core-misc.cloud.bad_response", { brand: "Comma", error: c }))) : Effect.succeed(c);
        });

      /// still.fail cloud's account calls, as Comma has them.
      const request = (sub: string, method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
        const [bare] = path.split("?");
        let m: RegExpExecArray | null;
        if (method === "GET" && bare === "/v1/me") return me(sub);
        if (method === "GET" && (m = /^\/v1\/workspaces\/([^/]+)$/.exec(bare!))) return workspace(sub, m[1]!);
        if (method === "POST" && (m = /^\/v1\/workspaces\/([^/]+)\/credential$/.exec(bare!))) {
          const device = isObject(body) && typeof body.device === "string" ? body.device : "";
          return credential(sub, decodeURIComponent(m[1]!), device);
        }
        if (method === "POST" && (m = /^\/v1\/workspaces\/([^/]+)\/enrollments$/.exec(bare!))) return as(sub, "POST", `/v1/comma/workspaces/${m[1]}/stations/enrollments`, body ?? {});
        if ((method === "PATCH" || method === "DELETE") && (m = /^\/v1\/workspaces\/([^/]+)\/stations\/([^/]+)$/.exec(bare!))) {
          return as(sub, method, `/v1/comma/workspaces/${m[1]}/stations/${m[2]}`, method === "PATCH" ? body : null);
        }
        // Pushes reach Comma's people through the Comma app's own registration.
        if (bare === "/v1/push") return Effect.succeed({});
        return Effect.fail(unsupported(`${method} ${bare}`));
      };

      /// The account's events: each workspace's SSE, merged, as still.fail cloud frames them.
      const events = (sub: string): Effect.Effect<Pull<string>, CoreError, Scope.Scope> =>
        Effect.gen(function* () {
          const answer = yield* me(sub);
          const ids = (Array.isArray((answer as { workspaces?: unknown[] }).workspaces) ? (answer as { workspaces: { id: string }[] }).workspaces : []).map((w) => w.id);
          type Item = { frame: string } | { end: true } | { broke: HostError };
          const queue = yield* Queue.unbounded<Item>();
          const put = (item: Item) => Effect.asVoid(Queue.offer(queue, item));
          for (const id of ids) {
            const bearer = yield* accounts.accessToken(sub);
            const response = yield* open(bearer, { method: "GET", url: `${origin}/v1/comma/workspaces/${encodeURIComponent(id)}/stations/events`, headers: [["accept", "text/event-stream"]], body: null }).pipe(
              Effect.mapError(asCoreError),
            );
            if (response.status !== 200) {
              return yield* Effect.fail(response.status === 401 ? CoreError.signedOut(t("core-logic.accounts.signed_out")).withStatus(401) : cloudError(`http_${response.status}`, response.status));
            }
            const parser = new SseParser();
            const read: Effect.Effect<void> = Effect.gen(function* () {
              for (;;) {
                const chunk = yield* response.body.take;
                if (chunk === null) return yield* put({ end: true });
                const said = parser.feed(chunk);
                // A heartbeat (a comment) is the socket's pong: it is alive.
                if (said.length === 0) yield* put({ frame: "pong" });
                for (const [name, data] of said) {
                  const value = parseJson(new TextEncoder().encode(data));
                  if (name === "station" && isObject(value) && typeof value.id === "string" && typeof value.online === "boolean") {
                    yield* put({ frame: JSON.stringify({ type: "station", workspace: id, id: value.id, online: value.online }) });
                    // A name or version said with it: the workspace is read again for them.
                    if (typeof value.name === "string" || typeof value.version === "string") yield* put({ frame: JSON.stringify({ type: "workspace", id }) });
                  } else if (name === "stations") yield* put({ frame: JSON.stringify({ type: "workspace", id }) });
                }
              }
            }).pipe(Effect.catch((e: HostError) => put({ broke: e })));
            yield* Effect.forkScoped(read);
          }
          if (ids.length === 0) {
            // Nothing to follow: alive all the same, and opened anew now and then.
            const idle = Effect.gen(function* () {
              for (let waited = 0; waited < IDLE_REOPEN_MS; waited += HEARTBEAT_MS) {
                yield* Effect.sleep(HEARTBEAT_MS);
                yield* put({ frame: "pong" });
              }
              yield* put({ end: true });
            });
            yield* Effect.forkScoped(idle);
          }
          const pull: Pull<string> = {
            take: Effect.flatMap(Queue.take(queue), (item) => ("frame" in item ? Effect.succeed(item.frame) : "end" in item ? Effect.succeed(null) : Effect.fail(item.broke))),
          };
          return pull;
        });

      const supported: Feature[] = [];
      const provider: AccountProvider = {
        kind: "comma",
        accounts,
        supports: (feature) => supported.includes(feature),
        // Who the session is, read now: the account appears (or changes) once Comma says.
        start: () =>
          void Effect.runFork(
            Effect.gen(function* () {
              const bearer = options.bearer;
              const token = bearer
                ? Effect.tryPromise({ try: () => bearer(), catch: () => CoreError.signedOut(t("core-logic.accounts.signed_out")) })
                : Effect.succeed("");
              const answer = yield* Effect.result(Effect.map(call(token, "GET", "/v1/comma/stations/me", null), meOf));
              if (answer._tag === "Success" && answer.success !== null) yield* Effect.ignore(identify(answer.success));
              // Signed out of the app: what this device kept for the account goes with it.
              else if (answer._tag === "Failure" && answer.failure.code === "signed_out" && answer.failure.status === 401) yield* Effect.ignore(accounts.set(null));
            }),
          ),
        request: (sub, method, path, body) => request(sub, method, path, body),
        me: (sub) => me(sub),
        credential,
        events,
        pushKey: () => Effect.fail(unsupported("Web Push")),
        // Comma takes no client traces yet.
        traces: () => Effect.void,
      };
      return provider;
    });

