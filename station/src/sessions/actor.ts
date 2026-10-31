// One actor per session (the Rust station's session.rs): every change to a session's state runs through its serial queue, so
// runtime events, deliveries and tool calls never interleave halfway. Redesigned on two points (docs/station-ts.md):
// - Where it stands is one value (`phase`): idle, starting, running, waiting, or closed; not three flags kept apart.
// - What tools say of the running turn (its state, need, about, what it waits for) goes through the queue too, and the
//   tool answers once it is recorded: a turn's end comes after the tool's answer, so nothing a tool said is lost.
// Its process is a runner's (src/agents/runner.ts): this actor can go (a station stopping or handing over) and the
// next take it up (`snapshot` / `adopt`), its turn going on all along.
import { join } from "node:path";
import { Clock, Effect, Exit, FiberSet, Scope, Semaphore } from "effect";
import type { AgentDriver, AgentSession, BackgroundTask, LiveEvent, OpenOptions, Profile, RuntimeEvent, TurnOutcome } from "../agents/runtime.ts";
import { GO_ON_AFTER_AUTH, GO_ON_AFTER_LOST, GO_ON_AFTER_OVERLOADED, GO_ON_AFTER_REFILL, GO_ON_AFTER_SPENT, NUDGE, RESUME_AFTER_RESTART, TOOLS_LOST, afresh as afreshNote, backgroundStopped, cleared, continuedHere, formatInbound, formatWidgetModels, resumeLost, sessionInstructions, waitOver } from "../agents/instructions.ts";
import { CONNECTION_LOST } from "../agents/sandbox.ts";
import { chars } from "../agents/live.ts";
import { CommandMissing } from "../agents/runner.ts";
import { latest as latestNote, untold } from "../agents/migrations.ts";
import { unreadableDir, unreadableDirMessage } from "../ops/files.ts";
import { Places } from "../ops/places.ts";
import { log } from "../ops/log.ts";
import { tr, stationLang } from "../ops/i18n.ts";
import { runtimeKind, runtimeLabel, type RuntimeKind } from "../agents/runtime.ts";
import { type Handed, handedOf } from "../store/rows.ts";

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

/// How long it waits before trying again a turn the provider had no room for, the `n`th in a row (from 0): twice as long
/// each time, ten minutes at most.
export const retryAfter = (n: number) => Math.min(30 * 2 ** n, 600);

export type TurnFor = { profile: string | null; person: string | null; thread: number | null };
const nobody: TurnFor = { profile: null, person: null, thread: null };

/// A chat thread the running turn works for, with the message that brought it in: it is told what the turn does.
type Working = { connect: string; channel: string; threadTs: string; ts: string | null };

/// What the actor needs of the store: the Rust Store's methods, camelCase (src/store/store.ts).
export type SessionStore = {
  pendingMessages(key: string): any[];
  markDelivered(key: string, handed: Handed[]): void;
  markUndelivered(key: string, handed: Handed[]): void;
  untoldWidgetModels(key: string): any[];
  markWidgetModelsTold(key: string, pairs: [string, string][]): void;
  heardThreads(key: string): Set<number> | number[];
  threadSessions(thread: number): { session: string; connect: string }[];
  getSession(key: string): any | null;
  hasTurns(key: string): boolean;
  toldNotes(key: string): number | null;
  setToldNotes(key: string, n: number): void;
  startTurnFor(id: string, key: string, kind: string, by: TurnFor): void;
  endTurn(id: string, outcome: string, detail: string | null, declared: string | null, wait: number | null): void;
  declareTurn(id: string, declared: string, wait: number | null): void;
  setRunning(key: string, running: boolean): void;
  setRuntimeSessionId(key: string, id: string | null): void;
  /// The runtime sessions it ran in, the first first (optional: none known without it).
  runtimeSessions?(key: string): string[];
  setWaitFor(turn: string, what: string, watch: boolean): void;
  setNeed(turn: string, what: string): void;
  setAbout(turn: string, about: [number, number, string] | null): void;
  lastTurn(key: string): any | null;
  stopWait(key: string): void;
  forgetWait(key: string): void;
  listJobs(session: string | null): any[];
  latestThread(key: string): any | null;
  entriesBefore(thread: number, n: number | null, limit: number): any[];
  insertMessage(message: any): unknown;
  notify(key: string): void;
};

/// A chat surface, as far as a session uses one (chat/mod.rs `ChatSurface`).
export type Surface = {
  post(thread: { channel: string; threadTs: string }, text: string, files: unknown[]): Promise<string>;
  userName?(user: string): Promise<string | null>;
  working?(thread: { channel: string; threadTs: string }, messageTs: string | null, status: string, page?: string | null): void;
  standsAt?(thread: { channel: string; threadTs: string }, stands: { kind: "done" | "need"; words: string | null } | null): void;
  mention?(user: string): string;
  botName?(): string;
  botUserId?(): string;
};

/// What a session needs of the station; the hub gives it.
export type SessionDeps = {
  store: SessionStore;
  chat(connect: string): Surface | undefined;
  driver(runtime: RuntimeKind): AgentDriver;
  /// The profile a session's runtime starts on now: its own while usable, else another that can take it on (`holding`:
  /// its process has work going in the background, kept on an account nearly full).
  runOn(key: string, holding?: boolean): Profile & { spelling?(model: string): string | null };
  /// A turn ran into the allowance of `ranOn`, the profile its process was started on (null: the session's own): the
  /// profile left and the one moved to, when it moved.
  spend(key: string, ranOn: string | null): [string, string] | null;
  /// When session `key`'s profile, its allowance run out, is expected to run again (absent: in an hour).
  refillsAt?(key: string): number;
  /// A runtime failed to sign in on `profile`: it is checked again (the pool passes over one whose login is over).
  recheck?(profile: string): Promise<void>;
  mcpUrl(): string;
  /// Before input is handed to the agent: what the station put in the session's workspace since (its uploads, its
  /// instructions) copied to the agent's sandbox, when it runs in one (agents/sandbox.ts).
  toSandbox?(key: string): Promise<void>;
  reposDir(): string;
  /// Session `key`'s MEMORY.md: its workspace's (agent-home.ts `workspaceAgentHome`).
  memoryPath(key: string): string;
  maxNudges(): number;
  backgroundOnMessage(key: string): boolean;
  /// Where the runtime's live steps go, for whoever watches the session (and that it went on in a new runtime session).
  live?: { event(key: string, event: LiveEvent): void; turnEnded(key: string): void; moved?(key: string): void };
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
  /// Its subagents `ids` of runtime session `from`, stopped with its process, taken to runtime session `to` begun on
  /// `on`, so that they are taken up there (sessions/afresh.ts): the ids taken.
  carrySubagents?(from: string, to: string, on: Profile, ids: string[]): string[];
  /// The runtime session it runs in, on `profile` (null: not known).
  ranIn?(key: string, id: string, profile: string | null): void;
  idle(key: string): void;
  archiveIsCold(key: string): boolean;
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
  nextTs(): string;
  /// Its time (the hub's).
  clock: Clock.Clock;
};

/// `lostRetried`: started again once already after the connection to its sandbox was lost (agents/sandbox.ts).
type Turn = { id: string; declared: DeclaredState | null; authRetried: boolean; lostRetried?: boolean; by: TurnFor };

/// Where a session stands: no runtime session; one starting up; a turn running; the agent waiting on work it started;
/// or the actor closed (its station stopping or handing over).
type Phase = "idle" | "running" | "waiting" | "closed";

/// What a next station takes up from this one (session.rs `HandedSession`, without the process: the runner keeps it).
export type Snapshot = {
  key: string;
  runtime: RuntimeKind;
  agent: unknown | null;
  turn: { id: string; authRetried: boolean; lostRetried?: boolean; by: TurnFor; declared: string | null; wait: number | null } | null;
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
  readonly runtime: RuntimeKind;
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
  /// Its context cleared to go on afresh (`clear`'s `readBack`): its next runtime session told to read back its work.
  private readBack = false;
  private generation = 0;
  private phase: Phase = "idle";
  private turn: Turn | null = null;
  private nudges = 0;
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
  private queued = 0;

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
      await this.deps.cleanArchive?.(this.key);
    });
  }

  // ── what the hub asks ────────────────────────────────────────────────────────────────────────────────────────

  /// running: a turn is in progress; warm: a runtime process waits for input; cold: none.
  processState(): "running" | "warm" | "cold" {
    if (this.turn || this.agent?.session.busy()) return "running";
    return this.agent ? "warm" : "cold";
  }

  /// How long the runtime process has sat idle, or null if there is none or it is working.
  idleMs(now: number): number | null {
    return this.agent && !this.agent.session.busy() && !this.turn && this.waiting === null ? now - this.idleSince : null;
  }

  holdsState(): boolean {
    return this.notices.length > 0 || this.waiting !== null || this.refill !== null;
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
      if (!this.turn && !this.agent?.session.busy()) await this.letGo();
    });
  }

  /// It posted in a chat (chat_post), in turn order.
  postedNow(): Promise<void> {
    return this.enqueue(async () => {
      this.posted = true;
    });
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
    return this.enqueue(async () => {
      if (this.agent?.session.busy()) {
        this.stopRequested = true;
        await this.agent.session.abort();
        return;
      }
      if (this.turn) return;
      await this.stopWaiting();
      // Nothing runs: whatever is still said to be under way (a start that failed) is not.
      this.deps.live?.turnEnded(this.key);
    });
  }

  /// Its last turn stopped at its account's allowance, or waits to be tried again after the provider had no room for it,
  /// and it was changed since: it goes on where it stopped.
  goOn(): Promise<void> {
    return this.enqueue(async () => {
      if (this.deps.held(this.key) || this.archived() || this.turn || this.agent?.session.busy()) return;
      this.refill = null;
      if (this.deps.store.pendingMessages(this.key).length > 0) return this.pump();
      const last = this.deps.store.lastTurn(this.key);
      await this.startTurn("resume", last && retrying(last) ? GO_ON_AFTER_OVERLOADED : GO_ON_AFTER_SPENT);
    });
  }

  /// After a station stopped with this session's turn running and no runner kept it: the turn was cut off; resume it.
  recover(): Promise<void> {
    return this.enqueue(async () => {
      const store = this.deps.store;
      store.setRunning(this.key, false);
      if (this.archived()) return this.letGo();
      const pending = store.pendingMessages(this.key);
      const [said, widgets] = await this.format(pending);
      await this.startTurn("resume", said === "" ? RESUME_AFTER_RESTART : `${RESUME_AFTER_RESTART}\n\n${said}`);
      this.delivered(pending, widgets);
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

  /// Turns were held and are no longer: what waited meanwhile goes on.
  release(): Promise<void> {
    return this.enqueue(async () => {
      if (this.waiting !== null && this.waitingUntil <= this.now()) this.waitMs(this.waitingSeconds, 0);
      await this.pump();
      if (this.notices.length > 0) await this.giveNotices();
    });
  }

  /// Starts the runtime process ahead of a message, so its start-up overlaps the typing.
  warm(): Promise<void> {
    return this.enqueue(async () => {
      if (this.agent || this.deps.held(this.key)) return;
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
      // Work it has going in the background would end with it.
      if (!agent || agent.session.busy() || this.turn || this.waiting !== null || this.holding()) return;
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

  private async beginCompacting(): Promise<string | null> {
    if (this.turn || this.compacting || this.agent?.session.busy()) return t("station.context.busy");
    if (this.deps.held(this.key)) return t("station.context.held");
    const row = this.deps.store.getSession(this.key);
    if (!row?.runtimeSessionId) return t("station.context.empty");
    let agent: AgentSession;
    try {
      agent = await this.ensureAgent();
    } catch (error) {
      return t("station.notice.compactFailed", { error: (error as Error).message });
    }
    // Gone on in a new runtime session (another account's): nothing in it to compact yet.
    if (this.afresh !== null) return t("station.context.empty");
    if (!agent.compact) return t("station.context.cannotCompact", { name: runtimeLabel(this.runtime) });
    log.info("session", "compacting its context, asked by hand", { session: this.key });
    this.compacting = true;
    this.deps.store.setRunning(this.key, true);
    this.deps.store.notify(this.key);
    try {
      await agent.compact();
    } catch (error) {
      this.compacting = false;
      this.deps.store.setRunning(this.key, false);
      this.deps.store.notify(this.key);
      return t("station.notice.compactFailed", { error: (error as Error).message });
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
    store.notify(this.key);
    log.info("session", "compaction by hand ended", { session: this.key, outcome: outcome.kind });
    if (outcome.kind === "completed") await this.notice(t("station.notice.compacted"));
    else if (outcome.kind === "failed") await this.notice(`⚠️ ${t("station.notice.compactFailed", { error: outcome.message })}`, outcome.reason === "auth" || outcome.reason === "refused" ? this.profile : null);
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
    if (store.pendingMessages(this.key).length > 0) return this.pump();
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

  /// Clears it (`clear`), saying `said` in its chat; `by`: who asked, for the log.
  private async clearNow(readBack: boolean, said = readBack ? "station.notice.afresh" : "station.notice.cleared", by = "by hand"): Promise<string | null> {
    if (this.turn || this.compacting || this.agent?.session.busy()) return t("station.context.busy");
    const store = this.deps.store;
    const row = store.getSession(this.key);
    if (!row?.runtimeSessionId) return t("station.context.empty");
    await this.stopWaiting(false);
    const agent = this.agent;
    this.agent = null;
    log.info("session", `clearing its context, asked ${by}`, { session: this.key, left: row.runtimeSessionId, readBack, background: agent?.session.background?.().length ?? 0 });
    await agent?.session.dispose();
    // Nothing of the conversation left is carried to the next.
    this.stopped = [];
    this.stoppedNote = null;
    this.resumeLost = false;
    this.afresh = null;
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
    return this.enqueue(async () => {
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
      if (!agent && !turn) return;
      const store = this.deps.store;
      const resume = (turn !== null || busy) && !(turn?.declared && settled(turn.declared));
      log.info("session", "ending the runtime process: the station is in no workspace", { session: this.key, resume });
      await agent?.session.dispose();
      if (turn) store.endTurn(turn.id, "aborted", "other: the station left its workspace", endedIn(turn.declared, "aborted")?.kind ?? null, null);
      store.setRunning(this.key, resume);
      if (turn || busy) store.markUndelivered(this.key, steered);
      this.deps.live?.turnEnded(this.key);
      store.notify(this.key);
      this.phase = "idle";
    });
  }

  /// Where the session stands, for the next station; from here on this actor does nothing more. Its runtime session is
  /// let go of (the runner keeps the process), not ended.
  snapshot(): Snapshot {
    const agent = this.agent?.session ?? null;
    const snap: Snapshot = {
      key: this.key,
      runtime: this.runtime,
      agent: agent?.snapshot() ?? null,
      turn: this.turn && {
        id: this.turn.id,
        authRetried: this.turn.authRetried,
        lostRetried: this.turn.lostRetried === true,
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
    this.agent = agent ? { generation: this.generation, session: agent } : null;
    this.profile = agent ? profile : null;
    this.turn = snap.turn && {
      id: snap.turn.id,
      authRetried: snap.turn.authRetried,
      lostRetried: snap.turn.lostRetried === true,
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
    this.stale = snap.stale ?? false;
    this.restart = snap.restart ?? false;
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
    Effect.runFork(Scope.close(this.scope, Exit.void));
  }

  /// Ends the runtime process too (the session is deleted, or the station stops for good).
  async dispose() {
    const agent = this.agent;
    this.agent = null;
    this.close();
    await agent?.session.dispose();
  }

  // ── inside the queue ─────────────────────────────────────────────────────────────────────────────────────────

  /// The notices waiting, as the agent reads them: each a message from the station (via="ember", as before the rename).
  private takeNotices(): string | null {
    const notices = this.notices;
    this.notices = [];
    if (notices.length === 0) return null;
    const at = this.deps.nextTs();
    return notices.map((n) => `<message via="ember" from="ember" ts="${at}">\n${n}\n</message>`).join("\n");
  }

  private async giveNotices() {
    if (this.deps.held(this.key) || this.compacting) return;
    if (this.archived()) {
      this.notices = [];
      return;
    }
    // Its account spent: a turn for them would run into it again; they wait for the refill.
    if (this.refill !== null && !this.agent?.session.busy()) return;
    if (this.agent?.session.busy()) {
      const text = this.takeNotices();
      if (text === null) return;
      // Not now: after the running turn.
      if (!(await this.agent.session.steer(text))) this.notices.unshift(text);
      return;
    }
    const text = this.takeNotices();
    if (text !== null) await this.startTurn("job", text);
  }

  private async pump() {
    if (this.deps.held(this.key) || this.archived() || this.compacting) return; // they stay pending
    const store = this.deps.store;
    const pending = store.pendingMessages(this.key);
    if (pending.length === 0) return;
    const [text, widgets] = await this.format(pending);
    const agent = this.agent?.session;
    if (agent?.busy()) {
      // So it is read now, not when a long command ends; what it waited on goes on.
      if (this.deps.backgroundOnMessage(this.key)) await agent.backgroundTools();
      if (await agent.steer(text)) {
        this.workFor(pending);
        this.delivered(pending, widgets);
        this.steered.push(...pending.map(handedOf));
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
    for (const m of messages.filter((m) => m.surface !== "ember")) {
      const at = this.workingFor.find((w) => w.connect === m.connect && w.channel === m.channel && w.threadTs === m.threadTs);
      if (at) at.ts = m.message.ts;
      else this.workingFor.push({ connect: m.connect, channel: m.channel, threadTs: m.threadTs, ts: m.message.ts });
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

  /// The messages as the agent reads them, made now so edits count (session.rs `format`).
  private async format(said: any[]): Promise<[string, [string, string][]]> {
    const store = this.deps.store;
    const heard = new Set(store.heardThreads(this.key));
    const newThreads = new Set<number>(said.map((m) => m.message.thread).filter((t: number) => !heard.has(t)));
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
    const text = formatInbound(said, newThreads, names, selves);
    const models = store.untoldWidgetModels(this.key);
    const widgets = models.map((w: any): [string, string] => [w.path, w.model]);
    const told = formatWidgetModels(models);
    return [told === "" ? text : text === "" ? told : `${text}\n\n${told}`, widgets];
  }

  /// What another agent goes by in a thread: the bot of the connect it posts there through, with its mention; in the
  /// station's own chats, its runtime and model.
  private agentName(key: string, thread: number): string {
    const via = this.deps.store.threadSessions(thread).find((m) => m.session === key)?.connect;
    const chat = via && via !== "ember" ? this.deps.chat(via) : undefined;
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
      // sent again (a wait of its own ends with it). Not while it has work going in the background (which would end
      // with its process).
      if ((kind === "input" || kind === "job") && !this.holding() && !this.agent?.session.busy() && this.deps.coldAfresh?.(this.key, this.now()) === true) {
        await this.clearNow(true, "station.notice.afreshCold", "as its cache is over");
      }
      let agent = await this.ensureAgent();
      const row = store.getSession(this.key);
      // A session begun in a terminal and continued here: its first turn here says so, with how still.fail works.
      const continued = row && row.cwd && !store.hasTurns(this.key) ? continuedHere(sessionInstructions(row.workspace, row.cwd, this.deps.reposDir(), this.deps.memoryPath(this.key))) : null;
      const lost = this.resumeLost;
      this.resumeLost = false;
      let prompt = lost ? `${this.deps.resumeLost?.(this.key) ?? resumeLost(this.key, [])}\n\n${text}` : text;
      const stopped = this.stoppedNote;
      this.stoppedNote = null;
      if (stopped !== null) prompt = `${stopped}\n\n${prompt}`;
      const afresh = this.afresh;
      this.afresh = null;
      if (afresh !== null) prompt = `${afresh}\n\n${prompt}`;
      if (continued !== null) prompt = `${continued}\n\n${prompt}`;
      // What changed in how it works since it was last told (migrations): once, before what it is handed.
      const told = store.toldNotes(this.key) ?? latestNote();
      if (told < latestNote()) {
        const full = row ? join(row.workspace, ".stillfail-instructions.md") : "";
        if (row) {
          const { writeFileSync } = await import("node:fs");
          try {
            writeFileSync(full, sessionInstructions(row.workspace, row.cwd ?? null, this.deps.reposDir(), this.deps.memoryPath(this.key)));
          } catch {}
        }
        store.setToldNotes(this.key, latestNote());
        prompt = `${untold(told, full)}\n\n${prompt}`;
      }
      await this.deps.toSandbox?.(this.key).catch((error) => log.warn("session", "files not copied to its sandbox", { session: this.key, error: (error as Error).message }));
      // The runtime may have started a turn on its own (late input became a turn); join it.
      if (agent.busy() && (await agent.steer(prompt))) return;
      this.steered = [];
      this.steeredFor = [];
      this.beginTurn(kind, by);
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
    } catch (error) {
      const message = (error as Error).message;
      const turn = this.turn;
      this.turn = null;
      this.phase = "idle";
      if (turn) store.endTurn(turn.id, "failed", `other: ${message}`, null, null);
      store.setRunning(this.key, false);
      // It was said to be starting: no turn runs.
      this.deps.live?.turnEnded(this.key);
      this.doneWorking();
      // Not installed here: said so, about the runtime (the pages offer to install it; once installed, what waits goes
      // on). Tried again (each restart gives it what waits) and failing the same, it is not said again.
      const missing = error instanceof CommandMissing && error.command === this.runtime;
      if (missing) this.deps.runtimeMissing?.(this.runtime);
      const said = missing ? `⚠️ ${t("station.notice.runtimeMissing", { name: runtimeLabel(this.runtime) })}` : `⚠️ ${t("station.notice.cannotStart", { error: message })}`;
      if (!this.saidLast(said)) await this.notice(said, null, missing ? this.runtime : null);
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
    this.turn = { id, declared: null, authRetried: kind === "auth_retry", lostRetried: kind === "sandbox_retry", by };
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
    if (!this.restart && row && profile && profile.id === this.profile && agent.session.retune?.(openOptions(row, profile, this.deps))) {
      this.stale = false;
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
    if (this.deps.archiveIsCold(this.key)) await this.deps.restoreArchive(this.key);
    const store = this.deps.store;
    const row = store.getSession(this.key);
    if (!row) throw new Error(`session ${this.key} disappeared`);
    const driver = this.deps.driver(this.runtime);
    const profile = this.deps.runOn(this.key);
    const base = openOptions(row, profile, this.deps);
    // Its context cleared by hand (clear): no runtime session now, those before on record. A new one, told so; one
    // continued from a terminal is given still.fail's instructions as a new session is (no cache of its own to keep).
    const wasCleared = row.runtimeSessionId === null && (store.runtimeSessions?.(this.key).length ?? 0) > 0;
    if (wasCleared && row.cwd) base.instructions = sessionInstructions(row.workspace, row.cwd, this.deps.reposDir(), this.deps.memoryPath(this.key));
    // A runtime started where the station may not read exits at once with nothing to say why (macOS privacy protection
    // on a session continued in ~/Documents): told as it is instead. A directory someone named (one continued from a
    // terminal) is looked at as ops/places.ts does, never on this thread in a folder macOS protects (still.fail Helper
    // asked for it, its window put up for a grant it lacks); the session's own workspace is the station's.
    if (row.cwd) await (this.deps.places ?? defaultPlaces()).directory(row.cwd, { lang: stationLang() });
    else if (unreadableDir(base.cwd)) throw new Error(unreadableDirMessage(stationLang(), base.cwd));
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
      resumable = this.deps.carrySubagents?.(row.runtimeSessionId!, agent.id(), profile, subagents) ?? [];
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
            this.workingFor = this.steeredFor;
            this.steeredFor = [];
            this.say(t("station.status.thinking"));
          }
        });
        break;
      case "turnEnded":
        this.deps.live?.turnEnded(this.key);
        this.doneWorking();
        void this.enqueue(() => this.onTurnEnded(generation, event.outcome));
        break;
      case "live":
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
      case "closed":
        void this.enqueue(async () => {
          if (!this.isCurrent(generation)) return;
          log.info("session", "session runtime closed", { session: this.key, reason: event.why });
          if (this.compacting) {
            this.compacting = false;
            this.deps.store.setRunning(this.key, false);
          }
          // What it had going in the background is gone with it.
          this.stopped.push(...(this.agent?.session.background?.() ?? []));
          this.agent = null;
          this.deps.store.notify(this.key);
        });
        break;
    }
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
    // Reopen Claude once so it reads the current credentials (and refreshes an expiring machine token). Resume its
    // transcript with a continuation, never replay the original request: it may already have run tools.
    if (this.runtime === "claude" && outcome.kind === "failed" && outcome.reason === "auth" && !stopRequested && !this.deps.held(this.key) && turn && !turn.authRetried && !turn.declared) {
      this.nudges = 0;
      const agent = this.agent;
      this.agent = null;
      await this.endProcess(agent);
      // Its account checked first: one whose login is over is left, and the turn goes on on another (`runOn`).
      if (this.profile !== null) await this.deps.recheck?.(this.profile);
      log.info("session", "Claude authentication failed; reopening and continuing once", { session: this.key });
      return this.startTurn("auth_retry", GO_ON_AFTER_AUTH, turn.by);
    }
    // Its process ran in a sandbox and the connection to it was lost (not the program ending): started again there once,
    // going on from its transcript as after an authentication error.
    if (outcome.kind === "failed" && outcome.reason === "exited" && outcome.message.includes(CONNECTION_LOST) && !stopRequested && !this.deps.held(this.key) && turn && !turn.lostRetried && !turn.declared) {
      this.nudges = 0;
      const agent = this.agent;
      this.agent = null;
      await this.endProcess(agent);
      log.info("session", "the connection to its sandbox was lost; starting again and continuing once", { session: this.key });
      return this.startTurn("sandbox_retry", GO_ON_AFTER_LOST, turn.by);
    }
    const spent = outcome.kind === "failed" && outcome.reason === "rate_limit";
    if (!spent) this.refill = null;
    if (spent) {
      this.nudges = 0;
      // Left to the station, it moves to another account and goes on there; otherwise it waits for a change.
      let moved: [string, string] | null = null;
      try {
        moved = this.deps.spend(this.key, this.profile);
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
        if (store.pendingMessages(this.key).length > 0) return this.pump();
        return this.startTurn("resume", GO_ON_AFTER_SPENT);
      }
      // Said once: what wakes it meanwhile (a job's notice, a wait over) would only run into it again.
      if (!this.saidLast((said) => said.startsWith(SPENT_NOTICE()))) await this.notice(failureNotice(outcome), this.profile);
      this.awaitRefill(this.deps.refillsAt?.(this.key) ?? this.now() + REFILL_FALLBACK_MS);
    } else if (overloaded) {
      this.nudges = 0;
      // Said once: tried again and turned away again, nothing new to tell.
      if (!this.saidLast(OVERLOADED_NOTICE())) await this.notice(OVERLOADED_NOTICE());
    } else if (outcome.kind === "failed") {
      this.nudges = 0;
      // A sign-in that failed is its profile's, as is a refused request (its environment is where a proxy goes): the
      // notice points there.
      await this.notice(failureNotice(outcome), outcome.reason === "auth" || outcome.reason === "refused" ? this.profile : null);
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
      // needs (failed and stopped have their notice there already; waiting says nothing)
      const stands = ended === "all_done" ? { kind: "done" as const, words } : ended === "need_human" ? { kind: "need" as const, words } : null;
      for (const w of this.endedFor) this.deps.chat(w.connect)?.standsAt?.({ channel: w.channel, threadTs: w.threadTs }, stands);
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
    if (store.pendingMessages(this.key).length > 0) return this.pump();
    if (this.notices.length > 0) return this.giveNotices();
    const declared = turn?.declared ?? null;
    if (ends?.kind === "waiting") {
      this.nudges = 0;
      this.wait(ends.seconds);
      this.deps.idle(this.key);
      return;
    }
    this.deps.idle(this.key);
    if (outcome.kind !== "completed" || declared) {
      this.nudges = 0;
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
      return this.giveUp();
    }
    if (this.nudges < this.deps.maxNudges()) {
      this.nudges++;
      log.info("session", "turn ended without a state; nudging", { session: this.key, attempt: this.nudges });
      return this.startTurn("nudge", NUDGE);
    }
    this.nudges = 0;
    await this.giveUp();
  }

  /// No turn ended in a state, and no more are asked for: the thread is told so, with the agent's last words when it
  /// posted none (it may have answered where nobody reads: its tools out of reach), marked as the station's.
  private async giveUp() {
    const said = this.posted ? "" : this.lastSaid;
    this.lastSaid = "";
    if (said === "") return this.notice(`⚠️ ${t("station.notice.noResult")}`);
    log.info("session", "the turn reached nobody; its last words are shown in its place", { session: this.key });
    const quoted = chars(said, FALLBACK_MOST).split("\n").map((line) => `> ${line}`).join("\n");
    await this.notice(`⚠️ ${t("station.notice.noResultSaid")}\n\n${quoted}`);
  }

  /// Stopped while it waits: the wait ends, and so does the work that would bring it back (session.rs `stop_waiting`).
  private async stopWaiting(say = true) {
    const store = this.deps.store;
    const waited = this.waiting !== null;
    this.waiting = null;
    if (this.phase === "waiting") this.phase = "idle";
    // Its wait may be on record only (an earlier station had it).
    const last = store.lastTurn(this.key);
    const recorded = last && last.endedAt !== null && last.declared === "waiting";
    if (!waited && !recorded) return;
    log.info("session", "stopped while waiting", { session: this.key });
    // A turn waiting to be tried again waits on no work of its own: its jobs go on. Asked again, it starts over.
    if (last && retrying(last)) this.overloads = 0;
    else await this.deps.stopJobs(this.key);
    this.nudges = 0;
    const agent = this.agent;
    this.agent = null;
    await agent?.session.dispose();
    store.stopWait(this.key);
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
              if (last?.waitWatch !== false && this.deps.store.listJobs(this.key).some((j) => j.watch && j.state === "running")) return this.wait(seconds);
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
    return last !== undefined && last.authorKind === "ember" && (typeof text === "string" ? last.text === text : text(last.text));
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
              this.refill = null;
              // Held, it goes on when released (its notices); a running turn ends as it will.
              if (this.deps.held(this.key) || this.archived() || this.turn || this.agent?.session.busy()) return;
              log.info("session", "its allowance should have refilled; going on", { session: this.key });
              if (this.deps.store.pendingMessages(this.key).length > 0) return this.pump();
              await this.startTurn("resume", GO_ON_AFTER_REFILL);
            }),
          ),
        ),
      ),
    ).catch(() => undefined);
  }

  /// The station's own words (not the agent's) go to the thread people spoke in last, and are recorded there; one about
  /// a profile (`profile`, its id) is linked to that profile's page, one about a runtime not installed (`runtime`)
  /// offers to install it.
  private async notice(text: string, profile: string | null = null, runtime: RuntimeKind | null = null) {
    const store = this.deps.store;
    const latest = store.latestThread(this.key);
    const chat = latest ? this.deps.chat(latest.connect) : undefined;
    if (!latest || !chat) {
      log.warn("session", "no thread to post a notice to", { session: this.key, text });
      return;
    }
    try {
      const ts = await chat.post({ channel: latest.thread.channel, threadTs: latest.thread.threadTs }, text, []);
      store.insertMessage({ thread: latest.thread.id, ts, authorKind: "ember", author: "ember", text, profile, runtime, attachments: [], quotes: [], declared: null, client: null, card: null, options: null, agentIdentity: null });
    } catch (error) {
      log.warn("session", "notice failed", { session: this.key, error: (error as Error).message });
    }
  }
}

/// How a session's runtime session is opened (or taken up) on `profile`: its directory, model as the profile spells it,
/// effort, instructions and MCP token.
export function openOptions(row: any, profile: Profile & { spelling?(model: string): string | null }, deps: Pick<SessionDeps, "mcpUrl" | "reposDir" | "memoryPath">): OpenOptions {
  // The model as this profile spells it (openai/gpt-6-astra on a router for gpt-6-astra).
  const model = row.model ? (profile.spelling?.(row.model) ?? row.model) : undefined;
  return {
    key: row.key,
    profile,
    cwd: row.cwd ?? row.workspace,
    model,
    effort: row.effort ?? undefined,
    // A session continued from a terminal keeps the system prompt it began with (its cache holds).
    instructions: row.cwd ? "" : sessionInstructions(row.workspace, null, deps.reposDir(), deps.memoryPath(row.key)),
    mcpToken: row.token,
    mcpUrl: deps.mcpUrl(),
    route: row.key,
  };
}

/// How long a spent account is waited on when it refills is not known.
const REFILL_FALLBACK_MS = 60 * 60 * 1000;

/// The start of the notice that its account is spent, whatever the runtime said.
const SPENT_NOTICE = () => `⚠️ ${t("station.notice.rateLimit", { error: "" })}`;

/// That the provider had no room for it: its words, about no account, are of no use to people.
const OVERLOADED_NOTICE = () => `⚠️ ${t("station.notice.overloaded")}`;

function failureNotice(outcome: TurnOutcome): string {
  if (outcome.kind !== "failed") return "";
  const key = outcome.reason === "auth" ? "auth" : outcome.reason === "refused" ? "refused" : outcome.reason === "rate_limit" ? "rateLimit" : outcome.reason === "exited" ? "exited" : "failed";
  return `⚠️ ${t(`station.notice.${key}`, { error: outcome.message })}`;
}

/// Who wrote a message, as a creator reference: their email on the page, their Slack user through the connect it came by.
const personRef = (m: any) => (m.surface === "ember" ? m.message.author : `slack:${m.connect}:${m.message.author}`);
