import { Worker } from "node:worker_threads";
import { log } from "../ops/log.ts";
import { releaseStoppedBackfill } from "../store/backfill.ts";
import { chatShareIndexReady, chatShareIndexStep, hasChatShareIndex, installChatShareIndex, refreshChatShareIndex, SHARE_MANY } from "../store/chat-share-index.ts";
import type { Store } from "../store/store.ts";

/// Sharing continues to answer the old way while the preceding station is up or a worker prepares its old grants.
export class ChatShareIndexBuilder {
  private pending: Promise<boolean> | null = null;
  private worker: Worker | null = null;
  private stopped = false;
  private readonly cancelled = Promise.withResolvers<boolean>();
  private readonly previous: Promise<boolean>;
  private readonly store: Store;
  private readonly workerFile: URL | undefined;

  constructor(store: Store, previous: Promise<void>, workerFile?: URL) {
    this.store = store;
    this.workerFile = workerFile;
    this.previous = previous.then(() => true, (error) => {
      log.warn("xshare", "could not wait for the previous station before preparing shares", { error: (error as Error).message });
      return false;
    });
  }

  request(): void {
    if (this.stopped || this.pending !== null) return;
    try {
      if (chatShareIndexReady(this.store.db)) return;
      // A few shares are cheaper to read directly. Do not install anything until the table grows past this probe.
      if (!hasChatShareIndex(this.store.db) && this.store.db.prepare(SHARE_MANY).get() === undefined) return;
    } catch (error) {
      log.warn("xshare", "the share lookup could not be checked", { error: (error as Error).message });
      return;
    }
    const work = (async () => {
      if (!await Promise.race([this.previous, this.cancelled.promise]) || this.stopped) return false;
      if (this.store.db.location() === null) {
        installChatShareIndex(this.store.db);
        while (!this.stopped && !chatShareIndexReady(this.store.db)) {
          chatShareIndexStep(this.store.db);
          await new Promise<void>((resolve) => setImmediate(resolve));
        }
        return !this.stopped;
      }
      return this.runWorker();
    })().catch((error) => {
      log.warn("xshare", "the share lookup could not be prepared", { error: (error as Error).message });
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
      catch (error) { log.warn("xshare", "the share worker could not start", { error: (error as Error).message }); resolve(false); return; }
      const owner = worker.threadId;
      let done = false;
      this.worker = worker;
      worker.unref();
      worker.on("message", (result: { done: boolean; error?: string }) => {
        if (result.error) {
          log.warn("xshare", "a share batch stopped", { error: result.error });
          void worker.terminate();
        } else if (result.done || this.stopped) {
          done = result.done && !this.stopped;
          void worker.terminate();
        } else worker.postMessage({ kind: "chat-share" });
      });
      worker.once("error", (error) => log.warn("xshare", "the share worker failed", { error: error.message }));
      worker.once("exit", (code) => {
        releaseStoppedBackfill(this.store.backfillPriority, owner);
        if (this.worker === worker) this.worker = null;
        if (done) {
          try { done = refreshChatShareIndex(this.store.db); }
          catch (error) { done = false; log.warn("xshare", "the prepared share lookup could not be found", { error: (error as Error).message }); }
        }
        if (!done && !this.stopped) log.warn("xshare", "the share worker stopped before finishing", { code });
        resolve(done);
      });
      worker.postMessage({ kind: "chat-share" });
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
