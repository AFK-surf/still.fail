// One actor per session. Every change to a session's state runs through
// its serial queue, so runtime events, deliveries and tool calls never
// interleave halfway.
import { randomUUID } from "node:crypto";
import type { Profile, RuntimeKind } from "./config.ts";
import type { ChatSurface } from "./chat/types.ts";
import { formatInbound, NUDGE, RESUME_AFTER_RESTART, RESUME_LOST, sessionInstructions } from "./instructions.ts";
import { toolStatus } from "./chat/slack-status.ts";
import { log } from "./log.ts";
import type { AgentDriver, AgentSession, LiveEvent, TurnOutcome } from "./runtime/types.ts";
import { EMBER_SURFACE, type PendingMessage, type SessionRow, type Store, type TurnKind } from "./store.ts";

export type DeclaredState = "final" | "block";

export interface SessionDeps {
  store: Store;
  /** A connect's chat connection, when it is connected. A session hears from and answers through several. */
  chat(connect: string): Pick<ChatSurface, "post" | "botUserId" | "botName" | "userName" | "working"> | undefined;
  drivers: Record<RuntimeKind, AgentDriver>;
  profile(id: string): Profile | undefined;
  /** The profile a session's runtime starts on now: its own while usable, else another that can take it on. */
  runOn(key: string): Profile;
  mcpUrl: string;
  reposDir: string;
  memoryPath: string;
  maxNudges: number;
  /** Where the runtime's live steps go, for whoever watches the session. */
  live?: { event(key: string, event: LiveEvent): void; turnEnded(key: string): void };
  /** The runtime process has gone idle (see Hub's eviction deadlines). */
  idle?(key: string): void;
}

interface Turn {
  id: string;
  kind: TurnKind;
  declared: DeclaredState | null;
}

export class SessionActor {
  readonly key: string;
  readonly #deps: SessionDeps;
  #chain: Promise<void> = Promise.resolve();
  #agent: AgentSession | undefined;
  #turn: Turn | undefined;
  #nudges = 0;
  #stopRequested = false;
  #resumeLost = false;
  #closing = false;
  #idleSince = Date.now();

  constructor(key: string, deps: SessionDeps) {
    this.key = key;
    this.#deps = deps;
  }

  get #row(): SessionRow {
    const row = this.#deps.store.getSession(this.key);
    if (!row) throw new Error(`session ${this.key} disappeared`);
    return row;
  }

  get runtime(): RuntimeKind {
    return this.#row.runtime;
  }

  /** running: a turn is in progress; warm: a runtime process is waiting for input; cold: none. */
  get processState(): "running" | "warm" | "cold" {
    if (this.#turn || this.#agent?.busy) return "running";
    return this.#agent ? "warm" : "cold";
  }

  /** How long the runtime process has sat idle, or null if there is none or it is working. */
  idleMs(now = Date.now()): number | null {
    if (!this.#agent || this.#agent.busy || this.#turn) return null;
    return now - this.#idleSince;
  }

  /** Delivers any pending messages. */
  kick(): Promise<void> {
    return this.#enqueue(() => this.#pump());
  }

  /** Called by the MCP tools while a turn runs. */
  declare(state: DeclaredState): void {
    if (this.#turn) this.#turn.declared = state;
  }

  stop(): Promise<void> {
    return this.#enqueue(async () => {
      if (this.#agent?.busy) {
        this.#stopRequested = true;
        await this.#agent.abort();
      }
    });
  }

  /** After ember restarts: the turn recorded as running was cut off; resume it. */
  recover(): Promise<void> {
    return this.#enqueue(async () => {
      this.#deps.store.setRunning(this.key, false);
      const pending = this.#deps.store.pendingMessages(this.key);
      const said = await this.#format(pending);
      await this.#startTurn("resume", said ? `${RESUME_AFTER_RESTART}\n\n${said}` : RESUME_AFTER_RESTART);
      this.#delivered(pending);
    });
  }

  /**
   * Starts the runtime process ahead of a message, so its start-up overlaps
   * the typing. Nothing is sent; an unused process is evicted as usual.
   */
  warm(): Promise<void> {
    return this.#enqueue(async () => {
      if (this.#agent || this.#closing) return;
      log.info("warming session process", { session: this.key });
      await this.#ensureAgent();
      this.#idleSince = Date.now();
      this.#deps.store.notify(this.key);
      this.#deps.idle?.(this.key);
    });
  }

  /** Ends the runtime process if it is idle. */
  evict(): Promise<void> {
    return this.#enqueue(async () => {
      if (!this.#agent || this.#agent.busy || this.#turn) return;
      log.info("evicting idle session process", { session: this.key });
      const agent = this.#agent;
      this.#agent = undefined;
      await agent.dispose();
      this.#deps.store.notify(this.key);
    });
  }

  /**
   * For shutdown. A running turn is left marked running, so the next start
   * resumes it instead of reporting a crash to the thread.
   */
  async dispose(): Promise<void> {
    this.#closing = true; // queued and future tasks are skipped from here on
    const agent = this.#agent;
    this.#agent = undefined;
    await agent?.dispose();
  }

  // ── internals (always inside the queue) ────────────────────────────────

  #enqueue(task: () => Promise<void>): Promise<void> {
    const next = this.#chain.then(() => (this.#closing ? undefined : task())).catch((error: unknown) => log.error("session task failed", { session: this.key, error }));
    this.#chain = next;
    return next;
  }

  async #pump(): Promise<void> {
    const pending = this.#deps.store.pendingMessages(this.key);
    if (pending.length === 0) return;
    const text = await this.#format(pending);
    if (this.#agent?.busy) {
      if (await this.#agent.steer(text)) {
        this.#workFor(pending);
        this.#delivered(pending);
      }
      return; // otherwise delivered when the turn ends
    }
    this.#nudges = 0;
    this.#workFor(pending);
    await this.#startTurn("input", text);
    this.#delivered(pending);
  }

  /** The chat threads the running turn works for, each with the message that brought it in: they are told what it does. */
  #workingFor: { connect: string; thread: { channel: string; threadTs: string }; ts: string | null }[] = [];
  /** Tool calls under way in the running turn, by id: what the status line says. */
  readonly #tools = new Map<string, string>();

  #workFor(messages: readonly PendingMessage[]): void {
    for (const m of messages) {
      if (m.surface === EMBER_SURFACE) continue;
      const at = this.#workingFor.find((w) => w.connect === m.connect && w.thread.channel === m.channel && w.thread.threadTs === m.threadTs);
      if (at) at.ts = m.ts ?? at.ts;
      else this.#workingFor.push({ connect: m.connect, thread: { channel: m.channel, threadTs: m.threadTs }, ts: m.ts ?? null });
    }
    this.#say("正在思考…");
  }

  #say(status: string): void {
    for (const w of this.#workingFor) this.#deps.chat(w.connect)?.working?.(w.thread, w.ts, status);
  }

  /** A live step of the running turn, for its threads' status line. */
  #onLive(event: LiveEvent): void {
    if (this.#workingFor.length === 0) return;
    if (event.kind === "start" && event.step === "tool" && event.tool) this.#tools.set(event.id, event.tool);
    else if (event.kind === "end") this.#tools.delete(event.id);
    else if (event.kind !== "phase") return;
    const tool = [...this.#tools.values()].at(-1);
    this.#say(tool ? toolStatus(tool) : "正在思考…");
  }

  /** The turn is over: its threads' status line goes. */
  #doneWorking(): void {
    this.#say("");
    this.#workingFor = [];
    this.#tools.clear();
  }

  #delivered(messages: readonly PendingMessage[]): void {
    this.#deps.store.markDelivered(this.key, messages.map((m) => ({ thread: m.thread, n: m.n })));
  }

  /**
   * The messages as the agent reads them, made now so edits count: each with
   * its source and sender's name, plus a hint when a thread appears in this
   * session for the first time mid-conversation (its earlier messages are
   * only a chat_history away).
   */
  async #format(said: readonly PendingMessage[]): Promise<string> {
    const heard = this.#deps.store.heardThreads(this.key);
    const newThreads = new Set(said.map((m) => m.thread).filter((t) => !heard.has(t)));
    const names = new Map<string, string>();
    for (const m of said) {
      if (m.authorKind !== "person" || names.has(m.author)) continue;
      const name = await this.#deps.chat(m.connect)?.userName?.(m.author);
      if (name) names.set(m.author, name);
    }
    // What the agent is called in each connect these came through: the bot's name there and its mention.
    const selves = new Map<string, string>();
    for (const connect of new Set(said.map((m) => m.connect))) {
      const chat = this.#deps.chat(connect);
      const name = chat?.botName ?? "";
      const mention = chat?.botUserId && chat.botName ? `<@${chat.botUserId}>` : "";
      if (name) selves.set(connect, mention ? `${name} (${mention})` : name);
    }
    return formatInbound(said, { newThreads, names, selves });
  }

  /**
   * Starts a turn with `text`. On failure the thread is told and the error
   * rethrown, so callers leave their messages pending for the next attempt.
   */
  async #startTurn(kind: TurnKind, text: string): Promise<void> {
    try {
      // Until the runtime says it has sent its request, the turn is starting (a warm process can still take a while to take input).
      this.#deps.live?.event(this.key, { kind: "phase", phase: "starting" });
      let agent = await this.#ensureAgent();
      const prompt = this.#resumeLost ? `${RESUME_LOST}\n\n${text}` : text;
      this.#resumeLost = false;
      // The runtime may have started a turn on its own (late input became a turn); join it.
      if (agent.busy && await agent.steer(prompt)) return;
      this.#beginTurn(kind);
      try {
        await agent.prompt(prompt);
      } catch (error) {
        // The runtime is unusable (died between turns, or refused): replace it once.
        log.warn("prompt failed, reopening the runtime", { session: this.key, error });
        this.#agent = undefined;
        await agent.dispose();
        agent = await this.#ensureAgent();
        await agent.prompt(prompt);
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (this.#turn) this.#deps.store.endTurn(this.#turn.id, "failed", `other: ${message}`, null);
      this.#turn = undefined;
      this.#deps.store.setRunning(this.key, false);
      this.#doneWorking();
      await this.#notice(`⚠️ 无法启动 agent：${message}`);
      throw error;
    }
  }

  #beginTurn(kind: TurnKind): void {
    this.#turn = { id: randomUUID(), kind, declared: null };
    this.#deps.store.startTurn(this.#turn.id, this.key, kind);
    this.#deps.store.setRunning(this.key, true);
  }

  async #ensureAgent(): Promise<AgentSession> {
    if (this.#agent) return this.#agent;
    const row = this.#row;
    const driver = this.#deps.drivers[row.runtime];
    const profile = this.#deps.runOn(this.key);
    const base = {
      profile,
      cwd: row.workspace,
      ...(row.model ? { model: row.model } : {}),
      ...(row.effort ? { effort: row.effort } : {}),
      instructions: sessionInstructions({
        workspace: row.workspace, reposDir: this.#deps.reposDir, memoryPath: this.#deps.memoryPath,
      }),
      mcpToken: row.token,
      mcpUrl: this.#deps.mcpUrl,
      route: row.key,
    };
    let agent: AgentSession;
    const events = {
      turnStarted: () => void this.#enqueue(async () => {
        if (this.#agent === agent && !this.#turn) this.#beginTurn("input");
      }),
      turnEnded: (outcome: TurnOutcome) => {
        this.#deps.live?.turnEnded(this.key);
        this.#doneWorking();
        void this.#enqueue(() => this.#onTurnEnded(agent, outcome));
      },
      live: (event: LiveEvent) => {
        this.#deps.live?.event(this.key, event);
        this.#onLive(event);
      },
      closed: (reason: string) => void this.#enqueue(async () => {
        if (this.#agent === agent) {
          log.info("session runtime closed", { session: this.key, reason });
          this.#agent = undefined;
          this.#deps.store.notify(this.key);
        }
      }),
    };
    if (row.runtimeSessionId) {
      try {
        agent = await driver.open({ ...base, resume: row.runtimeSessionId }, events);
      } catch (error) {
        log.warn("resume failed; starting a new runtime session", { session: this.key, runtimeSessionId: row.runtimeSessionId, error });
        agent = await driver.open(base, events);
        this.#resumeLost = true;
      }
    } else {
      agent = await driver.open(base, events);
    }
    if (agent.id !== row.runtimeSessionId) this.#deps.store.setRuntimeSessionId(this.key, agent.id);
    this.#agent = agent;
    return agent;
  }

  async #onTurnEnded(agent: AgentSession, outcome: TurnOutcome): Promise<void> {
    if (this.#agent !== agent) return;
    const turn = this.#turn;
    this.#turn = undefined;
    this.#idleSince = Date.now();
    this.#deps.store.setRunning(this.key, false);
    if (turn) {
      const detail = outcome.kind === "failed" ? `${outcome.reason}: ${outcome.message}` : null;
      this.#deps.store.endTurn(turn.id, outcome.kind, detail, turn.declared);
    }
    if (outcome.kind === "failed") {
      this.#nudges = 0;
      await this.#notice(failureNotice(outcome));
    } else if (outcome.kind === "aborted") {
      this.#nudges = 0;
      if (this.#stopRequested) await this.#notice("已停止当前任务。");
    }
    this.#stopRequested = false;

    if (this.#deps.store.pendingMessages(this.key).length > 0) {
      await this.#pump();
      return;
    }
    this.#deps.idle?.(this.key);
    if (outcome.kind !== "completed" || turn?.declared) {
      this.#nudges = 0;
      return;
    }
    if (this.#nudges < this.#deps.maxNudges) {
      this.#nudges++;
      log.info("turn ended without a state; nudging", { session: this.key, attempt: this.#nudges });
      await this.#startTurn("nudge", NUDGE);
      return;
    }
    this.#nudges = 0;
    await this.#notice("⚠️ 我停下来了，但没有给出明确结果。如果还需要继续，请直接回复我。");
  }

  /** ember's own words (not the agent's) go to the thread people spoke in last, and are recorded there. */
  async #notice(text: string): Promise<void> {
    const latest = this.#deps.store.latestThread(this.key);
    const chat = latest && this.#deps.chat(latest.connect);
    if (!latest || !chat) {
      log.warn("no thread to post a notice to", { session: this.key, text });
      return;
    }
    try {
      const ts = await chat.post(latest, text);
      this.#deps.store.insertMessage({ thread: latest.id, ts, authorKind: "ember", author: "ember", text });
    } catch (error) {
      log.warn("notice failed", { session: this.key, error });
    }
  }
}

function failureNotice(outcome: Extract<TurnOutcome, { kind: "failed" }>): string {
  switch (outcome.reason) {
    case "auth":
      return `⚠️ 运行时认证失败，需要管理员检查账号：${outcome.message}`;
    case "rate_limit":
      return `⚠️ 触发了额度或限流，请稍后再回复我继续：${outcome.message}`;
    case "exited":
      return `⚠️ agent 进程意外退出（${outcome.message}）。再回复一条消息会自动恢复会话。`;
    default:
      return `⚠️ 这一轮出错了：${outcome.message}`;
  }
}
