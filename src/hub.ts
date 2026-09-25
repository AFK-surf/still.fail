// Routes chat messages to session actors, creates sessions, and exposes the
// MCP tools through which agents act on their thread.
import { randomBytes } from "node:crypto";
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { profileFor, RUNTIMES, type Config, type RuntimeKind } from "./config.ts";
import type { ChatSurface, InboundMessage } from "./chat/types.ts";
import { log } from "./log.ts";
import type { Tool } from "./mcp.ts";
import type { AgentDriver } from "./runtime/types.ts";
import { SessionActor, type DeclaredState } from "./session.ts";
import type { Store } from "./store.ts";

export function sessionKey(channel: string, threadTs: string): string {
  return `slack:${channel}:${threadTs}`;
}

/** `[codex] fix the build` picks the runtime for a new session. */
export function runtimeOverride(text: string): RuntimeKind | undefined {
  const match = /^\s*(?:<@[A-Z0-9]+>\s*)*\[(claude|codex)\]/i.exec(text);
  return match ? (match[1]!.toLowerCase() as RuntimeKind) : undefined;
}

export function isStopCommand(text: string): boolean {
  return /^\s*(?:<@[A-Z0-9]+>\s*)*-stop\s*$/i.test(text);
}

export class Hub {
  readonly #config: Config;
  readonly #store: Store;
  readonly #chat: ChatSurface;
  readonly #drivers: Record<RuntimeKind, AgentDriver>;
  readonly #mcpUrl: string;
  readonly #actors = new Map<string, SessionActor>();

  constructor(options: { config: Config; store: Store; chat: ChatSurface; drivers: Record<RuntimeKind, AgentDriver>; mcpUrl: string }) {
    this.#config = options.config;
    this.#store = options.store;
    this.#chat = options.chat;
    this.#drivers = options.drivers;
    this.#mcpUrl = options.mcpUrl;
  }

  get reposDir(): string {
    return join(this.#config.dataDir, "repos");
  }

  /** Accepts one chat message. Resolves once it is durably recorded (or deliberately ignored). */
  async accept(message: InboundMessage): Promise<void> {
    const key = sessionKey(message.channel, message.threadTs);
    let created = false;
    if (!this.#store.getSession(key)) {
      if (!message.addressed) return; // chatter in a thread we are not part of
      try {
        this.#createSession(key, message);
      } catch (error) {
        log.error("cannot create session", { session: key, error });
        await this.#chat.post(message, `⚠️ 无法创建会话：${error instanceof Error ? error.message : String(error)}`);
        return;
      }
      created = true;
    }
    const fresh = this.#store.insertInbound({
      channel: message.channel, ts: message.ts, sessionKey: key, user: message.user, text: message.text, receivedAt: Date.now(),
    });
    if (!fresh) return;
    const actor = this.#actor(key, { earlierMessages: created && message.ts !== message.threadTs });
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
      log.info("recovering a turn cut off by restart", { session: row.key });
      void this.#actor(row.key).recover();
    }
    for (const key of this.#store.sessionsWithPendingInbound()) void this.#actor(key).kick();
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
    const threadOf = (key: string) => {
      const row = this.#store.getSession(key);
      if (!row) throw new Error("unknown session");
      return { channel: row.channel, threadTs: row.threadTs };
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
          await this.#chat.post(threadOf(key), text);
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
          const messages = await this.#chat.history(threadOf(key), before, limit);
          if (messages.length === 0) return "No earlier messages.";
          return messages.map((m) => `<slack user="${m.user}"${m.fromBot ? " bot" : ""} ts="${m.ts}">\n${m.text}\n</slack>`).join("\n");
        },
      },
    ];
  }

  #createSession(key: string, message: InboundMessage): void {
    const channelDefaults = this.#config.channels[message.channel] ?? {};
    const runtime = runtimeOverride(message.text) ?? channelDefaults.runtime ?? this.#config.defaults.runtime;
    const profile = profileFor(this.#config, runtime);
    if (!profile) throw new Error(`no profile configured for runtime ${runtime}`);
    const workspace = join(this.#config.dataDir, "sessions", `${message.channel}-${message.threadTs.replace(".", "-")}`, "workspace");
    mkdirSync(workspace, { recursive: true });
    mkdirSync(this.reposDir, { recursive: true });
    const model = channelDefaults.model ?? this.#config.defaults.model ?? null;
    const now = Date.now();
    this.#store.insertSession({
      key, channel: message.channel, threadTs: message.threadTs, runtime, profile: profile.id, model,
      workspace, token: randomBytes(24).toString("base64url"), createdAt: now, lastActiveAt: now,
    });
    log.info("session created", { session: key, runtime, profile: profile.id });
  }

  #actor(key: string, options: { earlierMessages?: boolean } = {}): SessionActor {
    let actor = this.#actors.get(key);
    if (!actor) {
      actor = new SessionActor(key, {
        store: this.#store,
        chat: this.#chat,
        drivers: this.#drivers,
        profile: (id) => this.#config.profiles.find((p) => p.id === id),
        mcpUrl: this.#mcpUrl,
        reposDir: this.reposDir,
        maxNudges: this.#config.maxNudges,
      }, options);
      this.#actors.set(key, actor);
    }
    return actor;
  }
}
