// The tasks another station's chats ran here. The original rows remain the source of truth; these lookup tables and
// counts are kept by triggers, including when an older station writes the database. Old rows are filled in small batches.
import type { DatabaseSync } from "node:sqlite";

// The workspace is the second colon-delimited part, just as session.split(":")[1] ?? "" read it before.
const WS = (name: string) => `(CASE WHEN instr(${name}.session, ':') = 0 THEN '' ELSE
  CASE WHEN instr(substr(${name}.session, instr(${name}.session, ':') + 1), ':') = 0
    THEN substr(${name}.session, instr(${name}.session, ':') + 1)
    ELSE substr(substr(${name}.session, instr(${name}.session, ':') + 1), 1,
      instr(substr(${name}.session, instr(${name}.session, ':') + 1), ':') - 1) END END)`;

const SCHEMA = `
CREATE TABLE remote_run_progress (id INTEGER PRIMARY KEY CHECK (id = 1), after_seq INTEGER, end_seq INTEGER, done INTEGER NOT NULL);
INSERT INTO remote_run_progress SELECT 1, NULL, (SELECT MAX(rowid) FROM remote_runs), NOT EXISTS (SELECT 1 FROM remote_runs LIMIT 1);
CREATE TABLE remote_run_lookup (ws TEXT NOT NULL, at INTEGER NOT NULL, seq INTEGER NOT NULL, job TEXT NOT NULL, session TEXT NOT NULL,
  PRIMARY KEY (ws, at, seq)) WITHOUT ROWID;
CREATE TABLE remote_run_by_time (at INTEGER NOT NULL, seq INTEGER NOT NULL, job TEXT NOT NULL, session TEXT NOT NULL,
  PRIMARY KEY (at, seq)) WITHOUT ROWID;
CREATE TABLE remote_run_by_job (job TEXT PRIMARY KEY, ws TEXT NOT NULL, at INTEGER NOT NULL, seq INTEGER NOT NULL) WITHOUT ROWID;
CREATE TABLE remote_run_counts (ws TEXT PRIMARY KEY, n INTEGER NOT NULL) WITHOUT ROWID;
CREATE TABLE remote_run_total (id INTEGER PRIMARY KEY CHECK (id = 1), n INTEGER NOT NULL);
INSERT INTO remote_run_total VALUES (1, 0);
CREATE TRIGGER remote_run_lookup_add AFTER INSERT ON remote_run_lookup BEGIN
  INSERT INTO remote_run_by_time VALUES (NEW.at, NEW.seq, NEW.job, NEW.session);
  INSERT INTO remote_run_by_job VALUES (NEW.job, NEW.ws, NEW.at, NEW.seq);
  INSERT INTO remote_run_counts SELECT NEW.ws, 1 WHERE NEW.at >= 0
    ON CONFLICT (ws) DO UPDATE SET n = n + 1;
  UPDATE remote_run_total SET n = n + 1 WHERE id = 1 AND NEW.at >= 0;
END;
CREATE TRIGGER remote_run_lookup_drop AFTER DELETE ON remote_run_lookup BEGIN
  DELETE FROM remote_run_by_time WHERE at = OLD.at AND seq = OLD.seq;
  DELETE FROM remote_run_by_job WHERE job = OLD.job AND ws = OLD.ws AND at = OLD.at AND seq = OLD.seq;
  UPDATE remote_run_counts SET n = n - 1 WHERE ws = OLD.ws AND OLD.at >= 0;
  DELETE FROM remote_run_counts WHERE ws = OLD.ws AND n = 0;
  UPDATE remote_run_total SET n = n - 1 WHERE id = 1 AND OLD.at >= 0;
END;
CREATE TRIGGER remote_run_add AFTER INSERT ON remote_runs BEGIN
  -- SQLite's INSERT OR REPLACE can delete a conflicting old row without firing its delete trigger. Remove its indexed
  -- copy by job before inserting the replacement; INSERT OR IGNORE never reaches this trigger on a conflict.
  DELETE FROM remote_run_lookup WHERE (ws, at, seq) = (SELECT ws, at, seq FROM remote_run_by_job WHERE job = NEW.job);
  INSERT OR IGNORE INTO remote_run_lookup VALUES (${WS("NEW")}, NEW.at, NEW.rowid, NEW.job, NEW.session);
END;
CREATE TRIGGER remote_run_drop AFTER DELETE ON remote_runs BEGIN
  DELETE FROM remote_run_lookup WHERE ws = ${WS("OLD")} AND at = OLD.at AND seq = OLD.rowid;
END;
CREATE TRIGGER remote_run_change AFTER UPDATE ON remote_runs BEGIN
  DELETE FROM remote_run_lookup WHERE ws = ${WS("OLD")} AND at = OLD.at AND seq = OLD.rowid;
  DELETE FROM remote_run_lookup WHERE (ws, at, seq) = (SELECT ws, at, seq FROM remote_run_by_job WHERE job = NEW.job);
  INSERT OR IGNORE INTO remote_run_lookup VALUES (${WS("NEW")}, NEW.at, NEW.rowid, NEW.job, NEW.session);
END;
`;

/// Install empty structures and write triggers without scanning old task history on the station's thread.
export function installRemoteRuns(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'remote_run_progress'").get() !== undefined;
  if (installed()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(SCHEMA);
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}

export const DELETE_EXPIRED_REMOTE_RUNS = `DELETE FROM remote_runs WHERE job IN
  (SELECT job FROM remote_run_by_time WHERE at < ? ORDER BY at, seq)`;

export const REMOTE_RUNS_OF = "SELECT at, session FROM remote_run_lookup WHERE ws = ?1 AND at >= ?2 ORDER BY at, seq";
export const REMOTE_RUNS_ALL = "SELECT at, session FROM remote_run_by_time WHERE at >= ? ORDER BY at, seq";
/// Fill no more than `limit` old rows; writes, deletions, and the cursor commit together.
export function backfillRemoteRuns(db: DatabaseSync, limit = 32): { done: boolean; processed: number } {
  db.exec("BEGIN IMMEDIATE");
  try {
    const state = db.prepare("SELECT after_seq, end_seq, done FROM remote_run_progress WHERE id = 1").get() as
      { after_seq: number | null; end_seq: number | null; done: number };
    if (state.done) {
      db.exec("COMMIT");
      return { done: true, processed: 0 };
    }
    const rows = (state.after_seq === null
      ? db.prepare("SELECT rowid AS seq, at FROM remote_runs WHERE rowid <= ? ORDER BY rowid LIMIT ?").all(state.end_seq, limit)
      : db.prepare("SELECT rowid AS seq, at FROM remote_runs WHERE rowid > ? AND rowid <= ? ORDER BY rowid LIMIT ?").all(state.after_seq, state.end_seq, limit)) as
      { seq: number; at: number }[];
    const add = db.prepare(`INSERT OR IGNORE INTO remote_run_lookup
      SELECT ${WS("r")}, r.at, r.rowid, r.job, r.session FROM remote_runs r WHERE r.rowid = ?`);
    for (const row of rows) add.run(row.seq);
    const done = rows.length < limit;
    db.prepare("UPDATE remote_run_progress SET after_seq = ?, done = ? WHERE id = 1")
      .run(rows.at(-1)?.seq ?? state.after_seq, done ? 1 : 0);
    db.exec("COMMIT");
    return { done, processed: rows.length };
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}
