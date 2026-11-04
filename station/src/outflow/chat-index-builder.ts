import { Worker } from "node:worker_threads";
import { log } from "../ops/log.ts";
import { Fibers } from "../ops/fibers.ts";
import { releaseStoppedBackfill } from "../store/backfill.ts";
import { outflowChatScopes } from "../store/outflow-index.ts";
import type { InWorkspace } from "../store/rows.ts";

type Waiter = { resolve: () => void; reject: (error: Error) => void; done: () => void };
const IDLE_MS = 5_000;

/// Work only while a program is waiting. Concurrent requests share each scope's bounded work.
export class OutflowChatIndex {
  #worker: Worker | null = null;
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

  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    this.#path = path;
    this.#options = options;
    this.#workerFile = workerFile;
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
    if (this.#worker === null) {
      const file = this.#workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./chat-index-worker.ts" : "./outflow/chat-index-worker.js", import.meta.url);
      let worker: Worker;
      try { worker = new Worker(file, { workerData: { path: this.#path, priority: this.#options.priority }, resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 8 } }); }
      catch (error) { this.#fail(error instanceof Error ? error : new Error(String(error))); return; }
      const owner = worker.threadId;
      this.#worker = worker;
      worker.unref();
      worker.on("message", (result: { done: boolean; error?: string }) => {
        if (this.#worker !== worker || this.#closed) return;
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
      });
      worker.once("error", (error) => log.warn("outflow", "the chat order worker failed", { error: error.message }));
      worker.once("exit", () => {
        releaseStoppedBackfill(this.#options.priority, owner);
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
    const scope = this.#waiting.keys().next().value as string | undefined;
    if (scope !== undefined) { this.#current = scope; this.#worker.postMessage(scope); }
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
