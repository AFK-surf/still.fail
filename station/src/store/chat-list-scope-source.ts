// A bounded source for preparing a workspace's recent-chat index. The caller must journal session changes while
// building: a session moved behind the cursor cannot be found by this scan alone.
import type { DatabaseSync } from "node:sqlite";

export type RecentScopeSessionCursor = { connect: string | null; after: bigint | null; done: boolean };
export type RecentScopeSession = { rowid: bigint; key: string };

export const FIRST_SCOPE_CONNECT = "SELECT connect FROM sessions INDEXED BY sessions_by_connect ORDER BY connect LIMIT 1";
export const NEXT_SCOPE_CONNECT = "SELECT connect FROM sessions INDEXED BY sessions_by_connect WHERE connect > ? ORDER BY connect LIMIT 1";
export const SCOPE_SESSIONS = `SELECT rowid, key FROM sessions INDEXED BY sessions_by_connect
  WHERE connect = ?1 AND ws = ?2 AND rowid > ?3 ORDER BY rowid LIMIT ?4`;
export const FIRST_SCOPE_SESSIONS = `SELECT rowid, key FROM sessions INDEXED BY sessions_by_connect
  WHERE connect = ?1 AND ws = ?2 ORDER BY rowid LIMIT ?3`;

/// One step visits at most one connection's `limit` sessions. A connection with none is advanced in its own step,
/// so even a station with many connections does not hold a write transaction while searching through them all.
export function recentScopeSessionsStep(db: DatabaseSync, workspace: string, cursor: RecentScopeSessionCursor,
  limit: number): { sessions: RecentScopeSession[]; cursor: RecentScopeSessionCursor } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent scope session batch must be positive");
  if (cursor.done) return { sessions: [], cursor };
  const connect = cursor.connect ?? (db.prepare(FIRST_SCOPE_CONNECT).get() as { connect: string } | undefined)?.connect ?? null;
  if (connect === null) return { sessions: [], cursor: { connect: null, after: null, done: true } };
  const query = db.prepare(cursor.after === null ? FIRST_SCOPE_SESSIONS : SCOPE_SESSIONS);
  query.setReadBigInts(true);
  const sessions = (cursor.after === null ? query.all(connect, workspace, limit)
    : query.all(connect, workspace, cursor.after, limit)) as RecentScopeSession[];
  if (sessions.length === limit) return { sessions, cursor: { connect, after: sessions.at(-1)!.rowid, done: false } };
  const next = (db.prepare(NEXT_SCOPE_CONNECT).get(connect) as { connect: string } | undefined)?.connect ?? null;
  return { sessions, cursor: { connect: next, after: null, done: next === null } };
}
