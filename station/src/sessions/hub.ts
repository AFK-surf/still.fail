// Routes chat messages to session actors and creates sessions (the Rust station's hub.rs). Several connects share one hub;
// each has its own chat connection and its own sessions.
//
// A connect's mode decides the sessions: multi-session gives each thread its own session (started by an @mention);
// single-session sends every thread the connect sees into the one session bound to it, which people can switch or
// replace. Either way every message carries its source and the agent names the thread it answers, so a session never
// assumes it belongs to one conversation; replies go out through whichever connect the thread came in on.
//
// Everything said in a thread is recorded once (the store): people's messages are delivered to every session in the
// thread, and what agents and the station post there is recorded after the platform takes it.
//
// The Rust hub is one 2500-line type; here it is this core (actors, routing, holds, handover, eviction) and modules
// beside it, each a group of what the hub does: accounts.ts (which profile), conversations.ts (what agents post and
// read in their chats), others.ts (other chats), messages.ts (session_send), titles.ts, lifecycle.ts (sessions and
// chats made, archived, deleted), review.ts (the archive suggestion). The tools (src/tools/) are built on it.
//
// Redesigned where docs/station-ts.md asks: no settle-by-polling and no handing over of processes: at a handover the
// hub holds turns, waits until every actor's queue has run what it had (`flushed`, pushed, not polled), and snapshots
// every actor into <data>/run/handover.json; the runners keep the processes. A starting hub takes them up from that
// file (`takeUp`), and from the runners a crashed station left (no snapshot), then `recover` resumes the turns marked
// running that nothing took up.
import { idleSandboxes, keyPart, sandboxIdleMs, sandboxName, sandboxed, sessionSync, stopSandbox, syncChanged } from "../agents/sandbox.ts";
import { randomBytes } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { Clock, Effect, Fiber } from "effect";
import { liveClock, within } from "../ops/fibers.ts";
import type { AgentDriver, AgentSession, RuntimeKind } from "../agents/runtime.ts";
import { runnerId } from "../agents/process.ts";
import { allLeft, existingRunners } from "../agents/runner.ts";
import { log } from "../ops/log.ts";
import { tr, stationLang } from "../ops/i18n.ts";
import { homesFirst, iso, sessionPlaces, transcriptPaths } from "../read/transcript.ts";
import { type Attachment, MANUAL, type SessionRow, type Store, STILLFAIL_SURFACE, feishuSurface, slackSurface, type MessageRow, type ThreadRow, type ThreadSummary } from "../store/store.ts";
import { Accounts } from "./accounts.ts";
import { SessionActor, type SessionDeps, type Snapshot, openOptions } from "./actor.ts";
import { Places } from "../ops/places.ts";
import { threadCommand } from "./args.ts";
import type { ChatEvent, ChatSurface, InboundFile, InboundMessage, ThreadRef } from "./chat.ts";
import { toolStatus } from "./chat.ts";
import { type Connect, type HubConfig, type Profile, allowedIn, profilesFor, runtimeNamed, runtimeTitle } from "./config.ts";
import { INTERNAL_CONNECT, type InternalChat, nextTsAt } from "./internal.ts";
import { LiveHub } from "./live.ts";
import type { Jobs } from "./neighbours.ts";
import { agentHomePaths, workspaceAgentHome } from "./agent-home.ts";
import { type Roots, roots as machineRoots } from "../read/machine.ts";
import { carrySubagents, goesAfresh, startsAfresh, toldCleared, toldResumeLost } from "./afresh.ts";
import { serves } from "./pool.ts";
import { settled } from "./opened.ts";
import { shownFacts } from "./image-size.ts";

type Json = any;

/// A multi-session connect's session for one thread.
export const sessionKey = (connect: string, channel: string, threadTs: string) => `${connect}:${channel}:${threadTs}`;

/// A new session for a single-session connect.
export const newSingleSessionKey = (connect: string) => `${connect}:s-${randomBytes(4).toString("hex")}`;

/// A new session talked to in the station's chat.
export const newChatKey = () => `${INTERNAL_CONNECT}:c-${randomBytes(5).toString("hex")}`;

/// The bearer token a session presents to the MCP endpoint.
export const newToken = () => randomBytes(24).toString("base64url");

/// Why turns are held. Each is taken back on its own: a station drained for a restart while in no workspace takes no
/// turns once the drain ends either.
/// - drain: a restart or handover is coming.
/// - unbound: the station is in no workspace (never joined one, or removed from it): it does no work until it is.
/// - starting: the agents' door (their MCP endpoint) is not open yet: a runtime started now has no station tools.
export type Hold = "drain" | "unbound" | "starting";

/// A chat of another workspace shared with this one, as chat_list lists it (xshare/index.ts `Borrowed`).
export type OutsideChat = { workspace: string; workspaceName: string; station: string; chat: string; title: string; link: string; write: boolean };

/// Cold storage of archived sessions' files (archive.rs, footprint.rs): an archived, idle session's workspace and
/// transcripts packed, and restored before its runtime starts again or when it is shown again. The station's is
/// cold.ts; the default keeps nothing cold.
export interface ColdStorage {
  isCold(key: string): boolean;
  restore(key: string): void | Promise<void>;
  /// Packs what it can of an archived, idle session.
  pack(key: string): void | Promise<void>;
  /// Whether an archived session's directory holds more than its chat's files, and empties it of that.
  holdsMore?(key: string): Promise<boolean>;
  expire?(key: string, before: number): Promise<void>;
}

/// The most of a shared file the station fetches, as much as an agent may attach.
const MAX_INBOUND_FILE = 50 * 1024 * 1024;

const NOTHING_COLD: ColdStorage = { isCold: () => false, restore: () => {}, pack: () => {} };

/// What the hub hands to the next station: each actor's snapshot (handover.json).
export type Handover = { sessions: Snapshot[] };

export type HubOptions = {
  /// Read on every use, so edits apply to the next decision.
  config: () => HubConfig;
  store: Store;
  /// The connected connects by id; configured connects without one are offline.
  chats: (connect: string) => ChatSurface | undefined;
  drivers: AgentDriver[];
  /// The agents' MCP endpoint (a function when it is known only once its server listens).
  mcpUrl: string | (() => string);
  /// The station's own chat on its pages; sessions can be talked to there too.
  internal?: InternalChat | null;
  /// How the directories and files people and agents name are looked at (ops/places.ts: never on this thread in a
  /// folder macOS protects); default: without still.fail Helper.
  places?: Places;
  /// A session's page in still.fail (its /o/ link), when the station is in a workspace.
  link?: (key: string) => string | undefined;
  /// The workspaces the station is in now, its home one first (docs/multi-workspace.md); none outside any.
  workspaces?: () => string[];
  /// The runners alive on this machine now, by id (default: <data>/run/runners).
  runners?: () => string[];
  cold?: ColdStorage;
  /// Its time, and its sessions' (a TestClock in tests).
  clock?: Clock.Clock;
  /// Where the machine's own Claude Code and Codex keep their sessions (default: read/machine.ts `roots`).
  machineRoots?: () => Roots;
};

/// The handover file, in the data directory.
export const handoverFile = (dataDir: string) => join(dataDir, "run", "handover.json");

export class Hub {
  readonly options: HubOptions;
  readonly store: Store;
  readonly internal: InternalChat | null;
  readonly drivers: Map<string, AgentDriver>;
  readonly link: (key: string) => string | undefined;
  readonly workspaces: () => string[];
  readonly cold: ColdStorage;
  readonly accounts: Accounts;
  readonly clock: Clock.Clock;
  readonly places: Places;
  readonly machineRoots: () => Roots;
  /// Told when a session's runtime was not found on PATH as it started (the pages read it again).
  private runtimeMissing: (runtime: RuntimeKind) => void = () => {};
  /// What running turns are doing, for the pages' live view.
  readonly live: LiveHub;
  /// Every thread as lists have it, read by the readers (agents.ts sets it): chat_list's, not read on the main thread
  /// (some 15 queries a thread, 1,200 threads on ccvm: 10 seconds held while memory was short). Unset (tests): the store.
  threadList: (() => Promise<ThreadSummary[]>) | null = null;
  /// A thread's latest `limit` messages, oldest first, read by the readers (agents.ts sets it): the archive review's
  /// (review.ts), up to 400 of them through the merged view, 3 seconds held on ccvm. Unset (tests): the store.
  latestMessages: ((thread: number, limit: number) => Promise<MessageRow[]>) | null = null;
  /// Stops following the store's sessions starting and stopping (live.ts `running`).
  private unlistenRunning: () => void = () => {};
  readonly actors = new Map<string, SessionActor>();
  /// When each idle process is next looked at for eviction.
  private deadlines = new Map<string, Fiber.Fiber<void>>();
  /// Fibers of the hub's own (title waits, archive reviews): interrupted at shutdown.
  readonly fibers = new Set<Fiber.Fiber<void>>();
  /// Why turns are held (SessionDeps.held): held while any reason stands.
  private holdsNow = new Set<Hold>();
  /// Sessions taken up from the previous station: their turns run on, not cut off.
  private adopted = new Set<string>();
  /// Chats made lately by session key: the key their client gave them, and when (NewChat.clientKey).
  readonly clientKeysMade = new Map<string, [string, number]>();
  /// Titles agents gave chats someone has open, waiting until they leave (titles.ts), by thread.
  readonly titles = new Map<number, string>();
  /// Conversations a chat was relayed to whose agent has not posted there yet, by thread: the session and the station's
  /// first message there, which that post goes into (relay.ts). Kept in memory: after a restart it is a reply.
  readonly openings = new Map<number, { session: string; ts: string }>();
  /// One message at a time per thread: Slack sends a mention twice (app_mention and message), and both would make its
  /// session.
  readonly gates = new Map<string, { tail: Promise<void>; waiting: number }>();
  /// The station's background jobs (made after the hub, which tells their agents).
  jobs: Jobs | null = null;
  private closedHook: ((key: string) => void) | null = null;
  private peersHook: ((station: string, request: Json) => Promise<Json>) | null = null;
  private outsideHook: ((ws: string | null) => OutsideChat[]) | null = null;
  readonly deps: SessionDeps;

  constructor(options: HubOptions) {
    this.options = options;
    this.clock = options.clock ?? liveClock;
    this.store = options.store;
    this.internal = options.internal ?? null;
    this.drivers = new Map(options.drivers.map((d) => [d.runtime(), d]));
    this.link = options.link ?? (() => undefined);
    this.workspaces = options.workspaces ?? (() => []);
    this.cold = options.cold ?? NOTHING_COLD;
    this.machineRoots = options.machineRoots ?? machineRoots;
    this.places = options.places ?? new Places();
    this.accounts = new Accounts({
      config: () => this.config(),
      store: this.store,
      running: (except) => [...this.actors.values()].filter((a) => a.key !== except && a.processState() !== "cold").flatMap((a) => this.store.getSession(a.key)?.profile ?? []),
      clock: this.clock,
      allows: (key, profile) => allowedIn(profile, this.wsOf(key), this.workspaces()[0] ?? null),
    });
    this.live = new LiveHub(
      (key) => {
        const row = this.store.getSession(key);
        const runtime = row && runtimeNamed(row.runtime);
        if (!row || !runtime || this.store.runtimeSessions(key).length === 0) return null;
        const { dataDir, profiles } = this.config();
        const { paths, current } = transcriptPaths(runtime, dataDir, homesFirst(profiles, row.profile), this.store.runtimeSessions(key), sessionPlaces(row));
        return paths.length === 0 ? null : { runtime, paths, current };
      },
      this.clock,
    );
    // The sessions at work are followed by the station itself (live.ts `running`): as the store says each starts and
    // stops, and those at work now. Each transcript's length goes where its summary reads it (its usage, the usage
    // part keeps: usage/module.ts).
    this.live.lengths = (key, n) => this.store.setTranscriptLength(key, n);
    this.unlistenRunning = this.store.subscribe((change) => {
      if (change.type === "session") this.live.running(change.key, this.store.getSession(change.key)?.running === true);
      else if (change.type === "sessionRemoved") this.live.running(change.key, false);
    });
    this.deps = this.sessionDeps();
  }

  /// The sessions at work as the station starts are followed (live.ts `running`): once where their history is read
  /// is set (agents.ts), so none is read on the main thread.
  followRunning() {
    for (const row of this.store.runningSessions()) this.live.running(row.key, true);
  }

  config(): HubConfig {
    return this.options.config();
  }

  /// Now, by its clock.
  now(): number {
    return this.clock.currentTimeMillisUnsafe();
  }

  /// A Slack-style ts for something said now.
  nextTs(): string {
    return nextTsAt(this.now());
  }

  reposDir(): string {
    return join(this.config().dataDir, "repos");
  }

  // ── holds ──────────────────────────────────────────────────────────────────────────────────────────────────────

  /// Holds turns for `reason`: none starts from now on, and messages stay pending. Those running go on.
  hold(reason: Hold) {
    this.holdsNow.add(reason);
  }

  /// Takes back `reason` to hold turns; once none is left, turns start again and what waited meanwhile goes on.
  release(reason: Hold) {
    if (!this.holdsNow.delete(reason) || this.holdsNow.size > 0) return;
    for (const actor of this.actors.values()) void actor.release();
    for (const key of this.store.sessionsWithPending()) {
      const row = this.store.getSession(key);
      if (row) void this.actor(row).kick();
    }
  }

  /// Whether turns are held for `reason`.
  holds(reason: Hold): boolean {
    return this.holdsNow.has(reason);
  }

  /// The station left its workspace (turns are held first): every runtime process ends, running or idle, then what the
  /// drivers run themselves (codex's app-servers), so no agent goes on outside the workspace. Turns cut off stay marked
  /// running and messages given to them pending again (SessionActor.suspend): `recover` resumes them once the station
  /// is back in its workspace.
  async suspendAll() {
    for (const fiber of this.deadlines.values()) this.interrupt(fiber);
    this.deadlines.clear();
    // Taken up from the previous station or not, what was cut off now resumes the usual way.
    this.adopted.clear();
    await Promise.all([...this.actors.values()].map((a) => a.suspend()));
    await Promise.all([...this.drivers.values()].map((d) => d.shutdown()));
  }

  /// Whether a session's workspace is one the station is in now (a joined one may have taken it out): held otherwise.
  /// Outside every workspace the "unbound" hold says so instead.
  private inAWorkspace(key: string): boolean {
    const all = this.workspaces();
    if (all.length === 0) return true;
    const ws = this.store.getSession(key)?.ws ?? null;
    return ws === null || all.includes(ws);
  }

  /// The station left one of its workspaces but is still in others (docs/multi-workspace.md): that workspace's
  /// sessions end their processes as `suspendAll` ends everyone's; `backIn` resumes them once it is back.
  async leftWorkspace(ws: string) {
    const keys = new Set(this.store.listSessions().filter((s) => s.ws === ws).map((s) => s.key));
    for (const [key, fiber] of this.deadlines) if (keys.has(key)) (this.interrupt(fiber), this.deadlines.delete(key));
    await Promise.all([...this.actors.values()].filter((a) => keys.has(a.key)).map((a) => a.suspend()));
  }

  /// The station is in a workspace again: its sessions' cut-off turns resume, and what waited goes on.
  backIn(ws: string) {
    for (const row of this.store.listSessions().filter((s) => s.ws === ws)) {
      if (row.running && this.online(row)) void this.actor(row).recover();
      else if (this.store.sessionsWithPending().includes(row.key) && this.online(row)) void this.actor(row).kick();
    }
  }

  /// How many turns are running.
  running(): number {
    return [...this.actors.values()].filter((a) => a.processState() === "running").length;
  }

  anyRunning(): boolean {
    return this.running() > 0;
  }

  // ── handover ───────────────────────────────────────────────────────────────────────────────────────────────────

  /// Hands the sessions to the next station: turns held, every queue run out, each actor's snapshot written to
  /// <data>/run/handover.json, and the drivers let go of their processes (the runners keep them). Until the snapshot
  /// is taken it can fail (the queues did not settle within `limitMs`) and turns are released again; after, this hub
  /// does nothing more.
  async handOver(limitMs = 30_000): Promise<Handover> {
    this.hold("drain");
    try {
      await this.settled(limitMs);
    } catch (error) {
      this.release("drain");
      throw error;
    }
    // Settled: snapshotted at once, before anything else is taken in.
    const sessions: Snapshot[] = [];
    for (const actor of this.actors.values()) {
      if (actor.processState() !== "cold" || actor.holdsState()) sessions.push(actor.snapshot());
      else actor.close();
    }
    for (const driver of this.drivers.values()) driver.detach();
    // The next station attaches to their runners once this file is there: every ack is in by then.
    await allLeft();
    this.stopTimers();
    const handed: Handover = { sessions };
    const file = handoverFile(this.config().dataDir);
    mkdirSync(join(file, ".."), { recursive: true });
    writeFileSync(file, JSON.stringify(handed));
    log.info("hub", "handed over", { sessions: sessions.length });
    return handed;
  }

  /// Resolves once no actor has a task queued or running: each queue is run out, and again while new tasks came
  /// meanwhile (a runtime's events). Fails after `limitMs`.
  private async settled(limitMs: number) {
    const runOut = async () => {
      for (;;) {
        await Promise.all([...this.actors.values()].map((a) => a.flushed()));
        if ([...this.actors.values()].every((a) => a.settled())) return;
      }
    };
    await within(this.clock, limitMs, runOut(), () => new Error(`sessions did not settle within ${Math.round(limitMs / 1000)} s`));
  }

  /// Takes up what the previous station left: the snapshots of its handover, then the runners it left without one (it
  /// crashed). Sessions taken up with their runtime run on; a turn marked running whose runtime is gone is `recover`'s.
  async takeUp() {
    const file = handoverFile(this.config().dataDir);
    let handed: Handover = { sessions: [] };
    if (existsSync(file)) {
      try {
        handed = JSON.parse(readFileSync(file, "utf8"));
      } catch (error) {
        log.warn("hub", "the handover file does not read; sessions resume the usual way", { error: (error as Error).message });
      }
      rmSync(file, { force: true });
    }
    await this.adopt(handed);
    // A crash left runners without a snapshot: what they keep is taken up as it stands.
    const runners = new Set(this.options.runners ? this.options.runners() : existingRunners(this.config().dataDir).map((r) => r.id));
    const taken = new Set(handed.sessions.map((s) => s.key));
    for (const row of this.store.listSessions()) {
      if (taken.has(row.key)) continue;
      const runtime = runtimeNamed(row.runtime);
      // Claude's and dsh's runner is the session's own (an idle one is taken up too); codex sessions share their
      // profile's host, which its driver finds, for a turn that was running.
      if (!runtime || (runtime !== "codex" ? !runners.has(runnerId(runtime, row.key)) : !row.running)) continue;
      const turn = row.running ? this.store.listTurns(row.key).at(-1) : undefined;
      const snap: Snapshot = {
        key: row.key,
        runtime,
        agent: null,
        turn: turn && turn.summary.endedAt === null ? { id: turn.id, authRetried: turn.summary.kind === "auth_retry", lostRetried: turn.summary.kind === "sandbox_retry", by: { profile: null, person: null, thread: null }, declared: turn.summary.declared, wait: turn.summary.waitSeconds } : null,
        workingFor: [],
        notices: [],
        waitingMs: null,
        waitingSeconds: 0,
        nudges: 0,
        stopRequested: false,
      };
      await this.adoptOne(row, snap, true);
    }
  }

  /// Takes up a handover's snapshots (sessions handed over by the previous station).
  async adopt(handed: Handover) {
    for (const snap of handed.sessions) {
      const row = this.store.getSession(snap.key);
      if (!row) {
        log.warn("hub", "session handed over is gone", { session: snap.key });
        continue;
      }
      await this.adoptOne(row, snap, snap.agent !== null);
    }
  }

  private async adoptOne(row: SessionRow, snap: Snapshot, withProcess: boolean) {
    let actor: SessionActor;
    try {
      actor = this.actor(row);
    } catch (error) {
      log.warn("hub", "session handed over could not be taken up; it resumes the usual way", { session: row.key, error: (error as Error).message });
      return;
    }
    // Its process runs on the profile it was started on (the one its runtime session last ran on), which the session may
    // have been moved off since: taken up there, not moved, it moves before its next turn (actor.ts `ensureAgent`).
    const ranOn = (row.runtimeSessionId ? this.store.ranOn(row.key, row.runtimeSessionId) : null) ?? row.profile;
    let agent: AgentSession | null = null;
    if (withProcess) {
      try {
        const driver = this.sessionDriver(snap.runtime);
        const generation = actor.nextGeneration();
        agent = await driver.adopt(openOptions(row, this.accounts.profile(ranOn) ?? this.accounts.runOn(row.key), this.deps), snap.agent, actor.listener(generation));
      } catch (error) {
        log.warn("hub", "a session's runtime could not be taken up; it resumes the usual way", { session: row.key, error: (error as Error).message });
      }
    }
    // Its runtime not taken up: a turn it had is resumed the usual way (recover).
    if (withProcess && !agent) return;
    actor.adopt(snap, agent, ranOn);
    log.info("hub", "session taken up from the previous station", { session: row.key, withAgent: agent !== null });
    if (agent) {
      this.adopted.add(row.key);
      if (!snap.turn) this.idleNow(row.key);
    }
    if (snap.notices.length > 0) void actor.release();
  }

  // ── messages in ────────────────────────────────────────────────────────────────────────────────────────────────

  /// Takes one event from a connect's platform. Resolves once it is durably recorded (or deliberately ignored).
  async receive(connectId: string, event: ChatEvent) {
    if (event.type === "message") return this.accept(connectId, event.message);
    this.store.editMessage(this.surface(connectId), event.channel, event.threadTs, event.ts, event.text);
  }

  /// Accepts one message seen by a connect, one at a time per thread. Resolves once it is durably recorded (or
  /// deliberately ignored).
  async accept(connectId: string, message: InboundMessage) {
    const at = `${this.surface(connectId)}\0${message.channel}\0${message.threadTs}`;
    let gate = this.gates.get(at);
    if (!gate) this.gates.set(at, (gate = { tail: Promise.resolve(), waiting: 0 }));
    gate.waiting++;
    const turn = gate.tail.then(() => this.acceptInTurn(connectId, message));
    gate.tail = turn.then(
      () => {},
      () => {},
    );
    try {
      return await turn;
    } finally {
      // No one waits on it any more.
      if (--gate.waiting === 0 && this.gates.get(at) === gate) this.gates.delete(at);
    }
  }

  private async acceptInTurn(connectId: string, message: InboundMessage) {
    const config = this.config();
    // What a bot of this station posted is its agent's, recorded and handed to the thread as it was posted: Slack's
    // copy of it, seen through another connect, is not a message of its own.
    if (this.ownBot(config, message.user)) return;
    const connect = connectOf(config, connectId);
    const chat = this.chat(connectId);
    const surface = this.surface(connectId);
    const single = connect.mode === "single-session";
    const bound = single ? this.store.binding(connect.id) : null;
    const key = bound ?? (single ? newSingleSessionKey(connect.id) : sessionKey(connect.id, message.channel, message.threadTs));
    const existing = this.store.threadAt(surface, message.channel, message.threadTs);
    const members = existing ? this.store.threadSessions(existing.id) : [];
    const exists = this.store.getSession(key) !== null;
    const wanted = single ? message.addressed || !connect.requireMention || (exists && members.some((m) => m.session === key)) : exists || message.addressed;
    // Chatter this connect is not part of, in a thread no session takes part in.
    if (!wanted && members.length === 0) return;
    const here: ThreadRef = { channel: message.channel, threadTs: message.threadTs };
    // Archived by hand: it takes no messages until someone shows it again; told so, once per message.
    if (existing && this.store.manuallyArchived(existing.id)) {
      if (this.store.messageAt(existing.id, message.ts) === null) {
        await chat.post(here, `⚠️ ${tr(stationLang(), "station.chat.archived")}`, []).catch((error) => log.warn("hub", "archived notice not posted", { thread: existing.id, error: (error as Error).message }));
      }
      return;
    }
    const createdBy = `slack:${connect.id}:${message.user}`;
    if (wanted && !exists) {
      try {
        this.createSession(config, key, connect, single ? "all" : "thread", message, null, createdBy);
        if (single) this.store.setBinding(connect.id, key);
      } catch (error) {
        log.error("hub", "cannot create session", { session: key, error: (error as Error).message });
        await chat.post(here, `⚠️ ${tr(stationLang(), "station.slack.sessionFailed", { error: (error as Error).message })}`, []);
        return;
      }
      // As the broker did: a new session says first where it can be followed. Once, as it starts; not waited for. In
      // Slack's own link form: what the station posts is sent as written.
      const link = single ? undefined : this.link(key);
      const said = link === undefined ? null : chat.sessionLink ? chat.sessionLink(link, tr(stationLang(), "station.slack.viewSession")) : `<${link}|${tr(stationLang(), "station.slack.viewSession")}>`;
      if (said !== null) {
        chat.post(here, said, []).catch((error) => log.warn("hub", "session link not posted", { session: key, error: (error as Error).message }));
      }
    }
    const thread = existing ?? (await this.openSlackThread(chat, surface, message, createdBy, key));
    if (wanted) this.store.joinThread(thread.id, key, connect.id);
    // Its files go where a session of the thread reads them; once (Slack sends a message again it was slow to hear of).
    const into = wanted ? key : (members[0]?.session ?? key);
    const said = this.store.messageAt(thread.id, message.ts) === null ? await this.fetched(chat, into, message.text, message.files) : { text: message.text, attachments: [] };
    const [n, fresh] = this.store.insertMessage({ thread: thread.id, ts: message.ts, authorKind: "person", author: message.user, ...said });
    // A message seen by a second connect is already delivered to the thread; only a session it brings in lacks it.
    const targets = fresh ? this.store.threadSessions(thread.id).map((m) => m.session) : wanted ? [key] : [];
    this.deliver(thread.id, n, targets, message.text);
  }

  /// A Slack thread the station starts following. When that happens mid-thread, what was said before is recorded first
  /// (without deliveries), so the thread on the pages and chat_history are complete and the log keeps Slack's order.
  private async openSlackThread(chat: ChatSurface, surface: string, message: InboundMessage, createdBy: string, key: string): Promise<ThreadRow> {
    let earlier: { ts: string; user: string; text: string; files?: InboundFile[] }[] = [];
    if (message.ts !== message.threadTs) {
      try {
        earlier = (await chat.history?.({ channel: message.channel, threadTs: message.threadTs }, message.ts, 200)) ?? [];
      } catch (error) {
        log.warn("hub", "cannot read what the thread said before; continuing without it", { channel: message.channel, threadTs: message.threadTs, error: (error as Error).message });
      }
    }
    // Asked before the thread exists, so a connect seeing the same message meanwhile cannot record it ahead of these.
    const said = [];
    for (const m of earlier) said.push({ ...m, ...(await this.fetched(chat, key, m.text, m.files)) });
    const thread = this.store.openThread(surface, message.channel, message.threadTs, null, createdBy);
    for (const m of said) this.store.insertMessage({ thread: thread.id, ts: m.ts, authorKind: "person", author: m.user, text: m.text, attachments: m.attachments });
    return thread;
  }

  /// A message's text and its shared files, fetched into the session's uploads (as files sent in the station's own
  /// chats are). A file that cannot be fetched is named in the text with why, so its reader knows one was there.
  private async fetched(chat: ChatSurface, key: string, text: string, files: InboundFile[] | undefined): Promise<{ text: string; attachments: Attachment[] }> {
    const row = files && files.length > 0 ? this.store.getSession(key) : null;
    if (!files || !row) return { text, attachments: [] };
    const dir = join(row.workspace, "uploads");
    const attachments: Attachment[] = [];
    const missing: string[] = [];
    for (const file of files) {
      try {
        if (!chat.download) throw new Error("this platform does not give files");
        if (file.size > MAX_INBOUND_FILE) throw new Error("over 50 MB");
        const bytes = await chat.download(file);
        mkdirSync(dir, { recursive: true });
        const safe = Array.from(file.name)
          .map((c) => (c === "\\" || c === "/" || c.codePointAt(0)! < 0x20 ? "_" : c))
          .join("");
        const path = join(dir, `${iso(this.now()).slice(0, 19).replace(/[:.]/g, "-")}-${file.id}-${safe}`);
        writeFileSync(path, bytes);
        const attachment: Attachment = { name: file.name, path, size: bytes.length, ...shownFacts(path) };
        attachments.push(attachment);
      } catch (error) {
        log.warn("hub", "shared file not fetched", { session: key, file: file.id, error: (error as Error).message });
        missing.push(tr(stationLang(), "station.slack.fileNotFetched", { name: file.name, error: (error as Error).message }));
      }
    }
    return { text: [text, ...missing].filter((t) => t !== "").join("\n\n"), attachments };
  }

  /// Gives sessions a message they have not had: each runs it, or stops for `-stop` (hub.rs `hand_over`), compacts its
  /// context for `-compact`, clears it for `-clear` (saying in the thread why not, when it cannot now).
  /// A session archived by hand hears nothing until shown again.
  deliver(thread: number, n: number, sessions: string[], text: string) {
    const hearing = sessions.filter((key) => this.store.getSession(key)?.archivedBy !== MANUAL);
    for (const key of this.store.deliver(thread, n, hearing)) {
      this.store.touch(key);
      const row = this.store.getSession(key);
      if (!row) continue;
      const actor = this.actor(row);
      const command = threadCommand(text);
      if (command === null) {
        void actor.kick();
        continue;
      }
      this.store.markDelivered(key, [[thread, n]]);
      if (command === "stop") void actor.stop();
      else if (command === "compact") void actor.compact(true);
      else void actor.clear(true);
    }
  }

  /// An agent's post reaches the other sessions of its thread, as a person's would: agents work together there.
  shared(thread: number, n: number, author: string, text: string) {
    const others = this.store.threadSessions(thread).map((m) => m.session).filter((s) => s !== author);
    if (others.length > 0) this.deliver(thread, n, others, text);
  }

  /// The station's tools are open at `url`: a process taken up that was told another address (the station before had
  /// them elsewhere) starts again, as it can (SessionActor `toolsAt`).
  toolsAt(url: string) {
    for (const actor of this.actors.values()) void actor.toolsAt(url);
  }

  /// After a restart: resume cut-off turns (those not taken up with their runtime), then deliver whatever is still
  /// pending.
  recover() {
    for (const row of this.store.runningSessions()) {
      // Taken up from the previous station: its turn runs on.
      if (this.adopted.has(row.key) || !this.online(row)) continue;
      log.info("hub", "recovering a turn cut off by restart", { session: row.key });
      void this.actor(row).recover();
    }
    for (const key of this.store.sessionsWithPending()) {
      const row = this.store.getSession(key);
      if (row && this.online(row)) void this.actor(row).kick();
    }
    // Waits on record that were not handed over (the station before stopped without a handover): taken up, so each asks
    // again when it would have (or put right, SessionActor.takeWait). Over the sessions shown: an archived one waits on
    // nothing.
    const live = this.store.liveSessions();
    const stats = this.store.statsOf(live.map((s) => s.key));
    for (const row of live) {
      const last = stats.get(row.key)?.lastTurn;
      if (last?.declared === "waiting" && last.endedAt !== null && this.online(row)) void this.actor(row).takeWait();
    }
  }

  /// What to do when a session's runtime was not found as it started.
  onRuntimeMissing(f: (runtime: RuntimeKind) => void) {
    this.runtimeMissing = f;
  }

  /// A runtime installed here (from the pages): the sessions on it whose messages wait (their start found it missing)
  /// take them now.
  installed(runtime: RuntimeKind) {
    for (const key of this.store.sessionsWithPending()) {
      const row = this.store.getSession(key);
      if (row && row.runtime === runtime && this.online(row)) void this.actor(row).kick();
    }
  }

  // ── warm processes ─────────────────────────────────────────────────────────────────────────────────────────────

  /// Ends idle claude and dsh processes (one per session) beyond the warm limit, oldest first, once they have idled
  /// past warmMs. Codex threads share a process and stay. Runs when a process goes idle (the count grew) and at each
  /// idle process's deadline.
  private evictIdle() {
    const config = this.config();
    const now = this.now();
    // In sandboxes every session's process goes once idle long enough, whatever its runtime, and its sandbox with it:
    // nothing is kept warm there (agents/sandbox.ts `sandboxIdleMs`).
    const sandboxIdle = sandboxIdleMs(config.dataDir);
    if (sandboxIdle !== null) {
      for (const actor of this.actors.values()) {
        const ms = actor.idleMs(now);
        if (ms !== null && ms >= sandboxIdle) void this.stopIdle(actor);
      }
      return;
    }
    const idle = [...this.actors.values()]
      .filter((a) => a.runtime !== "codex")
      .flatMap((a) => {
        const ms = a.idleMs(now);
        return ms === null ? [] : [[a, ms] as const];
      })
      .sort((a, b) => b[1] - a[1]);
    let excess = idle.length - config.maxWarmClaude;
    for (const [actor, ms] of idle) {
      if (excess <= 0 || ms < config.warmMs) break;
      void actor.evict();
      excess--;
    }
  }

  /// Ends an idle session's process, then stops its sandbox, unless something started there again meanwhile (the front
  /// door refuses while a job or a new process has a connection to it).
  private async stopIdle(actor: SessionActor) {
    await actor.evict();
    if (actor.processState() !== "cold") return;
    const data = this.config().dataDir;
    if (await stopSandbox(data, keyPart(actor.key))) log.info("hub", "idle session's sandbox stopped", { session: actor.key });
  }

  /// Stops the sandboxes of this station's sessions that nothing runs in: a session whose process ended some other way
  /// than going idle (it exited, the station restarted without it), left with its sandbox. Every `SWEEP_MS` while the
  /// station runs things in sandboxes (agents.ts).
  async sweepSandboxes() {
    const data = this.config().dataDir;
    if (sandboxIdleMs(data) === null) return;
    const idle = await idleSandboxes(data);
    if (idle.length === 0) return;
    const sessions = new Map(this.store.listSessions().map((row) => [sandboxName(keyPart(row.key)), row.key]));
    for (const name of idle) {
      const key = sessions.get(name);
      if (key === undefined) continue;
      if ((this.actors.get(key)?.processState() ?? "cold") !== "cold") continue;
      if (await stopSandbox(data, keyPart(key))) log.info("hub", "a sandbox nothing ran in stopped", { session: key });
    }
  }

  /// A process went idle: look again when it has idled past warmMs.
  idleNow(key: string) {
    // A manual archive may have arrived during the last turn. Finish that archive when the turn ends; never sweep old
    // directories on a clock or at startup.
    const row = this.store.getSession(key);
    if (row && row.archivedAt !== null) {
      const actor = this.actor(row);
      void actor.evict().then(() => actor.cleanArchive());
    }
    const old = this.deadlines.get(key);
    if (old) this.interrupt(old);
    // When it will have idled long enough: from when it went idle (one taken up from the previous station may have been
    // idle a while already).
    const limit = Math.min(this.config().warmMs, sandboxIdleMs(this.config().dataDir) ?? Infinity);
    const idleFor = this.actors.get(key)?.idleMs(this.now()) ?? 0;
    const fiber = this.runFork(
      Effect.sleep(Math.max(0, limit - idleFor)).pipe(
        Effect.andThen(
          Effect.sync(() => {
            this.deadlines.delete(key);
            this.evictIdle();
          }),
        ),
      ),
    );
    this.deadlines.set(key, fiber);
    this.evictIdle();
  }

  /// Ends the session's runtime process if it is idle; the conversation resumes on the next message.
  async evict(key: string) {
    await this.actors.get(key)?.evict();
  }

  /// How a session runs changed: its process ends now if idle, else before its next turn (SessionActor.changed).
  async changed(key: string) {
    await this.actors.get(key)?.changed();
  }

  /// What every runtime process starts with changed (the station's variables for its agents, ops/agent-env.ts): each
  /// session's process ends now if idle, else before its next turn, and the next starts with it (none retuned in place).
  everyChanged() {
    for (const actor of [...this.actors.values()]) void actor.changed(true).catch(() => {});
  }

  /// A profile was deleted: the sessions on it are taken on by another of their runtime's (their process ends now if
  /// idle, else when its turn is over); those no other profile can run are stopped, and their process ends.
  async profileGone(id: string) {
    for (const row of this.store.listSessions()) {
      if (row.profile !== id) continue;
      let movable = true;
      try {
        this.accounts.runOn(row.key);
      } catch {
        movable = false;
      }
      log.info("hub", "profile deleted under a session", { session: row.key, profile: id, movedTo: movable ? (this.store.getSession(row.key)?.profile ?? "") : "" });
      const actor = this.actors.get(row.key);
      if (!actor) continue;
      if (!movable) await actor.stop();
      await actor.changed();
    }
  }

  /// Starts a session's runtime ahead of a message (SessionActor.warm).
  async warm(key: string) {
    const row = this.store.getSession(key);
    if (row) await this.actor(row).warm();
  }

  /// Interrupts the session's running turn, or what it waits on, as `-stop` in a thread would.
  async stop(key: string) {
    const row = this.store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    await this.actor(row).stop();
  }

  /// Compacts the session's context between turns, as `-compact` in a thread would (SessionActor.compact): why not,
  /// when it cannot now.
  async compact(key: string): Promise<string | null> {
    const row = this.store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    return this.actor(row).compact();
  }

  /// Clears the session's context between turns, as `-clear` in a thread would (SessionActor.clear; `readBack`: to go on
  /// afresh): why not, when it cannot now.
  async clear(key: string, readBack = false): Promise<string | null> {
    const row = this.store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    return this.actor(row).clear(false, readBack);
  }

  /// A word from the station for a session's agent, outside any conversation (SessionActor.notify).
  notify(key: string, text: string) {
    const row = this.store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    void this.actor(row).notify(text);
  }

  /// Live process state of a session, for the pages.
  processState(key: string): "running" | "warm" | "cold" {
    return this.actors.get(key)?.processState() ?? "cold";
  }

  /// Every session's process state that is not cold (what the reads are given).
  processes(): Map<string, string> {
    return new Map([...this.actors].flatMap(([key, a]) => (a.processState() === "cold" ? [] : [[key, a.processState()] as [string, string]])));
  }

  /// The key the client that asked for a session gave it (NewChat.clientKey), while it is kept.
  clientKey(key: string): string | undefined {
    const kept = this.clientKeysMade.get(key);
    return kept && this.now() - kept[1] < CLIENT_KEY_KEPT_MS ? kept[0] : undefined;
  }

  clientKeys(): Map<string, string> {
    return new Map([...this.clientKeysMade].filter(([, [, at]]) => this.now() - at < CLIENT_KEY_KEPT_MS).map(([key, [client]]) => [key, client]));
  }

  // ── what goes beside it ────────────────────────────────────────────────────────────────────────────────────────

  /// The station's background jobs, once they are made.
  setJobs(jobs: Jobs) {
    this.jobs = jobs;
  }

  /// What to do when a session is archived or deleted (Remote.closeSession).
  onClose(closed: (key: string) => void) {
    this.closedHook = closed;
  }

  closed(key: string) {
    this.closedHook?.(key);
  }

  /// Hooks session_send up to the other stations of the workspace.
  onPeer(call: (station: string, request: Json) => Promise<Json>) {
    this.peersHook = call;
  }

  peers() {
    return this.peersHook;
  }

  /// Hooks chat_list up to the chats other workspaces share with this one (xshare/index.ts).
  onOutsideChats(list: (ws: string | null) => OutsideChat[]) {
    this.outsideHook = list;
  }

  /// The chats other workspaces share with workspace `ws` (null: the home one).
  outsideChats(ws: string | null = null): OutsideChat[] {
    return this.outsideHook?.(ws) ?? [];
  }

  async shutdown() {
    this.stopTimers();
    this.unlistenRunning();
    this.live.close();
    await Promise.all([...this.actors.values()].map((a) => a.dispose()));
    await Promise.all([...this.drivers.values()].map((d) => d.shutdown()));
  }

  private stopTimers() {
    for (const fiber of [...this.deadlines.values(), ...this.fibers]) this.interrupt(fiber);
    this.deadlines.clear();
    this.fibers.clear();
  }

  /// Runs `effect` as a fiber of the hub's own, interrupted at shutdown or handover.
  fork(effect: Effect.Effect<void>) {
    // It may end before runFork returns.
    const held: { fiber?: Fiber.Fiber<void>; done?: boolean } = {};
    held.fiber = this.runFork(
      effect.pipe(
        Effect.ensuring(
          Effect.sync(() => {
            held.done = true;
            if (held.fiber) this.fibers.delete(held.fiber);
          }),
        ),
      ),
    );
    if (!held.done) this.fibers.add(held.fiber);
  }

  /// Runs `effect` on the hub's clock.
  private runFork<A>(effect: Effect.Effect<A>): Fiber.Fiber<A> {
    return Effect.runFork(effect.pipe(Effect.provideService(Clock.Clock, this.clock)));
  }

  private interrupt(fiber: Fiber.Fiber<void>) {
    Effect.runFork(Fiber.interrupt(fiber));
  }

  // ── chats and connects ─────────────────────────────────────────────────────────────────────────────────────────

  chat(connect: string): ChatSurface {
    const chat = this.chatOf(connect);
    if (!chat) throw new Error(`connect ${connect} is not connected`);
    return chat;
  }

  chatOf(connect: string): ChatSurface | undefined {
    if (connect === INTERNAL_CONNECT) return this.internal ?? undefined;
    return this.options.chats(connect);
  }

  /// Where a connect's threads live; the rule the v10 migration follows too. A Feishu connect's are its own (its people's
  /// ids are the app's own, so another bot's in the same chat are other people: docs/feishu.md).
  surface(connect: string): string {
    if (connect === INTERNAL_CONNECT) return STILLFAIL_SURFACE;
    if (this.config().connects.find((c) => c.id === connect)?.kind === "feishu") return feishuSurface(connect);
    return slackSurface(connect, this.chatOf(connect)?.workspace() ?? null);
  }

  /// A Slack user that is one of this station's connects' bots.
  private ownBot(config: HubConfig, user: string): boolean {
    return config.connects.some((c) => {
      const bot = this.chatOf(c.id)?.botUserId() ?? "";
      return bot !== "" && bot === user;
    });
  }

  private online(row: SessionRow): boolean {
    const via = this.store.latestThread(row.key)?.connect ?? row.connect;
    if (this.chatOf(via)) return true;
    log.warn("hub", "session's latest thread came through a connect that is not connected; leaving it", { session: row.key, connect: via });
    return false;
  }

  /// Which workspace a session's chat is in: its own, or the station's home one for those from before (null outside
  /// any workspace).
  wsOf(row: SessionRow | string | null): string | null {
    const s = typeof row === "string" ? this.store.getSession(row) : row;
    return s?.ws ?? this.workspaces()[0] ?? null;
  }

  /// The profiles sessions of workspace `ws` may run on (docs/multi-workspace.md): every one for the home workspace's.
  profilesIn(ws: string | null): Profile[] {
    const home = this.workspaces()[0] ?? null;
    return this.config().profiles.filter((p) => allowedIn(p, ws, home));
  }

  /// Whether a session's chat is in `workspace` (a viewer's): what a member of one workspace may see and use.
  inWorkspace(row: SessionRow | string | null, workspace: string): boolean {
    const s = typeof row === "string" ? this.store.getSession(row) : row;
    return s !== null && s !== undefined && this.wsOf(s) === workspace;
  }

  /// A session for a connect: the connect's own profile when it keeps to one (and it still can run it); else any of its
  /// runtime, the model's first (pool.ts).
  createSession(config: HubConfig, key: string, connect: Connect, scope: "thread" | "all", message: InboundMessage | null, title: string | null, createdBy: string | null) {
    const fits = profilesFor(config, connect, this.workspaces()[0] ?? null);
    if (fits.length === 0 && profilesFor(config, connect).length > 0) throw new Error(tr(stationLang(), "station.session.noProfileHere", { runtime: runtimeTitle(connect.bind.runtime) }));
    const model = connect.bind.model ?? null;
    const kept = connect.bind.profile !== undefined ? fits.find((p) => p.id === connect.bind.profile && serves(p, model)) : undefined;
    const profile = kept ?? this.accounts.pick(fits, model, false);
    const dir = scope === "thread" && message ? `${message.channel}-${message.threadTs.replace(".", "-")}` : key.slice(connect.id.length + 1);
    const workspace = join(config.dataDir, "sessions", connect.id, dir, "workspace");
    mkdirSync(workspace, { recursive: true });
    mkdirSync(join(config.dataDir, "repos"), { recursive: true });
    const now = this.now();
    this.store.insertSession({
      key,
      connect: connect.id,
      scope,
      title,
      createdBy,
      runtime: connect.bind.runtime,
      profile: profile.id,
      profilePinned: kept !== undefined,
      model: connect.bind.model ?? null,
      effort: connect.bind.effort ?? null,
      fast: null,
      workspace,
      cwd: null,
      runtimeSessionId: null,
      token: newToken(),
      createdAt: now,
      lastActiveAt: now,
      ws: connect.workspace ?? null,
    });
    log.info("hub", "session created", { session: key, connect: connect.id, scope, runtime: connect.bind.runtime, profile: profile.id });
  }

  /// The session's actor, made on first use.
  actor(row: SessionRow): SessionActor {
    const existing = this.actors.get(row.key);
    if (existing) return existing;
    const runtime = runtimeNamed(row.runtime);
    if (!runtime) throw new Error(`session ${row.key} runs an unknown runtime ${row.runtime}`);
    const actor = new SessionActor(row.key, runtime, this.deps);
    this.actors.set(row.key, actor);
    return actor;
  }

  /// Takes a session's actor out (deleted).
  dropActor(key: string): SessionActor | undefined {
    const actor = this.actors.get(key);
    this.actors.delete(key);
    const deadline = this.deadlines.get(key);
    if (deadline) this.interrupt(deadline);
    this.deadlines.delete(key);
    return actor;
  }

  private sessionDriver(runtime: string): AgentDriver {
    const driver = this.drivers.get(runtime);
    if (!driver) throw new Error(`no ${runtime} driver`);
    return driver;
  }

  /// What a session needs of the station (SessionDeps).
  private sessionDeps(): SessionDeps {
    return {
      store: this.store,
      chat: (connect) => this.chatOf(connect),
      driver: (runtime) => this.sessionDriver(runtime),
      runOn: (key, holding) => this.accounts.runOn(key, holding),
      spend: (key, ranOn) => this.accounts.spend(key, ranOn),
      refillsAt: (key) => this.accounts.refillsAt(key),
      recheck: (profile) => this.accounts.recheck(profile),
      mcpUrl: () => (typeof this.options.mcpUrl === "string" ? this.options.mcpUrl : this.options.mcpUrl()),
      toSandbox: async (key) => {
        const data = this.config().dataDir;
        const row = this.store.getSession(key);
        if (row && sandboxed(data)) await syncChanged(data, keyPart(key), sessionSync(data, row.workspace));
      },
      reposDir: () => this.reposDir(),
      memoryPath: (key) => agentHomePaths(workspaceAgentHome(this.config().agentHome, this.wsOf(key), this.workspaces()[0] ?? null))[0],
      maxNudges: () => this.config().maxNudges,
      backgroundOnMessage: (key) => {
        const row = this.store.getSession(key);
        if (!row) return true;
        return this.config().profiles.find((p) => p.id === row.profile)?.backgroundOnMessage ?? true;
      },
      live: this.live,
      startsAfresh: (key, id, to, was) => startsAfresh(this, key, id, to, was),
      cleared: (key, readBack) => toldCleared(this, key, readBack),
      coldAfresh: (key, now) => goesAfresh(this, key, now),
      resumeLost: (key) => toldResumeLost(this, key),
      carrySubagents: (from, to, on, ids) => carrySubagents(this, from, to, on, ids),
      ranIn: (key, id, profile) => this.store.ranIn(key, id, profile),
      idle: (key) => this.idleNow(key),
      archiveIsCold: (key) => this.cold.isCold(key),
      restoreArchive: (key) => this.cold.restore(key),
      cleanArchive: (key) => this.cold.pack(key),
      held: (key) => this.holdsNow.size > 0 || !this.inAWorkspace(key),
      stopJobs: async (key) => {
        const jobs = this.jobs;
        const running = this.store.listJobs(key).filter((j) => j.state === "running" && (j.watch || j.port === null));
        if (!jobs) return;
        for (const job of running) {
          try {
            await jobs.stop(job.id);
            log.info("hub", "job stopped with its session's wait", { session: key, job: job.id });
          } catch (error) {
            log.warn("hub", "job not stopped", { session: key, job: job.id, error: (error as Error).message });
          }
        }
      },
      endJobs: async (key) => {
        const jobs = this.jobs;
        if (!jobs) return;
        for (const job of this.store.listJobs(key).filter((j) => j.state === "running" || (j.state === "exited" && j.port !== null))) {
          try {
            await jobs.stop(job.id);
            log.info("hub", "job stopped with its session archived", { session: key, job: job.id });
          } catch (error) {
            log.warn("hub", "job not stopped", { session: key, job: job.id, error: (error as Error).message });
          }
        }
      },
      settled: (key, state, words) => settled(this, key, state, words),
      toolStatus,
      pageOf: (key) => this.link(key),
      places: this.places,
      runtimeMissing: (runtime) => this.runtimeMissing(runtime),
      nextTs: () => this.nextTs(),
      clock: this.clock,
    };
  }
}

/// How long a new chat's rows say the key its client gave it: long past its answer.
export const CLIENT_KEY_KEPT_MS = 10 * 60 * 1000;

export function connectOf(config: HubConfig, id: string): Connect {
  const connect = config.connects.find((c) => c.id === id);
  if (!connect) throw new Error(`unknown connect ${id}`);
  return connect;
}
