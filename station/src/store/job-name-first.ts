import type { DatabaseSync } from "node:sqlite";

// One requested own chat per session with an up job. Its first raw membership is sufficient for a job's name only
// when that membership decodes to the job's active session; the reader checks that condition in its own snapshot.
const VERSION = 1;
export const JOB_NAME_FIRST_PENDING = "job name first member pending: ";
export const JOB_NAME_FIRST_LARGE = "SELECT 1 FROM thread_sessions WHERE thread=? LIMIT 1 OFFSET 64";
export const JOB_NAME_FIRST_ROW = `SELECT m.* FROM thread_sessions m WHERE m.rowid=(SELECT best FROM job_name_first
  WHERE owner=?1 AND thread=?2 AND ready=1 AND restart=0)`;

export function installJobNameFirst(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='job_name_first_meta'").get() !== undefined;
  if (installed()) { checkJobNameFirst(db); return; }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE job_name_first_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL) WITHOUT ROWID;
      INSERT INTO job_name_first_meta VALUES(1,${VERSION});
      CREATE TABLE job_name_first(owner TEXT PRIMARY KEY,thread INTEGER NOT NULL UNIQUE,best INTEGER,after_session TEXT,
        through_session TEXT,restart INTEGER NOT NULL DEFAULT 0,ready INTEGER NOT NULL DEFAULT 0) WITHOUT ROWID;
      CREATE INDEX job_name_first_best ON job_name_first(best);

      -- REPLACE can remove either of these old memberships without firing DELETE triggers in an older connection.
      CREATE TRIGGER job_name_first_before_add BEFORE INSERT ON thread_sessions BEGIN
        UPDATE job_name_first SET ready=0,restart=1 WHERE restart=0 AND best IN (
          SELECT rowid FROM thread_sessions WHERE rowid=NEW.rowid
          UNION SELECT rowid FROM thread_sessions WHERE thread=NEW.thread AND session=NEW.session);
      END;
      CREATE TRIGGER job_name_first_after_add AFTER INSERT ON thread_sessions BEGIN
        UPDATE job_name_first SET best=NEW.rowid WHERE thread=NEW.thread AND restart=0 AND best IS NOT NEW.rowid
          AND (best IS NULL OR (SELECT rowid FROM thread_sessions WHERE rowid IN (best,NEW.rowid)
            ORDER BY joined_at,rowid LIMIT 1)=NEW.rowid);
      END;
      CREATE TRIGGER job_name_first_before_change BEFORE UPDATE ON thread_sessions
      WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session OR OLD.joined_at IS NOT NEW.joined_at OR OLD.rowid IS NOT NEW.rowid
      BEGIN
        UPDATE job_name_first SET ready=0,restart=1 WHERE restart=0 AND (best=OLD.rowid OR best IN (
          SELECT rowid FROM thread_sessions WHERE rowid=NEW.rowid
          UNION SELECT rowid FROM thread_sessions WHERE thread=NEW.thread AND session=NEW.session));
      END;
      CREATE TRIGGER job_name_first_after_change AFTER UPDATE ON thread_sessions
      WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session OR OLD.joined_at IS NOT NEW.joined_at OR OLD.rowid IS NOT NEW.rowid
      BEGIN
        UPDATE job_name_first SET best=NEW.rowid WHERE thread=NEW.thread AND restart=0 AND best IS NOT NEW.rowid
          AND (best IS NULL OR (SELECT rowid FROM thread_sessions WHERE rowid IN (best,NEW.rowid)
            ORDER BY joined_at,rowid LIMIT 1)=NEW.rowid);
      END;
      CREATE TRIGGER job_name_first_drop BEFORE DELETE ON thread_sessions BEGIN
        UPDATE job_name_first SET ready=0,restart=1 WHERE best=OLD.rowid AND restart=0;
      END;
      -- A session can own at most one tracked chat, so finishing its final up job removes at most one row.
      CREATE TRIGGER job_name_first_job_drop AFTER DELETE ON session_up_job_rows
      WHEN NOT EXISTS (SELECT 1 FROM session_up_job_rows WHERE session=OLD.session LIMIT 1)
      BEGIN DELETE FROM job_name_first WHERE owner=OLD.session; END;
    `);
    else checkJobNameFirst(db);
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function checkJobNameFirst(db: DatabaseSync): void {
  const row = db.prepare("SELECT version FROM job_name_first_meta WHERE id=1").get() as { version: number } | undefined;
  if (!row || row.version !== VERSION) throw new Error(`job name first index version ${row?.version ?? "missing"} is incompatible with ${VERSION}`);
}

// Keep the cursor and end as SQLite values, not decoded JS strings: old keys can contain NUL, invalid UTF-8 or blobs.
export const JOB_NAME_FIRST_SCAN = (first: boolean) => `SELECT rowid FROM thread_sessions WHERE thread=?1
  AND session <= (SELECT through_session FROM job_name_first WHERE owner=?2)
  ${first ? "" : "AND session > (SELECT after_session FROM job_name_first WHERE owner=?2)"}
  ORDER BY session LIMIT ?3`;

/// Prepare one requested chat in bounded batches. Writers also consider additions behind the cursor. If the current
/// minimum disappears the cursor restarts; a fixed end lets an ongoing stream of later additions finish preparation.
export function jobNameFirstStep(db: DatabaseSync, owner: string, thread: number, limit = 64): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(thread) || !Number.isSafeInteger(limit) || limit < 1 || limit > 128) throw new RangeError("invalid job name first batch");
  db.exec("BEGIN IMMEDIATE");
  try {
    checkJobNameFirst(db);
    db.prepare(`INSERT OR IGNORE INTO job_name_first(owner,thread,through_session)
      SELECT ?1,?2,(SELECT session FROM thread_sessions WHERE thread=?2 ORDER BY session DESC LIMIT 1)
      WHERE EXISTS (SELECT 1 FROM session_up_job_rows WHERE session=?1 LIMIT 1)`).run(owner, thread);
    const current = db.prepare("SELECT thread,ready FROM job_name_first WHERE owner=?").get(owner) as { thread: number; ready: number } | undefined;
    if (!current || current.thread !== thread || current.ready === 1) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    db.prepare(`UPDATE job_name_first SET restart=0,ready=0,best=NULL,after_session=NULL,
      through_session=(SELECT session FROM thread_sessions WHERE thread=?2 ORDER BY session DESC LIMIT 1)
      WHERE owner=?1 AND thread=?2 AND restart=1`).run(owner, thread);
    const first = (db.prepare("SELECT after_session IS NULL AS first FROM job_name_first WHERE owner=?").get(owner) as { first: number }).first === 1;
    const q = db.prepare(JOB_NAME_FIRST_SCAN(first)); q.setReadBigInts(true);
    const batch = q.all(thread, owner, limit) as { rowid: bigint }[];
    if (batch.length) {
      const candidate = db.prepare(`SELECT rowid FROM thread_sessions WHERE rowid IN (${batch.map(() => "?").join(",")})
        ORDER BY joined_at,rowid LIMIT 1`); candidate.setReadBigInts(true);
      const best = (candidate.get(...batch.map((row) => row.rowid)) as { rowid: bigint }).rowid;
      db.prepare(`UPDATE job_name_first SET best=?2 WHERE owner=?1 AND best IS NOT ?2
        AND (best IS NULL OR (SELECT rowid FROM thread_sessions WHERE rowid IN (best,?2)
          ORDER BY joined_at,rowid LIMIT 1)=?2)`).run(owner, best);
      db.prepare(`UPDATE job_name_first SET after_session=(SELECT session FROM thread_sessions WHERE rowid=?2)
        WHERE owner=?1`).run(owner, batch.at(-1)!.rowid);
    }
    const done = batch.length < limit;
    if (done) db.prepare("UPDATE job_name_first SET ready=1 WHERE owner=?").run(owner);
    db.exec("COMMIT");
    return { done, visited: batch.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
