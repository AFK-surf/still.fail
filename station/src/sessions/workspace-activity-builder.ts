import { Worker } from "node:worker_threads";
import { MbBackfill, mbReaderBinary } from "../read/mb-reader.ts";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { releaseStoppedBackfill } from "../store/backfill.ts";
import { workspaceActivityReady, workspaceActivityStep } from "../store/workspace-activity.ts";
import { recoverWaitsReady, recoverWaitsStep } from "../store/recover-waits.ts";
import { awakeWaitsReady, awakeWaitsStep } from "../store/awake-waits.ts";
import { activeJobUpgradeReady, activeJobUpgradeStep } from "../store/active-jobs-upgrade.ts";
import type { Store } from "../store/store.ts";

type Kind = "activity" | "recovery" | "awake" | "active-jobs";

/// One worker prepares the lookups after handover, in bounded batches. Workspace activity is prepared first so its
/// existing callers are not held up by restart and awake preparation. Every cursor can resume after interruption. By
/// the MoonBit builder (station/mb, src/activity) where its program is there, the worker taking over a kind it leaves
/// to it (`MbBackfill`); a worker of its own given, by that one.
export function buildWorkspaceActivity(store: Store, previous: Promise<void>, workerFile?: URL, mb = workerFile === undefined ? mbReaderBinary() : null): {
  ready: Promise<boolean>; activeJobsReady: Promise<boolean>; close: () => Promise<void>;
} {
  const activity = Promise.withResolvers<boolean>();
  const activeJobs = Promise.withResolvers<boolean>();
  const path = store.db.location();
  const retries = new Fibers("workspace activity", store.clock);
  let worker: Worker | MbBackfill | null = null;
  let cancel: (() => void) | null = null;
  let closed = false;
  let activityDone = workspaceActivityReady(store.db);
  let recoveryDone = recoverWaitsReady(store.db);
  let awakeDone = awakeWaitsReady(store.db);
  let activeJobsDone = activeJobUpgradeReady(store.db);
  let pending: Kind = "activity";
  let retryMs = 250;
  if (activityDone) activity.resolve(true);
  if (activeJobsDone) activeJobs.resolve(true);
  const complete = () => activityDone && recoveryDone && awakeDone && activeJobsDone;
  const next = (): Kind => !activityDone ? "activity" : !recoveryDone ? "recovery" : !awakeDone ? "awake" : "active-jobs";
  const finish = (kind: Kind) => {
    if (closed) return;
    if (kind === "activity" && !activityDone) { activityDone = true; activity.resolve(true); }
    if (kind === "recovery" && !recoveryDone) recoveryDone = true;
    if (kind === "awake" && !awakeDone) awakeDone = true;
    if (kind === "active-jobs" && !activeJobsDone) { activeJobsDone = true; activeJobs.resolve(true); }
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
      const result = kind === "activity" ? workspaceActivityStep(store.db) : kind === "recovery" ? recoverWaitsStep(store.db)
        : kind === "awake" ? awakeWaitsStep(store.db) : activeJobUpgradeStep(store.db);
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
    let current: Worker | MbBackfill;
    const thread = () => new Worker(file, { workerData: { path, priority: store.backfillPriority } });
    try { current = mb !== null ? new MbBackfill(mb, ["--builder", "session-backfill", "--db", path], store.backfillPriority, 20, thread) : thread(); }
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
    activeJobsReady: activeJobs.promise,
    close: async () => {
      if (closed) return;
      closed = true;
      activity.resolve(false);
      activeJobs.resolve(false);
      cancel?.();
      await retries.close();
      if (worker !== null) await worker.terminate();
    },
  };
}
