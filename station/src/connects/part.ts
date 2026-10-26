// A chat platform's connects as a part of the agents' side (parts.ts, docs: connects), as Slack's (slack/module.ts) and
// Feishu's (feishu/module.ts) are: connected while the station is in their workspace, once the sessions are taken up
// (a socket's event goes to one connection of an app; two processes' would split them), and disconnected as it leaves;
// their chats the hub takes and posts to; the names the pages show of their people and chats, looked up as they are
// heard of (who wrote, and where) and, as a connect connects, of the threads people read lately; how its kind of connect
// shows, is edited and is connected again (the agents' `connectKind`); the overview and the sidebar told as they
// change. Stopped before the agents hand their sessions over (its scope closes before theirs): the platform's events go
// to the next process from then on.
import { Effect } from "effect";
import { log } from "../ops/log.ts";
import { Agents } from "../sessions/agents.ts";
import type { ChatSurface } from "../sessions/chat.ts";
import { INTERNAL_CONNECT } from "../sessions/internal.ts";
import { ControlPlane, Events, Paths, StationConfig, Store } from "../services.ts";
import type { ConnectState, Connection, EntryEdit } from "./connections.ts";
import type { ConnectsOptions } from "./connects.ts";

/// What the part needs of a platform's connects (connects.ts makeConnects').
type Connects = {
  chats(id: string): ChatSurface | undefined;
  chat(id: string): Connection | undefined;
  connects(): { id: string }[];
  reconcile(): Promise<void>;
  stopAll(): Promise<void>;
  state(id: string): ConnectState | null;
  onChange(listener: () => void): () => void;
  refreshIdentity(id: string): Promise<void>;
  close(): Promise<void>;
};

type Json = any;

/// What a platform's part says of its kind of connect.
export type KindOf<P> = {
  /// config.json's `kind` of its connects.
  kind: string;
  /// What a connect is known by in the overview, and its kind's own fields (ConnectKind `shown`).
  shown(connects: P, connect: Json): Record<string, unknown>;
  /// Its part of a connect's config entry, as the pages edit it.
  entry: EntryEdit;
  /// What it does once its connects are in line with the config as the station takes its sessions up.
  taken?(connects: P): void;
};

/// The connects `make` makes, kept for the part's scope and wired in as above.
export const connectsPart = <P extends Connects>(make: (options: ConnectsOptions) => P, own: KindOf<P>) =>
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const store = yield* Store;
    const config = yield* StationConfig;
    const events = yield* Events;
    const cloud = (yield* ControlPlane).state;
    const agents = yield* Agents;
    const { hub } = agents;
    const connects = yield* Effect.acquireRelease(
      Effect.sync(() =>
        make({
          data, store, config, receive: (connect, event) => hub.receive(connect, event), bound: () => agents.taken() && agents.bound(),
          inWorkspace: (ws) => ws === null || cloud.membership(ws) !== null,
        }),
      ),
      (c) => Effect.promise(() => c.close()),
    );
    agents.surfaces((id) => connects.chats(id));
    agents.connectKind(own.kind, {
      connection: (c) => connects.state(String(c?.id ?? "")),
      shown: (c) => own.shown(connects, c),
      entry: own.entry,
      reconnect: async (id) => {
        await connects.reconcile();
        await connects.refreshIdentity(id).catch((e) => log.warn(own.kind, "who the bot is not read again", { connect: id, error: (e as Error).message }));
      },
    });
    agents.along({
      taken: async () => {
        await connects.reconcile();
        own.taken?.(connects);
      },
      joined: () => connects.reconcile(),
      // Those of a workspace left disconnect, those of one back connect.
      changed: () => connects.reconcile(),
      left: () => connects.stopAll(),
    });
    // The names the pages show of people and chats are the readers' (from the names book); a connection looks up those
    // it does not know yet as it hears of them. A thread is its connect's: the one its sessions are of.
    const learn = (thread: number, people: string[]) => {
      const t = store.getThread(thread);
      if (t === null) return;
      const connect = store.threadSessions(thread).map((m) => m.connect).find((c) => c !== INTERNAL_CONNECT);
      const chat = connect === undefined ? undefined : connects.chat(connect);
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
    // A connect connected: the threads people read lately, learned once.
    const learned = new Set<string>();
    yield* Effect.acquireRelease(
      Effect.sync(() =>
        connects.onChange(() => {
          for (const c of connects.connects()) {
            if (learned.has(c.id) || connects.state(c.id)?.state !== "connected") continue;
            learned.add(c.id);
            const prefix = `slack:${c.id}:`;
            for (const t of store.listThreads("", null, null).slice(0, 200)) {
              if (t.sessions.some((m) => m.connect === c.id)) learn(t.thread.id, t.people.flatMap((p) => (p.startsWith(prefix) ? [p.slice(prefix.length)] : [])));
            }
          }
        }),
      ),
      (off) => Effect.sync(off),
    );
    // The sidebar names connects and their workspaces.
    yield* Effect.acquireRelease(
      Effect.sync(() => connects.onChange(() => (events.overviewChanged(), events.rowsChanged(null)))),
      (off) => Effect.sync(off),
    );
    return connects;
  });
