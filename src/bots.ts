// Keeps one chat connection per enabled bot, following config edits: a new or
// re-tokened bot is (re)connected, a removed or disabled one disconnected, the
// rest left alone.
import type { SlackIdentity } from "./chat/slack.ts";
import type { ChatSurface, InboundMessage } from "./chat/types.ts";
import type { Bot, Config } from "./config.ts";
import { log } from "./log.ts";

export type BotState =
  | { state: "disabled" }
  | { state: "no_tokens" }
  | { state: "starting" }
  | { state: "connected" | "reconnecting"; botUserId: string; lastError: string | null; workspace: SlackIdentity | null }
  | { state: "error"; error: string };

export interface Connection extends ChatSurface {
  readonly status: { connected: boolean; lastError: string | null };
  readonly identity: SlackIdentity | null;
}

export class BotConnections {
  /** Live connections by bot id; shared with the hub, which reads it on every use. */
  readonly chats = new Map<string, Connection>();
  readonly #tokens = new Map<string, string>();
  readonly #errors = new Map<string, string>();
  readonly #create: (bot: Bot) => Connection;
  readonly #onMessage: (botId: string, message: InboundMessage) => Promise<void>;
  #chain: Promise<void> = Promise.resolve();

  constructor(create: (bot: Bot) => Connection, onMessage: (botId: string, message: InboundMessage) => Promise<void>) {
    this.#create = create;
    this.#onMessage = onMessage;
  }

  /** Brings connections in line with `config`. Serialized, so rapid edits apply in order. */
  reconcile(config: Config): Promise<void> {
    this.#chain = this.#chain.then(() => this.#reconcile(config)).catch((error) => log.error("bot reconcile failed", { error }));
    return this.#chain;
  }

  state(bot: Bot): BotState {
    if (!bot.enabled) return { state: "disabled" };
    if (!bot.slack.appToken || !bot.slack.botToken) return { state: "no_tokens" };
    const error = this.#errors.get(bot.id);
    if (error) return { state: "error", error };
    const chat = this.chats.get(bot.id);
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
    const wanted = new Map(config.bots
      .filter((b) => b.enabled && b.slack.appToken && b.slack.botToken)
      .map((b) => [b.id, b]));
    for (const [id, chat] of [...this.chats]) {
      const bot = wanted.get(id);
      if (!bot || this.#tokens.get(id) !== tokenKey(bot)) {
        log.info("disconnecting bot", { bot: id });
        this.chats.delete(id);
        this.#tokens.delete(id);
        await chat.stop();
      }
    }
    for (const id of [...this.#errors.keys()]) if (!wanted.has(id)) this.#errors.delete(id);
    for (const bot of wanted.values()) {
      if (this.chats.has(bot.id)) continue;
      this.#errors.delete(bot.id);
      try {
        const chat = this.#create(bot);
        await chat.start((message) => this.#onMessage(bot.id, message));
        this.chats.set(bot.id, chat);
        this.#tokens.set(bot.id, tokenKey(bot));
        log.info("bot connected", { bot: bot.id, botUserId: chat.botUserId });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        this.#errors.set(bot.id, message);
        log.error("bot failed to connect", { bot: bot.id, error: message });
      }
    }
  }
}

function tokenKey(bot: Bot): string {
  return `${bot.slack.appToken}\n${bot.slack.botToken}`;
}
