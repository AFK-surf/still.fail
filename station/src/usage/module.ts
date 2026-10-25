// What the agents spent (docs: the usage page), as a part of the station (parts.ts): read from their transcripts now,
// after each turn ends and as a session at work writes more (usage/counter.ts), recorded once (store/usage.ts). Every
// way it is shown is added up from that record: a chat's execution details and agent card (told as more is recorded,
// on its live stream and in its session's summary, `usage`) and the usage page (GET /usage).
import { Effect, Layer } from "effect";
import { usageRoutes } from "../api/routes/usage.ts";
import { usageNow } from "../read/usage.ts";
import { Agents } from "../sessions/agents.ts";
import { hubConfig } from "../sessions/config.ts";
import type { LiveHub } from "../sessions/live.ts";
import { Parts, Paths, StationConfig, Store } from "../services.ts";
import type { Store as StationStore } from "../store/store.ts";
import { UsageCounter } from "./counter.ts";

/// A session's usage as its summary says it (store.ts `setSessionUsage`): as recorded now (read/usage.ts `usageNow`).
/// None before a call. `quiet`: not told as a change of the session.
export function keepUsage(store: StationStore, key: string, quiet = false): void {
  const usage = usageNow(store, key);
  if (usage !== null) store.setSessionUsage(key, usage, quiet);
}

/// Sessions' usage as `counter` records it: the live view tells it and asks the counter to count what a session at work
/// writes; each session counted anew is kept as counted (its summary), and those of before it was kept at once and
/// untold (a device reads them with its sessions). Gives what stops it.
export function keepCounted(store: StationStore, live: LiveHub, counter: UsageCounter): () => void {
  live.countWith({ of: (key) => usageNow(store, key), ask: (key) => counter.soon(key) });
  for (const key of store.sessionsWithoutUsage()) keepUsage(store, key, true);
  return store.subscribe((change) => {
    if (change.type !== "usage") return;
    // Those it follows told on their streams, then every session counted anew kept as counted.
    live.usageCounted();
    for (const key of change.sessions) keepUsage(store, key);
  });
}

export const UsageLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const store = yield* Store;
    const config = yield* StationConfig;
    const { hub } = yield* Agents;
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
