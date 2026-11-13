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
import { Agents } from "../sessions/agents.ts";
import { retiredWs } from "../sessions/hub.ts";
import { Copies } from "./copies.ts";
import { Retire } from "./retire.ts";
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
    const agents = yield* Agents;
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
      taking: () => retire.takingNow(),
    });
    // The jobs and services of a workspace's chats up now (what a retirement stops and the preview lists), and this
    // station's own accounts (no copy borrowed, not the machine's login: what may move, share/index.ts moveProfile).
    const jobsIn = (ws: string) => store.jobsUp().filter((j) => agents.hub.ofWorkspace(j.sessionKey, ws)).map((j) => ({ session: j.sessionKey, name: j.name, command: j.command }));
    const ownProfiles = (): Json[] => (Array.isArray(agents.config.raw()?.profiles) ? agents.config.raw().profiles : []).filter((p: Json) => typeof p?.id === "string" && p.machine !== true && !(p.share !== null && typeof p.share === "object" && p.share.borrowed === true));
    // A station retired from a workspace, its chats going on another of it; or another's taken here (retire.ts).
    const retire: Retire = new Retire({
      data,
      here: () => key.id,
      home: () => cloud.home(),
      roster: (ws) => {
        const m = cloud.membership(ws);
        if (m === null || !cloud.peersCurrent) return null;
        return m.peers.flatMap((p: Json) => (typeof p?.id === "string" ? [{ id: p.id as string, name: typeof p.name === "string" ? p.name : "" }] : []));
      },
      ask: (station, request) => bus.ask(station, request),
      fibers,
      changed: () => events.overviewChanged(),
      copies,
      quiet: async (ws) => {
        await agents.hub.quiet(ws);
        // (their jobs and services stop too, those of this workspace's chats alone, as `jobsIn` finds them; what they
        // were is said where the chats go)
        const up = jobsIn(ws);
        await agents.jobs.stopAll("this station's chats of the workspace went to another station", (job) => agents.hub.ofWorkspace(job.sessionKey, ws));
        return up;
      },
      jobsIn: (ws) => jobsIn(ws),
      connectsNamed: (ws) => agents.retireConnects?.named(ws) ?? [],
      askItself: (station, request) => bus.askItself(station, request),
      accounts: {
        own: () => ownProfiles().map((p: Json) => ({ id: String(p.id), name: typeof p.name === "string" && p.name !== "" ? p.name : String(p.id) })),
        move: (id, to) => agents.sharing.moveProfile(id, to),
      },
      unquiet: (ws) => agents.hub.unquiet(ws),
      retired: (ws) => {
        // (idempotent: once moved, none is left saying the workspace)
        store.setSessionsWs(cloud.home() === ws ? null : ws, retiredWs(ws));
      },
      connectsOf: (ws) => agents.retireConnects?.of(ws) ?? [],
      bindingsOf: (connects) => Object.fromEntries(connects.flatMap((c) => {
        const bound = store.binding(c);
        return bound === null ? [] : [[c, bound]];
      })),
      took: ({ bindings, notes }) => {
        for (const [connect, session] of Object.entries(bindings)) if (store.binding(connect) === null && store.getSession(session) !== null) store.setBinding(connect, session);
        store.setMovedNotes(notes);
      },
      moveConnects: async (ws, to) => {
        if (agents.retireConnects === null) throw new Error("the connects are not up yet");
        await agents.retireConnects.move(ws, to);
      },
      reposDir: agents.hub.reposDir(),
    });
    yield* Effect.addFinalizer(() => Effect.promise(() => retire.close()));
    yield* Effect.addFinalizer(() => Effect.promise(() => copies.close()));
    bus.on("retire.", retire.answers((peer, ws) => copies.inWorkspace(peer, ws)));
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
      void retire.start().catch((e) => log.warn("retire", "the retirement did not go on", { error: (e as Error).message }));
    });
    parts.overview("copies", (viewer) => ({ ...(copies.overview(viewer.workspace, managesStation(viewer)) as object), ...(retire.overview(viewer.workspace) as object) }));
    parts.routes(routes({ copies, retire }));
  }),
);
