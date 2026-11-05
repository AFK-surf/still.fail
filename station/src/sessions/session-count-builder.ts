import { Worker } from "node:worker_threads";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { releaseStoppedBackfill } from "../store/backfill.ts";
import { sessionCountsReady, sessionCountsStep } from "../store/session-counts.ts";
import type { Store } from "../store/store.ts";

/// Wait for the previous station before reading old rows; a stopped worker resumes at its committed cursor.
export function buildSessionCounts(store: Store, previous: Promise<void>, workerFile?: URL): { ready: Promise<boolean>; close: () => Promise<void> } {
  const { promise: ready, resolve } = Promise.withResolvers<boolean>();
  const path = store.db.location();
  const retries = new Fibers("session counts", store.clock);
  let worker: Worker | null = null;
  let cancel: (() => void) | null = null;
  let closed = false, complete = false, retryMs = 250;
  const finish = () => { if (!complete && !closed) { complete = true; resolve(true); } };
  const retry = () => {
    if (closed || complete || cancel !== null) return;
    const ms = retryMs;
    retryMs = Math.min(retryMs * 2, 30_000);
    cancel = retries.after(ms, () => { cancel = null; start(); });
  };
  const memoryStep = () => {
    if (closed || complete) return;
    try {
      if (sessionCountsStep(store.db).done) { finish(); return; }
      cancel = retries.after(20, () => { cancel = null; memoryStep(); });
    } catch (error) {
      log.warn("hub", "a session count batch stopped", { error: (error as Error).message });
      retry();
    }
  };
  const start = () => {
    if (closed || complete || worker !== null) return;
    if (path === null) { memoryStep(); return; }
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./session-count-worker.ts" : "./sessions/session-count-worker.js", import.meta.url);
    let current: Worker;
    try { current = new Worker(file, { workerData: { path, priority: store.backfillPriority } }); }
    catch (error) {
      log.warn("hub", "the session count worker could not start", { error: (error as Error).message });
      retry();
      return;
    }
    const owner = current.threadId;
    worker = current;
    current.unref();
    current.on("message", (result: { done: boolean; error?: string }) => {
      if (closed || worker !== current) return;
      if (result.error) {
        log.warn("hub", "a session count batch stopped", { error: result.error });
        void current.terminate();
      } else if (result.done) {
        finish();
        void current.terminate();
      } else {
        retryMs = 250;
        current.postMessage({});
      }
    });
    current.once("error", (error) => log.warn("hub", "the session count worker failed", { error: error.message }));
    current.once("exit", () => {
      releaseStoppedBackfill(store.backfillPriority, owner);
      if (worker === current) worker = null;
      retry();
    });
    current.postMessage({});
  };
  if (sessionCountsReady(store.db)) finish();
  else void previous.then(start).catch((error) => log.warn("hub", "could not start the session count worker", { error: (error as Error).message }));
  return {
    ready,
    close: async () => {
      if (closed) return;
      closed = true;
      resolve(false);
      cancel?.();
      await retries.close();
      if (worker !== null) await worker.terminate();
    },
  };
}
