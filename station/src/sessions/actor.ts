// One actor per session (the Rust station's session.rs): every change to a session's state runs through its serial queue, so
// runtime events, deliveries and tool calls never interleave halfway. Redesigned on two points:
// - Where it stands is one value (`phase`): idle, starting, running, waiting, or closed; not three flags kept apart.
// - What tools say of the running turn (its state, need, about, what it waits for) goes through the queue too, and the
//   tool answers once it is recorded: a turn's end comes after the tool's answer, so nothing a tool said is lost.
// Its process is a runner's (src/agents/runner.ts): this actor can go (a station stopping or handing over) and the
// next take it up (`snapshot` / `adopt`), its turn going on all along.
import { presetCopyOf, presetInstructions } from "./presets.ts";
import { sessionSkills } from "./agent-home.ts";
import { writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { Clock, Effect, Exit, FiberSet, Scope, Semaphore } from "effect";
import type { AgentDriver, AgentSession, BackgroundTask, FailureReason, LiveEvent, OpenOptions, Profile, RuntimeEvent, TurnOutcome } from "../agents/runtime.ts";
import { BACKGROUND_STOPPED_WAITING, GO_ON_AFTER_AUTH, GO_ON_AFTER_CODEX_UPDATE, GO_ON_AFTER_FAILED, GO_ON_AFTER_OVERLOADED, GO_ON_AFTER_REFILL, GO_ON_AFTER_SPENT, NUDGE, RESUME_AFTER_RESTART, TOOLS_LOST, afresh as afreshNote, backgroundStopped, cleared, continuedHere, formatCardChoices, formatInbound, formatWidgetModels, nameUntitled, readMemory, resumeLost, sessionInstructions, waitOver } from "../agents/instructions.ts";
import { chars } from "../agents/live.ts";
import { CommandMissing } from "../agents/runner.ts";
import { latest as latestNote, untold } from "../agents/migrations.ts";
import { unreadableDir, unreadableDirMessage } from "../ops/files.ts";
import { Places } from "../ops/places.ts";
import { log } from "../ops/log.ts";
import { Said, tr, stationLang } from "../ops/i18n.ts";
import { failureOf, modelLimitOf, runtimeKind, runtimeLabel, type RuntimeKind } from "../agents/runtime.ts";
import { type CardChoice, type DeliveryCardState, type Handed, type MessageRow, type PendingMessage, type RunChange, handedOf } from "../store/rows.ts";
import { runChangeWords } from "./run-change.ts";
import { PostBlocksUnavailable } from "../store/post-blocks.ts";
import { WidgetSourcesUnavailable } from "../store/widget-sources.ts";
import { STATION_AUTHOR, STILLFAIL_SURFACE } from "../store/rows.ts";
import { INTERNAL_CONNECT } from "./internal.ts";

/// How an agent ended its turn (chat_post / chat_state `kind`).
export type DeclaredState = { kind: "all_done" } | { kind: "need_help" } | { kind: "waiting"; seconds: number };

/// A kind as kept or given, the words from before these included: final is all_done, block and need_decision need_help.
export function parseDeclared(kind: string, wait: number): DeclaredState | null {
  if (kind === "all_done" || kind === "final") return { kind: "all_done" };
  if (["need_human", "need_help", "block", "need_decision"].includes(kind)) return { kind: "need_help" };
  if (kind === "waiting") return { kind: "waiting", seconds: wait };
  return null;
}

/// The turn ended as the agent's to take up again only when a person (or nothing) brings it back: not waiting.
const settled = (d: DeclaredState) => d.kind !== "waiting";

/// What a turn ends in, as recorded and as acted on: the state it declared, but a wait only when the turn completed. One
/// that failed or was stopped after it said it would wait is asked again by nothing (what it went on doing after saying
/// so is cut off, its process may be gone): recorded waiting, its chat would show it waiting on, unseen, instead of how
/// it ended.
const endedIn = (declared: DeclaredState | null, outcome: TurnOutcome["kind"]): DeclaredState | null =>
  declared?.kind === "waiting" && outcome !== "completed" ? null : declared;

/// A turn the provider had no room for (its model at capacity), recorded waiting to be tried again: the one wait a turn
/// that did not complete ends in.
const retrying = (turn: { outcome: string | null; declared: string | null; detail: string | null }) =>
  turn.outcome === "failed" && turn.declared === "waiting" && (turn.detail ?? "").startsWith("overloaded");

/// The reasons a failed turn can be taken up again by a press of its notice's 重试 (`retryFailed`), as a person's reply
/// would: what failed was the provider's or the connection's, or not said (`other`), and nothing of the person's (an
/// account's sign-in, its allowance, a refusal) has to change first.
const AGAIN = ["network", "model", "other", "exited"];

/// A turn that failed for one of `AGAIN`'s reasons and waits on nothing: its notice offers 重试.
export const retryable = (turn: { outcome: string | null; declared: string | null; detail: string | null }) =>
  turn.outcome === "failed" && turn.declared === null && AGAIN.some((reason) => (turn.detail ?? "").startsWith(`${reason}:`));

/// How long it waits before trying again a turn the provider had no room for, the `n`th in a row (from 0): twice as long
/// each time, ten minutes at most.
export const retryAfter = (n: number) => Math.min(30 * 2 ** n, 600);

export type TurnFor = { profile: string | null; person: string | null; thread: number | null };
const nobody: TurnFor = { profile: null, person: null, thread: null };

/// A chat thread the running turn works for, with the message that brought it in: it is told what the turn does.
type Working = { connect: string; channel: string; threadTs: string; ts: string | null; firstTs?: string | null; since?: number };

/// What the actor needs of the store: the Rust Store's methods, camelCase (src/store/store.ts).
export type SessionStore = {
  hasPending(key: string): boolean;
  markDelivered(key: string, handed: Handed[]): void;
  markUndelivered(key: string, handed: Handed[]): void;
  untoldWidgetModels(key: string): any[];
  markWidgetModelsTold(key: string, pairs: [string, string][]): void;
  untoldCardChoices(key: string): CardChoice[];
  markCardChoicesTold(key: string, told: readonly CardChoice[]): void;
  heardThreads(key: string, threads: number[]): Set<number> | number[];
  postsAfter(key: string, messages: readonly { thread: number; n: number }[]): (string | null)[];
  cardEndedByMessage(thread: number, n: number): [MessageRow, any] | null;
  pendingCard(thread: number): [MessageRow, any] | null;
  threadSessions(thread: number): { session: string; connect: string }[];
  /// Whether the session left this thread (chat_leave) and was not mentioned there since (optional: never without it).
  leftThread?(session: string, connect: string, channel: string, threadTs: string): boolean;
  getSession(key: string): any | null;
  hasTurns(key: string): boolean;
  toldNotes(key: string): number | null;
  setToldNotes(key: string, n: number): void;
  startTurnFor(id: string, key: string, kind: string, by: TurnFor): void;
  endTurn(id: string, outcome: string, detail: string | null, declared: string | null, wait: number | null): void;
  declareTurn(id: string, declared: string | null, wait: number | null): void;
  setRunning(key: string, running: boolean): void;
  setSessionContextBefore(key: string, before: number | null): void;
  setRuntimeSessionId(key: string, id: string | null): void;
  /// The runtime sessions it ran in, the first first (optional: none known without it).
  runtimeSessions?(key: string): string[];
  runtimeSessionSources?(key: string): { id: string; runtime: string; profile: string | null }[];
  runtimeSessionSource?(key: string, id: string): { id: string; runtime: string; profile: string | null } | null;
  setWaitFor(turn: string, what: string, watch: boolean): void;
  setNeed(turn: string, what: string): void;
  setAbout(turn: string, about: [number, number, string] | null): void;
  lastTurn(key: string): any | null;
  slackStop(session: string, connect: string, channel: string, threadTs: string): { ts: string; turn: string | null } | null;
  rememberSlackStop(session: string, connect: string, channel: string, threadTs: string, ts: string, turn: string | null): void;
  stopWait(key: string, refill?: boolean): void;
  forgetWait(key: string): void;
  hasSessionActiveWatch(session: string): boolean;
  latestThread(key: string): any | null;
  entriesBefore(thread: number, n: number | null, limit: number): any[];
  insertMessage(message: any): [number, boolean];
  notify(key: string): void;
};

/// A chat surface, as far as a session uses one (chat/mod.rs `ChatSurface`).
export type Surface = {
  post(thread: { channel: string; threadTs: string }, text: string, files: unknown[]): Promise<string>;
  userName?(user: string): Promise<string | null>;
  working?(thread: { channel: string; threadTs: string }, messageTs: string | null, status: string, page?: string | null): void;
  standsAt?(thread: { channel: string; threadTs: string }, stands: { kind: "done" | "need" | "left"; words: string | null } | null): void;
  mention?(user: string): string;
  botName?(): string;
  botUserId?(): string;
};

/// What a session needs of the station; the hub gives it.
export type SessionDeps = {
  store: SessionStore;
  /// What its process opening needs read first: its workspace's skills linked where it runs, its memory given back
  /// (`linkSkills`).
  linkSkills(row: any): Promise<string>;
  /// Pending messages and letters, merged as they are now, read off the station thread.
  pendingDeliveries(key: string, signal?: AbortSignal): Promise<PendingMessage[]>;
  /// Card state for a person's delivery, read off the station thread.
  deliveryCardState(thread: number, n: number, signal?: AbortSignal): Promise<DeliveryCardState | null>;
  /// An older store brings forward only the message ranges this delivery needs.
  preparePostsAfter?(messages: readonly { thread: number; n: number }[], signal?: AbortSignal): Promise<void>;
  prepareWidgetSources?(threads: readonly number[], signal?: AbortSignal): Promise<void>;
  chat(connect: string): Surface | undefined;
  driver(runtime: RuntimeKind): AgentDriver;
  /// The profile a session's runtime starts on now: its own while usable, else another that can take it on (`holding`:
  /// its process has work going in the background, kept on an account nearly full).
  runOn(key: string, holding?: boolean): Profile & { spelling?(model: string): string | null };
  /// A turn ran into the allowance of `ranOn`, the profile its process was started on (null: the session's own), or
  /// `model`'s own limit there (that model alone passed over on it): the profile left and the one moved to, when it moved.
  spend(key: string, ranOn: string | null, model?: string | null): [string, string] | null;
  /// When session `key`'s profile, its allowance run out, is expected to run again (absent: in an hour).
  refillsAt?(key: string): number;
  /// A runtime failed to sign in on `profile`: it is checked again (the pool passes over one whose login is over).
  recheck?(profile: string): Promise<void>;
  mcpUrl(): string;
  reposDir(): string;
  /// Session `key`'s MEMORY.md: its workspace's (agent-home.ts `workspaceAgentHome`).
  memoryPath(key: string): string;
  maxNudges(): number;
  /// The chat session `key` last heard from (its address), when it has no title and nobody is at work in it.
  untitled?(key: string): string | null;
  backgroundOnMessage(key: string): boolean;
  /// Where the runtime's live steps go, for whoever watches the session (and that it went on in a new runtime session).
  live?: { event(key: string, event: LiveEvent): void; turnEnded(key: string): Promise<void> | void; moved?(key: string): void };
  /// What it is told when it goes on on `to` in a new runtime session rather than take up `id` (last run on `was`, when
  /// the store does not know); null: it takes it up (sessions/afresh.ts).
  startsAfresh?(key: string, id: string, to: Profile, was: string | null): string | null;
  /// What a session whose context was cleared is told with its next prompt (sessions/afresh.ts `toldCleared`): to read
  /// back what it needs of its work too when `readBack` (cleared to go on afresh, as on another account).
  cleared?(key: string, readBack: boolean): string;
  /// Whether its next message or notice is to start it afresh, at `now` (sessions/afresh.ts `goesAfresh`): its chat or
  /// station set to, and its large context's prompt cache over.
  coldAfresh?(key: string, now: number): boolean;
  /// What a session whose runtime session could not be resumed is told with its next prompt (sessions/afresh.ts
  /// `toldResumeLost`).
  resumeLost?(key: string): string;
  /// What a session compacted or gone on in a new conversation is told when its chats are long (sessions/afresh.ts
  /// `toldLongChat`): to read back what people said in them. Null when they are not.
  longChat?(key: string): string | null;
  /// Its subagents `ids` of runtime session `from`, stopped with its process, taken to runtime session `to` begun on
  /// `on`, so that they are taken up there (sessions/afresh.ts): the ids taken.
  carrySubagents?(from: string, to: string, on: Profile, ids: string[]): string[];
  /// The runtime session it runs in, on `profile` (null: not known).
  ranIn?(key: string, id: string, profile: string | null): void;
  idle(key: string): void;
  archiveIsCold(key: string): Promise<boolean>;
  restoreArchive(key: string): void | Promise<void>;
  /// An archived session's process is gone: its files may go to cold storage now (session.rs `clean_archive`).
  cleanArchive?(key: string): void | Promise<void>;
  /// A turn ended as its opener (an agent that opened its chat) is told: all_done or need_human with its words, or
  /// failed or stopped.
  settled?(key: string, state: "all_done" | "need_human" | "failed" | "stopped", words: string | null): void;
  /// Turns are held (the station is about to stop or hand over, or is out of the session's workspace): none starts,
  /// messages stay pending.
  held(key: string): boolean;
  /// Stopped while it waits: ends the session's jobs that would bring it back.
  stopJobs(key: string): Promise<void>;
  /// Archived: ends every job and service of the session.
  endJobs(key: string): Promise<void>;
  toolStatus(tool: string): string;
  /// A session's page in still.fail, when the station is in a workspace: what a platform's status line points to.
  pageOf?(key: string): string | undefined;
  /// How a directory it is to run in is looked at (ops/places.ts); default: without still.fail Helper.
  places?: Places;
  /// Its runtime was not found on PATH as it started.
  runtimeMissing?(runtime: RuntimeKind): void;
  /// Updates the local Codex installation and waits until it can serve new turns.
  updateOldCodex?(runningVersion: string | null): Promise<void>;
  nextTs(): string;
  /// Its time (the hub's).
  clock: Clock.Clock;
};

type Turn = { id: string; declared: DeclaredState | null; authRetried: boolean; codexRetried?: boolean; by: TurnFor };

/// Where a session stands: no runtime session; one starting up; a turn running; the agent waiting on work it started;
/// or the actor closed (its station stopping or handing over).
type Phase = "idle" | "running" | "waiting" | "closed";

/// What a next station takes up from this one (session.rs `HandedSession`, without the process: the runner keeps it).
export type Snapshot = {
  key: string;
  runtime: RuntimeKind;
  agent: unknown | null;
  turn: { id: string; authRetried: boolean; codexRetried?: boolean; by: TurnFor; declared: string | null; wait: number | null } | null;
  workingFor: Working[];
  notices: string[];
  waitingMs: number | null;
  waitingSeconds: number;
  nudges: number;
  stopRequested: boolean;
  /// Its allowance ran out with no account to move to: how long until it goes on (optional: a station from before
  /// it does not say).
  refillMs?: number | null;
  /// How long its process had been idle (optional: a station from before it does not say): taken up, it has been idle
  /// that long already, so a station updated often still ends idle processes (hub.ts `evictIdle`).
  idleMs?: number;
  /// Changed while busy (optional: a station from before it does not say).
  stale?: boolean;
  /// What it was changed in needs a new process, not one retuned (optional: a station from before it does not say).
  restart?: boolean;
  /// Its context was being compacted by hand (optional: a station from before it does not say).
  compacting?: boolean;
  identity?: { model: string | null; effort: string | null; runtime: RuntimeKind } | null;
};

const t = (key: string, args?: Record<string, unknown>) => tr(stationLang(), key, args);

let places: Places | null = null;
const defaultPlaces = () => (places ??= new Places());

/// Times a process that lost the station's tools is started again before the turn is given up on.
const MAX_TOOLS_RESTARTS = 1;
/// The most of the agent's last words shown in its place.
const FALLBACK_MOST = 4000;

export class SessionActor {
  readonly key: string;
  runtime: RuntimeKind;
  private deps: SessionDeps;
  private lock = Semaphore.makeUnsafe(1);
  /// Runs an effect as a fiber of this actor's (its tasks, its wait's timer): they end when it closes.
  private run: (effect: Effect.Effect<void>) => Promise<void>;
  private scope: Scope.Closeable;

  private current: { generation: number; session: AgentSession } | null = null;
  /// Its runtime session now. What it has going in the background is told as it is taken up (one handed over still
  /// has its own), and as none once it is let go of (it ends with its process).
  private get agent() {
    return this.current;
  }
  private set agent(agent: { generation: number; session: AgentSession } | null) {
    const was = this.current;
    this.current = agent;
    if (agent?.session !== was?.session) this.deps.live?.event(this.key, { kind: "tasks", tasks: agent?.session.background?.() ?? [] });
  }
  /// How it runs was changed and its process has not caught up: before the next turn it takes the new model and effort
  /// in place, or ends so the next one starts as changed.
  private stale = false;
  /// What changed is not a model or an effort (the station's variables for its agents): no taking it in place.
  private restart = false;
  private profile: string | null = null;
  private runningIdentity: { model: string | null; effort: string | null; runtime: RuntimeKind } | null = null;

  /// What the process writing a message actually runs, even while its next settings have already been saved.
  messageIdentity() {
    return this.agent ? this.runningIdentity : null;
  }
  /// Its context cleared to go on afresh (`clear`'s `readBack`): its next runtime session told to read back its work.
  private readBack = false;
  private generation = 0;
  private phase: Phase = "idle";
  private turn: Turn | null = null;
  /// A failed turn waiting for the machine's shared Codex update; messages wait without blocking the actor's queue.
  private codexUpdate: { by: TurnFor; finished: boolean } | null = null;
  private nudges = 0;
  /// The chats it was asked to name as a turn ended with them untitled: asked once each.
  private askedToName = new Set<string>();
  /// Its turns the provider had no room for, in a row: each is tried again after longer (`retryAfter`).
  private overloads = 0;
  /// Its process lost the station's tools during the running turn (why): at the turn's end it starts again.
  private toolsLost: string | null = null;
  /// Times it was started again for that since it last ended a turn in a state (or was given something new).
  private toolsRestarts = 0;
  /// The agent's last words (a text step of its own) since it was last given something, and whether it posted since:
  /// what is shown, marked as the station's, when it is given up on without having posted.
  private saying: { id: string; text: string } | null = null;
  private lastSaid = "";
  private posted = false;
  private stopRequested = false;
  private resumeLost = false;
  /// Started afresh: what it is told of it with its next prompt.
  private afresh: string | null = null;
  /// Its context compacted with no turn to tell it in: its next prompt tells it, the chat long (`onCompacted`).
  private compactedUntold = false;
  /// Its context is being compacted by hand (compact): what it is told meanwhile waits for the end, as does a wait over
  /// meanwhile (`overWhileCompacting`).
  private compacting = false;
  private overWhileCompacting = false;
  /// What its processes ended by the station had going in the background (ended with them), until the next starts;
  /// then what it is told of it with its next prompt.
  private stopped: BackgroundTask[] = [];
  private stoppedNote: string | null = null;
  private idleSince: number;
  private workingFor: Working[] = [];
  /// The threads its last turn worked for (those it says where it stands in as a turn ends: one woken by a notice
  /// works for none, and says it in its last ones).
  private endedFor: Working[] = [];
  private tools: [string, string][] = [];
  private notices: string[] = [];
  /// The wait: its number (a newer wait voids an older one's timer), when it is over, and how long it was said to be.
  private waiting: number | null = null;
  private waits = 0;
  private waitingUntil = 0;
  private waitingSeconds = 0;
  /// Its last turn ran into its account's allowance and no other could take it on: when it goes on by itself, and its
  /// number (a newer one voids an older one's timer). Till then a job's notice waits with it; a person's message is
  /// tried at once.
  private refill: number | null = null;
  private refills = 0;
  private refillAt = 0;
  /// Messages given to the running turn while it ran: the runtime may not have read them yet (suspend).
  private steered: Handed[] = [];
  /// The threads of those messages: a runtime that had not read them when its turn ended takes them as a turn of its
  /// own, which works for them again.
  private steeredFor: Working[] = [];
  /// Messages given to the running turn since its model was last asked: what it writes now was written without them.
  private unread: PendingMessage[] = [];
  private queued = 0;
  private formatAbort: AbortController | null = null;
  /// A stop or suspension also prevents earlier queued deliveries from starting another read before it takes effect.
  private deliveryInterruptions = 0;
  /// Recoveries queued or reading: a stop cancels them; suspension keeps the cut-off turn marked running.
  private recoveries = 0;
  /// A recovery that reached a hold must resume the cut-off turn when the hold is released.
  private recoveryDeferred = false;
  /// File work cannot be interrupted by closing the effect that awaits it; disposal waits for it to stop.
  private archiving: Promise<void> | null = null;

  constructor(key: string, runtime: RuntimeKind, deps: SessionDeps) {
    this.key = key;
    this.runtime = runtime;
    this.deps = deps;
    this.idleSince = deps.clock.currentTimeMillisUnsafe();
    this.scope = Effect.runSync(Scope.make());
    const run = Effect.runSync(Scope.provide(FiberSet.makeRuntimePromise<never, void, never>(), this.scope));
    this.run = (effect) => run(effect.pipe(Effect.provideService(Clock.Clock, deps.clock)));
  }

  private now(): number {
    return this.deps.clock.currentTimeMillisUnsafe();
  }

  private closed(): boolean {
    return this.phase === "closed";
  }

  // ── the queue ─────────────────────────────────────────────────────────────────────────────────────────────────

  /// Queues a task; the promise resolves once it has run (or was skipped: the actor closed). A task's failure is
  /// logged, never thrown into the queue.
  private enqueue(task: () => Promise<void>): Promise<void> {
    this.queued++;
    const run = this.lock.withPermits(1)(
      Effect.promise(async () => {
        if (this.phase === "closed") return;
        try {
          await task();
        } catch (error) {
          log.error("session", "session task failed", { session: this.key, error: (error as Error).message });
        }
      }),
    ).pipe(Effect.ensuring(Effect.sync(() => this.queued--)));
    // Skipped (interrupted) once the actor closes: its caller is answered all the same.
    return this.run(run).catch(() => undefined);
  }

  /// No task queued or running.
  settled(): boolean {
    return this.queued === 0;
  }

  /// Resolves once every task queued before it has run (a handover waits on it, then looks at `settled`).
  flushed(): Promise<void> {
    return this.enqueue(async () => {});
  }

  /// Archived and idle: its files go to cold storage, in turn with the rest (session.rs `clean_archive`).
  cleanArchive(): Promise<void> {
    return this.enqueue(async () => {
      if (this.agent || this.turn || this.waiting !== null || this.notices.length > 0) return;
      const work = this.deps.cleanArchive?.(this.key);
      if (work === undefined) return;
      const archiving = Promise.resolve(work);
      this.archiving = archiving;
      try { await archiving; } finally { if (this.archiving === archiving) this.archiving = null; }
    });
  }

  // ── what the hub asks ────────────────────────────────────────────────────────────────────────────────────────

  /// running: a turn is in progress; warm: a runtime process waits for input; cold: none.
  processState(): "running" | "warm" | "cold" {
    if (this.turn || this.codexUpdate || this.agent?.session.busy()) return "running";
    return this.agent ? "warm" : "cold";
  }

  /// How long its process has had nothing to do (null: none, or it does). One waiting is idle all the same: what it waits
  /// for is the station's (its timer is this actor's, its jobs and tasks the station's); what it has going in its own
  /// process (`holding`) keeps that from being ended.
  idleMs(now: number): number | null {
    return this.agent && !this.agent.session.busy() && !this.turn ? now - this.idleSince : null;
  }

  holdsState(): boolean {
    return this.codexUpdate !== null || this.notices.length > 0 || this.waiting !== null || this.refill !== null;
  }

  /// Delivers any pending messages.
  kick(): Promise<void> {
    return this.enqueue(() => this.pump());
  }

  /// A word from the station for the agent outside any conversation (a job's notice): it joins the running turn, or
  /// runs as a turn of its own; one the running turn cannot take waits for its end. An archived session is not told.
  notify(text: string): Promise<void> {
    if (this.archived()) return Promise.resolve();
    this.notices.push(text);
    return this.enqueue(() => this.giveNotices());
  }

  /// Archived (by hand or by the station): its wait ends and so does every job and service of its own; a running turn
  /// goes on to its end and waits on nothing after. Only a new message brings it back (one archived by hand takes none).
  putAway(): Promise<void> {
    return this.enqueue(async () => {
      this.notices = [];
      if (this.codexUpdate) {
        this.codexUpdate = null;
        this.deps.store.setRunning(this.key, false);
      }
      if (!this.turn && !this.agent?.session.busy()) await this.letGo();
    });
  }

  /// The messages of `thread` given to the running turn that its model has not read yet (before entry `before`).
  unreadIn(thread: number, before: number): PendingMessage[] {
    return this.unread.filter((m) => m.message.thread === thread && m.message.n < before);
  }

  /// It posted in a chat (chat_post), in turn order.
  postedNow(): Promise<void> {
    return this.enqueue(async () => {
      this.posted = true;
    });
  }

  /// Bind an asynchronous tool read to the turn that asked for it.
  currentTurnId(): string | null { return this.turn?.id ?? null; }

  postedForTurn(id: string): Promise<void> {
    return this.enqueue(async () => { if (this.turn?.id === id) this.posted = true; });
  }

  /// The question may have taken long enough for its turn to end. Record its state as one queue action only if that
  /// same turn still runs, so its result cannot be applied to a later one.
  async stateForTurn(id: string, state: DeclaredState, words: string | null, about: [number, number, string] | null,
    watch = false, record?: (write: (about: [number, number, string] | null) => void) => void): Promise<boolean> {
    let recorded = false;
    let failed = false;
    let failure: unknown;
    await this.enqueue(async () => {
      const turn = this.turn;
      if (!turn || turn.id !== id) return;
      try {
        const write = (current: [number, number, string] | null) => {
          if (words !== null) {
            if (state.kind === "waiting") this.deps.store.setWaitFor(id, words, watch);
            else this.deps.store.setNeed(id, words);
          }
          this.deps.store.setAbout(id, current);
          this.deps.store.declareTurn(id, state.kind, state.kind === "waiting" ? state.seconds : null);
        };
        if (record) record(write);
        else write(about);
        turn.declared = state;
        recorded = true;
      } catch (error) {
        failed = true;
        failure = error;
      }
    });
    if (failed) throw failure;
    return recorded;
  }

  /// The station's tools are at `url` now. A process told another address (taken up from a station that had its tools
  /// elsewhere) cannot reach them: idle, it ends (the next turn starts one, resuming); running, it starts again once
  /// its turn ends.
  toolsAt(url: string): Promise<void> {
    return this.enqueue(async () => {
      const agent = this.agent;
      const was = agent?.session.mcpUrl?.() ?? null;
      if (!agent || was === null || was === url) return;
      if (this.turn || agent.session.busy()) {
        this.toolsLost ??= `its process was told the station's tools are at ${was}, not ${url}`;
        log.warn("session", "the process taken up was told another address of the station's tools; it starts again once its turn ends", { session: this.key, was, now: url });
        return;
      }
      this.agent = null;
      log.warn("session", "the process taken up was told another address of the station's tools; ending it, its next turn resumes in a new one", { session: this.key, was, now: url });
      await this.endProcess(agent);
      this.deps.store.notify(this.key);
    });
  }

  /// What a tool says of the running turn, recorded in turn order (the tool answers once this resolves), and on record at
  /// once: a station that dies before the turn ends would take it along.
  declare(state: DeclaredState): Promise<void> {
    return this.enqueue(async () => {
      if (!this.turn) return;
      this.turn.declared = state;
      this.deps.store.declareTurn(this.turn.id, state.kind, state.kind === "waiting" ? state.seconds : null);
    });
  }

  private undeclare() {
    if (!this.turn?.declared) return;
    log.info("session", "a message read after the turn said its state: the state no longer stands", { session: this.key, was: this.turn.declared.kind });
    this.turn.declared = null;
    this.deps.store.declareTurn(this.turn.id, null, null);
  }

  /// What its wait is for, and whether that is its watch keeping on (`watch`).
  waitFor(what: string, watch: boolean): Promise<void> {
    return this.enqueue(async () => {
      if (this.turn) this.deps.store.setWaitFor(this.turn.id, what, watch);
    });
  }

  need(what: string): Promise<void> {
    return this.enqueue(async () => {
      if (this.turn) this.deps.store.setNeed(this.turn.id, what);
    });
  }

  about(about: [number, number, string] | null): Promise<void> {
    return this.enqueue(async () => {
      if (this.turn) this.deps.store.setAbout(this.turn.id, about);
    });
  }

  /// Stops what it is doing: the running turn; or, while it waits on work it started, that work and the wait.
  stop(): Promise<void> {
    const stopRecovery = this.recoveries > 0 || this.recoveryDeferred;
    this.recoveryDeferred = false;
    this.deliveryInterruptions++;
    this.formatAbort?.abort();
    return this.enqueue(async () => {
      try {
        if (stopRecovery) this.deps.store.setRunning(this.key, false);
        if (this.codexUpdate) {
          this.codexUpdate = null;
          this.deps.store.setRunning(this.key, false);
          await this.notice(t("station.notice.stopped"));
          await this.deps.live?.turnEnded(this.key);
          return;
        }
        if (this.agent?.session.busy()) {
          this.stopRequested = true;
          try {
            await this.agent.session.abort();
          } catch (error) {
            this.stopRequested = false;
            throw error;
          }
          return;
        }
        if (this.turn) return;
        await this.stopWaiting();
        // Nothing runs: whatever is still said to be under way (a start that failed) is not.
        await this.deps.live?.turnEnded(this.key);
      } finally { this.deliveryInterruptions--; }
    });
  }

  /// Cancels only the overload retry identified by the notice the person pressed. A delayed press must never stop a
  /// different turn or a later wait, and the background jobs belonging to the session continue.
  cancelRetry(thread: number, seq: number): Promise<void> {
    return this.enqueue(async () => {
      const last = this.deps.store.lastTurn(this.key);
      if (this.turn || this.agent?.session.busy() || !last || !retrying(last) || last.about?.thread !== thread || last.about?.seq !== seq) return;
      await this.stopWaiting(false);
      await this.notice(t("station.notice.retryCanceled"));
      await this.deps.live?.turnEnded(this.key);
    });
  }

  /// Takes up again the failed turn the notice the person pressed (重试) was about, as a reply would, going on where
  /// it stopped. Only that notice's turn, while it is still the last and nothing runs or waits to be delivered: a
  /// delayed press after a reply, or on an older notice, does nothing.
  retryFailed(thread: number, seq: number): Promise<void> {
    return this.enqueue(async () => {
      if (this.deps.held(this.key) || this.archived() || this.turn || this.codexUpdate || this.agent?.session.busy() || this.deps.store.hasPending(this.key)) return;
      const last = this.deps.store.lastTurn(this.key);
      if (!last || !retryable(last) || last.about?.thread !== thread || last.about?.seq !== seq) return;
      log.info("session", "trying again a failed turn, as asked", { session: this.key });
      await this.startTurn("resume", GO_ON_AFTER_FAILED);
    });
  }

  /// Slack's stop button belongs to one bot in one thread. Bind the event to the turn it saw; a retry must not stop a
  /// later turn. Its timestamp also rules out an event known to predate newer work.
  async stopFromSlack(connect: string, channel: string, threadTs: string, ts: string, localAt?: number | null): Promise<void> {
    let failure: unknown;
    await this.enqueue(async () => {
      try {
        const previous = this.deps.store.slackStop(this.key, connect, channel, threadTs);
        const at = Number(ts);
        if (previous && Number(previous.ts) > at) return;
        let turn: string | null;
        if (previous && Number(previous.ts) === at) turn = previous.turn;
        else {
          const work = this.workingFor.find((w) => w.connect === connect && w.channel === channel && w.threadTs === threadTs);
          const since = work?.since ?? this.deps.store.lastTurn(this.key)?.startedAt ?? 0;
          // The first message and the stop share Slack's clock, which can order two turns even within the one-second
          // precision of an HTTP Date. Keep the first message rather than the latest steer into the same turn.
          const first = work?.firstTs ?? work?.ts;
          const timely = (!first || at >= Number(first)) && (localAt === null || (localAt ?? at * 1000) >= since);
          turn = work && this.turn && timely ? this.turn.id : null;
          this.deps.store.rememberSlackStop(this.key, connect, channel, threadTs, ts, turn);
        }
        if (!turn || this.turn?.id !== turn || !this.agent?.session.busy() || this.stopRequested) return;
        this.stopRequested = true;
        try {
          await this.agent.session.abort();
        } catch (error) {
          this.stopRequested = false;
          throw error;
        }
      } catch (error) {
        failure = error;
      }
    });
    if (failure !== undefined) throw failure;
  }

  /// Its last turn stopped at its account's allowance, or waits to be tried again after the provider had no room for it,
  /// and it was changed since: it goes on where it stopped.
  goOn(): Promise<void> {
    return this.enqueue(async () => {
      if (this.deps.held(this.key) || this.archived() || this.turn || this.codexUpdate || this.agent?.session.busy()) return;
      this.refill = null;
      if (this.deps.store.hasPending(this.key)) return this.pump();
      const last = this.deps.store.lastTurn(this.key);
      await this.startTurn("resume", last && retrying(last) ? GO_ON_AFTER_OVERLOADED : GO_ON_AFTER_SPENT);
    });
  }

  /// An allowance this session was waiting for was reset by hand.
  allowanceReset(): Promise<void> {
    return this.enqueue(async () => {
      if (this.refill === null || this.archived() || this.turn || this.agent?.session.busy()) return;
      if (this.deps.held(this.key)) {
        this.refillAt = this.now();
        return;
      }
      this.refill = null;
      if (this.deps.store.hasPending(this.key)) return this.pump();
      await this.startTurn("resume", GO_ON_AFTER_REFILL);
    });
  }

  /// After a station stopped with this session's turn running and no runner kept it: the turn was cut off; resume it.
  recover(): Promise<void> {
    this.recoveries++;
    return this.enqueue(async () => {
      let reading = true;
      try {
        if (this.deliveryInterruptions > 0) return;
        const store = this.deps.store;
        if (this.archived()) {
          this.recoveryDeferred = false;
          store.setRunning(this.key, false);
          return this.letGo();
        }
        if (this.deps.held(this.key)) {
          this.recoveryDeferred = true;
          return;
        }
        this.recoveryDeferred = false;
        const delivery = await this.pendingAndFormat(true);
        this.recoveries--;
        reading = false;
        if (delivery === null || this.deliveryInterruptions > 0 || this.closed()) return;
        if (this.archived()) {
          store.setRunning(this.key, false);
          return this.letGo();
        }
        if (this.deps.held(this.key)) {
          this.recoveryDeferred = true;
          return;
        }
        const { pending, text: said, widgets } = delivery;
        store.setRunning(this.key, false);
        await this.startTurn("resume", said === "" ? RESUME_AFTER_RESTART : `${RESUME_AFTER_RESTART}\n\n${said}`);
        this.delivered(pending, widgets);
      } finally { if (reading) this.recoveries--; }
    });
  }

  /// After a restart: the wait its last turn is recorded ending in, when this actor does not keep it (the station before
  /// stopped without handing it over), asks again when it would have, at once if that is past. One a station from
  /// before `endedIn` recorded for a turn that did not complete was never kept: recorded as the turn ended instead.
  takeWait(): Promise<void> {
    return this.enqueue(async () => {
      if (this.waiting !== null || this.turn || this.archived()) return;
      const store = this.deps.store;
      const last = store.lastTurn(this.key);
      if (!last || last.endedAt === null || last.declared !== "waiting") return;
      if (last.outcome !== "completed" && !retrying(last)) return store.forgetWait(this.key);
      const seconds = last.waitSeconds ?? 0;
      log.info("session", "taking up a wait on record", { session: this.key, seconds });
      this.waitMs(seconds, last.endedAt + seconds * 1000 - this.now());
    });
  }

  /// After an unclean restart, take up the allowance wait recorded by the failed turn.
  takeRefill(): Promise<void> {
    return this.enqueue(async () => {
      if (this.refill !== null || this.turn || this.agent?.session.busy() || this.archived()) return;
      const last = this.deps.store.lastTurn(this.key);
      if (last?.outcome !== "failed" || !last.detail?.startsWith("rate_limit:") || last.endedAt === null) return;
      this.awaitRefill(this.deps.refillsAt?.(this.key) ?? this.now() + REFILL_FALLBACK_MS);
    });
  }

  /// Turns were held and are no longer: what waited meanwhile goes on.
  release(): Promise<void> {
    if (this.recoveryDeferred) {
      this.recoveryDeferred = false;
      if (this.recoveries === 0) return this.recover();
    }
    return this.enqueue(async () => {
      if (this.waiting !== null && this.waitingUntil <= this.now()) this.waitMs(this.waitingSeconds, 0);
      if (this.refill !== null && this.refillAt <= this.now()) this.awaitRefill(this.now());
      await this.pump();
      if (this.notices.length > 0) await this.giveNotices();
    });
  }

  /// Starts the runtime process ahead of a message, so its start-up overlaps the typing.
  warm(): Promise<void> {
    return this.enqueue(async () => {
      if (this.agent || this.codexUpdate || this.deps.held(this.key)) return;
      log.info("session", "warming session process", { session: this.key });
      await this.ensureAgent();
      this.idleSince = this.now();
      this.deps.store.notify(this.key);
      this.deps.idle(this.key);
    });
  }

  /// How it runs (profile, model, effort) changed: its process takes it now if idle, else before its next turn. `restart`:
  /// what changed is what its process started with (its variables), which only a new one takes.
  changed(restart = false): Promise<void> {
    if (this.agent) {
      this.stale = true;
      if (restart) this.restart = true;
    }
    return this.enqueue(() => this.catchUp(!this.turn && this.waiting === null));
  }

  /// Ends the runtime process if it is idle.
  evict(): Promise<void> {
    return this.enqueue(async () => {
      const agent = this.agent;
      // Work it has going in the background would end with it. A wait goes on without it: the station asks again in a
      // new one, so waiting chats need not keep a process resident.
      if (!agent || agent.session.busy() || this.turn || this.holding()) return;
      this.agent = null;
      log.info("session", "evicting idle session process", { session: this.key });
      await agent.session.dispose();
      this.deps.store.notify(this.key);
    });
  }

  /// Compacts its context, by hand, between turns (a runtime that can: agents/runtime.ts `compact`); its end is told in
  /// its chat. What it is told meanwhile waits until then. Why not, when it cannot now (said in its chat too when
  /// `say`: asked there); null once begun.
  compact(say = false): Promise<string | null> {
    let refused: string | null = null;
    return this.enqueue(async () => {
      refused = await this.beginCompacting();
      if (refused !== null && say) await this.notice(`⚠️ ${refused}`);
    }).then(() => refused);
  }

  /// What it holds is over its lowered most (`contextBefore`): compacted now if nothing runs; else a turn's end or the
  /// next message comes back here.
  compactToCap(): Promise<void> {
    return this.enqueue(async () => {
      await this.compactingToCap();
    });
  }

  /// Whether a compaction down to its most has begun, for its end to go on from. Tried once: its runtime still compacts
  /// on its own a few calls on.
  private async compactingToCap(): Promise<boolean> {
    const store = this.deps.store;
    if (store.getSession(this.key)?.contextBefore == null) return false;
    if (this.turn || this.codexUpdate || this.compacting || this.waiting !== null || this.agent?.session.busy() || this.deps.held(this.key) || this.archived()) return false;
    const refused = await this.beginCompacting();
    if (refused === null) return true;
    log.info("session", "could not compact down to its most context", { session: this.key, why: refused });
    store.setSessionContextBefore(this.key, null);
    store.notify(this.key);
    return false;
  }

  private async beginCompacting(): Promise<string | null> {
    if (this.turn || this.codexUpdate || this.compacting || this.agent?.session.busy()) return t("station.context.busy");
    if (this.deps.held(this.key)) return t("station.context.held");
    const row = this.deps.store.getSession(this.key);
    if (!row?.runtimeSessionId) return t("station.context.empty");
    let agent: AgentSession;
    try {
      agent = await this.ensureAgent();
    } catch (error) {
      return compactFailed(error);
    }
    // Gone on in a new runtime session (another account's): nothing in it to compact yet.
    if (this.afresh !== null) return t("station.context.empty");
    if (!agent.compact) return t("station.context.cannotCompact", { name: runtimeLabel(this.runtime) });
    log.info("session", "compacting its context", { session: this.key });
    this.compacting = true;
    this.deps.store.setRunning(this.key, true);
    this.deps.store.notify(this.key);
    try {
      await agent.compact();
    } catch (error) {
      this.compacting = false;
      this.deps.store.setRunning(this.key, false);
      this.deps.store.notify(this.key);
      return compactFailed(error);
    }
    return null;
  }

  /// Its compaction ended (`outcome`): said in its chat; then what waited meanwhile goes on.
  private async compacted(outcome: TurnOutcome) {
    const store = this.deps.store;
    this.compacting = false;
    this.idleSince = this.now();
    const stopRequested = this.stopRequested;
    this.stopRequested = false;
    store.setRunning(this.key, false);
    store.setSessionContextBefore(this.key, null);
    store.notify(this.key);
    log.info("session", "compaction ended", { session: this.key, outcome: outcome.kind });
    if (outcome.kind === "completed") await this.notice(t("station.notice.compacted"));
    else if (outcome.kind === "failed") {
      log.warn("session", "compaction failed", { session: this.key, reason: outcome.reason, error: outcome.message });
      // Claude Code's own reason for compacting nothing is one people can act on.
      const why = /not enough messages/i.test(outcome.message) ? t("station.context.tooShort") : failureWords(outcome.reason);
      await this.notice(`⚠️ ${withSaid(t("station.notice.compactFailed", { why }), outcome.message)}`, outcome.reason === "auth" || outcome.reason === "refused" ? this.profile : null);
    }
    else if (stopRequested) await this.notice(t("station.notice.stopped"));
    if (this.archived()) {
      await this.letGo();
      this.deps.idle(this.key);
      return;
    }
    if (this.overWhileCompacting) {
      this.overWhileCompacting = false;
      if (this.waiting !== null) this.waitMs(this.waitingSeconds, 0);
    }
    if (store.hasPending(this.key)) return this.pump();
    if (this.notices.length > 0) return this.giveNotices();
    this.deps.idle(this.key);
  }

  /// Clears its context, by hand, between turns: its process ends (with what it had going in the background, and the
  /// wait for it), and its next turn starts a new runtime session, told so (`cleared`); the one before stays in its
  /// history. Said in its chat. `readBack`: to go on afresh, as it would on another account (its cache over, its
  /// conversation would be read again at full price): told to read back what it needs of what it did, not only its
  /// chats. Why not, when it cannot now (said in its chat too when `say`); null once done.
  clear(say = false, readBack = false): Promise<string | null> {
    let refused: string | null = null;
    return this.enqueue(async () => {
      refused = await this.clearNow(readBack);
      if (refused !== null && say) await this.notice(`⚠️ ${refused}`);
    }).then(() => refused);
  }

  /// Clears it (`clear`), saying `said` in its chat; `by`: who asked, for the log. `keepJobs`: its jobs go on, as when
  /// a message or notice starts it afresh by itself: the turn that comes is what its wait was for, and its watches keep
  /// watching (stopped with it, a watch would end without a word, the fresh agent not knowing it had one).
  private async clearNow(readBack: boolean, said = readBack ? "station.notice.afresh" : "station.notice.cleared", by = "by hand", keepJobs = false): Promise<string | null> {
    if (this.turn || this.codexUpdate || this.compacting || this.agent?.session.busy()) return t("station.context.busy");
    const store = this.deps.store;
    const row = store.getSession(this.key);
    if (!row?.runtimeSessionId) return t("station.context.empty");
    await this.stopWaiting(false, keepJobs);
    const agent = this.agent;
    this.agent = null;
    log.info("session", `clearing its context, asked ${by}`, { session: this.key, left: row.runtimeSessionId, readBack, background: agent?.session.background?.().length ?? 0 });
    await agent?.session.dispose();
    // Nothing of the conversation left is carried to the next.
    this.stopped = [];
    this.stoppedNote = null;
    this.resumeLost = false;
    this.afresh = null;
    this.compactedUntold = false;
    this.nudges = 0;
    this.toolsRestarts = 0;
    this.deps.ranIn?.(this.key, row.runtimeSessionId, null);
    store.setRuntimeSessionId(this.key, null);
    this.readBack = readBack;
    store.notify(this.key);
    await this.notice(t(said));
    return null;
  }

  /// The station left its workspace: the runtime process ends, and with it whatever the agent was doing or had been
  /// given (session.rs `suspend`): a turn under way stays marked running (to resume once back), unless it had already
  /// said a settled state; messages given to it while it ran are pending again.
  suspend(): Promise<void> {
    this.deliveryInterruptions++;
    this.formatAbort?.abort();
    return this.enqueue(async () => {
      try {
        const agent = this.agent;
        this.agent = null;
        const busy = agent?.session.busy() ?? false;
        const turn = this.turn;
        this.turn = null;
        this.tools = [];
        this.workingFor = [];
        this.stopRequested = false;
        const steered = this.steered;
        this.steered = [];
        this.steeredFor = [];
        this.unread = [];
        if (!agent && !turn) return;
        const store = this.deps.store;
        const resume = (turn !== null || busy) && !(turn?.declared && settled(turn.declared));
        log.info("session", "ending the runtime process: the station is in no workspace", { session: this.key, resume });
        await agent?.session.dispose();
        if (turn) store.endTurn(turn.id, "aborted", "other: the station left its workspace", endedIn(turn.declared, "aborted")?.kind ?? null, null);
        store.setRunning(this.key, resume);
        if (turn || busy) store.markUndelivered(this.key, steered);
        await this.deps.live?.turnEnded(this.key);
        store.notify(this.key);
        this.phase = "idle";
      } finally { this.deliveryInterruptions--; }
    });
  }

  /// Where the session stands, for the next station; from here on this actor does nothing more. Its runtime session is
  /// let go of (the runner keeps the process), not ended.
  snapshot(): Snapshot {
    const agent = this.agent?.session ?? null;
    const snap: Snapshot = {
      key: this.key,
      runtime: this.runtime,
      identity: this.runningIdentity,
      agent: agent?.snapshot() ?? null,
      turn: this.turn && {
        id: this.turn.id,
        authRetried: this.turn.authRetried,
        codexRetried: this.turn.codexRetried === true,
        by: this.turn.by,
        declared: this.turn.declared?.kind ?? null,
        wait: this.turn.declared?.kind === "waiting" ? this.turn.declared.seconds : null,
      },
      workingFor: this.workingFor,
      notices: this.notices,
      waitingMs: this.waiting !== null ? Math.max(0, this.waitingUntil - this.now()) : null,
      waitingSeconds: this.waitingSeconds,
      nudges: this.nudges,
      stopRequested: this.stopRequested,
      refillMs: this.refill !== null ? Math.max(0, this.refillAt - this.now()) : null,
      idleMs: Math.max(0, this.now() - this.idleSince),
      stale: this.stale,
      restart: this.restart,
      compacting: this.compacting,
    };
    agent?.detach();
    this.close();
    return snap;
  }

  /// Takes up a session the previous station left (its snapshot), on its runtime session when the driver took that up:
  /// as the generation the caller opened it as (`nextGeneration`, whose `listener` the driver was given), running on
  /// `profile`, the one its process was started on.
  adopt(snap: Snapshot, agent: AgentSession | null, profile: string) {
    if (agent) this.runtime = snap.runtime;
    const row = this.deps.store.getSession(this.key);
    this.runningIdentity = agent ? (snap.identity ?? { runtime: snap.runtime, model: row?.model ?? null, effort: row?.effort ?? null }) : null;
    this.agent = agent ? { generation: this.generation, session: agent } : null;
    this.profile = agent ? profile : null;
    this.turn = snap.turn && {
      id: snap.turn.id,
      authRetried: snap.turn.authRetried,
      codexRetried: snap.turn.codexRetried === true,
      by: snap.turn.by,
      declared: snap.turn.declared ? parseDeclared(snap.turn.declared, snap.turn.wait ?? 0) : null,
    };
    this.phase = this.turn ? "running" : "idle";
    this.workingFor = snap.workingFor;
    // Those given here before it was taken up (a task followed from here told ended while this station started) after
    // those the previous one had not given.
    this.notices = [...snap.notices, ...this.notices];
    this.nudges = snap.nudges;
    this.stopRequested = snap.stopRequested;
    const runtimeChanged = agent !== null && this.deps.store.getSession(this.key)?.runtime !== snap.runtime;
    this.stale = runtimeChanged || (snap.stale ?? false);
    this.restart = runtimeChanged || (snap.restart ?? false);
    this.compacting = snap.compacting === true;
    this.idleSince = this.now() - (typeof snap.idleMs === "number" ? snap.idleMs : 0);
    if (snap.waitingMs !== null) this.waitMs(snap.waitingSeconds, snap.waitingMs);
    if (typeof snap.refillMs === "number") this.awaitRefill(this.now() + snap.refillMs);
  }

  /// The events of the runtime session opened (or adopted) as `generation`, as a driver gives them.
  listener(generation: number): (event: RuntimeEvent) => void {
    return (event) => this.onEvent(generation, event);
  }

  nextGeneration(): number {
    return ++this.generation;
  }

  /// For shutdown or handover: queued and later tasks are skipped, timers end. A running turn stays marked running.
  close() {
    this.phase = "closed";
    this.formatAbort?.abort();
    Effect.runFork(Scope.close(this.scope, Exit.void));
  }

  /// Ends the runtime process too (the session is deleted, or the station stops for good).
  async dispose() {
    const agent = this.agent;
    this.agent = null;
    this.close();
    try { await agent?.session.dispose(); }
    finally { await this.archiving?.catch(() => {}); }
  }

  // ── inside the queue ─────────────────────────────────────────────────────────────────────────────────────────

  /// The notices waiting, as the agent reads them: each a message from the station (via="station").
  private takeNotices(): string | null {
    const notices = this.notices;
    this.notices = [];
    if (notices.length === 0) return null;
    const at = this.deps.nextTs();
    return notices.map((n) => `<message via="station" from="station" ts="${at}">\n${n}\n</message>`).join("\n");
  }

  private async giveNotices() {
    if (this.deps.held(this.key) || this.compacting || this.codexUpdate) return;
    if (this.archived()) {
      this.notices = [];
      return;
    }
    // Its account spent: a turn for them would run into it again; they wait for the refill.
    if (this.refill !== null && !this.agent?.session.busy()) return;
    if (this.agent?.session.busy()) {
      const text = this.takeNotices();
      if (text === null) return;
      const [handed, told] = await this.withChoices(text);
      // Not now: after the running turn.
      if (await this.agent.session.steer(handed)) told();
      else this.notices.unshift(text);
      return;
    }
    const text = this.takeNotices();
    if (text !== null) await this.startTurn("job", text);
  }

  private async pump() {
    if (this.deliveryInterruptions > 0 || this.recoveries > 0 || this.recoveryDeferred || this.deps.held(this.key) || this.archived() || this.compacting) return; // they stay pending
    if (this.codexUpdate) {
      if (this.codexUpdate.finished) await this.continueAfterCodexUpdate(this.codexUpdate);
      return;
    }
    const store = this.deps.store;
    if (!store.hasPending(this.key) || (await this.compactingToCap())) return;
    if (this.deliveryInterruptions > 0 || this.recoveries > 0 || this.recoveryDeferred || this.closed() || this.deps.held(this.key) || this.archived() || this.compacting) return;
    const delivery = await this.pendingAndFormat(false);
    if (delivery === null || this.deliveryInterruptions > 0 || this.recoveries > 0 || this.recoveryDeferred || this.closed() || this.deps.held(this.key) || this.archived() || this.compacting) return;
    const { pending, text, widgets } = delivery;
    const agent = this.agent?.session;
    if (agent?.busy()) {
      // So it is read now, not when a long command ends; what it waited on goes on.
      if (this.deps.backgroundOnMessage(this.key)) await agent.backgroundTools();
      const [handed, told] = await this.withChoices(text);
      if (await agent.steer(handed)) {
        told();
        this.workFor(pending);
        this.delivered(pending, widgets);
        this.steered.push(...pending.map(handedOf));
        this.unread.push(...pending.filter((m: PendingMessage) => m.message.apart !== true));
        const from = (w: Working) => pending.some((m: any) => m.connect === w.connect && m.channel === w.channel && m.threadTs === w.threadTs);
        this.steeredFor = [...this.steeredFor.filter((w) => !from(w)), ...this.workingFor.filter(from)];
      }
      return; // otherwise delivered when the turn ends
    }
    this.nudges = 0;
    this.toolsRestarts = 0;
    this.workFor(pending);
    // The turn is for the first person whose message it takes.
    const first = pending.find((m: any) => m.message.authorKind === "person");
    const by: TurnFor = first ? { person: personRef(first), thread: first.message.thread, profile: null } : nobody;
    await this.startTurn("input", text, by);
    this.delivered(pending, widgets);
  }

  private workFor(messages: any[]) {
    for (const m of messages.filter((m) => m.surface !== STILLFAIL_SURFACE)) {
      const at = this.workingFor.find((w) => w.connect === m.connect && w.channel === m.channel && w.threadTs === m.threadTs);
      if (at) at.ts = m.message.ts;
      else this.workingFor.push({ connect: m.connect, channel: m.channel, threadTs: m.threadTs, ts: m.message.ts, firstTs: m.message.ts, since: this.now() });
    }
    this.say(t("station.status.thinking"));
  }

  private say(status: string) {
    const page = this.deps.pageOf?.(this.key) ?? null;
    for (const w of this.workingFor) this.deps.chat(w.connect)?.working?.({ channel: w.channel, threadTs: w.threadTs }, w.ts, status, page);
  }

  /// A live step of the running turn, for its threads' status line.
  private onLive(event: LiveEvent) {
    if (this.workingFor.length === 0) return;
    if (event.kind === "start" && event.step === "tool" && event.tool) {
      if (!this.tools.some(([i]) => i === event.id)) this.tools.push([event.id, event.tool]);
    } else if (event.kind === "end") this.tools = this.tools.filter(([i]) => i !== event.id);
    else if (event.kind !== "phase") return;
    const last = this.tools.at(-1);
    this.say(last ? this.deps.toolStatus(last[1]) : t("station.status.thinking"));
  }

  /// The turn is over: its threads' status line goes.
  private doneWorking() {
    if (this.workingFor.length > 0) this.endedFor = this.workingFor;
    this.say("");
    this.workingFor = [];
    this.tools = [];
  }

  private delivered(messages: any[], widgets: [string, string][]) {
    this.deps.store.markDelivered(this.key, messages.map(handedOf));
    this.deps.store.markWidgetModelsTold(this.key, widgets);
  }

  /// Stop and handover can interrupt both the pending read and its formatting, including old-index preparation.
  private async pendingAndFormat(allowEmpty: boolean): Promise<{ pending: PendingMessage[]; text: string; widgets: [string, string][] } | null> {
    const abort = new AbortController();
    this.formatAbort = abort;
    try {
      const pending = await this.deps.pendingDeliveries(this.key, abort.signal);
      if (abort.signal.aborted) throw new Error("delivery cancelled");
      if (!allowEmpty && pending.length === 0) return null;
      const [text, widgets] = await this.format(pending, abort);
      if (abort.signal.aborted) throw new Error("delivery cancelled");
      return { pending, text, widgets };
    } finally { if (this.formatAbort === abort) this.formatAbort = null; }
  }

  /// The messages as the agent reads them, made now so edits count (session.rs `format`).
  private async format(said: any[], abort?: AbortController): Promise<[string, [string, string][]]> {
    const controller = abort ?? new AbortController();
    if (!abort) this.formatAbort = controller;
    try { return await this.formatWithSignal(said, controller.signal); }
    finally { if (!abort && this.formatAbort === controller) this.formatAbort = null; }
  }

  private async formatWithSignal(said: any[], signal: AbortSignal): Promise<[string, [string, string][]]> {
    const store = this.deps.store;
    const threads: number[] = said.map((m) => m.message.thread);
    const heard = new Set(store.heardThreads(this.key, threads));
    const newThreads = new Set<number>(threads.filter((t) => !heard.has(t)));
    const names = new Map<string, string>();
    for (const m of said) {
      if (names.has(m.message.author)) continue;
      if (m.message.authorKind === "agent") {
        names.set(m.message.author, this.agentName(m.message.author, m.message.thread));
        continue;
      }
      if (m.message.authorKind !== "person") continue;
      const name = await this.deps.chat(m.connect)?.userName?.(m.message.author);
      if (name) names.set(m.message.author, name);
    }
    // What the agent is called in each connect these came through: the bot's name there and its mention.
    const selves = new Map<string, string>();
    for (const m of said) {
      if (selves.has(m.connect)) continue;
      const chat = this.deps.chat(m.connect);
      const [name, user] = [chat?.botName?.() ?? "", chat?.botUserId?.() ?? ""];
      if (name !== "") selves.set(m.connect, user === "" ? name : `${name} (${chat?.mention?.(user) ?? `<@${user}>`})`);
    }
    // What it posted in a thread after a message there was said: the message was written without seeing that post.
    const posts = new Map<PendingMessage, string>();
    const fromChat = (said as PendingMessage[]).filter((m) => m.message.apart !== true);
    const positions = fromChat.map((m) => ({ thread: m.message.thread, n: m.message.n }));
    let laterPosts: (string | null)[];
    for (;;) {
      if (signal.aborted) throw new Error("delivery cancelled");
      try { laterPosts = store.postsAfter(this.key, positions); break; }
      catch (error) {
        if (!(error instanceof PostBlocksUnavailable) || !this.deps.preparePostsAfter) throw error;
        await this.deps.preparePostsAfter(error.positions, signal);
      }
    }
    fromChat.forEach((m, i) => { const ts = laterPosts[i]; if (ts !== undefined && ts !== null) posts.set(m, ts); });
    const cards = new Map<PendingMessage, { ended: DeliveryCardState["ended"]; current: DeliveryCardState["current"]; special: string | null }>();
    for (const m of said as PendingMessage[]) {
      if (m.message.apart === true || m.message.authorKind !== "person") continue;
      if (signal.aborted) throw new Error("delivery cancelled");
      const state = await this.deps.deliveryCardState(m.message.thread, m.message.n, signal);
      if (state === null) continue;
      const card = state.card;
      const special = typeof card?.vault?.request === "string" ? `Use secret_reask {request: ${JSON.stringify(card.vault.request)}} if the request is still needed.`
        : typeof card?.adb?.request === "string" ? `Use phone_use {reason: ${JSON.stringify(card.adb.reason ?? "")}, reask: true} if the request is still needed.`
        : typeof card?.signin?.site === "string" ? `Use sign_in {site: ${JSON.stringify(card.signin.site)}, reask: true} if the sign-in is still needed.`
        : card?.type === "login" ? "Check the login with its tool; if it still needs the person, post its login card again."
        : null;
      cards.set(m, { ended: state.ended, current: state.current, special });
    }
    const text = formatInbound(said, newThreads, names, selves, posts, cards, this.key);
    let models: any[];
    for (;;) {
      if (signal.aborted) throw new Error("delivery cancelled");
      try { models = store.untoldWidgetModels(this.key); break; }
      catch (error) {
        if (!(error instanceof WidgetSourcesUnavailable) || !this.deps.prepareWidgetSources) throw error;
        await this.deps.prepareWidgetSources(error.threads, signal);
      }
    }
    const widgets = models.map((w: any): [string, string] => [w.path, w.model]);
    const told = formatWidgetModels(models);
    return [told === "" ? text : text === "" ? told : `${text}\n\n${told}`, widgets];
  }

  /// `text` as the agent is handed it, after what people chose on its cards with an option that closes them (no message
  /// was sent then, so it has not heard: store.ts closeCard), and what marks those told once it has been handed.
  private async withChoices(text: string): Promise<[string, () => void]> {
    const store = this.deps.store;
    const chose = store.untoldCardChoices(this.key);
    if (chose.length === 0) return [text, () => {}];
    const names = new Map<string, string>();
    for (const c of chose) {
      if (names.has(c.by)) continue;
      const via = store.threadSessions(c.thread).find((m) => m.session === this.key)?.connect;
      const name = via === undefined ? undefined : await this.deps.chat(via)?.userName?.(c.by);
      if (name) names.set(c.by, name);
    }
    const said = formatCardChoices(chose, names, this.now());
    return [text === "" ? said : `${said}\n\n${text}`, () => store.markCardChoicesTold(this.key, chose)];
  }

  /// What another agent goes by in a thread: the bot of the connect it posts there through, with its mention; in the
  /// station's own chats, its runtime and model.
  private agentName(key: string, thread: number): string {
    const via = this.deps.store.threadSessions(thread).find((m) => m.session === key)?.connect;
    const chat = via && via !== INTERNAL_CONNECT ? this.deps.chat(via) : undefined;
    const name = chat?.botName?.() ?? "";
    if (name !== "") {
      const user = chat?.botUserId?.() ?? "";
      return user === "" ? name : `${name} (<@${user}>)`;
    }
    const row = this.deps.store.getSession(key);
    return row ? `${runtimeLabel(runtimeKind(row.runtime) ?? "claude")}${row.model ? ` ${row.model}` : ""}` : "another agent";
  }

  /// Starts a turn with `text` for someone. On failure the thread is told and the error thrown, so callers leave their
  /// messages pending for the next attempt.
  private async startTurn(kind: string, text: string, by: TurnFor = nobody): Promise<void> {
    const store = this.deps.store;
    // An automatic retry is still the one described by the original notice, even if it meets capacity again.
    const retryAbout = text === GO_ON_AFTER_OVERLOADED ? store.lastTurn(this.key)?.about ?? null : null;
    // Archived: only a new message starts a turn (and has brought it back by then).
    if (kind !== "input" && this.archived()) {
      log.info("session", "archived: no turn of its own", { session: this.key, kind });
      return;
    }
    try {
      // Until the runtime says it has sent its request, the turn is starting.
      this.deps.live?.event(this.key, { kind: "phase", phase: "starting" });
      // Started by a message or a notice, its large context's cache over, where its chat or else its station is set to
      // (`afresh`, config.json `afreshWhenCold`): it goes on afresh, as 换新上下文 has it by hand, not with all of it
      // sent again (a wait of its own ends with it; its jobs, watches too, go on). Not while it has work going in the background (which would end
      // with its process).
      if ((kind === "input" || kind === "job") && !this.holding() && !this.agent?.session.busy() && this.deps.coldAfresh?.(this.key, this.now()) === true) {
        await this.clearNow(true, "station.notice.afreshCold", "as its cache is over", true);
      }
      let agent = await this.ensureAgent();
      const row = store.getSession(this.key);
      // A session begun in a terminal and continued here: its first turn here says so, with how still.fail works.
      const continued = row && row.cwd && !store.hasTurns(this.key) ? continuedHere(sessionInstructions(row.workspace, row.cwd, this.deps.reposDir(), this.deps.memoryPath(this.key), await this.deps.linkSkills(row))) : null;
      const lost = this.resumeLost;
      this.resumeLost = false;
      // What people chose on its cards without a message since it was last handed anything: before what it is handed.
      const [handed, toldChoices] = await this.withChoices(text);
      let prompt = lost ? `${this.deps.resumeLost?.(this.key) ?? resumeLost(this.key, [])}\n\n${handed}` : handed;
      const stopped = this.stoppedNote;
      this.stoppedNote = null;
      if (stopped !== null) prompt = `${stopped}\n\n${prompt}`;
      const afresh = this.afresh;
      this.afresh = null;
      const compacted = this.compactedUntold;
      this.compactedUntold = false;
      // Gone on in a new conversation, or compacted: in a long chat, told to read back what people said in it.
      const long = lost || afresh !== null || compacted ? (this.deps.longChat?.(this.key) ?? null) : null;
      if (long !== null) prompt = `${long}\n\n${prompt}`;
      if (afresh !== null) prompt = `${afresh}\n\n${prompt}`;
      if (continued !== null) prompt = `${continued}\n\n${prompt}`;
      // What changed in how it works since it was last told (migrations): once, before what it is handed.
      const told = store.toldNotes(this.key) ?? latestNote();
      if (told < latestNote()) {
        const full = row ? join(row.workspace, ".stillfail-instructions.md") : "";
        if (row) {
          try {
            const preset = row.cwd ? null : presetCopyOf(row.workspace);
            const memory = await this.deps.linkSkills(row);
            await writeFile(full, sessionInstructions(row.workspace, row.cwd ?? null, this.deps.reposDir(), this.deps.memoryPath(this.key), memory) + (preset ? presetInstructions(preset) : ""));
          } catch {}
        }
        store.setToldNotes(this.key, latestNote());
        prompt = `${untold(told, full)}\n\n${prompt}`;
      }
      // The runtime may have started a turn on its own (late input became a turn); join it.
      if (agent.busy() && (await agent.steer(prompt))) return toldChoices();
      this.steered = [];
      this.steeredFor = [];
      this.unread = [];
      this.beginTurn(kind, by);
      if (retryAbout && this.turn) store.setAbout((this.turn as Turn).id, [retryAbout.thread, retryAbout.seq, retryAbout.ts]);
      try {
        await agent.prompt(prompt);
      } catch (error) {
        // The runtime is unusable (died between turns, or refused): replace it once.
        log.warn("session", "prompt failed, reopening the runtime", { session: this.key, error: (error as Error).message });
        this.agent = null;
        await agent.dispose();
        agent = await this.ensureAgent();
        await agent.prompt(prompt);
      }
      toldChoices();
    } catch (error) {
      const message = (error as Error).message;
      const turn = this.turn;
      this.turn = null;
      this.phase = "idle";
      if (turn) store.endTurn(turn.id, "failed", `other: ${message}`, null, null);
      store.setRunning(this.key, false);
      // It was said to be starting: no turn runs.
      await this.deps.live?.turnEnded(this.key);
      this.doneWorking();
      // Not installed here: said so, about the runtime (the pages offer to install it; once installed, what waits goes
      // on). Tried again (each restart gives it what waits) and failing the same, it is not said again.
      const missing = error instanceof CommandMissing && error.command === this.runtime;
      if (missing) this.deps.runtimeMissing?.(this.runtime);
      const said = missing ? `⚠️ ${t("station.notice.runtimeMissing", { name: runtimeLabel(this.runtime) })}` : `⚠️ ${cannotStartWords(error)}`;
      // Nothing said since it last could not start: not said again, for another reason either (two taking turns as the
      // station restarted filled a chat, 2026-11-02). A person's word in between is answered.
      const cannotStart = `⚠️ ${t("station.notice.cannotStart")}`;
      if (!this.saidLast((last) => last === said || (!missing && last.startsWith(cannotStart)))) {
        await this.notice(said, null, missing ? this.runtime : null, turn ? (where) => { store.setAbout(turn.id, where); store.notify(this.key); } : undefined);
      }
      throw error;
    }
  }

  private beginTurn(kind: string, by: TurnFor) {
    // Given something new: what it says from here on is what counts.
    if (kind === "input" || kind === "job") {
      this.lastSaid = "";
      this.posted = false;
    }
    const id = crypto.randomUUID();
    this.turn = { id, declared: null, authRetried: kind === "auth_retry", codexRetried: kind === "codex_retry", by };
    this.phase = "running";
    this.waiting = null;
    this.deps.store.startTurnFor(id, this.key, kind, { ...by, profile: this.profile });
    this.deps.store.setRunning(this.key, true);
  }

  /// A process idle since the session was changed takes its new model and effort in place, when it runs on the same
  /// profile and can; otherwise it ends (when `end`: not while a turn or a wait holds on to it), also when no profile
  /// can run it now (its own deleted, none to take it on).
  private async catchUp(end: boolean) {
    const agent = this.agent;
    if (!agent || !this.stale || agent.session.busy()) return;
    const row = this.deps.store.getSession(this.key);
    let profile: ReturnType<SessionDeps["runOn"]> | null = null;
    try {
      profile = row ? this.deps.runOn(this.key, this.holding()) : null;
    } catch {}
    const ready = row && profile && !this.restart && profile.id === this.profile && agent.session.retune ? await this.deps.linkSkills(row) : "";
    if (!this.restart && row && profile && profile.id === this.profile && agent.session.retune?.(openOptions(row, profile, this.deps, ready))) {
      this.stale = false;
      this.runningIdentity = { runtime: this.runtime, model: row.model ?? null, effort: row.effort ?? null };
      log.info("session", "session process takes the change in place", { session: this.key, model: row.model ?? "", effort: row.effort ?? "" });
      return;
    }
    if (!end) return;
    this.stale = false;
    this.restart = false;
    this.agent = null;
    log.info("session", "ending the process from before the session was changed", { session: this.key, background: agent.session.background?.().length ?? 0 });
    await this.endProcess(agent);
    this.deps.store.notify(this.key);
  }

  /// Whether its process has work going in the background (which ends with it).
  private holding(): boolean {
    return (this.agent?.session.background?.().length ?? 0) > 0;
  }

  /// Ends a process of its the station leaves: what it had going in the background ends with it, and its next turn is
  /// told (`stoppedNote`).
  private async endProcess(agent: { session: AgentSession } | null) {
    if (!agent) return;
    this.stopped.push(...(agent.session.background?.() ?? []));
    await agent.session.dispose();
  }

  private async ensureAgent(): Promise<AgentSession> {
    // Before each turn the account is asked about again: one whose five hours are nearly full is left for one with
    // room when its context was just compacted or is about to be (accounts.ts runOn), before a turn runs into it; not
    // while its process has work going in the background, which would end with it.
    if (this.agent && !this.stale && !this.agent.session.busy()) {
      try {
        if (this.deps.runOn(this.key, this.holding()).id !== this.profile) this.stale = true;
      } catch {}
    }
    await this.catchUp(true);
    if (this.agent) return this.agent.session;
    if (await this.deps.archiveIsCold(this.key)) await this.deps.restoreArchive(this.key);
    const store = this.deps.store;
    const row = store.getSession(this.key);
    if (!row) throw new Error(`session ${this.key} disappeared`);
    const runtime = runtimeKind(row.runtime);
    if (!runtime) throw new Error(`session ${this.key} runs an unknown runtime ${row.runtime}`);
    this.runtime = runtime;
    const driver = this.deps.driver(this.runtime);
    const profile = this.deps.runOn(this.key);
    const memory = await this.deps.linkSkills(row);
    const base = openOptions(row, profile, this.deps, memory);
    // Its context cleared by hand (clear): no runtime session now, those before on record. A new one, told so; one
    // continued from a terminal is given still.fail's instructions as a new session is (no cache of its own to keep).
    const wasCleared = row.runtimeSessionId === null && (store.runtimeSessions?.(this.key).length ?? 0) > 0;
    if (wasCleared && row.cwd) base.instructions = sessionInstructions(row.workspace, row.cwd, this.deps.reposDir(), this.deps.memoryPath(this.key), memory);
    // A runtime started where the station may not read exits at once with nothing to say why (macOS privacy protection
    // on a session continued in ~/Documents): told as it is instead. A directory someone named (one continued from a
    // terminal) is looked at as ops/places.ts does, never on this thread in a folder macOS protects (still.fail Helper
    // asked for it, its window put up for a grant it lacks); the session's own workspace is the station's.
    if (row.cwd) await (this.deps.places ?? defaultPlaces()).directory(row.cwd, { lang: stationLang() });
    else if (unreadableDir(base.cwd)) throw new Said(unreadableDirMessage(stationLang(), base.cwd));
    const generation = this.nextGeneration();
    let agent: AgentSession;
    // Recorded before it may be left, so the history reads on from it.
    if (row.runtimeSessionId) this.deps.ranIn?.(this.key, row.runtimeSessionId, null);
    const afresh = row.runtimeSessionId ? (this.deps.startsAfresh?.(this.key, row.runtimeSessionId, profile, this.profile) ?? null) : null;
    // What its process before had going in the background, stopped with it: its subagents are taken up again in the
    // runtime session resumed, or taken to the new one.
    const stopped = this.stopped;
    const subagents = stopped.filter((t) => t.kind === "agent").map((t) => t.id);
    let resumable: string[] = [];
    if (afresh !== null) {
      log.info("session", "going on in a new runtime session on another account", { session: this.key, left: row.runtimeSessionId, profile: profile.id });
      agent = await driver.open(base, this.listener(generation));
      this.afresh = afresh;
      const from = store.runtimeSessionSource ? store.runtimeSessionSource(this.key, row.runtimeSessionId!) ?? undefined
        : store.runtimeSessionSources?.(this.key).find((s) => s.id === row.runtimeSessionId);
      if (from === undefined || from.runtime === row.runtime) resumable = this.deps.carrySubagents?.(row.runtimeSessionId!, agent.id(), profile, subagents) ?? [];
    } else if (row.runtimeSessionId) {
      try {
        agent = await driver.open({ ...base, resume: row.runtimeSessionId }, this.listener(generation));
        resumable = subagents;
      } catch (error) {
        log.warn("session", "resume failed; starting a new runtime session", { session: this.key, id: row.runtimeSessionId, error: (error as Error).message });
        agent = await driver.open(base, this.listener(generation));
        this.resumeLost = true;
      }
    } else {
      agent = await driver.open(base, this.listener(generation));
      if (wasCleared) this.afresh = this.deps.cleared?.(this.key, this.readBack) ?? (this.readBack ? afreshNote(this.key, []) : cleared(this.key, []));
      this.readBack = false;
    }
    // Recorded before it is the one gone on with: its conversation's calls are those from then (store.ts `conversationSince`).
    this.deps.ranIn?.(this.key, agent.id(), profile.id);
    if (row.runtimeSessionId !== agent.id()) {
      store.setRuntimeSessionId(this.key, agent.id());
      if (row.runtimeSessionId || wasCleared) this.deps.live?.moved?.(this.key);
    }
    this.stopped = [];
    if (stopped.length > 0) this.stoppedNote = backgroundStopped(stopped, resumable);
    this.agent = { generation, session: agent };
    this.runningIdentity = { runtime: this.runtime, model: row.model ?? null, effort: row.effort ?? null };
    this.stale = false;
    this.restart = false;
    this.profile = profile.id;
    return agent;
  }

  private isCurrent(generation: number) {
    return this.agent?.generation === generation;
  }

  /// A runtime session's events, in order: live steps at once (they only feed the status line and watchers), the rest
  /// through the queue.
  private onEvent(generation: number, event: RuntimeEvent) {
    switch (event.type) {
      case "turnStarted":
        void this.enqueue(async () => {
          if (!this.isCurrent(generation) || this.turn || this.compacting) return;
          this.beginTurn("input", nobody);
          // Given messages too late for the turn that ended (Claude reads one written as its turn ends as a turn of its
          // own): their threads see it working again, and where the ended turn stood no longer stands.
          if (this.workingFor.length === 0 && this.steeredFor.length > 0) {
            this.workingFor = this.steeredFor.map((w) => ({ ...w, firstTs: w.ts, since: this.now() }));
            this.steeredFor = [];
            this.say(t("station.status.thinking"));
          }
        });
        break;
      case "turnEnded": {
        // What it wrote last is read (off the main thread) and told before the turn is said to be over.
        const read = this.deps.live?.turnEnded(this.key);
        this.doneWorking();
        void this.enqueue(async () => {
          await read;
          await this.onTurnEnded(generation, event.outcome);
        });
        break;
      }
      case "live":
        // Asking its model: what was given to the turn so far goes with the request.
        if (event.event.kind === "phase" && event.event.phase === "requesting") {
          // What it said of the turn it said without seeing them: it says where it stands again.
          if (this.unread.length > 0) void this.enqueue(async () => this.undeclare());
          this.unread = [];
        }
        this.deps.live?.event(this.key, event.event);
        if (this.isCurrent(generation)) this.heard(event.event);
        this.onLive(event.event);
        break;
      case "toolsLost":
        void this.enqueue(async () => {
          if (!this.isCurrent(generation) || this.toolsLost !== null) return;
          log.warn("session", "the agent cannot reach the station's tools", { session: this.key, why: event.why });
          this.toolsLost = event.why;
        });
        break;
      case "compacted":
        void this.enqueue(() => this.onCompacted(generation));
        break;
      case "closed":
        void this.enqueue(async () => {
          if (!this.isCurrent(generation)) return;
          log.info("session", "session runtime closed", { session: this.key, reason: event.why });
          if (this.compacting) {
            this.compacting = false;
            this.deps.store.setRunning(this.key, false);
          }
          // What it had going in the background is gone with it.
          const gone = this.agent?.session.background?.() ?? [];
          this.stopped.push(...gone);
          this.agent = null;
          this.deps.store.notify(this.key);
          // Waiting on it, it would never be brought back: it goes on now, as at a turn's end.
          if (gone.length > 0 && this.phase === "waiting" && !this.deps.held(this.key)) {
            log.info("session", "its background work ended with its process while it waits; going on now", { session: this.key, stopped: gone.length });
            await this.startTurn("resume", BACKGROUND_STOPPED_WAITING);
          }
        });
        break;
    }
  }

  /// Its context compacted: in a long chat, told to read back what people said in it. Compacted on its own in the
  /// middle of a turn, the turn is told at once; compacted by hand (a turn of its own) or with the turn over, its next
  /// prompt tells it.
  private async onCompacted(generation: number) {
    if (!this.isCurrent(generation)) return;
    const agent = this.agent?.session;
    if (!this.compacting && agent?.busy()) {
      const long = this.deps.longChat?.(this.key) ?? null;
      // As a notice is (takeNotices): a message from the station, not from the people of the chat.
      if (long === null || (await agent.steer(`<message via="station" from="station" ts="${this.deps.nextTs()}">\n${long}\n</message>`))) return;
    }
    this.compactedUntold = true;
  }

  /// The agent's own words as they come (not a subagent's, not its thinking).
  private heard(event: LiveEvent) {
    if (event.kind === "start" && event.step === "text" && !event.subagent && event.parent === undefined) this.saying = { id: event.id, text: "" };
    else if (event.kind === "delta" && event.field === "text" && event.id === this.saying?.id) {
      this.saying.text += event.text;
      if (this.saying.text.trim() !== "") this.lastSaid = this.saying.text.trim();
    }
  }

  private async onTurnEnded(generation: number, outcome: TurnOutcome) {
    if (!this.isCurrent(generation)) return;
    if (this.compacting && !this.turn) return this.compacted(outcome);
    const store = this.deps.store;
    this.idleSince = this.now();
    const turn = this.turn;
    this.turn = null;
    this.phase = "idle";
    const stopRequested = this.stopRequested;
    this.stopRequested = false;
    store.setRunning(this.key, false);
    // The provider had no room for it (not its account's doing: another would fare no better): it waits, as on work of
    // its own, and is tried again after a while, longer each time; stopped meanwhile, it is not.
    const overloaded = turn !== null && outcome.kind === "failed" && outcome.reason === "overloaded" && !stopRequested;
    const retry: DeclaredState | null = overloaded ? { kind: "waiting", seconds: retryAfter(this.overloads++) } : null;
    if (!overloaded) this.overloads = 0;
    const ends = retry ?? (turn ? endedIn(turn.declared, outcome.kind) : null);
    if (turn) {
      const detail = outcome.kind === "failed" ? `${outcome.reason}: ${outcome.message}` : null;
      store.endTurn(turn.id, outcome.kind, detail, ends?.kind ?? null, ends?.kind === "waiting" ? ends.seconds : null);
      if (retry) store.setWaitFor(turn.id, t("station.wait.overloaded"), false);
    }
    // Its process could not reach the station's tools: what it said through them reached nobody, and its next turn
    // would fare no better. It ends; the next one (resuming) is given the station's tools as they are now.
    const lost = this.toolsLost;
    this.toolsLost = null;
    if (lost !== null) {
      const agent = this.agent;
      this.agent = null;
      log.warn("session", "ending the process that lost the station's tools; the next one resumes it", { session: this.key, why: lost });
      await this.endProcess(agent);
      store.notify(this.key);
    }
    if (turn?.declared) this.toolsRestarts = 0;
    // This refusal is about the local Codex binary, not the account or the model. Do not replay the input: a turn may
    // have done work before it asked the model, so resume the transcript after the shared update instead.
    if (this.runtime === "codex" && outcome.kind === "failed" && codexTooOld(outcome.message) && !stopRequested && !this.deps.held(this.key) && turn && !turn.codexRetried && !turn.declared && this.deps.updateOldCodex) {
      const agent = this.agent;
      const version = agent?.session.runtimeVersion?.() ?? null;
      const update = { by: turn.by, finished: false };
      this.codexUpdate = update;
      this.agent = null;
      this.nudges = 0;
      await this.notice(t("station.notice.codexUpdating"), null, null, (where) => { store.setAbout(turn.id, where); store.notify(this.key); });
      await this.endProcess(agent);
      store.setRunning(this.key, true);
      // Do not hold the session queue during an install: stop and new messages must still be accepted.
      void Promise.resolve().then(async () => {
        if (agent?.session.runtimeUpdateMatchesStation && !(await agent.session.runtimeUpdateMatchesStation())) throw new Error(t("station.notice.codexDifferentPath"));
        await this.deps.updateOldCodex!(version);
      }).then(
        () => this.enqueue(async () => {
          if (this.codexUpdate !== update) return;
          update.finished = true;
          await this.continueAfterCodexUpdate(update);
        }),
        (error) => this.enqueue(async () => {
          if (this.codexUpdate !== update) return;
          this.codexUpdate = null;
          store.setRunning(this.key, false);
          const why = (error as Error)?.message || String(error);
          await this.notice(`⚠️ ${t("station.notice.codexUpdateFailed", { why })}`, null, null, (where) => { store.setAbout(turn.id, where); store.notify(this.key); });
          this.deps.settled?.(this.key, "failed", why);
          this.deps.idle(this.key);
          if (store.hasPending(this.key)) await this.pump();
        }),
      );
      return;
    }
    // Every Codex authentication refusal updates account health, including the retry's refusal.
    if (this.runtime === "codex" && outcome.kind === "failed" && outcome.reason === "auth" && !stopRequested && this.profile !== null) {
      await this.deps.recheck?.(this.profile);
    }
    // Reopen once so it reads the current credentials (and refreshes an expiring machine token). Resume its
    // transcript with a continuation, never replay the original request: it may already have run tools.
    if ((this.runtime === "claude" || this.runtime === "codex") && outcome.kind === "failed" && outcome.reason === "auth" && !stopRequested && !this.deps.held(this.key) && turn && !turn.authRetried && !turn.declared) {
      this.nudges = 0;
      const agent = this.agent;
      this.agent = null;
      await this.endProcess(agent);
      // Its account checked first: one whose login is over is left, and the turn goes on on another (`runOn`).
      if (this.runtime === "claude" && this.profile !== null) await this.deps.recheck?.(this.profile);
      log.info("session", "authentication failed; reopening and continuing once", { session: this.key, runtime: this.runtime });
      await this.startTurn("auth_retry", GO_ON_AFTER_AUTH, turn.by);
      if (this.turn && turn.codexRetried) (this.turn as Turn).codexRetried = true;
      return;
    }
    const spent = outcome.kind === "failed" && outcome.reason === "rate_limit";
    if (!spent) this.refill = null;
    if (spent) {
      this.nudges = 0;
      // Left to the station, it moves to another account and goes on there; otherwise it waits for a change.
      let moved: [string, string] | null = null;
      try {
        // A model's own limit is that model's on this account alone: its others still run there (#4643).
        moved = this.deps.spend(this.key, this.profile, modelLimitOf(outcome.message));
      } catch (error) {
        log.warn("session", "could not move off a spent profile", { session: this.key, error: (error as Error).message });
      }
      if (moved) {
        // Its process runs on the account left: the next starts on the one taken.
        const agent = this.agent;
        this.agent = null;
        await this.endProcess(agent);
        log.info("session", "allowance ran out; going on on another profile", { session: this.key, from: moved[0], to: moved[1] });
        this.refill = null;
        if (store.hasPending(this.key)) return this.pump();
        return this.startTurn("resume", GO_ON_AFTER_SPENT);
      }
      // Said once: what wakes it meanwhile (a job's notice, a wait over) would only run into it again.
      if (!this.saidLast((said) => [failureNotice(outcome).split("\n\n")[0]!, SPENT_NOTICE(), ...SPENT_BEFORE].some((s) => said.startsWith(s)))) {
        await this.notice(failureNotice(outcome), this.profile, null, turn ? (where) => { store.setAbout(turn.id, where); store.notify(this.key); } : undefined);
      } else if (turn) {
        // The existing notice is deliberately reused for this turn; retain its identity as for a new notice.
        const latest = store.latestThread(this.key);
        const last = latest ? store.entriesBefore(latest.thread.id, null, 1).at(-1) : undefined;
        if (latest && last) {
          store.setAbout(turn.id, [latest.thread.id, last.n, last.ts]);
          store.notify(this.key);
        }
      }
      this.awaitRefill(this.deps.refillsAt?.(this.key) ?? this.now() + REFILL_FALLBACK_MS);
    } else if (overloaded) {
      this.nudges = 0;
      // Reuse only this retry's own notice. A different agent can have said the same thing in this thread.
      const about = store.lastTurn(this.key)?.about;
      const latest = store.latestThread(this.key);
      const last = latest ? store.entriesBefore(latest.thread.id, null, 1).at(-1) : undefined;
      const same = about && last && about.thread === latest.thread.id && about.seq === last.n && about.ts === last.ts && last.text === OVERLOADED_NOTICE();
      if (!same) {
        await this.notice(OVERLOADED_NOTICE(), null, null, (where) => store.setAbout(turn!.id, where));
      }
      store.notify(this.key);
    } else if (outcome.kind === "failed") {
      this.nudges = 0;
      // A sign-in that failed is its profile's, as is a refused request (its environment is where a proxy goes): the
      // notice points there.
      const said = this.runtime === "codex" && turn?.codexRetried && codexTooOld(outcome.message)
        ? `⚠️ ${withSaid(t("station.notice.codexStillOld"), outcome.message)}` : failureNotice(outcome);
      await this.notice(said, outcome.reason === "auth" || outcome.reason === "refused" ? this.profile : null, null, turn ? (where) => { store.setAbout(turn.id, where); store.notify(this.key); } : undefined);
    } else if (outcome.kind === "aborted") {
      this.nudges = 0;
      if (stopRequested) {
        await this.stopBackground();
        await this.notice(t("station.notice.stopped"));
      }
    }

    // Told to whoever opened its chat: how the turn ended, when it ended in a state or did not get there.
    if (turn) {
      const ended = turn.declared?.kind === "all_done" ? "all_done" : turn.declared?.kind === "need_help" ? "need_human" : retry ? null : outcome.kind === "failed" ? "failed" : outcome.kind === "aborted" && stopRequested ? "stopped" : null;
      const words = ended === "failed" ? (outcome.kind === "failed" ? outcome.message : null) : (store.lastTurn(this.key)?.need ?? null);
      // Where it stands, said in its threads under their last message as its chat says it at its end: done, or what it
      // needs (failed and stopped have their notice there already; waiting says nothing); in a thread it left
      // (chat_leave), that it left, however the turn ended, so people there see it no longer follows
      const stands = ended === "all_done" ? { kind: "done" as const, words } : ended === "need_human" ? { kind: "need" as const, words } : null;
      for (const w of this.endedFor) {
        const left = store.leftThread?.(this.key, w.connect, w.channel, w.threadTs) === true;
        this.deps.chat(w.connect)?.standsAt?.({ channel: w.channel, threadTs: w.threadTs }, left ? { kind: "left", words: null } : stands);
      }
      if (ended !== null) {
        try {
          this.deps.settled?.(this.key, ended, words);
        } catch (error) {
          log.warn("session", "the opener of its chat was not told", { session: this.key, error: (error as Error).message });
        }
      }
    }
    // Archived while it ran: it waits on nothing.
    if (this.archived()) {
      await this.letGo();
      this.deps.idle(this.key);
      return;
    }
    if (outcome.kind === "completed" && ends?.kind !== "waiting" && (await this.compactingToCap())) return;
    if (store.hasPending(this.key)) return this.pump();
    if (this.notices.length > 0) return this.giveNotices();
    const declared = turn?.declared ?? null;
    if (ends?.kind === "waiting") {
      this.nudges = 0;
      // What it waits on may be the background work its process just ended with (it lost the station's tools): that
      // would never bring it back, so it goes on now, told what stopped, rather than when the wait runs out.
      if (!retry && this.stopped.length > 0 && !this.deps.held(this.key)) {
        log.info("session", "its background work ended with its process while it waits; going on now", { session: this.key, stopped: this.stopped.length });
        return this.startTurn("resume", BACKGROUND_STOPPED_WAITING);
      }
      this.wait(ends.seconds);
      this.deps.idle(this.key);
      return;
    }
    this.deps.idle(this.key);
    if (outcome.kind !== "completed" || declared) {
      this.nudges = 0;
      // Done or asking, and its chat still has no title with nobody at work there: asked once to name it.
      const untitled = outcome.kind === "completed" && !this.deps.held(this.key) ? this.deps.untitled?.(this.key) ?? null : null;
      if (untitled !== null && !this.askedToName.has(untitled)) {
        this.askedToName.add(untitled);
        log.info("session", "its chat has no title; asking it to name it", { session: this.key, chat: untitled });
        return this.startTurn("title", nameUntitled(untitled));
      }
      return;
    }
    if (this.deps.held(this.key)) return;
    // Not nudged (it could not have answered): told to go on in the new process, once; lost again, given up on.
    if (lost !== null) {
      this.nudges = 0;
      if (this.toolsRestarts < MAX_TOOLS_RESTARTS) {
        this.toolsRestarts++;
        log.info("session", "the turn reached nobody; going on in a new process", { session: this.key, attempt: this.toolsRestarts });
        return this.startTurn("resume", TOOLS_LOST);
      }
      this.toolsRestarts = 0;
      return this.giveUp(turn?.id ?? null);
    }
    if (this.nudges < this.deps.maxNudges()) {
      this.nudges++;
      log.info("session", "turn ended without a state; nudging", { session: this.key, attempt: this.nudges });
      return this.startTurn("nudge", NUDGE);
    }
    this.nudges = 0;
    await this.giveUp(turn?.id ?? null);
  }

  /// A completed install resumes only this failed turn; stopping, archiving or a newer update invalidates it.
  private async continueAfterCodexUpdate(update: { by: TurnFor; finished: boolean }) {
    if (this.codexUpdate !== update || !update.finished || this.deps.held(this.key)) return;
    this.codexUpdate = null;
    this.deps.store.setRunning(this.key, false);
    if (this.archived()) return;
    await this.startTurn("codex_retry", GO_ON_AFTER_CODEX_UPDATE, update.by);
    if (this.deps.store.hasPending(this.key)) await this.pump();
    else if (this.notices.length > 0) await this.giveNotices();
  }

  /// No turn ended in a state, and no more are asked for: the thread is told so, with the agent's last words when it
  /// posted none (it may have answered where nobody reads: its tools out of reach), marked as the station's.
  private async giveUp(turnId: string | null) {
    const said = this.posted ? "" : this.lastSaid;
    this.lastSaid = "";
    const store = this.deps.store;
    const recorded = turnId !== null ? (where: [number, number, string]) => { store.setAbout(turnId, where); store.notify(this.key); } : undefined;
    if (said === "") return this.notice(`⚠️ ${t("station.notice.noResult")}`, null, null, recorded);
    log.info("session", "the turn reached nobody; its last words are shown in its place", { session: this.key });
    const quoted = chars(said, FALLBACK_MOST).split("\n").map((line) => `> ${line}`).join("\n");
    await this.notice(`⚠️ ${t("station.notice.noResultSaid")}\n\n${quoted}`, null, null, recorded);
  }

  /// Stopped while it waits: the wait ends, and so does the work that would bring it back (session.rs `stop_waiting`).
  /// `keepJobs`: only the wait ends; its jobs go on (`clearNow` when it goes on afresh by itself).
  private async stopWaiting(say = true, keepJobs = false) {
    const store = this.deps.store;
    const refill = this.refill !== null;
    const waited = this.waiting !== null || refill;
    this.waiting = null;
    this.refill = null;
    if (this.phase === "waiting") this.phase = "idle";
    // Its wait may be on record only (an earlier station had it).
    const last = store.lastTurn(this.key);
    const recorded = last && last.endedAt !== null && last.declared === "waiting";
    if (!waited && !recorded) return;
    log.info("session", "stopped while waiting", { session: this.key });
    // A turn waiting to be tried again waits on no work of its own: its jobs go on. Asked again, it starts over.
    if (last && retrying(last)) this.overloads = 0;
    else if (!keepJobs) await this.deps.stopJobs(this.key);
    this.nudges = 0;
    const agent = this.agent;
    this.agent = null;
    await agent?.session.dispose();
    store.stopWait(this.key, refill);
    if (say) await this.notice(t("station.notice.stopped"));
  }

  /// Stopped by hand while it ran: what would bring it back on its own ends too, as with a wait (`stopWaiting`). Its
  /// process ends, with the work it had going in the background and what that work had to tell it at the turn's end
  /// (Claude runs that as a turn of its own the moment the stopped one ends); so do the jobs that would tell it, and
  /// what they told meanwhile is let go. Only a message brings it back; its next turn is told what was stopped.
  private async stopBackground() {
    const agent = this.agent;
    this.agent = null;
    await this.endProcess(agent);
    await this.deps.stopJobs(this.key);
    this.notices = [];
    this.deps.store.notify(this.key);
  }

  /// Archived (by hand or by the station): what would bring it back ends, without a word in its thread.
  private async letGo() {
    this.notices = [];
    this.nudges = 0;
    const waited = this.waiting !== null;
    this.waiting = null;
    if (this.phase === "waiting") this.phase = "idle";
    const last = this.deps.store.lastTurn(this.key);
    if (waited || (last && last.endedAt !== null && last.declared === "waiting")) {
      log.info("session", "archived: its wait ends", { session: this.key });
      this.deps.store.stopWait(this.key);
    }
    await this.deps.endJobs(this.key);
  }

  private archived(): boolean {
    return (this.deps.store.getSession(this.key)?.archivedAt ?? null) !== null;
  }

  /// Asks the agent again after `seconds`, unless a turn has started by then.
  private wait(seconds: number) {
    this.waitMs(seconds, seconds * 1000);
  }

  /// The same, with `ms` of it left. The timer is a fiber of this actor's: it ends with it.
  private waitMs(seconds: number, ms: number) {
    const wait = ++this.waits;
    this.waiting = wait;
    this.phase = "waiting";
    this.waitingUntil = this.now() + ms;
    this.waitingSeconds = seconds;
    void this.run(
      Effect.sleep(Math.max(0, ms)).pipe(
        Effect.andThen(
          Effect.promise(() =>
            this.enqueue(async () => {
              // Held: the wait stays, for the next station to take up.
              if (this.deps.held(this.key) || this.waiting !== wait) return;
              if (this.archived()) return this.letGo();
              if (this.compacting) {
                this.overWhileCompacting = true;
                return;
              }
              this.waiting = null;
              this.phase = "idle";
              // Waiting on its watch: the watch brings it back (its notices, its end), not the clock; it waits on. A wait
              // for something else runs out as any, a watch running or not (one said before `watch`: taken as its watch).
              const last = this.deps.store.lastTurn(this.key);
              if (last && retrying(last)) {
                log.info("session", "trying again a turn the provider had no room for", { session: this.key, seconds });
                return this.startTurn("resume", GO_ON_AFTER_OVERLOADED);
              }
              if (last?.waitWatch !== false && this.deps.store.hasSessionActiveWatch(this.key)) return this.wait(seconds);
              log.info("session", "the wait is over without word; asking again", { session: this.key, seconds });
              await this.startTurn("nudge", waitOver(seconds));
            }),
          ),
        ),
      ),
    ).catch(() => undefined);
  }

  /// Whether the thread people spoke in last ends with these very words of the station's: nothing said since.
  private saidLast(text: string | ((said: string) => boolean)): boolean {
    const latest = this.deps.store.latestThread(this.key);
    const last = latest ? this.deps.store.entriesBefore(latest.thread.id, null, 1).at(-1) : undefined;
    return last !== undefined && last.authorKind === STATION_AUTHOR && (typeof text === "string" ? last.text === text : text(last.text));
  }

  /// Its account spent with none to move to: at `at` it goes on there by itself, with what waited meanwhile.
  private awaitRefill(at: number) {
    const refill = ++this.refills;
    this.refill = refill;
    this.refillAt = at;
    void this.run(
      Effect.sleep(Math.max(0, at - this.now())).pipe(
        Effect.andThen(
          Effect.promise(() =>
            this.enqueue(async () => {
              if (this.refill !== refill) return;
              // Held: keep the wait so release can run it.
              if (this.deps.held(this.key)) return;
              this.refill = null;
              if (this.archived() || this.turn || this.agent?.session.busy()) return;
              log.info("session", "its allowance should have refilled; going on", { session: this.key });
              if (this.deps.store.hasPending(this.key)) return this.pump();
              await this.startTurn("resume", GO_ON_AFTER_REFILL);
            }),
          ),
        ),
      ),
    ).catch(() => undefined);
  }

  /// Its run changed (lifecycle.ts `configure`): said in its chat, how it ran and how it runs now kept with the words
  /// (the clients say what changed from them).
  async runChanged(change: RunChange): Promise<void> {
    await this.notice(runChangeWords(change, stationLang()), null, null, undefined, change);
  }

  /// The station's own words (not the agent's) go to the thread people spoke in last, and are recorded there; one about
  /// a profile (`profile`, its id) is linked to that profile's page, one about a runtime not installed (`runtime`)
  /// offers to install it; one that its run changed keeps how (`change`).
  private async notice(text: string, profile: string | null = null, runtime: RuntimeKind | null = null, recorded?: (where: [number, number, string]) => void, change?: RunChange) {
    const store = this.deps.store;
    const latest = store.latestThread(this.key);
    const chat = latest ? this.deps.chat(latest.connect) : undefined;
    if (!latest || !chat) {
      log.warn("session", "no thread to post a notice to", { session: this.key, text });
      return;
    }
    try {
      const ts = await chat.post({ channel: latest.thread.channel, threadTs: latest.thread.threadTs }, text, []);
      const [n] = store.insertMessage({ thread: latest.thread.id, ts, authorKind: STATION_AUTHOR, author: STATION_AUTHOR, text, profile, runtime, attachments: [], quotes: [], declared: null, client: null, card: null, options: null, agentIdentity: null, ...(change !== undefined ? { change } : {}) });
      recorded?.([latest.thread.id, n, ts]);
    } catch (error) {
      log.warn("session", "notice failed", { session: this.key, error: (error as Error).message });
    }
  }
}

/// How a session's runtime session is opened (or taken up) on `profile`: its directory, model as the profile spells it,
/// effort, instructions and MCP token.
/// What a session's process opening needs off the station's thread, before `openOptions`: its workspace's skills where
/// it runs (agent-home.ts), kept up with each time it is opened or retuned (a session continued from a terminal runs in
/// the person's own project, given none), and its workspace's memory as it is now, which it gives back.
export async function linkSkills(row: any, deps: Pick<SessionDeps, "memoryPath">): Promise<string> {
  const memory = readMemory(deps.memoryPath(row.key));
  if (!row.cwd) {
    try {
      await sessionSkills(row.workspace, join(dirname(deps.memoryPath(row.key)), "skills"));
    } catch (error) {
      log.warn("session", "its workspace's skills not linked where it runs", { session: row.key, error: (error as Error).message });
    }
  }
  return memory;
}

/// `memory`: its workspace's memory as `linkSkills` gave it.
export function openOptions(row: any, profile: Profile & { spelling?(model: string): string | null }, deps: Pick<SessionDeps, "mcpUrl" | "reposDir" | "memoryPath">, memory: string): OpenOptions {
  const skills = row.cwd ? undefined : join(dirname(deps.memoryPath(row.key)), "skills");
  // The model as this profile spells it (openai/gpt-6-astra on a router for gpt-6-astra).
  const model = row.model ? (profile.spelling?.(row.model) ?? row.model) : undefined;
  // What its chat was opened with (presets.ts): told after the station's own instructions (its folders' skills are in
  // its workspace already).
  const preset = row.cwd ? null : presetCopyOf(row.workspace);
  return {
    key: row.key,
    profile,
    cwd: row.cwd ?? row.workspace,
    model,
    effort: row.effort ?? undefined,
    ...(typeof row.context === "number" ? { context: row.context } : {}),
    ...(typeof row.fast === "boolean" ? { fast: row.fast } : {}),
    // A session continued from a terminal keeps the system prompt it began with (its cache holds).
    instructions: row.cwd ? "" : sessionInstructions(row.workspace, null, deps.reposDir(), deps.memoryPath(row.key), memory) + (preset ? presetInstructions(preset) : ""),
    ...(skills !== undefined ? { skills } : {}),
    mcpToken: row.token,
    mcpUrl: deps.mcpUrl(),
    route: row.key,
  };
}

/// How long a spent account is waited on when it refills is not known.
const REFILL_FALLBACK_MS = 60 * 60 * 1000;

/// The notice that its account is spent; and how stations before 2026-11-03 began it (going on with what the runtime
/// said), in a thread from then.
const SPENT_NOTICE = () => `⚠️ ${t("station.notice.rateLimit")}`;
const SPENT_BEFORE = ["⚠️ 已达到额度或速率限制", "⚠️ Hit a usage or rate limit"];

/// That the provider had no room for it: its words, about no account, are of no use to people.
const OVERLOADED_NOTICE = () => `⚠️ ${t("station.notice.overloaded")}`;

/// Codex relays the provider's exact refusal inside its error message, sometimes wrapped in a JSON response.
const codexTooOld = (message: string) => /\bmodel requires a newer version of Codex\.\s*Please upgrade to the latest app or CLI and try again\./i.test(message);

/// A failed turn as its chat is told it: what it means and what to do, by its reason, on its first line (what a
/// notice shows closed, and a push says); what the runtime said after it, as it said it (`withSaid`). A reason the
/// station cannot put in words of its own (the model's, any other) has the runtime's first line in it: "模型服务出错"
/// alone told people nothing (2026-11-05). A model's own limit names the model: "额度已用完" beside quota bars with room
/// left read as a mistake (#4365).
function failureNotice(outcome: TurnOutcome): string {
  if (outcome.kind !== "failed") return "";
  const model = outcome.reason === "rate_limit" ? modelLimitOf(outcome.message) : null;
  if (model !== null) return `⚠️ ${withSaid(t("station.notice.modelLimit", { model }), outcome.message)}`;
  const key = outcome.reason === "rate_limit" ? "rateLimit" : outcome.reason === "other" ? "failed" : outcome.reason;
  const why = outcome.reason === "model" || outcome.reason === "other" ? firstLine(outcome.message) : "";
  return `⚠️ ${withSaid(why === "" ? t(`station.notice.${key}`) : t(`station.notice.${key}Why`, { why }), outcome.message)}`;
}

/// The first line of what failed said, short enough for a notice's line and a push.
function firstLine(said: string): string {
  const line = said.trim().split("\n")[0]!.trim();
  return line.length > FIRST_LINE ? `${line.slice(0, FIRST_LINE - 1).trimEnd()}…` : line;
}
const FIRST_LINE = 200;

/// `words`, and under them what failed said itself (a provider's, a process's, in its own words), as a code block: a
/// notice opened shows it, for whoever wants to see the error as it was (2026-11-03).
function withSaid(words: string, said: string): string {
  const raw = said.trim().replace(/```/g, "ʼʼʼ");
  return raw === "" ? words : `${words}\n\n\`\`\`\n${raw}\n\`\`\``;
}

/// A failure's reason in a few words, after what failed ("Couldn't compact the context: …").
const failureWords = (reason: FailureReason) => t(`station.failure.${reason === "rate_limit" ? "rateLimit" : reason}`);

/// Why its agent could not start, as its chat is told it: the station's own words as they are (`Said`); else what the
/// error means where that is the account, the provider or the network, and otherwise only that it could not.
function cannotStartWords(error: unknown): string {
  if (error instanceof Said) return t("station.notice.cannotStartWhy", { why: error.message });
  const reason = failureOf((error as Error)?.message ?? "");
  const words = reason === "auth" || reason === "refused" || reason === "blocked" || reason === "network" ? t("station.notice.cannotStartWhy", { why: failureWords(reason) }) : t("station.notice.cannotStart");
  return withSaid(words, (error as Error)?.message ?? "");
}

/// Compaction that could not begin, in words: the station's own as they are, else what kind of failure it was.
function compactFailed(error: unknown): string {
  if (error instanceof Said) return t("station.notice.compactFailed", { why: error.message });
  log.warn("session", "compaction could not begin", { error: (error as Error)?.message ?? String(error) });
  return t("station.notice.compactFailed", { why: failureWords(failureOf((error as Error)?.message ?? "")) });
}

/// Who wrote a message, as a creator reference: their email on the page, their Slack user through the connect it came by.
const personRef = (m: any) => (m.surface === STILLFAIL_SURFACE ? m.message.author : `slack:${m.connect}:${m.message.author}`);
