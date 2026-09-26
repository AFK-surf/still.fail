// All durable ember state, in one SQLite file. Runtime transcripts stay in the
// runtimes' own homes; this only records what ember needs to route and resume.
import { EventEmitter } from "node:events";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";
import type { RuntimeKind } from "./config.ts";

/** thread: started by one thread (multi-session connects); all: takes every thread of the connects bound to it (single-session). */
export type SessionScope = "thread" | "all";

export interface SessionRow {
  key: string;
  /** The connect that started it. Replies go through the connect each thread came from. */
  connect: string;
  scope: SessionScope;
  /** A name people gave it, for choosing among single-session sessions. */
  title: string | null;
  /**
   * Who started it: "slack:<connect>:<user>" for a chat message, an email for
   * someone on ember cloud, "local" for the station's own page; null if unknown.
   */
  createdBy: string | null;
  /**
   * The thread of the session's first message; empty for a session created
   * before any message. ember's own notices go to the latest thread instead.
   */
  channel: string;
  threadTs: string;
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
}

export interface InboundRow {
  connect: string;
  channel: string;
  /** The thread the message belongs to (its own ts for a thread root). */
  threadTs: string;
  ts: string;
  sessionKey: string;
  user: string;
  text: string;
  status: "pending" | "delivered";
  receivedAt: number;
}

/** A chat on ember's admin page, bound to one session. Its thread_ts is its address. */
export interface ChatRow {
  threadTs: string;
  sessionKey: string;
  title: string | null;
  createdBy: string;
  createdAt: number;
}

export interface ChatMessageRow {
  threadTs: string;
  ts: string;
  /** person: typed on the admin page; agent: posted by the agent (or an ember notice). */
  role: "person" | "agent";
  user: string;
  text: string;
  createdAt: number;
  /** Files sent with the message, stored in the session's workspace. */
  attachments?: Attachment[];
  /** Passages of earlier messages this one answers, Zork-style comments. */
  quotes?: Quote[];
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

function toChat(row: Row): ChatRow {
  return {
    threadTs: row.thread_ts as string, sessionKey: row.session_key as string, title: (row.title as string | null) ?? null,
    createdBy: row.created_by as string, createdAt: row.created_at as number,
  };
}

export type TurnKind = "input" | "nudge" | "resume";

/**
 * Bump on schema changes and add a step to MIGRATIONS that brings the
 * previous version up. Versions without a migration path are refused.
 */
const SCHEMA_VERSION = 9;

const MIGRATIONS: Record<number, string> = {
  // v2 → v3: bots became connects; sessions may span all threads; messages remember their thread.
  2: `
    ALTER TABLE sessions RENAME COLUMN bot TO connect;
    ALTER TABLE sessions ADD COLUMN scope TEXT NOT NULL DEFAULT 'thread';
    ALTER TABLE inbound RENAME COLUMN bot TO connect;
    ALTER TABLE inbound ADD COLUMN thread_ts TEXT NOT NULL DEFAULT '';
    UPDATE inbound SET thread_ts = COALESCE((SELECT s.thread_ts FROM sessions s WHERE s.key = inbound.session_key), ts);
  `,
  // v3 → v4: a single-session connect delivers into the session bound to it, which people may choose.
  3: `
    ALTER TABLE sessions ADD COLUMN title TEXT;
    CREATE TABLE bindings (connect TEXT PRIMARY KEY, session_key TEXT NOT NULL);
    INSERT INTO bindings (connect, session_key) SELECT connect, key FROM sessions WHERE scope = 'all';
  `,
  // v4 → v5: ember's own chat, opened on a session from the admin page. Tables only, created below.
  4: "",
  // v5 → v6: who started a session.
  5: "ALTER TABLE sessions ADD COLUMN created_by TEXT;",
  // v6 → v7: the reasoning effort a session runs with.
  6: "ALTER TABLE sessions ADD COLUMN effort TEXT;",
  // v7 → v8: files sent with a chat message.
  7: "ALTER TABLE chat_messages ADD COLUMN attachments TEXT;",
  // v8 → v9: passages of earlier messages quoted in a message, with what was said about each.
  8: "ALTER TABLE chat_messages ADD COLUMN quotes TEXT;",
};

const SCHEMA = `
CREATE TABLE IF NOT EXISTS sessions (
  key TEXT PRIMARY KEY,
  connect TEXT NOT NULL,
  channel TEXT NOT NULL,
  thread_ts TEXT NOT NULL,
  runtime TEXT NOT NULL,
  profile TEXT NOT NULL,
  model TEXT,
  runtime_session_id TEXT,
  workspace TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  running INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  last_active_at INTEGER NOT NULL,
  scope TEXT NOT NULL DEFAULT 'thread',
  title TEXT,
  created_by TEXT,
  effort TEXT
);
CREATE TABLE IF NOT EXISTS chats (
  thread_ts TEXT PRIMARY KEY,
  session_key TEXT NOT NULL,
  title TEXT,
  created_by TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS chat_messages (
  thread_ts TEXT NOT NULL,
  ts TEXT NOT NULL,
  role TEXT NOT NULL,
  user TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  attachments TEXT,
  quotes TEXT,
  PRIMARY KEY (thread_ts, ts)
);
CREATE TABLE IF NOT EXISTS bindings (
  connect TEXT PRIMARY KEY,
  session_key TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS inbound (
  connect TEXT NOT NULL,
  channel TEXT NOT NULL,
  ts TEXT NOT NULL,
  session_key TEXT NOT NULL,
  user TEXT NOT NULL,
  text TEXT NOT NULL,
  status TEXT NOT NULL,
  received_at INTEGER NOT NULL,
  thread_ts TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (connect, channel, ts)
);
CREATE INDEX IF NOT EXISTS inbound_pending ON inbound (session_key, status, ts);
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
`;

type Row = Record<string, unknown>;

function toSession(row: Row): SessionRow {
  return {
    key: row.key as string,
    connect: row.connect as string,
    scope: (row.scope as SessionScope | undefined) ?? "thread",
    title: (row.title as string | null | undefined) ?? null,
    createdBy: (row.created_by as string | null | undefined) ?? null,
    channel: row.channel as string,
    threadTs: row.thread_ts as string,
    runtime: row.runtime as RuntimeKind,
    profile: row.profile as string,
    model: (row.model as string | null) ?? null,
    effort: (row.effort as string | null | undefined) ?? null,
    runtimeSessionId: (row.runtime_session_id as string | null) ?? null,
    workspace: row.workspace as string,
    token: row.token as string,
    running: row.running === 1,
    createdAt: row.created_at as number,
    lastActiveAt: row.last_active_at as number,
  };
}

function toInbound(row: Row): InboundRow {
  return {
    connect: row.connect as string,
    channel: row.channel as string,
    threadTs: row.thread_ts as string,
    ts: row.ts as string,
    sessionKey: row.session_key as string,
    user: row.user as string,
    text: row.text as string,
    status: row.status as InboundRow["status"],
    receivedAt: row.received_at as number,
  };
}

export class Store {
  readonly #db: DatabaseSync;
  /** Emits "session" with a session key whenever anything about that session changes. */
  readonly changes = new EventEmitter();

  constructor(path: string) {
    if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true });
    this.#db = new DatabaseSync(path);
    this.#db.exec("PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;");
    let version = (this.#db.prepare("PRAGMA user_version").get() as Row).user_version as number;
    const hasTables = this.#db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sessions'").get() !== undefined;
    if (hasTables) {
      while (version < SCHEMA_VERSION) {
        const step = MIGRATIONS[version];
        if (step === undefined) throw new Error(`${path} has schema version ${version}, which ember ${SCHEMA_VERSION} cannot migrate; move it aside`);
        this.#db.exec(`BEGIN; ${step} PRAGMA user_version = ${version + 1}; COMMIT;`);
        version++;
      }
      if (version > SCHEMA_VERSION) throw new Error(`${path} was written by a newer ember (schema ${version})`);
    }
    this.#db.exec(SCHEMA);
    this.#db.exec(`PRAGMA user_version = ${SCHEMA_VERSION}`);
  }

  close(): void {
    this.#db.close();
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

  listSessions(): SessionRow[] {
    return (this.#db.prepare("SELECT * FROM sessions ORDER BY last_active_at DESC").all() as Row[]).map(toSession);
  }

  insertSession(s: Omit<SessionRow, "running" | "runtimeSessionId" | "title" | "createdBy" | "effort"> & { title?: string | null; createdBy?: string | null; effort?: string | null }): void {
    this.#db.prepare(`INSERT INTO sessions (key, connect, scope, title, created_by, channel, thread_ts, runtime, profile, model, effort, workspace, token, created_at, last_active_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .run(s.key, s.connect, s.scope, s.title ?? null, s.createdBy ?? null, s.channel, s.threadTs, s.runtime, s.profile, s.model, s.effort ?? null, s.workspace, s.token, s.createdAt, s.lastActiveAt);
    this.notify(s.key);
  }

  /** Remembers the thread of a session created before any message. */
  setFirstThread(key: string, channel: string, threadTs: string): void {
    this.#db.prepare("UPDATE sessions SET channel = ?, thread_ts = ? WHERE key = ? AND channel = ''").run(channel, threadTs, key);
  }

  setTitle(key: string, title: string | null): void {
    this.#db.prepare("UPDATE sessions SET title = ? WHERE key = ?").run(title, key);
    this.notify(key);
  }

  touch(key: string): void {
    this.#db.prepare("UPDATE sessions SET last_active_at = ? WHERE key = ?").run(Date.now(), key);
  }

  // ── single-session bindings ────────────────────────────────────────────

  /** The session a single-session connect delivers into, if one is bound. */
  binding(connect: string): string | undefined {
    const row = this.#db.prepare("SELECT session_key FROM bindings WHERE connect = ?").get(connect) as Row | undefined;
    return row ? row.session_key as string : undefined;
  }

  /** Binds a connect to a session, or unbinds it (null) so its next message starts a new one. */
  setBinding(connect: string, sessionKey: string | null): void {
    if (sessionKey) this.#db.prepare("INSERT OR REPLACE INTO bindings (connect, session_key) VALUES (?, ?)").run(connect, sessionKey);
    else this.#db.prepare("DELETE FROM bindings WHERE connect = ?").run(connect);
    if (sessionKey) this.notify(sessionKey);
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

  // ── inbound messages ───────────────────────────────────────────────────

  /** Records a message for one connect; false if it was already recorded (Slack delivers mentions twice). */
  insertInbound(m: Omit<InboundRow, "status">): boolean {
    const result = this.#db.prepare(`INSERT OR IGNORE INTO inbound (connect, channel, thread_ts, ts, session_key, user, text, status, received_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?)`).run(m.connect, m.channel, m.threadTs, m.ts, m.sessionKey, m.user, m.text, m.receivedAt);
    if (result.changes > 0) this.notify(m.sessionKey);
    return result.changes > 0;
  }

  pendingInbound(sessionKey: string): InboundRow[] {
    return (this.#db.prepare("SELECT * FROM inbound WHERE session_key = ? AND status = 'pending' ORDER BY ts")
      .all(sessionKey) as Row[]).map(toInbound);
  }

  markDelivered(rows: readonly InboundRow[]): void {
    const stmt = this.#db.prepare("UPDATE inbound SET status = 'delivered' WHERE connect = ? AND channel = ? AND ts = ?");
    for (const r of rows) stmt.run(r.connect, r.channel, r.ts);
    for (const key of new Set(rows.map((r) => r.sessionKey))) this.notify(key);
  }

  /** Everyone who wrote in each session, as creator references, earliest first. */
  participants(): Map<string, string[]> {
    const out = new Map<string, string[]>();
    const rows = this.#db.prepare("SELECT session_key, connect, user, MIN(CAST(ts AS REAL)) AS first FROM inbound GROUP BY session_key, connect, user ORDER BY first").all() as Row[];
    for (const r of rows) {
      const ref = r.connect === "ember" ? r.user as string : `slack:${r.connect as string}:${r.user as string}`;
      const key = r.session_key as string;
      out.set(key, [...(out.get(key) ?? []), ref]);
    }
    return out;
  }

  /** The session's most recent message: where ember's own notices go. */
  latestInbound(sessionKey: string): InboundRow | undefined {
    const row = this.#db.prepare("SELECT * FROM inbound WHERE session_key = ? ORDER BY CAST(ts AS REAL) DESC LIMIT 1").get(sessionKey) as Row | undefined;
    return row ? toInbound(row) : undefined;
  }

  /** Which connect a thread of this session came through, if it is one of its threads. */
  threadConnect(sessionKey: string, channel: string, threadTs: string): string | undefined {
    const row = this.#db.prepare("SELECT connect FROM inbound WHERE session_key = ? AND channel = ? AND thread_ts = ? ORDER BY ts DESC LIMIT 1")
      .get(sessionKey, channel, threadTs) as Row | undefined;
    return row ? row.connect as string : undefined;
  }

  /** Whether the session already has messages from this thread, i.e. is part of that conversation. */
  inThread(sessionKey: string, channel: string, threadTs: string): boolean {
    return this.#db.prepare("SELECT 1 FROM inbound WHERE session_key = ? AND channel = ? AND thread_ts = ? LIMIT 1")
      .get(sessionKey, channel, threadTs) !== undefined;
  }

  /** The threads a session has messages from, most recent first. */
  listThreads(sessionKey: string): { channel: string; threadTs: string; messages: number; lastTs: string }[] {
    return (this.#db.prepare(`SELECT channel, thread_ts, COUNT(*) AS n, MAX(ts) AS last FROM inbound
      WHERE session_key = ? GROUP BY channel, thread_ts ORDER BY MAX(CAST(ts AS REAL)) DESC`).all(sessionKey) as Row[])
      .map((r) => ({ channel: r.channel as string, threadTs: r.thread_ts as string, messages: r.n as number, lastTs: r.last as string }));
  }

  sessionsWithPendingInbound(): string[] {
    return (this.#db.prepare("SELECT DISTINCT session_key FROM inbound WHERE status = 'pending'").all() as Row[])
      .map((r) => r.session_key as string);
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

  listTurns(sessionKey: string): { id: string; kind: TurnKind; outcome: string | null; detail: string | null; declared: string | null; startedAt: number; endedAt: number | null }[] {
    return (this.#db.prepare("SELECT * FROM turns WHERE session_key = ? ORDER BY started_at").all(sessionKey) as Row[]).map((r) => ({
      id: r.id as string, kind: r.kind as TurnKind, outcome: (r.outcome as string | null) ?? null,
      detail: (r.detail as string | null) ?? null, declared: (r.declared as string | null) ?? null,
      startedAt: r.started_at as number, endedAt: (r.ended_at as number | null) ?? null,
    }));
  }

  /** Per session: turn count, the latest turn, and undelivered messages. For listings. */
  sessionStats(): Map<string, { turns: number; pending: number; firstText: string | null; lastTurn: { kind: string; outcome: string | null; declared: string | null; detail: string | null; startedAt: number; endedAt: number | null } | null }> {
    const rows = this.#db.prepare(`
      SELECT s.key,
        (SELECT COUNT(*) FROM turns t WHERE t.session_key = s.key) AS turns,
        (SELECT COUNT(*) FROM inbound i WHERE i.session_key = s.key AND i.status = 'pending') AS pending,
        (SELECT substr(text, 1, 300) FROM inbound i WHERE i.session_key = s.key ORDER BY ts LIMIT 1) AS first_text,
        l.kind, l.outcome, l.declared, l.detail, l.started_at, l.ended_at
      FROM sessions s
      LEFT JOIN turns l ON l.id = (SELECT id FROM turns t2 WHERE t2.session_key = s.key ORDER BY t2.started_at DESC LIMIT 1)
    `).all() as Row[];
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

  listInbound(sessionKey: string): InboundRow[] {
    return (this.#db.prepare("SELECT * FROM inbound WHERE session_key = ? ORDER BY ts").all(sessionKey) as Row[]).map(toInbound);
  }

  // ── ember's own chats ──────────────────────────────────────────────────

  insertChat(chat: ChatRow): void {
    this.#db.prepare("INSERT INTO chats (thread_ts, session_key, title, created_by, created_at) VALUES (?, ?, ?, ?, ?)")
      .run(chat.threadTs, chat.sessionKey, chat.title, chat.createdBy, chat.createdAt);
    this.notify(chat.sessionKey);
  }

  getChat(threadTs: string): ChatRow | undefined {
    const row = this.#db.prepare("SELECT * FROM chats WHERE thread_ts = ?").get(threadTs) as Row | undefined;
    return row ? toChat(row) : undefined;
  }

  listChats(sessionKey: string): ChatRow[] {
    return (this.#db.prepare("SELECT * FROM chats WHERE session_key = ? ORDER BY created_at").all(sessionKey) as Row[]).map(toChat);
  }

  insertChatMessage(m: ChatMessageRow): void {
    this.#db.prepare("INSERT INTO chat_messages (thread_ts, ts, role, user, text, created_at, attachments, quotes) VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
      .run(m.threadTs, m.ts, m.role, m.user, m.text, m.createdAt, m.attachments?.length ? JSON.stringify(m.attachments) : null, m.quotes?.length ? JSON.stringify(m.quotes) : null);
    const chat = this.getChat(m.threadTs);
    if (chat) this.notify(chat.sessionKey);
  }

  /** A chat's messages oldest first; with `before`, only older ones, the latest `limit` of them. */
  chatMessages(threadTs: string, before?: string, limit = 1000): ChatMessageRow[] {
    const rows = (before
      ? this.#db.prepare("SELECT * FROM chat_messages WHERE thread_ts = ? AND CAST(ts AS REAL) < CAST(? AS REAL) ORDER BY CAST(ts AS REAL) DESC LIMIT ?").all(threadTs, before, limit)
      : this.#db.prepare("SELECT * FROM chat_messages WHERE thread_ts = ? ORDER BY CAST(ts AS REAL) DESC LIMIT ?").all(threadTs, limit)) as Row[];
    return rows.reverse().map((r) => ({
      threadTs: r.thread_ts as string, ts: r.ts as string, role: r.role as ChatMessageRow["role"],
      user: r.user as string, text: r.text as string, createdAt: r.created_at as number,
      ...(r.attachments ? { attachments: JSON.parse(r.attachments as string) as Attachment[] } : {}),
      ...(r.quotes ? { quotes: JSON.parse(r.quotes as string) as Quote[] } : {}),
    }));
  }

  // ── runtime process groups ─────────────────────────────────────────────

  recordProcess(pgid: number, startedAt: number, runtime: RuntimeKind, label: string): void {
    this.#db.prepare("INSERT OR REPLACE INTO processes (pgid, started_at, runtime, label) VALUES (?, ?, ?, ?)")
      .run(pgid, startedAt, runtime, label);
  }

  forgetProcess(pgid: number): void {
    this.#db.prepare("DELETE FROM processes WHERE pgid = ?").run(pgid);
  }

  listProcesses(): { pgid: number; startedAt: number; runtime: RuntimeKind; label: string }[] {
    return (this.#db.prepare("SELECT * FROM processes").all() as Row[]).map((r) => ({
      pgid: r.pgid as number, startedAt: r.started_at as number, runtime: r.runtime as RuntimeKind, label: r.label as string,
    }));
  }
}
