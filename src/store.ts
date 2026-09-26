// All durable ember state, in one SQLite file. Runtime transcripts stay in the
// runtimes' own homes; this records what ember needs to route and resume, and
// everything said in the threads its sessions take part in.
//
// A thread is a log of entries that are appended and never changed (see
// docs/station-storage.md): an edit is an entry of its own, which
// readers merge into the message it changes. A thread whose sessions are all
// archived is written out to a zstd file and read from there.
import { EventEmitter } from "node:events";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { zstdCompressSync, zstdDecompressSync } from "node:zlib";
import type { RuntimeKind } from "./config.ts";
import type { ProfileCheck } from "./profiles.ts";
import type { ProfileQuota } from "./quota.ts";

/** thread: started by one thread (multi-session connects); all: takes every thread of the connects bound to it (single-session). */
export type SessionScope = "thread" | "all";

export interface SessionRow {
  key: string;
  /** The connect that started it ("ember" for the page). Replies go through the connect each thread came from. */
  connect: string;
  scope: SessionScope;
  /** A name people gave it, for choosing among single-session sessions. */
  title: string | null;
  /**
   * Who started it: "slack:<connect>:<user>" for a chat message, an email for
   * someone on ember cloud, "local" for the station's own page; null if unknown.
   */
  createdBy: string | null;
  runtime: RuntimeKind;
  profile: string;
  model: string | null;
  /** Reasoning effort, as the connect set it when the session started; null for the runtime's default. */
  effort: string | null;
  runtimeSessionId: string | null;
  workspace: string;
  token: string;
  /** A turn was running when this was last written; true after a crash means the turn was cut off. */
  running: boolean;
  createdAt: number;
  lastActiveAt: number;
  /** Hidden from lists since then; null while shown. */
  archivedAt: number | null;
}

/** A place people talk: a Slack thread, or a chat on ember's page. */
export interface ThreadRow {
  id: number;
  /** "slack:<team id>" (or "slack:<connect id>" while the team is unknown), or "ember". */
  surface: string;
  /** Slack channel id; "EMBER" on the page. */
  channel: string;
  threadTs: string;
  title: string | null;
  createdBy: string | null;
  createdAt: number;
}

/** A session in a thread, and the connect it posts there through. */
export interface Membership {
  thread: number;
  session: string;
  connect: string;
  joinedAt: number;
}

export type AuthorKind = "person" | "agent" | "ember";

export type EntryKind = "message" | "edit";

/** One entry of a thread's log. Entries are only ever appended; they go only with their whole thread. Nothing said is taken back: ember has no delete. */
export interface EntryRow {
  thread: number;
  /** 1, 2, 3 … within the thread, no gaps. */
  n: number;
  kind: EntryKind;
  /** edit: the n of the message it changes. */
  target: number | null;
  /** message: the platform's id (Slack ts; ember makes Slack-like ones), unique in the thread. */
  ts: string | null;
  /** message: who said it; edit: whose message it changes. */
  authorKind: AuthorKind;
  /** person: Slack user id, email or "local"; agent: session key; ember: "ember". */
  author: string;
  /** Markdown. */
  text: string | null;
  /** message and edit: the files and quotes it has (an edit gives the message's whole new version). */
  attachments: Attachment[];
  quotes: Quote[];
  /** message: an agent's final or block, posted with it. */
  declared: string | null;
  at: number;
}

/** A message as it reads now: its latest edit's words, files and quotes. */
export interface MessageRow {
  thread: number;
  /** Its entry's n. */
  n: number;
  ts: string;
  authorKind: AuthorKind;
  author: string;
  text: string;
  attachments: Attachment[];
  quotes: Quote[];
  declared: string | null;
  createdAt: number;
  /** When its latest edit came; null if never edited. */
  editedAt: number | null;
}

/** A message a session has yet to read, with where it was said and how the session hears that thread. */
export interface PendingMessage extends MessageRow {
  surface: string;
  channel: string;
  threadTs: string;
  /** The connect the session hears this thread through. */
  connect: string;
}

/** A passage quoted from an earlier message, and what the sender says about it. */
export interface Quote {
  author: string; text: string; comment: string;
  /** The quoted message's id (its ts) and whose it is, so the agent knows exactly what is quoted. */
  ts?: string; role?: "agent" | "person";
}

/** A file someone sent to a session; `path` is where the agent finds it on the station. */
export interface Attachment {
  name: string; path: string; size: number;
  /** An image's pixel size, measured by the sender, so the page can hold its place before it loads. */
  width?: number; height?: number;
}

/** A thread for listings: who takes part, the last thing said, and how much the viewer has not read. */
export interface ThreadSummary extends ThreadRow {
  sessions: Membership[];
  /** The thread's last entry number, 0 before anything is said: follow it with entriesAfter. */
  last: number;
  /** The latest message as merged, for lists. */
  lastMessage: MessageRow | null;
  /** The viewer's read position (an entry number), 0 if never read. */
  read: number;
  /** Messages after the read position that are not the viewer's own (nor of a Slack user they are). */
  unread: number;
  /** Everyone who wrote in it, as creator references, earliest first. */
  people: string[];
  /** The first thing a person said in it (the start of it), for a title. */
  firstText: string | null;
}

export interface TurnSummary {
  kind: string;
  outcome: string | null;
  declared: string | null;
  detail: string | null;
  startedAt: number;
  endedAt: number | null;
}

export interface SessionStats {
  turns: number;
  pending: number;
  firstText: string | null;
  lastTurn: TurnSummary | null;
}

export interface ProfileStatus {
  check: ProfileCheck | null;
  quota: ProfileQuota | null;
}

export type TurnKind = "input" | "nudge" | "resume";

/** The page's own threads live on this surface, in this channel. */
export const EMBER_SURFACE = "ember";

/**
 * Bump on schema changes. A database of another version is refused: there is one station, and its data is moved by
 * hand when the schema changes (no migrations are kept in the code).
 */
const SCHEMA_VERSION = 11;

/** Where a Slack connect's threads live: its team, or the connect itself while the team is unknown. */
export function slackSurface(connect: string, teamId: string | null | undefined): string {
  return teamId ? `slack:${teamId}` : `slack:${connect}`;
}

const THREADS = `
CREATE TABLE IF NOT EXISTS threads (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  surface TEXT NOT NULL,
  channel TEXT NOT NULL,
  thread_ts TEXT NOT NULL,
  title TEXT,
  created_by TEXT,
  created_at INTEGER NOT NULL,
  archived_at INTEGER,
  UNIQUE (surface, channel, thread_ts)
);`;

const ENTRIES = `
CREATE TABLE IF NOT EXISTS entries (
  thread INTEGER NOT NULL,
  n INTEGER NOT NULL,
  kind TEXT NOT NULL,
  target INTEGER,
  ts TEXT,
  author_kind TEXT NOT NULL,
  author TEXT NOT NULL,
  text TEXT,
  attachments TEXT,
  quotes TEXT,
  declared TEXT,
  at INTEGER NOT NULL,
  PRIMARY KEY (thread, n)
);
CREATE UNIQUE INDEX IF NOT EXISTS entries_ts ON entries (thread, ts) WHERE ts IS NOT NULL;
CREATE INDEX IF NOT EXISTS entries_target ON entries (thread, target) WHERE target IS NOT NULL;`;

const DELIVERIES = `
CREATE TABLE IF NOT EXISTS deliveries (
  thread INTEGER NOT NULL,
  n INTEGER NOT NULL,
  session TEXT NOT NULL,
  delivered_at INTEGER,
  PRIMARY KEY (thread, n, session)
);
CREATE INDEX IF NOT EXISTS deliveries_pending ON deliveries (session) WHERE delivered_at IS NULL;
CREATE INDEX IF NOT EXISTS deliveries_session ON deliveries (session, thread);`;

const READS = `
CREATE TABLE IF NOT EXISTS reads (
  viewer TEXT NOT NULL,
  thread INTEGER NOT NULL,
  n INTEGER NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (viewer, thread)
);`;

const TABLES = `
${THREADS}
CREATE TABLE IF NOT EXISTS thread_sessions (
  thread INTEGER NOT NULL,
  session TEXT NOT NULL,
  connect TEXT NOT NULL,
  joined_at INTEGER NOT NULL,
  PRIMARY KEY (thread, session)
);
CREATE INDEX IF NOT EXISTS thread_sessions_session ON thread_sessions (session);
${ENTRIES}
${DELIVERIES}
${READS}
CREATE TABLE IF NOT EXISTS profile_status (
  profile TEXT PRIMARY KEY,
  check_json TEXT, checked_at INTEGER,
  quota_json TEXT, quota_at INTEGER
);
-- Each message as it reads now: its latest edit's words, files and quotes.
CREATE VIEW IF NOT EXISTS merged AS
  SELECT m.thread, m.n, m.ts, m.author_kind, m.author,
    CASE WHEN e.n IS NULL THEN m.text ELSE e.text END AS text,
    CASE WHEN e.n IS NULL THEN m.attachments ELSE e.attachments END AS attachments,
    CASE WHEN e.n IS NULL THEN m.quotes ELSE e.quotes END AS quotes,
    m.declared, m.at AS created_at, e.at AS edited_at
  FROM entries m
  LEFT JOIN entries e ON e.thread = m.thread
    AND e.n = (SELECT MAX(x.n) FROM entries x WHERE x.thread = m.thread AND x.target = m.n)
  WHERE m.kind = 'message';
`;

const SCHEMA = `
CREATE TABLE IF NOT EXISTS sessions (
  key TEXT PRIMARY KEY,
  connect TEXT NOT NULL,
  scope TEXT NOT NULL,
  title TEXT,
  created_by TEXT,
  runtime TEXT NOT NULL,
  profile TEXT NOT NULL,
  model TEXT,
  effort TEXT,
  runtime_session_id TEXT,
  workspace TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  running INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  last_active_at INTEGER NOT NULL,
  archived_at INTEGER
);
${TABLES}
CREATE TABLE IF NOT EXISTS bindings (
  connect TEXT PRIMARY KEY,
  session_key TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS turns (
  id TEXT PRIMARY KEY,
  session_key TEXT NOT NULL,
  kind TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  outcome TEXT,
  detail TEXT,
  declared TEXT
);
CREATE TABLE IF NOT EXISTS processes (
  pgid INTEGER PRIMARY KEY,
  started_at INTEGER NOT NULL,
  runtime TEXT NOT NULL,
  label TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS identities (
  viewer TEXT NOT NULL,
  slack_user TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (viewer, slack_user)
);
`;

type Row = Record<string, unknown>;

function toSession(row: Row): SessionRow {
  return {
    key: row.key as string,
    connect: row.connect as string,
    scope: row.scope as SessionScope,
    title: (row.title as string | null) ?? null,
    createdBy: (row.created_by as string | null) ?? null,
    runtime: row.runtime as RuntimeKind,
    profile: row.profile as string,
    model: (row.model as string | null) ?? null,
    effort: (row.effort as string | null) ?? null,
    runtimeSessionId: (row.runtime_session_id as string | null) ?? null,
    workspace: row.workspace as string,
    token: row.token as string,
    running: row.running === 1,
    createdAt: row.created_at as number,
    lastActiveAt: row.last_active_at as number,
    archivedAt: (row.archived_at as number | null) ?? null,
  };
}

function toThread(row: Row): ThreadRow {
  return {
    id: row.id as number, surface: row.surface as string, channel: row.channel as string, threadTs: row.thread_ts as string,
    title: (row.title as string | null) ?? null, createdBy: (row.created_by as string | null) ?? null, createdAt: row.created_at as number,
  };
}

function toMembership(row: Row): Membership {
  return { thread: row.thread as number, session: row.session as string, connect: row.connect as string, joinedAt: row.joined_at as number };
}

function toEntry(row: Row): EntryRow {
  return {
    thread: row.thread as number, n: row.n as number, kind: row.kind as EntryKind, target: (row.target as number | null) ?? null,
    ts: (row.ts as string | null) ?? null, authorKind: row.author_kind as AuthorKind, author: row.author as string,
    text: (row.text as string | null) ?? null,
    attachments: row.attachments ? JSON.parse(row.attachments as string) as Attachment[] : [],
    quotes: row.quotes ? JSON.parse(row.quotes as string) as Quote[] : [],
    declared: (row.declared as string | null) ?? null, at: row.at as number,
  };
}

function toMessage(row: Row): MessageRow {
  return {
    thread: row.thread as number, n: row.n as number, ts: row.ts as string,
    authorKind: row.author_kind as AuthorKind, author: row.author as string, text: (row.text as string | null) ?? "",
    attachments: row.attachments ? JSON.parse(row.attachments as string) as Attachment[] : [],
    quotes: row.quotes ? JSON.parse(row.quotes as string) as Quote[] : [],
    declared: (row.declared as string | null) ?? null, createdAt: row.created_at as number,
    editedAt: (row.edited_at as number | null) ?? null,
  };
}

/** Entries merged into their messages, as the `merged` view does: for a thread read from its archive file. */
function mergeEntries(entries: readonly EntryRow[]): MessageRow[] {
  const messages = new Map<number, MessageRow>();
  for (const e of entries) {
    if (e.kind === "message") {
      messages.set(e.n, {
        thread: e.thread, n: e.n, ts: e.ts ?? "", authorKind: e.authorKind, author: e.author, text: e.text ?? "",
        attachments: e.attachments, quotes: e.quotes, declared: e.declared, createdAt: e.at, editedAt: null,
      });
      continue;
    }
    const m = e.target === null ? undefined : messages.get(e.target);
    if (m) Object.assign(m, { text: e.text ?? "", attachments: e.attachments, quotes: e.quotes, editedAt: e.at });
  }
  return [...messages.values()];
}

const json = (value: unknown[] | undefined): string | null => (value?.length ? JSON.stringify(value) : null);

/** Archived threads whose entries are kept decompressed, the most recently read last. */
const ARCHIVE_CACHE = 32;

/**
 * `changes` emits:
 * - "session" (key): anything about that session changed;
 * - "session-removed" (key): it was deleted;
 * - "thread" ({ id, entries }): entries were appended there (contiguous, in order), or its sessions changed (none);
 * - "thread-removed" ({ id }): it went, with every entry it had;
 * - "read" ({ viewer, thread, n }): a viewer's read position moved;
 * - "identities" (viewer): the Slack users a viewer said are them changed;
 * - "processes": the recorded runtime processes changed.
 */
export class Store {
  readonly #db: DatabaseSync;
  readonly changes = new EventEmitter();
  /** Where archived threads (and sessions' transcript copies) are written; see archiveDir. */
  #archiveDir: string | undefined;
  /** Entries of archived threads read lately (they never change), the most recent last. */
  readonly #archived = new Map<number, EntryRow[]>();

  /** `archive` is where archived threads go: `archive/` beside the database unless given. */
  constructor(path: string, options: { archive?: string } = {}) {
    if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true });
    this.#archiveDir = options.archive ?? (path === ":memory:" ? undefined : join(dirname(path), "archive"));
    this.#db = new DatabaseSync(path);
    this.#db.exec("PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;");
    const version = Store.#version(this.#db);
    if (version !== null && version !== SCHEMA_VERSION) {
      throw new Error(`${path} has schema version ${version}; this ember uses ${SCHEMA_VERSION}. Move its data by hand, or move it aside.`);
    }
    this.#db.exec(SCHEMA);
    this.#db.exec(`PRAGMA user_version = ${SCHEMA_VERSION}`);
  }

  /** The schema version of a database with ember's tables, or null for an empty one. */
  static #version(db: DatabaseSync): number | null {
    const hasTables = db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sessions'").get() !== undefined;
    return hasTables ? (db.prepare("PRAGMA user_version").get() as Row).user_version as number : null;
  }

  close(): void {
    this.#db.close();
  }

  /** Where archived threads and transcript copies go (`threads/`, `transcripts/`). */
  get archiveDir(): string {
    // An in-memory store (tests) archives into a directory of its own.
    return (this.#archiveDir ??= mkdtempSync(join(tmpdir(), "ember-archive-")));
  }

  #transaction<T>(run: () => T): T {
    this.#db.exec("BEGIN");
    try {
      const result = run();
      this.#db.exec("COMMIT");
      return result;
    } catch (error) {
      this.#db.exec("ROLLBACK");
      throw error;
    }
  }

  /** Announces a change ember keeps outside the database (e.g. a runtime process ending). */
  notify(sessionKey: string): void {
    this.changes.emit("session", sessionKey);
  }

  // ── sessions ────────────────────────────────────────────────────────────

  getSession(key: string): SessionRow | undefined {
    const row = this.#db.prepare("SELECT * FROM sessions WHERE key = ?").get(key) as Row | undefined;
    return row ? toSession(row) : undefined;
  }

  sessionByToken(token: string): SessionRow | undefined {
    const row = this.#db.prepare("SELECT * FROM sessions WHERE token = ?").get(token) as Row | undefined;
    return row ? toSession(row) : undefined;
  }

  /** Every session, most recently active first. */
  listSessions(): SessionRow[] {
    return (this.#db.prepare("SELECT * FROM sessions ORDER BY last_active_at DESC").all() as Row[]).map(toSession);
  }

  insertSession(s: Omit<SessionRow, "running" | "runtimeSessionId" | "title" | "createdBy" | "effort" | "archivedAt"> & { title?: string | null; createdBy?: string | null; effort?: string | null }): void {
    this.#db.prepare(`INSERT INTO sessions (key, connect, scope, title, created_by, runtime, profile, model, effort, workspace, token, created_at, last_active_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .run(s.key, s.connect, s.scope, s.title ?? null, s.createdBy ?? null, s.runtime, s.profile, s.model, s.effort ?? null, s.workspace, s.token, s.createdAt, s.lastActiveAt);
    this.notify(s.key);
  }

  /** Moves a session to another profile (Hub.setProfile has copied its transcript there). */
  setSessionProfile(key: string, profile: string): void {
    this.#db.prepare("UPDATE sessions SET profile = ? WHERE key = ?").run(profile, key);
    this.notify(key);
  }

  setTitle(key: string, title: string | null): void {
    this.#db.prepare("UPDATE sessions SET title = ? WHERE key = ?").run(title, key);
    this.notify(key);
  }

  touch(key: string): void {
    this.#db.prepare("UPDATE sessions SET last_active_at = ? WHERE key = ?").run(Date.now(), key);
  }

  /**
   * Hides a session from lists, or shows it again. A thread whose sessions
   * are all archived goes out to its archive file; showing one of them again
   * brings it back.
   */
  setArchived(key: string, archived: boolean): void {
    this.#db.prepare("UPDATE sessions SET archived_at = ? WHERE key = ?").run(archived ? Date.now() : null, key);
    for (const { id } of this.sessionThreads(key)) {
      if (!archived && this.#isArchived(id)) this.#restoreThread(id);
      else if (archived && !this.#isArchived(id) && this.#db.prepare(`SELECT 1 FROM thread_sessions ts JOIN sessions s ON s.key = ts.session
        WHERE ts.thread = ? AND s.archived_at IS NULL LIMIT 1`).get(id) === undefined) this.#archiveThread(id);
    }
    this.notify(key);
  }

  /**
   * Forgets a session: its row, turns, deliveries, memberships and bindings,
   * and the threads only it took part in, with their entries (or archive
   * files) and reads.
   */
  deleteSession(key: string): void {
    const { kept, removed } = this.#transaction(() => {
      const threads = (this.#db.prepare("SELECT thread FROM thread_sessions WHERE session = ?").all(key) as Row[]).map((r) => r.thread as number);
      this.#db.prepare("DELETE FROM thread_sessions WHERE session = ?").run(key);
      this.#db.prepare("DELETE FROM deliveries WHERE session = ?").run(key);
      this.#db.prepare("DELETE FROM turns WHERE session_key = ?").run(key);
      this.#db.prepare("DELETE FROM bindings WHERE session_key = ?").run(key);
      this.#db.prepare("DELETE FROM sessions WHERE key = ?").run(key);
      const kept: number[] = [];
      const removed: number[] = [];
      for (const thread of threads) {
        if (this.#db.prepare("SELECT 1 FROM thread_sessions WHERE thread = ? LIMIT 1").get(thread) !== undefined) {
          kept.push(thread);
          continue;
        }
        removed.push(thread);
        this.#db.prepare("DELETE FROM deliveries WHERE thread = ?").run(thread);
        this.#db.prepare("DELETE FROM entries WHERE thread = ?").run(thread);
        this.#db.prepare("DELETE FROM reads WHERE thread = ?").run(thread);
        this.#db.prepare("DELETE FROM threads WHERE id = ?").run(thread);
      }
      return { kept, removed };
    });
    for (const thread of removed) {
      this.#archived.delete(thread);
      rmSync(this.#threadFile(thread), { force: true });
    }
    this.changes.emit("session-removed", key);
    // Clients drop what they keep of the threads that went with it.
    for (const thread of removed) this.changes.emit("thread-removed", { id: thread });
    for (const thread of kept) this.changes.emit("thread", { id: thread, entries: [] });
  }

  // ── single-session bindings ────────────────────────────────────────────

  /** The session a single-session connect delivers into, if one is bound. */
  binding(connect: string): string | undefined {
    const row = this.#db.prepare("SELECT session_key FROM bindings WHERE connect = ?").get(connect) as Row | undefined;
    return row ? row.session_key as string : undefined;
  }

  /** Binds a connect to a session, or unbinds it (null) so its next message starts a new one. */
  setBinding(connect: string, sessionKey: string | null): void {
    const before = this.binding(connect);
    if (sessionKey) this.#db.prepare("INSERT OR REPLACE INTO bindings (connect, session_key) VALUES (?, ?)").run(connect, sessionKey);
    else this.#db.prepare("DELETE FROM bindings WHERE connect = ?").run(connect);
    for (const key of new Set([before, sessionKey])) if (key) this.notify(key);
  }

  /** Connects bound to each session. */
  listBindings(): Map<string, string[]> {
    const out = new Map<string, string[]>();
    for (const r of this.#db.prepare("SELECT connect, session_key FROM bindings").all() as Row[]) {
      const key = r.session_key as string;
      out.set(key, [...(out.get(key) ?? []), r.connect as string]);
    }
    return out;
  }

  setRuntimeSessionId(key: string, id: string): void {
    this.#db.prepare("UPDATE sessions SET runtime_session_id = ? WHERE key = ?").run(id, key);
    this.notify(key);
  }

  setRunning(key: string, running: boolean): void {
    this.#db.prepare("UPDATE sessions SET running = ?, last_active_at = ? WHERE key = ?").run(running ? 1 : 0, Date.now(), key);
    this.notify(key);
  }

  // ── threads ─────────────────────────────────────────────────────────────

  getThread(id: number): ThreadRow | undefined {
    const row = this.#db.prepare("SELECT * FROM threads WHERE id = ?").get(id) as Row | undefined;
    return row ? toThread(row) : undefined;
  }

  threadAt(surface: string, channel: string, threadTs: string): ThreadRow | undefined {
    const row = this.#db.prepare("SELECT * FROM threads WHERE surface = ? AND channel = ? AND thread_ts = ?").get(surface, channel, threadTs) as Row | undefined;
    return row ? toThread(row) : undefined;
  }

  /** The thread at this address, made if new. */
  openThread(t: Omit<ThreadRow, "id" | "createdAt" | "title" | "createdBy"> & { title?: string | null; createdBy?: string | null }): ThreadRow {
    this.#db.prepare("INSERT OR IGNORE INTO threads (surface, channel, thread_ts, title, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?)")
      .run(t.surface, t.channel, t.threadTs, t.title ?? null, t.createdBy ?? null, Date.now());
    return this.threadAt(t.surface, t.channel, t.threadTs)!;
  }

  /** Makes a session take part in a thread, posting through `connect`. False if it already did. */
  joinThread(thread: number, session: string, connect: string): boolean {
    const joined = this.#db.prepare("INSERT OR IGNORE INTO thread_sessions (thread, session, connect, joined_at) VALUES (?, ?, ?, ?)")
      .run(thread, session, connect, Date.now()).changes > 0;
    if (joined) {
      this.notify(session);
      this.changes.emit("thread", { id: thread, entries: [] });
    }
    return joined;
  }

  threadSessions(thread: number): Membership[] {
    return (this.#db.prepare("SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid").all(thread) as Row[]).map(toMembership);
  }

  /** A thread of this session by the address the agent names it with, and how the session posts there. */
  sessionThread(session: string, channel: string, threadTs: string): (ThreadRow & { connect: string }) | undefined {
    const row = this.#db.prepare(`SELECT t.*, ts.connect FROM thread_sessions ts JOIN threads t ON t.id = ts.thread
      WHERE ts.session = ? AND t.channel = ? AND t.thread_ts = ?`).get(session, channel, threadTs) as Row | undefined;
    return row ? { ...toThread(row), connect: row.connect as string } : undefined;
  }

  /** The threads a session takes part in, most recently joined first, with the connect it posts through in each. */
  sessionThreads(session: string): (ThreadRow & { connect: string })[] {
    return (this.#db.prepare(`SELECT t.*, ts.connect FROM thread_sessions ts JOIN threads t ON t.id = ts.thread
      WHERE ts.session = ? ORDER BY ts.joined_at DESC, ts.rowid DESC`).all(session) as Row[]).map((r) => ({ ...toThread(r), connect: r.connect as string }));
  }

  /**
   * The thread a session last heard from: where ember's own notices go and
   * whose connect's name the agent goes by. Falls back to the thread it
   * joined last when it has heard nothing yet.
   */
  latestThread(session: string): (ThreadRow & { connect: string }) | undefined {
    const row = (this.#db.prepare(`SELECT t.*, ts.connect FROM deliveries d JOIN threads t ON t.id = d.thread
        JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = d.session
        WHERE d.session = ? ORDER BY d.rowid DESC LIMIT 1`).get(session)
      ?? this.#db.prepare(`SELECT t.*, ts.connect FROM thread_sessions ts JOIN threads t ON t.id = ts.thread
        WHERE ts.session = ? ORDER BY ts.joined_at DESC, ts.rowid DESC LIMIT 1`).get(session)) as Row | undefined;
    return row ? { ...toThread(row), connect: row.connect as string } : undefined;
  }

  /**
   * Threads with their sessions, last entry, latest message and the viewer's
   * unread count, most recently said in first: those of one session, one
   * thread, or all.
   */
  listThreads(viewer: string, filter: { session?: string; thread?: number } = {}): ThreadSummary[] {
    const where = filter.thread !== undefined ? "WHERE t.id = ?" : filter.session !== undefined ? "WHERE t.id IN (SELECT thread FROM thread_sessions WHERE session = ?)" : "";
    const params = filter.thread ?? filter.session;
    const rows = this.#db.prepare(`SELECT t.*, COALESCE(r.n, 0) AS read_n FROM threads t LEFT JOIN reads r ON r.thread = t.id AND r.viewer = ? ${where}`)
      .all(...(params === undefined ? [viewer] : [viewer, params])) as Row[];
    const summaries = rows.map((r): ThreadSummary => {
      const id = r.id as number;
      const read = r.read_n as number;
      return {
        ...toThread(r), sessions: this.threadSessions(id), last: this.lastEntry(id), lastMessage: this.lastMessage(id),
        read, unread: this.unreadCount(viewer, id, read), people: this.#threadPeople(id, r.surface as string), firstText: this.#firstText(id),
      };
    });
    const said = (t: ThreadSummary) => t.lastMessage?.createdAt ?? 0;
    return summaries.sort((a, b) => said(b) - said(a) || b.createdAt - a.createdAt || b.id - a.id);
  }

  /** The thread's latest message as merged, for lists. */
  lastMessage(thread: number): MessageRow | null {
    if (this.#isArchived(thread)) return this.#archivedMessages(thread).at(-1) ?? null;
    const row = this.#db.prepare("SELECT * FROM merged WHERE thread = ? ORDER BY n DESC LIMIT 1").get(thread) as Row | undefined;
    return row ? toMessage(row) : null;
  }

  /** Messages after the viewer's read position (or `read`) that are not the viewer's own (nor of a Slack user they are). */
  unreadCount(viewer: string, thread: number, read = this.readPosition(viewer, thread)): number {
    const slack = this.getThread(thread)?.surface !== EMBER_SURFACE;
    const selves = new Set([viewer, ...(slack ? this.slackIdentities(viewer) : [])]);
    if (this.#isArchived(thread)) return this.#archivedMessages(thread).filter((m) => m.n > read && !(m.authorKind === "person" && selves.has(m.author))).length;
    return (this.#db.prepare(`SELECT COUNT(*) AS c FROM entries WHERE thread = ? AND n > ? AND kind = 'message'
      AND NOT (author_kind = 'person' AND author IN (SELECT value FROM json_each(?)))`).get(thread, read, JSON.stringify([...selves])) as Row).c as number;
  }

  /** Everyone who wrote in a thread, as creator references (a Slack user through a connect in it), earliest first. */
  #threadPeople(thread: number, surface: string): string[] {
    const connect = (this.#db.prepare("SELECT MIN(connect) AS connect FROM thread_sessions WHERE thread = ?").get(thread) as Row).connect as string | null;
    const authors = this.#isArchived(thread)
      ? [...new Set(this.#archivedEntries(thread).filter((e) => e.kind === "message" && e.authorKind === "person").map((e) => e.author))]
      : (this.#db.prepare(`SELECT author, MIN(n) AS first FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person'
        GROUP BY author ORDER BY first`).all(thread) as Row[]).map((r) => r.author as string);
    if (surface === EMBER_SURFACE) return authors;
    return connect ? authors.map((author) => `slack:${connect}:${author}`) : [];
  }

  /** The first thing a person said in it (up to 300 characters). */
  #firstText(thread: number): string | null {
    if (this.#isArchived(thread)) return this.#archivedMessages(thread).find((m) => m.authorKind === "person")?.text.slice(0, 300) ?? null;
    const row = this.#db.prepare(`SELECT substr(text, 1, 300) AS text FROM merged WHERE thread = ? AND author_kind = 'person'
      ORDER BY n LIMIT 1`).get(thread) as Row | undefined;
    return row ? row.text as string : null;
  }

  // ── entries ─────────────────────────────────────────────────────────────

  /**
   * Records something said. A message already recorded in that thread (Slack
   * delivers to every connect in the channel, and redelivers) is the same
   * message: its n comes back with `fresh` false and nothing changes.
   */
  insertMessage(m: { thread: number; ts: string; authorKind: AuthorKind; author: string; text: string; attachments?: Attachment[]; quotes?: Quote[]; declared?: string | null; at?: number }): { n: number; fresh: boolean } {
    const existing = this.messageAt(m.thread, m.ts);
    if (existing) return { n: existing.n, fresh: false };
    const entry = this.#append({
      thread: m.thread, kind: "message", target: null, ts: m.ts, authorKind: m.authorKind, author: m.author, text: m.text,
      attachments: m.attachments ?? [], quotes: m.quotes ?? [], declared: m.declared ?? null, at: m.at ?? Date.now(),
    });
    return { n: entry.n, fresh: true };
  }

  /**
   * A platform edit: an edit entry with the message's new words. Returns the
   * thread, or undefined for a message ember never recorded or one whose words
   * did not change.
   */
  editMessage(surface: string, channel: string, threadTs: string, ts: string, text: string): number | undefined {
    const message = this.#platformMessage(surface, channel, threadTs, ts);
    if (!message || message.text === text) return undefined;
    this.#append({
      thread: message.thread, kind: "edit", target: message.n, ts: null, authorKind: message.authorKind, author: message.author, text,
      attachments: message.attachments, quotes: message.quotes, declared: null, at: Date.now(),
    });
    return message.thread;
  }

  #platformMessage(surface: string, channel: string, threadTs: string, ts: string): MessageRow | undefined {
    const thread = this.threadAt(surface, channel, threadTs);
    return thread && this.messageAt(thread.id, ts);
  }

  /** Appends an entry as the thread's next, bringing an archived thread back first. */
  #append(entry: Omit<EntryRow, "n">): EntryRow {
    if (this.#isArchived(entry.thread)) this.#restoreThread(entry.thread);
    const appended = this.#transaction(() => {
      const n = ((this.#db.prepare("SELECT MAX(n) AS n FROM entries WHERE thread = ?").get(entry.thread) as Row).n as number | null ?? 0) + 1;
      this.#insertEntry({ ...entry, n });
      return { ...entry, n };
    });
    this.changes.emit("thread", { id: entry.thread, entries: [appended] });
    return appended;
  }

  #insertEntry(e: EntryRow): void {
    this.#db.prepare(`INSERT INTO entries (thread, n, kind, target, ts, author_kind, author, text, attachments, quotes, declared, at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .run(e.thread, e.n, e.kind, e.target, e.ts, e.authorKind, e.author, e.text, json(e.attachments), json(e.quotes), e.declared, e.at);
  }

  /** The thread's last entry number, 0 before anything is said. */
  lastEntry(thread: number): number {
    if (this.#isArchived(thread)) return this.#archivedEntries(thread).at(-1)?.n ?? 0;
    return ((this.#db.prepare("SELECT MAX(n) AS n FROM entries WHERE thread = ?").get(thread) as Row).n as number | null) ?? 0;
  }

  /** Entries after n: what came since. */
  entriesAfter(thread: number, n: number): EntryRow[] {
    return this.entriesBetween(thread, n + 1, Number.MAX_SAFE_INTEGER);
  }

  /** The latest `limit` entries before n (the latest of all without it), oldest first. */
  entriesBefore(thread: number, n: number | undefined, limit: number): EntryRow[] {
    const before = n ?? Number.MAX_SAFE_INTEGER;
    if (this.#isArchived(thread)) return this.#archivedEntries(thread).filter((e) => e.n < before).slice(-limit);
    return (this.#db.prepare("SELECT * FROM entries WHERE thread = ? AND n < ? ORDER BY n DESC LIMIT ?")
      .all(thread, before, limit) as Row[]).reverse().map(toEntry);
  }

  /** Entries from n = `from` to n = `to`, both included: a gap. */
  entriesBetween(thread: number, from: number, to: number): EntryRow[] {
    if (this.#isArchived(thread)) return this.#archivedEntries(thread).filter((e) => e.n >= from && e.n <= to);
    return (this.#db.prepare("SELECT * FROM entries WHERE thread = ? AND n >= ? AND n <= ? ORDER BY n").all(thread, from, to) as Row[]).map(toEntry);
  }

  /** A message of the thread by its platform id, as merged. */
  messageAt(thread: number, ts: string): MessageRow | undefined {
    if (this.#isArchived(thread)) return this.#archivedMessages(thread).find((m) => m.ts === ts);
    const row = this.#db.prepare("SELECT * FROM merged WHERE thread = ? AND ts = ?").get(thread, ts) as Row | undefined;
    return row ? toMessage(row) : undefined;
  }

  /** The latest `limit` messages before n (the latest of all without it), as merged, oldest first. */
  messagesBefore(thread: number, n: number | undefined, limit: number): MessageRow[] {
    const before = n ?? Number.MAX_SAFE_INTEGER;
    if (this.#isArchived(thread)) return this.#archivedMessages(thread).filter((m) => m.n < before).slice(-limit);
    return (this.#db.prepare("SELECT * FROM merged WHERE thread = ? AND n < ? ORDER BY n DESC LIMIT ?")
      .all(thread, before, limit) as Row[]).reverse().map(toMessage);
  }

  // ── archive ─────────────────────────────────────────────────────────────

  #isArchived(thread: number): boolean {
    return (this.#db.prepare("SELECT archived_at FROM threads WHERE id = ?").get(thread) as Row | undefined)?.archived_at != null;
  }

  #threadFile(thread: number): string {
    return join(this.archiveDir, "threads", `${thread}.jsonl.zst`);
  }

  /**
   * Writes a thread's entries out to its archive file (one entry per line,
   * zstd) and deletes their rows. Entries never change, so the file is the
   * thread as it was and what clients keep of it stays true.
   */
  #archiveThread(thread: number): void {
    const entries = (this.#db.prepare("SELECT * FROM entries WHERE thread = ? ORDER BY n").all(thread) as Row[]).map(toEntry);
    const path = this.#threadFile(thread);
    writeCompressed(path, entries.map((e) => `${JSON.stringify(e)}\n`).join(""));
    try {
      this.#transaction(() => {
        this.#db.prepare("DELETE FROM entries WHERE thread = ?").run(thread);
        this.#db.prepare("UPDATE threads SET archived_at = ? WHERE id = ?").run(Date.now(), thread);
      });
    } catch (error) {
      rmSync(path, { force: true });
      throw error;
    }
  }

  /** Loads an archived thread's entries back into the database and removes its file. */
  #restoreThread(thread: number): void {
    const entries = this.#archivedEntries(thread);
    this.#transaction(() => {
      for (const e of entries) this.#insertEntry(e);
      this.#db.prepare("UPDATE threads SET archived_at = NULL WHERE id = ?").run(thread);
    });
    this.#archived.delete(thread);
    rmSync(this.#threadFile(thread), { force: true });
  }

  /** An archived thread's entries, from its file. */
  #archivedEntries(thread: number): EntryRow[] {
    let entries = this.#archived.get(thread);
    if (entries) {
      this.#archived.delete(thread);
    } else {
      const text = zstdDecompressSync(readFileSync(this.#threadFile(thread))).toString("utf8");
      entries = text.split("\n").filter(Boolean).map((line) => JSON.parse(line) as EntryRow);
      if (this.#archived.size >= ARCHIVE_CACHE) this.#archived.delete(this.#archived.keys().next().value!);
    }
    this.#archived.set(thread, entries);
    return entries;
  }

  #archivedMessages(thread: number): MessageRow[] {
    return mergeEntries(this.#archivedEntries(thread));
  }

  // ── deliveries ─────────────────────────────────────────────────────────

  /** Hands a message to sessions. Returns those that did not have it yet. */
  deliver(thread: number, n: number, sessions: readonly string[]): string[] {
    const stmt = this.#db.prepare("INSERT OR IGNORE INTO deliveries (thread, n, session) VALUES (?, ?, ?)");
    const added = sessions.filter((s) => stmt.run(thread, n, s).changes > 0);
    for (const key of added) this.notify(key);
    return added;
  }

  /** What the session has yet to read, as merged now, in the order it was handed over. */
  pendingMessages(session: string): PendingMessage[] {
    return (this.#db.prepare(`SELECT m.*, t.surface, t.channel, t.thread_ts, ts.connect FROM deliveries d
      JOIN merged m ON m.thread = d.thread AND m.n = d.n JOIN threads t ON t.id = d.thread
      JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = d.session
      WHERE d.session = ? AND d.delivered_at IS NULL ORDER BY d.rowid`).all(session) as Row[])
      .map((r) => ({ ...toMessage(r), surface: r.surface as string, channel: r.channel as string, threadTs: r.thread_ts as string, connect: r.connect as string }));
  }

  markDelivered(session: string, messages: readonly { thread: number; n: number }[]): void {
    const stmt = this.#db.prepare("UPDATE deliveries SET delivered_at = ? WHERE thread = ? AND n = ? AND session = ? AND delivered_at IS NULL");
    const now = Date.now();
    for (const m of messages) stmt.run(now, m.thread, m.n, session);
    if (messages.length) this.notify(session);
  }

  /** Threads the session has already read something from. */
  heardThreads(session: string): Set<number> {
    return new Set((this.#db.prepare("SELECT DISTINCT thread FROM deliveries WHERE session = ? AND delivered_at IS NOT NULL")
      .all(session) as Row[]).map((r) => r.thread as number));
  }

  sessionsWithPending(): string[] {
    return (this.#db.prepare("SELECT DISTINCT session FROM deliveries WHERE delivered_at IS NULL").all() as Row[]).map((r) => r.session as string);
  }

  /** Everyone who wrote in each session's threads, as creator references, earliest first. */
  participants(session?: string): Map<string, string[]> {
    const rows = this.#db.prepare(`SELECT ts.session, ts.connect, t.id, t.surface, t.archived_at FROM thread_sessions ts JOIN threads t ON t.id = ts.thread
      ${session ? "WHERE ts.session = ?" : ""}`).all(...(session ? [session] : [])) as Row[];
    // Each person once per session, at the first time they wrote in any of its threads.
    const firsts = new Map<string, Map<string, number>>();
    for (const r of rows) {
      const thread = r.id as number;
      const authors = r.archived_at != null
        ? this.#archivedEntries(thread).filter((e) => e.kind === "message" && e.authorKind === "person")
        : (this.#db.prepare(`SELECT author, MIN(at) AS at FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' GROUP BY author`)
          .all(thread) as Row[]).map((a) => ({ author: a.author as string, at: a.at as number }));
      const refs = firsts.get(r.session as string) ?? new Map<string, number>();
      firsts.set(r.session as string, refs);
      for (const { author, at } of authors) {
        const ref = r.surface === EMBER_SURFACE ? author : `slack:${r.connect as string}:${author}`;
        if (!refs.has(ref) || at < refs.get(ref)!) refs.set(ref, at);
      }
    }
    return new Map([...firsts].filter(([, refs]) => refs.size > 0).map(([key, refs]) => [key, [...refs].sort((a, b) => a[1] - b[1]).map(([ref]) => ref)]));
  }

  // ── reads ───────────────────────────────────────────────────────────────

  /** How far a viewer has read a thread (an entry number), 0 if never. */
  readPosition(viewer: string, thread: number): number {
    return (this.#db.prepare("SELECT n FROM reads WHERE viewer = ? AND thread = ?").get(viewer, thread) as Row | undefined)?.n as number | undefined ?? 0;
  }

  /** Moves a viewer's read position forward (never back). Returns where it is now. */
  setRead(viewer: string, thread: number, n: number): number {
    this.#db.prepare(`INSERT INTO reads (viewer, thread, n, at) VALUES (?, ?, ?, ?)
      ON CONFLICT (viewer, thread) DO UPDATE SET n = MAX(n, excluded.n), at = excluded.at`).run(viewer, thread, n, Date.now());
    const now = this.readPosition(viewer, thread);
    this.changes.emit("read", { viewer, thread, n: now });
    return now;
  }

  // ── identities ──────────────────────────────────────────────────────────

  /** The Slack users a viewer said are them: their messages are the viewer's own. */
  slackIdentities(viewer: string): string[] {
    return (this.#db.prepare("SELECT slack_user FROM identities WHERE viewer = ? ORDER BY at").all(viewer) as Row[]).map((r) => r.slack_user as string);
  }

  /** Binds a Slack user to a viewer ("这是我"), or unbinds it. Nobody checks: it is the viewer's word. */
  setSlackIdentity(viewer: string, user: string, bound: boolean): void {
    if (bound) this.#db.prepare("INSERT OR IGNORE INTO identities (viewer, slack_user, at) VALUES (?, ?, ?)").run(viewer, user, Date.now());
    else this.#db.prepare("DELETE FROM identities WHERE viewer = ? AND slack_user = ?").run(viewer, user);
    this.changes.emit("identities", viewer);
  }

  // ── turns ───────────────────────────────────────────────────────────────

  startTurn(id: string, sessionKey: string, kind: TurnKind): void {
    this.#db.prepare("INSERT INTO turns (id, session_key, kind, started_at) VALUES (?, ?, ?, ?)").run(id, sessionKey, kind, Date.now());
    this.notify(sessionKey);
  }

  endTurn(id: string, outcome: string, detail: string | null, declared: string | null): void {
    this.#db.prepare("UPDATE turns SET ended_at = ?, outcome = ?, detail = ?, declared = ? WHERE id = ?")
      .run(Date.now(), outcome, detail, declared, id);
    const row = this.#db.prepare("SELECT session_key FROM turns WHERE id = ?").get(id) as Row | undefined;
    if (row) this.notify(row.session_key as string);
  }

  listTurns(sessionKey: string): (TurnSummary & { id: string; kind: TurnKind })[] {
    return (this.#db.prepare("SELECT * FROM turns WHERE session_key = ? ORDER BY started_at").all(sessionKey) as Row[]).map((r) => ({
      id: r.id as string, kind: r.kind as TurnKind, outcome: (r.outcome as string | null) ?? null,
      detail: (r.detail as string | null) ?? null, declared: (r.declared as string | null) ?? null,
      startedAt: r.started_at as number, endedAt: (r.ended_at as number | null) ?? null,
    }));
  }

  /** Per session (or for one): turn count, the latest turn, undelivered messages and the first one it heard. For listings. */
  sessionStats(key?: string): Map<string, SessionStats> {
    const rows = this.#db.prepare(`
      SELECT s.key,
        (SELECT COUNT(*) FROM turns t WHERE t.session_key = s.key) AS turns,
        (SELECT COUNT(*) FROM deliveries d WHERE d.session = s.key AND d.delivered_at IS NULL) AS pending,
        (SELECT substr(m.text, 1, 300) FROM deliveries d JOIN merged m ON m.thread = d.thread AND m.n = d.n
          WHERE d.session = s.key ORDER BY d.rowid LIMIT 1) AS first_text,
        l.kind, l.outcome, l.declared, l.detail, l.started_at, l.ended_at
      FROM sessions s
      LEFT JOIN turns l ON l.id = (SELECT id FROM turns t2 WHERE t2.session_key = s.key ORDER BY t2.started_at DESC LIMIT 1)
      ${key ? "WHERE s.key = ?" : ""}
    `).all(...(key ? [key] : [])) as Row[];
    return new Map(rows.map((r) => [r.key as string, {
      turns: r.turns as number,
      pending: r.pending as number,
      firstText: (r.first_text as string | null) ?? null,
      lastTurn: r.started_at == null ? null : {
        kind: r.kind as string, outcome: (r.outcome as string | null) ?? null, declared: (r.declared as string | null) ?? null,
        detail: (r.detail as string | null) ?? null, startedAt: r.started_at as number, endedAt: (r.ended_at as number | null) ?? null,
      },
    }]));
  }

  // ── profile checks and quotas ──────────────────────────────────────────

  profileStatus(): Map<string, ProfileStatus> {
    return new Map((this.#db.prepare("SELECT * FROM profile_status").all() as Row[]).map((r) => [r.profile as string, {
      check: r.check_json ? JSON.parse(r.check_json as string) as ProfileCheck : null,
      quota: r.quota_json ? JSON.parse(r.quota_json as string) as ProfileQuota : null,
    }]));
  }

  setProfileCheck(profile: string, check: ProfileCheck): void {
    this.#db.prepare(`INSERT INTO profile_status (profile, check_json, checked_at) VALUES (?, ?, ?)
      ON CONFLICT (profile) DO UPDATE SET check_json = excluded.check_json, checked_at = excluded.checked_at`).run(profile, JSON.stringify(check), check.checkedAt);
  }

  setProfileQuota(profile: string, quota: ProfileQuota): void {
    this.#db.prepare(`INSERT INTO profile_status (profile, quota_json, quota_at) VALUES (?, ?, ?)
      ON CONFLICT (profile) DO UPDATE SET quota_json = excluded.quota_json, quota_at = excluded.quota_at`).run(profile, JSON.stringify(quota), quota.checkedAt);
  }

  // ── runtime process groups ─────────────────────────────────────────────

  recordProcess(pgid: number, startedAt: number, runtime: RuntimeKind, label: string): void {
    this.#db.prepare("INSERT OR REPLACE INTO processes (pgid, started_at, runtime, label) VALUES (?, ?, ?, ?)")
      .run(pgid, startedAt, runtime, label);
    this.changes.emit("processes");
  }

  forgetProcess(pgid: number): void {
    if (this.#db.prepare("DELETE FROM processes WHERE pgid = ?").run(pgid).changes > 0) this.changes.emit("processes");
  }

  listProcesses(): { pgid: number; startedAt: number; runtime: RuntimeKind; label: string }[] {
    return (this.#db.prepare("SELECT * FROM processes").all() as Row[]).map((r) => ({
      pgid: r.pgid as number, startedAt: r.started_at as number, runtime: r.runtime as RuntimeKind, label: r.label as string,
    }));
  }
}

/** Writes a file compressed with zstd: aside first, then renamed into place. */
export function writeCompressed(path: string, text: string): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(`${path}.tmp`, zstdCompressSync(Buffer.from(text)));
  renameSync(`${path}.tmp`, path);
}
