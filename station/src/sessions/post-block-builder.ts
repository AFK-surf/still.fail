import { Worker } from "node:worker_threads";
import { setMaxListeners } from "node:events";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { releaseStoppedBackfill } from "../store/backfill.ts";
import { postBlocksCoverage, postBlocksReady, postBlocksStep } from "../store/post-blocks.ts";
import type { Store } from "../store/store.ts";

type Waiter = { after: number; resolve: () => void; reject: (error: Error) => void; done: () => void };
type Current = { thread: number; after: number };
const IDLE_MS = 5_000;

/// Index only the old thread suffixes a delivery needs. Concurrent deliveries share the work; each step gives other
/// threads and foreground writes a turn. A stopped builder leaves its last committed position for the next station.
export class PostBlockBuilder {
  readonly #store: Store;
  readonly #previous: Promise<void>;
  readonly #workerFile: URL | undefined;
  readonly #timers = new Fibers("post block index");
  readonly #waiting = new Map<number, Set<Waiter>>();
  #worker: Worker | null = null;
  #current: Current | null = null;
  #previousReady = false;
  #previousWaiting = false;
  #closed = false;
  #retry: (() => void) | null = null;
  #idle: (() => void) | null = null;
  #retryMs = 250;

  constructor(store: Store, previous: Promise<void>, workerFile?: URL) {
    this.#store = store;
    this.#previous = previous;
    this.#workerFile = workerFile;
  }

  ready(messages: readonly { thread: number; n: number }[], signal?: AbortSignal): Promise<void> {
    if (this.#closed) return Promise.reject(new Error("station stopping"));
    if (signal?.aborted) return Promise.reject(new Error("delivery cancelled"));
    const threads = new Map<number, number>();
    for (const message of messages) threads.set(message.thread, Math.min(threads.get(message.thread) ?? message.n, message.n));
    const cancel = new AbortController();
    setMaxListeners(0, cancel.signal); // One listener per requested thread, all removed when the delivery settles.
    const abort = () => cancel.abort();
    signal?.addEventListener("abort", abort, { once: true });
    try {
      return Promise.all([...threads].map(([thread, after]) => this.#readyThread(thread, after, cancel.signal)))
        .then(() => {})
        .catch((error: unknown) => { cancel.abort(); throw error; })
        .finally(() => signal?.removeEventListener("abort", abort));
    } catch (error) {
      cancel.abort();
      signal?.removeEventListener("abort", abort);
      return Promise.reject(error);
    }
  }

  #readyThread(thread: number, after: number, signal?: AbortSignal): Promise<void> {
    if (postBlocksReady(this.#store.db, thread, after)) return Promise.resolve();
    return new Promise((resolve, reject) => {
      let waiters = this.#waiting.get(thread);
      if (!waiters) { waiters = new Set(); this.#waiting.set(thread, waiters); }
      const group = waiters;
      const abort = () => { waiter.done(); reject(new Error("delivery cancelled")); this.#pump(); };
      const waiter: Waiter = { after, resolve, reject, done: () => {
        signal?.removeEventListener("abort", abort);
        group.delete(waiter);
        if (group.size === 0 && this.#waiting.get(thread) === group) this.#waiting.delete(thread);
      } };
      group.add(waiter);
      signal?.addEventListener("abort", abort, { once: true });
      this.#pump();
    });
  }

  #fail(thread: number, error: Error): void {
    const waiters = this.#waiting.get(thread);
    this.#waiting.delete(thread);
    if (waiters) for (const waiter of [...waiters]) { waiter.done(); waiter.reject(error); }
  }

  #answer(result: { done: boolean; error?: string }): void {
    const current = this.#current;
    this.#current = null;
    if (this.#closed || current === null) return;
    if (result.error) this.#fail(current.thread, new Error(result.error));
    else {
      const waiters = this.#waiting.get(current.thread);
      if (waiters) {
        try {
          const { complete, cursor } = postBlocksCoverage(this.#store.db, current.thread);
          for (const waiter of [...waiters]) {
            if (!complete && (cursor === null || cursor > waiter.after + 1)) continue;
            waiter.done();
            waiter.resolve();
          }
        } catch (error) {
          this.#fail(current.thread, error instanceof Error ? error : new Error(String(error)));
        }
        if (this.#waiting.get(current.thread) === waiters) {
          this.#waiting.delete(current.thread);
          if (waiters.size !== 0) this.#waiting.set(current.thread, waiters);
        }
      }
      this.#retryMs = 250;
    }
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
      void this.#previous.then(() => {
        this.#previousReady = true;
        this.#previousWaiting = false;
        this.#pump();
      }, (error) => {
        this.#previousWaiting = false;
        for (const thread of [...this.#waiting.keys()]) this.#fail(thread, error instanceof Error ? error : new Error(String(error)));
      });
      return;
    }
    const [thread, waiters] = this.#waiting.entries().next().value as [number, Set<Waiter>];
    let after = Infinity;
    for (const waiter of waiters) after = Math.min(after, waiter.after);
    const current = { thread, after };
    this.#current = current;
    const path = this.#store.db.location();
    if (path === null) {
      this.#retry = this.#timers.after(20, () => {
        this.#retry = null;
        try { this.#answer(postBlocksStep(this.#store.db, thread, current.after)); }
        catch (error) { this.#answer({ done: false, error: (error as Error).message }); }
      });
      return;
    }
    if (this.#worker === null) {
      const file = this.#workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./post-block-worker.ts" : "./sessions/post-block-worker.js", import.meta.url);
      let worker: Worker;
      try { worker = new Worker(file, { workerData: { path, priority: this.#store.backfillPriority }, resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 8 } }); }
      catch (error) { this.#answer({ done: false, error: (error as Error).message }); return; }
      const owner = worker.threadId;
      this.#worker = worker;
      worker.unref();
      worker.on("message", (result: { done: boolean; error?: string }) => { if (this.#worker === worker) this.#answer(result); });
      worker.once("error", (error) => log.warn("hub", "the post block worker failed", { error: error.message }));
      worker.once("exit", () => {
        releaseStoppedBackfill(this.#store.backfillPriority, owner);
        if (this.#worker !== worker) return;
        this.#worker = null;
        this.#current = null;
        if (this.#idle !== null) { this.#idle(); this.#idle = null; }
        if (this.#closed || this.#waiting.size === 0) return;
        const ms = this.#retryMs;
        this.#retryMs = Math.min(ms * 2, 30_000);
        this.#retry = this.#timers.after(ms, () => { this.#retry = null; this.#pump(); });
      });
    }
    this.#worker.postMessage(current);
  }

  async close(): Promise<void> {
    if (this.#closed) return;
    this.#closed = true;
    this.#retry?.();
    this.#retry = null;
    this.#idle?.();
    this.#idle = null;
    for (const thread of [...this.#waiting.keys()]) this.#fail(thread, new Error("station stopping"));
    const worker = this.#worker;
    this.#worker = null;
    if (worker !== null) await worker.terminate();
    await this.#timers.close();
  }
}
