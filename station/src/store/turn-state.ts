import { randomBytes } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";

export const TURN_COUNT_BATCH = 64;
export const TURN_COUNT_FIRST = `SELECT started_at, rowid AS rid FROM turns INDEXED BY turns_by_session
  WHERE session_key = ?1 ORDER BY started_at, rowid LIMIT ?2`;
export const TURN_COUNT_AFTER = `SELECT started_at, rowid AS rid FROM turns INDEXED BY turns_by_session
  WHERE session_key = ?1 AND (started_at, rowid) > (?2, ?3) ORDER BY started_at, rowid LIMIT ?4`;

type Position = { started_at: bigint; rid: bigint };
export type TurnCountScan = { session: string; token: string; n: number; after: Position | null; finished: boolean };
type Step = { done: boolean; visited: number; scan: TurnCountScan | null };

/// Count one requested session in short indexed slices. Writes to its turns invalidate the guard; the last write
/// transaction verifies it before publishing, so slices from different snapshots cannot form a stale count.
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
      db.prepare(`INSERT INTO session_turns_guard(session, token) VALUES (?, ?)
        ON CONFLICT(session) DO UPDATE SET token = excluded.token`).run(session, token);
      db.exec("COMMIT");
      return { done: false, visited: 0, scan: { session, token, n: 0, after: null, finished: false } };
    } catch (error) {
      try { db.exec("ROLLBACK"); } catch {}
      throw error;
    }
  }
  const guard = () => db.prepare("SELECT token FROM session_turns_guard WHERE session = ?").get(session) as { token: string } | undefined;
  if (guard()?.token !== scan.token) return { done: false, visited: 0, scan: null };
  let visited = 0;
  if (!scan.finished) {
    const statement = db.prepare(scan.after === null ? TURN_COUNT_FIRST : TURN_COUNT_AFTER);
    statement.setReadBigInts(true);
    const rows = (scan.after === null ? statement.all(session, limit)
      : statement.all(session, scan.after.started_at, scan.after.rid, limit)) as Position[];
    visited = rows.length;
    scan.n += visited;
    if (rows.length > 0) scan.after = rows.at(-1)!;
    scan.finished = rows.length < limit;
  }
  if (!scan.finished || (mayWrite && !mayWrite())) return { done: false, visited, scan };
  db.exec("BEGIN IMMEDIATE");
  try {
    if (guard()?.token !== scan.token) { db.exec("COMMIT"); return { done: false, visited, scan: null }; }
    if (scan.n > 0) db.prepare("INSERT INTO session_turns (session, n) VALUES (?, ?)").run(session, scan.n);
    db.prepare("DELETE FROM session_turns_guard WHERE session = ? AND token = ?").run(session, scan.token);
    db.exec("COMMIT");
    return { done: true, visited, scan: null };
  } catch (error) {
    try { db.exec("ROLLBACK"); } catch {}
    throw error;
  }
}
