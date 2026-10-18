// The connects' Slack as a part of the agents' side (parts.ts, docs: connects): connected while the station is in its
// workspace, once the sessions are taken up (a Socket Mode event goes to one connection of an app; two processes' would
// split them), and disconnected as it leaves; the connects' chats the hub takes and posts to; the names the pages show
// of Slack people and channels learned as they are heard of; the overview's connects and Slack workspaces; the Slack
// routes. Stopped before the agents hand their sessions over (its scope closes before theirs): Slack's events go to the
// next process from then on.
import { Effect, Layer } from "effect";
import { routes } from "../api/routes/slack.ts";
import { log } from "../ops/log.ts";
import { Agents } from "../sessions/agents.ts";
import { ControlPlane, Events, Parts, Paths, StationConfig, Store } from "../services.ts";
import { makeConnections } from "./index.ts";

export const SlackLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const store = yield* Store;
    const config = yield* StationConfig;
    const events = yield* Events;
    const cloud = (yield* ControlPlane).state;
    const parts = yield* Parts;
    const agents = yield* Agents;
    const { hub } = agents;
    const slack = yield* Effect.acquireRelease(
      Effect.sync(() =>
        makeConnections({
          data, store, config, receive: (connect, event) => hub.receive(connect, event), bound: () => agents.taken() && agents.bound(),
          inWorkspace: (ws) => ws === null || cloud.membership(ws) !== null,
        }),
      ),
      (s) => Effect.promise(() => s.close()),
    );
    agents.surfaces((id) => slack.chats(id));
    agents.slackView({
      connection: (c: any) => slack.state(c.id),
      teams: (viewer) => slack.overview(viewer.email).slackTeams,
      apps: (viewer) => slack.overview(viewer.email).slackApps,
    });
    agents.along({
      taken: async () => {
        await slack.reconcile();
        if (slack.connects().length === 0) log.warn("station", "no connect is connected; add or enable one in the workspace's settings");
      },
      joined: () => slack.reconcile(),
      // Those of a workspace left disconnect, those of one back connect.
      changed: () => slack.reconcile(),
      left: () => slack.stopAll(),
    });
    // The names the pages show of Slack people and channels are the readers' (from the names book); a connection looks
    // up those it does not know yet as it hears of them: who wrote, and where.
    const learn = (thread: number, people: string[]) => {
      const t = store.getThread(thread);
      if (t === null || t.surface === "ember") return;
      const connect = store.threadSessions(thread).map((m) => m.connect).find((c) => c !== "ember");
      const chat = connect === undefined ? undefined : slack.chat(connect);
      if (chat === undefined) return;
      chat.knownChannel?.(t.channel);
      for (const user of people) chat.knownPerson?.(user);
    };
    yield* Effect.acquireRelease(
      Effect.sync(() =>
        store.subscribe((change) => {
          if (change.type === "thread") learn(change.id, [...new Set(change.entries.filter((e) => e.authorKind === "person").map((e) => e.author))]);
        }),
      ),
      (unsubscribe) => Effect.sync(unsubscribe),
    );
    // A connect connected: the Slack threads people read lately, learned once.
    const learned = new Set<string>();
    yield* Effect.acquireRelease(
      Effect.sync(() =>
        slack.onChange(() => {
          for (const c of slack.connects()) {
            if (learned.has(c.id) || slack.state(c.id)?.state !== "connected") continue;
            learned.add(c.id);
            for (const t of store.listThreads("", null, null).slice(0, 200)) {
              if (t.sessions.some((m) => m.connect === c.id)) learn(t.thread.id, [...t.people.flatMap((p) => (p.startsWith(`slack:${c.id}:`) ? [p.slice(`slack:${c.id}:`.length)] : []))]);
            }
          }
        }),
      ),
      (off) => Effect.sync(off),
    );
    // The sidebar names connects and their Slack workspaces.
    yield* Effect.acquireRelease(
      Effect.sync(() => slack.onChange(() => (events.overviewChanged(), events.rowsChanged(null)))),
      (off) => Effect.sync(off),
    );
    parts.routes(
      routes({
        slack, config, data, store,
        hub: () => hub,
        overview: (viewer, lang) => agents.overview(viewer, lang),
        place: () => agents.place(),
        overviewChanged: () => events.overviewChanged(),
      }),
    );
  }),
);
