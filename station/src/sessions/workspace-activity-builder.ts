import { Worker } from "node:worker_threads";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { releaseStoppedBackfill } from "../store/backfill.ts";
import { workspaceActivityReady, workspaceActivityStep } from "../store/workspace-activity.ts";
import { recoverWaitsReady, recoverWaitsStep } from "../store/recover-waits.ts";
import type { Store } from "../store/store.ts";

type Kind = "activity" | "recovery";

/// A single worker prepares both lookups after handover, in bounded batches. Workspace activity is prepared first so
/// its existing callers are not held up by the restart lookup. Both cursors can resume after interruption.
export function buildWorkspaceActivity(store: Store, previous: Promise<void>, workerFile?: URL): {
  ready: Promise<boolean>; close: () => Promise<void>;
} {
  const activity = Promise.withResolvers<boolean>();
  const path = store.db.location();
  const retries = new Fibers("workspace activity", store.clock);
  let worker: Worker | null = null;
  let cancel: (() => void) | null = null;
  let closed = false;
  let activityDone = workspaceActivityReady(store.db);
  let recoveryDone = recoverWaitsReady(store.db);
  let pending: Kind = "activity";
  let retryMs = 250;
  if (activityDone) activity.resolve(true);
  const complete = () => activityDone && recoveryDone;
  const next = (): Kind => activityDone ? "recovery" : "activity";
  const finish = (kind: Kind) => {
    if (closed) return;
    if (kind === "activity" && !activityDone) { activityDone = true; activity.resolve(true); }
    if (kind === "recovery" && !recoveryDone) recoveryDone = true;
  };
  const retry = () => {
    if (closed || complete() || cancel !== null) return;
    const ms = retryMs;
    retryMs = Math.min(retryMs * 2, 30_000);
    cancel = retries.after(ms, () => { cancel = null; start(); });
  };
  const memoryStep = () => {
    if (closed || complete()) return;
    const kind = next();
    try {
      const result = kind === "activity" ? workspaceActivityStep(store.db) : recoverWaitsStep(store.db);
      if (result.done) finish(kind);
      if (!complete()) cancel = retries.after(20, () => { cancel = null; memoryStep(); });
    } catch (error) {
      log.warn("hub", "a session recovery batch stopped", { error: (error as Error).message });
      retry();
    }
  };
  const start = () => {
    if (closed || complete() || worker !== null) return;
    if (path === null) { memoryStep(); return; }
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./workspace-activity-worker.ts" : "./sessions/workspace-activity-worker.js", import.meta.url);
    let current: Worker;
    try { current = new Worker(file, { workerData: { path, priority: store.backfillPriority } }); }
    catch (error) {
      log.warn("hub", "the session recovery worker could not start", { error: (error as Error).message });
      retry();
      return;
    }
    const owner = current.threadId;
    worker = current;
    current.unref();
    const send = () => { pending = next(); current.postMessage({ kind: pending }); };
    current.on("message", (result: { done: boolean; error?: string; kind?: Kind }) => {
      if (closed || worker !== current) return;
      if (result.error) {
        log.warn("hub", "a session recovery batch stopped", { error: result.error });
        void current.terminate();
      } else {
        if (result.done) finish(result.kind ?? pending);
        if (complete()) void current.terminate();
        else { retryMs = 250; send(); }
      }
    });
    current.once("error", (error) => log.warn("hub", "the session recovery worker failed", { error: error.message }));
    current.once("exit", () => {
      releaseStoppedBackfill(store.backfillPriority, owner);
      if (worker === current) worker = null;
      retry();
    });
    send();
  };
  if (!complete()) void previous.then(start).catch((error) => log.warn("hub", "could not start the session recovery worker", { error: (error as Error).message }));
  return {
    ready: activity.promise,
    close: async () => {
      if (closed) return;
      closed = true;
      activity.resolve(false);
      cancel?.();
      await retries.close();
      if (worker !== null) await worker.terminate();
    },
  };
}
