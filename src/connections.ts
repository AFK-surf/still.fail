// Keeps one chat connection per enabled connect, following config edits: a new
// or re-credentialed connect is (re)connected, a removed or disabled one
// disconnected, the rest left alone.
import { EventEmitter } from "node:events";
import type { SlackIdentity } from "./chat/slack.ts";
import type { ChatEvent, ChatSurface } from "./chat/types.ts";
import type { Config, Connect } from "./config.ts";
import { log } from "./log.ts";

export type ConnectState =
  | { state: "disabled" }
  | { state: "no_tokens" }
  | { state: "starting" }
  | { state: "connected" | "reconnecting"; botUserId: string; lastError: string | null; workspace: SlackIdentity | null }
  | { state: "error"; error: string };

export interface Connection extends ChatSurface {
  readonly status: { connected: boolean; lastError: string | null };
  readonly identity: SlackIdentity | null;
  /** Calls `listener` whenever `status` changes. */
  onStatus(listener: () => void): void;
}

export class Connections {
  /** Live connections by connect id; shared with the hub, which reads it on every use. */
  readonly chats = new Map<string, Connection>();
  /** Emits "change" whenever what state() reports may have changed. */
  readonly changes = new EventEmitter();
  readonly #tokens = new Map<string, string>();
  readonly #errors = new Map<string, string>();
  readonly #create: (connect: Connect) => Connection;
  readonly #onEvent: (connectId: string, event: ChatEvent) => Promise<void>;
  #chain: Promise<void> = Promise.resolve();

  constructor(create: (connect: Connect) => Connection, onEvent: (connectId: string, event: ChatEvent) => Promise<void>) {
    this.#create = create;
    this.#onEvent = onEvent;
  }

  /** Brings connections in line with `config`. Serialized, so rapid edits apply in order. */
  reconcile(config: Config): Promise<void> {
    this.#chain = this.#chain.then(() => this.#reconcile(config)).catch((error) => log.error("reconcile failed", { error }));
    return this.#chain;
  }

  state(connect: Connect): ConnectState {
    if (!connect.enabled) return { state: "disabled" };
    if (!connect.slack.appToken || !connect.slack.botToken) return { state: "no_tokens" };
    const error = this.#errors.get(connect.id);
    if (error) return { state: "error", error };
    const chat = this.chats.get(connect.id);
    if (!chat || !chat.botUserId) return { state: "starting" };
    return {
      state: chat.status.connected ? "connected" : "reconnecting",
      botUserId: chat.botUserId, lastError: chat.status.lastError, workspace: chat.identity,
    };
  }

  async stopAll(): Promise<void> {
    await this.#chain;
    await Promise.all([...this.chats.values()].map((chat) => chat.stop()));
    this.chats.clear();
  }

  async #reconcile(config: Config): Promise<void> {
    try {
      await this.#apply(config);
    } finally {
      this.changes.emit("change");
    }
  }

  async #apply(config: Config): Promise<void> {
    const wanted = new Map(config.connects
      .filter((b) => b.enabled && b.slack.appToken && b.slack.botToken)
      .map((b) => [b.id, b]));
    for (const [id, chat] of [...this.chats]) {
      const connect = wanted.get(id);
      if (!connect || this.#tokens.get(id) !== tokenKey(connect)) {
        log.info("disconnecting", { connect: id });
        this.chats.delete(id);
        this.#tokens.delete(id);
        await chat.stop();
      }
    }
    for (const id of [...this.#errors.keys()]) if (!wanted.has(id)) this.#errors.delete(id);
    for (const connect of wanted.values()) {
      if (this.chats.has(connect.id)) continue;
      this.#errors.delete(connect.id);
      try {
        const chat = this.#create(connect);
        chat.onStatus(() => this.changes.emit("change"));
        await chat.start((event) => this.#onEvent(connect.id, event));
        this.chats.set(connect.id, chat);
        this.#tokens.set(connect.id, tokenKey(connect));
        log.info("connected", { connect: connect.id, botUserId: chat.botUserId });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        this.#errors.set(connect.id, message);
        log.error("failed to connect", { connect: connect.id, error: message });
      }
    }
  }
}

function tokenKey(connect: Connect): string {
  return `${connect.slack.appToken}\n${connect.slack.botToken}`;
}
