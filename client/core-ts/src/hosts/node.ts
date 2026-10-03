// The core on Node (the desktop app's utility process; tests and the side-by-side runs): the Host over fetch, the `ws`
// package, node:sqlite and files, as the Rust core's native host kept them — the same data directory, the same file per
// storage key (`%XX` for what a file name cannot hold), the same `core.db` — so a desktop app moving from the Rust core
// keeps its logins and what it had read. `start` is the API the Rust core's Node addon had: connect / receive(json) / disconnect, the
// listener given `(client, json)`.
import { mkdirSync } from "node:fs";
import { open, readFile, rename, rm } from "node:fs/promises";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { webcrypto } from "node:crypto";
import { Effect, Queue, Scope } from "effect";
import WebSocket from "ws";
import { connect as tcpConnect } from "node:net";
import { Core } from "../core.ts";
import { nodeIroh } from "./node-iroh.ts";
import { HostWire } from "../station/wire.ts";
import { HostError } from "../error.ts";
import { SOCKET_PING, SOCKET_PING_MS, type TcpConnection, type DbOp, type DbRange, type Host, type HttpRequest, type HttpResponse, type Pull, type StreamResponse } from "../host.ts";
import type { ClientId, CoreMessage } from "../protocol.ts";
import { service } from "../trace.ts";
import { t } from "../i18n.ts";

export type Listener = (client: ClientId, json: string) => void;

function fetchError(e: unknown): HostError {
  // undici says "fetch failed" and keeps the cause: say what failed.
  let message = e instanceof Error ? e.message : String(e);
  let cause = e instanceof Error ? (e as { cause?: unknown }).cause : undefined;
  while (cause instanceof Error) {
    message += `: ${cause.message}`;
    cause = (cause as { cause?: unknown }).cause;
  }
  return new HostError(message);
}

export class NodeHost implements Host {
  readonly #origin: string;
  readonly #beta: boolean;
  readonly #dir: string;
  #db: DatabaseSync | null = null;
  readonly #listener: Listener;
  readonly #started = performance.now();

  constructor(dataDir: string, cloudOrigin: string, beta: boolean, listener: Listener) {
    mkdirSync(dataDir, { recursive: true });
    this.#dir = dataDir;
    this.#origin = cloudOrigin.replace(/\/+$/, "");
    this.#beta = beta;
    this.#listener = listener;
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
    return Effect.tryPromise({
      // Interrupted, the request is let go (its signal).
      try: async (signal) => {
        const response = await fetch(request.url, { method: request.method, headers: request.headers, body: (request.body ?? undefined) as BodyInit | undefined, signal, redirect: "manual" });
        return { status: response.status, headers: [...response.headers.entries()], body: new Uint8Array(await response.arrayBuffer()) };
      },
      catch: fetchError,
    });
  }

  fetchStream(request: HttpRequest): Effect.Effect<StreamResponse, HostError, Scope.Scope> {
    return Effect.gen(function* () {
      const abort = new AbortController();
      // The response goes with the scope it was opened in.
      yield* Effect.addFinalizer(() => Effect.sync(() => abort.abort()));
      const response = yield* Effect.tryPromise({
        try: () => fetch(request.url, { method: request.method, headers: request.headers, body: (request.body ?? undefined) as BodyInit | undefined, signal: abort.signal }),
        catch: fetchError,
      });
      const reader = response.body?.getReader();
      const body: Pull<Uint8Array> = {
        take: reader
          ? Effect.tryPromise({
              try: async () => {
                const { done, value } = await reader.read();
                return done ? null : value;
              },
              catch: fetchError,
            })
          : Effect.succeed(null),
      };
      return { status: response.status, headers: [...response.headers.entries()], body };
    });
  }

  websocket(url: string, protocols: string[]): Effect.Effect<Pull<string>, HostError, Scope.Scope> {
    return Effect.gen(function* () {
      const frames = yield* Queue.unbounded<string | null | HostError>();
      const socket = yield* Effect.acquireRelease(
        Effect.callback<WebSocket, HostError>((resume) => {
          const socket = new WebSocket(url, protocols);
          let open = false;
          socket.on("open", () => {
            open = true;
            resume(Effect.succeed(socket));
          });
          socket.on("message", (data, binary) => {
            if (!binary) Queue.offerUnsafe(frames, data.toString());
          });
          socket.on("close", () => Queue.offerUnsafe(frames, null));
          socket.on("unexpected-response", (_req, res) => {
            resume(Effect.fail(new HostError(`websocket refused (${res.statusCode})`)));
            socket.terminate();
          });
          socket.on("error", (e) => {
            if (!open) resume(Effect.fail(new HostError(`websocket: ${e.message}`)));
            else Queue.offerUnsafe(frames, new HostError(`websocket: ${e.message}`));
          });
          // Interrupted while opening: let go.
          return Effect.sync(() => socket.terminate());
        }),
        (socket) => Effect.sync(() => socket.close()),
      );
      // The host's ping (host.rs SOCKET_PING_MS): still.fail cloud answers `pong`. A measurement of the connection, not
      // a read of anything.
      yield* Effect.forkScoped(Effect.forever(Effect.sleep(SOCKET_PING_MS).pipe(Effect.andThen(Effect.sync(() => socket.send(SOCKET_PING))))));
      return { take: Effect.flatMap(Queue.take(frames), (v) => (v instanceof HostError ? Effect.fail(v) : Effect.succeed(v))) };
    });
  }

  resetConnections(): void {}

  tcp(port: number): Effect.Effect<TcpConnection, HostError, Scope.Scope> {
    return nodeTcp(port);
  }

  /// Keys may hold anything; file names only letters, digits, `-` and `_` (the rest is %XX).
  path(key: string): string {
    let name = "";
    for (const b of new TextEncoder().encode(key)) {
      const c = String.fromCharCode(b);
      name += /[A-Za-z0-9\-_]/.test(c) ? c : `%${b.toString(16).toUpperCase().padStart(2, "0")}`;
    }
    return join(this.#dir, name);
  }

  /// One file operation after another, in the order asked for (as the Rust core's storage thread did): a write is never
  /// overtaken by an earlier one, and none holds up the core's thread.
  #files: Promise<unknown> = Promise.resolve();

  #file<T>(job: () => Promise<T>, error: (e: Error) => string): Effect.Effect<T, HostError> {
    const run = this.#files.then(job);
    this.#files = run.catch(() => {});
    return Effect.tryPromise({ try: () => run, catch: (e) => new HostError(error(e as Error)) });
  }

  storageGet(key: string): Effect.Effect<Uint8Array | null, HostError> {
    return this.#file(
      async () => {
        try {
          return new Uint8Array(await readFile(this.path(key)));
        } catch (e) {
          if ((e as NodeJS.ErrnoException).code === "ENOENT") return null;
          throw e;
        }
      },
      (e) => `读不了：${e.message}`,
    );
  }

  storageSet(key: string, value: Uint8Array): Effect.Effect<void, HostError> {
    // Written aside and renamed over: a crash leaves the old value or the new one, never half.
    return this.#file(
      async () => {
        const path = this.path(key);
        const partial = `${path}.partial`;
        const file = await open(partial, "w");
        try {
          await file.writeFile(value);
          await file.sync();
        } finally {
          await file.close();
        }
        await rename(partial, path);
      },
      (e) => `写不进去：${e.message}`,
    );
  }

  storageDelete(key: string): Effect.Effect<void, HostError> {
    return this.#file(() => rm(this.path(key), { force: true }), (e) => `删不掉：${e.message}`);
  }

  #open(): DatabaseSync {
    if (!this.#db) {
      const db = new DatabaseSync(join(this.#dir, "core.db"), { timeout: 5000 });
      db.exec("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; CREATE TABLE IF NOT EXISTS records (tbl TEXT NOT NULL, key TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY (tbl, key)) WITHOUT ROWID;");
      this.#db = db;
    }
    return this.#db;
  }

  dbRead(range: DbRange): Effect.Effect<[string, Uint8Array][], HostError> {
    return Effect.try({
      try: () =>
        (this.#open().prepare("SELECT key, value FROM records WHERE tbl = ? AND key >= ? AND key < ? ORDER BY key").all(range.table, range.from, range.to) as { key: string; value: Uint8Array }[]).map(
          (r) => [r.key, new Uint8Array(r.value)] as [string, Uint8Array],
        ),
      catch: (e) => new HostError(`数据库出错：${(e as Error).message}`),
    });
  }

  dbWrite(ops: DbOp[]): Effect.Effect<void, HostError> {
    return Effect.try({
      try: () => {
        const db = this.#open();
        db.exec("BEGIN");
        try {
          const put = db.prepare("INSERT OR REPLACE INTO records (tbl, key, value) VALUES (?, ?, ?)");
          const del = db.prepare("DELETE FROM records WHERE tbl = ? AND key = ?");
          for (const op of ops) {
            if ("put" in op) put.run(op.put.table, op.put.key, op.put.value);
            else del.run(op.delete.table, op.delete.key);
          }
          db.exec("COMMIT");
        } catch (e) {
          db.exec("ROLLBACK");
          throw e;
        }
      },
      catch: (e) => new HostError(`数据库出错：${(e as Error).message}`),
    });
  }

  nowMs(): number {
    return Date.now();
  }
  monotonicMs(): number {
    return performance.now() - this.#started;
  }
  utcOffsetMin(atMs: number): number {
    return -new Date(atMs).getTimezoneOffset();
  }
  randomBytes(buf: Uint8Array): void {
    webcrypto.getRandomValues(buf);
  }
  emit(client: ClientId, message: CoreMessage): void {
    this.#listener(client, JSON.stringify(message));
  }

  close(): void {
    this.#db?.close();
    this.#db = null;
  }
}

/// The Node addon's `start`, as the Rust core had it: a core whose messages go to `listener(client, json)`; `channel` "beta" for a beta app's.
/// A bug that ends a fiber ends the core as a panic ended the Rust core: each client is told `{"fatal": …}` and the host
/// starts another (apps/desktop/src/core.ts).
/// `hostWire`: its stations answer at the cloud's origin over plain HTTP, not on the mesh (the side-by-side run,
/// harness/run.ts).
export function start(dataDir: string, cloudOrigin: string, listener: Listener, channel?: string, options: { hostWire?: boolean } = {}) {
  service.name = "stillfail-native";
  service.os = process.platform === "darwin" ? "macos" : process.platform;
  const host = new NodeHost(dataDir, cloudOrigin, channel === "beta", listener);
  const clients = new Set<number>();
  let dead = false;
  const fatal = (error: unknown) => {
    if (dead) return;
    dead = true;
    console.error("still.fail core:", error);
    const said = JSON.stringify({ fatal: t("core-misc.host.crashed", { reason: error instanceof Error ? error.message : String(error) }) });
    for (const client of clients) listener(client, said);
    void ready.then((core) => core.close(), () => {});
  };
  // Messages that arrive while the core starts wait, in order (as the Rust core's queue did).
  const ready = Core.create(host, options.hostWire ? { iroh: null, wire: () => new HostWire(host) } : { iroh: nodeIroh() }).then((core) => {
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
    connect(): number {
      const id = next++;
      clients.add(id);
      later((core) => core.connect());
      return id;
    },
    receive(client: number, json: string): void {
      later((core) => core.receiveJson(client, json));
    },
    disconnect(client: number): void {
      clients.delete(client);
      later((core) => core.disconnect(client));
    },
    async close(): Promise<void> {
      dead = true;
      (await ready).close();
      host.close();
    },
  };
}

/// A TCP connection to this machine's `port` (adbd), open while the scope is.
export function nodeTcp(port: number): Effect.Effect<TcpConnection, HostError, Scope.Scope> {
  return Effect.gen(function* () {
    const incoming = yield* Queue.unbounded<Uint8Array | null | HostError>();
    const socket = yield* Effect.acquireRelease(
      Effect.callback<import("node:net").Socket, HostError>((resume) => {
        const socket = tcpConnect({ host: "127.0.0.1", port });
        let open = false;
        socket.on("connect", () => {
          open = true;
          resume(Effect.succeed(socket));
        });
        socket.on("data", (data: Buffer) => Queue.offerUnsafe(incoming, new Uint8Array(data)));
        socket.on("end", () => Queue.offerUnsafe(incoming, null));
        socket.on("close", () => Queue.offerUnsafe(incoming, null));
        socket.on("error", (e) => {
          if (!open) resume(Effect.fail(new HostError(e.message)));
          else Queue.offerUnsafe(incoming, new HostError(e.message));
        });
        return Effect.sync(() => socket.destroy());
      }),
      (socket) => Effect.sync(() => socket.destroy()),
    );
    return {
      read: { take: Effect.flatMap(Queue.take(incoming), (v) => (v instanceof HostError ? Effect.fail(v) : Effect.succeed(v))) },
      write: (bytes: Uint8Array) =>
        Effect.callback<void, HostError>((resume) => {
          socket.write(bytes, (e) => resume(e ? Effect.fail(new HostError(e.message)) : Effect.void));
        }),
      end: () => socket.end(),
    };
  });
}
