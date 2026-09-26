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
//
// Everything said in a thread is recorded once (see store.ts): people's
// messages are delivered to every session in the thread, and what agents and
// ember post there is recorded after the platform takes it.
import { randomBytes } from "node:crypto";
import { copyFileSync, mkdirSync, rmSync, statSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { agentHomePaths } from "./agent-home.ts";
import { EFFORTS, profileFor, RUNTIMES, type Config, type Connect, type Profile, type RuntimeKind } from "./config.ts";
import { pickProfile, type ProfileHealth } from "./pool.ts";
import { INTERNAL_CHANNEL, INTERNAL_CONNECT, nextTs, type InternalChat } from "./chat/internal.ts";
import type { ChatEvent, ChatMessage, ChatSurface, InboundMessage } from "./chat/types.ts";
import { formatHistory, parseThreadAddress, threadAddress } from "./instructions.ts";
import { log } from "./log.ts";
import type { Tool } from "./mcp.ts";
import type { AgentDriver } from "./runtime/types.ts";
import { SessionActor, type DeclaredState } from "./session.ts";
import { EMBER_SURFACE, slackSurface, type Attachment, type Quote, type SessionRow, type SessionScope, type Store, type ThreadRow } from "./store.ts";
import { LiveHub } from "./live.ts";
import { transcriptPath } from "./transcript.ts";
import { imageSize } from "./image-size.ts";

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
  /** When each idle process is next looked at for eviction. */
  readonly #deadlines = new Map<string, ReturnType<typeof setTimeout>>();
  /** How profiles are doing, for the pool; the admin API knows their checks and allowances. */
  #health: (id: string) => ProfileHealth = () => ({ check: null, quota: null });
  readonly #picked = new Map<string, number>();
  /** What running turns are doing, for the admin page's live view. */
  readonly live: LiveHub;

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
    this.live = new LiveHub((key) => {
      const row = this.#store.getSession(key);
      const profile = row && this.#config.profiles.find((p) => p.id === row.profile);
      const path = row?.runtimeSessionId && profile ? transcriptPath(row.runtime, profile.home, row.runtimeSessionId) : undefined;
      return path && row ? { runtime: row.runtime, path } : undefined;
    });
  }

  get #config(): Config {
    return this.#getConfig();
  }

  get reposDir(): string {
    return join(this.#config.dataDir, "repos");
  }

  /** Takes one event from a connect's platform. Resolves once it is durably recorded (or deliberately ignored). */
  async receive(connectId: string, event: ChatEvent): Promise<void> {
    if (event.kind === "message") return this.accept(connectId, event.message);
    const surface = this.#surface(connectId);
    if (event.kind === "changed") this.#store.editMessage(surface, event.channel, event.ts, event.text);
    else this.#store.deleteMessage(surface, event.channel, event.ts);
  }

  /** Accepts one message seen by a connect. Resolves once it is durably recorded (or deliberately ignored). */
  async accept(connectId: string, message: InboundMessage): Promise<void> {
    const connect = this.#connect(connectId);
    const chat = this.#chat(connectId);
    const surface = this.#surface(connectId);
    const single = connect.mode === "single-session";
    const bound = single ? this.#store.binding(connect.id) : undefined;
    const key = single ? bound ?? newSingleSessionKey(connect.id) : sessionKey(connect.id, message.channel, message.threadTs);
    const existing = this.#store.threadAt(surface, message.channel, message.threadTs);
    const members = existing ? this.#store.threadSessions(existing.id) : [];
    const exists = Boolean(this.#store.getSession(key));
    const wanted = single
      ? message.addressed || !connect.requireMention || (exists && members.some((m) => m.session === key))
      : exists || message.addressed;
    // Chatter this connect is not part of, in a thread no session takes part in.
    if (!wanted && members.length === 0) return;
    if (wanted && !exists) {
      try {
        this.#createSession(key, connect, single ? "all" : "thread", message, null, `slack:${connect.id}:${message.user}`);
        if (single) this.#store.setBinding(connect.id, key);
      } catch (error) {
        log.error("cannot create session", { session: key, error });
        await chat.post(message, `⚠️ 无法创建会话：${error instanceof Error ? error.message : String(error)}`);
        return;
      }
    }
    const thread = existing ?? await this.#openSlackThread(chat, surface, message, `slack:${connect.id}:${message.user}`);
    if (wanted) this.#store.joinThread(thread.id, key, connect.id);
    const { seq, fresh } = this.#store.insertMessage({ thread: thread.id, ts: message.ts, authorKind: "person", author: message.user, text: message.text });
    // A message seen by a second connect is already delivered to the thread; only a session it brings in lacks it.
    const targets = fresh ? this.#store.threadSessions(thread.id).map((m) => m.session) : wanted ? [key] : [];
    this.#handOver(seq, targets, message.text);
  }

  /**
   * A Slack thread ember starts following. When that happens mid-thread, what
   * was said before is recorded first (without deliveries), so the thread on
   * ember's page and chat_history are complete and seq keeps Slack's order.
   */
  async #openSlackThread(chat: ChatSurface, surface: string, message: InboundMessage, createdBy: string): Promise<ThreadRow> {
    let earlier: ChatMessage[] = [];
    if (message.ts !== message.threadTs && chat.history) {
      try {
        earlier = await chat.history(message, message.ts, 200);
      } catch (error) {
        log.warn("cannot read what the thread said before; continuing without it", { channel: message.channel, threadTs: message.threadTs, error });
      }
    }
    // Asked before the thread exists, so a connect seeing the same message meanwhile cannot record it ahead of these.
    const thread = this.#store.openThread({ surface, channel: message.channel, threadTs: message.threadTs, createdBy });
    for (const m of earlier) this.#store.insertMessage({ thread: thread.id, ts: m.ts, authorKind: "person", author: m.user, text: m.text });
    return thread;
  }

  /** Gives sessions a message they have not had: each runs it, or stops for `-stop`. */
  #handOver(seq: number, sessions: string[], text: string): void {
    for (const key of this.#store.deliver(seq, sessions)) {
      this.#store.touch(key);
      const row = this.#store.getSession(key);
      if (!row) continue;
      const actor = this.#actor(row);
      if (isStopCommand(text)) {
        this.#store.markDelivered(key, [seq]);
        void actor.stop();
      } else {
        void actor.kick();
      }
    }
  }

  /** After a restart: resume cut-off turns, then deliver whatever is still pending. */
  async recover(): Promise<void> {
    for (const row of this.#store.listSessions().filter((s) => s.running)) {
      if (!this.#online(row)) continue;
      log.info("recovering a turn cut off by restart", { session: row.key });
      void this.#actor(row).recover();
    }
    for (const key of this.#store.sessionsWithPending()) {
      const row = this.#store.getSession(key);
      if (row && this.#online(row)) void this.#actor(row).kick();
    }
  }

  /**
   * Ends idle claude processes beyond the warm limit, oldest first, once
   * they have idled past warmMs. Codex threads share a process and stay.
   * Runs when a process goes idle (the count grew) and at each idle
   * process's deadline (one may have become old enough).
   */
  #evictIdle(now = Date.now()): void {
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

  /** A process went idle: look again when it has idled past warmMs. */
  #idle(key: string): void {
    clearTimeout(this.#deadlines.get(key));
    this.#deadlines.set(key, setTimeout(() => {
      this.#deadlines.delete(key);
      this.#evictIdle();
    }, this.#config.warmMs).unref());
    this.#evictIdle();
  }

  /**
   * Points a single-session connect at a session: an existing one (any
   * session on the same runtime, whichever connect started it) or, with
   * `null`, a new empty one. Returns the bound session's key.
   */
  bindSingle(connectId: string, target: string | null, title?: string, createdBy: string | null = null): string {
    const connect = this.#connect(connectId);
    if (connect.mode !== "single-session") throw new Error(`connect ${connectId} is not single-session`);
    if (target === null) {
      const key = newSingleSessionKey(connect.id);
      this.#createSession(key, connect, "all", null, title?.trim() || null, createdBy);
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

  /**
   * Opens a chat on ember's page with a session in it. Returns the thread.
   * More sessions can join it later (see addToThread).
   */
  openChat(sessionKey: string, createdBy: string, title: string | null = null): ThreadRow {
    if (!this.#internal) throw new Error("ember chat is not available");
    if (!this.#store.getSession(sessionKey)) throw new Error(`unknown session ${sessionKey}`);
    const thread = this.#store.openThread({ surface: EMBER_SURFACE, channel: INTERNAL_CHANNEL, threadTs: nextTs(), title, createdBy });
    this.#store.joinThread(thread.id, sessionKey, INTERNAL_CONNECT);
    return thread;
  }

  /** Brings another session into a chat on ember's page; it hears what is said from then on. */
  addToThread(threadId: number, sessionKey: string): void {
    const thread = this.#store.getThread(threadId);
    if (!thread || thread.surface !== EMBER_SURFACE) throw new Error(`no ember chat ${threadId}`);
    if (!this.#store.getSession(sessionKey)) throw new Error(`unknown session ${sessionKey}`);
    this.#store.joinThread(threadId, sessionKey, INTERNAL_CONNECT);
  }

  /**
   * A person's message in a chat on ember's page: recorded with its quotes
   * and files and delivered to every session in the chat, like a Slack
   * message. Returns its seq.
   */
  say(threadId: number, user: string, text: string, attachments: Attachment[] = [], quotes: Quote[] = []): number {
    const thread = this.#store.getThread(threadId);
    if (!thread || thread.surface !== EMBER_SURFACE) throw new Error(`no ember chat ${threadId}`);
    const { seq } = this.#store.insertMessage({ thread: threadId, ts: nextTs(), authorKind: "person", author: user, text, attachments, quotes });
    this.#handOver(seq, this.#store.threadSessions(threadId).map((m) => m.session), text);
    return seq;
  }

  /**
   * A person's message written on ember's page into a Slack chat: the connect's
   * bot posts it into the thread, saying who wrote it, so the thread stays
   * whole in Slack; it is recorded under the ts Slack gave that post (Slack's
   * echo of the bot's own post is ignored) as the person's, and delivered to
   * every session in the chat. Returns its seq.
   */
  async sayInSlack(threadId: number, user: string, name: string, text: string, quotes: Quote[] = []): Promise<number> {
    const thread = this.#store.getThread(threadId);
    if (!thread || thread.surface === EMBER_SURFACE) throw new Error(`no Slack chat ${threadId}`);
    const members = this.#store.threadSessions(threadId);
    const via = members.map((m) => m.connect).find((c) => c !== INTERNAL_CONNECT);
    if (!via) throw new Error(`Slack chat ${threadId} has no connect`);
    const quoted = quotes.map((q) => `${q.text.split("\n").map((l) => `> ${l}`).join("\n")}${q.comment ? `\n${q.comment}` : ""}`);
    const markdown = [`*${name}*（来自 ember）：`, ...quoted, text].filter(Boolean).join("\n");
    const ts = await this.#chat(via).post({ channel: thread.channel, threadTs: thread.threadTs }, markdown);
    const { seq } = this.#store.insertMessage({ thread: threadId, ts, authorKind: "person", author: user, text, attachments: [], quotes });
    this.#handOver(seq, members.map((m) => m.session), text);
    return seq;
  }

  /** Hides a session from lists, or shows it again. */
  archive(key: string, archived: boolean): void {
    if (!this.#store.getSession(key)) throw new Error(`unknown session ${key}`);
    this.#store.setArchived(key, archived);
  }

  /**
   * Deletes a session: its process ends, its rows go (see Store.deleteSession)
   * and its workspace directory with them. The runtime's transcript stays in
   * the profile's home, which may be a person's own.
   */
  async deleteSession(key: string): Promise<void> {
    const row = this.#store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    const actor = this.#actors.get(key);
    this.#actors.delete(key);
    clearTimeout(this.#deadlines.get(key));
    this.#deadlines.delete(key);
    await actor?.dispose();
    this.live.forget(key);
    this.#store.deleteSession(key);
    // Sessions made by ember keep their workspace in a directory of their own.
    const home = basename(row.workspace) === "workspace" && row.workspace.startsWith(join(this.#config.dataDir, "sessions")) ? dirname(row.workspace) : row.workspace;
    rmSync(home, { recursive: true, force: true });
    log.info("session deleted", { session: key });
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

  /**
   * Copies files the agent attaches into the session's uploads, so the
   * message keeps them even if the originals change, and measures images so
   * pages can hold their place.
   */
  #attach(key: string, paths: string[]): Attachment[] {
    const row = this.#store.getSession(key);
    if (!row) throw new Error("unknown session");
    if (paths.length > 10) throw new Error("at most 10 files per message");
    const dir = join(row.workspace, "uploads");
    mkdirSync(dir, { recursive: true });
    return paths.map((given) => {
      const path = resolve(row.workspace, given);
      let st;
      try {
        st = statSync(path);
      } catch {
        throw new Error(`no such file: ${given}`);
      }
      if (!st.isFile()) throw new Error(`not a file: ${given}`);
      if (st.size > 50 * 1024 * 1024) throw new Error(`too large (over 50 MB): ${given}`);
      const name = basename(path);
      const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
      const copy = join(dir, `${stamp}-${name.replace(/[\\/\u0000-\u001f]/g, "_")}`);
      copyFileSync(path, copy);
      const size = /\.(png|jpe?g|gif|webp)$/i.test(name) ? imageSize(copy) : null;
      return { name, path: copy, size: st.size, ...(size ?? {}) };
    });
  }

  /**
   * A session of its own, talked to in ember's chat: the runtime, profile,
   * model and effort chosen by whoever starts it rather than a connect's.
   * The profile defaults to the first one of that runtime.
   */
  newSession(options: { runtime: RuntimeKind; profile?: string; model?: string; effort?: string; title?: string; createdBy: string }): { key: string; thread: ThreadRow } {
    const profiles = this.#config.profiles.filter((p) => p.runtime === options.runtime);
    if (!profiles.length) throw new Error(`no ${options.runtime} profile configured`);
    const profile = options.profile ? profiles.find((p) => p.id === options.profile) : this.#pick(profiles, options.model?.trim() || null);
    if (!profile) throw new Error(`no ${options.runtime} profile ${options.profile}`);
    if (options.effort && !EFFORTS[options.runtime].includes(options.effort)) throw new Error(`effort must be one of ${EFFORTS[options.runtime].join(", ")}`);
    const key = `${INTERNAL_CONNECT}:c-${randomBytes(5).toString("hex")}`;
    const workspace = join(this.#config.dataDir, "sessions", INTERNAL_CONNECT, key.slice(INTERNAL_CONNECT.length + 1), "workspace");
    mkdirSync(workspace, { recursive: true });
    mkdirSync(this.reposDir, { recursive: true });
    const now = Date.now();
    const title = options.title?.trim() || null;
    this.#store.insertSession({
      key, connect: INTERNAL_CONNECT, scope: "all", title, createdBy: options.createdBy,
      runtime: options.runtime, profile: profile.id, model: options.model?.trim() || profile.model || null, effort: options.effort || null,
      workspace, token: randomBytes(24).toString("base64url"), createdAt: now, lastActiveAt: now,
    });
    log.info("session created", { session: key, connect: INTERNAL_CONNECT, runtime: options.runtime, profile: profile.id, model: options.model ?? null });
    return { key, thread: this.openChat(key, options.createdBy, title) };
  }

  /** Lets the pool see profiles' checks and allowances. */
  setProfileHealth(health: (id: string) => ProfileHealth): void {
    this.#health = health;
  }

  /** Chooses the profile a new session runs on; see pool.ts. */
  #pick(candidates: Profile[], model: string | null, strict = true): Profile {
    const profile = pickProfile(candidates, model, {
      health: (id) => this.#health(id),
      load: (id) => [...this.#actors.entries()].filter(([key, a]) => a.processState !== "cold" && this.#store.getSession(key)?.profile === id).length,
      lastPicked: (id) => this.#picked.get(id) ?? 0,
    }, strict);
    this.#picked.set(profile.id, Date.now());
    return profile;
  }

  /** Starts a session's runtime ahead of a message; see SessionActor.warm. */
  warm(key: string): Promise<void> {
    const row = this.#store.getSession(key);
    return row ? this.#actor(row).warm() : Promise.resolve();
  }

  async shutdown(): Promise<void> {
    for (const timer of this.#deadlines.values()) clearTimeout(timer);
    this.live.close();
    await Promise.all([...this.#actors.values()].map((a) => a.dispose()));
    await Promise.all(RUNTIMES.map((r) => this.#drivers[r].shutdown()));
  }

  tools(): Tool[] {
    /** A thread of this session the agent named with to=, and how the session posts there. */
    const target = (key: string, to: unknown): ThreadRow & { connect: string } => {
      if (!this.#store.getSession(key)) throw new Error("unknown session");
      const known = () => this.#store.sessionThreads(key).map((t) => threadAddress(t.channel, t.threadTs)).join(", ") || "none yet";
      if (typeof to !== "string" || !to.trim()) throw new Error(`to is required: the thread attribute of the message you are answering. This session's threads: ${known()}`);
      const address = parseThreadAddress(to);
      if (!address) throw new Error(`to must look like CHANNEL/THREAD_TS, got ${JSON.stringify(to)}`);
      const thread = this.#store.sessionThread(key, address.channel, address.threadTs);
      if (!thread) throw new Error(`${to} is not a conversation of this session. Its threads: ${known()}`);
      return thread;
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
            files: { type: "array", items: { type: "string" }, description: "Absolute paths of files on this machine to attach (ember chat only; images show inline). Up to 10, 50 MB each." },
          },
          required: ["to"],
          additionalProperties: false,
        },
        run: async (key, args) => {
          const text = String(args.text ?? "").trim();
          const paths = Array.isArray(args.files) ? args.files.map(String) : [];
          if (!text && !paths.length) throw new Error("text is empty");
          const kind = stateArg(args.kind);
          const thread = target(key, args.to);
          const files = paths.length ? this.#attach(key, paths) : [];
          const ts = await this.#chat(thread.connect).post(thread, text, files);
          this.#store.insertMessage({ thread: thread.id, ts, authorKind: "agent", author: key, text, attachments: files, declared: kind ?? null });
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
        description: "Read earlier messages of one of your conversations, oldest first, your own posts included.",
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
          const thread = target(key, args.to);
          const from = before === undefined ? undefined : this.#store.messageAt(thread.id, before);
          if (before !== undefined && !from) throw new Error(`no message ${before} in ${args.to}`);
          const messages = this.#store.messagesBefore(thread.id, from?.seq, limit).filter((m) => m.deletedAt === null);
          if (messages.length === 0) return "No earlier messages.";
          const chat = this.#chatOf(thread.connect);
          const names = new Map<string, string>();
          for (const author of new Set(messages.filter((m) => m.authorKind === "person").map((m) => m.author))) {
            const name = await chat?.userName?.(author);
            if (name) names.set(author, name);
          }
          return formatHistory(messages, { surface: thread.surface, address: threadAddress(thread.channel, thread.threadTs), self: key, names });
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

  /** Where a connect's threads live; the rule the v10 migration follows too. */
  #surface(connectId: string): string {
    return connectId === INTERNAL_CONNECT ? EMBER_SURFACE : slackSurface(connectId, this.#chatOf(connectId)?.workspace);
  }

  #online(row: SessionRow): boolean {
    const via = this.#store.latestThread(row.key)?.connect ?? row.connect;
    if (this.#chatOf(via)) return true;
    log.warn("session's latest thread came through a connect that is not connected; leaving it", { session: row.key, connect: via });
    return false;
  }

  #createSession(key: string, connect: Connect, scope: SessionScope, message: InboundMessage | null, title: string | null = null, createdBy: string | null = null): void {
    const bound = connect.bind.profiles.map((id) => this.#config.profiles.find((p) => p.id === id)).filter((p): p is Profile => Boolean(p));
    const profile = bound.length ? this.#pick(bound, connect.bind.model ?? null, false) : profileFor(this.#config, connect);
    const dir = scope === "all" ? key.slice(connect.id.length + 1) : `${message!.channel}-${message!.threadTs.replace(".", "-")}`;
    const workspace = join(this.#config.dataDir, "sessions", connect.id, dir, "workspace");
    mkdirSync(workspace, { recursive: true });
    mkdirSync(this.reposDir, { recursive: true });
    const now = Date.now();
    this.#store.insertSession({
      key, connect: connect.id, scope, title, createdBy,
      runtime: connect.bind.runtime, profile: profile.id, model: connect.bind.model ?? null, effort: connect.bind.effort ?? null,
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
        live: this.live,
        idle: (key) => this.#idle(key),
      });
      this.#actors.set(row.key, actor);
    }
    return actor;
  }
}
