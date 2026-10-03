// A host for tests (testing.rs): in-memory storage and database, HTTP answered by a function you set, emissions
// collected, WebSockets fed by the test, time on a TestClock the test moves (`pass`), random bytes from a fixed seed.
import { Duration, Effect, Scope, type Clock } from "effect";
import { TestClock } from "effect/testing";
import { COALESCE_MS } from "./store.ts";
import { HostError } from "./error.ts";
import { BaseHost, type Chunks, type DbOp, type DbRange, type HttpRequest, type HttpResponse, type SocketFrames, type StreamResponse } from "./host.ts";
import type { ClientId, CoreMessage } from "./protocol.ts";
import { compareKeys, toJsonBytes } from "./util.ts";

/// A test's clock: a TestClock, with every sleep asked of it noted.
export class TestTime {
  readonly clock: Clock.Clock;
  readonly #test: TestClock.TestClock;
  /// Every sleep asked for (ms), in order: timers show here.
  readonly sleeps: number[] = [];
  /// What the clock read at its zero: the TestClock starts at 0, and the wall clock is this from there.
  readonly #base: number;

  constructor(start = Date.now()) {
    const scope = Effect.runSync(Scope.make());
    this.#test = Effect.runSync(Scope.provide(TestClock.make(), scope)) as TestClock.TestClock;
    this.#base = start;
    const test = this.#test;
    const base = start;
    const sleeps = this.sleeps;
    this.clock = {
      ...test,
      currentTimeMillisUnsafe: () => base + test.currentTimeMillisUnsafe(),
      currentTimeMillis: Effect.sync(() => base + test.currentTimeMillisUnsafe()),
      sleep(duration: Duration.Duration) {
        sleeps.push(Duration.toMillis(duration));
        return test.sleep(duration);
      },
    } as Clock.Clock;
  }

  now(): number {
    return this.#base + this.#test.currentTimeMillisUnsafe();
  }

  /// Lets `ms` of the core's time pass, in small steps, so what each step wakes runs (and sleeps again) before the next.
  async pass(ms: number, step = 10): Promise<void> {
    await flush();
    let left = ms;
    while (left > 0) {
      const d = Math.min(step, left);
      await Effect.runPromise(this.#test.adjust(d));
      left -= d;
      await flush();
    }
    await flush();
  }
}

/// Lets what is ready run: promise continuations and the runtime's scheduled fibers.
export async function flush(rounds = 6): Promise<void> {
  for (let i = 0; i < rounds; i++) await new Promise<void>((r) => setImmediate(r));
}

type Responder = (request: HttpRequest) => HttpResponse | Promise<HttpResponse>;

/// A WebSocket the test feeds: `send` a frame, `close` it, `fail` it.
export class FakeSocket implements SocketFrames {
  readonly url: string;
  readonly protocols: string[];
  #queue: (string | null | Error)[] = [];
  #waiting: ((v: string | null | Error) => void) | null = null;
  closed = false;

  constructor(url: string, protocols: string[]) {
    this.url = url;
    this.protocols = protocols;
  }

  #push(v: string | null | Error): void {
    const w = this.#waiting;
    if (w) {
      this.#waiting = null;
      w(v);
    } else this.#queue.push(v);
  }

  send(text: string): void {
    if (!this.closed) this.#push(text);
  }

  /// The server went away.
  end(): void {
    if (this.closed) return;
    this.closed = true;
    this.#push(null);
  }

  fail(message: string): void {
    if (this.closed) return;
    this.closed = true;
    this.#push(new HostError(message));
  }

  async next(): Promise<string | null> {
    const v = this.#queue.length > 0 ? this.#queue.shift()! : await new Promise<string | null | Error>((r) => (this.#waiting = r));
    if (v instanceof Error) throw v;
    return v;
  }

  close(): void {
    this.closed = true;
  }
}

export class FakeHost extends BaseHost {
  origin = "https://stillfail.test";
  isBeta = false;
  onTestChannel = false;
  readonly time: TestTime;
  readonly storage = new Map<string, Uint8Array>();
  /// The core's database: `${table}\u0000${key}` → bytes.
  readonly db = new Map<string, Uint8Array>();
  #responder: Responder | null = null;
  #streamResponder: ((request: HttpRequest) => StreamResponse | Promise<StreamResponse>) | null = null;
  readonly sockets: FakeSocket[] = [];
  refuseSockets = false;
  resets = 0;
  readonly requests: HttpRequest[] = [];
  #holds: [string, Promise<void>][] = [];
  emitted: [ClientId, CoreMessage][] = [];
  #seed = 0x5eedn;
  #offset = 0;
  /// How far the clock was moved on at once (`advance`), ms.
  #ahead = 0;

  constructor(time = new TestTime()) {
    super();
    this.time = time;
  }

  cloudOrigin(): string {
    return this.origin;
  }
  beta(): boolean {
    return this.isBeta;
  }
  testChannel(): boolean {
    return this.isBeta || this.onTestChannel;
  }

  onFetch(responder: Responder): void {
    this.#responder = responder;
  }

  onFetchStream(responder: (request: HttpRequest) => StreamResponse | Promise<StreamResponse>): void {
    this.#streamResponder = responder;
  }

  /// Holds back the answer of the next request whose url ends with `path` until `release` is called.
  hold(path: string): () => void {
    let release!: () => void;
    const held = new Promise<void>((r) => (release = r));
    this.#holds.push([path, held]);
    return release;
  }

  stored(key: string): Uint8Array | undefined {
    return this.storage.get(key);
  }

  store(key: string, value: Uint8Array | unknown): void {
    this.storage.set(key, value instanceof Uint8Array ? value : toJsonBytes(value));
  }

  setUtcOffsetMin(minutes: number): void {
    this.#offset = minutes;
  }

  /// Moves the clock on by `ms` at once, timers left as they are.
  advance(ms: number): void {
    this.#ahead += ms;
  }

  /// Sends a text frame on the newest open WebSocket whose url ends with `path`.
  socketSend(path: string, text: string): void {
    const socket = [...this.sockets].reverse().find((s) => s.url.endsWith(path) && !s.closed);
    if (!socket) throw new Error("socket open");
    socket.send(text);
  }

  socketClose(path: string): void {
    for (const s of this.sockets) if (s.url.endsWith(path)) s.end();
  }

  openSockets(path: string): number {
    return this.sockets.filter((s) => s.url.endsWith(path) && !s.closed).length;
  }

  takeEmitted(): [ClientId, CoreMessage][] {
    const out = this.emitted;
    this.emitted = [];
    return out;
  }

  /// Lets spawned tasks and timers up to COALESCE_MS run.
  async settle(): Promise<void> {
    await this.time.pass(COALESCE_MS + 20);
  }

  async fetch(request: HttpRequest): Promise<HttpResponse> {
    this.requests.push(request);
    const i = this.#holds.findIndex(([path]) => request.url.endsWith(path));
    const held = i >= 0 ? this.#holds.splice(i, 1)[0][1] : null;
    if (!this.#responder) {
      if (held) await held;
      throw new HostError(`no responder for ${request.method} ${request.url}`);
    }
    const answer = Promise.resolve().then(() => this.#responder!(request));
    if (held) await held;
    return answer;
  }

  async fetchStream(request: HttpRequest): Promise<StreamResponse> {
    this.requests.push(request);
    if (!this.#streamResponder) throw new HostError(`no stream responder for ${request.method} ${request.url}`);
    return this.#streamResponder(request);
  }

  async websocket(url: string, protocols: string[]): Promise<SocketFrames> {
    if (this.refuseSockets) throw new HostError("refused");
    const socket = new FakeSocket(url, protocols);
    this.sockets.push(socket);
    return socket;
  }

  resetConnections(): void {
    this.resets++;
  }

  async storageGet(key: string): Promise<Uint8Array | null> {
    return this.storage.get(key) ?? null;
  }
  async storageSet(key: string, value: Uint8Array): Promise<void> {
    this.storage.set(key, value);
  }
  async storageDelete(key: string): Promise<void> {
    this.storage.delete(key);
  }

  async dbRead(range: DbRange): Promise<[string, Uint8Array][]> {
    const out: [string, Uint8Array][] = [];
    for (const [k, v] of this.db) {
      const at = k.indexOf("\u0000");
      const table = k.slice(0, at);
      const key = k.slice(at + 1);
      if (table === range.table && compareKeys(key, range.from) >= 0 && compareKeys(key, range.to) < 0) out.push([key, v]);
    }
    return out.sort((a, b) => compareKeys(a[0], b[0]));
  }

  async dbWrite(ops: DbOp[]): Promise<void> {
    for (const op of ops) {
      if ("put" in op) this.db.set(`${op.put.table}\u0000${op.put.key}`, op.put.value);
      else this.db.delete(`${op.delete.table}\u0000${op.delete.key}`);
    }
  }

  /// The database's keys of a table.
  dbKeys(table: string): string[] {
    return [...this.db.keys()].filter((k) => k.startsWith(`${table}\u0000`)).map((k) => k.slice(table.length + 1)).sort(compareKeys);
  }

  nowMs(): number {
    return this.time.now() + this.#ahead;
  }

  utcOffsetMin(_at: number): number {
    return this.#offset;
  }

  /// A deterministic xorshift: tests see the same "random" values every run (testing.rs's).
  randomBytes(buf: Uint8Array): void {
    const mask = (1n << 64n) - 1n;
    let s = this.#seed;
    for (let i = 0; i < buf.length; i++) {
      s ^= (s << 13n) & mask;
      s ^= s >> 7n;
      s ^= (s << 17n) & mask;
      buf[i] = Number(s & 0xffn);
    }
    this.#seed = s;
  }

  emit(client: ClientId, message: CoreMessage): void {
    // As it goes on the wire: what a UI gets is JSON.
    this.emitted.push([client, JSON.parse(JSON.stringify(message)) as CoreMessage]);
  }
}

/// A JSON response.
export function jsonResponse(status: number, value: unknown): HttpResponse {
  return { status, headers: [["content-type", "application/json"]], body: toJsonBytes(value) };
}

/// A streamed body from fixed chunks; `pending` one that never ends.
export function chunks(parts: Uint8Array[], pending = false): Chunks {
  const queue = [...parts];
  return {
    async next() {
      if (queue.length > 0) return queue.shift()!;
      if (pending) await new Promise(() => {});
      return null;
    },
    close() {},
  };
}
