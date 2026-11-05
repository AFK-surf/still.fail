// Sessions whose last completed turn may need to be taken up after a restart. Old stores are prepared in bounded
// batches; writes from either station keep both sides of the cursor current.
import type { DatabaseSync } from "node:sqlite";

const wanted = (key: string) => `EXISTS (SELECT 1 FROM sessions s WHERE s.key = ${key} AND s.archived_at IS NULL AND s.running = 0)
  AND EXISTS (SELECT 1 FROM turns t WHERE t.rowid = (SELECT rowid FROM turns INDEXED BY turns_by_session
    WHERE session_key = ${key} ORDER BY started_at DESC, rowid DESC LIMIT 1)
    AND t.ended_at IS NOT NULL AND (t.declared = 'waiting' OR (t.outcome = 'failed' AND substr(t.detail, 1, 11) = 'rate_limit:')))`;
const remove = (key: string, guard = "1") => `DELETE FROM session_recover_waits WHERE session = ${key} AND (${guard}) AND NOT (${wanted(key)});`;
const add = (key: string, guard = "1") => `INSERT INTO session_recover_waits (session) SELECT ${key} WHERE (${guard}) AND ${wanted(key)}
  AND NOT EXISTS (SELECT 1 FROM session_recover_waits WHERE session = ${key});`;
const sync = (key: string, guard = "1") => `${remove(key, guard)} ${add(key, guard)}`;
const reconcile = (stage: string) => `DELETE FROM session_recover_waits WHERE session IN (SELECT session FROM ${stage})
    AND NOT (${wanted("session_recover_waits.session")});
  INSERT INTO session_recover_waits (session) SELECT r.session FROM ${stage} r WHERE ${wanted("r.session")}
    AND NOT EXISTS (SELECT 1 FROM session_recover_waits w WHERE w.session = r.session);
  DELETE FROM ${stage} WHERE session IS NOT NULL;`;

export const RECOVER_WAITS = `SELECT s.*, t.outcome AS recovery_outcome, t.detail AS recovery_detail
  FROM session_recover_waits w CROSS JOIN sessions s ON s.key = w.session
  CROSS JOIN turns t ON t.rowid = (SELECT rowid FROM turns INDEXED BY turns_by_session
    WHERE session_key = s.key ORDER BY started_at DESC, rowid DESC LIMIT 1)
  WHERE s.archived_at IS NULL AND s.running = 0 AND t.ended_at IS NOT NULL
    AND (t.declared = 'waiting' OR (t.outcome = 'failed' AND substr(t.detail, 1, 11) = 'rate_limit:'))
  ORDER BY s.last_active_at DESC, s.rowid DESC`;
export const RECOVER_BACKFILL_FIRST = "SELECT key FROM sessions ORDER BY key LIMIT ?";
export const RECOVER_BACKFILL_NEXT = "SELECT key FROM sessions WHERE key > ? ORDER BY key LIMIT ?";

export function installRecoverWaits(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'session_recover_wait_meta'").get() !== undefined;
  if (installed()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE session_recover_waits (session TEXT PRIMARY KEY) WITHOUT ROWID;
      CREATE TABLE session_recover_turn_stage (session TEXT PRIMARY KEY) WITHOUT ROWID;
      CREATE TABLE session_recover_session_stage (session TEXT PRIMARY KEY) WITHOUT ROWID;
      CREATE TABLE session_recover_wait_meta (id INTEGER PRIMARY KEY CHECK (id = 1), cursor TEXT, complete INTEGER NOT NULL);
      INSERT INTO session_recover_wait_meta VALUES (1, NULL, NOT EXISTS (SELECT 1 FROM sessions LIMIT 1));

      CREATE TRIGGER session_recover_before_turn_add BEFORE INSERT ON turns BEGIN
        DELETE FROM session_recover_turn_stage WHERE session IS NOT NULL;
        INSERT INTO session_recover_turn_stage SELECT session_key FROM turns WHERE id = NEW.id;
      END;
      CREATE TRIGGER session_recover_turn_add AFTER INSERT ON turns BEGIN
        ${sync("NEW.session_key")}
        ${reconcile("session_recover_turn_stage")}
      END;
      CREATE TRIGGER session_recover_before_turn_move BEFORE UPDATE OF id ON turns WHEN OLD.id IS NOT NEW.id BEGIN
        DELETE FROM session_recover_turn_stage WHERE session IS NOT NULL;
        INSERT INTO session_recover_turn_stage SELECT session_key FROM turns WHERE id = NEW.id AND rowid != OLD.rowid;
      END;
      CREATE TRIGGER session_recover_turn_change AFTER UPDATE OF id, session_key, started_at, ended_at, outcome, detail, declared ON turns
        WHEN OLD.id IS NOT NEW.id OR OLD.session_key IS NOT NEW.session_key OR OLD.started_at IS NOT NEW.started_at
          OR OLD.ended_at IS NOT NEW.ended_at OR OLD.outcome IS NOT NEW.outcome OR OLD.detail IS NOT NEW.detail OR OLD.declared IS NOT NEW.declared BEGIN
        ${sync("OLD.session_key")}
        ${sync("NEW.session_key", "OLD.session_key IS NOT NEW.session_key")}
        ${reconcile("session_recover_turn_stage")}
      END;
      CREATE TRIGGER session_recover_turn_drop AFTER DELETE ON turns BEGIN ${sync("OLD.session_key")} END;

      CREATE TRIGGER session_recover_before_session_add BEFORE INSERT ON sessions BEGIN
        DELETE FROM session_recover_session_stage WHERE session IS NOT NULL;
        INSERT INTO session_recover_session_stage SELECT key FROM sessions WHERE key = NEW.key OR token = NEW.token;
      END;
      CREATE TRIGGER session_recover_session_add AFTER INSERT ON sessions BEGIN
        ${sync("NEW.key")}
        ${reconcile("session_recover_session_stage")}
      END;
      CREATE TRIGGER session_recover_before_session_move BEFORE UPDATE OF key, token ON sessions
        WHEN OLD.key IS NOT NEW.key OR OLD.token IS NOT NEW.token BEGIN
        DELETE FROM session_recover_session_stage WHERE session IS NOT NULL;
        INSERT INTO session_recover_session_stage SELECT key FROM sessions
          WHERE (key = NEW.key OR token = NEW.token) AND key != OLD.key;
      END;
      CREATE TRIGGER session_recover_session_change AFTER UPDATE OF key, token, archived_at, running ON sessions
        WHEN OLD.key IS NOT NEW.key OR OLD.token IS NOT NEW.token OR OLD.archived_at IS NOT NEW.archived_at OR OLD.running IS NOT NEW.running BEGIN
        ${sync("OLD.key")}
        ${sync("NEW.key", "OLD.key IS NOT NEW.key")}
        ${reconcile("session_recover_session_stage")}
      END;
      CREATE TRIGGER session_recover_session_drop AFTER DELETE ON sessions BEGIN
        DELETE FROM session_recover_waits WHERE session = OLD.key;
      END;
    `);
    db.exec("COMMIT");
  } catch (error) {
    try { db.exec("ROLLBACK"); } catch {}
    throw error;
  }
}

export function recoverWaitsReady(db: DatabaseSync): boolean {
  return (db.prepare("SELECT complete FROM session_recover_wait_meta WHERE id = 1").get() as { complete: number }).complete === 1;
}

/// Fill at most `limit` existing sessions. The cursor and its updates commit together; triggers cover intervening writes.
export function recoverWaitsStep(db: DatabaseSync, limit = 64): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recovery wait batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const state = db.prepare("SELECT cursor, complete FROM session_recover_wait_meta WHERE id = 1").get() as { cursor: string | null; complete: number };
    if (state.complete === 1) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const rows = (state.cursor === null ? db.prepare(RECOVER_BACKFILL_FIRST).all(limit)
      : db.prepare(RECOVER_BACKFILL_NEXT).all(state.cursor, limit)) as { key: string }[];
    const drop = db.prepare(remove("?1"));
    const put = db.prepare(add("?1"));
    for (const { key } of rows) { drop.run(key); put.run(key); }
    const done = rows.length < limit;
    db.prepare("UPDATE session_recover_wait_meta SET cursor = ?, complete = ? WHERE id = 1")
      .run(rows.at(-1)?.key ?? state.cursor, done ? 1 : 0);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) {
    try { db.exec("ROLLBACK"); } catch {}
    throw error;
  }
}
