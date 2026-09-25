// All durable ember state, in one SQLite file. Runtime transcripts stay in the
// runtimes' own homes; this only records what ember needs to route and resume.
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";
import type { RuntimeKind } from "./config.ts";

export interface SessionRow {
  key: string;
  channel: string;
  threadTs: string;
  runtime: RuntimeKind;
  profile: string;
  model: string | null;
  runtimeSessionId: string | null;
  workspace: string;
  token: string;
  /** A turn was running when this was last written; true after a crash means the turn was cut off. */
  running: boolean;
  createdAt: number;
  lastActiveAt: number;
}

export interface InboundRow {
  channel: string;
  ts: string;
  sessionKey: string;
  user: string;
  text: string;
  status: "pending" | "delivered";
  receivedAt: number;
}

export type TurnKind = "input" | "nudge" | "resume";

const SCHEMA = `
CREATE TABLE IF NOT EXISTS sessions (
  key TEXT PRIMARY KEY,
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
  last_active_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS inbound (
  channel TEXT NOT NULL,
  ts TEXT NOT NULL,
  session_key TEXT NOT NULL,
  user TEXT NOT NULL,
  text TEXT NOT NULL,
  status TEXT NOT NULL,
  received_at INTEGER NOT NULL,
  PRIMARY KEY (channel, ts)
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
    channel: row.channel as string,
    threadTs: row.thread_ts as string,
    runtime: row.runtime as RuntimeKind,
    profile: row.profile as string,
    model: (row.model as string | null) ?? null,
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
    channel: row.channel as string,
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

  constructor(path: string) {
    if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true });
    this.#db = new DatabaseSync(path);
    this.#db.exec("PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;");
    this.#db.exec(SCHEMA);
  }

  close(): void {
    this.#db.close();
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

  insertSession(s: Omit<SessionRow, "running" | "runtimeSessionId">): void {
    this.#db.prepare(`INSERT INTO sessions (key, channel, thread_ts, runtime, profile, model, workspace, token, created_at, last_active_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .run(s.key, s.channel, s.threadTs, s.runtime, s.profile, s.model, s.workspace, s.token, s.createdAt, s.lastActiveAt);
  }

  setRuntimeSessionId(key: string, id: string): void {
    this.#db.prepare("UPDATE sessions SET runtime_session_id = ? WHERE key = ?").run(id, key);
  }

  setRunning(key: string, running: boolean): void {
    this.#db.prepare("UPDATE sessions SET running = ?, last_active_at = ? WHERE key = ?").run(running ? 1 : 0, Date.now(), key);
  }

  // ── inbound messages ───────────────────────────────────────────────────

  /** Records a message; false if it was already recorded (Slack delivers mentions twice). */
  insertInbound(m: Omit<InboundRow, "status">): boolean {
    const result = this.#db.prepare(`INSERT OR IGNORE INTO inbound (channel, ts, session_key, user, text, status, received_at)
      VALUES (?, ?, ?, ?, ?, 'pending', ?)`).run(m.channel, m.ts, m.sessionKey, m.user, m.text, m.receivedAt);
    return result.changes > 0;
  }

  pendingInbound(sessionKey: string): InboundRow[] {
    return (this.#db.prepare("SELECT * FROM inbound WHERE session_key = ? AND status = 'pending' ORDER BY ts")
      .all(sessionKey) as Row[]).map(toInbound);
  }

  markDelivered(rows: readonly InboundRow[]): void {
    const stmt = this.#db.prepare("UPDATE inbound SET status = 'delivered' WHERE channel = ? AND ts = ?");
    for (const r of rows) stmt.run(r.channel, r.ts);
  }

  sessionsWithPendingInbound(): string[] {
    return (this.#db.prepare("SELECT DISTINCT session_key FROM inbound WHERE status = 'pending'").all() as Row[])
      .map((r) => r.session_key as string);
  }

  // ── turns ───────────────────────────────────────────────────────────────

  startTurn(id: string, sessionKey: string, kind: TurnKind): void {
    this.#db.prepare("INSERT INTO turns (id, session_key, kind, started_at) VALUES (?, ?, ?, ?)").run(id, sessionKey, kind, Date.now());
  }

  endTurn(id: string, outcome: string, detail: string | null, declared: string | null): void {
    this.#db.prepare("UPDATE turns SET ended_at = ?, outcome = ?, detail = ?, declared = ? WHERE id = ?")
      .run(Date.now(), outcome, detail, declared, id);
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
