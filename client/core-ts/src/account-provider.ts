// Who the core's accounts are with: the control plane that signs them in (or is told who they are), lists their
// workspaces and stations, issues their member credentials and tells what changes (docs/core-ts.md, "Account providers
// and embedding"). still.fail cloud's is the default and what the core always did (Google PKCE, rotating refresh
// tokens, /v1/me, /v1/workspaces/:ws/credential, /v1/events, push, the workspace operations); Comma's (comma.ts) is
// given its session by the app that embeds the core. Everything the rest of the core keeps is in still.fail cloud's
// shapes (`/v1/me`, a workspace, its events), whichever provider answers.
import { Effect, type Scope } from "effect";
import { Accounts, type AccountView } from "./accounts.ts";
import * as brand from "./brand.ts";
import { Cloud, type Credential } from "./cloud.ts";
import { CoreError, asCoreError } from "./error.ts";
import type { Host, Pull } from "./host.ts";
import { t } from "./i18n.ts";
import type { Status } from "./status.ts";
import type { SpanContext, Tracer } from "./trace.ts";
import { isObject, parseJson } from "./util.ts";

/// The accounts signed in on this device, as a provider keeps them: never their tokens.
export interface AccountSessions {
  list(): AccountView[];
  /// Called after every change to the list.
  onChange(listener: () => void): void;
  /// What authorizes a call as `sub` now (a bearer token).
  accessToken(sub: string): Effect.Effect<string, CoreError>;
  beginSignIn(redirectUri: string, returnTo: string, deviceName: string): Effect.Effect<string, CoreError>;
  completeSignIn(query: string): Effect.Effect<[AccountView, string], CoreError>;
  passwordSignIn(email: string, password: string, deviceName: string): Effect.Effect<AccountView, CoreError>;
  signOut(sub: string): Effect.Effect<void, CoreError>;
  /// Accounts kept before the core (a page's, a dev cloud's).
  migrate(accounts: unknown): Effect.Effect<void, CoreError>;
  setTracer(tracer: Tracer): void;
  /// Refreshes under way.
  refreshing(): number;
}

/// What a provider can do besides the accounts, workspaces, stations and credentials every provider has.
export type Feature = "loginSessions" | "admin" | "invitations" | "push" | "signIn";

export interface AccountProvider {
  readonly kind: "stillfail" | "comma";
  readonly accounts: AccountSessions;
  supports(feature: Feature): boolean;
  /// Starts what it keeps by itself (Comma: who the host's session is).
  start(): void;
  /// One call as `sub`, in still.fail cloud's terms (`GET /v1/me`, `POST /v1/workspaces/:ws/enrollments`, …): the
  /// account topics and operations (ops.ts) go through here. What the provider has no such thing for fails
  /// `unsupported`.
  request(sub: string, method: string, path: string, body: unknown, ctx?: SpanContext | null): Effect.Effect<unknown, CoreError>;
  /// `GET /v1/me`: {user, workspaces, invitations, relay_urls}.
  me(sub: string, ctx?: SpanContext | null): Effect.Effect<unknown, CoreError>;
  /// This device's member credential for a workspace.
  credential(sub: string, workspace: string, device: string): Effect.Effect<Credential, CoreError>;
  /// The account's events, as still.fail cloud's `/v1/events` frames them (`pong`, `{"type":"workspaces"}`,
  /// `{"type":"workspace","id"}`, `{"type":"station","workspace","id","online"}`), open while the scope is.
  events(sub: string): Effect.Effect<Pull<string>, CoreError, Scope.Scope>;
  /// The Web Push key, where pushes are the core's to register.
  pushKey(): Effect.Effect<{ vapid: string }, CoreError>;
  /// A batch of the core's spans (OTLP JSON) as `sub`; dropped where the provider takes none.
  traces(sub: string, body: Uint8Array): Effect.Effect<void, CoreError>;
}

/// What a provider is made with.
export type ProviderEnv = { host: Host; tracer: Tracer; status: Status };

/// How a core gets its provider (Options.account): still.fail cloud's unless the embedding app gives another.
export type AccountProviderFactory = (env: ProviderEnv) => Effect.Effect<AccountProvider>;

/// The subprotocol still.fail cloud's `/v1/events` answers with; the token travels as a second one.
export const EVENTS_PROTOCOL = "stillfail-events";

/// still.fail cloud's: as the core always was.
export const stillfailAccountProvider: AccountProviderFactory = ({ host, tracer, status }) =>
  Effect.map(Accounts.load(host), (accounts) => {
    accounts.setTracer(tracer);
    const cloud = new Cloud(host, accounts, tracer, status);
    const provider: AccountProvider = {
      kind: "stillfail",
      accounts,
      supports: () => true,
      start: () => {},
      request: (sub, method, path, body, ctx) => cloud.request(sub, method, path, body, ctx),
      me: (sub, ctx) => cloud.me(sub, ctx),
      credential: (sub, workspace, device) => cloud.credential(sub, workspace, device),
      events: (sub) =>
        Effect.gen(function* () {
          const token = yield* accounts.accessToken(sub);
          const origin = host.cloudOrigin();
          const url = origin.startsWith("https://") ? `wss://${origin.slice(8)}/v1/events` : `ws://${origin.startsWith("http://") ? origin.slice(7) : origin}/v1/events`;
          return yield* Effect.mapError(host.websocket(url, [EVENTS_PROTOCOL, `stillfail-token.${token}`]), asCoreError);
        }),
      pushKey: () =>
        Effect.gen(function* () {
          const response = yield* Effect.mapError(host.fetch({ method: "GET", url: `${host.cloudOrigin()}/v1/push/key`, headers: [], body: null }), asCoreError);
          const data = parseJson(response.body);
          const vapid = isObject(data) ? data.vapid : undefined;
          if (typeof vapid === "string" && response.status === 200) return { vapid };
          return yield* Effect.fail(new CoreError("push_unavailable", t("core-misc.call.push_unavailable", { brand: brand.name() })));
        }),
      traces: (sub, body) => cloud.traces(sub, body),
    };
    return provider;
  });
