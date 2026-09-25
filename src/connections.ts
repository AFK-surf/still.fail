// Keeps one chat connection per enabled connect, following config edits: a new
// or re-credentialed connect is (re)connected, a removed or disabled one
// disconnected, the rest left alone.
import type { SlackIdentity } from "./chat/slack.ts";
import type { ChatSurface, InboundMessage } from "./chat/types.ts";
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
}

export class Connections {
  /** Live connections by connect id; shared with the hub, which reads it on every use. */
  readonly chats = new Map<string, Connection>();
  readonly #tokens = new Map<string, string>();
  readonly #errors = new Map<string, string>();
  readonly #create: (connect: Connect) => Connection;
  readonly #onMessage: (connectId: string, message: InboundMessage) => Promise<void>;
  #chain: Promise<void> = Promise.resolve();

  constructor(create: (connect: Connect) => Connection, onMessage: (connectId: string, message: InboundMessage) => Promise<void>) {
    this.#create = create;
    this.#onMessage = onMessage;
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
        await chat.start((message) => this.#onMessage(connect.id, message));
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
