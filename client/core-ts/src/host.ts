// What differs per platform (host.rs), as Effects. The Node host (hosts/node.ts) implements it over fetch, the `ws`
// package, node:sqlite and files; the web's over fetch, WebSocket and IndexedDB; Android's over OkHttp and SQLite
// through JSI. Tests use testing.ts. Waiting is not the host's: the core sleeps on Effect's Clock.
//
// What streams (a response's body, a WebSocket's frames) is a pull handle: `take` gives the next piece, null once it
// ended, failing when it broke. It lives in the Scope it was opened in: closing that scope closes it.
import type { Effect, Scope } from "effect";
import { HostError } from "./error.ts";
import type { CoreMessage, ClientId } from "./protocol.ts";
export { HostError };

export type HttpRequest = {
  method: string;
  /// Absolute URL.
  url: string;
  headers: [string, string][];
  body: Uint8Array | null;
};

export type HttpResponse = {
  status: number;
  headers: [string, string][];
  body: Uint8Array;
};

export function header(response: { headers: [string, string][] }, name: string): string | undefined {
  return response.headers.find(([k]) => k.toLowerCase() === name.toLowerCase())?.[1];
}

/// The next piece of what streams: null once it ended.
export type Pull<A> = { readonly take: Effect.Effect<A | null, HostError> };

/// A response whose body arrives in chunks.
export type StreamResponse = { status: number; headers: [string, string][]; body: Pull<Uint8Array> };

/// What a host sends on an open WebSocket to be answered `pong`, and how often.
export const SOCKET_PING = "ping";
export const SOCKET_PING_MS = 25_000;

/// Keys `[from, to)` of one table of the core's database, in key order.
export type DbRange = { table: string; from: string; to: string };

/// One change to the core's database; a batch of them is written at once or not at all.
export type DbOp = { put: { table: string; key: string; value: Uint8Array } } | { delete: { table: string; key: string } };

export interface Host {
  /// Where still.fail cloud is: the page's origin on the web, https://app.still.fail natively.
  cloudOrigin(): string;
  /// A beta app: its calls to still.fail cloud say so.
  beta(): boolean;
  /// On the test channel (youdid.wtf): what the core says names the product so. A beta app is.
  testChannel(): boolean;

  fetch(request: HttpRequest): Effect.Effect<HttpResponse, HostError>;
  /// A streamed response, open while the scope is.
  fetchStream(request: HttpRequest): Effect.Effect<StreamResponse, HostError, Scope.Scope>;
  /// A WebSocket that only listens (still.fail cloud's `/v1/events`), open while the scope is; succeeds once it is
  /// open. The host sends SOCKET_PING every SOCKET_PING_MS while it is.
  websocket(url: string, protocols: string[]): Effect.Effect<Pull<string>, HostError, Scope.Scope>;

  /// Small persistent values by key: accounts, the device key, preferences.
  storageGet(key: string): Effect.Effect<Uint8Array | null, HostError>;
  storageSet(key: string, value: Uint8Array): Effect.Effect<void, HostError>;
  storageDelete(key: string): Effect.Effect<void, HostError>;

  /// The core's database: records by table and key. A host without one keeps nothing.
  dbRead(range: DbRange): Effect.Effect<[string, Uint8Array][], HostError>;
  dbWrite(ops: DbOp[]): Effect.Effect<void, HostError>;

  /// Milliseconds since the Unix epoch.
  nowMs(): number;
  /// Milliseconds on a clock that only moves forward, for timing spans.
  monotonicMs(): number;
  /// The viewer's time zone at that moment: minutes to add to UTC to get local time.
  utcOffsetMin(atMs: number): number;
  /// The connections kept for requests are taken for gone: what is asked next goes on new ones.
  resetConnections(): void;

  randomBytes(buf: Uint8Array): void;

  /// Delivers a message to one connected UI.
  emit(client: ClientId, message: CoreMessage): void;
}
