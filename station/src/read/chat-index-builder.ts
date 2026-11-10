import { Worker } from "node:worker_threads";
import { log } from "../ops/log.ts";
import { Fibers } from "../ops/fibers.ts";
import { giveBackfill, releaseStoppedBackfill, takeBackfill } from "../store/backfill.ts";
import { outflowChatScopes } from "../store/outflow-index.ts";
import type { InWorkspace } from "../store/rows.ts";
import { MbProcess, mbReaderBinary } from "./mb-reader.ts";

type Waiter = { resolve: () => void; reject: (error: Error) => void; done: () => void };
const IDLE_MS = 5_000;
/// The pause after a batch that did not finish, as the worker makes it, for the station's other work.
const PAUSE_MS = 20;
/// What stands for the MoonBit builder in the backfill permit (a worker's thread id there): never a thread's.
let nextOwner = 0x50000000;

/// Work only while a program is waiting. Concurrent requests share each scope's bounded work. By the MoonBit builder
/// (station/mb, src/outflow) where its program is there, the pool taking the backfill permit for it around each batch
/// (read/requested-builder.ts does the same); else by the worker; a worker of its own given, by that one.
export class OutflowChatIndex {
  #worker: Worker | MbProcess | null = null;
  readonly #mb: string | null;
  #owner = 0;
  #holding = false;
  #current: string | null = null;
  #waiting = new Map<string, Set<Waiter>>();
  #closed = false;
  #previousReady = false;
  #previousWaiting = false;
  #retry: (() => void) | null = null;
  #idle: (() => void) | null = null;
  #retryMs = 250;
  readonly #timers = new Fibers("outflow chat index");
  readonly #path: string;
  readonly #options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer };
  readonly #workerFile: URL | undefined;

  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL, mb = workerFile === undefined ? mbReaderBinary() : null) {
    this.#path = path;
    this.#options = options;
    this.#workerFile = workerFile;
    this.#mb = mb;
  }

  #priority(): Int32Array | null {
    return this.#options.priority instanceof SharedArrayBuffer ? new Int32Array(this.#options.priority) : null;
  }

  ready(viewer: InWorkspace, signal?: AbortSignal): Promise<void> {
    return Promise.all(outflowChatScopes(viewer).map((scope) => this.#readyScope(scope, signal))).then(() => {});
  }

  #readyScope(scope: string, signal?: AbortSignal): Promise<void> {
    if (this.#closed) return Promise.reject(new Error("station stopping"));
    if (signal?.aborted) return Promise.reject(new Error("read cancelled"));
    return new Promise((resolve, reject) => {
      let group = this.#waiting.get(scope);
      if (!group) { group = new Set(); this.#waiting.set(scope, group); }
      const waiters = group;
      const abort = () => { waiter.done(); reject(new Error("read cancelled")); this.#pump(); };
      const waiter: Waiter = { resolve, reject, done: () => {
        signal?.removeEventListener("abort", abort);
        waiters.delete(waiter);
        if (waiters.size === 0 && this.#waiting.get(scope) === waiters) this.#waiting.delete(scope);
      } };
      waiters.add(waiter);
      signal?.addEventListener("abort", abort, { once: true });
      this.#pump();
    });
  }

  #fail(error: Error): void {
    for (const waiters of [...this.#waiting.values()]) for (const waiter of [...waiters]) { waiter.done(); waiter.reject(error); }
  }

  #pump(): void {
    if (this.#closed || this.#current !== null || this.#retry !== null) return;
    if (this.#waiting.size === 0) {
      if (this.#worker !== null && this.#idle === null) {
        const worker = this.#worker;
        this.#idle = this.#timers.after(IDLE_MS, () => {
          this.#idle = null;
          if (this.#worker === worker && this.#current === null && this.#waiting.size === 0) {
            this.#worker = null;
            void worker.terminate();
          }
        });
      }
      return;
    }
    if (this.#idle !== null) { this.#idle(); this.#idle = null; }
    if (!this.#previousReady) {
      if (this.#previousWaiting) return;
      this.#previousWaiting = true;
      void (this.#options.previousGone ?? Promise.resolve()).then(() => {
        this.#previousReady = true; this.#previousWaiting = false; this.#pump();
      }, (error) => { this.#previousWaiting = false; this.#fail(error instanceof Error ? error : new Error(String(error))); });
      return;
    }
    if (this.#worker === null && this.#mb !== null) {
      const mb = new MbProcess(this.#mb, ["--builder", "outflow-chats", "--db", this.#path]);
      const owner = this.#owner = nextOwner++;
      this.#worker = mb;
      mb.on("message", (result: { done: boolean; error?: string }) => {
        if (this.#worker !== mb || this.#closed) return;
        if (this.#holding) { this.#holding = false; giveBackfill(this.#priority(), owner); }
        if (!result.done && !result.error) this.#timers.after(PAUSE_MS, () => { if (this.#worker === mb && !this.#closed) this.#answer(result); });
        else this.#answer(result);
      });
      mb.once("error", (error: Error) => log.warn("outflow", "the chat order builder failed", { error: error.message }));
      mb.once("exit", () => {
        releaseStoppedBackfill(this.#options.priority, owner);
        this.#holding = false;
        this.#gone(mb);
      });
    }
    if (this.#worker === null) {
      const file = this.#workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./chat-index-worker.ts" : "./read/chat-index-worker.js", import.meta.url);
      let worker: Worker;
      try { worker = new Worker(file, { workerData: { path: this.#path, priority: this.#options.priority }, resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 8 } }); }
      catch (error) { this.#fail(error instanceof Error ? error : new Error(String(error))); return; }
      const owner = worker.threadId;
      this.#worker = worker;
      worker.unref();
      worker.on("message", (result: { done: boolean; error?: string }) => {
        if (this.#worker !== worker || this.#closed) return;
        this.#answer(result);
      });
      worker.once("error", (error) => log.warn("outflow", "the chat order worker failed", { error: error.message }));
      worker.once("exit", () => {
        releaseStoppedBackfill(this.#options.priority, owner);
        this.#gone(worker);
      });
    }
    const scope = this.#waiting.keys().next().value as string | undefined;
    if (scope === undefined) return;
    this.#current = scope;
    const worker = this.#worker;
    if (!(worker instanceof MbProcess)) return void worker.postMessage(scope);
    // (the MoonBit builder asked once it holds the permit, as the worker takes it itself; without it, not done)
    if (!takeBackfill(this.#priority(), this.#owner)) {
      this.#timers.after(PAUSE_MS, () => { if (this.#worker === worker && !this.#closed) this.#answer({ done: false }); });
      return;
    }
    this.#holding = true;
    worker.postMessage({ scope });
  }

  /// A batch answered: an error fails every request; a scope done resolves its own, one not done goes to the back.
  #answer(result: { done: boolean; error?: string }): void {
    const scope = this.#current;
    this.#current = null;
    if (result.error) {
      this.#fail(new Error(result.error));
      this.#pump();
      return;
    }
    this.#retryMs = 250;
    const waiters = scope === null ? undefined : this.#waiting.get(scope);
    if (scope !== null && waiters) {
      if (result.done) for (const waiter of [...waiters]) { waiter.done(); waiter.resolve(); }
      else { this.#waiting.delete(scope); this.#waiting.set(scope, waiters); }
    }
    this.#pump();
  }

  /// The worker or builder process ended: what it held is asked again of another, after a growing wait.
  #gone(worker: Worker | MbProcess): void {
    if (this.#worker !== worker) return;
    this.#worker = null;
    this.#current = null;
    if (this.#idle !== null) { this.#idle(); this.#idle = null; }
    if (this.#closed || this.#waiting.size === 0) return;
    const ms = this.#retryMs;
    this.#retryMs = Math.min(ms * 2, 30_000);
    this.#retry = this.#timers.after(ms, () => { this.#retry = null; this.#pump(); });
  }

  async close(): Promise<void> {
    if (this.#closed) return;
    this.#closed = true;
    if (this.#retry !== null) this.#retry();
    this.#retry = null;
    if (this.#idle !== null) this.#idle();
    this.#idle = null;
    this.#fail(new Error("station stopping"));
    const worker = this.#worker;
    this.#worker = null;
    if (worker !== null) await worker.terminate();
    await this.#timers.close();
  }
}
