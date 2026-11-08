// The Comma connects as a part of the agents' side (connects/part.ts says what every platform's connects are there): a
// Comma connect as the overview shows it and the pages edit it, and the route that makes one; the workspace's
// statistics and Task index its connections send Comma (stats.ts), the chats of that index as the Router reads and
// writes in them (`task.read`, `task.say`), and what this station answers another's read of them, or write (peer.ts).
import { Effect, Layer } from "effect";
import { DatabaseSync } from "node:sqlite";
import { commaEntry, commaRoutes } from "../api/routes/comma.ts";
import { connectsPart } from "../connects/part.ts";
import { member } from "../mesh/peer.ts";
import { stationLang } from "../ops/i18n.ts";
import { Agents } from "../sessions/agents.ts";
import { ControlPlane, Parts, Paths, Peers, Previous, Readers, StationConfig, Store } from "../services.ts";
import { makeComma } from "./index.ts";
import type { CommaChats } from "./surface.ts";
import { READ, SAY, type WorkspaceReads, answerText, peerRead, workspaceRead } from "./peer.ts";
import { routerReads, routerSaysAfter } from "./chats.ts";
import { CommaStats, RevIndex, chatOf } from "./stats.ts";
import { homeIndex } from "./home-index.ts";

type Json = any;

export const CommaLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const config = yield* StationConfig;
    const parts = yield* Parts;
    const agents = yield* Agents;
    const readers = yield* Readers;
    const bus = yield* Peers;
    const store = yield* Store;
    const previous = yield* Previous;
    const cloud = (yield* ControlPlane).state;
    let indexHome = cloud.home(), homeVersion = 0;
    yield* Effect.acquireRelease(
      Effect.sync(() => cloud.listen(() => {
        const home = cloud.home();
        if (home !== indexHome) { indexHome = home; homeVersion++; }
      })),
      (stop) => Effect.sync(stop),
    );
    // Another station of the workspace reading this one's statistics, for the Comma connect there.
    bus.on(READ, peerRead((op, args, lang) => readers.read(op, args, lang), () => cloud.home(), stationLang,
      () => homeVersion, (peer, workspace) => { member(cloud, peer, workspace); }));
    const readsFor = (workspace: string): WorkspaceReads => ({
      home: () => workspace,
      here: (op, args) => readers.read(op, { ...args, lang: stationLang() }, stationLang(), { background: true }),
      others: async () => {
        const roster = await bus.ask("", { method: "peers", workspace });
        if (roster?.current !== true) throw new Error("the roster is not current");
        const here = cloud.state?.station ?? "";
        return (Array.isArray(roster?.stations) ? roster.stations : []).map((e: any) => e?.id).filter((id: unknown): id is string => typeof id === "string" && id !== "" && id !== here);
      },
      there: async (station, op, args) => answerText(await bus.ask(station, { method: READ, workspace, op, args, whole: true })),
    });
    // What moves the statistics or the Task index: the agents' spending, a chat's messages and its turns.
    const usage = (changed: () => void) => store.subscribe((change) => void (["usage", "session", "thread"].includes(change.type) && changed()));
    // Keep the old database for Router deduplication across a downgrade. Its unscoped indexes are not sent.
    const legacy = yield* Effect.acquireRelease(
      Effect.sync(() => CommaStats.at(data, async () => ({ stations: [], unread: [] }), usage)),
      (s) => Effect.sync(() => s.close()),
    );
    // A joined workspace must not receive the home's index. Send an empty epoch so Comma also removes rows that an
    // older station already sent to this connect; the regular Task protocol remains available there.
    const empty = yield* Effect.acquireRelease(
      Effect.sync(() => {
        const db = new DatabaseSync(":memory:");
        db.exec("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
        return { db, stats: new RevIndex(db, "stats_index"), tasks: new RevIndex(db, "task_index"), start: () => {} };
      }),
      (index) => Effect.sync(() => index.db.close()),
    );
    // The general handover timeout can take sessions up before the older process really exits.
    const said = routerSaysAfter(agents.hub, legacy, () => cloud.home(), previous.exited);
    // Another station of the workspace writing in one of this one's chats, for the Router of the Comma connect there.
    bus.on(SAY, async (_peer: string, request: Json, workspace?: string) => {
      if (typeof workspace !== "string" || workspace !== cloud.home()) throw new Error("not this workspace");
      const w = request?.say;
      if (typeof w?.thread !== "number" || typeof w?.text !== "string" || w.text.trim() === "") throw new Error("no such write");
      return { seq: said({ thread: w.thread, text: w.text, key: String(w.key ?? ""), requester: String(w.requester ?? "Router"), connect: String(w.connect ?? "comma") }) };
    });
    const scopes = yield* Effect.acquireRelease(
      Effect.sync(() => new Map<string, { indexes: ReturnType<typeof homeIndex>["indexes"]; stats: CommaStats; chats: CommaChats }>()),
      (all) => Effect.sync(() => { for (const scope of all.values()) scope.stats.close(); }),
    );
    const scope = (workspace: string) => {
      const had = scopes.get(workspace);
      if (had !== undefined) return had;
      const reads = readsFor(workspace);
      const index = homeIndex(data, workspace, () => cloud.home(), () => homeVersion, workspaceRead(reads), usage);
      const chats: CommaChats = {
        read: (ref, after, limit) => routerReads(index.stats, reads, ref, after, limit),
        say: async (ref, text, key, requester, connect) => {
          if (cloud.home() !== workspace) throw new Error("the workspace changed while writing");
          const chat = chatOf(ref);
          if (chat === null) throw new Error("no such chat");
          const w = { thread: chat.thread, text, key: key === "" ? "" : `${connect}:${key}`, requester, connect };
          if (chat.station === null) return { seq: said(w) };
          const got = await bus.ask(chat.station, { method: SAY, workspace, say: w });
          return { seq: got?.seq };
        },
      };
      const created = { ...index, chats };
      scopes.set(workspace, created);
      return created;
    };
    const onHomeChange = (changed: () => void) => {
      let seen = homeVersion;
      return cloud.listen(() => { if (seen !== homeVersion) { seen = homeVersion; changed(); } });
    };
    yield* connectsPart((options) => makeComma({ ...options, scope, empty, home: () => cloud.home(),
      homeVersion: () => homeVersion, onHomeChange, previousExited: previous.exited }), { kind: "comma", shown: (c, raw) => c.shown(raw), entry: commaEntry });
    // (what offers Comma as a platform in the connect wizard: a station from before says nothing)
    parts.overview("comma", () => true);
    parts.routes(
      commaRoutes({
        config, data,
        hub: () => agents.hub,
        overview: (viewer, lang) => agents.overview(viewer, lang),
        place: () => agents.place(),
        heldBy: agents.heldBy,
      }),
    );
  }),
);
