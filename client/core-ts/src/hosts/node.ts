// The core on Node (the desktop app's utility process; tests and the side-by-side runs): the Host over fetch, the `ws`
// package, node:sqlite and files, as client/ffi's native host does it — the same data directory, the same file per
// storage key (`%XX` for what a file name cannot hold), the same `core.db` — so a desktop app moving from the Rust
// core keeps its logins and what it had read. `start` is client/node's API: connect / receive(json) / disconnect,
// the listener given `(client, json)`.
import { mkdirSync, readFileSync, renameSync, rmSync, writeFileSync, openSync, fsyncSync, closeSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { webcrypto } from "node:crypto";
import WebSocket from "ws";
import { Core } from "../core.ts";
import { HostError } from "../error.ts";
import { BaseHost, SOCKET_PING, SOCKET_PING_MS, type Chunks, type DbOp, type DbRange, type HttpRequest, type HttpResponse, type SocketFrames, type StreamResponse } from "../host.ts";
import type { ClientId, CoreMessage } from "../protocol.ts";
import { service } from "../trace.ts";

export type Listener = (client: ClientId, json: string) => void;

export class NodeHost extends BaseHost {
  readonly #origin: string;
  readonly #beta: boolean;
  readonly #dir: string;
  #db: DatabaseSync | null = null;
  /// Writes in the order they were asked for.
  #writes: Promise<void> = Promise.resolve();
  #listener: Listener;
  readonly #started = performance.now();
  /// Requests in flight, let go when the connections are taken for gone (`resetConnections`).
  #aborts = new Set<AbortController>();

  constructor(dataDir: string, cloudOrigin: string, beta: boolean, listener: Listener) {
    super();
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

  async fetch(request: HttpRequest): Promise<HttpResponse> {
    const abort = new AbortController();
    this.#aborts.add(abort);
    try {
      const response = await fetch(request.url, { method: request.method, headers: request.headers, body: (request.body ?? undefined) as BodyInit | undefined, signal: abort.signal, redirect: "manual" });
      const body = new Uint8Array(await response.arrayBuffer());
      return { status: response.status, headers: [...response.headers.entries()], body };
    } catch (e) {
      throw new HostError(fetchError(e));
    } finally {
      this.#aborts.delete(abort);
    }
  }

  async fetchStream(request: HttpRequest): Promise<StreamResponse> {
    const abort = new AbortController();
    let response: Response;
    try {
      response = await fetch(request.url, { method: request.method, headers: request.headers, body: (request.body ?? undefined) as BodyInit | undefined, signal: abort.signal });
    } catch (e) {
      throw new HostError(fetchError(e));
    }
    const reader = response.body?.getReader();
    const body: Chunks = {
      async next() {
        if (!reader) return null;
        try {
          const { done, value } = await reader.read();
          return done ? null : value;
        } catch (e) {
          throw new HostError(fetchError(e));
        }
      },
      close() {
        abort.abort();
      },
    };
    return { status: response.status, headers: [...response.headers.entries()], body };
  }

  websocket(url: string, protocols: string[]): Promise<SocketFrames> {
    return new Promise((resolve, reject) => {
      const socket = new WebSocket(url, protocols);
      const queue: (string | null | HostError)[] = [];
      let waiting: ((v: string | null | HostError) => void) | null = null;
      let ping: ReturnType<typeof setInterval> | null = null;
      let open = false;
      const push = (v: string | null | HostError) => {
        if (waiting) {
          const w = waiting;
          waiting = null;
          w(v);
        } else queue.push(v);
      };
      socket.on("open", () => {
        open = true;
        // The host's ping (host.rs SOCKET_PING_MS): still.fail cloud answers `pong`.
        ping = setInterval(() => socket.send(SOCKET_PING), SOCKET_PING_MS);
        resolve({
          async next() {
            const v = queue.length > 0 ? queue.shift()! : await new Promise<string | null | HostError>((r) => (waiting = r));
            if (v instanceof HostError) throw v;
            return v;
          },
          close() {
            if (ping) clearInterval(ping);
            socket.close();
          },
        });
      });
      socket.on("message", (data, binary) => {
        if (!binary) push(data.toString());
      });
      socket.on("close", () => {
        if (ping) clearInterval(ping);
        push(null);
      });
      socket.on("unexpected-response", (_req, res) => {
        reject(new HostError(`websocket refused (${res.statusCode})`));
        socket.terminate();
      });
      socket.on("error", (e) => {
        if (!open) reject(new HostError(`websocket: ${e.message}`));
        else push(new HostError(`websocket: ${e.message}`));
      });
    });
  }

  resetConnections(): void {
    // Requests already on the old connections keep them until they end (the core fails those it takes for gone).
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

  #queue<T>(job: () => T): Promise<T> {
    const run = this.#writes.then(job);
    this.#writes = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }

  storageGet(key: string): Promise<Uint8Array | null> {
    return this.#queue(() => {
      try {
        return new Uint8Array(readFileSync(this.path(key)));
      } catch (e) {
        if ((e as NodeJS.ErrnoException).code === "ENOENT") return null;
        throw new HostError(`读不了：${(e as Error).message}`);
      }
    });
  }

  storageSet(key: string, value: Uint8Array): Promise<void> {
    return this.#queue(() => {
      // Written aside and renamed over: a crash leaves the old value or the new one, never half.
      const path = this.path(key);
      const partial = `${path}.partial`;
      writeFileSync(partial, value);
      const fd = openSync(partial, "r");
      try {
        fsyncSync(fd);
      } finally {
        closeSync(fd);
      }
      renameSync(partial, path);
    });
  }

  storageDelete(key: string): Promise<void> {
    return this.#queue(() => rmSync(this.path(key), { force: true }));
  }

  #open(): DatabaseSync {
    if (!this.#db) {
      const db = new DatabaseSync(join(this.#dir, "core.db"), { timeout: 5000 });
      db.exec("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; CREATE TABLE IF NOT EXISTS records (tbl TEXT NOT NULL, key TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY (tbl, key)) WITHOUT ROWID;");
      this.#db = db;
    }
    return this.#db;
  }

  dbRead(range: DbRange): Promise<[string, Uint8Array][]> {
    return this.#queue(() => {
      const rows = this.#open().prepare("SELECT key, value FROM records WHERE tbl = ? AND key >= ? AND key < ? ORDER BY key").all(range.table, range.from, range.to) as { key: string; value: Uint8Array }[];
      return rows.map((r) => [r.key, new Uint8Array(r.value)] as [string, Uint8Array]);
    });
  }

  dbWrite(ops: DbOp[]): Promise<void> {
    return this.#queue(() => {
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
        throw new HostError(`数据库出错：${(e as Error).message}`);
      }
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

function fetchError(e: unknown): string {
  // undici says "fetch failed" and keeps the cause: say what failed.
  let message = e instanceof Error ? e.message : String(e);
  let cause = e instanceof Error ? (e as { cause?: unknown }).cause : undefined;
  while (cause instanceof Error) {
    message += `: ${cause.message}`;
    cause = (cause as { cause?: unknown }).cause;
  }
  return message;
}

/// client/node's `start`: a core whose messages go to `listener(client, json)`; `channel` "beta" for a beta app's.
export function start(dataDir: string, cloudOrigin: string, listener: Listener, channel?: string) {
  service.name = "stillfail-native";
  service.os = process.platform === "darwin" ? "macos" : process.platform;
  const host = new NodeHost(dataDir, cloudOrigin, channel === "beta", listener);
  // Messages that arrive while the core starts wait, in order (client/ffi's queue).
  const ready = Core.create(host).then((core) => {
    core.keepTime();
    return core;
  });
  let next = 1;
  let chain: Promise<unknown> = ready;
  const later = (job: (core: Core) => void) => {
    chain = chain.then(() => ready.then(job));
  };
  return {
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
    async close(): Promise<void> {
      (await ready).close();
      host.close();
    },
  };
}
