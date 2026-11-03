// What the agents spent (docs: the usage page), as a part of the station (parts.ts): read from their transcripts now,
// after each turn ends and as a session at work writes more (usage/counter.ts), recorded once (store/usage.ts). Every
// way it is shown is added up from that record: a chat's execution details and agent card (told as more is recorded,
// on its live stream and in its session's summary, `usage`) and the usage page (GET /usage).
import { Effect, Layer } from "effect";
import { Worker } from "node:worker_threads";
import { usageRoutes } from "../api/routes/usage.ts";
import { usageNow } from "../read/usage.ts";
import { Agents } from "../sessions/agents.ts";
import { hubConfig } from "../sessions/config.ts";
import type { LiveHub } from "../sessions/live.ts";
import { Parts, Paths, Previous, StationConfig, Store } from "../services.ts";
import { log } from "../ops/log.ts";
import { Fibers, wall } from "../ops/fibers.ts";
import type { Store as StationStore } from "../store/store.ts";
import { releaseStoppedBackfill } from "../store/backfill.ts";
import { retireUsageIndexes } from "../store/usage-retire.ts";
import { installCompactUsage } from "../store/usage-compact.ts";
import { UsageCounter } from "./counter.ts";

/// A session's usage as its summary says it (store.ts `setSessionUsage`): as recorded now (read/usage.ts `usageNow`).
/// None before a call. `quiet`: not told as a change of the session.
export function keepUsage(store: StationStore, key: string, quiet = false): void {
  const usage = usageNow(store, key);
  if (usage !== null) store.setSessionUsage(key, usage, quiet);
}

/// The live view reads each saved summary. Only sessions whose recorded usage changes are updated and told.
export function keepCounted(store: StationStore, live: LiveHub, counter: UsageCounter): () => void {
  live.countWith({ of: (key) => store.sessionUsage(key), ask: (key) => counter.soon(key) });
  return store.subscribe((change) => {
    // A session gone on in another conversation (its context cleared, as 换新上下文 does): its context is that one's.
    const sessions = change.type === "usage" ? change.sessions : change.type === "conversation" ? [change.key] : null;
    if (sessions === null) return;
    for (const key of sessions) keepUsage(store, key);
    live.usageCounted();
  });
}

/// An older station may still use these indexes during handover. Stop their writers only after it actually exits.
export function retireAfterPrevious(store: StationStore, exited: Promise<void>, installed: () => void = () => {}) {
  return Effect.promise(async () => {
    try {
      await exited;
      const path = store.db.location();
      if (path === null) { installCompactUsage(store.db, () => store.now()); installed(); retireUsageIndexes(store.db); return; }
      const file = new URL(import.meta.url.endsWith(".ts") ? "./retire-worker.ts" : "./usage/retire-worker.js", import.meta.url);
      const worker = new Worker(file, { workerData: { path, priority: store.backfillPriority, now: store.now(), capturedAt: wall.now() } });
      const owner = worker.threadId;
      worker.unref();
      await new Promise<void>((resolve, reject) => {
        let failure: Error | null = null;
        let complete = false;
        worker.on("message", (answer: { installed?: boolean; complete?: boolean }) => {
          if (answer.installed) installed();
          complete ||= answer.complete === true;
        });
        worker.once("error", (error) => { failure = error; });
        worker.once("exit", (code) => {
          releaseStoppedBackfill(store.backfillPriority, owner);
          if (failure !== null || code !== 0 || !complete) reject(failure ?? new Error(`usage retirement stopped (exit ${code})`));
          else resolve();
        });
      });
    } catch (error) {
      log.warn("usage", "usage indexes could not be retired", { error: (error as Error).message });
    }
  });
}

/// A worker sleeps until session ownership changes or the compact source is installed. Pending moves survive a restart.
export function watchCompactMoves(store: StationStore, exited: Promise<void>): { wake: () => void; close: () => Promise<void> } {
  const path = store.db.location();
  const retries = new Fibers("usage workspace", store.clock);
  let closed = false;
  let ready = false;
  let requested = true;
  let outstanding = false;
  let retryMs = 250;
  let cancelRetry: (() => void) | null = null;
  let worker: Worker | null = null;
  const dispatch = () => {
    if (worker !== null && requested && !outstanding) {
      requested = false;
      outstanding = true;
      worker.postMessage({ wake: true });
    }
  };
  const retry = () => {
    if (closed || cancelRetry !== null) return;
    const delay = retryMs;
    retryMs = Math.min(retryMs * 2, 30_000);
    cancelRetry = retries.after(delay, () => {
      cancelRetry = null;
      requested = true;
      start();
      dispatch();
    });
  };
  const start = () => {
    if (closed || !ready || path === null || worker !== null) return;
    const file = new URL(import.meta.url.endsWith(".ts") ? "./scope-worker.ts" : "./usage/scope-worker.js", import.meta.url);
    const current = new Worker(file, { workerData: { path, priority: store.backfillPriority } });
    const owner = current.threadId;
    let failed = false;
    worker = current;
    current.unref();
    current.on("message", (answer: { session?: string; error?: string; idle?: boolean }) => {
      if (closed) return;
      if (answer.error) { failed = true; log.warn("usage", "a usage workspace move stopped", { error: answer.error }); }
      if (answer.session) store.usageChanged([answer.session]);
      if (answer.idle) {
        outstanding = false;
        if (failed) { failed = false; retry(); }
        else { retryMs = 250; dispatch(); }
      }
    });
    current.once("error", (error) => log.warn("usage", "the usage workspace worker failed", { error: error.message }));
    current.once("exit", (code) => {
      releaseStoppedBackfill(store.backfillPriority, owner);
      if (worker === current) worker = null;
      outstanding = false;
      requested = true;
      if (!closed) {
        log.warn("usage", "the usage workspace worker stopped", { code });
        retry();
      }
    });
    dispatch();
  };
  const wake = () => {
    cancelRetry?.();
    cancelRetry = null;
    requested = true;
    start();
    dispatch();
  };
  const unsubscribe = store.onSessionWorkspaceChange(wake);
  void exited.then(() => { ready = true; start(); }).catch((error) => log.warn("usage", "could not start usage workspace worker", { error: (error as Error).message }));
  return {
    wake,
    close: async () => {
      closed = true;
      unsubscribe();
      await retries.close();
      if (worker !== null) await worker.terminate();
    },
  };
}

export const UsageLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const store = yield* Store;
    const config = yield* StationConfig;
    const { hub } = yield* Agents;
    const previous = yield* Previous;
    const mover = yield* Effect.acquireRelease(
      Effect.sync(() => watchCompactMoves(store, previous.exited)),
      (m) => Effect.promise(() => m.close()),
    );
    yield* Effect.forkScoped(retireAfterPrevious(store, previous.exited, mover.wake));
    const usage = yield* Effect.acquireRelease(
      Effect.sync(() => new UsageCounter({ store, config: () => ({ dataDir: data, profiles: hubConfig(config.raw(), data).profiles }), clock: hub.clock })),
      (u) => Effect.promise(() => u.stop()),
    );
    usage.start();
    yield* Effect.acquireRelease(
      Effect.sync(() => keepCounted(store, hub.live, usage)),
      (unsubscribe) => Effect.sync(unsubscribe),
    );
    (yield* Parts).routes((tools) => usageRoutes(tools, () => usage.readingAll()));
  }),
);
