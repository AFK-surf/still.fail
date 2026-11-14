// The Comma connects as a part of the agents' side (connects/part.ts says what every platform's connects are there): a
// Comma connect as the overview shows it and the pages edit it, and the route that makes one; the workspace's
// statistics and Task index its connections send Comma (stats.ts), the chats of that index as the Router reads and
// writes in them (`task.read`, `task.say`), and what this station answers another's read of them, or write (peer.ts).
import { hostname } from "node:os";
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
import { workspaceIndex } from "./workspace-index.ts";

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
    // The station's workspaces, its home one first: what each connect's index and Router are of. Any change of them
    // moves `scopeVersion`, so that what was read or written before it is not used after.
    const workspaces = () => JSON.stringify([cloud.home(), ...cloud.memberships().map((m) => m.workspace).sort()]);
    const within = (workspace: string) => cloud.membership(workspace) !== null;
    let indexed = workspaces(), scopeVersion = 0;
    yield* Effect.acquireRelease(
      Effect.sync(() => cloud.listen(() => {
        const now = workspaces();
        if (now !== indexed) { indexed = now; scopeVersion++; }
      })),
      (stop) => Effect.sync(stop),
    );
    // A chat's link in the app is made by the reader, of where this station's pages are (sessions/page.ts): the
    // station's own, never what the asker says.
    const linked = (op: string, args: Json) => (op === "outflowChats" ? { ...args, pages: agents.pages() } : args);
    // Another station of the workspace reading this one's statistics, for the Comma connect there.
    bus.on(READ, peerRead((op, args, lang) => readers.read(op, linked(op, args), lang), () => cloud.home(), stationLang,
      () => scopeVersion, (peer, workspace) => { member(cloud, peer, workspace); }));
    const readsFor = (workspace: string): WorkspaceReads => ({
      of: () => ({ workspace, home: workspace === cloud.home() }),
      here: (op, args) => readers.read(op, linked(op, { ...args, lang: stationLang() }), stationLang(), { background: true }),
      others: async () => {
        const roster = await bus.ask("", { method: "peers", workspace });
        if (roster?.current !== true) throw new Error("the roster is not current");
        const here = cloud.state?.station ?? "";
        return (Array.isArray(roster?.stations) ? roster.stations : []).map((e: any) => e?.id).filter((id: unknown): id is string => typeof id === "string" && id !== "" && id !== here);
      },
      there: async (station, op, args) => answerText(await bus.ask(station, { method: READ, workspace, op, args, whole: true })),
    });
    // What moves the statistics or the Task index: the agents' spending, a chat's messages (the Router's too: its
    // first in a chat makes the row `router`) and its turns, and where
    // someone read a chat to (a done chat its creator has not read is one the Task index says waits for them).
    const usage = (changed: () => void) => store.subscribe((change) => void (["usage", "session", "thread", "read"].includes(change.type) && changed()));
    // Keep the old database for Router deduplication across a downgrade. Its unscoped indexes are not sent.
    const legacy = yield* Effect.acquireRelease(
      Effect.sync(() => CommaStats.at(data, async () => ({ stations: [], unread: [] }), usage)),
      (s) => Effect.sync(() => s.close()),
    );
    // A connect of no workspace the station is in now must not receive another's index. Send an empty epoch so Comma
    // also removes rows that an older station already sent to this connect; the regular Task protocol remains there.
    const empty = yield* Effect.acquireRelease(
      Effect.sync(() => {
        const db = new DatabaseSync(":memory:");
        db.exec("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
        return { db, stats: new RevIndex(db, "stats_index"), tasks: new RevIndex(db, "task_index"), start: () => {} };
      }),
      (index) => Effect.sync(() => index.db.close()),
    );
    // The general handover timeout can take sessions up before the older process really exits.
    const said = routerSaysAfter(agents.hub, legacy, previous.exited);
    // Another station of the workspace writing in one of this one's chats, for the Router of the Comma connect there.
    bus.on(SAY, async (_peer: string, request: Json, workspace?: string) => {
      if (typeof workspace !== "string" || !within(workspace)) throw new Error("not this workspace");
      const w = request?.say;
      if (typeof w?.thread !== "number" || typeof w?.text !== "string" || w.text.trim() === "") throw new Error("no such write");
      return { seq: said(workspace, { thread: w.thread, text: w.text, key: String(w.key ?? ""), requester: String(w.requester ?? "Router"), connect: String(w.connect ?? "comma") }) };
    });
    const scopes = yield* Effect.acquireRelease(
      Effect.sync(() => new Map<string, { indexes: ReturnType<typeof workspaceIndex>["indexes"]; stats: CommaStats; chats: CommaChats }>()),
      (all) => Effect.sync(() => { for (const scope of all.values()) scope.stats.close(); }),
    );
    const scope = (workspace: string) => {
      const had = scopes.get(workspace);
      if (had !== undefined) return had;
      const reads = readsFor(workspace);
      const index = workspaceIndex(data, workspace, () => within(workspace), () => scopeVersion, workspaceRead(reads), usage);
      const chats: CommaChats = {
        read: (ref, after, limit) => routerReads(index.stats, reads, ref, after, limit),
        say: async (ref, text, key, requester, connect) => {
          if (!within(workspace)) throw new Error("the workspace changed while writing");
          const chat = chatOf(ref);
          if (chat === null) throw new Error("no such chat");
          const w = { thread: chat.thread, text, key: key === "" ? "" : `${connect}:${key}`, requester, connect };
          if (chat.station === null) return { seq: said(workspace, w) };
          const got = await bus.ask(chat.station, { method: SAY, workspace, say: w });
          return { seq: got?.seq };
        },
      };
      const created = { ...index, chats };
      scopes.set(workspace, created);
      return created;
    };
    const onScopeChange = (changed: () => void) => {
      let seen = scopeVersion;
      return cloud.listen(() => { if (seen !== scopeVersion) { seen = scopeVersion; changed(); } });
    };
    yield* connectsPart((options) => makeComma({ ...options, scope, empty, home: () => cloud.home(), within,
      scopeVersion: () => scopeVersion, onScopeChange, previousExited: previous.exited,
      name: (ws) => {
        const m = cloud.membership(ws ?? cloud.home() ?? "");
        return m === null ? hostname() : `${m.workspace_name} · ${m.name === "" ? hostname() : m.name}`;
      } }), { kind: "comma", shown: (c, raw) => c.shown(raw), entry: commaEntry });
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
