// An expiry-ordered view of the live sessions' latest waiting turns. Recovery still retains expired waits.
import type { DatabaseSync } from "node:sqlite";

// Stay within exact integer arithmetic in both SQLite and JavaScript. An unusual old value uses the sentinel and
// keeps the original JavaScript comparison until that wait changes, rather than guessing how to coerce it.
const HALF_SAFE = 2_251_799_813_685_247;
const SECOND_LIMIT = 2_251_799_813_685;
const UNCERTAIN = "-9007199254740991";
const deadline = `CASE WHEN typeof(t.ended_at) = 'integer' AND t.ended_at BETWEEN -${HALF_SAFE} AND ${HALF_SAFE}
  AND (t.wait_seconds IS NULL OR (typeof(t.wait_seconds) = 'integer' AND t.wait_seconds BETWEEN -${SECOND_LIMIT} AND ${SECOND_LIMIT}))
  THEN t.ended_at + COALESCE(t.wait_seconds, 0) * 1000 ELSE ${UNCERTAIN} END`;
export const awakeDeadline = (key: string) => `(SELECT ${deadline} FROM sessions s
  CROSS JOIN turns t ON t.rowid = (SELECT rowid FROM turns INDEXED BY turns_by_session
    WHERE session_key = s.key ORDER BY started_at DESC, rowid DESC LIMIT 1)
  WHERE s.key = ${key} AND s.archived_at IS NULL AND s.running != 1 AND t.ended_at IS NOT NULL AND t.declared = 'waiting')`;

// These snippets are included in the recovery triggers, including their staged reconciliation of REPLACE writes.
// Updating the recovery row only when its deadline changes avoids writes for unrelated fields.
export const syncAwakeWait = (key: string, guard = "1") => `UPDATE session_recover_waits SET awake_deadline = ${awakeDeadline(key)}
  WHERE session = ${key} AND (${guard}) AND awake_deadline IS NOT ${awakeDeadline(key)};`;
export const reconcileAwakeWaits = (stage: string) => `UPDATE session_recover_waits
  SET awake_deadline = ${awakeDeadline("session_recover_waits.session")}
  WHERE session IN (SELECT session FROM ${stage}) AND awake_deadline IS NOT ${awakeDeadline("session_recover_waits.session")};`;

// A pre-upgrade station may have prepared an INSERT of a recovery key without its deadline. Recompute after every
// insert; guarded insertion also works if recursive triggers are disabled. Each change uses one expiry-ordered tree.
export const AWAKE_WAIT_TRIGGERS = `
  CREATE TRIGGER session_awake_insert AFTER INSERT ON session_recover_waits BEGIN
    ${syncAwakeWait("NEW.session")}
    INSERT INTO session_awake_deadlines (deadline, session)
      SELECT awake_deadline, session FROM session_recover_waits WHERE session = NEW.session AND awake_deadline IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM session_awake_deadlines WHERE deadline = awake_deadline AND session = NEW.session);
  END;
  CREATE TRIGGER session_awake_update AFTER UPDATE OF session, awake_deadline ON session_recover_waits
    WHEN OLD.session IS NOT NEW.session OR OLD.awake_deadline IS NOT NEW.awake_deadline BEGIN
    DELETE FROM session_awake_deadlines WHERE deadline = OLD.awake_deadline AND session = OLD.session;
    INSERT INTO session_awake_deadlines (deadline, session)
      SELECT NEW.awake_deadline, NEW.session WHERE NEW.awake_deadline IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM session_awake_deadlines WHERE deadline = NEW.awake_deadline AND session = NEW.session);
  END;
  CREATE TRIGGER session_awake_delete AFTER DELETE ON session_recover_waits WHEN OLD.awake_deadline IS NOT NULL BEGIN
    DELETE FROM session_awake_deadlines WHERE deadline = OLD.awake_deadline AND session = OLD.session;
  END;`;

export const AWAKE_WAIT_STATUS = `SELECT
  EXISTS (SELECT 1 FROM session_awake_deadlines WHERE deadline = ${UNCERTAIN} LIMIT 1) AS uncertain,
  EXISTS (SELECT 1 FROM session_awake_deadlines WHERE deadline > ? LIMIT 1) AS awake`;
export const AWAKE_BACKFILL_FIRST = "SELECT session FROM session_recover_waits ORDER BY session LIMIT ?";
export const AWAKE_BACKFILL_NEXT = "SELECT session FROM session_recover_waits WHERE session > ? ORDER BY session LIMIT ?";

export function awakeWaitsReady(db: DatabaseSync): boolean {
  return (db.prepare("SELECT complete FROM session_awake_wait_meta WHERE id = 1").get() as { complete: number }).complete === 1;
}

/// The old recovery lookup is prepared first; its entries, the cursor and deadline updates commit together.
export function awakeWaitsStep(db: DatabaseSync, limit = 64): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("awake wait batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const state = db.prepare("SELECT cursor, complete FROM session_awake_wait_meta WHERE id = 1").get() as { cursor: string | null; complete: number };
    if (state.complete === 1) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const recovery = db.prepare("SELECT complete FROM session_recover_wait_meta WHERE id = 1").get() as { complete: number };
    if (recovery.complete !== 1) { db.exec("COMMIT"); return { done: false, visited: 0 }; }
    const rows = (state.cursor === null ? db.prepare(AWAKE_BACKFILL_FIRST).all(limit)
      : db.prepare(AWAKE_BACKFILL_NEXT).all(state.cursor, limit)) as { session: string }[];
    const update = db.prepare(syncAwakeWait("?1"));
    for (const { session } of rows) update.run(session);
    const done = rows.length < limit;
    db.prepare("UPDATE session_awake_wait_meta SET cursor = ?, complete = ? WHERE id = 1")
      .run(rows.at(-1)?.session ?? state.cursor, done ? 1 : 0);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) {
    try { db.exec("ROLLBACK"); } catch {}
    throw error;
  }
}

/// True if the indexed arithmetic and the caller's arithmetic are both exact integers.
export function exactAwakeTime(now: number, linger: number): boolean {
  return Number.isSafeInteger(now) && Number.isSafeInteger(linger) && Math.abs(now) <= HALF_SAFE && Math.abs(linger) <= HALF_SAFE;
}
