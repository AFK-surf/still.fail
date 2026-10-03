// What differs per platform (host.rs), as Effects. The Node host (hosts/node.ts) implements it over fetch, the `ws`
// package, node:sqlite and files; the web's over fetch, WebSocket, IndexedDB and SQLite's WASM build on OPFS;
// Android's over the native shell (client/shell: reqwest, SQLite) through JSI. Tests use testing.ts. Waiting is not the host's: the core sleeps on Effect's Clock.
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

/// Keys `[from, to)` of one table of the former records store (the KV `records` table, IndexedDB `records`), in key
/// order: read once, when an account's database is first made (db/import.ts).
export type DbRange = { table: string; from: string; to: string };

/// A value SQLite takes and gives: no BigInt (integers stay within 2^53), text, bytes, null.
export type SqlValue = null | number | string | Uint8Array;
export type SqlRow = SqlValue[];

/// One SQLite database, used synchronously by the core's thread (db/account.ts): the host prepares each statement once and
/// keeps it. What fails throws a SqlError.
export interface Sql {
  /// Statements without parameters, one after another.
  exec(sql: string): void;
  /// One statement; how many rows it changed.
  run(sql: string, params?: readonly SqlValue[]): number;
  /// One statement's rows, each its columns in order.
  all(sql: string, params?: readonly SqlValue[]): SqlRow[];
  close(): void;
}

/// What SQLite said went wrong: `full` (no room left: the disk or the browser's quota), `busy` (another process holds
/// the database), or anything else.
export class SqlError extends Error {
  readonly kind: "full" | "busy" | "other";
  constructor(message: string, kind: "full" | "busy" | "other") {
    super(message);
    this.kind = kind;
  }
}

/// SQLite's error as a SqlError, by its result code or its words.
export function sqlError(e: unknown): SqlError {
  if (e instanceof SqlError) return e;
  const message = e instanceof Error ? e.message : String(e);
  const code = typeof (e as { errcode?: unknown })?.errcode === "number" ? (e as { errcode: number }).errcode : typeof (e as { resultCode?: unknown })?.resultCode === "number" ? (e as { resultCode: number }).resultCode : null;
  const primary = code === null ? null : code & 0xff;
  if (primary === 13 || /SQLITE_FULL|database or disk is full|quota/i.test(message)) return new SqlError(message, "full");
  if (primary === 5 || primary === 6 || /SQLITE_BUSY|SQLITE_LOCKED|database is locked/i.test(message)) return new SqlError(message, "busy");
  return new SqlError(message, "other");
}

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

  /// An account's SQLite database by name (`account-<sub>`), made empty if it is not there: one file per signed-in
  /// account (docs/core-db.md). Fails when it cannot be opened, or another process holds it (`SqlError` "busy").
  /// A host without one keeps nothing on the device.
  openDb?(name: string): Effect.Effect<Sql, HostError | SqlError>;
  /// A database in memory, for an account whose file cannot be opened (another process holds it): kept this run only
  /// (undefined while the host cannot make one yet).
  memoryDb?(): Sql | undefined;
  /// An account's database gone (it signed out).
  deleteDb?(name: string): Effect.Effect<void, HostError>;
  /// The former records store (before the databases per account), read once to bring what it kept over; left as it
  /// is, so an older core still finds it.
  legacyRead?(range: DbRange): Effect.Effect<[string, Uint8Array][], HostError>;

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

  /// A TCP connection to this machine's `port` (adbd, for the adb share: adb.ts), open while the scope is; only a
  /// native host has one.
  tcp?(port: number): Effect.Effect<TcpConnection, HostError, Scope.Scope>;
}

/// A TCP connection: what comes in, as it comes; what goes out; `end`, no more goes out.
export type TcpConnection = { read: Pull<Uint8Array>; write(bytes: Uint8Array): Effect.Effect<void, HostError>; end(): void };
