// The station on the mesh, once it is in a workspace (cloud.json there): its endpoint, its relays, its presence at
// still.fail cloud, and members' connections. Everything here lives in the layer's scope: stopping the station closes
// the endpoint and every connection and loop it started.
import { Effect, FiberSet, Layer, Option, Stream } from "effect";
import { presence } from "../cloud/presence.ts";
import { log } from "../ops/log.ts";
import { AdminApi, Cloud, Key, MeshNative, Up } from "../services.ts";
import { SubscriptionRef } from "effect";
import { keepRelays } from "./relays.ts";
import { ALPN, FORMER_ALPN, serve } from "./serve.ts";

export const MeshLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const cloud = yield* Cloud;
    const key = yield* Key;
    const native = yield* MeshNative;
    const admin = yield* AdminApi;
    const up = yield* Up;
    const run = Effect.gen(function* () {
      // Not in a workspace yet: on the mesh once `enroll` writes cloud.json.
      if (!cloud.state.state) yield* cloud.changes.pipe(Stream.filter(() => cloud.state.state !== null), Stream.runHead);
      const endpoint = yield* Effect.acquireRelease(
        Effect.promise(() => native.bind({ secretKey: key.seed, alpns: [ALPN, FORMER_ALPN], relayUrls: cloud.state.relays(), discovery: process.env.STILLFAIL_NO_DISCOVERY !== "1" })),
        // iroh closes gracefully, waiting on every connection (the keepers' too): up to ~12 s. A station stopping or
        // handing over doesn't wait that long: a second, then it is gone (clients reconnect, as they do anyway).
        (endpoint) => Effect.ignore(Effect.timeoutOption(Effect.promise(() => endpoint.close()), "1 second")),
      );
      log.info("mesh", "mesh listening", { station: endpoint.id(), workspace: cloud.state.state!.workspace_name, sockets: endpoint.sockets() });
      yield* Effect.forkScoped(keepRelays(endpoint));
      // Online at the cloud only once a relay can reach the station: a device that saw "online" and connected before
      // the relay link was up had its first packets dropped (~3 s of retransmits).
      const online = yield* Effect.timeoutOption(Effect.promise(() => endpoint.online()), "15 seconds");
      if (Option.isNone(online)) log.warn("mesh", "no relay link after 15 s; going online at still.fail cloud anyway");
      yield* Effect.forkScoped(presence);
      const connections = yield* FiberSet.make();
      const members = { cloud: cloud.state, admin, up: () => SubscriptionRef.getUnsafe(up) };
      for (;;) {
        const conn = yield* Effect.promise(() => endpoint.accept());
        if (!conn) return;
        yield* FiberSet.run(
          connections,
          Effect.tryPromise(() => serve(members, conn)).pipe(
            Effect.catch((e) => Effect.sync(() => log.info("mesh", "connection ended", { error: String((e as Error).cause ?? e) }))),
            Effect.ensuring(Effect.sync(() => conn.close(0, "station stopping"))),
          ),
        );
      }
    });
    yield* Effect.forkScoped(Effect.scoped(run));
  }),
);
