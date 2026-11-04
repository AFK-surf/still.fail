import { setMaxListeners } from "node:events";
import { Worker } from "node:worker_threads";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { releaseStoppedBackfill } from "../store/backfill.ts";

type Waiter = { resolve: () => void; reject: (error: Error) => void; done: () => void };
const IDLE_MS = 5_000;

/// The requested chats alone; concurrent readers share each chat's progress. A long old run gives the next chat and
/// foreground writes a turn after every slice. Work stops when nobody waits for it.
export class SaidBuilder {
  readonly #path: string;
  readonly #options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer };
  readonly #workerFile: URL | undefined;
  readonly #timers = new Fibers("sidebar said state");
  readonly #waiting = new Map<number, Set<Waiter>>();
  #worker: Worker | null = null;
  #current: number | null = null;
  #previousReady = false;
  #previousWaiting = false;
  #closed = false;
  #retry: (() => void) | null = null;
  #idle: (() => void) | null = null;
  #retryMs = 250;

  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    this.#path = path; this.#options = options; this.#workerFile = workerFile;
  }

  ready(threads: readonly number[], signal?: AbortSignal): Promise<void> {
    if (this.#closed) return Promise.reject(new Error("station stopping"));
    if (signal?.aborted) return Promise.reject(new Error("read cancelled"));
    const cancel = new AbortController();
    setMaxListeners(0, cancel.signal);
    const abort = () => cancel.abort();
    signal?.addEventListener("abort", abort, { once: true });
    return Promise.all([...new Set(threads)].map((thread) => this.#readyThread(thread, cancel.signal)))
      .then(() => {})
      .catch((error: unknown) => { cancel.abort(); throw error; })
      .finally(() => signal?.removeEventListener("abort", abort));
  }

  #readyThread(thread: number, signal: AbortSignal): Promise<void> {
    return new Promise((resolve, reject) => {
      let waiters = this.#waiting.get(thread);
      if (!waiters) { waiters = new Set(); this.#waiting.set(thread, waiters); }
      const group = waiters;
      const abort = () => { waiter.done(); reject(new Error("read cancelled")); this.#pump(); };
      const waiter: Waiter = { resolve, reject, done: () => {
        signal.removeEventListener("abort", abort);
        group.delete(waiter);
        if (group.size === 0 && this.#waiting.get(thread) === group) this.#waiting.delete(thread);
      } };
      group.add(waiter);
      signal.addEventListener("abort", abort, { once: true });
      this.#pump();
    });
  }

  #fail(thread: number, error: Error): void {
    const waiters = this.#waiting.get(thread);
    this.#waiting.delete(thread);
    if (waiters) for (const waiter of [...waiters]) { waiter.done(); waiter.reject(error); }
  }

  #answer(result: { done: boolean; error?: string }): void {
    const thread = this.#current;
    this.#current = null;
    if (this.#closed || thread === null) return;
    if (result.error) this.#fail(thread, new Error(result.error));
    else {
      const waiters = this.#waiting.get(thread);
      if (waiters && result.done) for (const waiter of [...waiters]) { waiter.done(); waiter.resolve(); }
      else if (waiters) { this.#waiting.delete(thread); this.#waiting.set(thread, waiters); }
      this.#retryMs = 250;
    }
    if (!this.#waiting.has(thread) && !result.done) this.#worker?.postMessage({ thread, cancel: true });
    this.#pump();
  }

  #pump(): void {
    if (this.#closed || this.#current !== null || this.#retry !== null) return;
    if (this.#waiting.size === 0) {
      if (this.#worker !== null && this.#idle === null) {
        const worker = this.#worker;
        this.#idle = this.#timers.after(IDLE_MS, () => {
          this.#idle = null;
          if (this.#worker === worker && this.#current === null && this.#waiting.size === 0) {
            this.#worker = null; void worker.terminate();
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
      }, (error) => {
        this.#previousWaiting = false;
        for (const thread of [...this.#waiting.keys()]) this.#fail(thread, error instanceof Error ? error : new Error(String(error)));
      });
      return;
    }
    if (this.#worker === null) {
      const file = this.#workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./said-worker.ts" : "./read/said-worker.js", import.meta.url);
      let worker: Worker;
      try { worker = new Worker(file, { workerData: { path: this.#path, priority: this.#options.priority }, resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 8 } }); }
      catch (error) { for (const thread of [...this.#waiting.keys()]) this.#fail(thread, error instanceof Error ? error : new Error(String(error))); return; }
      const owner = worker.threadId;
      this.#worker = worker;
      worker.unref();
      worker.on("message", (result: { done: boolean; error?: string }) => { if (this.#worker === worker) this.#answer(result); });
      worker.once("error", (error) => log.warn("readers", "the sidebar state worker failed", { error: error.message }));
      worker.once("exit", () => {
        releaseStoppedBackfill(this.#options.priority, owner);
        if (this.#worker !== worker) return;
        this.#worker = null; this.#current = null;
        if (this.#idle !== null) { this.#idle(); this.#idle = null; }
        if (this.#closed || this.#waiting.size === 0) return;
        const ms = this.#retryMs;
        this.#retryMs = Math.min(ms * 2, 30_000);
        this.#retry = this.#timers.after(ms, () => { this.#retry = null; this.#pump(); });
      });
    }
    const thread = this.#waiting.keys().next().value as number | undefined;
    if (thread !== undefined) { this.#current = thread; this.#worker.postMessage({ thread }); }
  }

  async close(): Promise<void> {
    if (this.#closed) return;
    this.#closed = true;
    this.#retry?.(); this.#retry = null;
    this.#idle?.(); this.#idle = null;
    for (const thread of [...this.#waiting.keys()]) this.#fail(thread, new Error("station stopping"));
    const worker = this.#worker; this.#worker = null;
    if (worker !== null) await worker.terminate();
    await this.#timers.close();
  }
}
