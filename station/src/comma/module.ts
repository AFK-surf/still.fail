// The Comma connects as a part of the agents' side (connects/part.ts says what every platform's connects are there): a
// Comma connect as the overview shows it and the pages edit it, and the route that makes one; the workspace's
// statistics and Task index its connections send Comma (stats.ts), the chats of that index as the Router reads and
// writes in them (`task.read`, `task.say`), and what this station answers another's read of them, or write (peer.ts).
import { Effect, Layer } from "effect";
import { commaEntry, commaRoutes } from "../api/routes/comma.ts";
import { connectsPart } from "../connects/part.ts";
import { stationLang } from "../ops/i18n.ts";
import { Agents } from "../sessions/agents.ts";
import { ControlPlane, Parts, Paths, Peers, Readers, StationConfig, Store } from "../services.ts";
import { makeComma } from "./index.ts";
import type { CommaChats } from "./surface.ts";
import { READ, SAY, type WorkspaceReads, answerText, peerRead, workspaceRead } from "./peer.ts";
import { routerSays } from "./chats.ts";
import { CommaStats, chatOf } from "./stats.ts";

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
    const cloud = (yield* ControlPlane).state;
    // Another station of the workspace reading this one's statistics, for the Comma connect there.
    bus.on(READ, peerRead((op, args, lang) => readers.read(op, args, lang), () => cloud.home(), stationLang));
    const reads: WorkspaceReads = {
      home: () => cloud.home(),
      here: (op, args) => readers.read(op, { ...args, lang: stationLang() }, stationLang(), { background: true }),
      others: async () => {
        const roster = await bus.ask("", { method: "peers", workspace: cloud.home() });
        if (roster?.current !== true) throw new Error("the roster is not current");
        const here = cloud.state?.station ?? "";
        return (Array.isArray(roster?.stations) ? roster.stations : []).map((e: any) => e?.id).filter((id: unknown): id is string => typeof id === "string" && id !== "" && id !== here);
      },
      there: async (station, op, args) => answerText(await bus.ask(station, { method: READ, workspace: cloud.home(), op, args, whole: true })),
    };
    const read = workspaceRead(reads);
    // What moves the statistics or the Task index: the agents' spending, a chat's messages and its turns.
    const usage = (changed: () => void) => store.subscribe((change) => void (["usage", "session", "thread"].includes(change.type) && changed()));
    const stats = yield* Effect.acquireRelease(
      Effect.sync(() => CommaStats.at(data, read, usage)),
      (s) => Effect.sync(() => s.close()),
    );
    const said = (w: { thread: number; text: string; key: string; requester: string; connect: string }) => routerSays(agents.hub, stats, cloud.home(), w);
    // Another station of the workspace writing in one of this one's chats, for the Router of the Comma connect there.
    bus.on(SAY, async (_peer: string, request: Json, workspace?: string) => {
      if (typeof workspace !== "string" || workspace !== cloud.home()) throw new Error("not this workspace");
      const w = request?.say;
      if (typeof w?.thread !== "number" || typeof w?.text !== "string" || w.text.trim() === "") throw new Error("no such write");
      return { seq: said({ thread: w.thread, text: w.text, key: String(w.key ?? ""), requester: String(w.requester ?? "Router"), connect: String(w.connect ?? "comma") }) };
    });
    const chats: CommaChats = {
      read: async (ref, after, limit) => {
        const chat = chatOf(ref);
        if (chat === null) throw new Error("no such chat");
        const args = { thread: chat.thread, after, limit };
        const home = cloud.home();
        const got = JSON.parse(chat.station === null
          ? await reads.here("outflowMessages", home === null ? args : { ...args, ws: { workspace: home, home: true } })
          : await reads.there(chat.station, "outflowMessages", args));
        if (got === null) throw new Error("no such chat of the workspace");
        const title = stats.tasks.since(0, 1_000_000).find((r) => r.key === ref && !r.removed);
        return {
          title: title === undefined ? "" : JSON.parse(title.json).title,
          messages: (got.messages as Json[]).filter((m) => m.kind === "message").map((m) => ({
            seq: m.n, author_kind: m.authorKind, author: m.person?.name ?? m.person?.email ?? m.author, text: m.text, at: m.at,
          })),
          through: got.last,
        };
      },
      say: async (ref, text, key, requester, connect) => {
        const chat = chatOf(ref);
        if (chat === null) throw new Error("no such chat");
        const w = { thread: chat.thread, text, key: key === "" ? "" : `${connect}:${key}`, requester, connect };
        if (chat.station === null) return { seq: said(w) };
        const got = await bus.ask(chat.station, { method: SAY, workspace: cloud.home(), say: w });
        return { seq: got?.seq };
      },
    };
    yield* connectsPart((options) => makeComma({ ...options, stats, chats }), { kind: "comma", shown: (c, raw) => c.shown(raw), entry: commaEntry });
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
