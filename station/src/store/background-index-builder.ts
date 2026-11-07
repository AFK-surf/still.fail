import { Worker } from "node:worker_threads";
import { log } from "../ops/log.ts";
import { releaseStoppedBackfill } from "./backfill.ts";
import type { Store } from "./store.ts";

type Lookup = {
  scope: "memory" | "xshare";
  name: "process job" | "share";
  previousName: "jobs" | "shares";
  kind: "process-jobs" | "chat-share";
  install: () => void;
  ready: () => boolean;
  step: () => unknown;
  refresh: () => boolean;
};

/// One lifecycle for a requested whole-index build, including handover and worker ownership.
export class BackgroundIndexBuilder {
  private pending: Promise<boolean> | null = null;
  private worker: Worker | null = null;
  protected stopped = false;
  private readonly cancelled = Promise.withResolvers<boolean>();
  private readonly previous: Promise<boolean>;
  protected readonly store: Store;
  private readonly workerFile: URL | undefined;
  private readonly lookup: Lookup;

  constructor(store: Store, previous: Promise<void>, lookup: Lookup, workerFile?: URL) {
    this.store = store;
    this.lookup = lookup;
    this.workerFile = workerFile;
    this.previous = previous.then(() => true, (error) => {
      log.warn(this.lookup.scope, `could not wait for the previous station before preparing ${this.lookup.previousName}`, { error: (error as Error).message });
      return false;
    });
  }

  protected buildIf(needed: () => boolean): void {
    if (this.stopped || this.pending !== null) return;
    try { if (!needed()) return; }
    catch (error) { log.warn(this.lookup.scope, `the ${this.lookup.name} lookup could not be checked`, { error: (error as Error).message }); return; }
    const work = (async () => {
      if (!await Promise.race([this.previous, this.cancelled.promise]) || this.stopped) return false;
      if (this.store.db.location() === null) {
        this.lookup.install();
        while (!this.stopped && !this.lookup.ready()) {
          this.lookup.step();
          await new Promise<void>((resolve) => setImmediate(resolve));
        }
        return !this.stopped;
      }
      return this.runWorker();
    })().catch((error) => {
      log.warn(this.lookup.scope, `the ${this.lookup.name} lookup could not be prepared`, { error: (error as Error).message });
      return false;
    }).finally(() => { if (this.pending === work) this.pending = null; });
    this.pending = work;
  }

  async settled(): Promise<void> { await this.pending; }

  private runWorker(): Promise<boolean> {
    const path = this.store.db.location();
    if (path === null) return Promise.resolve(false);
    const file = this.workerFile ?? new URL(import.meta.url.endsWith(".ts")
      ? "../sessions/workspace-activity-worker.ts" : "./sessions/workspace-activity-worker.js", import.meta.url);
    return new Promise<boolean>((resolve) => {
      let worker: Worker;
      try { worker = new Worker(file, { workerData: { path, priority: this.store.backfillPriority } }); }
      catch (error) { log.warn(this.lookup.scope, `the ${this.lookup.name} worker could not start`, { error: (error as Error).message }); resolve(false); return; }
      const owner = worker.threadId;
      let done = false;
      this.worker = worker;
      worker.unref();
      worker.on("message", (result: { done: boolean; error?: string }) => {
        if (result.error) { log.warn(this.lookup.scope, `a ${this.lookup.name} batch stopped`, { error: result.error }); void worker.terminate(); }
        else if (result.done || this.stopped) { done = result.done && !this.stopped; void worker.terminate(); }
        else worker.postMessage({ kind: this.lookup.kind });
      });
      worker.once("error", (error) => log.warn(this.lookup.scope, `the ${this.lookup.name} worker failed`, { error: error.message }));
      worker.once("exit", (code) => {
        releaseStoppedBackfill(this.store.backfillPriority, owner);
        if (this.worker === worker) this.worker = null;
        if (done) {
          try { done = this.lookup.refresh(); }
          catch (error) { done = false; log.warn(this.lookup.scope, `the prepared ${this.lookup.name} lookup could not be found`, { error: (error as Error).message }); }
        }
        if (!done && !this.stopped) log.warn(this.lookup.scope, `the ${this.lookup.name} worker stopped before finishing`, { code });
        resolve(done);
      });
      worker.postMessage({ kind: this.lookup.kind });
    });
  }

  async close(): Promise<void> {
    if (this.stopped) return;
    this.stopped = true;
    this.cancelled.resolve(false);
    if (this.worker !== null) await this.worker.terminate();
    await this.pending;
  }
}
