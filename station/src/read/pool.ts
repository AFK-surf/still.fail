// The readers: worker threads, each with its own read-only connection, in two lines that share none of them. What the
// station tells as things change (the event streams, its notices: `told`) is read by a reader of its own; what devices
// ask, by the others. Neither waits on the other: on a station (2026-11-02) one line served both, and what was told of a
// message just said waited 50 s behind a usage read and sidebar updates, a push notice 55 s. Among what devices ask,
// bulk reads leave room for chat reads. None of these reads holds up writes.
// A reader is a V8 of its own (tens of MB), so they are started when reads come and let go once none has come for a
// while: an idle station keeps none. One that dies (its heap is bounded) fails what it held and is replaced by the next
// read.
import { availableParallelism } from "node:os";
import { join } from "node:path";
import { Worker } from "node:worker_threads";
import { catalog } from "../accounts/catalog.ts";
import { tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import type { InWorkspace } from "../store/rows.ts";
import { MinuteReader } from "../usage/minute-reader.ts";
import { OutflowChatIndex } from "./chat-index-builder.ts";
import { SaidBuilder } from "./said-builder.ts";
import { RequestedBuilder } from "./requested-builder.ts";
import { TurnBuilder } from "./turn-builder.ts";
import { RecentChatBuilder } from "./recent-chat-builder.ts";
import { RECENT_CHAT_PENDING } from "./recent-chat.ts";
import { SessionListBuilder } from "./session-list-builder.ts";
import { SESSION_LIST_PENDING } from "../store/session-list-index.ts";
import { SessionBindingsBuilder } from "./session-bindings-builder.ts";
import { ArchiveMarkBuilder } from "./archive-mark-builder.ts";
import { SessionUpJobsBuilder } from "./session-up-jobs-builder.ts";
import { WorkspaceUpJobsBuilder } from "./workspace-up-jobs-builder.ts";
import { WidgetSourcesBuilder } from "./widget-sources-builder.ts";
import { CcIndexBuilder } from "./cc-index-builder.ts";
import { CardPostsBuilder, ClosedCardsBuilder, PeopleSinceBuilder } from "./card-posts-builder.ts";
import { CC_SESSIONS_PENDING } from "../store/cc-thread-index.ts";
import { JOB_NAME_FIRST_PENDING } from "../store/job-name-first.ts";
import { CARD_POSTS_PENDING } from "../store/card-post-index.ts";
import { CLOSED_CARDS_PENDING } from "../store/legacy-closed-cards.ts";
import { PEOPLE_TIME_PENDING } from "../store/legacy-people-since.ts";
import { SESSION_BINDINGS_PENDING } from "../store/session-bindings-index.ts";
import { OUTFLOW_CHATS_PENDING } from "./outflow.ts";
import type { Answer, Ask, Ready } from "./worker.ts";
import { LAST_MESSAGE_PENDING, LEGACY_EDITS_PENDING, LEGACY_SAID_PENDING, PAGE_LETTER_PENDING, REMOTE_RUNS_PENDING, SAID_PENDING, TURN_COUNT_PENDING, USAGE_CHATS_PENDING, USAGE_DETAIL_PENDING } from "./store.ts";
import { HttpError } from "./views.ts";
import { MbReader, type ReaderLike, mbReaderBinary } from "./mb-reader.ts";
import { wall } from "../ops/fibers.ts";
import { roots as machineRoots } from "./machine.ts";
import type { CardEditPage, CardMessagePage } from "../store/card-outbox.ts";

/// How long a reader with nothing to do is kept.
const IDLE_MS = 60_000;
/// A read that waited or took longer than this is logged, with what it was.
const SLOW_MS = 2_000;

/// `held`: the read it is answering, if any.
type Slot = { worker: ReaderLike; held: Asked | null; idle?: () => void; retiring?: boolean; catalogVersion: number };

/// A read in line or being answered: when it was asked and when a reader took it, and the reader it is best read in (a
/// session's history, where its reading stands in memory).
type Asked = {
  ask: Ask;
  session: string | null;
  home: Slot | null;
  /// After every other read waiting, one at a time (`read`).
  background: boolean;
  at: number;
  took: number;
  resolve: (text: string) => void;
  reject: (error: Error) => void;
};

/// A line of reads and the readers that answer it, at most `size` of them, the first read first. `room`: bulk reads leave
/// one of them for a chat read (what devices ask).
/// `rested`: when a background read may be taken again (one just read rests as long as it took).
/// `wake`: the line looked at again once it has rested (one at a time).
type Line = { told: boolean; size: number; room: boolean; slots: Slot[]; waiting: Asked[]; rested?: number; wake?: () => void };

/// How many sessions' readers are remembered (the most recently read).
const HOMES = 4096;
/// How long after the store changes its log is written into the database (`checkpointSoon`): at most this often.
const CHECKPOINT_MS = 2_000;
/// Writing the store's log into the database (worker.ts `checkpoint`) is no read and waits for no one: it has a reader
/// of its own (`log`). In line behind reads, a checkpoint may wait as the log grows until the main connection writes it
/// at its next commit (store.ts WAL_PAGES); on a device reader it can hold up interactive reads while reaching disk.
const CHECKPOINT = "checkpoint";
const cancelled = () => new HttpError(503, "read cancelled");
/// The scoped reads on the path to showing a chat, and those a device's lists are made of, each of a few rows and the
/// statistics kept of them (the sidebar, a session's detail and summary, a chat's latest messages). Other page reads,
/// including new kinds not yet classified, leave room for these, and these go before them: a slow transcript or resource
/// snapshot can block just as a slow aggregate can. A machine sample (api/host.ts), one job, and the jobs up without
/// their chats are interactive too; jobs with their chats (an older device's, the sidebar made for it) are a bulk read.
const INTERACTIVE = new Set(["thread", "chats", "chatMarks", "session", "summary", "latestMessages", "openedChatSaid", "chatHistoryMessages", "historyPendingCard", "stateQuestion", "statePendingCard", "deliveryCardState", "job"]);

/// One thread's current or older page is interactive. An `after` or explicit range can ask for an unbounded amount on
/// older clients, so it remains in the background until that request is paged end to end.
function interactive(a: Asked): boolean {
  if (INTERACTIVE.has(a.ask.op)) return true;
  if (a.ask.op === "openJobs") return a.ask.args?.chats === false;
  if (a.ask.op !== "entries" && a.ask.op !== "letters") return false;
  const params = a.ask.args?.params;
  const keys = Array.isArray(params) ? params.map((p: unknown) => Array.isArray(p) ? p[0] : null) : Object.keys(params ?? {});
  return !keys.includes("after") && !keys.includes("from") && !keys.includes("to");
}

/// A stretch of a session's history in brief (`from` and `to`): what a client fills in of it in the background, where its
/// stream left a hole or it holds less than there is (client/core-ts/src/station/channel-kinds.ts TRANSCRIPT). Up to
/// 1,000 items a read, 16 MB of a Codex transcript and 6 s on a station (2026-11-03), the sidebar waiting 9 s behind them.
/// One read whole (a step opened) is someone's waiting on it.
function filling(op: string, args: unknown): boolean {
  const a = args as { from?: unknown; to?: unknown; brief?: unknown } | null;
  return op === "timeline" && a !== null && typeof a.from === "string" && typeof a.to === "string" && a.brief === "1";
}

/// Reads by the pages' readers (`pages`): a history's pages, and the machine's own sessions (GET /machine-sessions, a walk
/// of every Claude and Codex project there, 14 s on a station, 2026-11-03), each of the files on the disk rather than the
/// database.
const PAGES = new Set(["timeline", "machineSessions"]);
/// The reads the MoonBit reader answers itself (station/mb src/readops), on readers of their own (`moved`) where its
/// program is there; every other read is a worker's.
const MOVED = new Set(["job", "jobLog", "historyPendingCard", "statePendingCard", "deliveryCardState", "reviewPendingCard", "stateQuestion", "pendingDeliveries", "latestMessages", "chatHistoryMessages", "openedChatSaid", "widgetState", "transcriptFile", "memory", "machineSessions", "machineSession", "sessionsAtWork", "policyChecks", "recentConnectPeople", "usageTurns", "usageCalls", "outflowMessages", "archiveLook", "recentChatList", "searchChatList", "threadList", "sharedOf", "sharedChats"]);
/// The reads of this machine's own Claude Code and Codex sessions: the MoonBit reader is told where they are kept, from
/// this process's environment (read/machine.ts `roots`), as the worker reads it.
const MACHINE = new Set(["machineSessions", "machineSession"]);
/// The reads that say who someone is in the station's words (read/views.ts `creator`, `authorNames`: the local page, its
/// admin), and go by the time of day (a share used lately, a card answered lately): the MoonBit reader keeps no words
/// and its clock is no wall's, so it is given these in the language asked, and the time as the read is asked.
const WORDED = new Set(["sharedOf", "sharedChats"]);
const wordsIn = (lang: Ask["lang"]) => ({ localPage: tr(lang, "station.creator.localPage"), admin: tr(lang, "station.author.admin") });

export class Readers {
  /// What devices ask, and what the station tells (`told`), each answered by readers of its own.
  private asked: Line;
  /// The pages of sessions' histories (`timeline`), by a reader of their own: a page is read from the mark before it
  /// (read/transcripts.ts), megabytes of a long transcript, seconds from a disk short of memory; in line with what
  /// devices ask, the sidebar and a chat opened waited 20 s and more behind them on a station (2026-11-03).
  private pages: Line;
  private told: Line;
  /// The store's log written into the database (CHECKPOINT), by a reader of its own.
  private log: Line;
  /// The reads the MoonBit reader answers (MOVED), for devices and streams alike.
  private moved: Line;
  /// The reader each session's history was last read in (`timeline`).
  private homes = new Map<string, Slot>();
  private next = 0;
  private closed = false;
  private minutes: MinuteReader | null = null;
  private outflowChats: OutflowChatIndex | null = null;
  private said: SaidBuilder | null = null;
  private archiveLast: RequestedBuilder<number> | null = null;
  private legacyEdits: RequestedBuilder<number> | null = null;
  private legacySaid: RequestedBuilder<number> | null = null;
  private pageLetters: RequestedBuilder<number> | null = null;
  private turns: TurnBuilder | null = null;
  private recentChats: RecentChatBuilder | null = null;
  private sessionList: SessionListBuilder | null = null;
  private sessionBindings: SessionBindingsBuilder | null = null;
  private archiveMarks: ArchiveMarkBuilder | null = null;
  private sessionUpJobs: SessionUpJobsBuilder | null = null;
  private workspaceUpJobs: WorkspaceUpJobsBuilder | null = null;
  private jobNameFirst: RequestedBuilder<string> | null = null;
  private preparingWorkspaceUpJobs = false;
  /// Reads of the same old session share one unattended preparation, including during handover.
  private preparingUpJobs = new Set<string>();
  private widgetSources: WidgetSourcesBuilder | null = null;
  private cardPosts: CardPostsBuilder | null = null;
  private closedCards: ClosedCardsBuilder | null = null;
  private peopleSince: PeopleSinceBuilder | null = null;
  private ccIndex: CcIndexBuilder | null = null;
  /// A checkpoint is armed or running (`checkpointSoon`), and the store changed again since it was armed.
  private checkpointing = false;
  private again = false;
  /// The station's data directory, whose database they read.
  readonly data: string;
  private readonly workerFile: URL | undefined;
  private readonly backfill: { previousGone?: Promise<void>; priority?: SharedArrayBuffer };
  /// People's names as their credentials say them (the admin API's `deps.names`), given to every read.
  readonly names = new Map<string, string>();
  /// The MoonBit reader's program (read/mb-reader.ts), which writes the store's log into it (`log`); none: a worker
  /// does, as it does every other read (and with a worker of its own given, `workerFile`, that one).
  mbReader: string | null;
  /// What only the hub knows, given to every read: sessions' process states and client keys (the hub sets these).
  processes: () => Map<string, string> = () => new Map();
  clientKeys: () => Map<string, string> = () => new Map();

  /// For what devices ask, at most two by default (STILLFAIL_READERS says otherwise); for what is told, `tellers`.
  constructor(data: string, size = Number(process.env.STILLFAIL_READERS) || Math.min(2, Math.max(1, availableParallelism() - 1)), workerFile?: URL, tellers = 1, backfill: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}) {
    this.data = data;
    this.workerFile = workerFile;
    this.mbReader = workerFile === undefined ? mbReaderBinary() : null;
    this.backfill = backfill;
    this.asked = { told: false, size, room: true, slots: [], waiting: [] };
    // Two: one a background page (a history brought on, a stretch filled) may hold, one left for a page someone waits on.
    this.pages = { told: false, size: 2, room: false, slots: [], waiting: [] };
    this.told = { told: true, size: tellers, room: false, slots: [], waiting: [] };
    this.log = { told: true, size: 1, room: false, slots: [], waiting: [] };
    this.moved = { told: false, size, room: true, slots: [], waiting: [] };
  }

  /// Check statistical coverage without occupying a device reader or writing old history.
  startUsageIndex() {
    if (this.closed) return;
    if (this.minutes === null) this.minutes = new MinuteReader(join(this.data, "stillfail.db"), this.backfill, this.mbReader);
    this.minutes.start();
  }

  private start(line: Line): Slot {
    // From source: worker.ts beside this; bundled (this inside dist/main.js): dist/read/worker.js.
    const file = this.workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./worker.ts" : "./read/worker.js", import.meta.url);
    // A reader's heap stays small: what it builds is answered and dropped.
    const worker: ReaderLike = (line === this.log || line === this.moved) && this.mbReader !== null ? new MbReader(this.mbReader, this.data)
      : new Worker(file, { workerData: { data: this.data }, resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 8 } });
    const slot: Slot = { worker, held: null, catalogVersion: 0 };
    const begun = wall.now();
    worker.on("message", (answer: Answer | Ready) => {
      // How long a reader took to start: a read given it as it starts waits on that (one read of 1.9 s took 18 s on
      // a station short of memory, 2026-11-03, a reader started for it).
      if ("ready" in answer) {
        const ms = wall.now() - begun;
        if (ms >= 1_000) log.warn("readers", "a reader started slowly", { ms, line: line === this.asked ? "asked" : line === this.pages ? "pages" : line === this.log ? "log" : line === this.moved ? "moved" : "told", ...answer.ready });
        return;
      }
      // An abandoned read may finish while its worker is being stopped. Do not give that worker another read until it exits.
      if (slot.retiring) return;
      const asked = slot.held;
      slot.held = null;
      if (asked !== null && asked.ask.id === answer.id) {
        const now = wall.now();
        if (now - asked.at > SLOW_MS) log.warn("readers", "a read went slowly", { op: asked.ask.op, told: line.told, waitedMs: asked.took - asked.at, ms: now - asked.took });
        // A background read rests its line as long as it took before the next: one after another, a history brought on
        // read 40 MB of a transcript in 10 s on a station short of memory (2026-11-03), every write and read waiting on the
        // disk meanwhile.
        if (asked.background) line.rested = now + (now - asked.took);
        if (answer.text !== undefined) {
          const session = answer.prepareUpJobs;
          if (session !== undefined && !this.preparingUpJobs.has(session)) {
            this.preparingUpJobs.add(session);
            void this.prepareSessionUpJobs([session]).catch((error) => {
              if (!this.closed) log.warn("readers", "preparing a session's up jobs failed", { error: (error as Error).message });
            }).finally(() => this.preparingUpJobs.delete(session));
          }
          if (answer.prepareWorkspaceUpJobs && !this.preparingWorkspaceUpJobs) {
            this.preparingWorkspaceUpJobs = true;
            void this.prepareWorkspaceUpJobs().catch((error) => {
              if (!this.closed) log.warn("readers", "preparing workspace up jobs failed", { error: (error as Error).message });
            }).finally(() => { this.preparingWorkspaceUpJobs = false; });
          }
          asked.resolve(answer.text);
        }
        else asked.reject(new HttpError(answer.status ?? 500, answer.error ?? "read failed"));
      }
      this.pump(line);
    });
    worker.on("error", (error) => log.error("readers", "a reader failed", { error: error.message, reading: slot.held?.ask.op ?? null }));
    worker.on("exit", (code) => {
      slot.idle?.();
      line.slots = line.slots.filter((s) => s !== slot);
      slot.held?.reject(new HttpError(500, `the reader stopped (exit ${code})`));
      slot.held = null;
      this.pump(line);
    });
    line.slots.push(slot);
    return slot;
  }

  /// A reader with nothing to do goes after IDLE_MS, but not those of a line someone waits on (what devices ask, what
  /// streams tell): one started for a read took 3 s on a station short of memory (2026-11-03, its code read in again), the
  /// read itself 40 ms; the second of what devices ask, started as the first was busy, 16 s.
  private letGoLater(slot: Slot, line: Line) {
    if (slot.idle) return;
    // A thread's resources: the machine's time.
    slot.idle = wall.after(IDLE_MS, () => {
      slot.idle = undefined;
      if (slot.held !== null) return;
      if (this.kept(line)) return;
      void slot.worker.terminate();
    });
  }

  private kept(line: Line): boolean {
    return line === this.asked || line === this.told;
  }

  /// The readers of what devices ask and of what streams tell, started before either is asked anything: the first
  /// reads after the station starts (an update), and one beside a slow one, need not wait on them.
  warm() {
    for (const line of [this.asked, this.told]) while (!this.closed && line.slots.length < line.size) this.start(line);
  }

  /// The answer, as JSON text. `told`: what an event stream or a notice tells, read by the station's own reader.
  /// `background`: what a client brings onto its device in the background (POST /batch: a session's history page after
  /// page): after every other read waiting, and one at a time. In line with the rest, a sweep's pages (1 to 4 s each on
  /// a station, 2 to 7 MB of a Codex transcript read: 2026-11-03) held the sidebar, a session opened and the rest 10 s and
  /// more behind them, four at once from each device.
  read(op: string, args: unknown, lang: Ask["lang"], { told = false, background = false, signal }: { told?: boolean; background?: boolean; signal?: AbortSignal } = {}): Promise<string> {
    if (op === "usage") return this.usageRead(args, lang, told, signal);
    if (op === "outflowUsage") return this.outflowUsageRead(args, lang, told, signal);
    if (op === "outflowChats") return this.outflowChatsRead(args, lang, told, signal);
    if (op === "recentChatList") return this.recentChatRead(args, lang, told, signal);
    if (op === "sessions") return this.sessionListRead(args, lang, told, background, signal);
    return this.saidRead(op, args, lang, told, background || filling(op, args), signal);
  }

  /// Prepare the same old-chat boundary for a sidebar read or the auto-archive check; concurrent requests share work.
  prepareSaid(threads: readonly number[], signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    this.said ??= new SaidBuilder(join(this.data, "stillfail.db"), this.backfill);
    return this.covered(this.said.ready(threads, signal), signal);
  }

  /// Prepare only the requested chats' last messages in bounded slices for the archive and notices.
  prepareArchiveLast(threads: readonly number[], signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    // (by the MoonBit builder, station/mb's src/archivelast, where its program is there; else by the worker)
    const path = join(this.data, "stillfail.db"), mb = this.mbReader;
    this.archiveLast ??= new RequestedBuilder(path, this.backfill, undefined, "thread",
      "archive last message", (thread, cancel) => ({ thread, archiveLast: true, cancel }),
      mb === null ? null : { binary: mb, args: ["--builder", "archive-last", "--db", path] });
    return this.covered(this.archiveLast.ready(threads, signal), signal);
  }

  /// Share the bounded old-edit preparation between notices, and leave a cancelled request unattended.
  prepareLegacyEdits(signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    // (by the MoonBit builder, station/mb's src/legacy, where its program is there; else, and for a store whose merged
    // view must be switched first, by the worker)
    const path = join(this.data, "stillfail.db"), mb = this.mbReader;
    this.legacyEdits ??= new RequestedBuilder(path, this.backfill, undefined, "thread",
      "legacy edits", (thread, cancel) => ({ thread, legacyEdits: true, cancel }),
      mb === null ? null : { binary: mb, args: ["--builder", "legacy-edits", "--db", path] });
    return this.covered(this.legacyEdits.ready([0], signal), signal);
  }

  /// Read only one page for a guarded card outcome, behind interactive work and without a long-lived snapshot.
  async cardEditPage(thread: number, target: string, before: string | null, signal?: AbortSignal): Promise<CardEditPage> {
    return JSON.parse(await this.read("internalCardEditPage", { thread, target, before }, "zh", { background: true, signal })) as CardEditPage;
  }

  async cardMessagePage(thread: number, target: string, before: string | null, signal?: AbortSignal): Promise<CardMessagePage> {
    return JSON.parse(await this.read("internalCardMessagePage", { thread, target, before }, "zh", { background: true, signal })) as CardMessagePage;
  }

  /// Share the initial old-message scan between pages waiting for it.
  prepareLegacySaid(signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    // (by the MoonBit builder, station/mb's src/legacy, where its program is there; else by the worker)
    const path = join(this.data, "stillfail.db"), mb = this.mbReader;
    this.legacySaid ??= new RequestedBuilder(path, this.backfill, undefined, "thread",
      "legacy said", (thread, cancel) => ({ thread, legacySaid: true, cancel }),
      mb === null ? null : { binary: mb, args: ["--builder", "legacy-said", "--db", path] });
    return this.covered(this.legacySaid.ready([0], signal), signal);
  }

  /// Prepare only the requested old chats' letter-message keys, sharing progress and handover with other readers.
  preparePageLetters(threads: readonly number[], signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    // (by the MoonBit builder, station/mb's src/letters, where its program is there; else by the worker)
    const path = join(this.data, "stillfail.db"), mb = this.mbReader;
    this.pageLetters ??= new RequestedBuilder(path, this.backfill, undefined, "thread",
      "old page letters", (thread, cancel) => ({ thread, pageLetters: true, cancel }),
      mb === null ? null : { binary: mb, args: ["--builder", "page-letters", "--db", path] });
    return this.covered(this.pageLetters.ready(threads, signal), signal);
  }

  /// Prepare the old connection bindings for session reads and auto-archiving together.
  prepareSessionBindings(signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    this.sessionBindings ??= new SessionBindingsBuilder(join(this.data, "stillfail.db"), this.backfill);
    return this.covered(this.sessionBindings.readyIndex(signal), signal);
  }

  /// Prepare old pin and keep marks before automatic archiving.
  prepareArchiveMarks(signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    this.archiveMarks ??= new ArchiveMarkBuilder(join(this.data, "stillfail.db"), this.backfill);
    return this.covered(this.archiveMarks.readyIndex(signal), signal);
  }

  /// Prepare the jobs of the sessions an archive check is waiting on.
  prepareSessionUpJobs(sessions: readonly string[], signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    this.sessionUpJobs ??= new SessionUpJobsBuilder(join(this.data, "stillfail.db"), this.backfill);
    return this.covered(this.sessionUpJobs.ready(sessions, signal), signal);
  }

  /// Prepare old up jobs without holding the reader that supplied a fallback answer.
  prepareWorkspaceUpJobs(signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    this.workspaceUpJobs ??= new WorkspaceUpJobsBuilder(join(this.data, "stillfail.db"), this.backfill);
    return this.covered(this.workspaceUpJobs.ready(["all"], signal), signal);
  }

  /// Prepare a requested own chat's first member after handover, sharing and cancelling its bounded batches.
  prepareJobNameFirst(owner: string, thread: number, signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    const file = new URL(import.meta.url.endsWith(".ts") ? "./session-up-jobs-worker.ts" : "./read/session-up-jobs-worker.js", import.meta.url);
    this.jobNameFirst ??= new RequestedBuilder(join(this.data, "stillfail.db"), this.backfill, file, "scope", "job name first member",
      (key, cancel) => { const [session, first] = JSON.parse(key) as [string, number]; return { session, first, ...(cancel ? { cancel: true } : {}) }; });
    return this.covered(this.jobNameFirst.ready([JSON.stringify([owner, thread])], signal), signal);
  }

  /// Prepare only old threads whose widget sources a delivery needs.
  prepareWidgetSources(threads: readonly number[], signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    this.widgetSources ??= new WidgetSourcesBuilder(join(this.data, "stillfail.db"), this.backfill);
    return this.covered(this.widgetSources.ready(threads, signal), signal);
  }

  /// Prepare old card posts requested by a read; concurrent reads share this work.
  prepareCardPosts(threads: readonly number[], signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    this.cardPosts ??= new CardPostsBuilder(join(this.data, "stillfail.db"), this.backfill);
    return this.covered(this.cardPosts.ready(threads, signal), signal);
  }

  /// Prepare only the old closed cards requested by the read.
  prepareClosedCards(threads: readonly number[], signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    this.closedCards ??= new ClosedCardsBuilder(join(this.data, "stillfail.db"), this.backfill);
    return this.covered(this.closedCards.ready(threads, signal), signal);
  }

  /// Prepare only the old people-time lookups requested by the read.
  preparePeopleSince(threads: readonly number[], signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    this.peopleSince ??= new PeopleSinceBuilder(join(this.data,"stillfail.db"),this.backfill);
    return this.covered(this.peopleSince.ready(threads,signal),signal);
  }

  /// Prepare the sessions needed to choose a chat's copy destinations.
  prepareCcSessions(sessions: readonly string[], signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    this.ccIndex ??= new CcIndexBuilder(join(this.data, "stillfail.db"), this.backfill);
    return this.covered(this.ccIndex.ready(sessions, signal), signal);
  }

  /// Prepare the ordered chat names for only the sessions a caller needs.
  prepareSessionChatNames(sessions: readonly string[], signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    this.ccIndex ??= new CcIndexBuilder(join(this.data, "stillfail.db"), this.backfill);
    return this.covered(this.ccIndex.readyNames(sessions, signal), signal);
  }

  /// Prepare the latest conversation for only the old sessions a caller needs.
  prepareLatestThreads(sessions: readonly string[], signal?: AbortSignal): Promise<void> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    this.ccIndex ??= new CcIndexBuilder(join(this.data, "stillfail.db"), this.backfill);
    return this.covered(this.ccIndex.readyLatest(sessions, signal), signal);
  }

  private async saidRead(op: string, args: unknown, lang: Ask["lang"], told: boolean, background: boolean, signal?: AbortSignal): Promise<string> {
    while (!this.closed) {
      try { return await this.enqueue(op, args, lang, told, op === CHECKPOINT, background, signal); }
      catch (error) {
        if (!(error instanceof HttpError)) throw error;
        if (error.message === LEGACY_EDITS_PENDING) {
          await this.prepareLegacyEdits(signal);
          continue;
        }
        if (error.message === LEGACY_SAID_PENDING) {
          await this.prepareLegacySaid(signal);
          continue;
        }
        if (error.message.startsWith(PAGE_LETTER_PENDING)) {
          let threads: unknown;
          try { threads = JSON.parse(error.message.slice(PAGE_LETTER_PENDING.length)); } catch { throw error; }
          if (!Array.isArray(threads) || threads.length === 0 || !threads.every(Number.isSafeInteger)) throw error;
          await this.preparePageLetters(threads, signal);
          continue;
        }
        if (error.message.startsWith(LAST_MESSAGE_PENDING)) {
          let threads: unknown;
          try { threads = JSON.parse(error.message.slice(LAST_MESSAGE_PENDING.length)); } catch { throw error; }
          if (!Array.isArray(threads) || threads.length === 0 || !threads.every(Number.isSafeInteger)) throw error;
          await this.prepareArchiveLast(threads, signal);
          continue;
        }
        if (error.message === SESSION_BINDINGS_PENDING) {
          await this.prepareSessionBindings(signal);
          continue;
        }
        if (error.message.startsWith(CC_SESSIONS_PENDING)) {
          let sessions: unknown;
          try { sessions = JSON.parse(error.message.slice(CC_SESSIONS_PENDING.length)); } catch { throw error; }
          if (!Array.isArray(sessions) || sessions.length === 0 || !sessions.every((key) => typeof key === "string")) throw error;
          await this.prepareCcSessions(sessions, signal);
          continue;
        }
        if (error.message.startsWith(JOB_NAME_FIRST_PENDING)) {
          let key: unknown;
          try { key = JSON.parse(error.message.slice(JOB_NAME_FIRST_PENDING.length)); } catch { throw error; }
          if (!Array.isArray(key) || key.length !== 2 || typeof key[0] !== "string" || !Number.isSafeInteger(key[1])) throw error;
          await this.prepareJobNameFirst(key[0], key[1], signal);
          continue;
        }
        if (error.message.startsWith(CARD_POSTS_PENDING)) {
          let threads: unknown;
          try { threads = JSON.parse(error.message.slice(CARD_POSTS_PENDING.length)); } catch { throw error; }
          if (!Array.isArray(threads) || threads.length === 0 || !threads.every(Number.isSafeInteger)) throw error;
          await this.prepareCardPosts(threads, signal);
          continue;
        }
        if (error.message.startsWith(CLOSED_CARDS_PENDING)) {
          let threads: unknown;
          try { threads = JSON.parse(error.message.slice(CLOSED_CARDS_PENDING.length)); } catch { throw error; }
          if (!Array.isArray(threads) || threads.length === 0 || !threads.every(Number.isSafeInteger)) throw error;
          await this.prepareClosedCards(threads, signal);
          continue;
        }
        if (error.message.startsWith(PEOPLE_TIME_PENDING)) {
          let threads: unknown;
          try { threads = JSON.parse(error.message.slice(PEOPLE_TIME_PENDING.length)); } catch { throw error; }
          if (!Array.isArray(threads) || threads.length === 0 || !threads.every(Number.isSafeInteger)) throw error;
          await this.preparePeopleSince(threads,signal);
          continue;
        }
        if (error.message.startsWith(TURN_COUNT_PENDING)) {
          let sessions: unknown;
          try { sessions = JSON.parse(error.message.slice(TURN_COUNT_PENDING.length)); } catch { throw error; }
          if (!Array.isArray(sessions) || sessions.length === 0 || !sessions.every((key) => typeof key === "string")) throw error;
          this.turns ??= new TurnBuilder(join(this.data, "stillfail.db"), this.backfill);
          await this.covered(this.turns.ready(sessions, signal), signal);
          continue;
        }
        if (!error.message.startsWith(SAID_PENDING)) throw error;
        let threads: unknown;
        try { threads = JSON.parse(error.message.slice(SAID_PENDING.length)); } catch { throw error; }
        if (!Array.isArray(threads) || threads.length === 0 || !threads.every(Number.isSafeInteger)) throw error;
        await this.prepareSaid(threads, signal);
      }
    }
    throw new HttpError(502, "station stopping");
  }

  private async covered(check: Promise<void>, signal?: AbortSignal): Promise<void> {
    try {
      if (!signal) await check;
      else await new Promise<void>((resolve, reject) => {
        const abort = () => { signal.removeEventListener("abort", abort); reject(cancelled()); };
        if (signal.aborted) abort();
        else signal.addEventListener("abort", abort, { once: true });
        check.then(() => { signal.removeEventListener("abort", abort); resolve(); }, (error) => { signal.removeEventListener("abort", abort); reject(error); });
      });
    }
    catch (error) {
      if (error instanceof HttpError && error.message === "read cancelled") throw error;
      if (this.closed) throw new HttpError(502, "station stopping");
      throw new HttpError(503, (error as Error).message);
    }
  }

  private async usageRead(args: unknown, lang: Ask["lang"], told: boolean, signal?: AbortSignal): Promise<string> {
    const viewer = (args as { viewer?: InWorkspace | null } | null)?.viewer ?? null;
    const history = (args as { history?: unknown } | null)?.history === true;
    while (!this.closed) {
      try {
        return await this.enqueue("usage", args, lang, told, false, false, signal);
      } catch (error) {
        if (error instanceof HttpError && error.message === USAGE_DETAIL_PENDING) {
          this.startUsageIndex();
          await this.covered(this.minutes!.readyDetail(viewer), signal);
          continue;
        }
        if (error instanceof HttpError && error.message === USAGE_CHATS_PENDING && history) {
          this.startUsageIndex();
          await this.covered(this.minutes!.readyChats(viewer), signal);
          continue;
        }
        if (!(error instanceof HttpError) || error.message !== REMOTE_RUNS_PENDING) throw error;
        this.startUsageIndex();
        await this.covered(this.minutes!.readyRemote(), signal);
      }
    }
    throw new HttpError(502, "station stopping");
  }

  private async outflowUsageRead(args: unknown, lang: Ask["lang"], told: boolean, signal?: AbortSignal): Promise<string> {
    const ws = (args as { ws?: InWorkspace } | null)?.ws;
    const viewer: InWorkspace = ws !== null && typeof ws === "object" && typeof ws.workspace === "string"
      ? { workspace: ws.workspace, home: ws.home === true } : { workspace: "\u0000home", home: true };
    while (!this.closed) {
      try { return await this.enqueue("outflowUsage", args, lang, told, false, false, signal); }
      catch (error) {
        if (!(error instanceof HttpError) || error.message !== USAGE_DETAIL_PENDING) throw error;
        this.startUsageIndex();
        await this.covered(this.minutes!.readyDetail(viewer), signal);
      }
    }
    throw new HttpError(502, "station stopping");
  }

  private async outflowChatsRead(args: unknown, lang: Ask["lang"], told: boolean, signal?: AbortSignal): Promise<string> {
    const ws = (args as { ws?: InWorkspace } | null)?.ws;
    const viewer: InWorkspace = ws !== null && typeof ws === "object" && typeof ws.workspace === "string"
      ? { workspace: ws.workspace, home: ws.home === true } : { workspace: "\u0000home", home: true };
    while (!this.closed) {
      try { return await this.enqueue("outflowChats", args, lang, told, false, false, signal); }
      catch (error) {
        if (!(error instanceof HttpError) || error.message !== OUTFLOW_CHATS_PENDING) throw error;
        this.outflowChats ??= new OutflowChatIndex(join(this.data, "stillfail.db"), this.backfill);
        await this.covered(this.outflowChats.ready(viewer, signal), signal);
      }
    }
    throw new HttpError(502, "station stopping");
  }

  private async recentChatRead(args: unknown, lang: Ask["lang"], told: boolean, signal?: AbortSignal): Promise<string> {
    const a = args as { ws?: unknown; home?: unknown } | null;
    const ws = a?.ws, home = a?.home;
    if ((ws !== null && typeof ws !== "string") || (home !== null && typeof home !== "string"))
      throw new HttpError(400, "invalid recent chat scope");
    while (!this.closed) {
      try { return await this.saidRead("recentChatList", args, lang, told, false, signal); }
      catch (error) {
        if (!(error instanceof HttpError) || error.message !== RECENT_CHAT_PENDING) throw error;
        this.recentChats ??= new RecentChatBuilder(join(this.data, "stillfail.db"), this.backfill);
        await this.covered(this.recentChats.readyScope({ ws, home }, signal), signal);
      }
    }
    throw new HttpError(502, "station stopping");
  }

  private async sessionListRead(args: unknown, lang: Ask["lang"], told: boolean, background: boolean, signal?: AbortSignal): Promise<string> {
    while (!this.closed) {
      try { return await this.saidRead("sessions", args, lang, told, background, signal); }
      catch (error) {
        if (!(error instanceof HttpError) || error.message !== SESSION_LIST_PENDING) throw error;
        this.sessionList ??= new SessionListBuilder(join(this.data, "stillfail.db"), this.backfill);
        await this.covered(this.sessionList.readyIndex(signal), signal);
      }
    }
    throw new HttpError(502, "station stopping");
  }

  /// `first`: before the reads waiting (CHECKPOINT).
  private enqueue(op: string, args: unknown, lang: Ask["lang"], told: boolean, first = false, background = false, signal?: AbortSignal): Promise<string> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    if (signal?.aborted) return Promise.reject(cancelled());
    const line = op === CHECKPOINT ? this.log : this.mbReader !== null && MOVED.has(op) ? this.moved : told ? this.told : PAGES.has(op) ? this.pages : this.asked;
    // A session's history read where it was read before: that reader keeps where its reading stands in memory, another
    // reads it from disk (read/transcripts.ts).
    const session = (op === "timeline" || op === "transcriptState") && typeof (args as { key?: unknown })?.key === "string" ? (args as { key: string }).key : null;
    const home = session !== null ? this.homes.get(session) : undefined;
    const given = line !== this.moved ? args
      : MACHINE.has(op) ? { ...(args as object), roots: machineRoots() }
      : WORDED.has(op) ? { ...(args as object), words: wordsIn(lang), now: wall.now() }
      : args;
    const ask: Ask = { id: this.next++, op, args: given, lang, names: [], processes: [], clientKeys: [] };
    return new Promise((resolve, reject) => {
      let finished = false;
      const done = () => { finished = true; signal?.removeEventListener("abort", abort); };
      const asked: Asked = {
        ask, session, home: home !== undefined && line.slots.includes(home) ? home : null, background, at: wall.now(), took: 0,
        resolve: (text) => { if (!finished) { done(); resolve(text); } },
        reject: (error) => { if (!finished) { done(); reject(error); } },
      };
      const abort = () => {
        if (finished) return;
        const at = line.waiting.indexOf(asked);
        if (at >= 0) line.waiting.splice(at, 1);
        else {
          const slot = line.slots.find((s) => s.held === asked);
          if (slot) { slot.retiring = true; void slot.worker.terminate(); }
        }
        asked.reject(cancelled());
        if (at >= 0) this.pump(line);
      };
      signal?.addEventListener("abort", abort, { once: true });
      if (first) line.waiting.unshift(asked);
      else line.waiting.push(asked);
      this.pump(line);
    });
  }

  /// Reads in line go to its readers free, the first first (a session's history to its home reader when that one is
  /// free). Where bulk reads leave room (`room`, two readers or more), they hold one less than all: a later interactive
  /// read passes a waiting bulk read to the one left.
  private pump(line: Line) {
    if (this.closed) return;
    while (line.waiting.length > 0) {
      const bulkHeld = line.slots.filter((s) => s.held !== null && !interactive(s.held) && !s.held.background).length;
      const limited = line.room && line.size > 1 && bulkHeld >= line.size - 1;
      // A background read only when no other waits, none of its kind is being read, and a reader is left beside it.
      const foreground = line.waiting.findIndex((a) => !a.background);
      const free = line.slots.filter((s) => s.held === null).length + (line.size - line.slots.length);
      const resting = line.rested !== undefined && wall.now() < line.rested;
      const behind = resting || line.slots.some((s) => s.held?.background === true) || (free < 2 && line.size > 1) ? -1 : line.waiting.findIndex((a) => a.background);
      // (a background read of a kind someone waits on, a batch's chat, is a background read: one at a time, after a rest)
      const first = line.waiting.findIndex((a) => !a.background && (interactive(a) || a.ask.op === CHECKPOINT));
      const at = limited || first >= 0 ? first : foreground >= 0 ? foreground : behind;
      if (at < 0) {
        // A background read waiting while the line rests: looked at again once it has, however early a timer fires
        // (one armed for as long as the read took woke a moment before it was over, the read left waiting for good).
        if (resting && line.wake === undefined && line.waiting.some((a) => a.background)) {
          line.wake = wall.after(Math.max(1, line.rested! - wall.now()), () => {
            line.wake = undefined;
            this.pump(line);
          });
        }
        break;
      }
      const asked = line.waiting[at]!;
      const home = asked.home !== null && asked.home.held === null && line.slots.includes(asked.home) ? asked.home : null;
      const slot = home ?? line.slots.find((s) => s.held === null) ?? (line.slots.length < line.size ? this.start(line) : null);
      if (slot === null) break;
      line.waiting.splice(at, 1);
      this.give(slot, asked);
    }
    for (const slot of line.slots) if (slot.held === null) this.letGoLater(slot, line);
  }

  private give(slot: Slot, asked: Asked) {
    slot.idle?.();
    slot.idle = undefined;
    slot.held = asked;
    asked.took = wall.now();
    if (asked.session !== null) {
      // Where its reading will stand.
      this.homes.delete(asked.session);
      this.homes.set(asked.session, slot);
      while (this.homes.size > HOMES) this.homes.delete(this.homes.keys().next().value!);
    }
    asked.ask.names = [...this.names];
    asked.ask.processes = [...this.processes()];
    asked.ask.clientKeys = [...this.clientKeys()];
    if (!(slot.worker instanceof MbReader)) {
      const current = catalog();
      if (slot.catalogVersion !== current.version) {
        asked.ask.catalog = current.models;
        slot.catalogVersion = current.version;
      }
    }
    slot.worker.postMessage(asked.ask);
  }

  /// The store changed: what its log (the WAL) holds is written into the database shortly, by a reader (worker.ts
  /// `checkpoint`), one at a time, at most once a CHECKPOINT_MS. The main thread does not (store.ts): there it held
  /// every device while it reached the disk.
  checkpointSoon() {
    if (this.closed) return;
    if (this.checkpointing) return void (this.again = true);
    this.checkpointing = true;
    this.again = false;
    wall.after(CHECKPOINT_MS, () => {
      if (this.closed) return;
      this.read(CHECKPOINT, {}, "en")
        .catch((error) => log.warn("readers", "the database's log not written into it", { error: (error as Error).message }))
        .finally(() => {
          this.checkpointing = false;
          if (this.again) this.checkpointSoon();
        });
    });
  }

  /// Each running reader's JS heap in use, in bytes (for the memory log).
  heaps(): Promise<number[]> {
    return Promise.all([...this.asked.slots, ...this.told.slots, ...this.log.slots, ...this.pages.slots, ...this.moved.slots].map((s) => s.worker.getHeapStatistics().then((h) => h.used_heap_size, () => 0)));
  }

  close() {
    this.closed = true;
    if (this.minutes !== null) void this.minutes.close();
    if (this.outflowChats !== null) void this.outflowChats.close();
    if (this.said !== null) void this.said.close();
    if (this.archiveLast !== null) void this.archiveLast.close();
    if (this.legacyEdits !== null) void this.legacyEdits.close();
    if (this.legacySaid !== null) void this.legacySaid.close();
    if (this.pageLetters !== null) void this.pageLetters.close();
    if (this.turns !== null) void this.turns.close();
    if (this.recentChats !== null) void this.recentChats.close();
    if (this.sessionList !== null) void this.sessionList.close();
    if (this.sessionBindings !== null) void this.sessionBindings.close();
    if (this.archiveMarks !== null) void this.archiveMarks.close();
    if (this.sessionUpJobs !== null) void this.sessionUpJobs.close();
    if (this.workspaceUpJobs !== null) void this.workspaceUpJobs.close();
    if (this.jobNameFirst !== null) void this.jobNameFirst.close();
    if (this.widgetSources !== null) void this.widgetSources.close();
    if (this.cardPosts !== null) void this.cardPosts.close();
    if (this.closedCards !== null) void this.closedCards.close();
    if (this.peopleSince !== null) void this.peopleSince.close();
    if (this.ccIndex !== null) void this.ccIndex.close();
    for (const line of [this.asked, this.told, this.log, this.pages, this.moved]) {
      for (const asked of line.waiting.splice(0)) asked.reject(new HttpError(502, "station stopping"));
      for (const { worker } of line.slots) void worker.terminate();
    }
  }
}
