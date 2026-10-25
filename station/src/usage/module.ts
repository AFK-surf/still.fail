// What the agents spent (docs: the usage page), as a part of the station (parts.ts): read from their transcripts now
// and after each turn ends (usage/counter.ts); an execution's details show its calls as counted and are told when more
// are, and each session's summary says them (`usage`); GET /usage.
import { Effect, Layer } from "effect";
import { usageRoutes } from "../api/routes/usage.ts";
import { noUsage } from "../read/tail.ts";
import { sessionUsage } from "../read/usage.ts";
import { Agents } from "../sessions/agents.ts";
import { hubConfig } from "../sessions/config.ts";
import { Parts, Paths, StationConfig, Store } from "../services.ts";
import type { Store as StationStore } from "../store/store.ts";
import { UsageCounter } from "./counter.ts";

/// A session's usage as its summary says it (store.ts `setSessionUsage`): its calls as counted over what its live view
/// last told of the rest (the model, the context it carries on with); before it told any, those of its last call. None
/// before a call. `quiet`: not told as a change of the session.
export function keepUsage(store: StationStore, key: string, quiet = false): void {
  const counted = sessionUsage(store.usageOfSession(key));
  if (counted.modelCalls === 0) return;
  const last = store.lastContexts(key, 1)[0];
  const told = store.sessionUsage(key) ?? { ...noUsage(), model: last?.model ?? null, contextTokens: last?.context ?? 0 };
  store.setSessionUsage(key, { ...told, ...counted }, quiet);
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
    hub.live.countWith({ of: (key) => sessionUsage(store.usageOfSession(key)), ask: () => usage.soon() });
    // Those of before it was kept, at once and untold: a device reads them with its sessions.
    for (const key of store.sessionsWithoutUsage()) keepUsage(store, key, true);
    yield* Effect.acquireRelease(
      Effect.sync(() =>
        store.subscribe((change) => {
          if (change.type !== "usage") return;
          // Those it follows told on their streams (and kept), then every session counted anew kept as counted.
          hub.live.usageCounted();
          for (const key of change.sessions) keepUsage(store, key);
        }),
      ),
      (unsubscribe) => Effect.sync(unsubscribe),
    );
    (yield* Parts).routes((tools) => usageRoutes(tools, () => usage.readingAll()));
  }),
);
