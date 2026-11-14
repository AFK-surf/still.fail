// What the agents spent (docs: the usage page), as a part of the station (parts.ts): read from their transcripts now,
// after each turn ends and as a session at work writes more (usage/counter.ts), recorded once (store/usage.ts). Every
// way it is shown is added up from that record: a chat's execution details and agent card (told as more is recorded,
// on its live stream and in its session's summary, `usage`) and the usage page (GET /usage).
import { Clock, Effect, Layer } from "effect";
import { Worker } from "node:worker_threads";
import { MbBackfill, mbReaderBinary } from "../read/mb-reader.ts";
import { wall } from "../ops/fibers.ts";
import { usageRoutes } from "../api/routes/usage.ts";
import { usageNow } from "../read/usage.ts";
import { Agents } from "../sessions/agents.ts";
import { hubConfig } from "../sessions/config.ts";
import type { LiveHub } from "../sessions/live.ts";
import { Parts, Paths, Previous, Readers, StationConfig, Store } from "../services.ts";
import { log } from "../ops/log.ts";
import { Fibers } from "../ops/fibers.ts";
import type { Store as StationStore } from "../store/store.ts";
import type { InWorkspace } from "../store/rows.ts";
import { giveBackfill, releaseStoppedBackfill, takeBackfill } from "../store/backfill.ts";
import { retireUsageIndexes, stopUsageIndexes } from "../store/usage-retire.ts";
import { hasCompactUsage, installCompactUsage, installUsageSummaryChanges } from "../store/usage-compact.ts";
import { hasUsageSummaryBlocks, installUsageSummaryBlocks, type UsageSummaryKey, type UsageSummaryRange } from "../store/usage-summary-blocks.ts";
import { installUsageHistory } from "../store/usage-history.ts";
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
        installUsageSummaryBlocks(store.db);
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
    if (hasCompactUsage(store.db) && hasUsageSummaryBlocks(store.db)) {
      installed();
      // A page may have opened before handover and received unavailable statistics. Wake it even if no call follows.
      store.usageChanged([], undefined, true);
    }
    const path = store.db.location();
    if (path === null) { retireUsageIndexes(store.db); return hasCompactUsage(store.db) && hasUsageSummaryBlocks(store.db); }
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./retire-worker.ts" : "./usage/retire-worker.js", import.meta.url);
    // (by the MoonBit builder, station/mb's src/usagefill, where its program is there: a step at a time, the permit
    // taken for each, as retire-worker.ts takes it)
    const mb = workerFile === undefined ? mbReaderBinary() : null;
    if (mb !== null) yield* Effect.tryPromise({ try: () => retireByProgram(store, mb, path), catch: (error) => error });
    else yield* Effect.tryPromise({ try: async () => {
      const worker = new Worker(file, { workerData: { path, priority: store.backfillPriority } });
      const owner = worker.threadId;
      worker.unref();
      await new Promise<void>((resolve, reject) => {
        let failure: Error | null = null;
        let complete = false;
        worker.on("message", (answer: { complete?: boolean; filled?: boolean }) => {
          complete ||= answer.complete === true;
          // The days before the statistics began have just come in: pages open now read them again.
          if (answer.filled) store.usageChanged([], undefined, true);
        });
        worker.once("error", (error) => { failure = error; });
        worker.once("exit", (code) => {
          releaseStoppedBackfill(store.backfillPriority, owner);
          if (failure !== null || code !== 0 || !complete) reject(failure ?? new Error(`usage retirement stopped (exit ${code})`));
          else resolve();
        });
      });
    }, catch: (error) => error });
    return hasCompactUsage(store.db) && hasUsageSummaryBlocks(store.db);
  }).pipe(Effect.catch((error) => Effect.sync(() => {
    log.warn("usage", stopped ? "usage indexes could not be removed" : "usage index writers could not be stopped", { error: (error as Error).message });
    return false;
  })));
}

/// What retire-worker.ts does, by the MoonBit program: the retired indexes freed, then the old calls taken in, newest
/// first, with at most about a tenth of the time going to them; pages open read again once old days came in.
async function retireByProgram(store: StationStore, mb: string, path: string): Promise<void> {
  const program = new MbBackfill(mb, ["--builder", "usage-retire", "--db", path], store.backfillPriority, 20);
  const ask = (message: object) => new Promise<{ done: boolean; error?: string }>((resolve, reject) => {
    const exit = (code: number) => reject(new Error(`usage retirement stopped (exit ${code})`));
    program.once("exit", exit);
    program.once("message", (answer: { done: boolean; error?: string }) => {
      program.off("exit", exit);
      if (answer.error) reject(new Error(answer.error)); else resolve(answer);
    });
    program.postMessage(message);
  });
  try {
    while (!(await ask({ drop: true })).done);
    let filled = false;
    for (;;) {
      const started = performance.now();
      if ((await ask({})).done) break;
      filled = true;
      await wall.sleep(Math.max(200, (performance.now() - started) * 9));
    }
    // The days before the statistics began have just come in: pages open now read them again.
    if (filled) store.usageChanged([], undefined, true);
  } finally { await program.terminate(); }
}

/// Retry temporary installation or cleanup failures after stopping the old writers.
export function retireUntilComplete(store: StationStore, exited: Promise<void>, workerFile?: URL, installed: () => void = () => {}) {
  return Effect.gen(function* () {
    let retryMs = 250;
    while (!(yield* retireAfterPrevious(store, exited, workerFile, installed))) {
      yield* Effect.sleep(retryMs);
      retryMs = Math.min(retryMs * 2, 30_000);
    }
  });
}

/// A worker moves changed ownership and accounts a workspace's totals when that workspace asks for them.
export function watchCompactMoves(store: StationStore, exited: Promise<void>): {
  wake: () => void; read: (viewer: InWorkspace | null) => void;
  waitSummary: (viewer: InWorkspace | null, range: UsageSummaryRange, signal?: AbortSignal) => Promise<void>; close: () => Promise<void>;
} {
  const path = store.db.location();
  const retries = new Fibers("usage workspace", store.clock);
  let closed = false;
  let ready = false;
  let moves = true;
  type Work = { scope?: string; range?: UsageSummaryRange };
  const scopes = new Map<string, Work>();
  const workId = (work: Work) => work.range === undefined ? work.scope! : JSON.stringify([work.scope, String(work.range.from), String(work.range.to)]);
  const waiting = new Set<{ scopes: Set<string>; finish: (error?: Error) => void }>();
  const scopesOf = (viewer: InWorkspace | null) => viewer === null ? ["G"]
    : viewer.home === false ? [`W${viewer.workspace}`] : [`W${viewer.workspace}`, "H"];
  // A page cannot use a total until all its pending buckets are accounted. Remember only the earliest changed time
  // for each requested scope, so intermediate batches do not send it back to read an unavailable total again.
  const totals = new Map<string, { from: number | undefined }>();
  let held: Work | null = null;
  let preferMoves = false;
  let retryMs = 250;
  let cancelRetry: (() => void) | null = null;
  let worker: Worker | MbBackfill | null = null;
  const interested = (id: string) => [...waiting].some((waiter) => waiter.scopes.has(id));
  const requeue = (work: Work) => {
    if (work.scope === undefined) moves = true;
    else if (work.range === undefined || interested(workId(work))) scopes.set(workId(work), work);
  };
  const enqueue = (work: Work) => {
    const id = workId(work);
    if ((held === null || workId(held) !== id) && !scopes.has(id)) scopes.set(id, work);
  };
  const dispatch = () => {
    if (worker === null || held !== null || cancelRetry !== null) return;
    let work: Work;
    if (moves && (preferMoves || scopes.size === 0)) { moves = false; preferMoves = false; work = {}; }
    else if (scopes.size > 0) {
      const [id, next] = scopes.entries().next().value!;
      scopes.delete(id);
      preferMoves = true;
      work = next;
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
    // (by the MoonBit builder, station/mb's src/usagefill scope.mbt, where its program is there: `MbBackfill`)
    const mb = mbReaderBinary();
    const current = mb !== null ? new MbBackfill(mb, ["--builder", "usage-scope", "--db", path], store.backfillPriority, 20)
      : new Worker(file, { workerData: { path, priority: store.backfillPriority } });
    const owner = current.threadId;
    worker = current;
    current.unref();
    current.on("message", (answer: { done: boolean; session?: string; sessions?: string[]; from?: number; after?: UsageSummaryKey; converted?: boolean; error?: string }) => {
      if (closed) return;
      const work = held;
      held = null;
      if (work === null) return;
      if (!answer.done) {
        if (work.range !== undefined) {
          if (answer.after !== undefined) work.range.after = answer.after;
          if (answer.converted) work.range.converted = true;
        }
        requeue(work);
      }
      if (answer.error) {
        log.warn("usage", "a usage statistics batch stopped", { error: answer.error });
        retry();
        return;
      }
      if (answer.session) store.usageChanged([answer.session], undefined, true);
      if (work.scope !== undefined) {
        if (work.range === undefined) {
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
        if (answer.done) for (const waiter of waiting) {
          waiter.scopes.delete(workId(work));
          if (waiter.scopes.size === 0) waiter.finish();
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
    for (const scope of scopesOf(viewer)) enqueue({ scope });
    start();
    dispatch();
  };
  const waitSummary = (viewer: InWorkspace | null, range: UsageSummaryRange, signal?: AbortSignal): Promise<void> => {
    if (closed || path === null) return Promise.reject(new Error("station stopping"));
    if (signal?.aborted) return Promise.reject(new Error("read cancelled"));
    return new Promise<void>((resolve, reject) => {
      const work = scopesOf(viewer).map((scope) => ({ scope, range: { from: range.from, to: range.to } }));
      const waiter = { scopes: new Set(work.map(workId)), finish: (error?: Error) => {
        waiting.delete(waiter);
        signal?.removeEventListener("abort", abort);
        for (const id of waiter.scopes) if (!interested(id)) scopes.delete(id);
        if (error) reject(error); else resolve();
      } };
      const abort = () => waiter.finish(new Error("read cancelled"));
      waiting.add(waiter);
      signal?.addEventListener("abort", abort, { once: true });
      try { for (const item of work) enqueue(item); start(); dispatch(); }
      catch (cause) { waiter.finish(cause instanceof Error ? cause : new Error(String(cause))); }
    });
  };
  const unsubscribe = store.onSessionWorkspaceChange(wake);
  const unsubscribeUsage = store.subscribe((change) => {
    if (change.type === "usage" && !change.statisticsOnly) wake();
  });
  void exited.then(() => { ready = true; start(); }).catch((cause) => {
    const error = cause instanceof Error ? cause : new Error(String(cause));
    log.warn("usage", "could not start usage workspace worker", { error: error.message });
    for (const waiter of waiting) waiter.finish(error);
  });
  return {
    wake,
    read,
    waitSummary,
    close: async () => {
      closed = true;
      for (const waiter of waiting) waiter.finish(new Error("station stopping"));
      unsubscribe();
      unsubscribeUsage();
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
    const readers = yield* Readers;
    const mover = yield* Effect.acquireRelease(
      Effect.sync(() => watchCompactMoves(store, previous.exited)),
      (m) => Effect.promise(() => m.close()),
    );
    yield* Effect.forkScoped(retireUntilComplete(store, previous.exited, undefined, mover.wake).pipe(Effect.provideService(Clock.Clock, hub.clock)));
    const usage = yield* Effect.acquireRelease(
      Effect.sync(() => new UsageCounter({
        store, config: () => ({ dataDir: data, profiles: hubConfig(config.raw(), data).profiles }), clock: hub.clock,
        // The turns its calls were made in: a reader's (each part of a transcript asked several statements here).
        turns: async (session, from, until) => JSON.parse(await readers.read("usageTurns", { session, from, until }, "zh")),
      })),
      (u) => Effect.promise(() => u.stop()),
    );
    usage.start();
    yield* Effect.acquireRelease(
      Effect.sync(() => keepCounted(store, hub.live, usage)),
      (unsubscribe) => Effect.sync(unsubscribe),
    );
    (yield* Parts).routes((tools) => usageRoutes(tools, () => usage.readingAll(), mover.read, mover.waitSummary));
  }),
);
