// What the agents spent (docs: the usage page), as a part of the station (parts.ts): read from their transcripts now
// and after each turn ends (usage/counter.ts); an execution's details show its calls as counted and are told when more
// are; GET /usage.
import { Effect, Layer } from "effect";
import { usageRoutes } from "../api/routes/usage.ts";
import { sessionUsage } from "../read/usage.ts";
import { Agents } from "../sessions/agents.ts";
import { hubConfig } from "../sessions/config.ts";
import { Parts, Paths, StationConfig, Store } from "../services.ts";
import { UsageCounter } from "./counter.ts";

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
    yield* Effect.acquireRelease(
      Effect.sync(() => store.subscribe((change) => change.type === "usage" && hub.live.usageCounted())),
      (unsubscribe) => Effect.sync(unsubscribe),
    );
    (yield* Parts).routes((tools) => usageRoutes(tools, () => usage.readingAll()));
  }),
);
