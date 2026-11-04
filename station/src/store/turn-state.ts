import { randomBytes } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";

export const TURN_COUNT_BATCH = 64;
export const TURN_COUNT_FIRST = `SELECT started_at, rowid AS rid FROM turns INDEXED BY turns_by_session
  WHERE session_key = ?1 AND started_at = ?2 AND rowid <= ?3 ORDER BY rowid DESC LIMIT ?4`;
export const TURN_COUNT_AFTER = `SELECT started_at, rowid AS rid FROM turns INDEXED BY turns_by_session
  WHERE session_key = ?1 AND started_at = ?2 AND rowid < ?3 ORDER BY rowid DESC LIMIT ?4`;
export const TURN_COUNT_EARLIER = `SELECT started_at, rowid AS rid FROM turns INDEXED BY turns_by_session
  WHERE session_key = ?1 AND started_at < ?2 ORDER BY started_at DESC, rowid DESC LIMIT ?3`;

type Position = { started_at: bigint; rid: bigint };
export type TurnCountScan = { session: string; token: string; n: number; boundary: Position; after: Position | null; finished: boolean };
type Step = { done: boolean; visited: number; scan: TurnCountScan | null };

/// Count one requested session in short indexed slices. Writes to its turns invalidate the guard; the last write
/// transaction verifies it before publishing, so slices from different snapshots cannot form a stale count. Appends
/// after the original end are counted in the guard and do not invalidate a long scan.
export function turnCountStep(db: DatabaseSync, session: string, scan: TurnCountScan | null, limit = TURN_COUNT_BATCH,
  mayWrite?: () => boolean): Step {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > TURN_COUNT_BATCH) throw new RangeError("turn count batch must be between 1 and 64");
  if (scan !== null && scan.session !== session) throw new Error("turn count belongs to another session");
  const done = (): Step => ({ done: true, visited: 0, scan: null });
  const counted = () => db.prepare("SELECT 1 FROM session_turns WHERE session = ?").get(session) !== undefined;
  const hasTurns = () => db.prepare("SELECT 1 FROM turns INDEXED BY turns_by_session WHERE session_key = ? LIMIT 1").get(session) !== undefined;
  if (scan === null) {
    if (counted() || !hasTurns()) return done();
    if (mayWrite && !mayWrite()) return { done: false, visited: 0, scan: null };
    db.exec("BEGIN IMMEDIATE");
    try {
      if (counted() || !hasTurns()) { db.exec("COMMIT"); return done(); }
      const token = randomBytes(16).toString("hex");
      const latest = db.prepare(`SELECT started_at, rowid AS rid FROM turns INDEXED BY turns_by_session
        WHERE session_key = ? ORDER BY started_at DESC, rowid DESC LIMIT 1`);
      latest.setReadBigInts(true);
      const boundary = latest.get(session) as Position;
      db.prepare(`INSERT INTO session_turns_guard(session, token, boundary_at, boundary_rowid, appended) VALUES (?, ?, ?, ?, 0)
        ON CONFLICT(session) DO UPDATE SET token = excluded.token, boundary_at = excluded.boundary_at,
          boundary_rowid = excluded.boundary_rowid, appended = 0`).run(session, token, boundary.started_at, boundary.rid);
      db.exec("COMMIT");
      return { done: false, visited: 0, scan: { session, token, n: 0, boundary, after: null, finished: false } };
    } catch (error) {
      try { db.exec("ROLLBACK"); } catch {}
      throw error;
    }
  }
  const guard = () => db.prepare("SELECT token, appended FROM session_turns_guard WHERE session = ?").get(session) as { token: string; appended: number } | undefined;
  if (guard()?.token !== scan.token) return { done: false, visited: 0, scan: null };
  let visited = 0;
  if (!scan.finished) {
    const before = scan.after ?? scan.boundary;
    const statement = db.prepare(scan.after === null ? TURN_COUNT_FIRST : TURN_COUNT_AFTER);
    statement.setReadBigInts(true);
    const rows = statement.all(session, before.started_at, before.rid, limit) as Position[];
    if (rows.length < limit) {
      const earlier = db.prepare(TURN_COUNT_EARLIER);
      earlier.setReadBigInts(true);
      rows.push(...earlier.all(session, before.started_at, limit - rows.length) as Position[]);
    }
    visited = rows.length;
    scan.n += visited;
    if (rows.length > 0) scan.after = rows.at(-1)!;
    scan.finished = rows.length < limit;
  }
  if (!scan.finished || (mayWrite && !mayWrite())) return { done: false, visited, scan };
  db.exec("BEGIN IMMEDIATE");
  try {
    const current = guard();
    if (current?.token !== scan.token) { db.exec("COMMIT"); return { done: false, visited, scan: null }; }
    const count = scan.n + current.appended;
    if (count > 0) db.prepare("INSERT INTO session_turns (session, n) VALUES (?, ?)").run(session, count);
    db.prepare("DELETE FROM session_turns_guard WHERE session = ? AND token = ?").run(session, scan.token);
    db.exec("COMMIT");
    return { done: true, visited, scan: null };
  } catch (error) {
    try { db.exec("ROLLBACK"); } catch {}
    throw error;
  }
}
