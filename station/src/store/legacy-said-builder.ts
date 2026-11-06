import { Worker } from "node:worker_threads";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { releaseStoppedBackfill } from "./backfill.ts";
import { hasLegacySaid, legacySaidMaintenanceStep, legacySaidNeedsWork } from "./legacy-said-build.ts";
import type { Store } from "./store.ts";

/// Keep an old store readable during handover; prepare and reconcile only after the previous station has exited.
export function buildLegacySaid(store: Store, previous: Promise<void>, workerFile?: URL): {
  ready: Promise<boolean>; wake: () => void; close: () => Promise<void>;
} {
  const { promise: ready, resolve } = Promise.withResolvers<boolean>();
  const enabled = hasLegacySaid(store.db);
  const path = store.db.location();
  const work = new Fibers("old message lookup", store.clock);
  let worker: Worker | null = null;
  let retryCancel: (() => void) | null = null, memoryCancel: (() => void) | null = null;
  let allowed = false, closed = false, requested = false, retryMs = 250;
  let off: () => void = () => {};
  const retry = () => {
    if (closed || retryCancel !== null) return;
    const ms = retryMs;
    retryMs = Math.min(retryMs * 2, 30_000);
    retryCancel = work.after(ms, () => { retryCancel = null; start(); });
  };
  const memoryStep = () => {
    memoryCancel = null;
    if (closed) return;
    try {
      requested = false;
      const result = legacySaidMaintenanceStep(store.db);
      if (result.done && !requested) { retryMs = 250; resolve(true); return; }
      memoryCancel = work.after(20, memoryStep);
    } catch (error) {
      log.warn("store", "an old message lookup batch stopped", { error: (error as Error).message });
      retry();
    }
  };
  const start = () => {
    if (!enabled || !allowed || closed || worker !== null || retryCancel !== null || memoryCancel !== null) return;
    try {
      if (!legacySaidNeedsWork(store.db)) { requested = false; retryMs = 250; resolve(true); return; }
    } catch (error) {
      log.warn("store", "the old message lookup could not be checked", { error: (error as Error).message });
      retry();
      return;
    }
    if (path === null) { memoryStep(); return; }
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts")
      ? "../sessions/workspace-activity-worker.ts" : "./sessions/workspace-activity-worker.js", import.meta.url);
    let current: Worker;
    try { current = new Worker(file, { workerData: { path, priority: store.backfillPriority } }); }
    catch (error) {
      log.warn("store", "the old message lookup worker could not start", { error: (error as Error).message });
      retry();
      return;
    }
    const owner = current.threadId;
    let failed = false, finished = false;
    worker = current;
    current.unref();
    const send = () => { requested = false; current.postMessage({ kind: "legacy-said" }); };
    current.on("message", (result: { done: boolean; error?: string }) => {
      if (closed || worker !== current) return;
      if (result.error) {
        failed = true;
        log.warn("store", "an old message lookup batch stopped", { error: result.error });
        void current.terminate();
      } else if (result.done && !requested) {
        retryMs = 250;
        finished = true;
        resolve(true);
        void current.terminate();
      } else { retryMs = 250; send(); }
    });
    current.once("error", (error) => {
      failed = true;
      log.warn("store", "the old message lookup worker failed", { error: error.message });
    });
    current.once("exit", () => {
      releaseStoppedBackfill(store.backfillPriority, owner);
      if (worker === current) worker = null;
      if (closed) return;
      if (failed || !finished) { requested = true; retry(); }
      else if (requested) start();
    });
    send();
  };
  const wake = () => { requested = true; start(); };
  if (enabled) {
    off = store.subscribe((change) => {
      if ((change.type === "thread" && change.entries.length > 0) || change.type === "threadRemoved") wake();
    });
    // An older connection's writes do not notify this Store. Probe one indexed key periodically once handover ends.
    work.every(5_000, () => {
      if (!allowed || closed || worker !== null) return;
      try { if (legacySaidNeedsWork(store.db)) wake(); }
      catch (error) { log.warn("store", "the old message lookup could not be checked", { error: (error as Error).message }); retry(); }
    });
    void previous.then(() => { allowed = true; wake(); }, (error) => {
      log.warn("store", "could not wait for the previous station before preparing messages", { error: (error as Error).message });
      resolve(false);
    });
  } else resolve(true);
  return {
    ready, wake,
    close: async () => {
      if (closed) return;
      closed = true;
      resolve(false);
      off(); retryCancel?.(); memoryCancel?.();
      await work.close();
      if (worker !== null) await worker.terminate();
    },
  };
}
