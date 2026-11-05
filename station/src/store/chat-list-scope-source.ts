// Bounded sources for preparing a workspace's recent-chat index. The caller must journal changes while building:
// a session or membership moved behind a cursor cannot be found by these scans alone. It must also persist a step's
// rows and cursor in the same transaction.
import type { DatabaseSync } from "node:sqlite";

export type RecentScopeSessionCursor = { connect: string | null; after: bigint | null; done: boolean };
export type RecentScopeSession = { rowid: bigint; key: string };

export const FIRST_SCOPE_CONNECT = "SELECT connect FROM sessions INDEXED BY sessions_by_connect ORDER BY connect LIMIT 1";
export const NEXT_SCOPE_CONNECT = "SELECT connect FROM sessions INDEXED BY sessions_by_connect WHERE connect > ? ORDER BY connect LIMIT 1";
export const SCOPE_SESSIONS = `SELECT rowid, key FROM sessions INDEXED BY sessions_by_connect
  WHERE connect = ?1 AND ws = ?2 AND rowid > ?3 ORDER BY rowid LIMIT ?4`;
export const FIRST_SCOPE_SESSIONS = `SELECT rowid, key FROM sessions INDEXED BY sessions_by_connect
  WHERE connect = ?1 AND ws = ?2 ORDER BY rowid LIMIT ?3`;
export const FIRST_SCOPE_SESSIONS_THROUGH = `SELECT rowid, key FROM sessions INDEXED BY sessions_by_connect
  WHERE connect = ?1 AND ws = ?2 AND rowid <= ?3 ORDER BY rowid LIMIT ?4`;
export const SCOPE_SESSIONS_THROUGH = `SELECT rowid, key FROM sessions INDEXED BY sessions_by_connect
  WHERE connect = ?1 AND ws = ?2 AND rowid > ?3 AND rowid <= ?4 ORDER BY rowid LIMIT ?5`;
// Fallback source: limit raw session rows before testing their workspace, so each transaction stays bounded.
export const FIRST_SCOPE_OLD_SESSION = "SELECT rowid, key, ws FROM sessions WHERE rowid <= ?1 ORDER BY rowid LIMIT 1";
export const NEXT_SCOPE_OLD_SESSION = "SELECT rowid, key, ws FROM sessions WHERE rowid > ?1 AND rowid <= ?2 ORDER BY rowid LIMIT 1";

/// One step visits at most one connection's `limit` sessions. A connection with none is advanced in its own step,
/// so even a station with many connections does not hold a write transaction while searching through them all.
export function recentScopeSessionsStep(db: DatabaseSync, workspace: string, cursor: RecentScopeSessionCursor,
  limit: number, through?: bigint): { sessions: RecentScopeSession[]; cursor: RecentScopeSessionCursor } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent scope session batch must be positive");
  if (cursor.done) return { sessions: [], cursor };
  const connect = cursor.connect ?? (db.prepare(FIRST_SCOPE_CONNECT).get() as { connect: string } | undefined)?.connect ?? null;
  if (connect === null) return { sessions: [], cursor: { connect: null, after: null, done: true } };
  const query = db.prepare(through === undefined ? (cursor.after === null ? FIRST_SCOPE_SESSIONS : SCOPE_SESSIONS)
    : (cursor.after === null ? FIRST_SCOPE_SESSIONS_THROUGH : SCOPE_SESSIONS_THROUGH));
  query.setReadBigInts(true);
  const sessions = (through === undefined
    ? (cursor.after === null ? query.all(connect, workspace, limit) : query.all(connect, workspace, cursor.after, limit))
    : (cursor.after === null ? query.all(connect, workspace, through, limit)
      : query.all(connect, workspace, cursor.after, through, limit))) as RecentScopeSession[];
  if (sessions.length === limit) return { sessions, cursor: { connect, after: sessions.at(-1)!.rowid, done: false } };
  const next = (db.prepare(NEXT_SCOPE_CONNECT).get(connect) as { connect: string } | undefined)?.connect ?? null;
  return { sessions, cursor: { connect: next, after: null, done: next === null } };
}

export type RecentScopeThreadCursor = { phase: "home" | "members" | "done"; after: bigint | null };
export const FIRST_SCOPE_HOME_THREADS = "SELECT id AS thread FROM threads INDEXED BY threads_home WHERE home = ?1 ORDER BY id LIMIT ?2";
export const SCOPE_HOME_THREADS = "SELECT id AS thread FROM threads INDEXED BY threads_home WHERE home = ?1 AND id > ?2 ORDER BY id LIMIT ?3";
export const FIRST_SCOPE_MEMBER_THREADS = `SELECT rowid, thread FROM thread_sessions INDEXED BY thread_sessions_session
  WHERE session = ?1 ORDER BY rowid LIMIT ?2`;
export const SCOPE_MEMBER_THREADS = `SELECT rowid, thread FROM thread_sessions INDEXED BY thread_sessions_session
  WHERE session = ?1 AND rowid > ?2 ORDER BY rowid LIMIT ?3`;
export const SCOPE_MEMBER_WITHOUT_HOME = "SELECT 1 FROM threads WHERE id = ? AND home IS NULL";

/// For a session already found in this workspace, find its home chats and then its member chats without a home.
/// Apply the home check after limiting source memberships: otherwise a long run of ineligible members could make a
/// SQL LIMIT read an unbounded number of rows. `visited` is the number of source rows, not just the matches.
export function recentScopeSessionThreadsStep(db: DatabaseSync, session: string, cursor: RecentScopeThreadCursor,
  limit: number): { threads: bigint[]; visited: number; cursor: RecentScopeThreadCursor } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent scope thread batch must be positive");
  if (cursor.phase === "done") return { threads: [], visited: 0, cursor };
  if (cursor.phase === "home") {
    const query = db.prepare(cursor.after === null ? FIRST_SCOPE_HOME_THREADS : SCOPE_HOME_THREADS);
    query.setReadBigInts(true);
    const rows = (cursor.after === null ? query.all(session, limit) : query.all(session, cursor.after, limit)) as { thread: bigint }[];
    return { threads: rows.map((row) => row.thread), visited: rows.length,
      cursor: rows.length === limit ? { phase: "home", after: rows.at(-1)!.thread } : { phase: "members", after: null } };
  }
  const query = db.prepare(cursor.after === null ? FIRST_SCOPE_MEMBER_THREADS : SCOPE_MEMBER_THREADS);
  query.setReadBigInts(true);
  const rows = (cursor.after === null ? query.all(session, limit) : query.all(session, cursor.after, limit)) as { rowid: bigint; thread: bigint }[];
  const eligible = db.prepare(SCOPE_MEMBER_WITHOUT_HOME);
  const threads = rows.filter((row) => eligible.get(row.thread) !== undefined).map((row) => row.thread);
  return { threads, visited: rows.length,
    cursor: rows.length === limit ? { phase: "members", after: rows.at(-1)!.rowid } : { phase: "done", after: null } };
}
