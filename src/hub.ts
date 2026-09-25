// Routes chat messages to session actors, creates sessions, and exposes the
// MCP tools through which agents act on their conversations. Several connects
// share one hub; each has its own chat connection and its own sessions.
//
// A connect's mode decides the sessions: multi-session gives each thread its
// own session (started by an @mention); single-session sends every thread the
// connect sees into the one session bound to it, which people can switch or
// replace. Either way every message carries its source and the agent names the
// thread it answers, so a session never assumes it belongs to one conversation;
// replies go out through whichever connect the thread came in on.
import { randomBytes } from "node:crypto";
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { agentHomePaths } from "./agent-home.ts";
import { profileFor, RUNTIMES, type Config, type Connect, type RuntimeKind } from "./config.ts";
import { INTERNAL_CONNECT, type InternalChat } from "./chat/internal.ts";
import type { ChatSurface, InboundMessage, ThreadRef } from "./chat/types.ts";
import { parseThreadAddress, threadAddress } from "./instructions.ts";
import { log } from "./log.ts";
import type { Tool } from "./mcp.ts";
import type { AgentDriver } from "./runtime/types.ts";
import { SessionActor, type DeclaredState } from "./session.ts";
import type { SessionRow, SessionScope, Store } from "./store.ts";

/** A multi-session connect's session for one thread. */
export function sessionKey(connect: string, channel: string, threadTs: string): string {
  return `${connect}:${channel}:${threadTs}`;
}

/** A new session for a single-session connect. */
export function newSingleSessionKey(connect: string): string {
  return `${connect}:s-${randomBytes(4).toString("hex")}`;
}

export function isStopCommand(text: string): boolean {
  return /^\s*(?:<@[A-Z0-9]+>\s*)*-stop\s*$/i.test(text);
}

export class Hub {
  readonly #getConfig: () => Config;
  readonly #store: Store;
  readonly #chats: ReadonlyMap<string, ChatSurface>;
  readonly #internal: InternalChat | undefined;
  readonly #drivers: Record<RuntimeKind, AgentDriver>;
  readonly #mcpUrl: string;
  readonly #actors = new Map<string, SessionActor>();

  /**
   * `config` is read on every use, so edits apply to the next decision.
   * `chats` holds the connected connects by id and may change while running;
   * configured connects without an entry are offline.
   */
  constructor(options: {
    config: () => Config;
    store: Store;
    chats: ReadonlyMap<string, ChatSurface>;
    drivers: Record<RuntimeKind, AgentDriver>;
    mcpUrl: string;
    /** ember's own chat on the admin page; sessions can be talked to there too. */
    internal?: InternalChat;
  }) {
    this.#internal = options.internal;
    this.#getConfig = options.config;
    this.#store = options.store;
    this.#chats = options.chats;
    this.#drivers = options.drivers;
    this.#mcpUrl = options.mcpUrl;
  }

  get #config(): Config {
    return this.#getConfig();
  }

  get reposDir(): string {
    return join(this.#config.dataDir, "repos");
  }

  /** Accepts one message seen by a connect. Resolves once it is durably recorded (or deliberately ignored). */
  async accept(connectId: string, message: InboundMessage): Promise<void> {
    const connect = this.#connect(connectId);
    const chat = this.#chat(connectId);
    const single = connect.mode === "single-session";
    const bound = single ? this.#store.binding(connect.id) : undefined;
    const key = single ? bound ?? newSingleSessionKey(connect.id) : sessionKey(connect.id, message.channel, message.threadTs);
    const exists = Boolean(this.#store.getSession(key));
    const wanted = single
      ? message.addressed || !connect.requireMention || (exists && this.#store.inThread(key, message.channel, message.threadTs))
      : exists || message.addressed;
    if (!wanted) return; // chatter this connect is not part of
    if (!exists) {
      try {
        this.#createSession(key, connect, single ? "all" : "thread", message);
        if (single) this.#store.setBinding(connect.id, key);
      } catch (error) {
        log.error("cannot create session", { session: key, error });
        await chat.post(message, `⚠️ 无法创建会话：${error instanceof Error ? error.message : String(error)}`);
        return;
      }
    }
    const fresh = this.#store.insertInbound({
      connect: connect.id, channel: message.channel, threadTs: message.threadTs, ts: message.ts, sessionKey: key,
      user: message.user, text: message.text, receivedAt: Date.now(),
    });
    if (!fresh) return;
    this.#store.setFirstThread(key, message.channel, message.threadTs);
    this.#store.touch(key);
    const actor = this.#actor(this.#store.getSession(key)!);
    if (isStopCommand(message.text)) {
      const [row] = this.#store.pendingInbound(key).filter((m) => m.ts === message.ts && m.channel === message.channel);
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

  /**
   * Points a single-session connect at a session: an existing one (any
   * session on the same runtime, whichever connect started it) or, with
   * `null`, a new empty one. Returns the bound session's key.
   */
  bindSingle(connectId: string, target: string | null, title?: string): string {
    const connect = this.#connect(connectId);
    if (connect.mode !== "single-session") throw new Error(`connect ${connectId} is not single-session`);
    if (target === null) {
      const key = newSingleSessionKey(connect.id);
      this.#createSession(key, connect, "all", null, title?.trim() || null);
      this.#store.setBinding(connect.id, key);
      return key;
    }
    const row = this.#store.getSession(target);
    if (!row) throw new Error(`unknown session ${target}`);
    if (row.runtime !== connect.bind.runtime) throw new Error(`session ${target} runs ${row.runtime}, the connect runs ${connect.bind.runtime}`);
    this.#store.setBinding(connect.id, target);
    log.info("single-session connect rebound", { connect: connect.id, session: target });
    return target;
  }

  /** Opens a chat on the admin page bound to a session. Returns the chat's thread ts. */
  openChat(sessionKey: string, createdBy: string, title: string | null = null): string {
    if (!this.#internal) throw new Error("ember chat is not available");
    if (!this.#store.getSession(sessionKey)) throw new Error(`unknown session ${sessionKey}`);
    return this.#internal.open(sessionKey, createdBy, title).threadTs;
  }

  /** A person's message in an admin-page chat: recorded there and delivered to the chat's session like any chat message. */
  async sayInChat(threadTs: string, user: string, text: string): Promise<void> {
    if (!this.#internal) throw new Error("ember chat is not available");
    const chat = this.#store.getChat(threadTs);
    if (!chat) throw new Error(`unknown chat ${threadTs}`);
    const row = this.#store.getSession(chat.sessionKey);
    if (!row) throw new Error(`unknown session ${chat.sessionKey}`);
    const message = this.#internal.say(threadTs, user, text);
    this.#store.insertInbound({
      connect: INTERNAL_CONNECT, channel: message.channel, threadTs, ts: message.ts, sessionKey: row.key,
      user, text, receivedAt: Date.now(),
    });
    this.#store.touch(row.key);
    const actor = this.#actor(row);
    if (isStopCommand(text)) {
      this.#store.markDelivered(this.#store.pendingInbound(row.key).filter((m) => m.ts === message.ts));
      void actor.stop();
      return;
    }
    void actor.kick();
  }

  /** Live process state of a session, for the admin page. */
  processState(key: string): "running" | "warm" | "cold" {
    return this.#actors.get(key)?.processState ?? "cold";
  }

  /** Interrupts the session's running turn, as `-stop` in a thread would. */
  stop(key: string): Promise<void> {
    const row = this.#store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    return this.#actor(row).stop();
  }

  /** Ends the session's runtime process if it is idle; the conversation resumes on the next message. */
  evict(key: string): Promise<void> {
    return this.#actors.get(key)?.evict() ?? Promise.resolve();
  }

  async shutdown(): Promise<void> {
    await Promise.all([...this.#actors.values()].map((a) => a.dispose()));
    await Promise.all(RUNTIMES.map((r) => this.#drivers[r].shutdown()));
  }

  tools(): Tool[] {
    /** The connection and a thread of this session the agent named with to=. */
    const target = (key: string, to: unknown): { chat: ChatSurface; thread: ThreadRef } => {
      const row = this.#store.getSession(key);
      if (!row) throw new Error("unknown session");
      const known = () => this.#store.listThreads(key).map((t) => threadAddress(t.channel, t.threadTs)).join(", ") || "none yet";
      if (typeof to !== "string" || !to.trim()) throw new Error(`to is required: the thread attribute of the message you are answering. This session's threads: ${known()}`);
      const thread = parseThreadAddress(to);
      if (!thread) throw new Error(`to must look like CHANNEL/THREAD_TS, got ${JSON.stringify(to)}`);
      const via = this.#store.threadConnect(key, thread.channel, thread.threadTs);
      if (!via) throw new Error(`${to} is not a conversation of this session. Its threads: ${known()}`);
      return { chat: this.#chat(via), thread };
    };
    const stateArg = (value: unknown): DeclaredState | undefined => {
      if (value === undefined || value === null || value === "") return undefined;
      if (value === "final" || value === "block") return value;
      throw new Error(`kind must be "final" or "block", got ${JSON.stringify(value)}`);
    };
    const to = { type: "string", description: "CHANNEL/THREAD_TS: the thread attribute of the message you are answering." };
    return [
      {
        name: "chat_post",
        description: "Post a Markdown message to one of your conversations. Set kind to \"final\" when this message completes the work, or \"block\" when it asks a person for something you need.",
        inputSchema: {
          type: "object",
          properties: {
            to,
            text: { type: "string", description: "Markdown message." },
            kind: { type: "string", enum: ["final", "block"], description: "Omit for a progress update." },
          },
          required: ["to", "text"],
          additionalProperties: false,
        },
        run: async (key, args) => {
          const text = String(args.text ?? "").trim();
          if (!text) throw new Error("text is empty");
          const kind = stateArg(args.kind);
          const { chat, thread } = target(key, args.to);
          await chat.post(thread, text);
          if (kind) this.#actors.get(key)?.declare(kind);
          const where = threadAddress(thread.channel, thread.threadTs);
          return kind ? `Posted to ${where}, and recorded state ${kind}.` : `Posted to ${where}.`;
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
        description: "Read earlier messages of one of your conversations, oldest first.",
        inputSchema: {
          type: "object",
          properties: {
            to,
            before: { type: "string", description: "Only messages older than this message ts." },
            limit: { type: "integer", minimum: 1, maximum: 200, description: "Default 30." },
          },
          required: ["to"],
          additionalProperties: false,
        },
        run: async (key, args) => {
          const limit = Math.min(Math.max(Number(args.limit ?? 30) || 30, 1), 200);
          const before = typeof args.before === "string" && args.before ? args.before : undefined;
          const { chat, thread } = target(key, args.to);
          const messages = await chat.history(thread, before, limit);
          if (messages.length === 0) return "No earlier messages.";
          const address = threadAddress(thread.channel, thread.threadTs);
          return messages.map((m) => `<message via="slack" thread="${address}" from="${m.user}"${m.fromBot ? " bot" : ""} ts="${m.ts}">\n${m.text}\n</message>`).join("\n");
        },
      },
    ];
  }

  #connect(id: string): Connect {
    const connect = this.#config.connects.find((c) => c.id === id);
    if (!connect) throw new Error(`unknown connect ${id}`);
    return connect;
  }

  #chat(connectId: string): ChatSurface {
    const chat = this.#chatOf(connectId);
    if (!chat) throw new Error(`connect ${connectId} is not connected`);
    return chat;
  }

  #chatOf(connectId: string): ChatSurface | undefined {
    return connectId === INTERNAL_CONNECT ? this.#internal : this.#chats.get(connectId);
  }

  #online(row: SessionRow): boolean {
    const via = this.#store.latestInbound(row.key)?.connect ?? row.connect;
    if (this.#chatOf(via)) return true;
    log.warn("session's latest thread came through a connect that is not connected; leaving it", { session: row.key, connect: via });
    return false;
  }

  #createSession(key: string, connect: Connect, scope: SessionScope, message: InboundMessage | null, title: string | null = null): void {
    const profile = profileFor(this.#config, connect);
    const dir = scope === "all" ? key.slice(connect.id.length + 1) : `${message!.channel}-${message!.threadTs.replace(".", "-")}`;
    const workspace = join(this.#config.dataDir, "sessions", connect.id, dir, "workspace");
    mkdirSync(workspace, { recursive: true });
    mkdirSync(this.reposDir, { recursive: true });
    const now = Date.now();
    this.#store.insertSession({
      key, connect: connect.id, scope, title, channel: message?.channel ?? "", threadTs: message?.threadTs ?? "",
      runtime: connect.bind.runtime, profile: profile.id, model: connect.bind.model ?? null,
      workspace, token: randomBytes(24).toString("base64url"), createdAt: now, lastActiveAt: now,
    });
    log.info("session created", { session: key, connect: connect.id, scope, runtime: connect.bind.runtime, profile: profile.id });
  }

  #actor(row: SessionRow): SessionActor {
    let actor = this.#actors.get(row.key);
    if (!actor) {
      actor = new SessionActor(row.key, {
        store: this.#store,
        chat: (id) => this.#chatOf(id),
        // In ember's own chat the agent keeps the name of the connect that started it.
        name: (id) => this.#config.connects.find((c) => c.id === (id === INTERNAL_CONNECT ? row.connect : id))?.name ?? id,
        drivers: this.#drivers,
        profile: (id) => this.#config.profiles.find((p) => p.id === id),
        mcpUrl: this.#mcpUrl,
        reposDir: this.reposDir,
        memoryPath: agentHomePaths(this.#config.agentHome).memory,
        maxNudges: this.#config.maxNudges,
      });
      this.#actors.set(row.key, actor);
    }
    return actor;
  }
}
