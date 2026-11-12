// Keeps the station on still.fail's relays (the Rust station's main.rs `keep_relays`): the ones browsers reach (they
// know no others), iroh homing on the nearest and the station kept on the rest too (keepers), so a device that reaches
// only some of them still reaches it. Those the cloud adds or takes away are put in or taken out as it pushes them.
// iroh's public relays come in only while none of ours answers (so the station can still be reached; the DHT says
// where), and go once one does again (else iroh may home on a public relay, where browsers can't follow). The relay
// iroh homes on is asked first, and once it answers asked again on the same connection, timed: the ping other stations
// are told of (jobs/load.ts). The workspaces' own relays (mesh/ways.ts, kept by their stations) are kept the same way,
// after still.fail's, as they are added or taken away.
import { Effect, Schedule, Stream } from "effect";
import type { Net } from "../jobs/load.ts";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { ControlPlane } from "../services.ts";
import type { Endpoint } from "./native.ts";
import { sameUrl, waysOf } from "./ways.ts";

/// Asking our relays whether they answer is asking an outside system: the one timer here.
const RELAY_CHECK = "30 seconds";

/// Runs for good (until interrupted).
export const keepRelays = (endpoint: Endpoint, net?: Net) =>
  Effect.gen(function* () {
    const cloud = yield* ControlPlane;
    const ways = waysOf(cloud.state);
    // still.fail's, then the workspaces' own not among them.
    const wanted = () => {
      const theirs = cloud.state.relays();
      return [...theirs, ...ways.relays().filter((u) => !theirs.some((t) => sameUrl(t) === sameUrl(u)))];
    };
    let ours = wanted();
    endpoint.keep(ours);
    let added = false;

    // As the cloud pushes still.fail's, and as a workspace's own are added or taken away. One change at a time.
    let changing: Promise<void> = Promise.resolve();
    const changed = () => (changing = changing.then(async () => {
      const now = wanted();
      if (cloud.state.relays().length === 0 || JSON.stringify(now) === JSON.stringify(ours)) return;
      log.info("mesh", "the relays kept changed", { relays: now });
      const was = ours;
      ours = now;
      for (const url of now.filter((u) => !was.includes(u))) await endpoint.insertRelay(url);
      for (const url of was.filter((u) => !now.includes(u))) await endpoint.removeRelay(url);
      endpoint.keep(now);
    }).catch((e) => log.warn("mesh", "the relays kept were not changed", { error: (e as Error).message })));
    const follow = cloud.changes.pipe(Stream.runForEach(() => Effect.promise(changed)));
    const stopWays = ways.listen(() => void changed());

    const check = Effect.promise(async () => {
      let up = false;
      const bare = (url: string) => url.replace(/\/+$/, "");
      const home = endpoint.home();
      const order = home === null ? ours : [...ours.filter((u) => bare(u) === bare(home)), ...ours.filter((u) => bare(u) !== bare(home))];
      // Two tries each: one lost request is not the relay down.
      relays: for (const relay of order) {
        for (let i = 0; i < 2; i++) {
          try {
            const r = await fetch(`${bare(relay)}/ping`, { signal: AbortSignal.timeout(10_000) });
            if (r.ok) {
              up = true;
              if (net !== undefined) {
                // Once more on the connection made (its body read, so it is free again): the time is the way there and
                // back, not the handshakes.
                try {
                  await r.arrayBuffer();
                  const start = wall.now();
                  const again = await fetch(`${bare(relay)}/ping`, { signal: AbortSignal.timeout(10_000) });
                  await again.arrayBuffer();
                  if (again.ok) net.pinged(bare(relay), wall.now() - start);
                } catch {}
              }
              break relays;
            }
          } catch {}
        }
      }
      if (!up && !added) {
        log.warn("mesh", "none of still.fail's relays answers; adding iroh's public relays until one does", { relays: ours });
        await endpoint.publicRelays(true);
        added = true;
      } else if (up && added) {
        log.info("mesh", "still.fail's relays answer again; back home to them", { relays: ours });
        await endpoint.publicRelays(false);
        added = false;
      }
    });

    yield* Effect.all([follow, Effect.repeat(check, Schedule.spaced(RELAY_CHECK))], { concurrency: "unbounded", discard: true }).pipe(Effect.ensuring(Effect.sync(stopWays))); // timer: a ping that measures the relays, which tell nothing by themselves
  });
