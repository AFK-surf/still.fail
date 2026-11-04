// What the agents spent (docs: the usage page), as a part of the station (parts.ts): read from their transcripts now,
// after each turn ends and as a session at work writes more (usage/counter.ts), recorded once (store/usage.ts). Every
// way it is shown is added up from that record: a chat's execution details and agent card (told as more is recorded,
// on its live stream and in its session's summary, `usage`) and the usage page (GET /usage).
import { Clock, Effect, Layer } from "effect";
import { Worker } from "node:worker_threads";
import { usageRoutes } from "../api/routes/usage.ts";
import { usageNow } from "../read/usage.ts";
import { Agents } from "../sessions/agents.ts";
import { hubConfig } from "../sessions/config.ts";
import type { LiveHub } from "../sessions/live.ts";
import { Parts, Paths, Previous, StationConfig, Store } from "../services.ts";
import { log } from "../ops/log.ts";
import { Fibers } from "../ops/fibers.ts";
import type { Store as StationStore } from "../store/store.ts";
import type { InWorkspace } from "../store/rows.ts";
import { giveBackfill, releaseStoppedBackfill, takeBackfill } from "../store/backfill.ts";
import { retireUsageIndexes, stopUsageIndexes } from "../store/usage-retire.ts";
import { hasCompactUsage, installCompactUsage, installUsageSummaryChanges } from "../store/usage-compact.ts";
import { convertUsageHistoryStep, historyTransferPending, installUsageHistory } from "../store/usage-history.ts";
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
    if (change.type === "usage" && change.statisticsOnly) return;
    // A session gone on in another conversation (its context cleared, as 换新上下文 does): its context is that one's.
    const sessions = change.type === "usage" ? change.sessions : change.type === "conversation" ? [change.key] : null;
    if (sessions === null) return;
    for (const key of sessions) keepUsage(store, key);
    live.usageCounted();
  });
}

/// Install the new writers and stop the old ones without waiting behind another connection on the station thread.
function tryStopUsageIndexes(store: StationStore): boolean {
  const priority = new Int32Array(store.backfillPriority);
  const owner = -1; // Background workers use positive thread ids.
  if (!takeBackfill(priority, owner)) return false;
  try {
    const timeout = (store.db.prepare("PRAGMA busy_timeout").get() as { timeout: number }).timeout;
    store.db.exec("PRAGMA busy_timeout = 0");
    try {
      try {
        installCompactUsage(store.db, () => store.now());
        installUsageSummaryChanges(store.db);
      } catch (error) {
        const code = (error as { errcode?: number }).errcode;
        if (code !== undefined && [5, 6].includes(code & 255)) throw error;
        // Even if the new statistics cannot be installed, do not leave the old per-call writers running.
        log.warn("usage", "compact usage statistics could not be installed", { error: (error as Error).message });
      }
      stopUsageIndexes(store.db);
      try { installUsageHistory(store.db, store.now()); }
      catch (error) {
        const code = (error as { errcode?: number }).errcode;
        if (code !== undefined && [5, 6].includes(code & 255)) throw error;
        log.warn("usage", "the usage history could not be installed", { error: (error as Error).message });
      }
      return true;
    } catch (error) {
      const code = (error as { errcode?: number }).errcode;
      if (code !== undefined && [5, 6].includes(code & 255)) return false;
      throw error;
    } finally {
      store.db.exec(`PRAGMA busy_timeout = ${timeout}`);
    }
  } finally { giveBackfill(priority, owner); }
}

/// An older station may still use these indexes during handover. Stop their writers only after it actually exits.
export function retireAfterPrevious(store: StationStore, exited: Promise<void>, workerFile?: URL, installed: () => void = () => {}) {
  let stopped = false;
  return Effect.gen(function* () {
    yield* Effect.tryPromise({ try: () => exited, catch: (error) => error });
    while (!(yield* Effect.try({ try: () => tryStopUsageIndexes(store), catch: (error) => error }))) {
      yield* Effect.sleep(50);
    }
    stopped = true;
    if (hasCompactUsage(store.db)) {
      installed();
      // A page may have opened before handover and received unavailable statistics. Wake it even if no call follows.
      store.usageChanged([], undefined, true);
    }
    const path = store.db.location();
    if (path === null) {
      const converting = historyTransferPending(store.db);
      while (!convertUsageHistoryStep(store.db)) { /* In-memory stores have no worker. */ }
      if (converting) store.usageChanged([], undefined, true);
      retireUsageIndexes(store.db);
      return;
    }
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./retire-worker.ts" : "./usage/retire-worker.js", import.meta.url);
    yield* Effect.tryPromise({ try: async () => {
      const worker = new Worker(file, { workerData: { path, priority: store.backfillPriority } });
      const owner = worker.threadId;
      worker.unref();
      await new Promise<void>((resolve, reject) => {
        let failure: Error | null = null;
        let complete = false;
        worker.on("message", (answer: { complete?: boolean; historyReady?: boolean }) => {
          complete ||= answer.complete === true;
          if (answer.historyReady) store.usageChanged([], undefined, true);
        });
        worker.once("error", (error) => { failure = error; });
        worker.once("exit", (code) => {
          releaseStoppedBackfill(store.backfillPriority, owner);
          if (failure !== null || code !== 0 || !complete) reject(failure ?? new Error(`usage retirement stopped (exit ${code})`));
          else resolve();
        });
      });
    }, catch: (error) => error });
  }).pipe(Effect.catch((error) => Effect.sync(() => {
    log.warn("usage", stopped ? "usage indexes could not be removed" : "usage index writers could not be stopped", { error: (error as Error).message });
  })));
}

/// Keep the handover alive until its statistics and cleanup have finished.
export function retireUntilComplete(store: StationStore, exited: Promise<void>, workerFile?: URL, installed: () => void = () => {}) {
  return retireAfterPrevious(store, exited, workerFile, installed);
}

/// A worker moves changed ownership and accounts a workspace's totals when that workspace asks for them.
export function watchCompactMoves(store: StationStore, exited: Promise<void>): {
  wake: () => void; read: (viewer: InWorkspace | null) => void; close: () => Promise<void>;
} {
  const path = store.db.location();
  const retries = new Fibers("usage workspace", store.clock);
  let closed = false;
  let ready = false;
  let moves = true;
  const scopes = new Set<string>();
  // A page cannot use a total until all its pending buckets are accounted. Remember only the earliest changed time
  // for each requested scope, so intermediate batches do not send it back to read an unavailable total again.
  const totals = new Map<string, { from: number | undefined }>();
  let held: { scope?: string } | null = null;
  let preferMoves = false;
  let retryMs = 250;
  let cancelRetry: (() => void) | null = null;
  let worker: Worker | null = null;
  const requeue = (work: { scope?: string }) => { if (work.scope === undefined) moves = true; else scopes.add(work.scope); };
  const dispatch = () => {
    if (worker === null || held !== null || cancelRetry !== null) return;
    let work: { scope?: string };
    if (moves && (preferMoves || scopes.size === 0)) { moves = false; preferMoves = false; work = {}; }
    else if (scopes.size > 0) {
      const scope = scopes.values().next().value!;
      scopes.delete(scope);
      preferMoves = true;
      work = { scope };
    } else return;
    held = work;
    worker.postMessage({ wake: true, ...work });
  };
  const retry = () => {
    if (closed || cancelRetry !== null) return;
    const delay = retryMs;
    retryMs = Math.min(retryMs * 2, 30_000);
    cancelRetry = retries.after(delay, () => {
      cancelRetry = null;
      start();
      dispatch();
    });
  };
  const start = () => {
    if (closed || !ready || path === null || worker !== null) return;
    const file = new URL(import.meta.url.endsWith(".ts") ? "./scope-worker.ts" : "./usage/scope-worker.js", import.meta.url);
    const current = new Worker(file, { workerData: { path, priority: store.backfillPriority } });
    const owner = current.threadId;
    worker = current;
    current.unref();
    current.on("message", (answer: { done: boolean; session?: string; sessions?: string[]; from?: number; error?: string }) => {
      if (closed) return;
      const work = held;
      held = null;
      if (work === null) return;
      if (!answer.done) requeue(work);
      if (answer.error) {
        log.warn("usage", "a usage statistics batch stopped", { error: answer.error });
        retry();
        return;
      }
      if (answer.session) store.usageChanged([answer.session], undefined, true);
      if (work.scope !== undefined) {
        if (answer.sessions?.length) {
          const prior = totals.get(work.scope);
          const from = prior === undefined ? answer.from : prior.from === undefined || answer.from === undefined
            ? undefined : Math.min(prior.from, answer.from);
          totals.set(work.scope, { from });
        }
        const complete = answer.done ? totals.get(work.scope) : undefined;
        if (complete !== undefined) {
          totals.delete(work.scope);
          store.usageChanged([], complete.from, true);
        }
      }
      retryMs = 250;
      dispatch();
    });
    current.once("error", (error) => log.warn("usage", "the usage workspace worker failed", { error: error.message }));
    current.once("exit", (code) => {
      releaseStoppedBackfill(store.backfillPriority, owner);
      if (worker === current) worker = null;
      if (held !== null) requeue(held);
      held = null;
      moves = true;
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
    moves = true;
    start();
    dispatch();
  };
  const read = (viewer: InWorkspace | null) => {
    cancelRetry?.();
    cancelRetry = null;
    if (viewer === null) scopes.add("G");
    else {
      scopes.add(`W${viewer.workspace}`);
      if (viewer.home !== false) scopes.add("H");
    }
    start();
    dispatch();
  };
  const unsubscribe = store.onSessionWorkspaceChange(wake);
  void exited.then(() => { ready = true; start(); }).catch((error) => log.warn("usage", "could not start usage workspace worker", { error: (error as Error).message }));
  return {
    wake,
    read,
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
    yield* Effect.forkScoped(retireUntilComplete(store, previous.exited, undefined, mover.wake).pipe(Effect.provideService(Clock.Clock, hub.clock)));
    const usage = yield* Effect.acquireRelease(
      Effect.sync(() => new UsageCounter({ store, config: () => ({ dataDir: data, profiles: hubConfig(config.raw(), data).profiles }), clock: hub.clock })),
      (u) => Effect.promise(() => u.stop()),
    );
    usage.start();
    yield* Effect.acquireRelease(
      Effect.sync(() => keepCounted(store, hub.live, usage)),
      (unsubscribe) => Effect.sync(unsubscribe),
    );
    (yield* Parts).routes((tools) => usageRoutes(tools, () => usage.readingAll(), mover.read));
  }),
);
