// What differs per platform (host.rs). The Node host (hosts/node.ts) implements it over fetch, `ws`, node:sqlite and
// files; the web's over fetch, WebSocket and IndexedDB; Android's over OkHttp and SQLite through JSI. Tests use
// testing.ts. Waiting is not the host's: the core sleeps on Effect's Clock (runtime.ts), so tests move a TestClock.
import type { CoreMessage, ClientId } from "./protocol.ts";
import type { Wake } from "./wake.ts";
export { HostError } from "./error.ts";

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

/// A body that arrives in pieces: `next` gives the next one, null once it ended (it throws a HostError when it failed).
export type Chunks = {
  next(): Promise<Uint8Array | null>;
  /// Nobody wants the rest: the connection under it goes.
  close(): void;
};

/// A response whose body arrives in chunks (event streams).
export type StreamResponse = { status: number; headers: [string, string][]; body: Chunks };

/// A receive-only WebSocket's text frames: `next` gives the next one, null once the socket closed (it throws a
/// HostError when it failed). While it is open the host sends `SOCKET_PING` on it every `SOCKET_PING_MS`; still.fail
/// cloud answers `pong` (a frame like any other). `close` closes it.
export type SocketFrames = {
  next(): Promise<string | null>;
  close(): void;
};

/// What a host sends on an open WebSocket to be answered `pong`.
export const SOCKET_PING = "ping";
/// How often.
export const SOCKET_PING_MS = 25_000;

/// Keys `[from, to)` of one table of the core's database (docs/core-db.md), in key order.
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

  fetch(request: HttpRequest): Promise<HttpResponse>;
  fetchStream(request: HttpRequest): Promise<StreamResponse>;
  /// Opens a WebSocket that only listens (still.fail cloud's `/v1/events`); resolves once it is open.
  websocket(url: string, protocols: string[]): Promise<SocketFrames>;

  /// Small persistent values by key: accounts, the device key, preferences.
  storageGet(key: string): Promise<Uint8Array | null>;
  storageSet(key: string, value: Uint8Array): Promise<void>;
  storageDelete(key: string): Promise<void>;

  /// The core's database: records by table and key. A host without one keeps nothing.
  dbRead(range: DbRange): Promise<[string, Uint8Array][]>;
  dbWrite(ops: DbOp[]): Promise<void>;

  /// Milliseconds since the Unix epoch.
  nowMs(): number;
  /// Milliseconds on a clock that only moves forward, for timing spans; its zero is the host's own.
  monotonicMs(): number;
  /// The viewer's time zone at that moment: minutes to add to UTC to get local time.
  utcOffsetMin(atMs: number): number;
  /// The next time a UI says it is back after being away (wake.rs); never, on a host the core has not wrapped.
  woken(): Promise<Wake>;
  /// The connections kept for requests are taken for gone: what is asked next goes on new ones.
  resetConnections(): void;

  randomBytes(buf: Uint8Array): void;

  /// Delivers a message to one connected UI.
  emit(client: ClientId, message: CoreMessage): void;
}

/// What a host that does not say otherwise does: no beta, no database, no wakes.
export abstract class BaseHost implements Host {
  abstract cloudOrigin(): string;
  beta(): boolean {
    return false;
  }
  testChannel(): boolean {
    return this.beta();
  }
  abstract fetch(request: HttpRequest): Promise<HttpResponse>;
  abstract fetchStream(request: HttpRequest): Promise<StreamResponse>;
  abstract websocket(url: string, protocols: string[]): Promise<SocketFrames>;
  abstract storageGet(key: string): Promise<Uint8Array | null>;
  abstract storageSet(key: string, value: Uint8Array): Promise<void>;
  abstract storageDelete(key: string): Promise<void>;
  async dbRead(_range: DbRange): Promise<[string, Uint8Array][]> {
    return [];
  }
  async dbWrite(_ops: DbOp[]): Promise<void> {}
  abstract nowMs(): number;
  monotonicMs(): number {
    return this.nowMs();
  }
  abstract utcOffsetMin(atMs: number): number;
  woken(): Promise<Wake> {
    return new Promise(() => {});
  }
  resetConnections(): void {}
  abstract randomBytes(buf: Uint8Array): void;
  abstract emit(client: ClientId, message: CoreMessage): void;
}
