import { latest as latestNote } from "../agents/migrations.ts";
// All durable station state, in one SQLite file (the Rust station's store.rs ported: the same file, schema, SQL and rules, so
// the Rust station and this one open each other's data). One read-write connection, used synchronously; every method is
// the Rust `Store` method of the same name in camelCase, with its parameters in the same order.
//
// A thread is a log of entries that are appended and never changed: an edit is an entry of its own, which readers merge
// into the message it changes. A thread whose sessions are all archived is written out to a zstd file and read from
// there (store/archive.ts).
//
// What changed is told to subscribers once the method's writes are done (Store::with): the same StoreChange values at
// the same points as the Rust, in the same order.
import type { Clock } from "effect";
import { randomBytes } from "node:crypto";
import { existsSync, mkdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { DatabaseSync, type SQLInputValue, type StatementSync } from "node:sqlite";
import { liveClock } from "../ops/fibers.ts";
import { type Lang, stationLang, tr } from "../ops/i18n.ts";
import { readArchive, threadFile } from "./archive.ts";
import {
  type Attachment, type AutoTitle, type CardAnswer, type ChatShare, type EntryRow, type JobNotice, type JobRow, type Json, type Membership,
  type MessageRow, type NewMessage, type NewSession, type Opened, type PendingMessage, type Handed, type Letter, type AuthorKind, type Published, type ProcessRow, type ProfileStatus,
  type Quote, type SessionRow, type SessionStats, type SessionThread, type StoreChange, type ThreadRow, type ThreadSummary,
  type TurnFor, type TurnRow, type TurnSummary, type WidgetModel, AUTO, XSHARE_IDLE_MS, I64_MAX, MANUAL, STILLFAIL_SURFACE, attachment,
  byBytes, cardOf, jsonList, letterEntry, letterMessage, mergeEntries, optionsCard, parsed, quote, takeChars, toEntry, toJob, toMembership,
  CC_THREADS_SQL, LETTER_SQL, isLetter, liveShare, shareLive, toChatShare, toMessage, toOpened, toPublished, toSession, toSessionThread, toThread, toTurnSummary, JOBS_RUNNING, SESSION_JOBS, CARD_BEFORE, OPTIONS_BEFORE, CLOSED_SINCE, SESSION_OF_RUNTIME, PEOPLE_AT,
} from "./rows.ts";
import { SCHEMA, SCHEMA_VERSION, addArchiveColumns, addListState, addLetters, addThreadIndexes, addUsageCompactions, addAutoTitleColumns, addClientColumn, addLetterColumn, addQueueColumns, addSizeColumn, addUsageColumns, addUsageQuarters, addUsageTotals, addWaitWatchColumn, addWatchColumn, addWorkspaceColumns } from "./schema.ts";
import * as usage from "./usage.ts";
import { timed } from "./timed.ts";

// What the station's own periodic work asks, each by an index (schema.ts): their plans are tested to scan no table
// (and rows.ts JOBS_RUNNING and SESSION_JOBS, the readers' too).
export { JOBS_RUNNING, SESSION_JOBS };
export const LIVE_SESSIONS = "SELECT * FROM sessions WHERE archived_at IS NULL ORDER BY last_active_at DESC";
export const SESSION_COUNTS = "SELECT connect, ws, COUNT(*) AS n FROM sessions GROUP BY connect, ws";
export const ANY_RUNNING = "SELECT 1 AS r FROM sessions WHERE running = 1 LIMIT 1";
export const RUNNING_SESSIONS = "SELECT * FROM sessions WHERE running = 1";
export const JOBS_UP = "SELECT * FROM (SELECT * FROM jobs WHERE state = 'running' UNION ALL SELECT * FROM jobs WHERE state = 'exited' AND port IS NOT NULL) ORDER BY started_at DESC";
export const STATS_OF = `SELECT
    (SELECT COUNT(*) FROM turns t WHERE t.session_key = s.key) AS turns,
    ((SELECT COUNT(*) FROM deliveries d WHERE d.session = s.key AND d.delivered_at IS NULL) +
         (SELECT COUNT(*) FROM letter_deliveries d WHERE d.session = s.key AND d.delivered_at IS NULL)) AS pending,
    l.kind, l.outcome, l.declared, l.wait_seconds, l.wait_for, l.wait_watch, l.need, l.about_thread, l.about_n, l.about_ts, l.detail, l.started_at, l.ended_at
  FROM sessions s
  LEFT JOIN turns l ON l.id = (SELECT id FROM turns t2 WHERE t2.session_key = s.key ORDER BY t2.started_at DESC LIMIT 1)
  WHERE s.key = ?`;

// Each session's latest check of the last days (the archive policy's view) and a login's end (closeLoginCards), each by
// an index of its own (and rows.ts CARD_BEFORE, OPTIONS_BEFORE, CLOSED_SINCE: each list of chats', the readers' too).
// The checks are grouped by `+session`: by `session`, the station's SQLite went over every check in order of session.
export { CARD_BEFORE, CLOSED_SINCE, OPTIONS_BEFORE };
export const LATEST_DECISIONS =
  "SELECT id, session, created_at, result FROM decision_checks WHERE id IN (SELECT MAX(id) FROM decision_checks WHERE created_at >= ? GROUP BY +session) ORDER BY created_at, id";
export const LOGIN_CARDS =
  "SELECT thread, n, author FROM entries WHERE kind = 'message' AND author_kind = 'agent' AND card LIKE '%\"login\"%' AND card LIKE ? AND NOT EXISTS (SELECT 1 FROM closed_cards c WHERE c.thread = entries.thread AND c.n = entries.n)";

export * from "./rows.ts";
export { SCHEMA_VERSION } from "./schema.ts";
export { writeCompressed } from "./archive.ts";
export type { UsageCall, UsageFile, UsageFor, UsageGroup, UsageTurn } from "./usage.ts";

/// How much of the database the main connection keeps in memory, in KiB.
const CACHE_KIB = 32 * 1024;
/// How long the log may grow, in pages, before the main connection writes it into the database itself: well past what
/// the readers' checkpoints let it come to.
const WAL_PAGES = 10_000;
/// Archived threads whose entries are kept decompressed, the most recently read last.
const ARCHIVE_CACHE = 32;
/// How many of a job's notices are kept.
const JOB_NOTICES = 50;
/// How long a task another station's chat ran here is remembered (remote_runs): past the card's week and the usage
/// page's month.
const REMOTE_RUNS_MS = 90 * 24 * 3600 * 1000;
/// A chat shared with another workspace being used there is noted at most this often (chat_shares `used`).
const USED_NOTE_MS = 60_000;

type Changes = StoreChange[];
type Arg = SQLInputValue;
const flag = (b: boolean): number => (b ? 1 : 0);
const optFlag = (b: boolean | null | undefined): number | null => (b === null || b === undefined ? null : flag(b));

export class Store {
  readonly db: DatabaseSync;
  /// Where archived threads (and sessions' transcript copies) are written.
  readonly #archiveDir: string;
  /// Removed on close: an in-memory store's archive.
  readonly #temp: string | null;
  /// Where published snapshots are kept (docs/public-share.md): published/ beside the database (in an in-memory store's
  /// archive directory).
  readonly publishedDir: string;
  /// Entries of archived threads read lately (they never change), the most recent last.
  #archived: [number, EntryRow[]][] = [];
  #listeners: ((change: StoreChange) => void)[] = [];
  #statements = new Map<string, StatementSync>();
  /// How many times the decision checks or the archive policy were written in this process (decisionsVersion).
  #decisions = 0;

  /// Its time: what the rows say things happened at (a TestClock in tests).
  readonly clock: Clock.Clock;

  private constructor(db: DatabaseSync, archiveDir: string, temp: string | null, clock: Clock.Clock) {
    this.db = db;
    this.clock = clock;
    this.#archiveDir = archiveDir;
    this.#temp = temp;
    this.publishedDir = temp !== null ? join(temp, "published") : join(dirname(archiveDir), "published");
  }

  /// Opens the store at `path` (":memory:" for one of its own); archived threads go to `archive`, else `archive/`
  /// beside the database. A database of another schema version is refused.
  static open(path: string, archive: string | null = null, clock: Clock.Clock = liveClock): Store {
    const memory = path === ":memory:";
    if (!memory) mkdirSync(dirname(path), { recursive: true });
    // Busy for a moment (another process reading, the WAL recovered after a crash): waited for, from the first statement.
    // On the main thread, what takes long is said (timed.ts).
    const db = timed(new DatabaseSync(path, { timeout: 5000 }));
    try {
      // A commit waits for the log's write, not for the disk: what the last moments before a power cut wrote may be lost,
      // the database never damaged (WAL). Each live step of an agent commits a few times; with each its own flush to
      // disk, a machine short of memory and disk time held the main thread on them.
      db.exec("PRAGMA busy_timeout = 5000; PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;");
      // What this connection reads stays in its own memory (CACHE_KIB), not SQLite's 2 MB: on a machine short of memory
      // the system's file cache is the first to go, and each page read again from the disk there took some 50 ms (ccvm,
      // 2026-10-25: the main thread read 1,700 pages in six minutes, some of them six times over). This connection
      // writes alone, so what it keeps stays good across the readers' reads.
      // The log (the WAL) is written into the database off the main thread, by a reader (read/pool.ts `checkpoint`).
      // Left to SQLite, this connection did it itself at every thousandth page: one commit held every device for the
      // 6 s that took on ccvm (2026-10-25). Here only if the readers' fall behind, at WAL_PAGES.
      db.exec(`PRAGMA cache_size = -${CACHE_KIB}; PRAGMA wal_autocheckpoint = ${WAL_PAGES};`);
      const hasTables = db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sessions'").get() !== undefined;
      if (hasTables) {
        const version = (db.prepare("PRAGMA user_version").get() as Json).user_version;
        if (version !== SCHEMA_VERSION) {
          throw new Error(`${path} has schema version ${version}; this station uses ${SCHEMA_VERSION}. Move its data by hand, or move it aside.`);
        }
      }
      db.exec(SCHEMA);
      addArchiveColumns(db);
      addThreadIndexes(db);
      addLetterColumn(db);
      addClientColumn(db);
      addAutoTitleColumns(db);
      addWatchColumn(db);
      addQueueColumns(db);
      addSizeColumn(db);
      addWaitWatchColumn(db);
      addWorkspaceColumns(db);
      addUsageColumns(db);
      addUsageTotals(db);
      addUsageCompactions(db);
      addUsageQuarters(db);
      addListState(db);
      addLetters(db);
      db.exec(`PRAGMA user_version = ${SCHEMA_VERSION}`);
    } catch (e) {
      db.close();
      throw e;
    }
    if (archive !== null) return new Store(db, archive, null, clock);
    if (memory) {
      const dir = join(tmpdir(), `stillfail-archive-${randomBytes(8).toString("hex")}`);
      mkdirSync(dir, { recursive: true });
      return new Store(db, dir, dir, clock);
    }
    return new Store(db, join(dirname(path), "archive"), null, clock);
  }

  /// Now, by its clock.
  now(): number {
    return this.clock.currentTimeMillisUnsafe();
  }

  /// Closes the database (and removes an in-memory store's archive): the Rust's drop.
  close(): void {
    this.db.close();
    if (this.#temp !== null) rmSync(this.#temp, { recursive: true, force: true });
  }

  /// Hears what changes from now on; the function returned stops it.
  subscribe(listener: (change: StoreChange) => void): () => void {
    this.#listeners.push(listener);
    return () => {
      this.#listeners = this.#listeners.filter((l) => l !== listener);
    };
  }

  /// Where archived threads and transcript copies go (`threads/`, `transcripts/`).
  archiveDir(): string {
    return this.#archiveDir;
  }

  #send(changes: Changes): void {
    const listeners = this.#listeners;
    for (const change of changes) {
      for (const l of listeners) {
        try {
          l(change);
        } catch (e) {
          // A follower failing must not undo what was written, nor keep the others from hearing it.
          console.error("store listener:", e);
        }
      }
    }
  }

  /// Store::with: runs `run`, then tells what it says changed (also when it failed part way, as the Rust does).
  #with<T>(run: (changes: Changes) => T): T {
    const changes: Changes = [];
    try {
      return run(changes);
    } finally {
      this.#send(changes);
    }
  }

  /// rusqlite's transaction(): BEGIN (deferred), committed when `run` returns, rolled back when it throws.
  #tx<T>(run: () => T): T {
    this.db.exec("BEGIN");
    let result: T;
    try {
      result = run();
    } catch (e) {
      try {
        this.db.exec("ROLLBACK");
      } catch {
        // Already rolled back by SQLite.
      }
      throw e;
    }
    this.db.exec("COMMIT");
    return result;
  }

  #stmt(sql: string): StatementSync {
    let s = this.#statements.get(sql);
    if (s === undefined) {
      s = this.db.prepare(sql);
      this.#statements.set(sql, s);
    }
    return s;
  }
  #one(sql: string, ...args: Arg[]): Json | undefined {
    return this.#stmt(sql).get(...args);
  }
  #all(sql: string, ...args: Arg[]): Json[] {
    return this.#stmt(sql).all(...args);
  }
  /// How many rows it changed.
  #run(sql: string, ...args: Arg[]): number {
    return Number(this.#stmt(sql).run(...args).changes);
  }

  /// Announces a change the station keeps outside the database (e.g. a runtime process ending).
  notify(session: string): void {
    this.#send([{ type: "session", key: session }]);
  }

  // ── sessions ──

  getSession(key: string): SessionRow | null {
    const r = this.#one("SELECT * FROM sessions WHERE key = ?", key);
    return r ? toSession(r) : null;
  }

  sessionByToken(token: string): SessionRow | null {
    const r = this.#one("SELECT * FROM sessions WHERE token = ?", token);
    return r ? toSession(r) : null;
  }

  /// Every session, most recently active first.
  listSessions(): SessionRow[] {
    return this.#all("SELECT * FROM sessions ORDER BY last_active_at DESC").map(toSession);
  }

  /// The sessions shown (not archived), the latest active first: what the station's own periodic work goes over. The
  /// archived only grow with time; each is looked at again as it is shown.
  liveSessions(): SessionRow[] {
    return this.#all(LIVE_SESSIONS).map(toSession);
  }

  /// The sessions running a turn now (archived ones too).
  runningSessions(): SessionRow[] {
    return this.#all(RUNNING_SESSIONS).map(toSession);
  }

  /// The sessions in use: shown, or running a turn (one archived while at work too).
  sessionsInUse(): SessionRow[] {
    const live = this.liveSessions();
    const keys = new Set(live.map((s) => s.key));
    return [...live, ...this.runningSessions().filter((s) => !keys.has(s.key))];
  }

  /// How many sessions each connect has, in each workspace (null: the home one's), archived ones too: from the index
  /// alone, not every session's row.
  sessionCounts(): { connect: string; ws: string | null; n: number }[] {
    return this.#all(SESSION_COUNTS).map((r) => ({ connect: r.connect, ws: r.ws ?? null, n: r.n }));
  }

  /// Whether any session runs a turn now.
  anyRunning(): boolean {
    return this.#one(ANY_RUNNING) !== undefined;
  }

  /// Says the sessions of workspace `from` (null: those that say none, the home one's) are `to`'s (null: the home
  /// one's): when the station's home workspace changes (docs/multi-workspace.md).
  setSessionsWs(from: string | null, to: string | null): void {
    this.#with((changes) => {
      const keys = (from === null ? this.#all("SELECT key FROM sessions WHERE ws IS NULL") : this.#all("SELECT key FROM sessions WHERE ws = ?", from)).map((r) => r.key as string);
      if (from === null) this.#run("UPDATE sessions SET ws = ? WHERE ws IS NULL", to);
      else this.#run("UPDATE sessions SET ws = ? WHERE ws = ?", to, from);
      for (const key of keys) changes.push({ type: "session", key });
    });
  }

  insertSession(s: NewSession): void {
    this.#with((changes) => {
      this.#run(
        `INSERT INTO sessions (key, connect, scope, title, created_by, runtime, profile, profile_pinned, model, effort, workspace, cwd, runtime_session_id, token, created_at, last_active_at, told_notes, fast, ws)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        s.key, s.connect, s.scope ?? "thread", s.title ?? null, s.createdBy ?? null, s.runtime, s.profile, flag(s.profilePinned ?? false),
        s.model ?? null, s.effort ?? null, s.workspace, s.cwd ?? null, s.runtimeSessionId ?? null, s.token, s.createdAt, s.lastActiveAt,
        // A new session begins with today's instructions: no note is news to it.
        latestNote(), optFlag(s.fast), s.ws ?? null,
      );
      changes.push({ type: "session", key: s.key });
    });
  }

  /// Moves a session to another profile (its transcripts are shared by its runtime's profiles); `pinned` keeps it there.
  setSessionProfile(key: string, profile: string, pinned: boolean): void {
    this.#updateSession(key, "UPDATE sessions SET profile = ?1, profile_pinned = ?2 WHERE key = ?3", profile, flag(pinned), key);
  }

  /// A session's model and effort from its next start on (null: the runtime's default).
  setSessionModel(key: string, model: string | null, effort: string | null): void {
    this.#updateSession(key, "UPDATE sessions SET model = ?1, effort = ?2 WHERE key = ?3", model, effort, key);
  }

  setSessionFast(key: string, fast: boolean | null): void {
    this.#updateSession(key, "UPDATE sessions SET fast = ?1 WHERE key = ?2", optFlag(fast), key);
  }

  /// Whether it goes on afresh once its prompt cache is over (null: as the station is set).
  setSessionAfresh(key: string, afresh: boolean | null): void {
    this.#updateSession(key, "UPDATE sessions SET afresh = ?1 WHERE key = ?2", optFlag(afresh), key);
  }

  codexSessionFast(thread: string): boolean | null {
    const r = this.#one("SELECT fast FROM sessions WHERE runtime = 'codex' AND runtime_session_id = ?", thread);
    return r === undefined || r.fast === null ? null : r.fast !== 0;
  }

  setTitle(key: string, title: string | null): void {
    this.#updateSession(key, "UPDATE sessions SET title = ?1 WHERE key = ?2", title, key);
  }

  /// null: none now (its context cleared by hand); those it ran in stay in `runtime_sessions`. Where its context stands
  /// changes with it (read/usage.ts `usageNow`).
  setRuntimeSessionId(key: string, id: string | null): void {
    this.#with((changes) => {
      this.#run("UPDATE sessions SET runtime_session_id = ?1 WHERE key = ?2", id, key);
      changes.push({ type: "session", key }, { type: "conversation", key });
    });
  }

  /// When the conversation session `key` goes on with began: its runtime session's first record (`ranIn`), 0 where it
  /// has none (one from before they were recorded); null: none now (its context cleared, or never started).
  conversationSince(key: string): number | null {
    const r = this.#one("SELECT s.runtime_session_id AS id, r.at AS at FROM sessions s LEFT JOIN runtime_sessions r ON r.session_key = s.key AND r.id = s.runtime_session_id WHERE s.key = ?", key);
    if (r === undefined || r.id === null) return null;
    return r.at ?? 0;
  }

  /// How many entries the session's transcript has, as just read (sessions/live.ts): its summary says it from then on.
  /// Not a change of the session (nothing is told for it): the summary told next carries it.
  setTranscriptLength(key: string, n: number): void {
    this.#run("INSERT INTO transcript_lengths (session, n) VALUES (?1, ?2) ON CONFLICT (session) DO UPDATE SET n = excluded.n", key, n);
  }

  /// What a session's calls used, as just counted (usage/module.ts): its summary says it from then on. While it works
  /// its stream tells each change and the summary told next carries it; at rest (the count of its last turn comes in
  /// after it ended) the change is the session's, told as one unless `quiet`.
  setSessionUsage(key: string, usage: Json, quiet = false): void {
    const json = JSON.stringify(usage);
    if (this.#one("SELECT usage FROM session_usage WHERE session = ?", key)?.usage === json) return;
    const session = this.getSession(key);
    if (session === null) return;
    this.#with((changes) => {
      this.#run("INSERT INTO session_usage (session, usage) VALUES (?1, ?2) ON CONFLICT (session) DO UPDATE SET usage = excluded.usage", key, json);
      if (!quiet && !session.running) changes.push({ type: "session", key });
    });
  }

  /// What a session's calls used as last kept (`setSessionUsage`); null before any.
  sessionUsage(key: string): Json | null {
    const r = this.#one("SELECT usage FROM session_usage WHERE session = ?", key);
    return r ? JSON.parse(r.usage) : null;
  }

  /// Every session's key.
  sessionKeys(): string[] {
    return this.#all("SELECT key FROM sessions").map((r) => r.key as string);
  }

  /// A runtime session the session runs in, on `profile` (null: not known, a profile it had is kept).
  ranIn(key: string, id: string, profile: string | null): void {
    this.#run(
      `INSERT INTO runtime_sessions (session_key, id, profile, at) VALUES (?1, ?2, ?3, ?4)
       ON CONFLICT (session_key, id) DO UPDATE SET profile = COALESCE(excluded.profile, profile)`,
      key, id, profile, this.now(),
    );
  }

  /// The profile a runtime session of the session last ran on, if known.
  ranOn(key: string, id: string): string | null {
    return this.#one("SELECT profile FROM runtime_sessions WHERE session_key = ? AND id = ?", key, id)?.profile ?? null;
  }

  // ── chats shared with other workspaces (chat_shares; xshare/) ──

  /// What a chat (by the session key its link names) is shared with now, if anything: the workspaces whose share did
  /// not lapse (XSHARE_IDLE_MS unused).
  chatShare(session: string): ChatShare | null {
    const r = this.#one("SELECT * FROM chat_shares WHERE session = ?", session);
    return r ? liveShare(toChatShare(r), this.now()) : null;
  }

  /// Every chat shared with another workspace now, by its session key.
  chatShares(): Map<string, ChatShare> {
    const now = this.now();
    return new Map(this.#all("SELECT * FROM chat_shares").flatMap((r) => {
      const share = liveShare(toChatShare(r), now);
      return share === null ? [] : [[r.session, share] as const];
    }));
  }

  /// Whether a chat's share with one of `workspaces` (null: any) lapsed (unused too long), so is not on.
  chatShareLapsed(session: string, workspaces: string[] | null): boolean {
    const r = this.#one("SELECT * FROM chat_shares WHERE session = ?", session);
    const now = this.now();
    return r !== undefined && toChatShare(r).to.some((t) => (workspaces === null || workspaces.includes(t.workspace)) && !shareLive(t, now));
  }

  /// The workspaces some chat's share with lapsed: their stations are still answered why they read it no more.
  lapsedShareWorkspaces(): Set<string> {
    const now = this.now();
    return new Set(this.#all("SELECT * FROM chat_shares").flatMap((r) => toChatShare(r).to.filter((t) => !shareLive(t, now)).map((t) => t.workspace)));
  }

  /// The agents of `workspaces` read a chat or wrote to it: its share with them goes on from now (one lapsed stays
  /// so). Noted at most once a minute, no change to anything shown.
  usedChatShare(session: string, workspaces: string[]): void {
    const r = this.#one("SELECT * FROM chat_shares WHERE session = ?", session);
    if (!r) return;
    const now = this.now();
    const share = toChatShare(r);
    if (!share.to.some((t) => workspaces.includes(t.workspace) && shareLive(t, now) && now - t.used >= USED_NOTE_MS)) return;
    const to = share.to.map((t) => (workspaces.includes(t.workspace) && shareLive(t, now) ? { ...t, used: now } : t));
    this.#run("UPDATE chat_shares SET shared = ? WHERE session = ?", JSON.stringify(to), session);
  }

  /// The chats whose share with a workspace lapsed after `since` and by now: their views change (they are shared with
  /// it no longer). Answers when the next one lapses, null when none will.
  lapseChatShares(since: number): number | null {
    const now = this.now();
    let next: number | null = null;
    this.#with((changes) => {
      for (const r of this.#all("SELECT * FROM chat_shares")) {
        const ends = toChatShare(r).to.map((t) => t.used + XSHARE_IDLE_MS);
        if (ends.some((end) => end > since && end <= now)) {
          for (const t of this.sessionThreads(r.session)) changes.push({ type: "thread", id: t.thread.id, entries: [] });
          changes.push({ type: "session", key: r.session });
        }
        for (const end of ends) if (end > now && (next === null || end < next)) next = end;
      }
    });
    return next;
  }

  /// Shares a chat with other workspaces (`to`), or (none) no longer, each from now; its chat's views change.
  setChatShare(session: string, to: { workspace: string; name: string }[], write: boolean, by: string): void {
    this.#with((changes) => {
      if (to.length === 0) this.#run("DELETE FROM chat_shares WHERE session = ?", session);
      else {
        const now = this.now();
        this.#run(
          "INSERT INTO chat_shares (session, shared, write, by, at) VALUES (?1, ?2, ?3, ?4, ?5) ON CONFLICT (session) DO UPDATE SET shared = ?2, write = ?3, by = ?4, at = ?5",
          session, JSON.stringify(to.map((t) => ({ workspace: t.workspace, name: t.name, used: now }))), write ? 1 : 0, by, now,
        );
      }
      for (const t of this.sessionThreads(session)) changes.push({ type: "thread", id: t.thread.id, entries: [] });
      changes.push({ type: "session", key: session });
    });
  }

  // ── chats published as snapshots (published; publish/) ──

  /// A chat's published snapshots, the latest first.
  publishedOf(thread: number): Published[] {
    return this.#all("SELECT * FROM published WHERE thread = ? ORDER BY created_at DESC, id", thread).map(toPublished);
  }

  /// A published snapshot by its id.
  published(id: string): Published | null {
    const r = this.#one("SELECT * FROM published WHERE id = ?", id);
    return r ? toPublished(r) : null;
  }

  /// Records a snapshot written out to `publishedDir/<id>`; its chat's views change.
  addPublished(p: Published): void {
    this.#with((changes) => {
      this.#run(
        "INSERT INTO published (id, thread, key, title, created_by, by_name, created_at, upto, size) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        p.id, p.thread, p.key, p.title, p.by, p.byName, p.at, p.upto, p.size,
      );
      changes.push({ type: "thread", id: p.thread, entries: [] });
    });
  }

  /// Takes a snapshot down: its row and its files; its chat's views change. Whether there was one.
  removePublished(id: string): boolean {
    const p = this.published(id);
    if (p === null) return false;
    this.#with((changes) => {
      this.#run("DELETE FROM published WHERE id = ?", id);
      changes.push({ type: "thread", id: p.thread, entries: [] });
    });
    this.#removeSnapshot(id);
    return true;
  }

  #removeSnapshot(id: string): void {
    // An id is the station's own (base64url); anything else never names a directory here.
    if (/^[A-Za-z0-9_-]+$/.test(id)) rmSync(join(this.publishedDir, id), { recursive: true, force: true });
  }

  // ── chats agents opened (opened_chats; sessions/opened.ts) ──

  /// Records a chat opened for a session: by its station and key, and its parent's ('' for this station).
  insertOpened(o: Omit<Opened, "state" | "createdAt">): void {
    this.#run(
      `INSERT INTO opened_chats (child_station, child, parent_station, parent, key, title, link, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      o.childStation, o.child, o.parentStation, o.parent, o.key, o.title, o.link, this.now(),
    );
  }

  /// The chat a parent opened with `key` on `childStation`, if it has.
  openedWith(parentStation: string, parent: string, key: string, childStation: string): Opened | null {
    const r = this.#one("SELECT * FROM opened_chats WHERE parent_station = ? AND parent = ? AND key = ? AND child_station = ?", parentStation, parent, key, childStation);
    return r ? toOpened(r) : null;
  }

  /// Who opened session `child` of this station, if another agent did.
  openerOf(child: string): Opened | null {
    const r = this.#one("SELECT * FROM opened_chats WHERE child_station = '' AND child = ?", child);
    return r ? toOpened(r) : null;
  }

  /// How many chats `createdBy` started here since `since`, by runtime and model (what chat_create runs when it is told
  /// no model: sessions/model-choice.ts).
  modelsUsedBy(createdBy: string, since: number): { runtime: string; model: string | null; n: number }[] {
    return this.#all("SELECT runtime, model, COUNT(*) AS n FROM sessions WHERE created_by = ? AND created_at >= ? GROUP BY runtime, model", createdBy, since).map((r) => ({
      runtime: r.runtime as string,
      model: typeof r.model === "string" ? r.model : null,
      n: Number(r.n),
    }));
  }

  /// The chats this station's session `parent` opened, the first first.
  openedBy(parent: string): Opened[] {
    return this.#all("SELECT * FROM opened_chats WHERE parent_station = '' AND parent = ? ORDER BY created_at, rowid", parent).map(toOpened);
  }

  /// How a chat opened from here last ended a turn, as its station told.
  setOpenedState(childStation: string, child: string, state: string): void {
    this.#run("UPDATE opened_chats SET state = ? WHERE child_station = ? AND child = ?", state, childStation, child);
  }

  /// The runtime sessions the session has run in, the first first, ending with the one it runs in now.
  /// The session that went on with `runtime`'s session `id` (its current one, or one it ran in before), the latest
  /// active if more did; null if none did.
  sessionOfRuntime(runtime: string, id: string): SessionRow | null {
    const r = this.#one(SESSION_OF_RUNTIME, runtime, id);
    return r === undefined ? null : this.getSession(r.key);
  }

  runtimeSessions(key: string): string[] {
    const current = this.getSession(key)?.runtimeSessionId ?? null;
    const ids: string[] = this.#all("SELECT id FROM runtime_sessions WHERE session_key = ? ORDER BY at, rowid", key).map((r) => r.id);
    return current === null ? ids : [...ids.filter((id) => id !== current), current];
  }

  setRunning(key: string, running: boolean): void {
    this.#updateSession(key, "UPDATE sessions SET running = ?1, last_active_at = ?2 WHERE key = ?3", flag(running), this.now(), key);
  }

  #updateSession(key: string, sql: string, ...args: Arg[]): void {
    this.#with((changes) => {
      this.#run(sql, ...args);
      changes.push({ type: "session", key });
    });
  }

  touch(key: string): void {
    this.#run("UPDATE sessions SET last_active_at = ? WHERE key = ?", this.now(), key);
  }

  /// Hides a session from lists, or shows it again, with its own chat (ThreadRow.home); `by` is MANUAL or AUTO. Its
  /// threads' entries stay where they are (in the database); one an older station wrote out to a file is brought back.
  setArchived(key: string, archived: boolean, by: string): void {
    this.#with((changes) => this.#setArchived(key, archived, by, changes));
  }

  /// Out of lists by hand: the chat archived itself, or its sessions archived with one of them by hand. It takes no
  /// messages until shown again by hand; one archived by the station comes back with anything new said.
  manuallyArchived(thread: number): boolean {
    const r = this.#one("SELECT hidden_by FROM threads WHERE id = ?", thread);
    if (r === undefined || !this.#outOfLists(thread)) return false;
    if (r.hidden_by === MANUAL) return true;
    return this.#one("SELECT 1 FROM thread_sessions ts JOIN sessions s ON s.key = ts.session WHERE ts.thread = ? AND s.archived_by = ? LIMIT 1", thread, MANUAL) !== undefined;
  }

  /// Hides a chat of its own from lists, or shows it again; its sessions stay as they are.
  setThreadHidden(thread: number, hidden: boolean, by: string): void {
    this.#with((changes) => this.#setThreadHidden(thread, hidden, by, changes));
  }

  /// Names a chat, or (null) leaves it to be named by the first thing a person said in it.
  setThreadTitle(thread: number, title: string | null): void {
    this.#with((changes) => {
      this.#run("UPDATE threads SET title = ?1 WHERE id = ?2", title, thread);
      changes.push({ type: "thread", id: thread, entries: [] });
    });
  }

  /// The name a chat's agent gave it, as it stands: the name, the entry it came at, and how often it was changed since.
  autoTitle(thread: number): AutoTitle {
    const r = this.#one("SELECT auto_title, auto_title_n, auto_title_changes FROM threads WHERE id = ?", thread);
    return r ? { title: r.auto_title, n: r.auto_title_n ?? 0, changes: r.auto_title_changes } : { title: null, n: 0, changes: 0 };
  }

  /// Names a chat as its agent did: the first name, or (`changed`) another one, counted.
  setAutoTitle(thread: number, title: string, changed: boolean): void {
    this.#with((changes) => {
      const n = this.lastEntry(thread);
      this.#run(
        "UPDATE threads SET auto_title = ?1, auto_title_n = ?2, auto_title_changes = auto_title_changes + ?3 WHERE id = ?4",
        title, n, flag(changed), thread,
      );
      changes.push({ type: "thread", id: thread, entries: [] });
    });
  }

  /// How many messages people have written in a thread after entry `n`.
  peopleSaidAfter(thread: number, n: number): number {
    return this.#one("SELECT COUNT(*) AS c FROM entries WHERE thread = ? AND n > ? AND kind = 'message' AND author_kind = 'person'", thread, n).c;
  }

  /// When anyone last read a thread (moved their read position), in ms; null if nobody has.
  lastReadAt(thread: number): number | null {
    return this.#one("SELECT MAX(at) AS at FROM reads WHERE thread = ?", thread).at;
  }

  /// A session's own chat on the page (ThreadRow.home), if it has one.
  homeChat(session: string): ThreadRow | null {
    const r = this.#one("SELECT * FROM threads WHERE home = ? ORDER BY id LIMIT 1", session);
    return r ? toThread(r) : null;
  }

  /// Chats of their own on the page (no session's home) still in lists.
  chatsOfTheirOwn(): ThreadRow[] {
    return this.#all("SELECT * FROM threads WHERE surface = ? AND home IS NULL AND hidden_at IS NULL", STILLFAIL_SURFACE).map(toThread);
  }

  /// Forgets a session: its row, turns, deliveries, memberships and bindings, and the threads only it took part in,
  /// with their entries (or archive files) and reads.
  deleteSession(key: string): void {
    this.#with((changes) => {
      // Which workspace's it was, for those its going is told to.
      const ws: string | null = this.#one("SELECT ws FROM sessions WHERE key = ?", key)?.ws ?? null;
      const kept: number[] = [];
      const removed: number[] = [];
      const unpublished: string[] = [];
      this.#tx(() => {
        const threads: number[] = this.#all("SELECT thread FROM thread_sessions WHERE session = ?", key).map((r) => r.thread);
        this.#run("DELETE FROM thread_sessions WHERE session = ?", key);
        this.#run("DELETE FROM deliveries WHERE session = ?", key);
        this.#run("DELETE FROM letter_deliveries WHERE session = ?", key);
        this.#run("DELETE FROM turns WHERE session_key = ?", key);
        this.#run("DELETE FROM runtime_sessions WHERE session_key = ?", key);
        this.#run("DELETE FROM bindings WHERE session_key = ?", key);
        this.#run("DELETE FROM job_notices WHERE job_id IN (SELECT id FROM jobs WHERE session_key = ?)", key);
        this.#run("DELETE FROM jobs WHERE session_key = ?", key);
        this.#run("DELETE FROM widget_states WHERE session = ?", key);
        this.#run("DELETE FROM pins WHERE session = ?", key);
        this.#run("DELETE FROM transcript_lengths WHERE session = ?", key);
        this.#run("DELETE FROM session_usage WHERE session = ?", key);
        this.#run("DELETE FROM sessions WHERE key = ?", key);
        for (const thread of threads) {
          if (this.#one("SELECT 1 FROM thread_sessions WHERE thread = ? LIMIT 1", thread) !== undefined) {
            kept.push(thread);
            continue;
          }
          removed.push(thread);
          this.#run("DELETE FROM deliveries WHERE thread = ?", thread);
          this.#run("DELETE FROM entries WHERE thread = ?", thread);
          this.#run("DELETE FROM letter_deliveries WHERE thread = ?", thread);
          this.#run("DELETE FROM letters WHERE thread = ?", thread);
          this.#run("DELETE FROM reads WHERE thread = ?", thread);
          this.#run("DELETE FROM items WHERE thread = ?", thread);
          this.#run("DELETE FROM dismissed WHERE thread = ?", thread);
          this.#run("DELETE FROM closed_cards WHERE thread = ?", thread);
          this.#run("DELETE FROM kept_chats WHERE thread = ?", thread);
          // Its published snapshots go with it.
          for (const r of this.#all("SELECT id FROM published WHERE thread = ?", thread)) unpublished.push(r.id);
          this.#run("DELETE FROM published WHERE thread = ?", thread);
          this.#run("DELETE FROM threads WHERE id = ?", thread);
        }
      });
      for (const thread of removed) {
        this.#archived = this.#archived.filter(([id]) => id !== thread);
        rmSync(this.#threadFile(thread), { force: true });
      }
      for (const id of unpublished) this.#removeSnapshot(id);
      changes.push({ type: "sessionRemoved", key, ws });
      // Clients drop what they keep of the threads that went with it.
      for (const id of removed) changes.push({ type: "threadRemoved", id, ws });
      for (const id of kept) changes.push({ type: "thread", id, entries: [] });
    });
  }

  // ── single-session bindings ──

  /// The session a single-session connect delivers into, if one is bound.
  binding(connect: string): string | null {
    const r = this.#one("SELECT session_key FROM bindings WHERE connect = ?", connect);
    return r ? r.session_key : null;
  }

  /// Binds a connect to a session, or unbinds it (null) so its next message starts a new one.
  setBinding(connect: string, session: string | null): void {
    this.#with((changes) => {
      const before = this.binding(connect);
      if (session !== null) this.#run("INSERT OR REPLACE INTO bindings (connect, session_key) VALUES (?, ?)", connect, session);
      else this.#run("DELETE FROM bindings WHERE connect = ?", connect);
      const keys = [...new Set([before, session].filter((k): k is string => k !== null))].sort(byBytes);
      for (const key of keys) changes.push({ type: "session", key });
    });
  }

  /// Connects bound to each session (by session key, in the BTreeMap's order).
  listBindings(): Map<string, string[]> {
    const out = new Map<string, string[]>();
    for (const r of this.#all("SELECT connect, session_key FROM bindings")) out.set(r.session_key, [...(out.get(r.session_key) ?? []), r.connect]);
    return new Map([...out].sort(([a], [b]) => byBytes(a, b)));
  }

  // ── threads ──

  getThread(id: number): ThreadRow | null {
    const r = this.#one("SELECT * FROM threads WHERE id = ?", id);
    return r ? toThread(r) : null;
  }

  threadAt(surface: string, channel: string, threadTs: string): ThreadRow | null {
    const r = this.#one("SELECT * FROM threads WHERE surface = ? AND channel = ? AND thread_ts = ?", surface, channel, threadTs);
    return r ? toThread(r) : null;
  }

  /// The threads at CHANNEL/THREAD_TS on any surface (an agent names a conversation without its surface).
  threadsAt(channel: string, threadTs: string): ThreadRow[] {
    return this.#all("SELECT * FROM threads WHERE channel = ? AND thread_ts = ? ORDER BY id", channel, threadTs).map(toThread);
  }

  /// The thread at this address, made if new.
  openThread(surface: string, channel: string, threadTs: string, title: string | null, createdBy: string | null): ThreadRow {
    return this.openThreadOf(surface, channel, threadTs, title, createdBy, null);
  }

  /// The thread at this address, made if new as `home`'s own chat (ThreadRow.home).
  openThreadOf(surface: string, channel: string, threadTs: string, title: string | null, createdBy: string | null, home: string | null): ThreadRow {
    this.#run(
      "INSERT OR IGNORE INTO threads (surface, channel, thread_ts, title, created_by, created_at, home) VALUES (?, ?, ?, ?, ?, ?, ?)",
      surface, channel, threadTs, title, createdBy, this.now(), home,
    );
    const thread = this.threadAt(surface, channel, threadTs);
    if (thread === null) throw new Error(`thread ${surface} ${channel}/${threadTs} not made`);
    return thread;
  }

  /// The thread a platform message is in: the one it was said in, else the one it starts.
  threadOfMessage(surface: string, channel: string, ts: string): ThreadRow | null {
    const said = this.#one(
      "SELECT t.* FROM entries e JOIN threads t ON t.id = e.thread WHERE t.surface = ? AND t.channel = ? AND e.ts = ? LIMIT 1",
      surface, channel, ts,
    );
    return said ? toThread(said) : this.threadAt(surface, channel, ts);
  }

  /// Makes a session take part in a thread, posting through `connect`. False if it already did.
  joinThread(thread: number, session: string, connect: string): boolean {
    return this.#with((changes) => {
      const joined = this.#run("INSERT OR IGNORE INTO thread_sessions (thread, session, connect, joined_at) VALUES (?, ?, ?, ?)", thread, session, connect, this.now()) > 0;
      if (joined) {
        changes.push({ type: "session", key: session });
        changes.push({ type: "thread", id: thread, entries: [] });
      }
      return joined;
    });
  }

  threadSessions(thread: number): Membership[] {
    return this.#all("SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", thread).map(toMembership);
  }

  /// A thread of this session by the address the agent names it with, and how the session posts there.
  sessionThread(session: string, channel: string, threadTs: string): SessionThread | null {
    const r = this.#one(
      "SELECT t.*, ts.connect FROM thread_sessions ts JOIN threads t ON t.id = ts.thread WHERE ts.session = ? AND t.channel = ? AND t.thread_ts = ?",
      session, channel, threadTs,
    );
    return r ? toSessionThread(r) : null;
  }

  /// The threads a still.fail chat can copy people's messages to (rows.ts CC_THREADS_SQL).
  ccThreads(thread: number): SessionThread[] {
    return this.#all(CC_THREADS_SQL, thread).map(toSessionThread);
  }

  /// The threads a session takes part in, most recently joined first, with the connect it posts through in each.
  sessionThreads(session: string): SessionThread[] {
    return this.#all(
      "SELECT t.*, ts.connect FROM thread_sessions ts JOIN threads t ON t.id = ts.thread WHERE ts.session = ? ORDER BY ts.joined_at DESC, ts.rowid DESC",
      session,
    ).map(toSessionThread);
  }

  /// The thread a session last heard from: where the station's own notices go and whose connect's name the agent goes
  /// by. Falls back to the thread it joined last when it has heard nothing yet.
  latestThread(session: string): SessionThread | null {
    const heard = this.#one(
      `SELECT t.*, ts.connect FROM deliveries d JOIN threads t ON t.id = d.thread
       JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = d.session
       WHERE d.session = ? ORDER BY d.rowid DESC LIMIT 1`,
      session,
    );
    return heard ? toSessionThread(heard) : (this.sessionThreads(session)[0] ?? null);
  }

  /// Threads with their sessions, last entry, latest message and the viewer's unread count, most recently said in
  /// first: those of one session, one thread, or all.
  /// What a session's chat is called by: its thread said in last (as `listThreads` orders them) and, for one whose title may
  /// come from them (not a still.fail chat's: read/views.ts `titleOf`), its first person's words. Null when it has none.
  /// A row's lookups, not a list's: titles are asked of every chat a list of checks names.
  sessionChat(session: string): { thread: ThreadRow; firstText: string | null } | null {
    const r = this.#one(
      `SELECT t.* FROM thread_sessions m JOIN threads t ON t.id = m.thread WHERE m.session = ?
       ORDER BY (SELECT e.at FROM entries e WHERE e.thread = t.id ORDER BY e.n DESC LIMIT 1) DESC, t.created_at DESC, t.id DESC LIMIT 1`,
      session,
    );
    if (!r) return null;
    const thread = toThread(r);
    return { thread, firstText: thread.surface === STILLFAIL_SURFACE ? null : this.#firstText(thread.id) };
  }

  listThreads(viewer: string, session: string | null, thread: number | null): ThreadSummary[] {
    const base = "SELECT t.*, COALESCE(r.n, 0) AS read_n FROM threads t LEFT JOIN reads r ON r.thread = t.id AND r.viewer = ?1";
    const rows =
      thread !== null
        ? this.#all(`${base} WHERE t.id = ?2`, viewer, thread)
        : session !== null
          ? this.#all(`${base} WHERE t.id IN (SELECT thread FROM thread_sessions WHERE session = ?2)`, viewer, session)
          : this.#all(base, viewer);
    const summaries: ThreadSummary[] = rows.map((r) => {
      const t = toThread(r);
      const read: number = r.read_n;
      return {
        sessions: this.threadSessions(t.id),
        last: this.lastEntry(t.id),
        lastMessage: this.#lastSaid(t.id),
        read,
        unread: this.#unreadCount(viewer, t.id, read),
        people: this.#threadPeople(t.id, t.surface),
        firstText: this.#firstText(t.id),
        letters: this.#letterCount(t.id),
        lettersLast: this.lastLetter(t.id),
        thread: t,
      };
    });
    const said = (t: ThreadSummary) => t.lastMessage?.createdAt ?? 0;
    summaries.sort((a, b) => said(b) - said(a) || b.thread.createdAt - a.thread.createdAt || b.thread.id - a.thread.id);
    return summaries;
  }

  /// The thread's latest message as merged, for lists.
  lastMessage(thread: number): MessageRow | null {
    if (this.#isArchived(thread)) return mergeEntries(this.#archivedEntries(thread)).pop() ?? null;
    const r = this.#one("SELECT * FROM merged WHERE thread = ? ORDER BY n DESC LIMIT 1", thread);
    return r ? toMessage(r) : null;
  }

  /// How many letters the thread has (rows.ts isLetter), in either way.
  #letterCount(thread: number): number {
    // (those kept as entries before letters had their own log, and those of it)
    const apart = this.lastLetter(thread);
    if (this.#isArchived(thread)) {
      const keys = new Set(this.threadSessions(thread).map((m) => m.session));
      return apart + mergeEntries(this.#archivedEntries(thread)).filter((m) => isLetter(m, keys)).length;
    }
    return apart + (this.#one("SELECT letters FROM thread_state WHERE thread = ?", thread)?.letters ?? 0);
  }

  /// The thread's latest message that is not a letter (rows.ts isLetter), for lists: what they show and sort by.
  #lastSaid(thread: number): MessageRow | null {
    if (this.#isArchived(thread)) {
      const keys = new Set(this.threadSessions(thread).map((m) => m.session));
      return mergeEntries(this.#archivedEntries(thread)).findLast((m) => !isLetter(m, keys)) ?? null;
    }
    const r = this.#one("SELECT m.* FROM thread_state t JOIN merged m ON m.thread = t.thread AND m.n = t.said_n WHERE t.thread = ?", thread);
    return r ? toMessage(r) : null;
  }

  /// Messages after the viewer's read position that are not the viewer's own (nor of a Slack user they are), nor
  /// letters (rows.ts isLetter).
  unreadCount(viewer: string, thread: number): number {
    return this.#unreadCount(viewer, thread, this.readPosition(viewer, thread));
  }

  // ── entries ──

  /// Records something said. A message already recorded in that thread (Slack delivers to every connect in the channel,
  /// and redelivers) is the same message: its n comes back with `fresh` false and nothing changes.
  insertMessage(m: NewMessage): [number, boolean] {
    return this.#with((changes) => {
      const existing = this.#messageAt(m.thread, m.ts);
      if (existing !== null) return [existing.n, false];
      const card = m.card ?? undefined;
      const options = m.options ?? undefined;
      const entry = this.#append(
        {
          agentIdentity: undefined, thread: m.thread, n: 0, kind: "message", target: null, ts: m.ts, authorKind: m.authorKind,
          author: m.author, text: m.text, attachments: m.attachments ?? [], quotes: m.quotes ?? [], declared: m.declared ?? null,
          client: m.client ?? null, profile: m.profile ?? null, runtime: m.runtime ?? null,
          // An options card is kept as options too (what stations and clients from before cards read).
          options: options ?? (card !== undefined && card !== null && typeof card === "object" && card.type === "options" ? card.options : undefined),
          card: card ?? (options === undefined ? undefined : optionsCard(options)),
          at: m.at ?? this.now(),
          ...(m.letter !== undefined ? { letter: m.letter } : {}),
        },
        changes,
      );
      return [entry.n, true];
    });
  }

  /// A platform edit: an edit entry with the message's new words. The thread, or null for a message the station never
  /// recorded or one whose words did not change.
  editMessage(surface: string, channel: string, threadTs: string, ts: string, text: string): number | null {
    return this.#with((changes) => {
      const thread = this.threadAt(surface, channel, threadTs);
      if (thread === null) return null;
      const message = this.#messageAt(thread.id, ts);
      if (message === null || message.text === text) return null;
      this.#append(
        {
          agentIdentity: undefined, thread: message.thread, n: 0, kind: "edit", target: message.n, ts: null,
          authorKind: message.authorKind, author: message.author, text, attachments: message.attachments, quotes: message.quotes,
          declared: null, client: null, profile: null, runtime: null, options: undefined, card: undefined, at: this.now(),
        },
        changes,
      );
      return message.thread;
    });
  }

  /// Changes each time a decision check or the archive policy is written here: what is made of them (the overview's
  /// automatic decisions) is made again only then.
  decisionsVersion(): number {
    return this.#decisions;
  }

  recentDecisions(): Json[] {
    return this.#all("SELECT id, session, created_at, result FROM decision_checks ORDER BY id DESC LIMIT 30").map((r) => ({
      id: r.id, session: r.session, at: r.created_at, detail: parsed(r.result) ?? null,
    }));
  }

  /// Audit metadata only: no conversation text or API credentials.
  recordDecision(session: string, result: Json): void {
    this.#with((changes) => {
      this.#run("INSERT INTO decision_checks(session, created_at, result) VALUES (?, ?, ?)", session, this.now(), JSON.stringify(result));
      changes.push({ type: "decisionChecks" });
      this.#decisions++;
    });
  }

  /// The session's latest decision record, if any.
  lastDecision(session: string): Json | null {
    const row = this.#one("SELECT result FROM decision_checks WHERE session = ? ORDER BY id DESC LIMIT 1", session);
    return row ? (parsed(row.result) ?? null) : null;
  }

  /// Each session's latest check of those recorded since `since` (ms), the oldest first: what the archive policy's view
  /// counts (accounts/index.ts, sessions/archive-policy.ts).
  latestDecisionsSince(since: number): Json[] {
    return this.#all(LATEST_DECISIONS, since).map((r) => ({
      id: r.id, session: r.session, at: r.created_at, detail: parsed(r.result) ?? null,
    }));
  }

  /// A workspace's archive policy as last saved, and who saved it (`ws` null, or absent: the station's home workspace's);
  /// null until anyone has (the default then).
  archivePolicy(ws: string | null = null): { policy: Json; change: Json } | null {
    const r = this.#one("SELECT id, at, policy, author, summary FROM archive_policy WHERE ws IS ? ORDER BY id DESC LIMIT 1", ws);
    if (!r) return null;
    const policy = parsed(r.policy);
    if (!policy) return null;
    return { policy, change: { id: r.id, at: r.at, by: parsed(r.author) ?? null, summary: r.summary } };
  }

  /// A new archive policy of a workspace (null, or absent: the home one's), by whom, and what it changed.
  setArchivePolicy(policy: Json, author: Json, summary: string, ws: string | null = null): void {
    this.#with((changes) => {
      this.#run("INSERT INTO archive_policy(at, policy, author, summary, ws) VALUES (?, ?, ?, ?, ?)", this.now(), JSON.stringify(policy), JSON.stringify(author), summary, ws);
      changes.push({ type: "decisionChecks" });
      this.#decisions++;
    });
  }

  /// What the latest review found for a thread as it stood at `version`: the option picked, or why there is none.
  setArchiveVerdict(session: string, thread: number, version: number, verdict: Json): void {
    this.#with((changes) => {
      this.#run(
        "INSERT INTO archive_verdicts(thread, version, at, verdict) VALUES (?, ?, ?, ?) ON CONFLICT(thread) DO UPDATE SET version = excluded.version, at = excluded.at, verdict = excluded.verdict",
        thread, version, this.now(), JSON.stringify(verdict),
      );
      changes.push({ type: "session", key: session });
    });
  }

  /// The decision found nothing left to do in this thread as it stood at `version` (its last entry then).
  suggestArchive(session: string, thread: number, version: number): void {
    this.#with((changes) => {
      this.#run(
        "INSERT INTO archive_suggestions(thread, version, at) VALUES (?, ?, ?) ON CONFLICT(thread) DO UPDATE SET version = excluded.version, at = excluded.at",
        thread, version, this.now(),
      );
      changes.push({ type: "session", key: session });
    });
  }

  /// The decision no longer says so (it found something left, or could not tell).
  clearArchiveSuggestion(session: string, thread: number): void {
    this.#with((changes) => {
      if (this.#run("DELETE FROM archive_suggestions WHERE thread = ?", thread) > 0) changes.push({ type: "session", key: session });
    });
  }

  /// Whether the archive is recommended for the thread: the decision looked at it as it stands now.
  archiveSuggested(thread: number): boolean {
    let version: number | null = null;
    try {
      version = this.#one("SELECT version FROM archive_suggestions WHERE thread = ?", thread)?.version ?? null;
    } catch {
      // `.ok()`: a failing read is no suggestion.
    }
    return version !== null && version === this.lastEntry(thread);
  }

  /// The thread's last entry number, 0 before anything is said.
  lastEntry(thread: number): number {
    if (this.#isArchived(thread)) return this.#archivedEntries(thread).at(-1)?.n ?? 0;
    return this.#one("SELECT MAX(n) AS n FROM entries WHERE thread = ?", thread).n ?? 0;
  }

  /// Entries after n: what came since.
  entriesAfter(thread: number, n: number): EntryRow[] {
    return this.entriesBetween(thread, n + 1, I64_MAX);
  }

  /// The latest `limit` entries before n (the latest of all without it), oldest first.
  entriesBefore(thread: number, n: number | null, limit: number): EntryRow[] {
    const before = n ?? I64_MAX;
    if (this.#isArchived(thread)) {
      const entries = this.#archivedEntries(thread).filter((e) => e.n < before);
      return entries.slice(Math.max(0, entries.length - limit));
    }
    return this.#all("SELECT * FROM entries WHERE thread = ? AND n < ? ORDER BY n DESC LIMIT ?", thread, before, limit).map(toEntry).reverse();
  }

  /// Entries from n = `from` to n = `to`, both included: a gap.
  entriesBetween(thread: number, from: number | bigint, to: number | bigint): EntryRow[] {
    if (this.#isArchived(thread)) return this.#archivedEntries(thread).filter((e) => e.n >= from && e.n <= to);
    return this.#all("SELECT * FROM entries WHERE thread = ? AND n >= ? AND n <= ? ORDER BY n", thread, from, to).map(toEntry);
  }

  /// A message of the thread by its platform id, as merged.
  messageAt(thread: number, ts: string): MessageRow | null {
    return this.#messageAt(thread, ts);
  }

  /// The latest `limit` messages before n (the latest of all without it), as merged, oldest first.
  messagesBefore(thread: number, n: number | null, limit: number): MessageRow[] {
    const before = n ?? I64_MAX;
    if (this.#isArchived(thread)) {
      const messages = mergeEntries(this.#archivedEntries(thread)).filter((m) => m.n < before);
      return messages.slice(Math.max(0, messages.length - limit));
    }
    return this.#all("SELECT * FROM merged WHERE thread = ? AND n < ? ORDER BY n DESC LIMIT ?", thread, before, limit).map(toMessage).reverse();
  }

  // ── letters ──

  /// Keeps a letter in thread `thread`'s own log of them (schema.ts LETTERS), not among its entries: its n there. One
  /// coming in brings its chat back as a message does (#bringBack).
  insertLetter(l: { thread: number; ts: string; authorKind: AuthorKind; author: string; text: string; attachments?: Attachment[]; letter: Letter }): number {
    return this.#with((changes) => {
      let n = 0;
      const at = this.now();
      this.#tx(() => {
        n = (this.#one("SELECT MAX(n) AS n FROM letters WHERE thread = ?", l.thread).n ?? 0) + 1;
        this.#run(
          "INSERT INTO letters (thread, n, ts, author_kind, author, text, attachments, at, letter) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
          l.thread, n, l.ts, l.authorKind, l.author, l.text, jsonList<Attachment>(l.attachments ?? [], attachment), at, JSON.stringify(l.letter),
        );
      });
      const entry = letterEntry(this.#one("SELECT * FROM letters WHERE thread = ? AND n = ?", l.thread, n));
      changes.push({ type: "letters", id: l.thread, letters: [entry] });
      this.#bringBack(entry, changes);
      return n;
    });
  }

  /// The last letter of the thread's own log (0: none).
  lastLetter(thread: number): number {
    return this.#one("SELECT MAX(n) AS n FROM letters WHERE thread = ?", thread).n ?? 0;
  }

  /// Hands a letter of the thread's own log to sessions: those that did not have it yet (as `deliver` a message).
  deliverLetter(thread: number, n: number, sessions: string[]): string[] {
    return this.#with((changes) => {
      const added: string[] = [];
      for (const s of sessions) {
        if (this.#run("INSERT OR IGNORE INTO letter_deliveries (thread, n, session) VALUES (?, ?, ?)", thread, n, s) > 0) {
          added.push(s);
          changes.push({ type: "session", key: s });
        }
      }
      return added;
    });
  }

  // ── deliveries ──

  /// Hands a message to sessions. Those that did not have it yet.
  deliver(thread: number, n: number, sessions: string[]): string[] {
    return this.#with((changes) => {
      const added: string[] = [];
      for (const s of sessions) {
        if (this.#run("INSERT OR IGNORE INTO deliveries (thread, n, session) VALUES (?, ?, ?)", thread, n, s) > 0) {
          added.push(s);
          changes.push({ type: "session", key: s });
        }
      }
      return added;
    });
  }

  /// What the session has yet to read, as merged now, in the order it was handed over: its threads' messages, and the
  /// letters of their own logs among them by when each was kept.
  pendingMessages(session: string): PendingMessage[] {
    const said = this.#all(
      `SELECT m.*, t.surface, t.channel, t.thread_ts, ts.connect FROM deliveries d
       JOIN merged m ON m.thread = d.thread AND m.n = d.n JOIN threads t ON t.id = d.thread
       JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = d.session
       WHERE d.session = ? AND d.delivered_at IS NULL ORDER BY d.rowid`,
      session,
    ).map((r) => ({ message: toMessage(r), surface: r.surface, channel: r.channel, threadTs: r.thread_ts, connect: r.connect }));
    const letters = this.#all(
      `SELECT l.*, t.surface, t.channel, t.thread_ts, ts.connect FROM letter_deliveries d
       JOIN letters l ON l.thread = d.thread AND l.n = d.n JOIN threads t ON t.id = d.thread
       JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = d.session
       WHERE d.session = ? AND d.delivered_at IS NULL ORDER BY d.rowid`,
      session,
    ).map((r) => ({ message: letterMessage(r), surface: r.surface, channel: r.channel, threadTs: r.thread_ts, connect: r.connect }));
    if (letters.length === 0) return said;
    if (said.length === 0) return letters;
    // (each in the order handed over; the two together by when each was kept, a message first at the same time)
    const out: PendingMessage[] = [];
    let i = 0;
    let j = 0;
    while (i < said.length || j < letters.length) {
      if (j >= letters.length || (i < said.length && said[i]!.message.createdAt <= letters[j]!.message.createdAt)) out.push(said[i++]!);
      else out.push(letters[j++]!);
    }
    return out;
  }

  /// Marks messages read by the session.
  markDelivered(session: string, messages: Handed[]): void {
    this.#with((changes) => {
      const now = this.now();
      for (const { thread, n, apart } of messages) {
        this.#run(`UPDATE ${apart ? "letter_deliveries" : "deliveries"} SET delivered_at = ? WHERE thread = ? AND n = ? AND session = ? AND delivered_at IS NULL`, now, thread, n, session);
      }
      if (messages.length > 0) changes.push({ type: "session", key: session });
    });
  }

  /// Makes messages delivered to the session pending again: the runtime they were handed to ended before it could be
  /// sure to have read them.
  markUndelivered(session: string, messages: Handed[]): void {
    this.#with((changes) => {
      for (const { thread, n, apart } of messages) {
        this.#run(`UPDATE ${apart ? "letter_deliveries" : "deliveries"} SET delivered_at = NULL WHERE thread = ? AND n = ? AND session = ?`, thread, n, session);
      }
      if (messages.length > 0) changes.push({ type: "session", key: session });
    });
  }

  /// Threads the session has already read something from.
  heardThreads(session: string): Set<number> {
    return new Set(this.#all("SELECT DISTINCT thread FROM deliveries WHERE session = ? AND delivered_at IS NOT NULL", session).map((r) => r.thread));
  }

  sessionsWithPending(): string[] {
    return this.#all(
      "SELECT session FROM deliveries WHERE delivered_at IS NULL UNION SELECT session FROM letter_deliveries WHERE delivered_at IS NULL",
    ).map((r) => r.session);
  }

  /// Everyone who wrote in each session's threads (or one session's), as creator references, earliest first.
  participants(session: string | null): Map<string, string[]> {
    const sql = `SELECT ts.session, ts.connect, t.id, t.surface, t.archived_at FROM thread_sessions ts JOIN threads t ON t.id = ts.thread ${session !== null ? "WHERE ts.session = ?" : ""}`;
    const rows = session !== null ? this.#all(sql, session) : this.#all(sql);
    // Each person once per session, at the first time they wrote in any of its threads.
    const firsts = new Map<string, Map<string, number>>();
    for (const r of rows) {
      const authors: [string, number][] =
        r.archived_at !== null
          ? this.#archivedEntries(r.id).filter((e) => e.kind === "message" && e.authorKind === "person").map((e) => [e.author, e.at])
          : this.#all(PEOPLE_AT, r.id).map((a) => [a.author, a.at]);
      const refs = firsts.get(r.session) ?? new Map<string, number>();
      firsts.set(r.session, refs);
      for (const [author, at] of authors) {
        const reference = r.surface === STILLFAIL_SURFACE ? author : `slack:${r.connect}:${author}`;
        const first = refs.get(reference);
        if (first === undefined || at < first) refs.set(reference, at);
      }
    }
    const out = new Map<string, string[]>();
    for (const [key, refs] of [...firsts].sort(([a], [b]) => byBytes(a, b))) {
      if (refs.size === 0) continue;
      // In the BTreeMap's order, then (stably) by when.
      const sorted = [...refs].sort(([a], [b]) => byBytes(a, b)).sort(([, a], [, b]) => a - b);
      out.set(key, sorted.map(([r]) => r));
    }
    return out;
  }

  // ── reads ──

  /// How far a viewer has read a thread (an entry number), 0 if never.
  readPosition(viewer: string, thread: number): number {
    return this.#one("SELECT n FROM reads WHERE viewer = ? AND thread = ?", viewer, thread)?.n ?? 0;
  }

  /// Moves a viewer's read position forward (never back). Where it is now.
  setRead(viewer: string, thread: number, n: number): number {
    return this.#with((changes) => {
      this.#run(
        `INSERT INTO reads (viewer, thread, n, at) VALUES (?, ?, ?, ?)
         ON CONFLICT (viewer, thread) DO UPDATE SET n = MAX(n, excluded.n), at = excluded.at`,
        viewer, thread, n, this.now(),
      );
      const now = this.readPosition(viewer, thread);
      changes.push({ type: "read", viewer, thread, n: now });
      return now;
    });
  }

  // ── pins ──

  /// The chats a viewer pinned (by their session's key), with when.
  pins(viewer: string): Map<string, number> {
    return new Map(this.#all("SELECT session, at FROM pins WHERE viewer = ?", viewer).map((r) => [r.session, r.at]));
  }

  /// The chats someone pinned (by their session's key): the station does not archive them for idling.
  pinnedSessions(): Set<string> {
    return new Set(this.#all("SELECT DISTINCT session FROM pins").map((r) => r.session));
  }

  /// Pins a chat to the top of a viewer's list, or lets it go. Pinned again, it keeps when it was first pinned.
  setPin(viewer: string, session: string, pinned: boolean): void {
    this.#with((changes) => {
      if (pinned) this.#run("INSERT OR IGNORE INTO pins (viewer, session, at) VALUES (?, ?, ?)", viewer, session, this.now());
      else this.#run("DELETE FROM pins WHERE viewer = ? AND session = ?", viewer, session);
      changes.push({ type: "pins", viewer });
    });
  }

  /// When a chat was last relayed to each of a connect's channels and groups (by their ids).
  relayedTo(connect: string): Map<string, number> {
    return new Map(this.#all("SELECT channel, at FROM relayed_to WHERE connect = ?", connect).map((r) => [r.channel as string, r.at as number]));
  }

  /// A chat was relayed to a connect's channel or group now.
  noteRelayed(connect: string, channel: string): void {
    this.#run("INSERT INTO relayed_to (connect, channel, at) VALUES (?1, ?2, ?3) ON CONFLICT (connect, channel) DO UPDATE SET at = ?3", connect, channel, this.now());
  }

  /// Chats kept instead of offered for archiving. Null selects every viewer, for automatic archiving.
  keptChats(viewer: string | null): Set<number> {
    return new Set(this.#all("SELECT DISTINCT thread FROM kept_chats WHERE ?1 IS NULL OR viewer = ?1", viewer).map((r) => r.thread));
  }

  keepChat(viewer: string, thread: number): void {
    this.#with((changes) => {
      this.#run("INSERT OR IGNORE INTO kept_chats (viewer, thread) VALUES (?, ?)", viewer, thread);
      changes.push({ type: "dismissed", viewer });
    });
  }

  /// A chat kept by the viewer let go: offered for archiving again, and archived on its own once idle (unless someone
  /// else keeps it).
  unkeepChat(viewer: string, thread: number): void {
    this.#with((changes) => {
      this.#run("DELETE FROM kept_chats WHERE viewer = ? AND thread = ?", viewer, thread);
      changes.push({ type: "dismissed", viewer });
    });
  }

  // ── cards ──

  /// The thread's card still pending, if any: its latest post with a card (a newer one replaces an older one), as long
  /// as no person has written in the thread since. The post as merged, and its card.
  pendingCard(thread: number): [MessageRow, Json] | null {
    if (this.#isArchived(thread)) return null;
    // The latest of each kind (cards, and options from before cards), each read by its own index.
    const latest = (column: string): Json | undefined =>
      this.#one(`SELECT n, card, options FROM entries WHERE thread = ? AND kind = 'message' AND ${column} IS NOT NULL ORDER BY n DESC LIMIT 1`, thread);
    const a = latest("card");
    const b = latest("options");
    const asked = a && b ? (a.n >= b.n ? a : b) : (a ?? b);
    if (!asked) return null;
    const n: number = asked.n;
    const answered = this.#one("SELECT 1 FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? LIMIT 1", thread, n) !== undefined;
    const closed = this.#one("SELECT 1 FROM closed_cards WHERE thread = ? AND n = ?", thread, n) !== undefined;
    if (answered || closed) return null;
    const card = cardOf(asked.card, asked.options);
    if (card === undefined) return null;
    const m = this.#one("SELECT * FROM merged WHERE thread = ? AND n = ?", thread, n);
    return m ? [toMessage(m), card] : null;
  }

  /// The message an agent's need without a card asks with, while no person has written after it: the one its turn is
  /// about (`about`, an entry n), else the agent's latest message during the turn (`during`: from, to, ms); with the two
  /// messages before it. Null in an archived chat, or when that message has a card.
  askingMessage(thread: number, about: number | null, during: [number, number]): [MessageRow, MessageRow[]] | null {
    if (this.#isArchived(thread)) return null;
    const n: number | null =
      about ??
      this.#one("SELECT max(n) AS n FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'agent' AND at >= ? AND at <= ?", thread, during[0], during[1]).n;
    if (n === null) return null;
    const answered = this.#one("SELECT 1 FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? LIMIT 1", thread, n) !== undefined;
    // A post with a card is pendingCard's: one no longer pending was answered, closed or withdrawn.
    const carded = this.#one("SELECT 1 FROM entries WHERE thread = ? AND n = ? AND (card IS NOT NULL OR options IS NOT NULL)", thread, n) !== undefined;
    if (answered || carded) return null;
    const messages = this.messagesBefore(thread, n + 1, 3);
    const m = messages.pop();
    return m && m.n === n && m.authorKind === "agent" ? [m, messages] : null;
  }

  /// The cards answered since `since` (ms), whoever answered them: each a person's first message after a card (the
  /// thread's latest card then), or a choice that closed it (closed_cards, by a person: not its agent withdrawing it).
  answersSince(since: number): CardAnswer[] {
    const out: CardAnswer[] = [];
    const said = this.#all("SELECT thread, n FROM entries WHERE author_kind = 'person' AND kind = 'message' AND at >= ?", since);
    const askedBefore = (thread: number, n: number): number | null => {
      const card: number | null = this.#one(CARD_BEFORE, thread, n).n;
      const options: number | null = this.#one(OPTIONS_BEFORE, thread, n).n;
      // Option's max: None below any Some.
      return card === null ? options : options === null ? card : Math.max(card, options);
    };
    const cardAt = (thread: number, n: number): [MessageRow, Json] | null => {
      const row = this.#one("SELECT card, options FROM entries WHERE thread = ? AND n = ?", thread, n);
      const card = row ? cardOf(row.card, row.options) : undefined;
      if (card === undefined) return null;
      const m = this.#one("SELECT * FROM merged WHERE thread = ? AND n = ?", thread, n);
      return m ? [toMessage(m), card] : null;
    };
    for (const { thread, n } of said) {
      const asked = askedBefore(thread, n);
      if (asked === null) continue;
      // Only the first word after it answers it; one closed (by a choice or withdrawn) was answered then.
      const earlier = this.#one("SELECT 1 FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? AND n < ? LIMIT 1", thread, asked, n) !== undefined;
      const closed = this.#one("SELECT 1 FROM closed_cards WHERE thread = ? AND n = ?", thread, asked) !== undefined;
      if (earlier || closed) continue;
      const found = cardAt(thread, asked);
      if (!found) continue;
      const answer = this.#one("SELECT * FROM merged WHERE thread = ? AND n = ?", thread, n);
      if (!answer) continue;
      const a = toMessage(answer);
      out.push({ question: found[0], card: found[1], by: a.author, at: a.createdAt, answer: a });
    }
    for (const { thread, n, viewer: by, at } of this.#all(CLOSED_SINCE, since)) {
      const found = cardAt(thread, n);
      if (!found) continue;
      // Withdrawn by its own agent: no one answered it.
      if (found[0].author === by) continue;
      out.push({ question: found[0], card: found[1], by, at, answer: null });
    }
    return out;
  }

  /// The cards a viewer dismissed, as "thread:n" (read/store.ts's key for the Rust's (thread, n)).
  dismissed(viewer: string): Set<string> {
    return new Set(this.#all("SELECT thread, n FROM dismissed WHERE viewer = ?", viewer).map((r) => `${r.thread}:${r.n}`));
  }

  /// A viewer will not take up a card (the post at `n`): it leaves their list, on every device of theirs.
  dismiss(viewer: string, thread: number, n: number): void {
    this.#with((changes) => {
      this.#run("INSERT OR IGNORE INTO dismissed (viewer, thread, n, at) VALUES (?, ?, ?, ?)", viewer, thread, n, this.now());
      changes.push({ type: "dismissed", viewer });
    });
  }

  /// The author withdraws one exact card, without deleting its post or declaring the chat complete.
  withdrawCard(agent: string, thread: number, ts: string): boolean {
    return this.#with((changes) => {
      const r = this.#one(
        "SELECT n FROM entries WHERE thread = ? AND ts = ? AND kind = 'message' AND author_kind = 'agent' AND author = ? AND (card IS NOT NULL OR options IS NOT NULL)",
        thread, ts, agent,
      );
      if (r === undefined) return false;
      this.#run("INSERT OR IGNORE INTO closed_cards (thread, n, viewer, at) VALUES (?, ?, ?, ?)", thread, r.n, agent, this.now());
      changes.push({ type: "thread", id: thread, entries: [] });
      return true;
    });
  }

  /// The author restates its card on the post at `ts` (an edit entry with the post's words and `card`): what became of
  /// it, said on the post itself (a vault request's outcome). Whether the post was found.
  restateCard(agent: string, thread: number, ts: string, card: (was: Json) => Json): boolean {
    return this.#with((changes) => {
      const r = this.#one("SELECT card FROM entries WHERE thread = ? AND ts = ? AND kind = 'message' AND author_kind = 'agent' AND author = ? AND card IS NOT NULL", thread, ts, agent);
      const message = r === undefined ? null : this.#messageAt(thread, ts);
      if (r === undefined || message === null) return false;
      // The latest restated card, else the post's.
      const last = this.#one("SELECT card FROM entries WHERE thread = ? AND kind = 'edit' AND target = ? AND card IS NOT NULL ORDER BY n DESC LIMIT 1", thread, message.n);
      this.#append(
        {
          agentIdentity: undefined, thread, n: 0, kind: "edit", target: message.n, ts: null,
          authorKind: message.authorKind, author: message.author, text: message.text, attachments: message.attachments, quotes: message.quotes,
          declared: null, client: null, profile: null, runtime: null, options: undefined, card: card(parsed(last?.card ?? r.card)), at: this.now(),
        },
        changes,
      );
      return true;
    });
  }

  /// The login cards of a login (docs/remote-login.md: `{"type": "login", "login": <id>}`) still waiting: closed for
  /// everyone as the login ends, as their agent would withdraw them (nobody answered, nobody is woken: the station tells
  /// the agent itself). The sessions whose cards they were.
  closeLoginCards(login: string): string[] {
    return this.#with((changes) => {
      const rows = this.#all(LOGIN_CARDS, `%"login":${JSON.stringify(login)}%`);
      for (const r of rows) {
        this.#run("INSERT OR IGNORE INTO closed_cards (thread, n, viewer, at) VALUES (?, ?, ?, ?)", r.thread, r.n, r.author, this.now());
        changes.push({ type: "thread", id: r.thread, entries: [] });
      }
      return [...new Set(rows.map((r) => r.author as string))];
    });
  }

  /// Close this exact pending card for everyone. This writes no message or delivery: the agent stays asleep. A stale
  /// click cannot close a newer question or overwrite a newer turn's state. `lang` is lang.rs `spoken()`: the request's.
  closeCard(viewer: string, thread: number, n: number, option: string, lang: Lang = stationLang()): boolean {
    return this.#with((changes) => {
      // Told only when it got as far as closing it (one already closed says true and tells nothing, as the Rust).
      let closed: { agent: string; changed: boolean } | null = null;
      const done = this.#tx(() => {
        const offered = this.#one("SELECT card, options FROM entries WHERE thread = ? AND n = ? AND kind = 'message'", thread, n);
        const card = offered ? cardOf(offered.card, offered.options) : undefined;
        if (card === undefined) return false;
        const choices: Json[] = card !== null && Array.isArray(card.options) ? card.options : [];
        const closes = choices.some((o) => o !== null && typeof o === "object" && typeof o.label === "string" && o.label.trim() === option && o.action === "close");
        if (card === null || card.type !== "options" || !closes) return false;
        if (this.#one("SELECT 1 FROM closed_cards WHERE thread = ? AND n = ?", thread, n) !== undefined) return true;
        const asked = this.#one(
          "SELECT n, author, at FROM entries WHERE thread = ? AND kind = 'message' AND (card IS NOT NULL OR options IS NOT NULL) ORDER BY n DESC LIMIT 1",
          thread,
        );
        if (asked === undefined) return false;
        const answered = this.#one("SELECT EXISTS(SELECT 1 FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ?) AS e", thread, n).e !== 0;
        if (asked.n !== n || answered) return false;
        // Do not race the agent still composing its question / recording its ending.
        const composing = this.#one("SELECT ended_at IS NULL AS c FROM turns WHERE session_key = ? ORDER BY started_at DESC LIMIT 1", asked.author);
        if (composing !== undefined && composing.c !== 0) return false;
        this.#run("INSERT INTO closed_cards (thread, n, viewer, at) VALUES (?, ?, ?, ?)", thread, n, viewer, this.now());
        const changed = this.#run(
          `UPDATE turns SET declared = 'final', need = ?5, wait_seconds = NULL
           WHERE id = (SELECT id FROM turns WHERE session_key = ?1 ORDER BY started_at DESC LIMIT 1)
             AND declared IN ('block', 'need_help', 'need_human', 'need_decision') AND ended_at IS NOT NULL
             AND ((about_thread = ?2 AND about_n = ?3) OR (about_n IS NULL AND thread = ?2 AND started_at <= ?4))`,
          asked.author, thread, n, asked.at, tr(lang, "station.card.chosen", { option }),
        );
        closed = { agent: asked.author, changed: changed > 0 };
        return true;
      });
      const told = closed as { agent: string; changed: boolean } | null;
      if (told !== null) {
        if (told.changed) changes.push({ type: "session", key: told.agent });
        changes.push({ type: "thread", id: thread, entries: [] });
      }
      return done;
    });
  }

  // ── identities ──

  /// The Slack users a viewer said are them: their messages are the viewer's own.
  slackIdentities(viewer: string): string[] {
    return this.#all("SELECT slack_user FROM identities WHERE viewer = ? ORDER BY at", viewer).map((r) => r.slack_user);
  }

  /// Binds a Slack user to a viewer ("这是我"), or unbinds it. Nobody checks: it is the viewer's word.
  setSlackIdentity(viewer: string, user: string, bound: boolean): void {
    this.#with((changes) => {
      if (bound) this.#run("INSERT OR IGNORE INTO identities (viewer, slack_user, at) VALUES (?, ?, ?)", viewer, user, this.now());
      else this.#run("DELETE FROM identities WHERE viewer = ? AND slack_user = ?", viewer, user);
      changes.push({ type: "identities", viewer });
    });
  }

  // ── turns ──

  /// Whether the session has had a turn.
  hasTurns(session: string): boolean {
    return this.#one("SELECT EXISTS (SELECT 1 FROM turns WHERE session_key = ?) AS e", session).e !== 0;
  }

  startTurn(id: string, session: string, kind: string): void {
    this.startTurnFor(id, session, kind, { profile: null, person: null, thread: null });
  }

  /// Starts a turn for someone: the person whose message it answers, in that thread, on that profile. A turn nobody's
  /// message started goes on with the work of the one before it, so it is theirs.
  startTurnFor(id: string, session: string, kind: string, by: TurnFor): void {
    this.#with((changes) => {
      // The latest turn's alone (by the index on them): each says it, so one with none had none before it to say. Asked
      // for the latest that says it, a session that never had anyone's read back over every turn it had (1.4 s on ccvm).
      const before = (column: string) => `(SELECT ${column} FROM turns WHERE session_key = ?2 ORDER BY started_at DESC LIMIT 1)`;
      this.#run(
        `INSERT INTO turns (id, session_key, kind, started_at, profile, person, thread) VALUES (?1, ?2, ?3, ?4, ?5, COALESCE(?6, ${before("person")}), COALESCE(?7, ${before("thread")}))`,
        id, session, kind, this.now(), by.profile, by.person, by.thread,
      );
      changes.push({ type: "session", key: session });
    });
  }

  /// What a turn waits for once it ends as waiting (chat_state waiting `for`), in the agent's words, and whether that is
  /// its session's watch keeping on (`watch`).
  setWaitFor(id: string, what: string, watch: boolean): void {
    this.#run("UPDATE turns SET wait_for = ?, wait_watch = ? WHERE id = ?", what, watch ? 1 : 0, id);
  }

  /// The message a turn's state is about (`about`: thread, entry and ts), or none.
  setAbout(id: string, about: [number, number, string] | null): void {
    const [thread, n, ts] = about ?? [null, null, null];
    this.#run("UPDATE turns SET about_thread = ?, about_n = ?, about_ts = ? WHERE id = ?", thread, n, ts, id);
  }

  /// The last migration note a session was told; 0 for one never told any.
  toldNotes(key: string): number {
    return this.#one("SELECT told_notes FROM sessions WHERE key = ?", key)?.told_notes ?? 0;
  }

  setToldNotes(key: string, n: number): void {
    this.#run("UPDATE sessions SET told_notes = ? WHERE key = ?", n, key);
  }

  /// What a turn needs of a person once it ends as need_help (`need`), in the agent's words.
  setNeed(id: string, what: string): void {
    this.#run("UPDATE turns SET need = ? WHERE id = ?", what, id);
  }

  /// What a running turn says it ends in (`declared`, `waitSeconds` as `endTurn` takes them), on record as it is said: a
  /// station that dies before the turn ends (killed while handing over) leaves it for the next one to end the turn in.
  declareTurn(id: string, declared: string, waitSeconds: number | null): void {
    this.#run("UPDATE turns SET declared = ?, wait_seconds = ? WHERE id = ? AND ended_at IS NULL", declared, waitSeconds, id);
  }

  /// Ends a turn; `waitSeconds` is how long a turn ending as waiting waits at most.
  endTurn(id: string, outcome: string, detail: string | null, declared: string | null, waitSeconds: number | null): void {
    this.#with((changes) => {
      this.#run("UPDATE turns SET ended_at = ?, outcome = ?, detail = ?, declared = ?, wait_seconds = ? WHERE id = ?", this.now(), outcome, detail, declared, waitSeconds, id);
      const r = this.#one("SELECT session_key FROM turns WHERE id = ?", id);
      if (r !== undefined) changes.push({ type: "session", key: r.session_key });
    });
  }

  /// The session was stopped while it waited: its latest turn, if it ended waiting, is recorded as stopped instead
  /// (aborted, no longer waiting). Whether it was.
  stopWait(session: string): boolean {
    return this.#with((changes) => {
      const n = this.#run(
        `UPDATE turns SET outcome = 'aborted', declared = NULL, wait_seconds = NULL, detail = 'other: stopped while waiting'
         WHERE id = (SELECT id FROM turns WHERE session_key = ?1 ORDER BY started_at DESC LIMIT 1) AND declared = 'waiting' AND ended_at IS NOT NULL`,
        session,
      );
      if (n > 0) changes.push({ type: "session", key: session });
      return n > 0;
    });
  }

  /// The session's latest turn ended waiting though it did not complete (as stations recorded it before they recorded
  /// only the waits they keep): nothing waits for it, so it is recorded as it ended, not waiting.
  forgetWait(session: string): void {
    this.#with((changes) => {
      const n = this.#run(
        `UPDATE turns SET declared = NULL, wait_seconds = NULL
         WHERE id = (SELECT id FROM turns WHERE session_key = ?1 ORDER BY started_at DESC LIMIT 1) AND declared = 'waiting' AND ended_at IS NOT NULL
           AND outcome <> 'completed'`,
        session,
      );
      if (n > 0) changes.push({ type: "session", key: session });
    });
  }

  /// The session's latest turn.
  lastTurn(session: string): TurnSummary | null {
    const r = this.#one("SELECT * FROM turns WHERE session_key = ? ORDER BY started_at DESC, rowid DESC LIMIT 1", session);
    return r ? toTurnSummary(r) : null;
  }

  listTurns(session: string): TurnRow[] {
    return this.#all("SELECT * FROM turns WHERE session_key = ? ORDER BY started_at", session).map((r) => ({ id: r.id, summary: toTurnSummary(r) }));
  }

  /// For each of `keys` that is a session: its turn count, latest turn and undelivered messages as sessionStats says them,
  /// but not the first message it heard (`firstText` null: a read of its deliveries and their messages each). Each a
  /// row's lookups, for the station's own periodic work over the sessions at hand, not every session ever.
  statsOf(keys: Iterable<string>): Map<string, SessionStats> {
    const out = new Map<string, SessionStats>();
    for (const key of new Set(keys)) {
      const r = this.#one(STATS_OF, key);
      if (r !== undefined) out.set(key, { turns: r.turns, pending: r.pending, firstText: null, lastTurn: r.started_at === null ? null : toTurnSummary(r) });
    }
    return out;
  }

  /// Per session (or for one): turn count, the latest turn, undelivered messages and the first one it heard.
  sessionStats(key: string | null): Map<string, SessionStats> {
    const sql = `SELECT s.key,
         (SELECT COUNT(*) FROM turns t WHERE t.session_key = s.key) AS turns,
         ((SELECT COUNT(*) FROM deliveries d WHERE d.session = s.key AND d.delivered_at IS NULL) +
         (SELECT COUNT(*) FROM letter_deliveries d WHERE d.session = s.key AND d.delivered_at IS NULL)) AS pending,
         (SELECT substr(m.text, 1, 300) FROM session_first f JOIN merged m ON m.thread = f.thread AND m.n = f.n WHERE f.session = s.key) AS first_text,
         l.kind, l.outcome, l.declared, l.wait_seconds, l.wait_for, l.wait_watch, l.need, l.about_thread, l.about_n, l.about_ts, l.detail, l.started_at, l.ended_at
       FROM sessions s
       LEFT JOIN turns l ON l.id = (SELECT id FROM turns t2 WHERE t2.session_key = s.key ORDER BY t2.started_at DESC LIMIT 1)
       ${key !== null ? "WHERE s.key = ?" : ""}`;
    const rows = key !== null ? this.#all(sql, key) : this.#all(sql);
    return new Map(
      rows
        .map((r): [string, SessionStats] => [
          r.key,
          { turns: r.turns, pending: r.pending, firstText: r.first_text, lastTurn: r.started_at === null ? null : toTurnSummary(r) },
        ])
        .sort(([a], [b]) => byBytes(a, b)),
    );
  }

  // ── profile checks and quotas ──

  profileStatus(): Map<string, ProfileStatus> {
    return new Map(
      this.#all("SELECT profile, check_json, quota_json FROM profile_status")
        .map((r): [string, ProfileStatus] => [r.profile, { check: parsed(r.check_json) ?? null, quota: parsed(r.quota_json) ?? null }])
        .sort(([a], [b]) => byBytes(a, b)),
    );
  }

  /// Keeps a profile's check (its `checkedAt` says when).
  setProfileCheck(profile: string, check: Json): void {
    this.#run(
      `INSERT INTO profile_status (profile, check_json, checked_at) VALUES (?, ?, ?)
       ON CONFLICT (profile) DO UPDATE SET check_json = excluded.check_json, checked_at = excluded.checked_at`,
      profile, JSON.stringify(check), checkedAt(check),
    );
  }

  /// Keeps a profile's quota (its `checkedAt` says when).
  setProfileQuota(profile: string, quota: Json): void {
    this.#run(
      `INSERT INTO profile_status (profile, quota_json, quota_at) VALUES (?, ?, ?)
       ON CONFLICT (profile) DO UPDATE SET quota_json = excluded.quota_json, quota_at = excluded.quota_at`,
      profile, JSON.stringify(quota), checkedAt(quota),
    );
  }

  // ── runtime process groups ──

  recordProcess(pgid: number, startedAt: number, runtime: string, label: string): void {
    this.#with((changes) => {
      this.#run("INSERT OR REPLACE INTO processes (pgid, started_at, runtime, label) VALUES (?, ?, ?, ?)", pgid, startedAt, runtime, label);
      changes.push({ type: "processes" });
    });
  }

  forgetProcess(pgid: number): void {
    this.#with((changes) => {
      if (this.#run("DELETE FROM processes WHERE pgid = ?", pgid) > 0) changes.push({ type: "processes" });
    });
  }

  // ── background jobs ──

  /// A task another station's chat runs here began running (`session` its session's key, `remote:…`), at `at`; those
  /// older than REMOTE_RUNS_MS go.
  noteRemoteRun(job: string, session: string, at: number): void {
    this.#tx(() => {
      this.#run("INSERT OR IGNORE INTO remote_runs (job, at, session) VALUES (?, ?, ?)", job, at, session);
      this.#run("DELETE FROM remote_runs WHERE at < ?", at - REMOTE_RUNS_MS);
    });
  }

  insertJob(job: JobRow): void {
    this.#with((changes) => {
      this.#run(
        "INSERT INTO jobs (id, session_key, name, command, cwd, port, token, state, pgid, exit_code, started_at, ended_at, restarts, log, watch, queued, screen, size) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        job.id, job.sessionKey, job.name, job.command, job.cwd, job.port, job.token, job.state, job.pgid, job.exitCode, job.startedAt,
        job.endedAt, job.restarts, job.log, flag(job.watch), flag(job.queued === true), flag(job.screen === true),
        job.size ?? null,
      );
      changes.push({ type: "session", key: job.sessionKey });
      changes.push({ type: "job", id: job.id });
    });
  }

  /// A job started (again): running, in this process group.
  jobStarted(id: string, pgid: number, restarted: boolean): void {
    this.#jobUpdate(id, "UPDATE jobs SET state = 'running', pgid = ?1, exit_code = NULL, ended_at = NULL, restarts = restarts + ?2, queued = 0 WHERE id = ?3", pgid, flag(restarted), id);
  }

  /// A job ended: `state` exited, stopped or failed.
  jobEnded(id: string, state: string, exitCode: number | null): void {
    this.#jobUpdate(id, "UPDATE jobs SET state = ?1, exit_code = ?2, ended_at = ?3, pgid = NULL, queued = 0 WHERE id = ?4", state, exitCode, this.now(), id);
  }

  #jobUpdate(id: string, sql: string, ...args: Arg[]): void {
    this.#with((changes) => {
      this.#run(sql, ...args);
      this.#jobChanged(id, changes);
    });
  }

  /// Its session and the job, when the job is there.
  #jobChanged(id: string, changes: Changes): void {
    const r = this.#one("SELECT session_key FROM jobs WHERE id = ?", id);
    if (r !== undefined) {
      changes.push({ type: "session", key: r.session_key });
      changes.push({ type: "job", id });
    }
  }

  getJob(id: string): JobRow | null {
    const r = this.#one("SELECT * FROM jobs WHERE id = ?", id);
    return r ? toJob(r) : null;
  }

  jobByToken(token: string): JobRow | null {
    const r = this.#one("SELECT * FROM jobs WHERE token = ?", token);
    return r ? toJob(r) : null;
  }

  /// The jobs running, and the services stopped on their own that hold their port (an exited one with a port), the
  /// latest first: what a session has up.
  jobsUp(): JobRow[] {
    return this.#all(JOBS_UP).map(toJob);
  }

  /// A session's jobs (all sessions' with null), newest first. A session's by its index: asked as one statement for
  /// both (`?1 IS NULL OR session_key = ?1`), each read every job the station ever ran (5 s on ccvm with its pages put
  /// out, 2026-10-25).
  listJobs(session: string | null): JobRow[] {
    return (session === null ? this.#all("SELECT * FROM jobs ORDER BY started_at DESC") : this.#all(SESSION_JOBS, session)).map(toJob);
  }

  /// The jobs running now, as listJobs gives them (by the index on their state: the queue reads them at each look, and
  /// each second a command waits for the screen, jobs/jobs.ts `line`).
  jobsRunning(): JobRow[] {
    return this.#all(JOBS_RUNNING).map(toJob);
  }

  /// How many jobs are running now: other stations' tasks here (`remote_…`, jobs/remote.ts), web services (a port) and
  /// the other jobs, for what other stations are told of this one's load (jobs/load.ts).
  runningJobs(): { remote: number; jobs: number; services: number } {
    const r = this.#one(
      "SELECT COALESCE(SUM(substr(id, 1, 7) = 'remote_'), 0) AS remote, COALESCE(SUM(substr(id, 1, 7) <> 'remote_' AND port IS NOT NULL), 0) AS services, COUNT(*) AS n FROM jobs WHERE state = 'running'",
    );
    const remote = Number(r?.remote ?? 0);
    const services = Number(r?.services ?? 0);
    return { remote, services, jobs: Number(r?.n ?? 0) - remote - services };
  }

  /// What a job said (`stillfail-job notify`), kept for the pages: a job's latest words are how people see what it is up to.
  addJobNotice(id: string, text: string): void {
    this.#with((changes) => {
      this.#run("INSERT INTO job_notices (job_id, at, text) VALUES (?, ?, ?)", id, this.now(), text);
      // A job keeps its latest words only.
      this.#run(
        "DELETE FROM job_notices WHERE job_id = ?1 AND rowid NOT IN (SELECT rowid FROM job_notices WHERE job_id = ?1 ORDER BY at DESC, rowid DESC LIMIT ?2)",
        id, JOB_NOTICES,
      );
      this.#jobChanged(id, changes);
    });
  }

  /// A session's jobs that are over (stopped, failed, or ended by themselves; a service waiting to start again is not)
  /// taken off its record, with what they said: their ids and logs.
  clearEndedJobs(session: string): [string, string][] {
    return this.#with((changes) => {
      const gone = this.#tx(() => {
        const gone: [string, string][] = this.#all(
          "SELECT id, log FROM jobs WHERE session_key = ? AND (state IN ('stopped', 'failed') OR (state = 'exited' AND port IS NULL))",
          session,
        ).map((r) => [r.id, r.log]);
        for (const [id] of gone) {
          this.#run("DELETE FROM job_notices WHERE job_id = ?", id);
          this.#run("DELETE FROM jobs WHERE id = ?", id);
        }
        return gone;
      });
      if (gone.length > 0) {
        changes.push({ type: "session", key: session });
        for (const [id] of gone) changes.push({ type: "jobRemoved", id, session });
      }
      return gone;
    });
  }

  /// A job's notices, newest first (at most `limit`).
  jobNotices(id: string, limit: number): JobNotice[] {
    return this.#all("SELECT at, text FROM job_notices WHERE job_id = ? ORDER BY at DESC, rowid DESC LIMIT ?", id, limit).map((r) => ({ at: r.at, text: r.text }));
  }

  listProcesses(): ProcessRow[] {
    return this.#all("SELECT * FROM processes").map((r) => ({ pgid: r.pgid, startedAt: r.started_at, runtime: r.runtime, label: r.label }));
  }

  // ── widget states ──

  /// Keeps what a widget in one of the session's messages holds (`state`, JSON) and what of it is for the agent
  /// (`model`). A model other than the one last told is told again.
  putWidgetState(session: string, path: string, state: string, model: string | null): void {
    this.#run(
      `INSERT INTO widget_states (session, path, state, model, updated_at) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT (session, path) DO UPDATE SET state = excluded.state, model = excluded.model, updated_at = excluded.updated_at,
         told_at = CASE WHEN widget_states.model IS excluded.model THEN widget_states.told_at END`,
      session, path, state, model, this.now(),
    );
  }

  widgetState(session: string, path: string): string | null {
    return this.#one("SELECT state FROM widget_states WHERE session = ? AND path = ?", session, path)?.state ?? null;
  }

  /// The session's widget models it has not been told, with where each widget was posted (the latest of its threads'
  /// messages that carry the file).
  untoldWidgetModels(session: string): WidgetModel[] {
    const untold = this.#all("SELECT path, model FROM widget_states WHERE session = ? AND model IS NOT NULL AND told_at IS NULL ORDER BY updated_at, rowid", session);
    return untold.map(({ path, model }) => {
      const found = this.#one(
        `SELECT t.channel, t.thread_ts, json_extract(a.value, '$.name') AS name FROM merged m
         JOIN threads t ON t.id = m.thread JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = ?1, json_each(m.attachments) a
         WHERE m.attachments IS NOT NULL AND json_extract(a.value, '$.path') = ?2 ORDER BY m.created_at DESC LIMIT 1`,
        session, path,
      );
      const base: string = path.split(/[/\\]/).pop() ?? path;
      if (found === undefined) return { path, name: base, thread: null, model };
      const name = typeof found.name === "string" && found.name !== "" ? found.name : base;
      return { path, name, thread: [found.channel, found.thread_ts], model };
    });
  }

  /// The agent was told these (path, model): each is marked told unless its model changed since.
  markWidgetModelsTold(session: string, told: [string, string][]): void {
    const now = this.now();
    for (const [path, model] of told) {
      this.#run("UPDATE widget_states SET told_at = ? WHERE session = ? AND path = ? AND model = ?", now, session, path, model);
    }
  }

  // ── usage (store/usage.rs) ──

  /// Every transcript read for usage so far, by path.
  usageFiles(): Map<string, usage.UsageFile> {
    return usage.usageFiles(this.db);
  }

  /// Records a transcript's calls read up to `file.offset`, each with what it was for; a call recorded before keeps its
  /// row (its output grown, when the transcript wrote it again whole). How many were new.
  recordUsage(path: string, file: usage.UsageFile, runtime: string, calls: [usage.UsageCall, usage.UsageFor][]): number {
    return this.#tx(() => usage.recordUsage(this.db, path, file, runtime, calls));
  }

  /// A session's last `limit` main-thread calls, oldest first: the context each sent, on what (store/usage.ts).
  lastContexts(session: string, limit: number): usage.ContextCall[] {
    return usage.lastContexts(this.db, session, limit);
  }

  /// Where each model's context was compacted on this station since `since` (store/usage.ts).
  compactionPoints(since: number): Map<string, number> {
    return usage.compactionPoints(this.db, since);
  }

  /// Tells whoever follows the store that calls of `sessions` were recorded.
  usageChanged(sessions: string[]): void {
    this.#send([{ type: "usage", sessions }]);
  }

  /// Sessions whose transcripts may have grown since `since`: a turn running, or ended since then.
  usageActiveSessions(since: number): string[] {
    return usage.usageActiveSessions(this.db, since);
  }

  /// The turns of a session calls made from `from` until `until` (ms) were made in, oldest first, each with whom it
  /// worked for (store/usage.ts says how).
  usageTurns(session: string, from: number, until: number): usage.UsageTurn[] {
    return usage.usageTurns(this.db, session, from, until);
  }

  /// The calls from `from` until `to` (ms), added up by day in the asker's time zone and by thread, person, profile and
  /// model.
  usageGroups(from: number, to: number, utcOffsetMin: number): usage.UsageGroup[] {
    return usage.usageGroups(this.db, from, to, utcOffsetMin);
  }

  /// A session's calls, added up by model.
  usageOfSession(session: string): usage.UsageGroup[] {
    return usage.usageOfSession(this.db, session);
  }

  /// The threads usage names, each with the first thing a person said in it (for its title; none where its archive
  /// cannot be read). Those gone are left out.
  usageThreads(ids: number[]): [ThreadRow, string | null][] {
    const out: [ThreadRow, string | null][] = [];
    for (const id of ids) {
      const thread = this.getThread(id);
      if (thread === null) continue;
      let first: string | null = null;
      if (thread.title === null && thread.autoTitle === null) {
        try {
          first = this.#firstText(id);
        } catch {
          // `.ok().flatten()`: an archive that does not read gives none.
        }
      }
      out.push([thread, first]);
    }
    return out;
  }

  /// When the earliest call recorded was made.
  usageSince(): number | null {
    return usage.usageSince(this.db);
  }

  // ── Inner ──

  #unreadCount(viewer: string, thread: number, read: number): number {
    const t = this.getThread(thread);
    const slack = t ? t.surface !== STILLFAIL_SURFACE : true;
    const selves = [viewer];
    if (slack) selves.push(...this.slackIdentities(viewer));
    if (this.#isArchived(thread)) {
      const keys = new Set(this.threadSessions(thread).map((m) => m.session));
      return mergeEntries(this.#archivedEntries(thread)).filter((m) => m.n > read && !isLetter(m, keys) && !(m.authorKind === "person" && selves.includes(m.author))).length;
    }
    return this.#one(
      `SELECT COUNT(*) AS c FROM entries WHERE thread = ? AND n > ? AND kind = 'message'
       AND NOT (author_kind = 'person' AND author IN (SELECT value FROM json_each(?))) AND NOT ${LETTER_SQL}`,
      thread, read, JSON.stringify(selves),
    ).c;
  }

  /// Everyone who wrote in a thread, as creator references (a Slack user through a connect in it), earliest first.
  #threadPeople(thread: number, surface: string): string[] {
    const connect: string | null = this.#one("SELECT MIN(connect) AS c FROM thread_sessions WHERE thread = ?", thread).c;
    let authors: string[];
    if (this.#isArchived(thread)) {
      const seen = new Set<string>();
      authors = this.#archivedEntries(thread)
        .filter((e) => e.kind === "message" && e.authorKind === "person")
        .map((e) => e.author)
        .filter((a) => !seen.has(a) && (seen.add(a), true));
    } else {
      authors = this.#all("SELECT author FROM thread_people WHERE thread = ? ORDER BY first_n", thread).map((r) => r.author);
    }
    if (surface === STILLFAIL_SURFACE) return authors;
    return connect === null ? [] : authors.map((a) => `slack:${connect}:${a}`);
  }

  /// The first thing a person said in it (up to 300 characters).
  #firstText(thread: number): string | null {
    if (this.#isArchived(thread)) {
      const m = mergeEntries(this.#archivedEntries(thread)).find((m) => m.authorKind === "person");
      return m ? takeChars(m.text, 300) : null;
    }
    return this.#one("SELECT substr(m.text, 1, 300) AS t FROM thread_state s JOIN merged m ON m.thread = s.thread AND m.n = s.person_n WHERE s.thread = ?", thread)?.t ?? null;
  }

  #messageAt(thread: number, ts: string): MessageRow | null {
    if (this.#isArchived(thread)) return mergeEntries(this.#archivedEntries(thread)).find((m) => m.ts === ts) ?? null;
    const r = this.#one("SELECT * FROM merged WHERE thread = ? AND ts = ?", thread, ts);
    return r ? toMessage(r) : null;
  }

  /// Appends an entry as the thread's next, bringing an archived thread back first.
  #append(entry: EntryRow, changes: Changes): EntryRow {
    if (entry.kind === "message" && entry.authorKind === "agent") {
      const r = this.#one("SELECT model, effort FROM sessions WHERE key = ?", entry.author);
      entry.agentIdentity = r ? { model: r.model, effort: r.effort } : undefined;
    }
    if (this.#isArchived(entry.thread)) this.#restoreThread(entry.thread);
    this.#tx(() => {
      const n: number | null = this.#one("SELECT MAX(n) AS n FROM entries WHERE thread = ?", entry.thread).n;
      entry.n = (n ?? this.#lastKnown(entry.thread)) + 1;
      this.#insertEntry(entry);
    });
    changes.push({ type: "thread", id: entry.thread, entries: [{ ...entry }] });
    this.#bringBack(entry, changes);
    return entry;
  }

  #setArchived(key: string, archived: boolean, by: string, changes: Changes): void {
    const now = this.now();
    this.#tx(() => {
      if (archived) {
        this.#run("UPDATE sessions SET archived_at = ?, archived_by = ? WHERE key = ?", now, by, key);
      } else {
        const shown = by === MANUAL ? now : null;
        this.#run("UPDATE sessions SET archived_at = NULL, archived_by = NULL, shown_at = COALESCE(?, shown_at) WHERE key = ?", shown, key);
      }
      this.#run("UPDATE threads SET hidden_at = ?, hidden_by = ? WHERE home = ?", archived ? now : null, archived ? by : null, key);
    });
    for (const t of this.sessionThreads(key)) {
      this.#bringIn(t.thread.id);
      changes.push({ type: "thread", id: t.thread.id, entries: [] });
    }
    changes.push({ type: "session", key });
  }

  #setThreadHidden(thread: number, hidden: boolean, by: string, changes: Changes): void {
    const now = this.now();
    if (hidden) {
      this.#run("UPDATE threads SET hidden_at = ?, hidden_by = ? WHERE id = ?", now, by, thread);
    } else {
      const shown = by === MANUAL ? now : null;
      this.#run("UPDATE threads SET hidden_at = NULL, hidden_by = NULL, shown_at = COALESCE(?, shown_at) WHERE id = ?", shown, thread);
    }
    this.#bringIn(thread);
    changes.push({ type: "thread", id: thread, entries: [] });
  }

  /// Out of every list: archived itself, or none of its sessions shown.
  #outOfLists(thread: number): boolean {
    const r = this.#one("SELECT hidden_at FROM threads WHERE id = ?", thread);
    if (r === undefined) return false;
    if (r.hidden_at !== null) return true;
    const shown =
      this.#one("SELECT 1 FROM thread_sessions ts JOIN sessions s ON s.key = ts.session WHERE ts.thread = ? AND s.archived_at IS NULL LIMIT 1", thread) !== undefined;
    return !shown;
  }

  /// Brings a thread an older station wrote out to its archive file back into the database.
  #bringIn(thread: number): void {
    if (this.#isArchived(thread)) this.#restoreThread(thread);
  }

  /// Something new said in a thread brings what it is about back into lists: the chat, if the station archived it
  /// alone, and the sessions the station archived that hear it (every session of the thread) or said it. What was
  /// archived by hand stays archived: it takes no messages (manuallyArchived).
  #bringBack(entry: EntryRow, changes: Changes): void {
    if (entry.kind !== "message" || entry.authorKind === "ember") return;
    const thread = this.getThread(entry.thread);
    if (thread === null || this.manuallyArchived(thread.id)) return;
    const archived: string[] = this.#all(
      "SELECT key FROM sessions WHERE archived_at IS NOT NULL AND archived_by IS NOT ?1 AND (key IN (SELECT session FROM thread_sessions WHERE thread = ?2) OR key = ?3)",
      MANUAL,
      entry.thread,
      entry.authorKind === "agent" ? entry.author : null,
    ).map((r) => r.key);
    for (const key of archived) this.#setArchived(key, false, AUTO, changes);
    if (thread.hiddenAt !== null && thread.home === null) this.#setThreadHidden(thread.id, false, AUTO, changes);
  }

  /// The last entry number known of a thread with no entries: 0 for a new one. One whose archive file was lost is
  /// counted on from what was read and delivered of it, so that what clients keep of it is not numbered again.
  #lastKnown(thread: number): number {
    const r = this.#one(
      "SELECT MAX(n) AS n FROM (SELECT MAX(n) AS n FROM reads WHERE thread = ?1 UNION ALL SELECT MAX(n) FROM deliveries WHERE thread = ?1)",
      thread,
    );
    return r.n ?? 0;
  }

  // ── archive ──
  //
  // A chat out of every list keeps its entries in the database, as one in a list does: they are a few KB each (all of
  // ccvm's 26,000 come to some 20 MB), and every list read all of them alone, by an index, in some 10 ms. Stations before
  // wrote each such thread's entries out to `archive/threads/<id>.jsonl.zst` and took them out of the database
  // (`threads.archived_at`): then every list read each of those files (some 850 on ccvm, decompressed again whenever a
  // reader had let go of what it kept of them), and a thread said in again was read back first. Those files are read as
  // they are until each is brought back (`bringInArchived`, a few at a time after the station starts; at once when one
  // is said in or shown again).

  /// Brings back into the database up to `most` of the threads an older station wrote out to their archive files,
  /// the oldest first: how many it brought, and how many are left. Their entries are the same, so what clients keep of
  /// them stays true.
  bringInArchived(most: number): { brought: number; left: number } {
    const ids = this.#all("SELECT id FROM threads WHERE archived_at IS NOT NULL ORDER BY id LIMIT ?", most).map((r) => r.id as number);
    for (const id of ids) this.#restoreThread(id);
    return { brought: ids.length, left: this.#one("SELECT COUNT(*) AS c FROM threads WHERE archived_at IS NOT NULL").c };
  }

  /// The archived threads whose file is not there (lost with the disk it was on): each reads as one with no entries.
  lostArchives(): number[] {
    return this.#all("SELECT id FROM threads WHERE archived_at IS NOT NULL ORDER BY id")
      .map((r) => r.id as number)
      .filter((id) => !existsSync(this.#threadFile(id)));
  }

  #isArchived(thread: number): boolean {
    const r = this.#one("SELECT archived_at FROM threads WHERE id = ?", thread);
    return r !== undefined && r.archived_at !== null;
  }

  #threadFile(thread: number): string {
    return threadFile(this.#archiveDir, thread);
  }

  /// Loads an archived thread's entries back into the database and removes its file (one lost: none, and the thread is
  /// counted on from what was read and delivered of it, `#lastKnown`).
  #restoreThread(thread: number): void {
    const entries = this.#archivedEntries(thread);
    this.#tx(() => {
      for (const e of entries) this.#insertEntry(e);
      this.#run("UPDATE threads SET archived_at = NULL WHERE id = ?", thread);
    });
    this.#archived = this.#archived.filter(([id]) => id !== thread);
    rmSync(this.#threadFile(thread), { force: true });
  }

  /// An archived thread's entries, from its file.
  #archivedEntries(thread: number): EntryRow[] {
    const at = this.#archived.findIndex(([id]) => id === thread);
    if (at >= 0) {
      const [cached] = this.#archived.splice(at, 1);
      this.#archived.push(cached!);
      return cached![1];
    }
    const entries = readArchive(this.#threadFile(thread));
    if (this.#archived.length >= ARCHIVE_CACHE) this.#archived.shift();
    this.#archived.push([thread, entries]);
    return entries;
  }

  #insertEntry(e: EntryRow): void {
    this.#run(
      "INSERT INTO entries (thread, n, kind, target, ts, author_kind, author, text, attachments, quotes, declared, client, profile, runtime, options, card, at, agent_identity, letter) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      e.thread, e.n, e.kind, e.target, e.ts, e.authorKind, e.author, e.text,
      jsonList<Attachment>(e.attachments, attachment), jsonList<Quote>(e.quotes, quote),
      e.declared, e.client, e.profile, e.runtime,
      e.options === undefined ? null : JSON.stringify(e.options),
      e.card === undefined ? null : JSON.stringify(e.card),
      e.at,
      e.agentIdentity === undefined ? null : JSON.stringify(e.agentIdentity),
      e.letter === undefined ? null : JSON.stringify(e.letter),
    );
  }
}

/// `value.get("checkedAt").and_then(Value::as_i64)`.
function checkedAt(value: Json): number | null {
  const at = value !== null && typeof value === "object" && !Array.isArray(value) ? value.checkedAt : undefined;
  return typeof at === "number" && Number.isInteger(at) ? at : null;
}
