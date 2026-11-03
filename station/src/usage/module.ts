// What the agents spent (docs: the usage page), as a part of the station (parts.ts): read from their transcripts now,
// after each turn ends and as a session at work writes more (usage/counter.ts), recorded once (store/usage.ts). Every
// way it is shown is added up from that record: a chat's execution details and agent card (told as more is recorded,
// on its live stream and in its session's summary, `usage`) and the usage page (GET /usage).
import { Effect, Layer } from "effect";
import { join } from "node:path";
import { usageRoutes } from "../api/routes/usage.ts";
import { log } from "../ops/log.ts";
import { usageNow } from "../read/usage.ts";
import { Agents } from "../sessions/agents.ts";
import { hubConfig } from "../sessions/config.ts";
import type { LiveHub } from "../sessions/live.ts";
import { Parts, Paths, Previous, StationConfig, Store } from "../services.ts";
import type { Store as StationStore } from "../store/store.ts";
import { UsageCounter } from "./counter.ts";
import { CompactionBackfill } from "./compaction-backfill.ts";

/// Bump when the stored session summary or its prices need to be recalculated for existing sessions.
const SUMMARY_VERSION = 1;
/// A previous-version writer has no in-process event to wake this station; look for its dirty marks at this interval.
const SUMMARY_POLL_MS = 1_000;

/// A session's usage as its summary says it (store.ts `setSessionUsage`): as recorded now (read/usage.ts `usageNow`).
/// None before a call. `quiet`: not told as a change of the session.
export function keepUsage(store: StationStore, key: string, quiet = false): void {
  store.refreshSessionUsage(key, () => usageNow(store, key), quiet);
}

/// Sessions' usage as `counter` records it: the live view tells it and asks the counter to count what a session at work
/// writes; each session counted anew is kept as counted. A summary format upgrade visits one session at a time after
/// the previous process exits, and remembers its progress, rather than revisiting all sessions at each station start.
export function keepCounted(store: StationStore, live: LiveHub, counter: UsageCounter, previous: Promise<void> = Promise.resolve()): () => void {
  live.countWith({ of: (key) => usageNow(store, key), ask: (key) => counter.soon(key) });
  let closed = false;
  let ready = false;
  let preferDirty = true;
  let pending: NodeJS.Immediate | null = null;
  let retry: NodeJS.Timeout | null = null;
  const schedule = () => {
    if (ready && !closed && pending === null && retry === null) pending = setImmediate(step);
  };
  const wake = () => {
    if (retry !== null) clearTimeout(retry);
    retry = null;
    schedule();
  };
  const step = () => {
    pending = null;
    if (closed) return;
    try {
      // Alternate dirty sessions with the old-format sweep so a busy session cannot hold the upgrade back.
      const next = store.nextUsageSummaryRefresh(preferDirty);
      preferDirty = !preferDirty;
      if (next === null) {
        retry = setTimeout(() => { retry = null; schedule(); }, SUMMARY_POLL_MS);
        retry.unref();
        return;
      }
      store.refreshSessionUsage(next.key, () => usageNow(store, next.key), false, next.upgrade ? SUMMARY_VERSION : undefined);
      if (!closed) live.usageCounted([next.key]);
      schedule();
    } catch (error) {
      log.error("usage", "a session summary could not be refreshed", { error: (error as Error).message });
      if (!closed) {
        retry = setTimeout(() => { retry = null; schedule(); }, 5_000);
        retry.unref();
      }
    }
  };
  const unsubscribe = store.subscribe((change) => {
    // A session gone on in another conversation (its context cleared, as 换新上下文 does): its context is that one's.
    const sessions = change.type === "usage" ? change.sessions : change.type === "conversation" ? [change.key] : null;
    if (sessions === null) return;
    // Those it follows told on their streams, then every session counted anew kept as counted.
    live.usageCounted(sessions);
    try {
      // A first transcript read can report thousands of sessions at once. Their dirty marks are already durable;
      // one session is kept immediately, while a larger set is refreshed a session at a time by the worker.
      if (sessions.length === 1) keepUsage(store, sessions[0]!);
    } finally {
      // If a count failed, its dirty mark remains and the background refresh can try again.
      wake();
    }
  });
  void previous.then(() => {
    if (closed) return;
    store.startUsageSummaryRefresh(SUMMARY_VERSION);
    ready = true;
    schedule();
  }).catch((error) => log.error("usage", "session summaries could not start", { error: (error as Error).message }));
  return () => {
    closed = true;
    unsubscribe();
    if (pending !== null) clearImmediate(pending);
    if (retry !== null) clearTimeout(retry);
  };
}

export const UsageLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const store = yield* Store;
    const previous = yield* Previous;
    const config = yield* StationConfig;
    const { hub } = yield* Agents;
    const backfill = yield* Effect.acquireRelease(
      Effect.sync(() => new CompactionBackfill(join(data, "stillfail.db"), store.backfillPriority)),
      (index) => Effect.promise(() => index.stop()),
    );
    if (!store.compactionsReady()) void previous.exited.then(() => backfill.start()).catch((error) => {
      log.error("usage", "the compaction history worker could not start", { error: (error as Error).message });
    });
    const usage = yield* Effect.acquireRelease(
      Effect.sync(() => new UsageCounter({ store, config: () => ({ dataDir: data, profiles: hubConfig(config.raw(), data).profiles }), clock: hub.clock })),
      (u) => Effect.promise(() => u.stop()),
    );
    usage.start();
    yield* Effect.acquireRelease(
      Effect.sync(() => keepCounted(store, hub.live, usage, previous.exited)),
      (unsubscribe) => Effect.sync(unsubscribe),
    );
    (yield* Parts).routes((tools) => usageRoutes(tools, () => usage.readingAll()));
  }),
);
