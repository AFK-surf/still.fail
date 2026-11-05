import type { DatabaseSync } from "node:sqlite";

// A projection only for sessions whose copy destinations have been requested. A thread change is distributed in
// batches; a dirty session cannot be read until every relevant distribution and its own reconciliation have ended.
const VERSION = 1;
const orderChange = (thread: string) => `
  INSERT INTO cc_order_dispatch(thread, after_session, through_session)
    SELECT ${thread}, NULL, (SELECT session FROM cc_session_rows INDEXED BY cc_rows_thread
      WHERE thread=${thread} ORDER BY session DESC LIMIT 1) WHERE ${thread} IS NOT NULL
      AND EXISTS (SELECT 1 FROM cc_session_rows INDEXED BY cc_rows_thread WHERE thread=${thread} LIMIT 1)
      AND NOT EXISTS (SELECT 1 FROM cc_order_dispatch WHERE thread=${thread});`;
const memberChange = (thread: string, session: string) => `
  INSERT INTO cc_session_dirty(session, thread)
    SELECT ${session}, ${thread} WHERE ${session} IS NOT NULL AND ${thread} IS NOT NULL
      AND EXISTS (SELECT 1 FROM cc_sessions WHERE session=${session})
      AND NOT EXISTS (SELECT 1 FROM cc_session_dirty WHERE session=${session} AND thread=${thread});`;
const displacedMemberThread = "(SELECT thread FROM thread_sessions WHERE rowid=NEW.rowid)";
const displacedMemberSession = "(SELECT session FROM thread_sessions WHERE rowid=NEW.rowid)";
const displacedEntry = "(SELECT thread FROM entries WHERE rowid=NEW.rowid)";
const displacedThread = `(SELECT id FROM threads WHERE surface=NEW.surface AND channel=NEW.channel
  AND thread_ts=NEW.thread_ts)`;

export function installCcIndex(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='cc_index_meta'").get() !== undefined;
  if (installed()) { checkCcIndex(db); return; }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE cc_index_meta (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL) WITHOUT ROWID;
      INSERT INTO cc_index_meta VALUES(1, ${VERSION});
      CREATE TABLE cc_sessions (session TEXT PRIMARY KEY, scan_after INTEGER, scan_end INTEGER,
        complete INTEGER NOT NULL DEFAULT 0) WITHOUT ROWID;
      -- Keep memberships whose thread is missing or currently internal too: a later thread write may expose them.
      CREATE TABLE cc_session_rows (session TEXT NOT NULL, thread INTEGER NOT NULL, surface TEXT,
        created_at INTEGER, last_at INTEGER, PRIMARY KEY(session,thread)) WITHOUT ROWID;
      CREATE INDEX cc_session_order ON cc_session_rows(session,last_at DESC,created_at DESC,thread DESC)
        WHERE surface != 'ember';
      CREATE INDEX cc_rows_thread ON cc_session_rows(thread,session);
      CREATE TABLE cc_session_dirty (session TEXT NOT NULL, thread INTEGER NOT NULL,
        PRIMARY KEY(session,thread)) WITHOUT ROWID;
      CREATE TABLE cc_order_dispatch (thread INTEGER PRIMARY KEY, after_session TEXT, through_session TEXT NOT NULL);
      CREATE TABLE cc_order_turn (id INTEGER PRIMARY KEY CHECK(id=1), after_thread INTEGER, through_thread INTEGER);
      INSERT INTO cc_order_turn VALUES(1,NULL,NULL);

      -- An old writer can replace a different membership by rowid without a DELETE trigger.
      CREATE TRIGGER cc_member_before_add BEFORE INSERT ON thread_sessions BEGIN
        ${memberChange("NEW.thread", "NEW.session")}
        ${memberChange(displacedMemberThread, displacedMemberSession)}
      END;
      CREATE TRIGGER cc_member_add AFTER INSERT ON thread_sessions BEGIN ${memberChange("NEW.thread", "NEW.session")} END;
      CREATE TRIGGER cc_member_before_change BEFORE UPDATE ON thread_sessions
        WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session OR OLD.rowid IS NOT NEW.rowid BEGIN
          ${memberChange("OLD.thread", "OLD.session")}
          ${memberChange("NEW.thread", "NEW.session")}
          ${memberChange(displacedMemberThread, displacedMemberSession)}
      END;
      CREATE TRIGGER cc_member_change AFTER UPDATE ON thread_sessions
        WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session OR OLD.rowid IS NOT NEW.rowid BEGIN
          ${memberChange("NEW.thread", "NEW.session")}
      END;
      CREATE TRIGGER cc_member_drop AFTER DELETE ON thread_sessions BEGIN ${memberChange("OLD.thread", "OLD.session")} END;

      -- A row added behind a running distributor's cursor stays dirty until that distribution has ended.
      CREATE TRIGGER cc_row_add AFTER INSERT ON cc_session_rows
        WHEN EXISTS (SELECT 1 FROM cc_order_dispatch WHERE thread=NEW.thread) BEGIN
          ${memberChange("NEW.thread", "NEW.session")}
      END;

      CREATE TRIGGER cc_thread_before_add BEFORE INSERT ON threads BEGIN
        ${orderChange("NEW.id")} ${orderChange(displacedThread)}
      END;
      CREATE TRIGGER cc_thread_add AFTER INSERT ON threads BEGIN ${orderChange("NEW.id")} END;
      CREATE TRIGGER cc_thread_before_change BEFORE UPDATE ON threads
        WHEN OLD.id IS NOT NEW.id OR OLD.surface IS NOT NEW.surface OR OLD.created_at IS NOT NEW.created_at
          OR OLD.channel IS NOT NEW.channel OR OLD.thread_ts IS NOT NEW.thread_ts BEGIN
        ${orderChange("OLD.id")} ${orderChange("NEW.id")} ${orderChange(displacedThread)}
      END;
      CREATE TRIGGER cc_thread_change AFTER UPDATE ON threads
        WHEN OLD.id IS NOT NEW.id OR OLD.surface IS NOT NEW.surface OR OLD.created_at IS NOT NEW.created_at
          OR OLD.channel IS NOT NEW.channel OR OLD.thread_ts IS NOT NEW.thread_ts BEGIN
        ${orderChange("OLD.id")} ${orderChange("NEW.id")}
      END;
      CREATE TRIGGER cc_thread_drop AFTER DELETE ON threads BEGIN ${orderChange("OLD.id")} END;

      -- Track the source of the original query's timestamp, including manual changes and REPLACE by rowid.
      CREATE TRIGGER cc_state_add AFTER INSERT ON thread_state BEGIN ${orderChange("NEW.thread")} END;
      CREATE TRIGGER cc_state_change AFTER UPDATE OF thread,last_n ON thread_state
        WHEN OLD.thread IS NOT NEW.thread OR OLD.last_n IS NOT NEW.last_n BEGIN
          ${orderChange("OLD.thread")} ${orderChange("NEW.thread")}
      END;
      CREATE TRIGGER cc_state_drop AFTER DELETE ON thread_state BEGIN ${orderChange("OLD.thread")} END;
      CREATE TRIGGER cc_entry_before_add BEFORE INSERT ON entries BEGIN ${orderChange(displacedEntry)} END;
      CREATE TRIGGER cc_entry_add AFTER INSERT ON entries BEGIN ${orderChange("NEW.thread")} END;
      CREATE TRIGGER cc_entry_before_change BEFORE UPDATE OF rowid,_rowid_,oid,thread,n,ts,at ON entries BEGIN
        ${orderChange("OLD.thread")} ${orderChange("NEW.thread")} ${orderChange(displacedEntry)}
      END;
      CREATE TRIGGER cc_entry_change AFTER UPDATE OF rowid,_rowid_,oid,thread,n,ts,at ON entries BEGIN
        ${orderChange("OLD.thread")} ${orderChange("NEW.thread")}
      END;
      CREATE TRIGGER cc_entry_drop AFTER DELETE ON entries BEGIN ${orderChange("OLD.thread")} END;
    `);
    else checkCcIndex(db);
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function checkCcIndex(db: DatabaseSync): void {
  const row = db.prepare("SELECT version FROM cc_index_meta WHERE id=1").get() as { version: number } | undefined;
  if (row?.version !== VERSION) throw new Error(`copy destination index version ${row?.version ?? "missing"} is incompatible with ${VERSION}`);
}

export function trackCcSession(db: DatabaseSync, session: string): void {
  checkCcIndex(db);
  db.exec("BEGIN IMMEDIATE");
  try {
    db.prepare(`INSERT INTO cc_sessions(session,scan_end)
      SELECT ?1,(SELECT rowid FROM thread_sessions INDEXED BY thread_sessions_session
        WHERE session=?1 ORDER BY rowid DESC LIMIT 1)
      WHERE NOT EXISTS (SELECT 1 FROM cc_sessions WHERE session=?1)`).run(session);
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

function reconcile(db: DatabaseSync, session: string, thread: bigint): void {
  db.prepare(`DELETE FROM cc_session_rows WHERE session=?1 AND thread=?2 AND NOT EXISTS
    (SELECT 1 FROM thread_sessions WHERE session=?1 AND thread=?2)`).run(session, thread);
  db.prepare(`INSERT INTO cc_session_rows(session,thread,surface,created_at,last_at)
    SELECT m.session,m.thread,t.surface,t.created_at,e.at FROM thread_sessions m
    LEFT JOIN threads t ON t.id=m.thread LEFT JOIN thread_state st ON st.thread=t.id
    LEFT JOIN entries e ON e.thread=st.thread AND e.n=st.last_n
    WHERE m.session=?1 AND m.thread=?2
    ON CONFLICT(session,thread) DO UPDATE SET surface=excluded.surface,
      created_at=excluded.created_at,last_at=excluded.last_at
    WHERE surface IS NOT excluded.surface OR created_at IS NOT excluded.created_at OR last_at IS NOT excluded.last_at`)
    .run(session, thread);
}

export function scanCcSessionStep(db: DatabaseSync, session: string, limit = 64): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 128) throw new RangeError("copy destination batch must be between 1 and 128");
  db.exec("BEGIN IMMEDIATE");
  try {
    checkCcIndex(db);
    const scopeQuery = db.prepare("SELECT scan_after,scan_end,complete FROM cc_sessions WHERE session=?");
    scopeQuery.setReadBigInts(true);
    const scope = scopeQuery.get(session) as { scan_after: bigint | null; scan_end: bigint | null; complete: bigint } | undefined;
    if (!scope) throw new Error("copy destination session is not tracked");
    if (scope.complete === 1n) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const rowsQuery = db.prepare(scope.scan_after === null
      ? `SELECT rowid,thread FROM thread_sessions INDEXED BY thread_sessions_session
          WHERE session=?1 AND rowid<=?2 ORDER BY rowid LIMIT ?3`
      : `SELECT rowid,thread FROM thread_sessions INDEXED BY thread_sessions_session
          WHERE session=?1 AND rowid>?2 AND rowid<=?3 ORDER BY rowid LIMIT ?4`);
    rowsQuery.setReadBigInts(true);
    const rows = (scope.scan_after === null ? rowsQuery.all(session, scope.scan_end, limit)
      : rowsQuery.all(session, scope.scan_after, scope.scan_end, limit)) as { rowid: bigint; thread: bigint }[];
    for (const row of rows) reconcile(db, session, row.thread);
    const done = rows.length < limit;
    db.prepare("UPDATE cc_sessions SET scan_after=?,complete=? WHERE session=?")
      .run(rows.at(-1)?.rowid ?? scope.scan_after, done ? 1 : 0, session);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function dispatchCcOrderStep(db: DatabaseSync, limit = 64): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 128) throw new RangeError("copy destination batch must be between 1 and 128");
  db.exec("BEGIN IMMEDIATE");
  try {
    checkCcIndex(db);
    const turn = db.prepare("SELECT after_thread,through_thread FROM cc_order_turn WHERE id=1");
    turn.setReadBigInts(true);
    const progress = turn.get() as { after_thread: bigint | null; through_thread: bigint | null };
    let through = progress.through_thread;
    let pending: { thread: bigint; after_session: string | null; through_session: string } | undefined;
    if (through !== null) {
      const next = db.prepare(progress.after_thread === null
        ? "SELECT thread,after_session,through_session FROM cc_order_dispatch WHERE thread<=? ORDER BY thread LIMIT 1"
        : "SELECT thread,after_session,through_session FROM cc_order_dispatch WHERE thread>? AND thread<=? ORDER BY thread LIMIT 1");
      next.setReadBigInts(true);
      pending = (progress.after_thread === null ? next.get(through) : next.get(progress.after_thread, through)) as typeof pending;
    }
    if (!pending) {
      const last = db.prepare("SELECT MAX(thread) AS thread FROM cc_order_dispatch"); last.setReadBigInts(true);
      through = (last.get() as { thread: bigint | null }).thread;
      if (through === null) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
      const first = db.prepare("SELECT thread,after_session,through_session FROM cc_order_dispatch WHERE thread<=? ORDER BY thread LIMIT 1");
      first.setReadBigInts(true); pending = first.get(through) as typeof pending;
    }
    if (!pending) throw new Error("copy destination dispatch disappeared");
    db.prepare("UPDATE cc_order_turn SET after_thread=?,through_thread=? WHERE id=1").run(pending.thread, through);
    const members = db.prepare(pending.after_session === null
      ? "SELECT session FROM cc_session_rows INDEXED BY cc_rows_thread WHERE thread=?1 AND session<=?2 ORDER BY session LIMIT ?3"
      : "SELECT session FROM cc_session_rows INDEXED BY cc_rows_thread WHERE thread=?1 AND session>?2 AND session<=?3 ORDER BY session LIMIT ?4");
    const rows = (pending.after_session === null ? members.all(pending.thread, pending.through_session, limit)
      : members.all(pending.thread, pending.after_session, pending.through_session, limit)) as { session: string }[];
    const mark = db.prepare(`INSERT INTO cc_session_dirty(session,thread) SELECT ?1,?2 WHERE NOT EXISTS
      (SELECT 1 FROM cc_session_dirty WHERE session=?1 AND thread=?2)`);
    for (const row of rows) mark.run(row.session, pending.thread);
    if (rows.length === limit) db.prepare("UPDATE cc_order_dispatch SET after_session=? WHERE thread=?")
      .run(rows.at(-1)!.session, pending.thread);
    else db.prepare("DELETE FROM cc_order_dispatch WHERE thread=?").run(pending.thread);
    const done = db.prepare("SELECT 1 FROM cc_order_dispatch LIMIT 1").get() === undefined;
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function settleCcSessionStep(db: DatabaseSync, session: string): { done: boolean; visited: number } {
  db.exec("BEGIN IMMEDIATE");
  try {
    checkCcIndex(db);
    if (!db.prepare("SELECT 1 FROM cc_sessions WHERE session=?").get(session)) throw new Error("copy destination session is not tracked");
    const next = db.prepare("SELECT thread FROM cc_session_dirty WHERE session=? ORDER BY thread LIMIT 1");
    next.setReadBigInts(true);
    const row = next.get(session) as { thread: bigint } | undefined;
    if (!row) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    if (db.prepare("SELECT 1 FROM cc_order_dispatch WHERE thread=?").get(row.thread)) {
      db.exec("COMMIT"); return { done: false, visited: 0 };
    }
    reconcile(db, session, row.thread);
    db.prepare("DELETE FROM cc_session_dirty WHERE session=? AND thread=?").run(session, row.thread);
    const done = db.prepare("SELECT 1 FROM cc_session_dirty WHERE session=? LIMIT 1").get(session) === undefined;
    db.exec("COMMIT"); return { done, visited: 1 };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

// The caller must hold the snapshot through the subsequent read. Cap both sides of the intersection; if both are
// large, wait for dispatch rather than performing a history-sized read or returning stale destinations.
export function ccSessionReady(db: DatabaseSync, session: string): boolean {
  checkCcIndex(db);
  const scope = db.prepare("SELECT complete FROM cc_sessions WHERE session=?").get(session) as { complete: number } | undefined;
  if (scope?.complete !== 1 || db.prepare("SELECT 1 FROM cc_session_dirty WHERE session=? LIMIT 1").get(session)) return false;
  const dispatch = db.prepare(`SELECT COUNT(*) AS n, MAX(EXISTS
    (SELECT 1 FROM cc_session_rows r WHERE r.session=?1 AND r.thread=d.thread)) AS affects
    FROM (SELECT thread FROM cc_order_dispatch ORDER BY thread LIMIT 65) d`).get(session) as { n: number; affects: number | null };
  if (dispatch.affects === 1) return false;
  if (dispatch.n <= 64) return true;
  const rows = db.prepare(`SELECT COUNT(*) AS n, MAX(EXISTS
    (SELECT 1 FROM cc_order_dispatch d WHERE d.thread=r.thread)) AS affects
    FROM (SELECT thread FROM cc_session_rows WHERE session=?1 ORDER BY thread LIMIT 65) r`).get(session) as { n: number; affects: number | null };
  return rows.n <= 64 && rows.affects !== 1;
}

export const CC_SESSION_ROWS = `SELECT thread,last_at,created_at FROM cc_session_rows INDEXED BY cc_session_order
  WHERE session=?1 AND surface != 'ember' ORDER BY last_at DESC,created_at DESC,thread DESC LIMIT ?2`;

export function ccSessionRows(db: DatabaseSync, session: string, limit: number): { thread: number; last_at: number | null; created_at: number }[] {
  if (!Number.isSafeInteger(limit) || limit < 0) throw new RangeError("copy destination limit must be nonnegative");
  db.exec("SAVEPOINT cc_destination_read");
  try {
    if (!ccSessionReady(db, session)) throw new Error("copy destinations are still being prepared");
    return db.prepare(CC_SESSION_ROWS).all(session, limit) as { thread: number; last_at: number | null; created_at: number }[];
  } finally { db.exec("RELEASE cc_destination_read"); }
}
