// The copies of this station's chats as a part of the station (parts.ts; replica/AGENTS.md): the export's thread,
// what the store says changed told to it, the other stations' requests of the copies this one keeps (`replica.*`), a
// lost station's links taken to the one that took its place, the copies' part of the overview and their routes; a
// station's retirement (retire.ts) and station_retire, its cards' choices (retire-asks.ts).
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
import { RetireAsks, chatCards } from "./retire-asks.ts";
import { retireTools } from "../tools/retire.ts";
import { wall } from "../ops/fibers.ts";
import { WorkerRunner } from "./runner.ts";

type Json = any;

/// Whether a person (POST /retire) or an agent (station_retire start, hand_over) may start retiring a station here. Off
/// (左子健, 2026-11-14: 「我怀疑这个功能根本不能给用户用」, after its first real use filled a disk, paused chats for 18
/// minutes, left files out of place and posted into 193 Slack threads): starting is refused in words; what a station
/// already retired or taking another's chats does, the preview, status, cancel, again and the mesh's methods are as
/// they were. This goes once the fixes have passed their drill.
const RETIRE_STARTS = false;

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
    // (each with what it takes to run it again where the chats go, as a restart does: jobs.ts `relaunch`; another
    // station's task run here is not a chat's, and stays)
    const jobsIn = (ws: string) => store.jobsUp().filter((j) => !j.sessionKey.startsWith("remote:") && agents.hub.ofWorkspace(j.sessionKey, ws))
      .map((j) => ({ session: j.sessionKey, name: j.name, command: j.command, cwd: j.cwd, port: j.port, watch: j.watch }));
    // The agent home of a workspace (sessions/agent-home.ts `workspaceAgentHome`, not made here: a path).
    const agentHomeOf = (ws: string) => {
      const { agentHome } = agents.hub.config();
      return cloud.home() === ws ? agentHome : join(agentHome, "workspaces", ws);
    };
    let asks: RetireAsks | null = null;
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
      // (what their platforms said meanwhile taken here, in order, as it would have been)
      unquiet: (ws) => {
        agents.hub.unquiet(ws);
        void agents.retireConnects?.takeHeld(ws).catch((e) => log.warn("retire", "what the platforms said meanwhile not taken here", { error: (e as Error).message }));
      },
      tell: (session, text) => agents.hub.notify(session, text),
      jobs: {
        start: (session, j) => {
          const job = agents.jobs.start(session, j.name, j.command, j.cwd, j.port, j.watch);
          return { id: job.id, name: job.name, port: job.port };
        },
        running: (session, name, command) => store.jobsUp().some((j) => j.sessionKey === session && j.name === name && j.command === command),
        say: (session, text) => agents.jobs.say(session, text),
      },
      agentHome: agentHomeOf,
      drives: (station, session) => asks?.drives(station, session) === true,
      ofWorkspace: (session, ws) => agents.hub.ofWorkspace(session, ws),
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
    // station_retire: its cards in the asking chat, chosen in the app by an owner or admin (retire-asks.ts).
    const hub = agents.hub;
    asks = new RetireAsks({
      data,
      here: () => key.id,
      roster: (ws) => {
        const m = cloud.membership(ws);
        if (m === null || !cloud.peersCurrent) return null;
        return m.peers.flatMap((p: Json) => (typeof p?.id === "string" ? [{ id: p.id as string, name: typeof p.name === "string" ? p.name : "" }] : []));
      },
      wsOf: (session) => {
        const row = store.getSession(session);
        return row === null ? null : (row.ws ?? cloud.home());
      },
      retire,
      ask: (station, request) => bus.ask(station, request),
      cards: chatCards(hub as Json),
      notify: (session, text) => hub.notify(session, text),
      now: () => wall.now(),
      starts: RETIRE_STARTS,
    });
    const asked = asks;
    parts.cardChoice("retire", { may: (viewer, card, at) => asked.may(viewer, card, at), chosen: (viewer, card, option, at) => asked.chosen(viewer, card, option, at) });
    parts.tools(retireTools(asked));
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
    parts.routes(routes({ copies, retire, starts: RETIRE_STARTS }));
  }),
);
