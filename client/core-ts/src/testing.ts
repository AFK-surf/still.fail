// A host for tests (testing.rs): in-memory storage and database, HTTP answered by a function you set, emissions
// collected, WebSockets fed by the test, time on a TestClock the test moves (`pass`), random bytes from a fixed seed.
import { Deferred, Duration, Effect, Queue, Scope, type Clock } from "effect";
import { TestClock } from "effect/testing";
import { COALESCE_MS } from "./store.ts";
import { HostError } from "./error.ts";
import type { DbRange, Host, HttpRequest, HttpResponse, Pull, Sql, StreamResponse, TcpConnection } from "./host.ts";
import { DatabaseSync } from "node:sqlite";
import { NodeSql } from "./hosts/node-sql.ts";
import type { ClientId, CoreMessage } from "./protocol.ts";
import { compareKeys, toJsonBytes } from "./util.ts";

/// A test host's time: its clock, its now, and how it is moved on (TestTime; a simulated network's SimTime).
export interface HostTime {
  readonly clock: Clock.Clock;
  /// Every sleep asked of it (ms), in order.
  readonly sleeps: number[];
  now(): number;
  pass(ms: number, step?: number): Promise<void>;
}

/// A test's clock: a TestClock, with every sleep asked of it noted.
export class TestTime implements HostTime {
  readonly clock: Clock.Clock;
  readonly #test: TestClock.TestClock;
  /// Every sleep asked for (ms), in order: timers show here.
  readonly sleeps: number[] = [];
  /// What the clock read at its zero: the TestClock starts at 0, and the wall clock is this from there.
  readonly #base: number;

  /// `start`: a fixed moment by default, so a test reads the same time (and day) whenever it runs.
  constructor(start = Date.UTC(2026, 9, 6, 9, 0, 0)) {
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

/// A WebSocket the test feeds: `send` a frame, `end` it, `fail` it.
export class FakeSocket implements Pull<string> {
  readonly url: string;
  readonly protocols: string[];
  readonly #queue: Queue.Queue<string | null | HostError>;
  closed = false;

  constructor(url: string, protocols: string[]) {
    this.url = url;
    this.protocols = protocols;
    this.#queue = Effect.runSync(Queue.unbounded<string | null | HostError>());
  }

  send(text: string): void {
    if (!this.closed) Queue.offerUnsafe(this.#queue, text);
  }

  /// The server went away.
  end(): void {
    if (this.closed) return;
    this.closed = true;
    Queue.offerUnsafe(this.#queue, null);
  }

  fail(message: string): void {
    if (this.closed) return;
    this.closed = true;
    Queue.offerUnsafe(this.#queue, new HostError(message));
  }

  /// Let go by the core (its scope closed).
  close(): void {
    this.closed = true;
  }

  get take(): Effect.Effect<string | null, HostError> {
    return Effect.flatMap(Queue.take(this.#queue), (v) => (v instanceof HostError ? Effect.fail(v) : Effect.succeed(v)));
  }
}

export class FakeHost implements Host {
  origin = "https://stillfail.test";
  isBeta = false;
  onTestChannel = false;
  readonly time: HostTime;
  readonly storage = new Map<string, Uint8Array>();
  /// The former records store (what db/import.ts brings over): `${table}\u0000${key}` → bytes.
  readonly db = new Map<string, Uint8Array>();
  /// The accounts' databases, in memory, by name: a core started again on this host opens the same.
  readonly sqls = new Map<string, NodeSql>();
  /// What opening a database does instead (a test of one that cannot be opened).
  openDbHook: ((name: string) => Sql | Error | null) | null = null;
  /// A database in memory, where a test gives one.
  memoryDb?: () => Sql | undefined;
  #responder: Responder | null = null;
  #streamResponder: ((request: HttpRequest) => Effect.Effect<StreamResponse, HostError, Scope.Scope>) | null = null;
  readonly sockets: FakeSocket[] = [];
  refuseSockets = false;
  resets = 0;
  readonly requests: HttpRequest[] = [];
  #holds: [string, Deferred.Deferred<void>][] = [];
  emitted: [ClientId, CoreMessage][] = [];
  #seed = 0x5eedn;
  #offset = 0;
  #ahead = 0;

  constructor(time: HostTime = new TestTime()) {
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

  /// What still.fail cloud (and tests' stations) answer: a response, or a HostError thrown.
  onFetch(responder: Responder): void {
    this.#responder = responder;
  }

  onFetchStream(responder: (request: HttpRequest) => Effect.Effect<StreamResponse, HostError, Scope.Scope>): void {
    this.#streamResponder = responder;
  }

  /// Holds back the answer of the next request whose url ends with `path` until `release` is called.
  hold(path: string): () => void {
    const d = Deferred.makeUnsafe<void>();
    this.#holds.push([path, d]);
    return () => Deferred.doneUnsafe(d, Effect.void);
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

  advance(ms: number): void {
    this.#ahead += ms;
  }

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

  /// Lets spawned work and timers up to COALESCE_MS run.
  async settle(): Promise<void> {
    await this.time.pass(COALESCE_MS + 20);
  }

  fetch(request: HttpRequest): Effect.Effect<HttpResponse, HostError> {
    return Effect.gen({ self: this }, function* () {
      this.requests.push(request);
      const i = this.#holds.findIndex(([path]) => request.url.endsWith(path));
      const held = i >= 0 ? this.#holds.splice(i, 1)[0][1] : null;
      const responder = this.#responder;
      const answer = yield* Effect.result(
        Effect.tryPromise({
          try: async () => {
            if (!responder) throw new HostError(`no responder for ${request.method} ${request.url}`);
            return responder(request);
          },
          catch: (e) => (e instanceof HostError ? e : new HostError(String(e))),
        }),
      );
      if (held) yield* Deferred.await(held);
      if (answer._tag === "Failure") return yield* Effect.fail(answer.failure);
      return answer.success;
    });
  }

  fetchStream(request: HttpRequest): Effect.Effect<StreamResponse, HostError, Scope.Scope> {
    return Effect.suspend(() => {
      this.requests.push(request);
      if (!this.#streamResponder) return Effect.fail(new HostError(`no stream responder for ${request.method} ${request.url}`));
      return this.#streamResponder(request);
    });
  }

  websocket(url: string, protocols: string[]): Effect.Effect<Pull<string>, HostError, Scope.Scope> {
    return Effect.gen({ self: this }, function* () {
      if (this.refuseSockets) return yield* Effect.fail(new HostError("refused"));
      const socket = new FakeSocket(url, protocols);
      this.sockets.push(socket);
      // Closed with the scope it was opened in.
      yield* Effect.addFinalizer(() => Effect.sync(() => socket.close()));
      return socket as Pull<string>;
    });
  }

  resetConnections(): void {
    this.resets++;
  }

  /// This machine's TCP (adbd, for the adb share): set by a test that has one; none answers by default.
  tcpConnect: ((port: number) => Effect.Effect<TcpConnection, HostError, Scope.Scope>) | null = null;

  tcp(port: number): Effect.Effect<TcpConnection, HostError, Scope.Scope> {
    return this.tcpConnect ? this.tcpConnect(port) : Effect.fail(new HostError(`nothing listens on ${port}`));
  }

  storageGet(key: string): Effect.Effect<Uint8Array | null, HostError> {
    return Effect.sync(() => this.storage.get(key) ?? null);
  }
  storageSet(key: string, value: Uint8Array): Effect.Effect<void, HostError> {
    return Effect.sync(() => void this.storage.set(key, value));
  }
  storageDelete(key: string): Effect.Effect<void, HostError> {
    return Effect.sync(() => void this.storage.delete(key));
  }

  legacyRead(range: DbRange): Effect.Effect<[string, Uint8Array][], HostError> {
    return Effect.sync(() => {
      const out: [string, Uint8Array][] = [];
      for (const [k, v] of this.db) {
        const at = k.indexOf("\u0000");
        const table = k.slice(0, at);
        const key = k.slice(at + 1);
        if (table === range.table && compareKeys(key, range.from) >= 0 && compareKeys(key, range.to) < 0) out.push([key, v]);
      }
      return out.sort((a, b) => compareKeys(a[0], b[0]));
    });
  }

  openDb(name: string): Effect.Effect<Sql, HostError> {
    return Effect.suspend(() => {
      const hooked = this.openDbHook?.(name) ?? null;
      if (hooked instanceof Error) return Effect.fail(hooked as HostError);
      if (hooked !== null) return Effect.succeed(hooked);
      let sql = this.sqls.get(name);
      if (!sql) {
        sql = new NodeSql(new DatabaseSync(":memory:"), true);
        this.sqls.set(name, sql);
      }
      return Effect.succeed(sql as Sql);
    });
  }

  deleteDb(name: string): Effect.Effect<void, HostError> {
    return Effect.sync(() => {
      const sql = this.sqls.get(name);
      this.sqls.delete(name);
      sql?.db.close();
    });
  }

  /// A row count of an account's table (tests).
  rows(name: string, sql: string, params: (string | number | null)[] = []): unknown[][] {
    const db = this.sqls.get(name);
    return db ? (db.all(sql, params) as unknown[][]) : [];
  }

  /// Puts a record into the former records store (an import's test).
  legacyPut(table: string, key: string, value: unknown): void {
    this.db.set(`${table}\u0000${key}`, toJsonBytes(value));
  }

  dbKeys(table: string): string[] {
    return [...this.db.keys()].filter((k) => k.startsWith(`${table}\u0000`)).map((k) => k.slice(table.length + 1)).sort(compareKeys);
  }

  nowMs(): number {
    return this.time.now() + this.#ahead;
  }
  monotonicMs(): number {
    return this.nowMs();
  }
  utcOffsetMin(_at: number): number {
    return this.#offset;
  }

  /// A deterministic xorshift: tests see the same "random" values every run.
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
    this.emitted.push([client, JSON.parse(JSON.stringify(message)) as CoreMessage]);
  }
}

/// A JSON response.
export function jsonResponse(status: number, value: unknown): HttpResponse {
  return { status, headers: [["content-type", "application/json"]], body: toJsonBytes(value) };
}

/// A streamed body from fixed chunks; `pending`: one that never ends.
export function chunks(parts: Uint8Array[], pending = false): Pull<Uint8Array> {
  const queue = [...parts];
  return { take: Effect.suspend(() => (queue.length > 0 ? Effect.succeed(queue.shift()!) : pending ? Effect.never : Effect.succeed(null))) };
}
