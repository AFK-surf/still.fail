// The core on a native shell that is not Node (the Android app's: Hermes in C++, its IO in Rust, apps/android/core):
// the Host and the iroh over one narrow bridge. The JS asks for an operation by name with JSON and maybe bytes; the
// shell does it on its own threads and answers (`complete`) with JSON and maybe bytes. What the shell does is what
// the Rust core's native host did (HTTP, the cloud's WebSocket, files per storage key and `core.db`, TCP to adbd) and what the
// station's addon does for Node (iroh), so a phone moving from the Rust core keeps its files. The accounts' databases
// are SQLite in the shell, used synchronously (the `sql.*` calls), files `databases/<name>.db` beside the former
// `core.db`, which is only read (`db.read`), once.
//
// Operations (`op`, its JSON → its answer):
//   fetch {url, method, headers} + body → {status, headers} + body
//   stream.open {url, method, headers} + body → {status, headers, id}; stream.read {id} → bytes, or {end}; stream.close {id}
//   ws.open {url, protocols} → {id}; ws.next {id} → {text} or {end}; ws.send {id, text}; ws.close {id}
//   storage.get {key} → bytes or {none}; storage.set {key} + value; storage.delete {key}
//   db.read {table, from, to} → {keys, sizes} + the values one after another (the former records store, read once)
//   tcp.open {port} → {id}; tcp.read {id} → bytes or {end}; tcp.write {id} + bytes; tcp.end {id}; tcp.close {id}
//   reset {} — the connections kept for requests are taken for gone
//   iroh.bind {relayUrls, lookup, relayOnly} + key → {id}; iroh.connect {id, addr, additional: [hex]} + alpn → {id};
//     iroh.networkChange {id}; iroh.close {id}
//   conn.openBi / conn.acceptBi / conn.openUni {id} → {id} (acceptBi: {end} once gone); conn.closed {id} → reason;
//     conn.close {id, code, reason}
//   istream.read {id} → bytes or {end}; istream.write {id} + bytes; istream.finish {id}; istream.stopped {id} → {code};
//     istream.reset {id, code}
// And at once (`callSync`, answering {value} or {error}): sql.open {name} → {id} (`:memory:` one in memory);
//   sql.exec {id, sql}; sql.run {id, sql, params} → changes; sql.all {id, sql, params} → rows (arrays);
//   sql.close {id}; sql.delete {name}; iroh.endpointId {id}; iroh.addAddr {id, addr};
//   iroh.relayStatus {id}; conn.remoteId {id};
//   conn.closeReason {id}; conn.paths {id}; conn.stats {id}; release {id} (a handle let go).
import { Effect, type Scope } from "effect";
import { Core } from "../core.ts";
import { HostError } from "../error.ts";
import type { CloseReason, Iroh, IrohAddr, IrohConnection, IrohEndpoint, IrohStream } from "../iroh.ts";
import { SOCKET_PING, SOCKET_PING_MS, type DbRange, type Host, type HttpRequest, type HttpResponse, type Pull, type Sql, type SqlRow, type SqlValue, type StreamResponse, type TcpConnection, type SqlError, sqlError } from "../host.ts";
import type { ClientId, CoreMessage } from "../protocol.ts";
import { t } from "../i18n.ts";
import { service } from "../trace.ts";

/// What the shell gives the JS.
export interface Native {
  /// Starts operation `id`; its answer comes to `Bridge.complete`.
  call(id: number, op: string, json: string, bytes: Uint8Array | null): void;
  /// An operation answered at once (JSON).
  callSync(op: string, json: string): string;
  /// What the core says to one UI.
  emit(client: number, json: string): void;
  now(): number;
  monotonic(): number;
  utcOffset(atMs: number): number;
  random(buf: Uint8Array): void;
}

type Answer = { json: unknown; bytes: Uint8Array | null };
type Waiting = { resolve(a: Answer): void; reject(e: HostError): void };

/// The JS end of the bridge: what is waiting on the shell, by id.
export class Bridge {
  readonly native: Native;
  #next = 1;
  readonly #waiting = new Map<number, Waiting>();

  constructor(native: Native) {
    this.native = native;
  }

  /// Operation `op`; interrupted, it is not waited for any more (the shell's answer is let go).
  call(op: string, json: unknown, bytes: Uint8Array | null = null): Effect.Effect<Answer, HostError> {
    return Effect.callback<Answer, HostError>((resume) => {
      const id = this.#next++;
      this.#waiting.set(id, { resolve: (a) => resume(Effect.succeed(a)), reject: (e) => resume(Effect.fail(e)) });
      this.native.call(id, op, JSON.stringify(json ?? {}), bytes);
      return Effect.sync(() => this.#waiting.delete(id));
    });
  }

  sync(op: string, json: unknown): unknown {
    const out = this.native.callSync(op, JSON.stringify(json ?? {}));
    const parsed = JSON.parse(out) as { error?: string; value?: unknown };
    if (typeof parsed.error === "string") throw new HostError(parsed.error);
    return parsed.value;
  }

  /// The shell's answer to `id`: `error` set when it failed.
  complete(id: number, json: string | null, error: string | null, bytes: Uint8Array | null): void {
    const w = this.#waiting.get(id);
    if (!w) return;
    this.#waiting.delete(id);
    if (error !== null) w.reject(new HostError(error));
    else w.resolve({ json: json === null || json === "" ? null : JSON.parse(json), bytes });
  }
}

type J = any;

/// Bytes put one after another, and their sizes.
function concat(parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

const hex = (b: Uint8Array) => Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");

/// A pull over a shell operation that answers bytes, or `{end}`.
function pullBytes(bridge: Bridge, op: string, id: number): Pull<Uint8Array> {
  return { take: Effect.map(bridge.call(op, { id }), (a) => ((a.json as J)?.end === true ? null : (a.bytes ?? new Uint8Array(0)))) };
}

export class BridgeHost implements Host {
  readonly #bridge: Bridge;
  readonly #origin: string;
  readonly #beta: boolean;

  constructor(bridge: Bridge, cloudOrigin: string, beta: boolean) {
    this.#bridge = bridge;
    this.#origin = cloudOrigin.replace(/\/+$/, "");
    this.#beta = beta;
  }

  cloudOrigin(): string {
    return this.#origin;
  }
  beta(): boolean {
    return this.#beta;
  }
  testChannel(): boolean {
    return this.#beta;
  }

  fetch(request: HttpRequest): Effect.Effect<HttpResponse, HostError> {
    return Effect.map(this.#bridge.call("fetch", { url: request.url, method: request.method, headers: request.headers }, request.body ?? null), (a) => ({
      status: (a.json as J).status,
      headers: (a.json as J).headers,
      body: a.bytes ?? new Uint8Array(0),
    }));
  }

  fetchStream(request: HttpRequest): Effect.Effect<StreamResponse, HostError, Scope.Scope> {
    const bridge = this.#bridge;
    return Effect.gen(function* () {
      const opened = yield* Effect.acquireRelease(bridge.call("stream.open", { url: request.url, method: request.method, headers: request.headers }, request.body ?? null), (a) =>
        Effect.ignore(bridge.call("stream.close", { id: (a.json as J).id })),
      );
      const head = opened.json as J;
      return { status: head.status, headers: head.headers, body: pullBytes(bridge, "stream.read", head.id) };
    });
  }

  websocket(url: string, protocols: string[]): Effect.Effect<Pull<string>, HostError, Scope.Scope> {
    const bridge = this.#bridge;
    return Effect.gen(function* () {
      const opened = yield* Effect.acquireRelease(bridge.call("ws.open", { url, protocols }), (a) => Effect.ignore(bridge.call("ws.close", { id: (a.json as J).id })));
      const id = (opened.json as J).id as number;
      // The host's ping (host.rs SOCKET_PING_MS).
      yield* Effect.forkScoped(Effect.forever(Effect.sleep(SOCKET_PING_MS).pipe(Effect.andThen(Effect.ignore(bridge.call("ws.send", { id, text: SOCKET_PING }))))));
      return { take: Effect.map(bridge.call("ws.next", { id }), (a) => ((a.json as J)?.end === true ? null : String((a.json as J).text))) };
    });
  }

  resetConnections(): void {
    Effect.runFork(Effect.ignore(this.#bridge.call("reset", {})));
  }

  tcp(port: number): Effect.Effect<TcpConnection, HostError, Scope.Scope> {
    const bridge = this.#bridge;
    return Effect.gen(function* () {
      const opened = yield* Effect.acquireRelease(bridge.call("tcp.open", { port }), (a) => Effect.ignore(bridge.call("tcp.close", { id: (a.json as J).id })));
      const id = (opened.json as J).id as number;
      return {
        read: pullBytes(bridge, "tcp.read", id),
        write: (bytes: Uint8Array) => Effect.asVoid(bridge.call("tcp.write", { id }, bytes)),
        end: () => void Effect.runFork(Effect.ignore(bridge.call("tcp.end", { id }))),
      };
    });
  }

  storageGet(key: string): Effect.Effect<Uint8Array | null, HostError> {
    return Effect.map(this.#bridge.call("storage.get", { key }), (a) => ((a.json as J)?.none === true ? null : (a.bytes ?? new Uint8Array(0))));
  }
  storageSet(key: string, value: Uint8Array): Effect.Effect<void, HostError> {
    return Effect.asVoid(this.#bridge.call("storage.set", { key }, value));
  }
  storageDelete(key: string): Effect.Effect<void, HostError> {
    return Effect.asVoid(this.#bridge.call("storage.delete", { key }));
  }

  legacyRead(range: DbRange): Effect.Effect<[string, Uint8Array][], HostError> {
    return Effect.map(this.#bridge.call("db.read", range), (a) => {
      const { keys, sizes } = a.json as { keys: string[]; sizes: number[] };
      const bytes = a.bytes ?? new Uint8Array(0);
      let at = 0;
      return keys.map((k, i) => {
        const v = bytes.slice(at, at + sizes[i]);
        at += sizes[i];
        return [k, v] as [string, Uint8Array];
      });
    });
  }

  openDb(name: string): Effect.Effect<Sql, HostError | SqlError> {
    return Effect.try({ try: () => new BridgeSql(this.#bridge, name), catch: (e) => sqlError(e) });
  }

  memoryDb(): Sql {
    return new BridgeSql(this.#bridge, ":memory:");
  }

  deleteDb(name: string): Effect.Effect<void, HostError> {
    return Effect.try({ try: () => void this.#bridge.sync("sql.delete", { name }), catch: (e) => (e instanceof HostError ? e : new HostError(String(e))) });
  }

  nowMs(): number {
    return this.#bridge.native.now();
  }
  monotonicMs(): number {
    return this.#bridge.native.monotonic();
  }
  utcOffsetMin(atMs: number): number {
    return this.#bridge.native.utcOffset(atMs);
  }
  randomBytes(buf: Uint8Array): void {
    this.#bridge.native.random(buf);
  }
  emit(client: ClientId, message: CoreMessage): void {
    this.#bridge.native.emit(client, JSON.stringify(message));
  }
}

/// An account's database in the shell (SQLite, its statements prepared once there and kept), asked synchronously.
export class BridgeSql implements Sql {
  readonly #bridge: Bridge;
  readonly #id: number;
  #closed = false;

  constructor(bridge: Bridge, name: string) {
    this.#bridge = bridge;
    this.#id = (bridge.sync("sql.open", { name }) as { id: number }).id;
  }

  #ask(op: string, json: unknown): unknown {
    try {
      return this.#bridge.sync(op, json);
    } catch (e) {
      throw sqlError(e);
    }
  }

  exec(sql: string): void {
    this.#ask("sql.exec", { id: this.#id, sql });
  }

  run(sql: string, params: readonly SqlValue[] = []): number {
    return this.#ask("sql.run", { id: this.#id, sql, params }) as number;
  }

  all(sql: string, params: readonly SqlValue[] = []): SqlRow[] {
    return this.#ask("sql.all", { id: this.#id, sql, params }) as SqlRow[];
  }

  close(): void {
    if (this.#closed) return;
    this.#closed = true;
    this.#ask("sql.close", { id: this.#id });
  }
}

/// The shell's iroh as the core's (iroh.ts).
export function bridgeIroh(bridge: Bridge): Iroh {
  const handle = (a: Answer) => (a.json as J).id as number;
  const stream = (id: number): IrohStream => ({
    read: () => Effect.map(bridge.call("istream.read", { id }), (a) => ((a.json as J)?.end === true ? null : (a.bytes ?? new Uint8Array(0)))),
    write: (bytes) => Effect.asVoid(bridge.call("istream.write", { id }, bytes)),
    finish: () => Effect.asVoid(bridge.call("istream.finish", { id })),
    stopped: () => Effect.map(bridge.call("istream.stopped", { id }), (a) => (typeof (a.json as J)?.code === "number" ? (a.json as J).code : null)),
    reset: (code) => void Effect.runFork(Effect.ignore(bridge.call("istream.reset", { id, code }))),
  });
  const connection = (id: number): IrohConnection => ({
    remoteId: () => String(bridge.sync("conn.remoteId", { id })),
    openBi: () => Effect.map(bridge.call("conn.openBi", { id }), (a) => stream(handle(a))),
    acceptBi: () => Effect.orElseSucceed(Effect.map(bridge.call("conn.acceptBi", { id }), (a) => ((a.json as J)?.end === true ? null : stream(handle(a)))), () => null),
    openUni: () => Effect.map(bridge.call("conn.openUni", { id }), (a) => stream(handle(a))),
    close: (code, reason) => void Effect.runFork(Effect.ignore(bridge.call("conn.close", { id, code, reason }))),
    closeReason: () => (bridge.sync("conn.closeReason", { id }) as CloseReason | null) ?? null,
    closed: () => Effect.orElseSucceed(Effect.map(bridge.call("conn.closed", { id }), (a) => a.json as CloseReason), () => ({ kind: "other", reason: "" }) as CloseReason),
    paths: () => (bridge.sync("conn.paths", { id }) as { selected: boolean; relay: string | null; rttMs: number }[]) ?? [],
    stats: () => bridge.sync("conn.stats", { id }) as ReturnType<IrohConnection["stats"]>,
  });
  const endpoint = (id: number): IrohEndpoint => ({
    id: () => String(bridge.sync("iroh.endpointId", { id })),
    connect: (addr: IrohAddr, alpn, additional) => Effect.map(bridge.call("iroh.connect", { id, addr, additional: additional.map(hex) }, alpn), (a) => connection(handle(a))),
    addAddr: (addr) => void bridge.sync("iroh.addAddr", { id, addr }),
    networkChange: () => Effect.ignore(bridge.call("iroh.networkChange", { id })),
    relayStatus: () => (bridge.sync("iroh.relayStatus", { id }) as { url: string; connected: boolean }[]) ?? [],
    close: () => Effect.ignore(bridge.call("iroh.close", { id })),
  });
  return { bind: (o) => Effect.map(bridge.call("iroh.bind", { relayUrls: o.relayUrls, lookup: o.lookup, relayOnly: o.relayOnly }, o.secretKey), (a) => endpoint(handle(a))) };
}

/// A core on a shell: the API the Rust core's Node addon had (connect / receive(json) / disconnect). A bug that ends a fiber ends it as a
/// panic ended the Rust core: `onFatal` (each UI is told `{"fatal": …}` by the shell, which starts another).
export function startBridged(native: Native, cloudOrigin: string, beta: boolean, os: string, onFatal: (reason: string) => void) {
  service.name = "stillfail-native";
  service.os = os;
  const bridge = new Bridge(native);
  const host = new BridgeHost(bridge, cloudOrigin, beta);
  let dead = false;
  const fatal = (error: unknown) => {
    if (dead) return;
    dead = true;
    onFatal(t("core-misc.host.crashed", { reason: error instanceof Error ? error.message : String(error) }));
  };
  const ready = Core.create(host, { iroh: bridgeIroh(bridge) }).then((core) => {
    core.inner.runner.onDefect = fatal;
    core.keepTime();
    return core;
  });
  ready.catch(fatal);
  let next = 1;
  let chain: Promise<unknown> = ready;
  const later = (job: (core: Core) => void) => {
    chain = chain.then(() => ready.then((core) => !dead && job(core))).catch(fatal);
  };
  return {
    bridge,
    connect(): number {
      const id = next++;
      later((core) => core.connect());
      return id;
    },
    receive(client: number, json: string): void {
      later((core) => core.receiveJson(client, json));
    },
    disconnect(client: number): void {
      later((core) => core.disconnect(client));
    },
  };
}
