// Routes chat messages to session actors, creates sessions, and exposes the
// MCP tools through which agents act on their thread. Several bots share one
// hub; each has its own chat connection and its own sessions, so two bots in
// the same thread never share a conversation.
import { randomBytes } from "node:crypto";
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { agentHomePaths } from "./agent-home.ts";
import { profileFor, RUNTIMES, type Bot, type Config, type RuntimeKind } from "./config.ts";
import type { ChatSurface, InboundMessage } from "./chat/types.ts";
import { log } from "./log.ts";
import type { Tool } from "./mcp.ts";
import type { AgentDriver } from "./runtime/types.ts";
import { SessionActor, type DeclaredState } from "./session.ts";
import type { SessionRow, Store } from "./store.ts";

export function sessionKey(bot: string, channel: string, threadTs: string): string {
  return `${bot}:${channel}:${threadTs}`;
}

export function isStopCommand(text: string): boolean {
  return /^\s*(?:<@[A-Z0-9]+>\s*)*-stop\s*$/i.test(text);
}

export class Hub {
  readonly #config: Config;
  readonly #store: Store;
  readonly #chats: ReadonlyMap<string, ChatSurface>;
  readonly #drivers: Record<RuntimeKind, AgentDriver>;
  readonly #mcpUrl: string;
  readonly #actors = new Map<string, SessionActor>();

  /** `chats` holds the connected bots, by bot id; configured bots without one are offline. */
  constructor(options: {
    config: Config;
    store: Store;
    chats: ReadonlyMap<string, ChatSurface>;
    drivers: Record<RuntimeKind, AgentDriver>;
    mcpUrl: string;
  }) {
    this.#config = options.config;
    this.#store = options.store;
    this.#chats = options.chats;
    this.#drivers = options.drivers;
    this.#mcpUrl = options.mcpUrl;
  }

  get reposDir(): string {
    return join(this.#config.dataDir, "repos");
  }

  /** Accepts one message seen by `botId`. Resolves once it is durably recorded (or deliberately ignored). */
  async accept(botId: string, message: InboundMessage): Promise<void> {
    const bot = this.#bot(botId);
    const chat = this.#chat(botId);
    const key = sessionKey(bot.id, message.channel, message.threadTs);
    let created = false;
    if (!this.#store.getSession(key)) {
      if (!message.addressed) return; // chatter in a thread this bot is not part of
      try {
        this.#createSession(key, bot, message);
      } catch (error) {
        log.error("cannot create session", { session: key, error });
        await chat.post(message, `⚠️ 无法创建会话：${error instanceof Error ? error.message : String(error)}`);
        return;
      }
      created = true;
    }
    const fresh = this.#store.insertInbound({
      bot: bot.id, channel: message.channel, ts: message.ts, sessionKey: key,
      user: message.user, text: message.text, receivedAt: Date.now(),
    });
    if (!fresh) return;
    const actor = this.#actor(this.#store.getSession(key)!, { earlierMessages: created && message.ts !== message.threadTs });
    if (isStopCommand(message.text)) {
      const [row] = this.#store.pendingInbound(key).filter((m) => m.ts === message.ts);
      if (row) this.#store.markDelivered([row]);
      void actor.stop();
      return;
    }
    void actor.kick();
  }

  /** After a restart: resume cut-off turns, then deliver whatever is still pending. */
  async recover(): Promise<void> {
    for (const row of this.#store.listSessions().filter((s) => s.running)) {
      if (!this.#online(row)) continue;
      log.info("recovering a turn cut off by restart", { session: row.key });
      void this.#actor(row).recover();
    }
    for (const key of this.#store.sessionsWithPendingInbound()) {
      const row = this.#store.getSession(key);
      if (row && this.#online(row)) void this.#actor(row).kick();
    }
  }

  /** Ends idle claude processes beyond the warm limit, oldest first. Codex threads share a process and stay. */
  evictIdle(now = Date.now()): void {
    const idle = [...this.#actors.values()]
      .filter((a) => a.runtime === "claude")
      .map((actor) => ({ actor, idle: actor.idleMs(now) }))
      .filter((a): a is { actor: SessionActor; idle: number } => a.idle !== null)
      .sort((a, b) => b.idle - a.idle);
    let excess = idle.length - this.#config.maxWarmClaude;
    for (const { actor, idle: ms } of idle) {
      if (excess <= 0 || ms < this.#config.warmMs) break;
      void actor.evict();
      excess--;
    }
  }

  async shutdown(): Promise<void> {
    await Promise.all([...this.#actors.values()].map((a) => a.dispose()));
    await Promise.all(RUNTIMES.map((r) => this.#drivers[r].shutdown()));
  }

  tools(): Tool[] {
    const session = (key: string) => {
      const row = this.#store.getSession(key);
      if (!row) throw new Error("unknown session");
      return { chat: this.#chat(row.bot), thread: { channel: row.channel, threadTs: row.threadTs } };
    };
    const stateArg = (value: unknown): DeclaredState | undefined => {
      if (value === undefined || value === null || value === "") return undefined;
      if (value === "final" || value === "block") return value;
      throw new Error(`kind must be "final" or "block", got ${JSON.stringify(value)}`);
    };
    return [
      {
        name: "chat_post",
        description: "Post a Markdown message to your chat thread. Set kind to \"final\" when this message completes the work, or \"block\" when it asks a person for something you need.",
        inputSchema: {
          type: "object",
          properties: {
            text: { type: "string", description: "Markdown message." },
            kind: { type: "string", enum: ["final", "block"], description: "Omit for a progress update." },
          },
          required: ["text"],
          additionalProperties: false,
        },
        run: async (key, args) => {
          const text = String(args.text ?? "").trim();
          if (!text) throw new Error("text is empty");
          const kind = stateArg(args.kind);
          const { chat, thread } = session(key);
          await chat.post(thread, text);
          if (kind) this.#actors.get(key)?.declare(kind);
          return kind ? `Posted, and recorded state ${kind}.` : "Posted.";
        },
      },
      {
        name: "chat_state",
        description: "Record that this turn ends as final (work done) or block (waiting on a person) without posting another message.",
        inputSchema: {
          type: "object",
          properties: { kind: { type: "string", enum: ["final", "block"] } },
          required: ["kind"],
          additionalProperties: false,
        },
        run: async (key, args) => {
          const kind = stateArg(args.kind);
          if (!kind) throw new Error("kind is required");
          this.#actors.get(key)?.declare(kind);
          return `Recorded state ${kind}.`;
        },
      },
      {
        name: "chat_history",
        description: "Read earlier messages of your chat thread, oldest first.",
        inputSchema: {
          type: "object",
          properties: {
            before: { type: "string", description: "Only messages older than this message ts." },
            limit: { type: "integer", minimum: 1, maximum: 200, description: "Default 30." },
          },
          additionalProperties: false,
        },
        run: async (key, args) => {
          const limit = Math.min(Math.max(Number(args.limit ?? 30) || 30, 1), 200);
          const before = typeof args.before === "string" && args.before ? args.before : undefined;
          const { chat, thread } = session(key);
          const messages = await chat.history(thread, before, limit);
          if (messages.length === 0) return "No earlier messages.";
          return messages.map((m) => `<slack user="${m.user}"${m.fromBot ? " bot" : ""} ts="${m.ts}">\n${m.text}\n</slack>`).join("\n");
        },
      },
    ];
  }

  #bot(id: string): Bot {
    const bot = this.#config.bots.find((b) => b.id === id);
    if (!bot) throw new Error(`unknown bot ${id}`);
    return bot;
  }

  #chat(botId: string): ChatSurface {
    const chat = this.#chats.get(botId);
    if (!chat) throw new Error(`bot ${botId} is not connected`);
    return chat;
  }

  #online(row: SessionRow): boolean {
    if (this.#chats.has(row.bot)) return true;
    log.warn("session belongs to a bot that is not connected; leaving it", { session: row.key, bot: row.bot });
    return false;
  }

  #createSession(key: string, bot: Bot, message: InboundMessage): void {
    const profile = profileFor(this.#config, bot);
    const workspace = join(this.#config.dataDir, "sessions", bot.id, `${message.channel}-${message.threadTs.replace(".", "-")}`, "workspace");
    mkdirSync(workspace, { recursive: true });
    mkdirSync(this.reposDir, { recursive: true });
    const now = Date.now();
    this.#store.insertSession({
      key, bot: bot.id, channel: message.channel, threadTs: message.threadTs, runtime: bot.runtime, profile: profile.id,
      model: bot.model ?? null, workspace, token: randomBytes(24).toString("base64url"), createdAt: now, lastActiveAt: now,
    });
    log.info("session created", { session: key, bot: bot.id, runtime: bot.runtime, profile: profile.id });
  }

  #actor(row: SessionRow, options: { earlierMessages?: boolean } = {}): SessionActor {
    let actor = this.#actors.get(row.key);
    if (!actor) {
      actor = new SessionActor(row.key, {
        store: this.#store,
        chat: this.#chat(row.bot),
        botName: this.#bot(row.bot).name,
        drivers: this.#drivers,
        profile: (id) => this.#config.profiles.find((p) => p.id === id),
        mcpUrl: this.#mcpUrl,
        reposDir: this.reposDir,
        memoryPath: agentHomePaths(this.#config.agentHome).memory,
        maxNudges: this.#config.maxNudges,
      }, options);
      this.#actors.set(row.key, actor);
    }
    return actor;
  }
}
