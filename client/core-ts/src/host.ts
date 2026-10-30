// What differs per platform (host.rs), as Effects. The Node host (hosts/node.ts) implements it over fetch, the `ws`
// package, node:sqlite and files; the web's over fetch, WebSocket, IndexedDB and SQLite's WASM build on OPFS;
// Android's over the native shell (client/shell: reqwest, SQLite) through JSI. Tests use testing.ts. Waiting is not the host's: the core sleeps on Effect's Clock.
//
// What streams (a response's body, a WebSocket's frames) is a pull handle: `take` gives the next piece, null once it
// ended, failing when it broke. It lives in the Scope it was opened in: closing that scope closes it.
import type { Recorder } from "./record.ts";
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

/// A zstd stream being taken apart (Host.unzstd): each piece pushed in turn, what it makes; `whole`, whether what
/// it took so far ends a frame (a reply that must end with one: checked after its last piece).
export type Unzstd = { push(piece: Uint8Array): Effect.Effect<{ bytes: Uint8Array; whole: boolean }, HostError> };

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
/// the database), `corrupt` (its file is damaged, or no database at all), or anything else.
export class SqlError extends Error {
  readonly kind: "full" | "busy" | "corrupt" | "other";
  constructor(message: string, kind: "full" | "busy" | "corrupt" | "other") {
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
  if (primary === 11 || primary === 26 || /SQLITE_CORRUPT|SQLITE_NOTADB|disk image is malformed|file is not a database/i.test(message)) return new SqlError(message, "corrupt");
  return new SqlError(message, "other");
}

export interface Host {
  /// Where still.fail cloud is: the page's origin on the web, https://app.still.fail natively.
  cloudOrigin(): string;
  /// A beta app: its calls to still.fail cloud say so.
  beta(): boolean;
  /// On the test channel (youdid.wtf): what the core says names the product so, in still.fail's own app (brand.ts). A
  /// beta app is.
  testChannel(): boolean;

  fetch(request: HttpRequest): Effect.Effect<HttpResponse, HostError>;
  /// A streamed response, open while the scope is.
  fetchStream(request: HttpRequest): Effect.Effect<StreamResponse, HostError, Scope.Scope>;
  /// A WebSocket that only listens (still.fail cloud's `/v1/events`), open while the scope is; succeeds once it is
  /// open. The host sends SOCKET_PING every SOCKET_PING_MS while it is.
  websocket(url: string, protocols: string[]): Effect.Effect<Pull<string>, HostError, Scope.Scope>;

  /// Names in the order people read them in their language, as a file browser lists them (the system's collation:
  /// case and accents aside, numbers by value; 中文 by pinyin): each one's place, equal ones the same. None, or null for
  /// what the system cannot: the core orders them by hand (drive-browse.ts).
  collate?(names: readonly string[]): number[] | null;

  /// An Ed25519 seed's public key and its signature of `message`, where the host has a way of its own (a native app's
  /// shell). None, or null for a host that cannot: the core's own, noble's, in JS, which in Hermes (no JIT) took ~8 ms
  /// a signature and longer the first time, a lock claim's for each workspace and endpoint as the core connects
  /// (lock.ts lockClaim), all of it on the core's thread ahead of what the UI asked for.
  ed25519Sign?(seed: Uint8Array, message: Uint8Array): { publicKey: Uint8Array; signature: Uint8Array } | null;

  /// A zstd stream taken apart by the host, open while the scope is, where it has a way of its own (a native app's
  /// shell: libzstd). None: the core's own, fzstd, in JS, which Hermes (no JIT) runs at some 10 MB of what it makes a
  /// second on an M2 Max, a tenth of V8's and far under native (bench/zstd-read.ts): what a station sends, compressed,
  /// is taken apart on the core's thread, slower again on a phone holding back its clock.
  unzstd?(): Effect.Effect<Unzstd, HostError, Scope.Scope>;

  /// Small persistent values by key: accounts, the device key, preferences.
  storageGet(key: string): Effect.Effect<Uint8Array | null, HostError>;
  storageSet(key: string, value: Uint8Array): Effect.Effect<void, HostError>;
  storageDelete(key: string): Effect.Effect<void, HostError>;
  /// Where the value kept under `key` is, as a file of this device's: for what the app reads there itself (a face's
  /// file given to the system by its path, not carried whole). Null while none is kept; none on a host whose values are
  /// not files (a web page).
  storagePath?(key: string): string | null;
  /// Bytes `start` to `end` of a file the app saved where the person keeps files (`at`, as the system named it once it
  /// was saved: a path, a content address); null when it is no longer there or cannot be read. A host without one (the
  /// web: what the browser saved is out of the page's reach) keeps the device's copy of a download in its cache.
  savedRead?(at: string, start: number, end: number): Effect.Effect<Uint8Array | null, HostError>;

  /// Values the system keeps sealed (docs/vault.md, "设备上的钥匙"): an app's only (Android's Keystore; the Apple
  /// Keychain; Windows' DPAPI; the Electron app's safeStorage); a web page has none. `user: true`: reading it takes the
  /// person (biometrics or the device's credential: on Apple's systems Touch ID, Face ID or the device's password; the
  /// Electron app's Touch ID on a Mac that has it), `reason` said in the prompt; `user: false`: sealed at rest, read
  /// without asking. A value is read as it was kept: asked with the other `user`, it fails or is none. The host's errors
  /// say `user_cancelled` (the person said no), `no_device_lock` (no screen lock, so nothing can need the person: keeping
  /// a `user` value fails so too), `not_in_front` (no screen to ask on) or `key_invalidated` (Android: the screen lock
  /// was taken off since) as their message (CoreError.refused says them in words).
  secureGet?(key: string, opts: { user: boolean; reason?: string }): Effect.Effect<Uint8Array | null, HostError>;
  secureSet?(key: string, value: Uint8Array, opts: { user: boolean }): Effect.Effect<void, HostError>;
  secureDelete?(key: string): Effect.Effect<void, HostError>;
  /// The person asked to say yes, as reading a `user: true` value asks them, `reason` in the prompt: before what they
  /// should mean (turning the workspace lock off). Succeeds at once where nothing can ask (Windows, Linux, the
  /// Electron app on a Mac without Touch ID); fails as `secureGet` does (`user_cancelled`, `no_device_lock`, `not_in_front`).
  secureAsk?(reason: string): Effect.Effect<void, HostError>;

  /// An account's SQLite database by name (`account-<sub>`), made empty if it is not there: one file per signed-in
  /// account (docs/core-db.md). Fails when it cannot be opened, or another process holds it (`SqlError` "busy").
  /// A host without one keeps nothing on the device.
  openDb?(name: string): Effect.Effect<Sql, HostError | SqlError>;
  /// A database in memory, for an account whose file cannot be opened (another process holds it): kept this run only
  /// (undefined while the host cannot make one yet).
  memoryDb?(): Sql | undefined;
  /// An account's database gone (it signed out, or its file was damaged and is made again).
  deleteDb?(name: string): Effect.Effect<void, HostError>;
  /// An error the core goes on after, told to the host's error tracking (the web's goes to its page's, docs/telemetry.md):
  /// one that says why the device keeps less than it should (an account's database that cannot be opened, or was made
  /// again). Its message names no one's content. A host without error tracking has none.
  report?(error: Error): void;
  /// The former records store (before the databases per account), read once to bring what it kept over; left as it
  /// is, so an older core still finds it.
  legacyRead?(range: DbRange): Effect.Effect<[string, Uint8Array][], HostError>;

  /// The app's performance record, where the host keeps one: what the connections do written into it while it is on
  /// (record.ts).
  readonly recorder?: Recorder | undefined;
  /// Milliseconds since the Unix epoch.
  nowMs(): number;
  /// Milliseconds on a clock that only moves forward, for timing spans.
  monotonicMs(): number;
  /// The viewer's time zone at that moment: minutes to add to UTC to get local time.
  utcOffsetMin(atMs: number): number;
  /// The connections kept for requests are taken for gone: what is asked next goes on new ones.
  resetConnections(): void;

  randomBytes(buf: Uint8Array): void;
  /// Whether what this host keeps is out of reach of still.fail cloud's code: an app's (desktop, Android), not a web
  /// page's, whose code the cloud serves. Only such a host keeps a key that signs for the workspace lock (lock.ts).
  appKeys?: boolean;

  /// Delivers a message to one connected UI.
  emit(client: ClientId, message: CoreMessage): void;

  /// A TCP connection to this machine's `port` (adbd, for the adb share: adb.ts), open while the scope is; only a
  /// native host has one.
  tcp?(port: number): Effect.Effect<TcpConnection, HostError, Scope.Scope>;

  /// This device's own adb (the shell's adb.rs, docs/adb-share.md): paired once with adbd's pairing port, one session
  /// held to adbd's port, and a station's session carried on it, read and written as a socket is (`open`, failing while
  /// none is held). `hold` fails with `unpaired` while adbd does not take this device's key. Only a native host has it.
  adb?: {
    pair(port: number, code: string): Effect.Effect<void, HostError>;
    hold(port: number): Effect.Effect<void, HostError>;
    open(): Effect.Effect<TcpConnection, HostError, Scope.Scope>;
  };

  /// An HTTP listener on this machine's loopback `host` (127.0.0.1 or ::1, nothing else) at `port`, open while the scope
  /// is: what comes to it, a request at a time (a login's browser coming back, docs/remote-login.md). Fails when the port
  /// is taken there. Only a native host has one (a web page cannot listen).
  listen?(port: number, host: "127.0.0.1" | "::1" | string): Effect.Effect<Pull<LoopbackRequest>, HostError, Scope.Scope>;
}

/// A request that came to a loopback listener (`Host.listen`): what it asked, and how it is answered (once).
export type LoopbackRequest = {
  method: string;
  /// With its query.
  path: string;
  headers: [string, string][];
  body: Uint8Array;
  respond(status: number, headers: [string, string][], body: Uint8Array): void;
};

/// A TCP connection: what comes in, as it comes; what goes out; `end`, no more goes out.
export type TcpConnection = { read: Pull<Uint8Array>; write(bytes: Uint8Array): Effect.Effect<void, HostError>; end(): void };
