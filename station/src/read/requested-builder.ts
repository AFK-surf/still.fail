import { setMaxListeners } from "node:events";
import { Worker } from "node:worker_threads";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { releaseStoppedBackfill } from "../store/backfill.ts";

type Waiter = { resolve: () => void; reject: (error: Error) => void; done: () => void };
const IDLE_MS = 5_000;

/// Requested old state alone; readers share progress, each slice gives other work a turn, and abandoned work stops.
export class RequestedBuilder<K extends number | string> {
  readonly #path: string;
  readonly #options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer };
  readonly #workerFile: URL | undefined;
  readonly #timers: Fibers;
  readonly #field: "thread" | "session" | "scope";
  readonly #message: ((item: K, cancel: boolean) => Record<string, unknown>) | undefined;
  readonly #waiting = new Map<K, Set<Waiter>>();
  #worker: Worker | null = null;
  #current: K | null = null;
  #previousReady = false;
  #previousWaiting = false;
  #closed = false;
  #retry: (() => void) | null = null;
  #idle: (() => void) | null = null;
  #retryMs = 250;

  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer }, workerFile: URL | undefined,
    field: "thread" | "session" | "scope", name: string, message?: (item: K, cancel: boolean) => Record<string, unknown>) {
    this.#path = path; this.#options = options; this.#workerFile = workerFile; this.#field = field; this.#timers = new Fibers(name);
    this.#message = message;
  }

  ready(items: readonly K[], signal?: AbortSignal): Promise<void> {
    if (this.#closed) return Promise.reject(new Error("station stopping"));
    if (signal?.aborted) return Promise.reject(new Error("read cancelled"));
    const cancel = new AbortController();
    setMaxListeners(0, cancel.signal);
    const abort = () => cancel.abort();
    signal?.addEventListener("abort", abort, { once: true });
    return Promise.all([...new Set(items)].map((item) => this.#readyItem(item, cancel.signal)))
      .then(() => {})
      .catch((error: unknown) => { cancel.abort(); throw error; })
      .finally(() => signal?.removeEventListener("abort", abort));
  }

  #readyItem(item: K, signal: AbortSignal): Promise<void> {
    return new Promise((resolve, reject) => {
      let waiters = this.#waiting.get(item);
      if (!waiters) { waiters = new Set(); this.#waiting.set(item, waiters); }
      const group = waiters;
      const abort = () => { waiter.done(); reject(new Error("read cancelled")); this.#pump(); };
      const waiter: Waiter = { resolve, reject, done: () => {
        signal.removeEventListener("abort", abort);
        group.delete(waiter);
        if (group.size === 0 && this.#waiting.get(item) === group) this.#waiting.delete(item);
      } };
      group.add(waiter);
      signal.addEventListener("abort", abort, { once: true });
      this.#pump();
    });
  }

  #fail(item: K, error: Error): void {
    const waiters = this.#waiting.get(item);
    this.#waiting.delete(item);
    if (waiters) for (const waiter of [...waiters]) { waiter.done(); waiter.reject(error); }
  }

  #answer(result: { done: boolean; error?: string }): void {
    const item = this.#current;
    this.#current = null;
    if (this.#closed || item === null) return;
    if (result.error) this.#fail(item, new Error(result.error));
    else {
      const waiters = this.#waiting.get(item);
      if (waiters && result.done) for (const waiter of [...waiters]) { waiter.done(); waiter.resolve(); }
      else if (waiters) { this.#waiting.delete(item); this.#waiting.set(item, waiters); }
      this.#retryMs = 250;
    }
    if (!this.#waiting.has(item) && !result.done) this.#worker?.postMessage(this.#message?.(item, true) ?? { [this.#field]: item, cancel: true });
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
        for (const item of [...this.#waiting.keys()]) this.#fail(item, error instanceof Error ? error : new Error(String(error)));
      });
      return;
    }
    if (this.#worker === null) {
      const file = this.#workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./said-worker.ts" : "./read/said-worker.js", import.meta.url);
      let worker: Worker;
      try { worker = new Worker(file, { workerData: { path: this.#path, priority: this.#options.priority }, resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 8 } }); }
      catch (error) { for (const item of [...this.#waiting.keys()]) this.#fail(item, error instanceof Error ? error : new Error(String(error))); return; }
      const owner = worker.threadId;
      this.#worker = worker;
      worker.unref();
      worker.on("message", (result: { done: boolean; error?: string }) => { if (this.#worker === worker) this.#answer(result); });
      worker.once("error", (error) => log.warn("readers", "an old-state worker failed", { error: error.message }));
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
    const item = this.#waiting.keys().next().value as K | undefined;
    if (item !== undefined) { this.#current = item; this.#worker.postMessage(this.#message?.(item, false) ?? { [this.#field]: item }); }
  }

  async close(): Promise<void> {
    if (this.#closed) return;
    this.#closed = true;
    this.#retry?.(); this.#retry = null;
    this.#idle?.(); this.#idle = null;
    for (const item of [...this.#waiting.keys()]) this.#fail(item, new Error("station stopping"));
    const worker = this.#worker; this.#worker = null;
    if (worker !== null) await worker.terminate();
    await this.#timers.close();
  }
}
