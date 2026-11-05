import type { DatabaseSync } from "node:sqlite";
import { ccSessionReady, CcIndexPreparation } from "./cc-thread-index.ts";

const VERSION = 1;

// cc_session_rows already orders the non-ember members of a requested session. Keep only its ember members here,
// so choosing a session's latest chat can take one candidate from each order. This table starts empty even on an old
// station: its old members are prepared in batches, not by building an index over the old projection at startup.
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
  CREATE TABLE session_chat_ember (
    session TEXT NOT NULL, has_last INTEGER NOT NULL, last_at NOT NULL, created_at INTEGER NOT NULL, thread INTEGER NOT NULL,
    PRIMARY KEY(session, has_last DESC, last_at DESC, created_at DESC, thread DESC)
  ) WITHOUT ROWID;
  CREATE TRIGGER session_chat_cc_add AFTER INSERT ON cc_session_rows
    WHEN NEW.surface='ember' AND EXISTS (SELECT 1 FROM session_chat_scopes WHERE session=NEW.session) BEGIN
      INSERT OR IGNORE INTO session_chat_ember(session,has_last,last_at,created_at,thread)
        VALUES(NEW.session,NEW.last_at IS NOT NULL,COALESCE(NEW.last_at,0),NEW.created_at,NEW.thread);
  END;
  CREATE TRIGGER session_chat_cc_change AFTER UPDATE ON cc_session_rows
    WHEN OLD.session IS NOT NEW.session OR OLD.thread IS NOT NEW.thread OR OLD.surface IS NOT NEW.surface
      OR OLD.last_at IS NOT NEW.last_at OR OLD.created_at IS NOT NEW.created_at BEGIN
      DELETE FROM session_chat_ember WHERE OLD.surface='ember' AND session=OLD.session
        AND has_last=(OLD.last_at IS NOT NULL) AND last_at IS COALESCE(OLD.last_at,0)
        AND created_at IS OLD.created_at AND thread=OLD.thread;
      INSERT OR IGNORE INTO session_chat_ember(session,has_last,last_at,created_at,thread)
        SELECT NEW.session,NEW.last_at IS NOT NULL,COALESCE(NEW.last_at,0),NEW.created_at,NEW.thread
        WHERE NEW.surface='ember' AND EXISTS (SELECT 1 FROM session_chat_scopes WHERE session=NEW.session);
  END;
  CREATE TRIGGER session_chat_cc_drop AFTER DELETE ON cc_session_rows BEGIN
    DELETE FROM session_chat_ember WHERE OLD.surface='ember' AND session=OLD.session
      AND has_last=(OLD.last_at IS NOT NULL) AND last_at IS COALESCE(OLD.last_at,0)
      AND created_at IS OLD.created_at AND thread=OLD.thread;
  END;`);
    else checkSessionChatIndex(db);
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function checkSessionChatIndex(db: DatabaseSync): void {
  const row = db.prepare("SELECT version FROM session_chat_meta WHERE id=1").get() as { version: number } | undefined;
  if (row?.version !== VERSION) throw new Error(`session chat index version ${row?.version ?? "missing"} is incompatible with ${VERSION}`);
}

// The flag lets the single ordered primary key represent NULL timestamps without a second lookup index. NULL sorts
// below every non-NULL SQLite value; among NULLs the creation time and thread id still break ties.
export const SESSION_CHAT_EMBER = `SELECT thread,CASE WHEN has_last=0 THEN NULL ELSE last_at END AS last_at,created_at
  FROM session_chat_ember WHERE session=?1
  ORDER BY has_last DESC,session_chat_ember.last_at DESC,created_at DESC,thread DESC LIMIT 1`;
export const SESSION_CHAT_OTHER = `SELECT thread,last_at,created_at FROM cc_session_rows INDEXED BY cc_session_order
  WHERE session=?1 AND surface != 'ember' ORDER BY last_at DESC,created_at DESC,thread DESC LIMIT 1`;
export const SESSION_CHAT_INDEXED = `WITH own AS MATERIALIZED (${SESSION_CHAT_EMBER}), other AS MATERIALIZED (${SESSION_CHAT_OTHER})
  SELECT t.* FROM (SELECT * FROM own UNION ALL SELECT * FROM other) c JOIN threads t ON t.id=c.thread
  ORDER BY c.last_at DESC,c.created_at DESC,c.thread DESC LIMIT 1`;

export function sessionChatReady(db: DatabaseSync, session: string): boolean {
  checkSessionChatIndex(db);
  const row = db.prepare("SELECT complete FROM session_chat_scopes WHERE session=?").get(session) as { complete: number } | undefined;
  return row?.complete === 1 && ccSessionReady(db, session);
}

/// Read both readiness and the chosen thread in one SQLite snapshot.
export function indexedSessionChat(db: DatabaseSync, session: string): Record<string, unknown> | null {
  db.exec("SAVEPOINT session_chat_read");
  try {
    if (!sessionChatReady(db, session)) throw new Error("session chat is still being prepared");
    return db.prepare(SESSION_CHAT_INDEXED).get(session) ?? null;
  } finally { db.exec("RELEASE session_chat_read"); }
}

/// Prepare the existing order first, then add its ember rows in bounded key order. Triggers cover changes during the
/// scan, including rows inserted behind its cursor. Every slice and its cursor are committed together.
export class SessionChatPreparation {
  readonly #cc = new CcIndexPreparation();

  cancel(session: string): void { this.#cc.cancel(session); }

  step(db: DatabaseSync, session: string, limit = 64): { done: boolean; visited: number } {
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 128) throw new RangeError("session chat batch must be between 1 and 128");
    checkSessionChatIndex(db);
    if (!ccSessionReady(db, session)) {
      const progress = this.#cc.step(db, session, limit);
      return { done: false, visited: progress.visited };
    }
    db.exec("BEGIN IMMEDIATE");
    try {
      // Another writer may have changed the projection before this transaction took the write lock.
      checkSessionChatIndex(db);
      if (!ccSessionReady(db, session)) { db.exec("COMMIT"); return { done: false, visited: 0 }; }
      db.prepare(`INSERT INTO session_chat_scopes(session,scan_end)
        SELECT ?1,(SELECT thread FROM cc_session_rows WHERE session=?1 ORDER BY thread DESC LIMIT 1)
        WHERE NOT EXISTS (SELECT 1 FROM session_chat_scopes WHERE session=?1)`).run(session);
      const scopeQuery = db.prepare("SELECT scan_after,scan_end,complete FROM session_chat_scopes WHERE session=?");
      scopeQuery.setReadBigInts(true);
      const scope = scopeQuery.get(session) as { scan_after: bigint | null; scan_end: bigint | null; complete: bigint };
      if (scope.complete === 1n) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
      const scan = db.prepare(scope.scan_after === null
        ? "SELECT thread,surface,last_at,created_at FROM cc_session_rows WHERE session=?1 AND thread<=?2 ORDER BY thread LIMIT ?3"
        : "SELECT thread,surface,last_at,created_at FROM cc_session_rows WHERE session=?1 AND thread>?2 AND thread<=?3 ORDER BY thread LIMIT ?4");
      scan.setReadBigInts(true);
      const rows = (scope.scan_after === null ? scan.all(session, scope.scan_end, limit)
        : scan.all(session, scope.scan_after, scope.scan_end, limit)) as { thread: bigint; surface: string | null; last_at: number | bigint | string | null; created_at: number | bigint | string | null }[];
      const put = db.prepare("INSERT OR IGNORE INTO session_chat_ember(session,has_last,last_at,created_at,thread) VALUES(?,?,?,?,?)");
      for (const row of rows) if (row.surface === "ember") put.run(session, row.last_at === null ? 0 : 1, row.last_at ?? 0, row.created_at, row.thread);
      const done = rows.length < limit;
      db.prepare("UPDATE session_chat_scopes SET scan_after=?,complete=? WHERE session=?")
        .run(rows.at(-1)?.thread ?? scope.scan_after, done ? 1 : 0, session);
      db.exec("COMMIT");
      return { done, visited: rows.length };
    } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
  }
}
