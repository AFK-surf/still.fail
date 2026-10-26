// The connects of one chat platform on the station (Slack's: slack/index.ts; Feishu's: feishu/index.ts): their
// connections as config.json and the station's workspace say, connected while the station is in the connect's workspace
// and following config edits, disconnected out of it; what the platform calls people and chats (a names book in the data
// directory); and what each connected connect is known by (its bot's name and picture, its workspace), kept in
// config.json so that it shows by them while it is not connected too. Each connected connect's surface is the hub's
// (`chats`), and what the platform says reaches the hub through `receive`.
import { join } from "node:path";
import type { ConfigFile } from "../ops/config.ts";
import { log } from "../ops/log.ts";
import type { ChatEvent, ChatSurface } from "../sessions/chat.ts";
import type { Store } from "../store/store.ts";
import { type BotIdentity, type ConnectState, type Connection, Connections, type Credentials } from "./connections.ts";
import { NameBook } from "./names.ts";

type Json = any;

/// What every connect is in config.json, as far as its connection goes.
export type ConnectBase = { id: string; enabled: boolean; workspace?: string | null };

export type ConnectsOptions = {
  data: string;
  store: Store;
  config: ConfigFile;
  /// Takes what a connect's platform says (the hub's `receive`); resolves once it is kept, and only then is the
  /// platform told it arrived.
  receive: (connect: string, event: ChatEvent) => Promise<void>;
  /// Whether the station is in its workspace: only then are connects connected.
  bound: () => boolean;
  /// Whether the station is in a connect's workspace (null: its home one) now: a joined workspace's connects
  /// disconnect once it leaves that workspace (docs/multi-workspace.md). Absent: every one.
  inWorkspace?: (workspace: string | null) => boolean;
};

/// A platform, as its connects are kept.
export type Platform<C extends ConnectBase> = {
  /// config.json's `kind` of its connects (Slack's: none or "slack"), what the log calls it.
  kind: string;
  /// Its names book, in the data directory.
  names: string;
  /// Its connects in config.json.
  connects(raw: Json): C[];
  credentials: Credentials<C>;
  /// A connect's connection.
  create(connect: C, names: NameBook): Connection;
  /// What a connected connect is known by now, written into its config.json entry: null when that is what it has.
  seen(connect: C, identity: BotIdentity): ((entry: Json) => void) | null;
};

export function makeConnects<C extends ConnectBase>(options: ConnectsOptions, platform: Platform<C>) {
  const { config, store } = options;
  // What the platform calls people and chats, kept on disk; learning new ones refreshes what shows them. Saved before
  // the pages are told: the readers read the names from the file.
  const names = new NameBook(join(options.data, platform.names), { saveAfterMs: 200, learnAfterMs: 400 });
  // (The sessions shown: an archived one's summary is read again as it is shown, names and all.)
  names.onLearn(() => {
    for (const session of store.liveSessions()) store.notify(session.key);
  });
  const connections = new Connections<C>(platform.kind, (c) => platform.create(c, names), options.receive, platform.credentials);
  const connects = () => platform.connects(config.raw());
  const connect = (id: string) => connects().find((c) => c.id === id);

  let closed = false;
  /// In line with config.json while in the workspace; out of it, none connected.
  const reconcile = async () => {
    if (closed) return;
    if (options.bound()) await connections.reconcile(connects().filter((c) => options.inWorkspace?.(c.workspace ?? null) ?? true));
    else await connections.stopAll();
  };

  const rememberIdentities = () => {
    const seen = new Map<string, (entry: Json) => void>();
    for (const c of connects()) {
      const identity = connections.chat(c.id)?.identity();
      if (!identity || identity.botUserId === "") continue;
      const write = platform.seen(c, identity);
      if (write !== null) seen.set(c.id, write);
    }
    if (seen.size === 0) return;
    try {
      config.update((raw) => {
        for (const entry of Array.isArray(raw.connects) ? raw.connects : []) {
          if ((entry?.kind ?? "slack") === platform.kind) seen.get(entry.id)?.(entry);
        }
      });
    } catch (error) {
      log.warn(platform.kind, "connects' identities not kept", { error: (error as Error).message });
    }
  };
  // Looked at once after a burst of changes, not inside them.
  let remembering = false;
  const listeners = new Set<() => void>();
  /// Tells those that hear of the connects that what `state` reports may have changed.
  const tell = () => {
    for (const listener of listeners) {
      try {
        listener();
      } catch {}
    }
  };
  connections.onChange(() => {
    tell();
    if (remembering || closed) return;
    remembering = true;
    setImmediate(() => {
      remembering = false;
      if (!closed) rememberIdentities();
    });
  });

  // Edits apply as they are saved.
  const unlisten = config.listen(() => {
    void reconcile().catch((error) => log.warn(platform.kind, "connects not brought in line with the config", { error: (error as Error).message }));
  });

  return {
    connections,
    names,
    /// A connected connect's surface, for the hub (HubOptions.chats).
    chats: (id: string): ChatSurface | undefined => connections.chat(id),
    /// A connected connect's connection.
    chat: (id: string): Connection | undefined => connections.chat(id),
    /// config.json's connects, as their connections read them.
    connects,
    /// In line with config.json and the workspace now: connected while in it, disconnected out of it.
    reconcile,
    stopAll: () => connections.stopAll(),
    refreshIdentity: (id: string) => connections.refreshIdentity(id),
    /// A connect's link to its platform as the pages show it (the overview's `connection`).
    state: (c: string | C): ConnectState | null => {
      const found = typeof c === "string" ? connect(c) : c;
      return found ? connections.state(found) : null;
    },
    /// Hears whenever what `state` reports may have changed (the overview's events).
    onChange: (listener: () => void) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    tell,
    /// Stops listening, disconnects every connect, and keeps the names learned.
    close: async () => {
      closed = true;
      unlisten();
      listeners.clear();
      await connections.stopAll();
      await names.close();
    },
  };
}
