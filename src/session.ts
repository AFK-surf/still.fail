// One actor per chat thread. Every change to a session's state runs through
// its serial queue, so runtime events, inbound messages and tool calls never
// interleave halfway.
import { randomUUID } from "node:crypto";
import type { Profile, RuntimeKind } from "./config.ts";
import type { ChatSurface } from "./chat/types.ts";
import { formatInbound, NUDGE, RESUME_AFTER_RESTART, RESUME_LOST, sessionInstructions } from "./instructions.ts";
import { log } from "./log.ts";
import type { AgentDriver, AgentSession, TurnOutcome } from "./runtime/types.ts";
import type { SessionRow, Store, TurnKind } from "./store.ts";

export type DeclaredState = "final" | "block";

export interface SessionDeps {
  store: Store;
  chat: Pick<ChatSurface, "post" | "botUserId">;
  botName: string;
  drivers: Record<RuntimeKind, AgentDriver>;
  profile(id: string): Profile | undefined;
  mcpUrl: string;
  reposDir: string;
  memoryPath: string;
  maxNudges: number;
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
  /** Prefix for the next prompt: the thread had messages before the first mention. */
  #earlierMessages = false;
  #resumeLost = false;
  #closing = false;
  #idleSince = Date.now();

  constructor(key: string, deps: SessionDeps, options: { earlierMessages?: boolean } = {}) {
    this.key = key;
    this.#deps = deps;
    this.#earlierMessages = options.earlierMessages ?? false;
  }

  get #row(): SessionRow {
    const row = this.#deps.store.getSession(this.key);
    if (!row) throw new Error(`session ${this.key} disappeared`);
    return row;
  }

  get runtime(): RuntimeKind {
    return this.#row.runtime;
  }

  /** How long the runtime process has sat idle, or null if there is none or it is working. */
  idleMs(now = Date.now()): number | null {
    if (!this.#agent || this.#agent.busy || this.#turn) return null;
    return now - this.#idleSince;
  }

  /** Delivers any pending inbound messages. */
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
      const pending = this.#deps.store.pendingInbound(this.key);
      const text = pending.length > 0 ? `${RESUME_AFTER_RESTART}\n\n${formatInbound(pending, null)}` : RESUME_AFTER_RESTART;
      await this.#startTurn("resume", text);
      this.#deps.store.markDelivered(pending);
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
    const pending = this.#deps.store.pendingInbound(this.key);
    if (pending.length === 0) return;
    const text = formatInbound(pending, { earlierMessages: this.#earlierMessages });
    if (this.#agent?.busy) {
      if (await this.#agent.steer(text)) this.#deps.store.markDelivered(pending);
      return; // otherwise delivered when the turn ends
    }
    this.#earlierMessages = false;
    this.#nudges = 0;
    await this.#startTurn("input", text);
    this.#deps.store.markDelivered(pending);
  }

  /**
   * Starts a turn with `text`. On failure the thread is told and the error
   * rethrown, so callers leave their messages pending for the next attempt.
   */
  async #startTurn(kind: TurnKind, text: string): Promise<void> {
    try {
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
      const row = this.#row;
      await this.#deps.chat.post({ channel: row.channel, threadTs: row.threadTs }, `⚠️ 无法启动 agent：${message}`);
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
    const profile = this.#deps.profile(row.profile);
    if (!profile) throw new Error(`session ${this.key}: profile ${row.profile} is not configured`);
    const base = {
      profile,
      cwd: row.workspace,
      ...(row.model ? { model: row.model } : {}),
      instructions: sessionInstructions({
        botName: this.#deps.botName, botUserId: this.#deps.chat.botUserId, channel: row.channel, threadTs: row.threadTs,
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
      turnEnded: (outcome: TurnOutcome) => void this.#enqueue(() => this.#onTurnEnded(agent, outcome)),
      closed: (reason: string) => void this.#enqueue(async () => {
        if (this.#agent === agent) {
          log.info("session runtime closed", { session: this.key, reason });
          this.#agent = undefined;
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
    const thread = { channel: this.#row.channel, threadTs: this.#row.threadTs };

    if (outcome.kind === "failed") {
      this.#nudges = 0;
      await this.#deps.chat.post(thread, failureNotice(outcome));
    } else if (outcome.kind === "aborted") {
      this.#nudges = 0;
      if (this.#stopRequested) await this.#deps.chat.post(thread, "已停止当前任务。");
    }
    this.#stopRequested = false;

    if (this.#deps.store.pendingInbound(this.key).length > 0) {
      await this.#pump();
      return;
    }
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
    await this.#deps.chat.post(thread, "⚠️ 我停下来了，但没有给出明确结果。如果还需要继续，请直接回复我。");
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
