// All durable ember state, in one SQLite file. Runtime transcripts stay in the
// runtimes' own homes; this records what ember needs to route and resume, and
// everything said in the threads its sessions take part in.
import { EventEmitter } from "node:events";
import { existsSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";
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

export interface MessageRow {
  seq: number;
  /** The change cursor: grows on every insert, edit and delete, across all threads. */
  rev: number;
  thread: number;
  /** The platform's id (Slack ts; ember makes Slack-like ones). */
  ts: string;
  authorKind: AuthorKind;
  /** person: Slack user id, email or "local"; agent: session key; ember: "ember". */
  author: string;
  /** As shown (Markdown); empty once deleted. */
  text: string;
  attachments: Attachment[];
  quotes: Quote[];
  /** An agent's final or block, posted with this message. */
  declared: string | null;
  createdAt: number;
  editedAt: number | null;
  deletedAt: number | null;
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
  last: MessageRow | null;
  /** The thread's latest rev: follow it with messagesAfter. */
  rev: number;
  /** The viewer's read position (a seq), 0 if never read. */
  read: number;
  /** Messages after the read position, not deleted and not the viewer's own (nor of a Slack user they are). */
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
 * Bump on schema changes and add a step to MIGRATIONS that brings the
 * previous version up. Versions without a migration path are refused.
 */
const SCHEMA_VERSION = 10;

interface MigrationContext {
  /** The Slack team of each connect, where known; threads are named by team. */
  teams: ReadonlyMap<string, string>;
}

const MIGRATIONS: Record<number, (db: DatabaseSync, context: MigrationContext) => void> = {
  // v9 → v10: chats, chat_messages and inbound become threads, messages and deliveries.
  9: (db, { teams }) => {
    db.exec(TABLES);
    db.function("surface_of", (connect) => (connect === "ember" ? EMBER_SURFACE : slackSurface(String(connect), teams.get(String(connect)))));
    db.exec(`
      INSERT OR IGNORE INTO threads (surface, channel, thread_ts, title, created_by, created_at)
        SELECT 'ember', 'EMBER', thread_ts, title, created_by, created_at FROM chats;
      INSERT OR IGNORE INTO threads (surface, channel, thread_ts, created_by, created_at)
        SELECT surface_of(connect), channel, thread_ts, CASE connect WHEN 'ember' THEN user ELSE 'slack:' || connect || ':' || user END, MIN(received_at)
        FROM inbound GROUP BY surface_of(connect), channel, thread_ts;
      -- A session made before any message remembers the thread it was made for, if any.
      INSERT OR IGNORE INTO threads (surface, channel, thread_ts, created_by, created_at)
        SELECT surface_of(connect), channel, thread_ts, created_by, created_at FROM sessions s
        WHERE channel != '' AND NOT EXISTS (SELECT 1 FROM inbound i WHERE i.session_key = s.key);

      INSERT OR IGNORE INTO thread_sessions (thread, session, connect, joined_at)
        SELECT t.id, c.session_key, 'ember', c.created_at FROM chats c JOIN threads t ON t.surface = 'ember' AND t.channel = 'EMBER' AND t.thread_ts = c.thread_ts;
      INSERT OR IGNORE INTO thread_sessions (thread, session, connect, joined_at)
        SELECT t.id, i.session_key, i.connect, MIN(i.received_at) FROM inbound i
        JOIN threads t ON t.surface = surface_of(i.connect) AND t.channel = i.channel AND t.thread_ts = i.thread_ts
        GROUP BY t.id, i.session_key;
      INSERT OR IGNORE INTO thread_sessions (thread, session, connect, joined_at)
        SELECT t.id, s.key, s.connect, s.created_at FROM sessions s
        JOIN threads t ON t.surface = surface_of(s.connect) AND t.channel = s.channel AND t.thread_ts = s.thread_ts
        WHERE NOT EXISTS (SELECT 1 FROM inbound i WHERE i.session_key = s.key);

      -- Everything said, oldest first so seq keeps the order. A message typed on the page is in
      -- both old tables; the chat_messages row keeps its words, files and quotes as the person wrote them.
      CREATE TEMP TABLE said AS
        SELECT t.id AS thread, m.ts, CASE m.role WHEN 'agent' THEN 'agent' ELSE 'person' END AS author_kind,
          CASE m.role WHEN 'agent' THEN c.session_key ELSE m.user END AS author, m.text, m.attachments, m.quotes, m.created_at
        FROM chat_messages m JOIN chats c ON c.thread_ts = m.thread_ts
        JOIN threads t ON t.surface = 'ember' AND t.channel = 'EMBER' AND t.thread_ts = m.thread_ts;
      INSERT INTO said
        SELECT t.id, i.ts, 'person', i.user, i.text, NULL, NULL, MIN(i.received_at) FROM inbound i
        JOIN threads t ON t.surface = surface_of(i.connect) AND t.channel = i.channel AND t.thread_ts = i.thread_ts
        WHERE NOT EXISTS (SELECT 1 FROM said s WHERE s.thread = t.id AND s.ts = i.ts)
        GROUP BY t.id, i.ts;
      INSERT INTO messages (rev, thread, ts, author_kind, author, text, attachments, quotes, created_at)
        SELECT ROW_NUMBER() OVER (ORDER BY created_at, CAST(ts AS REAL)), thread, ts, author_kind, author, text, attachments, quotes, created_at
        FROM said ORDER BY created_at, CAST(ts AS REAL);
      DROP TABLE said;

      INSERT OR IGNORE INTO deliveries (message, session, delivered_at)
        SELECT m.seq, i.session_key, CASE i.status WHEN 'delivered' THEN i.received_at END FROM inbound i
        JOIN threads t ON t.surface = surface_of(i.connect) AND t.channel = i.channel AND t.thread_ts = i.thread_ts
        JOIN messages m ON m.thread = t.id AND m.ts = i.ts;

      DROP TABLE inbound;
      DROP TABLE chat_messages;
      DROP TABLE chats;
      ALTER TABLE sessions DROP COLUMN channel;
      ALTER TABLE sessions DROP COLUMN thread_ts;
      ALTER TABLE sessions ADD COLUMN archived_at INTEGER;
    `);
  },
};

/** Where a Slack connect's threads live: its team, or the connect itself while the team is unknown. */
export function slackSurface(connect: string, teamId: string | null | undefined): string {
  return teamId ? `slack:${teamId}` : `slack:${connect}`;
}

const TABLES = `
CREATE TABLE IF NOT EXISTS threads (
  id INTEGER PRIMARY KEY,
  surface TEXT NOT NULL,
  channel TEXT NOT NULL,
  thread_ts TEXT NOT NULL,
  title TEXT,
  created_by TEXT,
  created_at INTEGER NOT NULL,
  UNIQUE (surface, channel, thread_ts)
);
CREATE TABLE IF NOT EXISTS thread_sessions (
  thread INTEGER NOT NULL,
  session TEXT NOT NULL,
  connect TEXT NOT NULL,
  joined_at INTEGER NOT NULL,
  PRIMARY KEY (thread, session)
);
CREATE INDEX IF NOT EXISTS thread_sessions_session ON thread_sessions (session);
CREATE TABLE IF NOT EXISTS messages (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  rev INTEGER NOT NULL UNIQUE,
  thread INTEGER NOT NULL,
  ts TEXT NOT NULL,
  author_kind TEXT NOT NULL,
  author TEXT NOT NULL,
  text TEXT NOT NULL,
  attachments TEXT,
  quotes TEXT,
  declared TEXT,
  created_at INTEGER NOT NULL,
  edited_at INTEGER,
  deleted_at INTEGER,
  UNIQUE (thread, ts)
);
CREATE INDEX IF NOT EXISTS messages_thread_rev ON messages (thread, rev);
CREATE TABLE IF NOT EXISTS deliveries (
  message INTEGER NOT NULL,
  session TEXT NOT NULL,
  delivered_at INTEGER,
  PRIMARY KEY (message, session)
);
CREATE INDEX IF NOT EXISTS deliveries_pending ON deliveries (session) WHERE delivered_at IS NULL;
CREATE INDEX IF NOT EXISTS deliveries_session ON deliveries (session, message);
CREATE TABLE IF NOT EXISTS reads (
  viewer TEXT NOT NULL,
  thread INTEGER NOT NULL,
  seq INTEGER NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (viewer, thread)
);
CREATE TABLE IF NOT EXISTS profile_status (
  profile TEXT PRIMARY KEY,
  check_json TEXT, checked_at INTEGER,
  quota_json TEXT, quota_at INTEGER
);
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

function toMessage(row: Row): MessageRow {
  return {
    seq: row.seq as number, rev: row.rev as number, thread: row.thread as number, ts: row.ts as string,
    authorKind: row.author_kind as AuthorKind, author: row.author as string, text: row.text as string,
    attachments: row.attachments ? JSON.parse(row.attachments as string) as Attachment[] : [],
    quotes: row.quotes ? JSON.parse(row.quotes as string) as Quote[] : [],
    declared: (row.declared as string | null) ?? null, createdAt: row.created_at as number,
    editedAt: (row.edited_at as number | null) ?? null, deletedAt: (row.deleted_at as number | null) ?? null,
  };
}

const json = (value: unknown[] | undefined): string | null => (value?.length ? JSON.stringify(value) : null);

/**
 * `changes` emits:
 * - "session" (key): anything about that session changed;
 * - "session-removed" (key): it was deleted;
 * - "thread" ({ id, rev, messages }): messages were said, edited or deleted there, or its sessions changed (no messages);
 * - "read" ({ viewer, thread, seq }): a viewer's read position moved;
 * - "identities" (viewer): the Slack users a viewer said are them changed;
 * - "processes": the recorded runtime processes changed.
 */
export class Store {
  readonly #db: DatabaseSync;
  readonly changes = new EventEmitter();

  /** `teams` names the Slack team of each connect, for moving older data into threads (see MIGRATIONS). */
  constructor(path: string, options: { teams?: ReadonlyMap<string, string> } = {}) {
    if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true });
    this.#db = new DatabaseSync(path);
    this.#db.exec("PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;");
    let version = Store.#version(this.#db);
    if (version !== null) {
      while (version < SCHEMA_VERSION) {
        const step = MIGRATIONS[version];
        if (step === undefined) throw new Error(`${path} has schema version ${version}, which ember ${SCHEMA_VERSION} cannot migrate; move it aside`);
        this.#transaction(() => {
          step(this.#db, { teams: options.teams ?? new Map() });
          this.#db.exec(`PRAGMA user_version = ${version! + 1}`);
        });
        version++;
      }
      if (version > SCHEMA_VERSION) throw new Error(`${path} was written by a newer ember (schema ${version})`);
    }
    this.#db.exec(SCHEMA);
    this.#db.exec(`PRAGMA user_version = ${SCHEMA_VERSION}`);
  }

  /** Whether opening `path` will move data into threads, which wants the connects' Slack teams. */
  static needsTeams(path: string): boolean {
    if (path === ":memory:" || !existsSync(path)) return false;
    const db = new DatabaseSync(path);
    try {
      const version = Store.#version(db);
      return version !== null && version < 10;
    } finally {
      db.close();
    }
  }

  /** The schema version of a database with ember's tables, or null for an empty one. */
  static #version(db: DatabaseSync): number | null {
    const hasTables = db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sessions'").get() !== undefined;
    return hasTables ? (db.prepare("PRAGMA user_version").get() as Row).user_version as number : null;
  }

  close(): void {
    this.#db.close();
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

  setTitle(key: string, title: string | null): void {
    this.#db.prepare("UPDATE sessions SET title = ? WHERE key = ?").run(title, key);
    this.notify(key);
  }

  touch(key: string): void {
    this.#db.prepare("UPDATE sessions SET last_active_at = ? WHERE key = ?").run(Date.now(), key);
  }

  /** Hides a session from lists, or shows it again. */
  setArchived(key: string, archived: boolean): void {
    this.#db.prepare("UPDATE sessions SET archived_at = ? WHERE key = ?").run(archived ? Date.now() : null, key);
    this.notify(key);
  }

  /**
   * Forgets a session: its row, turns, deliveries, memberships and bindings,
   * and the threads only it took part in, with their messages and reads.
   */
  deleteSession(key: string): void {
    const { kept } = this.#transaction(() => {
      const threads = (this.#db.prepare("SELECT thread FROM thread_sessions WHERE session = ?").all(key) as Row[]).map((r) => r.thread as number);
      this.#db.prepare("DELETE FROM thread_sessions WHERE session = ?").run(key);
      this.#db.prepare("DELETE FROM deliveries WHERE session = ?").run(key);
      this.#db.prepare("DELETE FROM turns WHERE session_key = ?").run(key);
      this.#db.prepare("DELETE FROM bindings WHERE session_key = ?").run(key);
      this.#db.prepare("DELETE FROM sessions WHERE key = ?").run(key);
      const kept: number[] = [];
      for (const thread of threads) {
        if (this.#db.prepare("SELECT 1 FROM thread_sessions WHERE thread = ? LIMIT 1").get(thread) !== undefined) {
          kept.push(thread);
          continue;
        }
        this.#db.prepare("DELETE FROM deliveries WHERE message IN (SELECT seq FROM messages WHERE thread = ?)").run(thread);
        this.#db.prepare("DELETE FROM messages WHERE thread = ?").run(thread);
        this.#db.prepare("DELETE FROM reads WHERE thread = ?").run(thread);
        this.#db.prepare("DELETE FROM threads WHERE id = ?").run(thread);
      }
      return { kept };
    });
    // Threads that went with it need no event of their own: they belonged to the removed session.
    this.changes.emit("session-removed", key);
    for (const thread of kept) this.#threadChanged(thread, []);
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
      this.#threadChanged(thread, []);
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
    const row = (this.#db.prepare(`SELECT t.*, ts.connect FROM deliveries d JOIN messages m ON m.seq = d.message
        JOIN threads t ON t.id = m.thread JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = d.session
        WHERE d.session = ? ORDER BY d.message DESC LIMIT 1`).get(session)
      ?? this.#db.prepare(`SELECT t.*, ts.connect FROM thread_sessions ts JOIN threads t ON t.id = ts.thread
        WHERE ts.session = ? ORDER BY ts.joined_at DESC, ts.rowid DESC LIMIT 1`).get(session)) as Row | undefined;
    return row ? { ...toThread(row), connect: row.connect as string } : undefined;
  }

  /**
   * Threads with their sessions, last message and the viewer's unread count,
   * most recently active first: those of one session, one thread, or all.
   */
  listThreads(viewer: string, filter: { session?: string; thread?: number } = {}): ThreadSummary[] {
    const where = filter.thread !== undefined ? "WHERE t.id = ?" : filter.session !== undefined ? "WHERE t.id IN (SELECT thread FROM thread_sessions WHERE session = ?)" : "";
    const params = filter.thread ?? filter.session;
    const rows = this.#db.prepare(`
      SELECT t.*, COALESCE(r.seq, 0) AS read_seq,
        (SELECT MAX(rev) FROM messages m WHERE m.thread = t.id) AS rev,
        (SELECT MAX(seq) FROM messages m WHERE m.thread = t.id) AS last_seq,
        (SELECT COUNT(*) FROM messages m WHERE m.thread = t.id AND m.seq > COALESCE(r.seq, 0) AND m.deleted_at IS NULL
          AND NOT (m.author_kind = 'person' AND (m.author = ? OR (t.surface != '${EMBER_SURFACE}'
            AND m.author IN (SELECT slack_user FROM identities WHERE viewer = ?))))) AS unread,
        (SELECT substr(m.text, 1, 300) FROM messages m WHERE m.thread = t.id AND m.author_kind = 'person' AND m.deleted_at IS NULL
          ORDER BY m.seq LIMIT 1) AS first_text
      FROM threads t LEFT JOIN reads r ON r.thread = t.id AND r.viewer = ?
      ${where}
      ORDER BY COALESCE(last_seq, 0) DESC, t.created_at DESC, t.id DESC
    `).all(...(params === undefined ? [viewer, viewer, viewer] : [viewer, viewer, viewer, params])) as Row[];
    return rows.map((r) => {
      const last = r.last_seq == null ? undefined : this.#db.prepare("SELECT * FROM messages WHERE seq = ?").get(r.last_seq as number) as Row | undefined;
      return {
        ...toThread(r), sessions: this.threadSessions(r.id as number), last: last ? toMessage(last) : null,
        rev: (r.rev as number | null) ?? 0, read: r.read_seq as number, unread: r.unread as number,
        people: this.#threadPeople(r.id as number, r.surface as string), firstText: (r.first_text as string | null) ?? null,
      };
    });
  }

  /** Everyone who wrote in a thread, as creator references (a Slack user through a connect in it), earliest first. */
  #threadPeople(thread: number, surface: string): string[] {
    const connect = (this.#db.prepare("SELECT MIN(connect) AS connect FROM thread_sessions WHERE thread = ?").get(thread) as Row).connect as string | null;
    const authors = (this.#db.prepare(`SELECT author, MIN(seq) AS first FROM messages WHERE thread = ? AND author_kind = 'person'
      GROUP BY author ORDER BY first`).all(thread) as Row[]).map((r) => r.author as string);
    if (surface === EMBER_SURFACE) return authors;
    return connect ? authors.map((author) => `slack:${connect}:${author}`) : [];
  }

  // ── messages ────────────────────────────────────────────────────────────

  /**
   * Records something said. A message already recorded in that thread (Slack
   * delivers to every connect in the channel, and redelivers) is the same
   * message: its seq comes back with `fresh` false and nothing changes.
   */
  insertMessage(m: Omit<MessageRow, "seq" | "rev" | "createdAt" | "editedAt" | "deletedAt" | "attachments" | "quotes" | "declared"> & {
    attachments?: Attachment[]; quotes?: Quote[]; declared?: string | null; createdAt?: number;
  }): { seq: number; fresh: boolean } {
    const inserted = this.#transaction(() => {
      const existing = this.#db.prepare("SELECT seq FROM messages WHERE thread = ? AND ts = ?").get(m.thread, m.ts) as Row | undefined;
      if (existing) return { seq: existing.seq as number, fresh: false };
      const result = this.#db.prepare(`INSERT INTO messages (rev, thread, ts, author_kind, author, text, attachments, quotes, declared, created_at)
        VALUES (${NEXT_REV}, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
        .run(m.thread, m.ts, m.authorKind, m.author, m.text, json(m.attachments), json(m.quotes), m.declared ?? null, m.createdAt ?? Date.now());
      return { seq: Number(result.lastInsertRowid), fresh: true };
    });
    if (inserted.fresh) this.#threadChanged(m.thread, [inserted.seq]);
    return inserted;
  }

  /** A platform edit. Returns the thread, or undefined for a message ember never recorded or whose words did not change. */
  editMessage(surface: string, channel: string, ts: string, text: string): number | undefined {
    return this.#change(surface, channel, ts, "text = ?, edited_at = ?", [text, Date.now()], (m) => m.text !== text && m.deleted_at === null);
  }

  /** A platform delete: words and files go, the row stays so cursors hold. */
  deleteMessage(surface: string, channel: string, ts: string): number | undefined {
    return this.#change(surface, channel, ts, "text = '', attachments = NULL, quotes = NULL, deleted_at = ?", [Date.now()], (m) => m.deleted_at === null);
  }

  /** Changes a recorded message where `applies`, taking the next rev. Returns its thread, or undefined when nothing changed. */
  #change(surface: string, channel: string, ts: string, set: string, values: (string | number)[], applies: (row: Row) => boolean): number | undefined {
    const row = this.#transaction(() => {
      const found = this.#db.prepare(`SELECT m.* FROM messages m JOIN threads t ON t.id = m.thread
        WHERE t.surface = ? AND t.channel = ? AND m.ts = ?`).get(surface, channel, ts) as Row | undefined;
      if (!found || !applies(found)) return undefined;
      this.#db.prepare(`UPDATE messages SET ${set}, rev = ${NEXT_REV} WHERE seq = ?`).run(...values, found.seq as number);
      return found;
    });
    if (!row) return undefined;
    this.#threadChanged(row.thread as number, [row.seq as number]);
    return row.thread as number;
  }

  getMessage(seq: number): MessageRow | undefined {
    const row = this.#db.prepare("SELECT * FROM messages WHERE seq = ?").get(seq) as Row | undefined;
    return row ? toMessage(row) : undefined;
  }

  messageAt(thread: number, ts: string): MessageRow | undefined {
    const row = this.#db.prepare("SELECT * FROM messages WHERE thread = ? AND ts = ?").get(thread, ts) as Row | undefined;
    return row ? toMessage(row) : undefined;
  }

  /** Every message of the thread said, edited or deleted after cursor `rev`, in thread order. */
  messagesAfter(thread: number, rev: number): MessageRow[] {
    return (this.#db.prepare("SELECT * FROM messages WHERE thread = ? AND rev > ? ORDER BY seq").all(thread, rev) as Row[]).map(toMessage);
  }

  /** The latest `limit` messages of the thread before `seq` (all when absent), oldest first. */
  messagesBefore(thread: number, seq: number | undefined, limit: number): MessageRow[] {
    return (this.#db.prepare("SELECT * FROM messages WHERE thread = ? AND seq < ? ORDER BY seq DESC LIMIT ?")
      .all(thread, seq ?? Number.MAX_SAFE_INTEGER, limit) as Row[]).reverse().map(toMessage);
  }

  /** The thread's latest rev, 0 before anything is said. */
  threadRev(thread: number): number {
    return ((this.#db.prepare("SELECT MAX(rev) AS rev FROM messages WHERE thread = ?").get(thread) as Row).rev as number | null) ?? 0;
  }

  #threadChanged(thread: number, seqs: number[]): void {
    const messages = seqs.map((seq) => this.getMessage(seq)).filter((m): m is MessageRow => Boolean(m));
    this.changes.emit("thread", { id: thread, rev: this.threadRev(thread), messages });
  }

  // ── deliveries ─────────────────────────────────────────────────────────

  /** Hands a message to sessions. Returns those that did not have it yet. */
  deliver(seq: number, sessions: readonly string[]): string[] {
    const stmt = this.#db.prepare("INSERT OR IGNORE INTO deliveries (message, session) VALUES (?, ?)");
    const added = sessions.filter((s) => stmt.run(seq, s).changes > 0);
    for (const key of added) this.notify(key);
    return added;
  }

  /** What the session has yet to read, in the order it was said. */
  pendingMessages(session: string): PendingMessage[] {
    return (this.#db.prepare(`SELECT m.*, t.surface, t.channel, t.thread_ts, ts.connect FROM deliveries d
      JOIN messages m ON m.seq = d.message JOIN threads t ON t.id = m.thread
      JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = d.session
      WHERE d.session = ? AND d.delivered_at IS NULL ORDER BY m.seq`).all(session) as Row[])
      .map((r) => ({ ...toMessage(r), surface: r.surface as string, channel: r.channel as string, threadTs: r.thread_ts as string, connect: r.connect as string }));
  }

  markDelivered(session: string, seqs: readonly number[]): void {
    const stmt = this.#db.prepare("UPDATE deliveries SET delivered_at = ? WHERE message = ? AND session = ? AND delivered_at IS NULL");
    const now = Date.now();
    for (const seq of seqs) stmt.run(now, seq, session);
    if (seqs.length) this.notify(session);
  }

  /** Threads the session has already read something from. */
  heardThreads(session: string): Set<number> {
    return new Set((this.#db.prepare(`SELECT DISTINCT m.thread FROM deliveries d JOIN messages m ON m.seq = d.message
      WHERE d.session = ? AND d.delivered_at IS NOT NULL`).all(session) as Row[]).map((r) => r.thread as number));
  }

  sessionsWithPending(): string[] {
    return (this.#db.prepare("SELECT DISTINCT session FROM deliveries WHERE delivered_at IS NULL").all() as Row[]).map((r) => r.session as string);
  }

  /** Everyone who wrote in each session's threads, as creator references, earliest first. */
  participants(session?: string): Map<string, string[]> {
    const out = new Map<string, string[]>();
    const rows = this.#db.prepare(`SELECT ts.session, t.surface, MIN(ts.connect) AS connect, m.author, MIN(m.seq) AS first
      FROM thread_sessions ts JOIN threads t ON t.id = ts.thread JOIN messages m ON m.thread = ts.thread AND m.author_kind = 'person'
      ${session ? "WHERE ts.session = ?" : ""}
      GROUP BY ts.session, t.surface, m.author ORDER BY first`).all(...(session ? [session] : [])) as Row[];
    for (const r of rows) {
      const ref = r.surface === EMBER_SURFACE ? r.author as string : `slack:${r.connect as string}:${r.author as string}`;
      const key = r.session as string;
      const refs = out.get(key) ?? [];
      if (!refs.includes(ref)) out.set(key, [...refs, ref]);
    }
    return out;
  }

  // ── reads ───────────────────────────────────────────────────────────────

  /** Moves a viewer's read position forward (never back). Returns where it is now. */
  setRead(viewer: string, thread: number, seq: number): number {
    this.#db.prepare(`INSERT INTO reads (viewer, thread, seq, at) VALUES (?, ?, ?, ?)
      ON CONFLICT (viewer, thread) DO UPDATE SET seq = MAX(seq, excluded.seq), at = excluded.at`).run(viewer, thread, seq, Date.now());
    const now = (this.#db.prepare("SELECT seq FROM reads WHERE viewer = ? AND thread = ?").get(viewer, thread) as Row).seq as number;
    this.changes.emit("read", { viewer, thread, seq: now });
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
        (SELECT substr(m.text, 1, 300) FROM deliveries d JOIN messages m ON m.seq = d.message WHERE d.session = s.key ORDER BY d.message LIMIT 1) AS first_text,
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

/** The next change cursor, taken inside the statement's transaction. */
const NEXT_REV = "(SELECT COALESCE(MAX(rev), 0) + 1 FROM messages)";
