// The core in a browser's worker (web/src/core/worker.ts): the Host over the worker's own fetch, WebSocket, IndexedDB,
// crypto and clocks, as the Rust core's wasm host kept them — the same IndexedDB database (`stillfail-core`, its `values` by
// key and `records` by [table, key]; what `ember-core` had copied over on the first open) — so a browser moving from the
// Rust core keeps its logins and what it had read. Its iroh is client/iroh-wasm (relay only), loaded while the core
// starts from its database.
import { Effect, Queue, type Scope } from "effect";
import { Core } from "../core.ts";
import { HostError } from "../error.ts";
import type { BindOptions, Iroh } from "../iroh.ts";
import { type BoundEndpoint, wrapIroh } from "../iroh-bindings.ts";
import { SOCKET_PING, SOCKET_PING_MS, type DbOp, type DbRange, type Host, type HttpRequest, type HttpResponse, type Pull, type StreamResponse } from "../host.ts";
import { t } from "../i18n.ts";
import type { ClientId, CoreMessage } from "../protocol.ts";
import { service } from "../trace.ts";

const DATABASE = "stillfail-core";
/// Its name before the rename: what a browser that ran the core then has, copied over on the first open.
const FORMER_DATABASE = "ember-core";
const VERSION = 2;
const STORE = "values";
const RECORDS = "records";

/// What client/iroh-wasm's module gives (web/src/core/iroh-pkg).
export type IrohModule = { bind(options: { secretKey: Uint8Array; relayUrls: string[] }): Promise<unknown> };

const failed = (e: unknown) => new HostError(e instanceof Error ? e.message : e instanceof DOMException ? e.message : String(e));

/// One request's result.
function done<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(new HostError(request.error?.message ?? t("core-misc.host.idb.failed")));
  });
}

/// Once a write is durable, not merely queued.
function committed(tx: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(new HostError(tx.error?.message ?? t("core-misc.host.idb.unwritten")));
    tx.onabort = () => reject(new HostError(tx.error?.message ?? t("core-misc.host.idb.unwritten")));
  });
}

type Rows = [string, [IDBValidKey, unknown][]][];

/// Opens `name` (at `version`, or the one it has). One not there yet is made (its stores, filled with `rows`) only
/// when `create`; otherwise the upgrade is aborted, which leaves no database behind, and it is null.
function openAt(name: string, version: number | undefined, rows: Rows, create: boolean): Promise<IDBDatabase | null> {
  return new Promise((resolve, reject) => {
    const request = version === undefined ? indexedDB.open(name) : indexedDB.open(name, version);
    let absent = false;
    request.onupgradeneeded = (event) => {
      const tx = request.transaction;
      if (!tx) return;
      if (event.oldVersion === 0 && !create) {
        absent = true;
        tx.abort();
        return;
      }
      // Version 1 made `values`; version 2 adds `records`. Each store is made if it is not there yet.
      const db = request.result;
      for (const store of [STORE, RECORDS]) if (!db.objectStoreNames.contains(store)) db.createObjectStore(store);
      if (event.oldVersion === 0) {
        for (const [store, items] of rows) {
          const os = tx.objectStore(store);
          for (const [key, value] of items) os.put(value, key);
        }
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => {
      if (absent) resolve(null);
      else reject(new HostError(request.error?.message ?? t("core-misc.host.idb.failed")));
    };
  });
}

/// What the database had under its name from before the rename, if this browser has it (left as it was).
async function formerRows(): Promise<Rows> {
  const db = await openAt(FORMER_DATABASE, undefined, [], false);
  if (!db) return [];
  const rows: Rows = [];
  for (const store of [STORE, RECORDS]) {
    if (!db.objectStoreNames.contains(store)) continue;
    const os = db.transaction(store).objectStore(store);
    const keys = await done(os.getAllKeys());
    const values = await done(os.getAll());
    rows.push([store, keys.map((k, i) => [k, values[i]] as [IDBValidKey, unknown])]);
  }
  db.close();
  return rows;
}

async function openDatabase(): Promise<IDBDatabase> {
  if (typeof indexedDB === "undefined") throw new HostError(t("core-misc.host.idb.missing"));
  // The first open under the new name fills it with what the former one has (read first: the upgrade that makes the
  // stores puts the rows in the same transaction, so no other tab sees it made and empty).
  let db = await openAt(DATABASE, VERSION, [], false);
  if (!db) db = await openAt(DATABASE, VERSION, await formerRows(), true);
  if (!db) throw new HostError(t("core-misc.host.idb.unopened"));
  // Another tab upgrading the schema later must not be blocked by us.
  const opened = db;
  opened.onversionchange = () => opened.close();
  return opened;
}

const bytesOf = (v: unknown): Uint8Array => (v instanceof Uint8Array ? v : v instanceof ArrayBuffer ? new Uint8Array(v) : new Uint8Array(v as ArrayLike<number>));

export class WebHost implements Host {
  readonly #emit: (client: ClientId, message: unknown) => void;
  readonly #testChannel: boolean;
  #db: Promise<IDBDatabase> | null = null;

  constructor(emit: (client: ClientId, message: unknown) => void, testChannel: boolean) {
    this.#emit = emit;
    this.#testChannel = testChannel;
  }

  cloudOrigin(): string {
    return (globalThis as { location?: { origin?: string } }).location?.origin ?? "";
  }
  beta(): boolean {
    return false;
  }
  testChannel(): boolean {
    return this.#testChannel;
  }

  fetch(request: HttpRequest): Effect.Effect<HttpResponse, HostError> {
    return Effect.tryPromise({
      try: async (signal) => {
        const response = await fetch(request.url, { method: request.method, headers: request.headers, body: (request.body ?? undefined) as BodyInit | undefined, signal });
        return { status: response.status, headers: [...response.headers.entries()], body: new Uint8Array(await response.arrayBuffer()) };
      },
      catch: failed,
    });
  }

  fetchStream(request: HttpRequest): Effect.Effect<StreamResponse, HostError, Scope.Scope> {
    return Effect.gen(function* () {
      const abort = new AbortController();
      // An event stream the core lets go of does not stay open.
      yield* Effect.addFinalizer(() => Effect.sync(() => abort.abort()));
      const response = yield* Effect.tryPromise({
        try: () => fetch(request.url, { method: request.method, headers: request.headers, body: (request.body ?? undefined) as BodyInit | undefined, signal: abort.signal }),
        catch: failed,
      });
      const reader = response.body?.getReader();
      const body: Pull<Uint8Array> = {
        take: reader
          ? Effect.tryPromise({
              try: async () => {
                const { done: end, value } = await reader.read();
                return end ? null : value;
              },
              catch: failed,
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
          socket.onopen = () => {
            open = true;
            resume(Effect.succeed(socket));
          };
          socket.onmessage = (event) => {
            if (typeof event.data === "string") Queue.offerUnsafe(frames, event.data);
          };
          // Before it opened, a close is a refusal; after, the end of the frames.
          socket.onclose = (event) => {
            if (!open) resume(Effect.fail(new HostError(`websocket refused (${event.code})`)));
            else Queue.offerUnsafe(frames, null);
          };
          return Effect.sync(() => socket.close());
        }),
        (socket) =>
          Effect.sync(() => {
            socket.onopen = socket.onmessage = socket.onclose = null;
            socket.close();
          }),
      );
      // `ping` every SOCKET_PING_MS while it is open (host.rs).
      yield* Effect.forkScoped(
        Effect.forever(Effect.sleep(SOCKET_PING_MS).pipe(Effect.andThen(Effect.sync(() => socket.readyState === WebSocket.OPEN && socket.send(SOCKET_PING))))),
      );
      return { take: Effect.flatMap(Queue.take(frames), (v) => (v instanceof HostError ? Effect.fail(v) : Effect.succeed(v))) };
    });
  }

  resetConnections(): void {}

  /// The database, opened once on first use; a failed open is tried again by the next use, and one the browser
  /// closed under us (storage cleared, Safari evicting) is opened again.
  #tx(store: string, mode: IDBTransactionMode): Effect.Effect<IDBTransaction, HostError> {
    return Effect.tryPromise({
      try: async () => {
        this.#db ??= openDatabase();
        let db: IDBDatabase;
        try {
          db = await this.#db;
        } catch (e) {
          this.#db = null;
          throw e;
        }
        try {
          return db.transaction(store, mode);
        } catch {
          this.#db = openDatabase();
          return (await this.#db).transaction(store, mode);
        }
      },
      catch: failed,
    });
  }

  storageGet(key: string): Effect.Effect<Uint8Array | null, HostError> {
    return Effect.flatMap(this.#tx(STORE, "readonly"), (tx) =>
      Effect.tryPromise({ try: async () => {
        const value = await done(tx.objectStore(STORE).get(key));
        return value === undefined ? null : bytesOf(value);
      }, catch: failed }),
    );
  }

  storageSet(key: string, value: Uint8Array): Effect.Effect<void, HostError> {
    return Effect.flatMap(this.#tx(STORE, "readwrite"), (tx) =>
      Effect.tryPromise({ try: () => {
        tx.objectStore(STORE).put(value, key);
        return committed(tx);
      }, catch: failed }),
    );
  }

  storageDelete(key: string): Effect.Effect<void, HostError> {
    return Effect.flatMap(this.#tx(STORE, "readwrite"), (tx) =>
      Effect.tryPromise({ try: () => {
        tx.objectStore(STORE).delete(key);
        return committed(tx);
      }, catch: failed }),
    );
  }

  dbRead(range: DbRange): Effect.Effect<[string, Uint8Array][], HostError> {
    return Effect.flatMap(this.#tx(RECORDS, "readonly"), (tx) =>
      Effect.tryPromise({ try: async () => {
        const store = tx.objectStore(RECORDS);
        const bounds = IDBKeyRange.bound([range.table, range.from], [range.table, range.to], false, true);
        // Both in key order, in one transaction: they line up.
        const keys = await done(store.getAllKeys(bounds));
        const values = await done(store.getAll(bounds));
        return keys.map((k, i) => [String((k as IDBValidKey[])[1]), bytesOf(values[i])] as [string, Uint8Array]);
      }, catch: failed }),
    );
  }

  dbWrite(ops: DbOp[]): Effect.Effect<void, HostError> {
    return Effect.flatMap(this.#tx(RECORDS, "readwrite"), (tx) =>
      Effect.tryPromise({ try: () => {
        const store = tx.objectStore(RECORDS);
        for (const op of ops) {
          if ("put" in op) store.put(op.put.value, [op.put.table, op.put.key]);
          else store.delete([op.delete.table, op.delete.key]);
        }
        return committed(tx);
      }, catch: failed }),
    );
  }

  nowMs(): number {
    return Date.now();
  }
  /// Sub-millisecond and never set back, unlike Date.now().
  monotonicMs(): number {
    return performance.now();
  }
  utcOffsetMin(atMs: number): number {
    return -new Date(atMs).getTimezoneOffset();
  }
  randomBytes(buf: Uint8Array): void {
    // getRandomValues fills at most 64 KiB per call.
    for (let at = 0; at < buf.length; at += 65536) crypto.getRandomValues(buf.subarray(at, Math.min(at + 65536, buf.length)) as Uint8Array<ArrayBuffer>);
  }

  emit(client: ClientId, message: CoreMessage): void {
    // An error crosses as its JSON (`{code, message, status?}`): a structured clone of it would lose its code.
    this.#emit(client, "error" in message ? { id: message.id, error: message.error.toJSON() } : message);
  }
}

/// client/iroh-wasm as the core's iroh: loaded (`load`) the first time the mesh binds.
export function webIroh(load: () => Promise<IrohModule>): Iroh {
  return wrapIroh(async (o: BindOptions) => (await load()).bind({ secretKey: o.secretKey, relayUrls: o.relayUrls }) as Promise<BoundEndpoint>, (b) => b);
}

/// A core in this worker: one client per port.
export type WebCore = { connect(): number; disconnect(client: number): void; receive(client: number, message: unknown): void };

/// A core in this worker (as the Rust core's wasm `start` was): `emit(client, message)` gets what it says to each client;
/// `testChannel` the page is the test channel's. A bug that ends a fiber ends it as a panic ended the Rust core's:
/// `onFatal` is told, and the worker tells the pages and closes.
export function startWeb(emit: (client: ClientId, message: unknown) => void, testChannel: boolean, loadIroh: () => Promise<IrohModule>, onFatal: (reason: string) => void): Promise<WebCore> {
  service.name = "stillfail-web";
  service.os = "browser";
  const host = new WebHost(emit, testChannel);
  return Core.create(host, { iroh: webIroh(loadIroh) }).then((core) => {
    core.inner.runner.onDefect = (error) => onFatal(t("core-misc.host.crashed", { reason: error instanceof Error ? error.message : String(error) }));
    core.keepTime();
    return {
      connect: (): number => core.connect(),
      disconnect: (client: number): void => core.disconnect(client),
      receive: (client: number, message: unknown): void => core.receiveRaw(client, message),
    };
  });
}
