import type { DatabaseSync } from "node:sqlite";
import { ccSessionReady, CcIndexPreparation } from "./cc-thread-index.ts";

export const SESSION_CHAT_VERSION = 1;
const VERSION = SESSION_CHAT_VERSION;

// A name uses the last entry itself, including on old databases whose thread_state row is missing. Copy destinations
// use thread_state instead, so their ordering cannot be reused for names. This order starts empty on an old station;
// requested sessions are filled in batches using the copy worker's already-tracked membership set.
const lastAt = (thread: string) => `(SELECT at FROM entries WHERE thread=${thread} ORDER BY n DESC LIMIT 1)`;
const exists = (session: string, thread: string) => `(EXISTS
  (SELECT 1 FROM thread_sessions m JOIN threads t ON t.id=m.thread WHERE m.session=${session} AND m.thread=${thread}))`;
const refresh = (session: string, thread: string) => `UPDATE cc_session_rows SET
    name_present=${exists(session, thread)},
    name_has_last=CASE WHEN ${exists(session, thread)} THEN (${lastAt(thread)} IS NOT NULL) END,
    name_last_at=CASE WHEN ${exists(session, thread)} THEN COALESCE(${lastAt(thread)},0) END,
    name_created_at=(SELECT created_at FROM threads WHERE id=${thread})
  WHERE session=${session} AND thread=${thread}
    AND EXISTS (SELECT 1 FROM session_chat_scopes WHERE session=${session})
    AND (name_present IS NOT ${exists(session, thread)} OR (${exists(session, thread)} AND
      (name_has_last IS NOT (${lastAt(thread)} IS NOT NULL) OR name_last_at IS NOT COALESCE(${lastAt(thread)},0)
        OR name_created_at IS NOT (SELECT created_at FROM threads WHERE id=${thread}))))`;
// A scope may have been removed and recreated while its copy rows survived. Restore its ordered row during the scan.
const ensure = (session: string, thread: string) => `INSERT OR IGNORE INTO session_chat_rows(session,has_last,last_at,created_at,thread)
  SELECT session,name_has_last,name_last_at,name_created_at,thread FROM cc_session_rows
  WHERE session=${session} AND thread=${thread} AND name_present=1
    AND EXISTS (SELECT 1 FROM session_chat_scopes WHERE session=${session})`;

export function installSessionChatIndex(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='session_chat_meta'").get() !== undefined;
  if (installed()) { checkSessionChatIndex(db); return; }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`CREATE TABLE session_chat_meta (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL) WITHOUT ROWID;
  INSERT INTO session_chat_meta VALUES(1,${VERSION});
  CREATE TABLE session_chat_scopes (
    session TEXT PRIMARY KEY, scan_after INTEGER, scan_end INTEGER, complete INTEGER NOT NULL DEFAULT 0
  ) WITHOUT ROWID;
  -- Store the old order key on the already-tracked copy row; this permits one ordered tree for names.
  ALTER TABLE cc_session_rows ADD COLUMN name_present INTEGER NOT NULL DEFAULT 0;
  ALTER TABLE cc_session_rows ADD COLUMN name_has_last INTEGER;
  ALTER TABLE cc_session_rows ADD COLUMN name_last_at;
  ALTER TABLE cc_session_rows ADD COLUMN name_created_at INTEGER;
  CREATE TABLE session_chat_rows (
    session TEXT NOT NULL, has_last INTEGER NOT NULL, last_at NOT NULL, created_at INTEGER NOT NULL, thread INTEGER NOT NULL,
    PRIMARY KEY(session,has_last DESC,last_at DESC,created_at DESC,thread DESC)
  ) WITHOUT ROWID;
  CREATE TRIGGER session_chat_session_drop AFTER DELETE ON sessions BEGIN
    DELETE FROM session_chat_scopes WHERE session=OLD.key;
  END;
  CREATE TRIGGER session_chat_scope_drop AFTER DELETE ON session_chat_scopes BEGIN
    DELETE FROM session_chat_rows WHERE session=OLD.session;
  END;
  CREATE TRIGGER session_chat_cc_drop AFTER DELETE ON cc_session_rows BEGIN
    DELETE FROM session_chat_rows WHERE session=OLD.session AND has_last=OLD.name_has_last AND last_at=OLD.name_last_at
      AND created_at=OLD.name_created_at AND thread=OLD.thread AND OLD.name_present=1;
  END;
  CREATE TRIGGER session_chat_cc_name AFTER UPDATE OF name_present,name_has_last,name_last_at,name_created_at ON cc_session_rows
    WHEN OLD.name_present IS NOT NEW.name_present OR OLD.name_has_last IS NOT NEW.name_has_last
      OR OLD.name_last_at IS NOT NEW.name_last_at OR OLD.name_created_at IS NOT NEW.name_created_at BEGIN
    DELETE FROM session_chat_rows WHERE session=OLD.session AND has_last=OLD.name_has_last AND last_at=OLD.name_last_at
      AND created_at=OLD.name_created_at AND thread=OLD.thread AND OLD.name_present=1;
    INSERT OR IGNORE INTO session_chat_rows(session,has_last,last_at,created_at,thread)
      SELECT NEW.session,NEW.name_has_last,NEW.name_last_at,NEW.name_created_at,NEW.thread
      WHERE NEW.name_present=1 AND EXISTS (SELECT 1 FROM session_chat_scopes WHERE session=NEW.session);
  END;
  -- Name scopes are created only after copy tracking is complete. Later changes become dirty before their copy row
  -- changes; refresh once as that work settles, even if the copy row itself was unchanged (an old partial deletion).
  CREATE TRIGGER session_chat_cc_settled AFTER DELETE ON cc_session_dirty
    WHEN EXISTS (SELECT 1 FROM session_chat_scopes WHERE session=OLD.session) BEGIN
      ${refresh("OLD.session", "OLD.thread")};
      ${ensure("OLD.session", "OLD.thread")};
  END;`);
    else checkSessionChatIndex(db);
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function checkSessionChatIndex(db: DatabaseSync): void {
  const row = db.prepare("SELECT version FROM session_chat_meta WHERE id=1").get() as { version: number } | undefined;
  if (row?.version !== VERSION) throw new Error(`session chat index version ${row?.version ?? "missing"} is incompatible with ${VERSION}`);
}

// NULL entry times sort below non-NULL ones; creation time and thread id break ties in the original order.
export const SESSION_CHAT_INDEXED = `SELECT t.* FROM session_chat_rows r
  CROSS JOIN threads t ON t.id=r.thread WHERE r.session=?1
  ORDER BY r.has_last DESC,r.last_at DESC,r.created_at DESC,r.thread DESC LIMIT 1`;

// Zero or one membership determines the answer without maintaining an order. Do not read the membership's id into
// JavaScript separately: an old orphaned membership may contain an integer outside JavaScript's safe range.
export const SESSION_CHAT_SMALL = `WITH small AS MATERIALIZED
  (SELECT thread FROM thread_sessions INDEXED BY thread_sessions_session WHERE session=?1 LIMIT 2)
  SELECT (SELECT version FROM session_chat_meta WHERE id=1) AS _session_chat_version,
    (SELECT COUNT(*) FROM small) AS _member_count,t.* FROM (SELECT 1) x
  LEFT JOIN threads t ON (SELECT COUNT(*) FROM small)=1 AND t.id=(SELECT thread FROM small LIMIT 1)`;
export const SESSION_CHAT_MANY = `SELECT 1 FROM thread_sessions INDEXED BY thread_sessions_session
  WHERE session=?1 LIMIT 1 OFFSET 1`;

export function sessionChatReady(db: DatabaseSync, session: string): boolean {
  checkSessionChatIndex(db);
  const row = db.prepare("SELECT complete FROM session_chat_scopes WHERE session=?").get(session) as { complete: number } | undefined;
  return row?.complete === 1 && ccSessionReady(db, session);
}

/// Small sessions need no prepared order; the caller reads this and its answer in the same snapshot.
export function sessionChatReadable(db: DatabaseSync, session: string): boolean {
  checkSessionChatIndex(db);
  return db.prepare(SESSION_CHAT_MANY).get(session) === undefined || sessionChatReady(db, session);
}

export class SessionChatUnavailable extends Error {
  constructor() { super("session chat is still being prepared"); }
}

/// Read both readiness and the chosen thread in one SQLite snapshot.
export function indexedSessionChat(db: DatabaseSync, session: string): Record<string, unknown> | null {
  db.exec("SAVEPOINT session_chat_read");
  try {
    checkSessionChatIndex(db);
    const small = db.prepare(SESSION_CHAT_SMALL).get(session) as ({ _member_count: number; id: number | null } & Record<string, unknown>);
    if (small._member_count < 2) return small.id === null ? null : small;
    if (!sessionChatReady(db, session)) throw new SessionChatUnavailable();
    return db.prepare(SESSION_CHAT_INDEXED).get(session) ?? null;
  } finally { db.exec("RELEASE session_chat_read"); }
}

/// Prepare the existing membership set first, then add its ordered rows in bounded key order. Triggers cover changes during the
/// scan, including rows inserted behind its cursor. Every slice and its cursor are committed together.
export class SessionChatPreparation {
  readonly #cc = new CcIndexPreparation();

  cancel(session: string): void { this.#cc.cancel(session); }

  step(db: DatabaseSync, session: string, limit = 64,
    options: { existingSession?: boolean } = {}): { done: boolean; visited: number } {
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 128) throw new RangeError("session chat batch must be between 1 and 128");
    checkSessionChatIndex(db);
    if (options.existingSession && !db.prepare("SELECT 1 FROM sessions WHERE key=?").get(session)) return { done: true, visited: 0 };
    if (!ccSessionReady(db, session)) {
      const progress = this.#cc.step(db, session, limit, options);
      return { done: false, visited: progress.visited };
    }
    db.exec("BEGIN IMMEDIATE");
    try {
      // Another writer may have changed the projection before this transaction took the write lock.
      checkSessionChatIndex(db);
      // A session can disappear while the worker waits for handover or between batches. Never recreate its scope.
      if (options.existingSession && !db.prepare("SELECT 1 FROM sessions WHERE key=?").get(session)) {
        db.exec("COMMIT"); return { done: true, visited: 0 };
      }
      if (!ccSessionReady(db, session)) { db.exec("COMMIT"); return { done: false, visited: 0 }; }
      db.prepare(`INSERT INTO session_chat_scopes(session,scan_end)
        SELECT ?1,(SELECT thread FROM cc_session_rows WHERE session=?1 ORDER BY thread DESC LIMIT 1)
        WHERE NOT EXISTS (SELECT 1 FROM session_chat_scopes WHERE session=?1)`).run(session);
      const scopeQuery = db.prepare("SELECT scan_after,scan_end,complete FROM session_chat_scopes WHERE session=?");
      scopeQuery.setReadBigInts(true);
      const scope = scopeQuery.get(session) as { scan_after: bigint | null; scan_end: bigint | null; complete: bigint };
      if (scope.complete === 1n) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
      const scan = db.prepare(scope.scan_after === null
        ? "SELECT thread FROM cc_session_rows WHERE session=?1 AND thread<=?2 ORDER BY thread LIMIT ?3"
        : "SELECT thread FROM cc_session_rows WHERE session=?1 AND thread>?2 AND thread<=?3 ORDER BY thread LIMIT ?4");
      scan.setReadBigInts(true);
      const rows = (scope.scan_after === null ? scan.all(session, scope.scan_end, limit)
        : scan.all(session, scope.scan_after, scope.scan_end, limit)) as { thread: bigint }[];
      const update = db.prepare(refresh("?1", "?2"));
      const insert = db.prepare(ensure("?1", "?2"));
      for (const row of rows) { update.run(session, row.thread); insert.run(session, row.thread); }
      const done = rows.length < limit;
      db.prepare("UPDATE session_chat_scopes SET scan_after=?,complete=? WHERE session=?")
        .run(rows.at(-1)?.thread ?? scope.scan_after, done ? 1 : 0, session);
      db.exec("COMMIT");
      return { done, visited: rows.length };
    } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
  }
}
