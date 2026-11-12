// The copies of this station's chats as a part of the station (parts.ts; replica/AGENTS.md): the export's thread,
// what the store says changed told to it, the other stations' requests of the copies this one keeps (`replica.*`), a
// lost station's links taken to the one that took its place, the copies' part of the overview and their routes.
import { join } from "node:path";
import { Effect, Layer } from "effect";
import { routes } from "../api/routes/copies.ts";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { restarter } from "../ops/restart.ts";
import { managesStation } from "../mesh/credential.ts";
import { ControlPlane, Events, Key, Parts, Paths, Peers, Store } from "../services.ts";
import { Copies } from "./copies.ts";
import { WorkerRunner } from "./runner.ts";

type Json = any;

export const CopiesLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const store = yield* Store;
    const bus = yield* Peers;
    const cloud = (yield* ControlPlane).state;
    const events = yield* Events;
    const parts = yield* Parts;
    const key = yield* Key;
    const fibers = yield* Effect.acquireRelease(Effect.sync(() => new Fibers("copies")), (f) => Effect.promise(() => f.close()));
    const runner = yield* Effect.acquireRelease(
      Effect.sync(() => new WorkerRunner({ db: join(data, "stillfail.db"), replica: join(data, "replica"), dataDir: data, origin: key.id })),
      (r) => Effect.promise(() => r.close()),
    );
    const copies = new Copies({
      data,
      here: () => key.id,
      places: () => ({ home: cloud.home(), workspaces: cloud.memberships().map((m) => ({ workspace: m.workspace, name: m.name })) }),
      roster: (ws) => {
        const m = cloud.membership(ws);
        if (m === null || !cloud.peersCurrent) return null;
        return m.peers.flatMap((p: Json) => (typeof p?.id === "string" ? [{ id: p.id as string, name: typeof p.name === "string" ? p.name : "" }] : []));
      },
      ask: (station, request) => bus.ask(station, request),
      runner,
      fibers,
      changed: () => events.overviewChanged(),
      restart: () => restarter(data),
    });
    yield* Effect.addFinalizer(() => Effect.promise(() => copies.close()));
    bus.on("replica.", copies.answers());
    bus.formerly((station, ws) => copies.now(ws, station), key.id);
    yield* Effect.acquireRelease(Effect.sync(() => store.subscribe((c) => copies.told(c))), (off) => Effect.sync(off));
    // (the workspaces, or their stations, changed: what this station keeps and whom it tells, worked out again)
    let roster = "";
    const rosterNow = () => JSON.stringify(cloud.memberships().map((m) => [m.workspace, m.peers.map((p: Json) => p?.id)]).concat([[String(cloud.peersCurrent)]]));
    yield* Effect.acquireRelease(
      Effect.sync(() => cloud.listen(() => {
        const now = rosterNow();
        if (now === roster) return;
        roster = now;
        void copies.placesChanged().catch((e) => log.warn("copies", "the workspaces' copies not worked out again", { error: (e as Error).message }));
      })),
      (off) => Effect.sync(off),
    );
    bus.whenAttached(() => {
      roster = rosterNow();
      void copies.start().catch((e) => log.warn("copies", "the copies did not start", { error: (e as Error).message }));
    });
    parts.overview("copies", (viewer) => copies.overview(viewer.workspace, managesStation(viewer)));
    parts.routes(routes({ copies }));
  }),
);
