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
//   kept.read {at, start, end} → bytes or {none} — a file the app saved where the person keeps files, read back
//     (`at` as the system named it: a path; on Android a content address), answered by the app (Apple: apple_core.mm;
//     Android: CoreHost; Windows: win_core.c)
//   secure.get {key, user, reason?} → bytes or {none}; secure.set {key, user} + value; secure.delete {key};
//     secure.ask {reason} — answered by the app (Kotlin: the Keystore, and the prompt when `user` or asked), not the
//     shell (docs/vault.md, "设备上的钥匙")
//   db.read {table, from, to} → {keys, sizes} + the values one after another (the former records store, read once)
//   tcp.open {port} → {id}; tcp.read {id} → bytes or {end}; tcp.write {id} + bytes; tcp.end {id}; tcp.close {id}
//   adb.pair {port, code}; adb.hold {port} (fails `unpaired` while adbd does not take the key); adb.state {} → {port};
//     adb.open {} → {id}, read and written as a tcp one: this device's own adb session (the shell's adb.rs)
//   listen.open {port, host} → {id} (fails when the port is taken there); listen.next {id} → {request, method, path,
//     headers: [[name, value]]} + the body, or {end}; listen.respond {id, request, status, headers} + body;
//     listen.close {id} — a login's loopback listener (docs/remote-login.md), answered by the app (Kotlin:
//     Loopback.kt, where the app keeps itself running while it listens), not the shell
//   picked.read {file, start, end} → bytes; picked.hash {file} → {sha256}; picked.release {file} — a file picked in
//     the app, read a part at a time as it goes up (`composer.add` with `blob: {hostFile, size, type}`) and named by
//     its content first (a station that has it already copies its own), answered by the app (Kotlin: PickedFiles.kt).
//     Or held whole by the app and handed over with the call, its bytes beside it (`blob: {hostBytes: [start,
//     length], type, sha256}`: mbui's app, whose picked files are read whole), read from those as it goes up
//   reset {} — the connections kept for requests are taken for gone
//   zstd.open {} → {id}; zstd.push {id} + bytes → {whole} + what they make; zstd.close {id} — a station's reply taken
//     apart in the shell (libzstd), not in JS (Host.unzstd)
//   iroh.bind {relayUrls, lookup, relayOnly, alpns: [hex]} + key → {id}; iroh.connect {id, addr, additional: [hex]} +
//     alpn → {id}; iroh.accept {id} → {id, alpn: hex} (the next connection coming, its handshake done; {end} once the
//     endpoint is gone); iroh.networkChange {id}; iroh.close {id}
//   conn.openBi / conn.acceptBi / conn.openUni {id} → {id} (acceptBi: {end} once gone); conn.closed {id} → reason;
//     conn.close {id, code, reason}
//   istream.read {id} → bytes or {end}; istream.write {id} + bytes; istream.finish {id}; istream.stopped {id} → {code};
//     istream.reset {id, code}; istream.tap {id, call} + what was read past the reply → {tapped} (a remote screen's
//     picture and sound said to the app by the shell itself, where its host gave it a way to: Apple's)
// And at once (`callSync`, answering {value} or {error}): sql.open {name} → {id} (`:memory:` one in memory);
//   sql.exec {id, sql}; sql.run {id, sql, params} → changes; sql.all {id, sql, params} → rows (arrays);
//   sql.close {id}; sql.delete {name}; storage.path {key} → the file it is kept in, or null while none is;
//   fetch.cancel {id} → whether the pending fetch call was cancelled (a call id, not a handle);
//   iroh.endpointId {id}; iroh.addAddr {id, addr};
//   iroh.relayStatus {id}; conn.remoteId {id};
//   conn.closeReason {id}; conn.paths {id}; conn.stats {id}; release {id} (a handle let go); text.collate {names} →
//   each one's place in the order people read them (the system's collation; a shell without it: an error, and the
//   core orders them by hand); ed25519.sign {seed, message} (hex) → {publicKey, signature} (hex; a shell without it:
//   an error, and the core signs in JS: Host.ed25519Sign).
import type { Recorder } from "../record.ts";
import { Effect, type Scope } from "effect";
import { Core } from "../core.ts";
import { FileSource } from "../file-source.ts";
import type { CoreModule } from "../module.ts";
import { HostError } from "../error.ts";
import type { CloseReason, Iroh, IrohAddr, IrohConnection, IrohEndpoint, IrohPath, IrohStream } from "../iroh.ts";
import { accessOf } from "../iroh-bindings.ts";
import { SOCKET_PING, SOCKET_PING_MS, type DbRange, type Host, type HttpRequest, type HttpResponse, type LoopbackRequest, type Pull, type Sql, type SqlRow, type SqlValue, type StreamResponse, type TcpConnection, type SqlError, type Unzstd, sqlError } from "../host.ts";
import type { ClientId, CoreMessage } from "../protocol.ts";
import { t } from "../i18n.ts";
import { service } from "../trace.ts";
import { laterSleep } from "../runtime.ts";

/// What the shell gives the JS.
export interface Native {
  /// Starts operation `id`; its answer comes to `Bridge.complete`.
  call(id: number, op: string, json: string, bytes: Uint8Array | null): void;
  /// An operation answered at once (JSON).
  callSync(op: string, json: string): string;
  /// What the core says to one UI.
  emit(client: number, json: string): void;
  /// What the core says to one UI with bytes beside it (a screen view's frame, protocol.ts): the JSON without them.
  emitBytes(client: number, json: string, bytes: Uint8Array): void;
  now(): number;
  monotonic(): number;
  utcOffset(atMs: number): number;
  random(buf: Uint8Array): void;
  /// The app's performance record, where it keeps one (record.ts): whether it is kept now, a line into it.
  recording?(): boolean;
  record?(line: string): void;
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

  /// Operation `op`; interrupted, its answer is let go. A fetch is also cancelled in the shell: dropping only this
  /// waiter would leave its HTTP exchange alive through every subsequent retry on a weak network.
  call(op: string, json: unknown, bytes: Uint8Array | null = null): Effect.Effect<Answer, HostError> {
    return Effect.callback<Answer, HostError>((resume) => {
      const id = this.#next++;
      this.#waiting.set(id, { resolve: (a) => resume(Effect.succeed(a)), reject: (e) => resume(Effect.fail(e)) });
      this.native.call(id, op, JSON.stringify(json ?? {}), bytes);
      return Effect.sync(() => {
        if (!this.#waiting.delete(id) || op !== "fetch") return;
        // A shell from before fetch.cancel says an error; it still completes the fetch on its own as before.
        this.native.callSync("fetch.cancel", JSON.stringify({ id }));
      });
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
const unhex = (s: string) => Uint8Array.from(s.match(/../g) ?? [], (x) => parseInt(x, 16));

/// A pull over a shell operation that answers bytes, or `{end}`.
function pullBytes(bridge: Bridge, op: string, id: number): Pull<Uint8Array> {
  return { take: Effect.map(bridge.call(op, { id }), (a) => ((a.json as J)?.end === true ? null : (a.bytes ?? new Uint8Array(0)))) };
}

/// A socket the shell opened with `op` (a port of this machine's, a station's session on its adb), closed with the scope.
function socketOf(bridge: Bridge, op: string, args: J): Effect.Effect<TcpConnection, HostError, Scope.Scope> {
  return Effect.gen(function* () {
    const opened = yield* Effect.acquireRelease(bridge.call(op, args), (a) => Effect.ignore(bridge.call("tcp.close", { id: (a.json as J).id }), { log: "Unhandled", message: "tcp closed" }));
    const id = (opened.json as J).id as number;
    return {
      read: pullBytes(bridge, "tcp.read", id),
      write: (bytes: Uint8Array) => Effect.asVoid(bridge.call("tcp.write", { id }, bytes)),
      end: () => void Effect.runFork(Effect.ignore(bridge.call("tcp.end", { id }))),
    };
  });
}

export class BridgeHost implements Host {
  /// The app's performance record, where the engine keeps one (record.ts).
  get recorder(): Recorder | undefined {
    const n = this.#bridge.native;
    if (n.recording === undefined || n.record === undefined) return undefined;
    return { on: () => n.recording!(), line: (text) => n.record!(text) };
  }
  readonly #bridge: Bridge;
  readonly #origin: string;
  readonly #beta: boolean;

  constructor(bridge: Bridge, cloudOrigin: string, beta: boolean) {
    this.#bridge = bridge;
    this.#origin = cloudOrigin.replace(/\/+$/, "");
    this.#beta = beta;
  }

  /// The shell's collation (`text.collate`), until it says it has none.
  #collates = true;
  collate(names: readonly string[]): number[] | null {
    if (!this.#collates || names.length < 2) return null;
    try {
      const at = this.#bridge.sync("text.collate", { names });
      if (Array.isArray(at) && at.length === names.length && at.every((n) => typeof n === "number")) return at as number[];
    } catch {
      // A shell from before it.
    }
    this.#collates = false;
    return null;
  }

  /// The shell's Ed25519 (`ed25519.sign`), until it says it has none.
  #signs = true;
  ed25519Sign(seed: Uint8Array, message: Uint8Array): { publicKey: Uint8Array; signature: Uint8Array } | null {
    if (!this.#signs) return null;
    try {
      const out = this.#bridge.sync("ed25519.sign", { seed: hex(seed), message: hex(message) }) as J;
      if (typeof out?.publicKey === "string" && typeof out?.signature === "string") return { publicKey: unhex(out.publicKey), signature: unhex(out.signature) };
    } catch {
      // A shell from before it.
    }
    this.#signs = false;
    return null;
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
        Effect.ignore(bridge.call("stream.close", { id: (a.json as J).id }), { log: "Unhandled", message: "stream closed" }),
      );
      const head = opened.json as J;
      return { status: head.status, headers: head.headers, body: pullBytes(bridge, "stream.read", head.id) };
    });
  }

  /// A zstd stream taken apart by the shell, off the core's thread (zstd.open, zstd.push, zstd.close as the scope ends).
  unzstd(): Effect.Effect<Unzstd, HostError, Scope.Scope> {
    const bridge = this.#bridge;
    return Effect.map(
      Effect.acquireRelease(bridge.call("zstd.open", {}), (a) => Effect.ignore(bridge.call("zstd.close", { id: (a.json as J).id }), { log: "Unhandled", message: "zstd closed" })),
      (a): Unzstd => {
        const id = (a.json as J).id as number;
        return { push: (piece) => Effect.map(bridge.call("zstd.push", { id }, piece), (r) => ({ bytes: r.bytes ?? new Uint8Array(0), whole: (r.json as J)?.whole === true })) };
      },
    );
  }

  websocket(url: string, protocols: string[]): Effect.Effect<Pull<string>, HostError, Scope.Scope> {
    const bridge = this.#bridge;
    return Effect.gen(function* () {
      const opened = yield* Effect.acquireRelease(bridge.call("ws.open", { url, protocols }), (a) => Effect.ignore(bridge.call("ws.close", { id: (a.json as J).id }), { log: "Unhandled", message: "socket closed" }));
      const id = (opened.json as J).id as number;
      // The host's ping (host.rs SOCKET_PING_MS).
      yield* Effect.forkScoped(Effect.forever(laterSleep(SOCKET_PING_MS).pipe(Effect.andThen(Effect.ignore(bridge.call("ws.send", { id, text: SOCKET_PING }), { log: "Unhandled", message: "socket pinged" })))));
      return { take: Effect.map(bridge.call("ws.next", { id }), (a) => ((a.json as J)?.end === true ? null : String((a.json as J).text))) };
    });
  }

  resetConnections(): void {
    Effect.runFork(Effect.ignore(this.#bridge.call("reset", {})));
  }

  tcp(port: number): Effect.Effect<TcpConnection, HostError, Scope.Scope> {
    return socketOf(this.#bridge, "tcp.open", { port });
  }

  get adb(): NonNullable<Host["adb"]> {
    const bridge = this.#bridge;
    return {
      pair: (port, code) => Effect.asVoid(bridge.call("adb.pair", { port, code })),
      hold: (port) => Effect.asVoid(bridge.call("adb.hold", { port })),
      open: () => socketOf(bridge, "adb.open", {}),
    };
  }

  /// A loopback listener (a login's browser coming back, docs/remote-login.md), the app's: a request at a time, each
  /// answered once (the app closes its connection then).
  listen(port: number, host: string): Effect.Effect<Pull<LoopbackRequest>, HostError, Scope.Scope> {
    const bridge = this.#bridge;
    return Effect.gen(function* () {
      if (host !== "127.0.0.1" && host !== "::1") return yield* Effect.fail(new HostError(`not a loopback address: ${host}`));
      const opened = yield* Effect.acquireRelease(bridge.call("listen.open", { port, host }), (a) => Effect.ignore(bridge.call("listen.close", { id: (a.json as J).id }), { log: "Unhandled", message: "listener closed" }));
      const id = (opened.json as J).id as number;
      const request = (a: { json: unknown; bytes: Uint8Array | null }): LoopbackRequest | null => {
        const r = a.json as J;
        if (r?.end === true) return null;
        let answered = false;
        return {
          method: String(r.method),
          path: String(r.path),
          headers: Array.isArray(r.headers) ? (r.headers as unknown[]).filter((h): h is [string, string] => Array.isArray(h) && typeof h[0] === "string" && typeof h[1] === "string") : [],
          body: a.bytes ?? new Uint8Array(0),
          respond: (status, headers, body) => {
            if (answered) return;
            answered = true;
            Effect.runFork(Effect.ignore(bridge.call("listen.respond", { id, request: r.request, status, headers }, body)));
          },
        };
      };
      return { take: Effect.map(bridge.call("listen.next", { id }), request) };
    });
  }

  storageGet(key: string): Effect.Effect<Uint8Array | null, HostError> {
    return Effect.map(this.#bridge.call("storage.get", { key }), (a) => ((a.json as J)?.none === true ? null : (a.bytes ?? new Uint8Array(0))));
  }
  storageSet(key: string, value: Uint8Array): Effect.Effect<void, HostError> {
    return Effect.asVoid(this.#bridge.call("storage.set", { key }, value));
  }
  savedRead(at: string, start: number, end: number): Effect.Effect<Uint8Array | null, HostError> {
    return Effect.map(this.#bridge.call("kept.read", { at, start, end }), (a) => ((a.json as J)?.none === true ? null : (a.bytes ?? new Uint8Array(0))));
  }
  storageDelete(key: string): Effect.Effect<void, HostError> {
    return Effect.asVoid(this.#bridge.call("storage.delete", { key }));
  }
  /// The shell's file for a key (`storage.path`), until it says it has none.
  #paths = true;
  storagePath(key: string): string | null {
    if (!this.#paths) return null;
    try {
      const path = this.#bridge.sync("storage.path", { key });
      return typeof path === "string" ? path : null;
    } catch {
      // A shell from before it.
      this.#paths = false;
      return null;
    }
  }

  secureGet(key: string, opts: { user: boolean; reason?: string }): Effect.Effect<Uint8Array | null, HostError> {
    return Effect.map(this.#bridge.call("secure.get", { key, user: opts.user, reason: opts.reason ?? "" }), (a) => ((a.json as J)?.none === true ? null : (a.bytes ?? new Uint8Array(0))));
  }
  secureSet(key: string, value: Uint8Array, opts: { user: boolean }): Effect.Effect<void, HostError> {
    return Effect.asVoid(this.#bridge.call("secure.set", { key, user: opts.user }, value));
  }
  secureDelete(key: string): Effect.Effect<void, HostError> {
    return Effect.asVoid(this.#bridge.call("secure.delete", { key }));
  }
  secureAsk(reason: string): Effect.Effect<void, HostError> {
    return Effect.asVoid(this.#bridge.call("secure.ask", { reason }));
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
    // Match Date.now() on web and Node: persisted and transmitted wall times use whole milliseconds.
    return Math.floor(this.#bridge.native.now());
  }
  monotonicMs(): number {
    return this.#bridge.native.monotonic();
  }
  utcOffsetMin(atMs: number): number {
    return this.#bridge.native.utcOffset(atMs);
  }
  /// An app's: what it keeps is the device's, not code still.fail cloud serves (lock.ts).
  readonly appKeys = true;

  randomBytes(buf: Uint8Array): void {
    this.#bridge.native.random(buf);
  }
  emit(client: ClientId, message: CoreMessage): void {
    if ("bytes" in message && message.bytes !== undefined) {
      const { bytes, ...rest } = message;
      this.#bridge.native.emitBytes(client, JSON.stringify(rest), bytes);
    } else this.#bridge.native.emit(client, JSON.stringify(message));
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
    tap: (call, prefix) => Effect.map(bridge.call("istream.tap", { id, call }, prefix), (a) => (a.json as J)?.tapped === true),
  });
  const connection = (id: number, endpointId: number): IrohConnection => ({
    remoteId: () => String(bridge.sync("conn.remoteId", { id })),
    openBi: () => Effect.map(bridge.call("conn.openBi", { id }), (a) => stream(handle(a))),
    acceptBi: () => Effect.orElseSucceed(Effect.map(bridge.call("conn.acceptBi", { id }), (a) => ((a.json as J)?.end === true ? null : stream(handle(a)))), () => null),
    openUni: () => Effect.map(bridge.call("conn.openUni", { id }), (a) => stream(handle(a))),
    close: (code, reason) => void Effect.runFork(Effect.ignore(bridge.call("conn.close", { id, code, reason }))),
    closeReason: () => (bridge.sync("conn.closeReason", { id }) as CloseReason | null) ?? null,
    closed: () => Effect.orElseSucceed(Effect.map(bridge.call("conn.closed", { id }), (a) => a.json as CloseReason), () => ({ kind: "other", reason: "" }) as CloseReason),
    paths: () => {
      const paths = (bridge.sync("conn.paths", { id }) as IrohPath[]) ?? [];
      const statuses = (bridge.sync("iroh.relayStatus", { id: endpointId }) as { url: string; access?: string }[]) ?? [];
      return paths.map((p) => ({ ...p, relay: accessOf(p.relay, statuses) }));
    },
    stats: () => bridge.sync("conn.stats", { id }) as ReturnType<IrohConnection["stats"]>,
  });
  const endpoint = (id: number): IrohEndpoint => ({
    id: () => String(bridge.sync("iroh.endpointId", { id })),
    connect: (addr: IrohAddr, alpn, additional) => Effect.map(bridge.call("iroh.connect", { id, addr, additional: additional.map(hex) }, alpn), (a) => connection(handle(a), id)),
    accept: () =>
      Effect.orElseSucceed(
        Effect.map(bridge.call("iroh.accept", { id }), (a) => ((a.json as J)?.end === true ? null : { connection: connection(handle(a), id), alpn: unhex(String((a.json as J).alpn)) })),
        () => null,
      ),
    addAddr: (addr) => void bridge.sync("iroh.addAddr", { id, addr }),
    networkChange: () => Effect.ignore(bridge.call("iroh.networkChange", { id }), { log: "Unhandled", message: "network change told" }),
    relayStatus: () => (bridge.sync("iroh.relayStatus", { id }) as { url: string; connected: boolean }[]) ?? [],
    dhtSaid: (keep) => (bridge.sync("dht.said", { keep }) as ReturnType<NonNullable<IrohEndpoint["dhtSaid"]>> | null) ?? { lines: [], dropped: 0 },
    setRelayEntries: (entries) => Effect.asVoid(bridge.call("iroh.setRelayEntries", { id, entries })),
    close: () => Effect.ignore(bridge.call("iroh.close", { id }), { log: "Unhandled", message: "endpoint closed" }),
  });
  return {
    bind: (o) => Effect.map(bridge.call("iroh.bind", { relayUrls: o.relayUrls, ...(o.relayEntries ? { relayEntries: o.relayEntries } : {}), lookup: o.lookup, relayOnly: o.relayOnly, alpns: (o.alpns ?? []).map(hex) }, o.secretKey), (a) => endpoint(handle(a))),
  };
}

/// A core on a shell: the API the Rust core's Node addon had (connect / receive(json) / disconnect). A bug that ends a fiber ends it as a
/// panic ended the Rust core: `onFatal` (each UI is told `{"fatal": …}` by the shell, which starts another). `modules`:
/// what the app adds to the core (module.ts).
export function startBridged(native: Native, cloudOrigin: string, beta: boolean, os: string, onFatal: (reason: string) => void, extra: { modules?: readonly CoreModule[] } = {}) {
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
  const ready = Core.create(host, { iroh: bridgeIroh(bridge), modules: extra.modules }).then((core) => {
    // A database found damaged on the way is marked first: the core that follows makes it again (data.ts).
    core.inner.runner.onDefect = (error) => void core.inner.data.damageKept().then(() => fatal(error));
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
    receive(client: number, json: string, bytes?: Uint8Array): void {
      // A file picked in the app: read from there as it goes up, as the desktop's page's is (file-port.ts).
      if (json.includes('"hostFile"') || json.includes('"hostBytes"')) {
        let raw: unknown;
        try { raw = JSON.parse(json); } catch { raw = null; }
        const files = (raw as { call?: unknown; params?: { files?: unknown } } | null)?.params?.files;
        if ((raw as { call?: unknown } | null)?.call === "composer.add" && Array.isArray(files)) {
          let held = false;
          for (const f of files) {
            const b = (f as { blob?: unknown } | null)?.blob as { hostFile?: unknown; hostBytes?: unknown; size?: unknown; type?: unknown; sha256?: unknown } | undefined;
            // Handed over whole beside the call: read from those bytes, named by what the app worked out.
            const at = b?.hostBytes;
            if (bytes && Array.isArray(at) && at.length === 2 && Number.isSafeInteger(at[0]) && Number.isSafeInteger(at[1]) && at[0] >= 0 && at[1] >= 0 && at[0] + at[1] <= bytes.length) {
              const part = bytes.subarray(at[0], at[0] + at[1]);
              const sha = typeof b?.sha256 === "string" && /^[0-9a-f]{64}$/.test(b.sha256) ? b.sha256 : null;
              (f as { blob: unknown }).blob = new FileSource(at[1], typeof b?.type === "string" ? b.type : "",
                (start, end) => Promise.resolve(part.slice(start, end).buffer as ArrayBuffer), () => {},
                sha ? () => Promise.resolve(sha) : undefined);
              held = true;
              continue;
            }
            if (!b || !Number.isSafeInteger(b.hostFile) || !Number.isSafeInteger(b.size) || (b.size as number) < 0) continue;
            const file = b.hostFile as number;
            (f as { blob: unknown }).blob = new FileSource(b.size as number, typeof b.type === "string" ? b.type : "",
              (start, end) => Effect.runPromise(Effect.map(bridge.call("picked.read", { file, start, end }), (a) => {
                const got = a.bytes ?? new Uint8Array(0);
                return (got.buffer as ArrayBuffer).slice(got.byteOffset, got.byteOffset + got.byteLength);
              })),
              () => { Effect.runFork(Effect.ignore(bridge.call("picked.release", { file }))); },
              () => Effect.runPromise(Effect.orElseSucceed(Effect.map(bridge.call("picked.hash", { file }), (a) => {
                const sha = (a.json as { sha256?: unknown } | null)?.sha256;
                return typeof sha === "string" && /^[0-9a-f]{64}$/.test(sha) ? sha : null;
              }), () => null)));
          }
          later((core) => core.receiveRaw(client, raw, held ? undefined : bytes));
          return;
        }
      }
      later((core) => core.receiveJson(client, json, bytes));
    },
    disconnect(client: number): void {
      later((core) => core.disconnect(client));
    },
  };
}
