// A save decision names its request, while the corresponding sign-in used to be found by parsing every completed
// sign-in in the session. Maintain that association as sign-ins change; older ones are indexed in bounded steps.
import type { DatabaseSync } from "node:sqlite";

const add = `INSERT INTO signin_save_lookup (ask, session, save)
  SELECT NEW.id, NEW.session, json_extract(NEW.body, '$.save')
  WHERE json_type(NEW.body, '$.save') = 'text' AND NOT EXISTS (SELECT 1 FROM signin_save_lookup WHERE ask = NEW.id);`;
const changed = `DELETE FROM signin_save_lookup WHERE ask = NEW.id AND
  (session IS NOT NEW.session OR save IS NOT json_extract(NEW.body, '$.save')); ${add}`;

const SCHEMA = `
CREATE TABLE IF NOT EXISTS signin_save_lookup (ask TEXT PRIMARY KEY, session TEXT NOT NULL, save TEXT NOT NULL) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS signin_save_by_request ON signin_save_lookup (session, save, ask);
CREATE TABLE IF NOT EXISTS signin_save_progress (session TEXT PRIMARY KEY, status TEXT, row INTEGER, done INTEGER NOT NULL) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS signin_save_pending (session TEXT NOT NULL, save TEXT NOT NULL, status TEXT NOT NULL,
  PRIMARY KEY (session, save)) WITHOUT ROWID;
CREATE TRIGGER IF NOT EXISTS signin_save_add AFTER INSERT ON signin_asks BEGIN ${changed} END;
CREATE TRIGGER IF NOT EXISTS signin_save_change AFTER UPDATE OF id, session, body ON signin_asks BEGIN
  DELETE FROM signin_save_lookup WHERE ask = OLD.id AND OLD.id IS NOT NEW.id;
  ${changed}
END;
CREATE TRIGGER IF NOT EXISTS signin_save_drop AFTER DELETE ON signin_asks BEGIN
  DELETE FROM signin_save_lookup WHERE ask = OLD.id;
END;`;

/// No older sign-ins are read when the lookup and its triggers are installed.
export function installSigninSaveIndex(db: DatabaseSync): void { db.exec(SCHEMA); }

export const SIGNIN_SAVE = `SELECT a.body FROM signin_save_lookup l INDEXED BY signin_save_by_request
  JOIN signin_asks a ON a.id = l.ask WHERE l.session = ? AND l.save = ? ORDER BY a.status, a.rowid LIMIT 1`;

export function signinForSave(db: DatabaseSync, session: string, save: string): string | null {
  return (db.prepare(SIGNIN_SAVE).get(session, save) as { body: string } | undefined)?.body ?? null;
}

export type PendingSigninSave = { session: string; save: string; status: string };
export function pendingSigninSave(db: DatabaseSync, session?: string): PendingSigninSave | null {
  return (session === undefined
    ? db.prepare("SELECT session, save, status FROM signin_save_pending ORDER BY session, save LIMIT 1").get()
    : db.prepare("SELECT session, save, status FROM signin_save_pending WHERE session = ? ORDER BY save LIMIT 1").get(session)) as PendingSigninSave | undefined ?? null;
}

/// Round-robin the waiting sessions without walking the other sessions' requests.
export function nextPendingSigninSave(db: DatabaseSync, after: string | null): PendingSigninSave | null {
  const next = after === null ? undefined : db.prepare("SELECT session, save, status FROM signin_save_pending WHERE session > ? ORDER BY session, save LIMIT 1").get(after);
  return (next as PendingSigninSave | undefined) ?? pendingSigninSave(db);
}

export function forgetSigninSave(db: DatabaseSync, session: string, save: string, status?: string): void {
  if (status === undefined) db.prepare("DELETE FROM signin_save_pending WHERE session = ? AND save = ?").run(session, save);
  else db.prepare("DELETE FROM signin_save_pending WHERE session = ? AND save = ? AND status = ?").run(session, save, status);
}

export function queueSigninSave(db: DatabaseSync, session: string, save: string, status: string): void {
  db.prepare(`INSERT INTO signin_save_pending (session, save, status) VALUES (?, ?, ?)
    ON CONFLICT (session, save) DO UPDATE SET status = excluded.status WHERE status IS NOT excluded.status`).run(session, save, status);
}

export function signinSaveComplete(db: DatabaseSync, session: string): boolean {
  return (db.prepare("SELECT done FROM signin_save_progress WHERE session = ?").get(session) as { done: number } | undefined)?.done === 1;
}

/// Visits no more than `limit` old sign-ins for this session; writes behind the cursor are covered by the triggers.
export function stepSigninSaveIndex(db: DatabaseSync, session: string, limit = 64): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("sign-in index batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    db.prepare("INSERT INTO signin_save_progress (session, status, row, done) SELECT ?, NULL, NULL, 0 WHERE NOT EXISTS (SELECT 1 FROM signin_save_progress WHERE session = ?)").run(session, session);
    const get = db.prepare("SELECT status, row, done FROM signin_save_progress WHERE session = ?");
    get.setReadBigInts(true);
    const state = get.get(session) as { status: string | null; row: bigint | null; done: bigint };
    if (state.done === 1n) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const select = (sql: string, ...args: (string | number | bigint | null)[]) => {
      const query = db.prepare(sql); query.setReadBigInts(true);
      return query.all(...args) as { status: string; row: bigint }[];
    };
    let rows: { status: string; row: bigint }[];
    if (state.status === null) {
      rows = select("SELECT status, rowid AS row FROM signin_asks INDEXED BY signin_asks_by_session WHERE session = ?1 ORDER BY status, rowid LIMIT ?2", session, limit);
    } else {
      // SQLite cannot seek the rowid part of a tuple comparison here: it would walk every earlier row with this
      // status. Seek the remaining rowids of that status first, then seek the next statuses if the batch has room.
      rows = select("SELECT status, rowid AS row FROM signin_asks INDEXED BY signin_asks_by_session WHERE session = ?1 AND status = ?3 AND rowid > ?4 ORDER BY status, rowid LIMIT ?2", session, limit, state.status, state.row);
      if (rows.length < limit) rows.push(...select("SELECT status, rowid AS row FROM signin_asks INDEXED BY signin_asks_by_session WHERE session = ?1 AND status > ?3 ORDER BY status, rowid LIMIT ?2", session, limit - rows.length, state.status));
    }
    const remember = db.prepare(`INSERT INTO signin_save_lookup (ask, session, save)
      SELECT id, session, json_extract(body, '$.save') FROM signin_asks WHERE rowid = ?1 AND json_type(body, '$.save') = 'text'
      AND NOT EXISTS (SELECT 1 FROM signin_save_lookup l WHERE l.ask = signin_asks.id)`);
    for (const row of rows) remember.run(row.row);
    const last = rows.at(-1), done = rows.length < limit;
    db.prepare("UPDATE signin_save_progress SET status = ?, row = ?, done = ? WHERE session = ?")
      .run(last?.status ?? state.status, last?.row ?? state.row, done ? 1 : 0, session);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}
