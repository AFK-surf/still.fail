// A connect's live link to its chat platform (Slack's, Feishu's: config.json's `connects`), and one kept per enabled
// connect that has what it connects with (connections.rs), following the config: a new or re-credentialed connect is
// (re)connected, a removed or disabled one disconnected, the rest left alone. Rapid edits apply in order.
import { log } from "../ops/log.ts";
import type { ChatEvent, ChatSurface, Handler } from "../sessions/chat.ts";

/// Who a connect's bot is and where, as its platform says: its workspace (Slack's team, Feishu's company), its user
/// there, the name and picture people see.
export type BotIdentity = {
  team: string;
  teamId: string;
  /// The workspace's address, e.g. https://acme.slack.com/ ("" where the platform has none).
  url: string;
  botUserId: string;
  botName: string;
  /// Its picture, as the platform shows it; null when it does not say.
  botImage: string | null;
  /// Slack's bot id (B…), which its own messages carry besides its user; not for the pages.
  botId: string;
};

/// An identity as the pages are given it (without its bot id).
export const shownIdentity = (i: BotIdentity) => ({ team: i.team, teamId: i.teamId, url: i.url, botUserId: i.botUserId, botName: i.botName, botImage: i.botImage });

/// Whether the platform's socket is up, and the last connection error.
export type SocketStatus = { connected: boolean; lastError: string | null };

type Json = any;

/// A kind's part of a connect's config entry (`slack`, `feishu`), from what the page gave of it (`given`) and what it had
/// (`had`): null for none.
export type EntryEdit = (given: unknown, had: Json | null) => Json | null;

/// A kind of connect (config.json's `kind`: Slack's, Feishu's) as its part tells the agents' side (connects/part.ts):
/// how one shows in the overview, how the pages edit its part of its config entry, how it is connected again.
export type ConnectKind = {
  /// Its link to its platform now (null: not known as one of this kind's).
  connection(connect: Json): unknown;
  /// What it is known by (`name`, `team`, `botImage`) and its kind's own fields, its secrets masked.
  shown(connect: Json): Record<string, unknown>;
  entry: EntryEdit;
  /// Connected again, and who its bot is read again (its name changed on the platform shows now).
  reconnect(id: string): Promise<void>;
};

/// A connect's link to its platform, as the pages show it.
export type ConnectState =
  | { state: "disabled" }
  | { state: "no_tokens" }
  | { state: "starting" }
  | { state: "connected" | "reconnecting"; botUserId: string; lastError: string | null; workspace: ReturnType<typeof shownIdentity> | null }
  | { state: "error"; error: string };

/// A live chat connection: a surface, and how its link stands.
export interface Connection extends ChatSurface {
  start(handler: Handler): Promise<void>;
  stop(): Promise<void>;
  socket(): SocketStatus;
  identity(): BotIdentity | null;
  /// Hears whenever `socket` or `identity` changes; gives the function that stops it.
  onChange(listener: () => void): () => void;
  /// Reads again who the bot is and where (its name changed on the platform, say); listeners hear of it.
  refreshIdentity(): Promise<void>;
}

export type Create<C> = (connect: C) => Connection;
export type OnEvent = (connect: string, event: ChatEvent) => Promise<void>;

/// What a connect connects with, as one string (null: it has nothing to connect with yet): a change connects it again.
export type Credentials<C> = (connect: C) => string | null;

/// The connects of one platform (`kind`: what the log calls them), each by what it connects with.
export class Connections<C extends { id: string; enabled: boolean }> {
  /// Live connections by connect id; the hub reads it on every use.
  private chats = new Map<string, Connection>();
  private unlisten = new Map<string, () => void>();
  private tokens = new Map<string, string>();
  private errors = new Map<string, string>();
  private create: Create<C>;
  private credentials: Credentials<C>;
  private onEvent: OnEvent;
  /// Rapid edits apply in order.
  private chain: Promise<void> = Promise.resolve();
  private listeners = new Set<() => void>();

  private kind: string;

  constructor(kind: string, create: Create<C>, onEvent: OnEvent, credentials: Credentials<C>) {
    this.kind = kind;
    this.create = create;
    this.onEvent = onEvent;
    this.credentials = credentials;
  }

  chat(id: string): Connection | undefined {
    return this.chats.get(id);
  }

  ids(): string[] {
    return [...this.chats.keys()];
  }

  /// Hears whenever what `state` reports may have changed; gives the function that stops it.
  onChange(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private changed() {
    for (const listener of this.listeners) {
      try {
        listener();
      } catch (error) {
        log.warn(this.kind, "a listener of the connects failed", { error: (error as Error).message });
      }
    }
  }

  /// Reads again who a connect's bot is (its name, its workspace), as its platform says now.
  async refreshIdentity(id: string) {
    await this.chat(id)?.refreshIdentity();
  }

  state(connect: C): ConnectState {
    if (!connect.enabled) return { state: "disabled" };
    if (this.credentials(connect) === null) return { state: "no_tokens" };
    const error = this.errors.get(connect.id);
    if (error !== undefined) return { state: "error", error };
    const chat = this.chat(connect.id);
    if (!chat) return { state: "starting" };
    const botUserId = chat.botUserId();
    if (botUserId === "") return { state: "starting" };
    const socket = chat.socket();
    const identity = chat.identity();
    return { state: socket.connected ? "connected" : "reconnecting", botUserId, lastError: socket.lastError, workspace: identity ? shownIdentity(identity) : null };
  }

  /// Brings connections in line with `connects`. Serialized, so rapid edits apply in order.
  reconcile(connects: C[]): Promise<void> {
    return this.serially(async () => {
      await this.apply(connects);
      this.changed();
    });
  }

  stopAll(): Promise<void> {
    return this.serially(async () => {
      const chats = [...this.chats.entries()];
      this.chats.clear();
      this.tokens.clear();
      for (const [id] of chats) this.drop(id);
      for (const [, chat] of chats) await chat.stop();
      if (chats.length > 0) this.changed();
    });
  }

  private serially(f: () => Promise<void>): Promise<void> {
    const turn = this.chain.then(f);
    this.chain = turn.catch(() => {});
    return turn;
  }

  private drop(id: string) {
    this.unlisten.get(id)?.();
    this.unlisten.delete(id);
  }

  private async apply(connects: C[]) {
    const wanted = new Map(connects.filter((c) => c.enabled && this.credentials(c) !== null).map((c) => [c.id, c]));
    for (const [id, chat] of [...this.chats]) {
      const want = wanted.get(id);
      if (want && this.tokens.get(id) === this.credentials(want)) continue;
      log.info(this.kind, "disconnecting", { connect: id });
      this.chats.delete(id);
      this.tokens.delete(id);
      this.drop(id);
      await chat.stop();
    }
    for (const id of [...this.errors.keys()]) if (!wanted.has(id)) this.errors.delete(id);
    for (const connect of wanted.values()) {
      if (this.chats.has(connect.id)) continue;
      this.errors.delete(connect.id);
      let chat: Connection | null = null;
      try {
        chat = this.create(connect);
        // Its link's changes are the connects' changes.
        this.unlisten.set(connect.id, chat.onChange(() => this.changed()));
        const id = connect.id;
        await chat.start((event) => this.onEvent(id, event));
        log.info(this.kind, "connected", { connect: connect.id, botUserId: chat.botUserId() });
        this.chats.set(connect.id, chat);
        this.tokens.set(connect.id, this.credentials(connect)!);
      } catch (e) {
        const error = (e as Error).message;
        log.error(this.kind, "failed to connect", { connect: connect.id, error });
        this.drop(connect.id);
        // Started this far: what it opened is closed again.
        await chat?.stop().catch(() => {});
        this.errors.set(connect.id, error);
      }
    }
  }
}
