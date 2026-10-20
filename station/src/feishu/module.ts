// The Feishu connects as a part of the agents' side (parts.ts, docs/feishu.md), as slack/module.ts is Slack's:
// connected while the station is in their workspace and its sessions are taken up, disconnected as it leaves; their
// chats the hub takes and posts to; the names the pages show of Feishu people and chats, learned as they are heard of;
// the overview's Feishu connects and the apps being made by a scan; the Feishu routes; and feishu_api for the agents.
import { Effect, Layer } from "effect";
import { feishuRoutes } from "../api/routes/feishu.ts";
import { Agents } from "../sessions/agents.ts";
import { ControlPlane, Events, Parts, Paths, StationConfig, Store } from "../services.ts";
import { makeFeishu } from "./index.ts";
import { shownRegistration } from "./register.ts";
import { feishuTools } from "./tool.ts";

export const FeishuLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const store = yield* Store;
    const config = yield* StationConfig;
    const events = yield* Events;
    const cloud = (yield* ControlPlane).state;
    const parts = yield* Parts;
    const agents = yield* Agents;
    const { hub } = agents;
    const feishu = yield* Effect.acquireRelease(
      Effect.sync(() =>
        makeFeishu({
          data, store, config, receive: (connect, event) => hub.receive(connect, event), bound: () => agents.taken() && agents.bound(),
          inWorkspace: (ws) => ws === null || cloud.membership(ws) !== null,
        }),
      ),
      (f) => Effect.promise(() => f.close()),
    );
    agents.surfaces((id) => feishu.chats(id));
    agents.connectView("feishu", { connection: (c: any) => feishu.state(String(c?.id ?? "")), shown: (c: any) => feishu.shown(c) });
    agents.along({
      taken: () => feishu.reconcile(),
      joined: () => feishu.reconcile(),
      changed: () => feishu.reconcile(),
      left: () => feishu.stopAll(),
    });
    // The names the pages show of Feishu people and chats, looked up as they are heard of (who wrote, and where).
    const isFeishu = (connect: string) => feishu.connects().some((c) => c.id === connect);
    yield* Effect.acquireRelease(
      Effect.sync(() =>
        store.subscribe((change) => {
          if (change.type !== "thread") return;
          const t = store.getThread(change.id);
          if (t === null || !t.surface.startsWith("feishu:")) return;
          const chat = feishu.chat(t.surface.slice("feishu:".length));
          if (chat === undefined) return;
          chat.knownChannel?.(t.channel);
          for (const user of new Set(change.entries.filter((e) => e.authorKind === "person").map((e) => e.author))) chat.knownPerson?.(user);
        }),
      ),
      (unsubscribe) => Effect.sync(unsubscribe),
    );
    yield* Effect.acquireRelease(
      Effect.sync(() => feishu.onChange(() => (events.overviewChanged(), events.rowsChanged(null)))),
      (off) => Effect.sync(off),
    );
    parts.overview("feishuRegistrations", (viewer) => feishu.registrations.of(viewer.email).map(shownRegistration));
    parts.routes(
      feishuRoutes({
        feishu, config, data,
        hub: () => hub,
        overview: (viewer, lang) => agents.overview(viewer, lang),
        place: () => agents.place(),
      }),
    );
    parts.tools(feishuTools(() => hub, isFeishu));
  }),
);
