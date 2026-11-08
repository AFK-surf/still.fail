// The Comma connects as a part of the agents' side (connects/part.ts says what every platform's connects are there): a
// Comma connect as the overview shows it and the pages edit it, and the route that makes one; the workspace's
// statistics its connections send Comma (stats.ts), and what this station answers another's read of them (peer.ts).
import { Effect, Layer } from "effect";
import { commaEntry, commaRoutes } from "../api/routes/comma.ts";
import { connectsPart } from "../connects/part.ts";
import { stationLang } from "../ops/i18n.ts";
import { Agents } from "../sessions/agents.ts";
import { ControlPlane, Parts, Paths, Peers, Readers, StationConfig, Store } from "../services.ts";
import { makeComma } from "./index.ts";
import { READ, answerText, peerRead, workspaceRead } from "./peer.ts";
import { CommaStats } from "./stats.ts";

export const CommaLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const config = yield* StationConfig;
    const parts = yield* Parts;
    const agents = yield* Agents;
    const readers = yield* Readers;
    const bus = yield* Peers;
    const store = yield* Store;
    const cloud = (yield* ControlPlane).state;
    // Another station of the workspace reading this one's statistics, for the Comma connect there.
    bus.on(READ, peerRead((op, args, lang) => readers.read(op, args, lang), () => cloud.home(), stationLang));
    const read = workspaceRead({
      home: () => cloud.home(),
      here: (op, args) => readers.read(op, { ...args, lang: stationLang() }, stationLang(), { background: true }),
      others: async () => {
        const roster = await bus.ask("", { method: "peers", workspace: cloud.home() });
        if (roster?.current !== true) throw new Error("the roster is not current");
        const here = cloud.state?.station ?? "";
        return (Array.isArray(roster?.stations) ? roster.stations : []).map((e: any) => e?.id).filter((id: unknown): id is string => typeof id === "string" && id !== "" && id !== here);
      },
      there: async (station, op, args) => answerText(await bus.ask(station, { method: READ, workspace: cloud.home(), op, args, whole: true })),
    });
    const usage = (changed: () => void) => store.subscribe((change) => void (change.type === "usage" && changed()));
    const stats = yield* Effect.acquireRelease(
      Effect.sync(() => CommaStats.at(data, read, usage)),
      (s) => Effect.sync(() => s.close()),
    );
    yield* connectsPart((options) => makeComma({ ...options, stats }), { kind: "comma", shown: (c, raw) => c.shown(raw), entry: commaEntry });
    // (what offers Comma as a platform in the connect wizard: a station from before says nothing)
    parts.overview("comma", () => true);
    parts.routes(
      commaRoutes({
        config, data,
        hub: () => agents.hub,
        overview: (viewer, lang) => agents.overview(viewer, lang),
        place: () => agents.place(),
      }),
    );
  }),
);
