// A session's running jobs and services waiting to restart. Old jobs are prepared a session at a time, in batches;
// the writers follow changes made by either station while the previous process hands over.
import type { DatabaseSync } from "node:sqlite";

const VERSION = 1;
export const SESSION_UP_JOB = "SELECT 1 FROM session_up_job_rows WHERE session = ? LIMIT 1";
export const SESSION_UP_JOBS = `SELECT j.id FROM session_up_job_rows i
  CROSS JOIN jobs j ON j.rowid = i.job_rowid WHERE i.session = ? ORDER BY j.started_at DESC`;
export const SESSION_UP_JOBS_END = "SELECT rowid FROM jobs INDEXED BY jobs_by_session WHERE session_key = ? ORDER BY rowid DESC LIMIT 1";
export const SESSION_UP_JOBS_FIRST = `SELECT CAST(rowid AS TEXT) AS position FROM jobs INDEXED BY jobs_by_session
  WHERE session_key = ? AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?`;
export const SESSION_UP_JOBS_NEXT = `SELECT CAST(rowid AS TEXT) AS position FROM jobs INDEXED BY jobs_by_session
  WHERE session_key = ? AND rowid > CAST(? AS INTEGER) AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?`;

const up = (name: string) => `(${name}.state = 'running' OR (${name}.state = 'exited' AND ${name}.port IS NOT NULL))`;
const changed = `OLD.rowid IS NOT NEW.rowid OR OLD.id IS NOT NEW.id OR OLD.token IS NOT NEW.token
  OR OLD.session_key IS NOT NEW.session_key OR ${up("OLD")} IS NOT ${up("NEW")}
  OR EXISTS (SELECT 1 FROM session_up_job_replaced)`;
const displaced = (id: string, token: string, rowid: string) => `SELECT j.rowid, j.session_key FROM jobs j WHERE j.id = ${id}
  UNION SELECT j.rowid, j.session_key FROM jobs j WHERE j.token = ${token}
  UNION SELECT j.rowid, j.session_key FROM jobs j WHERE j.rowid = ${rowid}`;
export const SESSION_UP_JOBS_DISPLACED = displaced("?1", "?2", "?3");
const conflict = (id: string, token: string, rowid: string) =>
  `SELECT 1 FROM jobs WHERE id = ${id} OR token = ${token} OR rowid = ${rowid}`;
export const SESSION_UP_JOBS_CONFLICT = conflict("?1", "?2", "?3");
const stage = (old: boolean) => `DELETE FROM session_up_job_replaced;
  INSERT INTO session_up_job_replaced (job_rowid, session) ${displaced("NEW.id", "NEW.token", "NEW.rowid")}
    ${old ? "UNION SELECT OLD.rowid, OLD.session_key" : ""};`;
const see = (rowid: string) => `INSERT INTO session_up_job_rows (session, job_rowid)
  SELECT j.session_key, j.rowid FROM jobs j WHERE j.rowid = ${rowid} AND ${up("j")}
    AND NOT EXISTS (SELECT 1 FROM session_up_job_rows i WHERE i.session = j.session_key AND i.job_rowid = j.rowid);`;
const reconcile = `DELETE FROM session_up_job_rows WHERE (session, job_rowid) IN
    (SELECT session, job_rowid FROM session_up_job_replaced)
    AND NOT EXISTS (SELECT 1 FROM jobs j WHERE j.rowid = session_up_job_rows.job_rowid
      AND j.session_key = session_up_job_rows.session AND ${up("j")});
  INSERT INTO session_up_job_rows (session, job_rowid)
    SELECT j.session_key, j.rowid FROM session_up_job_replaced r CROSS JOIN jobs j ON j.rowid = r.job_rowid
    WHERE ${up("j")} AND NOT EXISTS (SELECT 1 FROM session_up_job_rows i
      WHERE i.session = j.session_key AND i.job_rowid = j.rowid);
  DELETE FROM session_up_job_replaced;`;

export function installSessionUpJobs(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'session_up_job_meta'").get() !== undefined;
  if (installed()) { sessionUpJobsReady(db, ""); return; }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE session_up_job_meta (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL, fresh INTEGER NOT NULL) WITHOUT ROWID;
      INSERT INTO session_up_job_meta SELECT 1, ${VERSION},
        NOT EXISTS (SELECT 1 FROM jobs INDEXED BY jobs_state WHERE state = 'running')
        AND NOT EXISTS (SELECT 1 FROM jobs INDEXED BY jobs_up WHERE state = 'exited' AND port IS NOT NULL);
      CREATE TABLE session_up_job_scopes (session TEXT PRIMARY KEY, last_rowid INTEGER, end_rowid INTEGER, complete INTEGER NOT NULL) WITHOUT ROWID;
      CREATE TABLE session_up_job_rows (session TEXT NOT NULL, job_rowid INTEGER NOT NULL, PRIMARY KEY (session, job_rowid)) WITHOUT ROWID;
      CREATE TABLE session_up_job_replaced (job_rowid INTEGER PRIMARY KEY, session TEXT NOT NULL);
      CREATE TRIGGER session_up_job_before_add BEFORE INSERT ON jobs
        WHEN EXISTS (SELECT 1 FROM session_up_job_replaced)
          OR EXISTS (${conflict("NEW.id", "NEW.token", "NEW.rowid")})
        BEGIN ${stage(false)} END;
      CREATE TRIGGER session_up_job_add AFTER INSERT ON jobs
        WHEN ${up("NEW")} OR EXISTS (SELECT 1 FROM session_up_job_replaced)
        BEGIN ${reconcile} ${see("NEW.rowid")} END;
      CREATE TRIGGER session_up_job_before_change BEFORE UPDATE ON jobs
        WHEN ${changed}
        BEGIN ${stage(true)} END;
      CREATE TRIGGER session_up_job_change AFTER UPDATE ON jobs
        WHEN ${changed}
        BEGIN ${reconcile} ${see("NEW.rowid")} END;
      CREATE TRIGGER session_up_job_drop AFTER DELETE ON jobs WHEN ${up("OLD")} BEGIN
        DELETE FROM session_up_job_rows WHERE session = OLD.session_key AND job_rowid = OLD.rowid;
      END;
    `);
    else sessionUpJobsReady(db, "");
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function sessionUpJobsReady(db: DatabaseSync, session: string): boolean {
  const meta = db.prepare("SELECT version, fresh FROM session_up_job_meta WHERE id = 1").get() as { version: number; fresh: number } | undefined;
  if (meta === undefined || meta.version !== VERSION) throw new Error(`session up jobs index version ${meta?.version ?? "missing"} is incompatible with ${VERSION}`);
  if (meta.fresh === 1) return true;
  return (db.prepare("SELECT complete FROM session_up_job_scopes WHERE session = ?").get(session) as { complete: number } | undefined)?.complete === 1;
}

export function sessionUpJobsStep(db: DatabaseSync, session: string, limit = 256): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("session up job batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    if (sessionUpJobsReady(db, session)) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    db.prepare(`INSERT INTO session_up_job_scopes (session, last_rowid, end_rowid, complete)
      SELECT ?, NULL, (${SESSION_UP_JOBS_END}), 0
      WHERE NOT EXISTS (SELECT 1 FROM session_up_job_scopes WHERE session = ?)`).run(session, session, session);
    const scope = db.prepare(`SELECT CAST(last_rowid AS TEXT) AS last_rowid, CAST(end_rowid AS TEXT) AS end_rowid
      FROM session_up_job_scopes WHERE session = ?`).get(session) as { last_rowid: string | null; end_rowid: string | null };
    const rows = (scope.last_rowid === null
      ? db.prepare(SESSION_UP_JOBS_FIRST).all(session, scope.end_rowid, limit)
      : db.prepare(SESSION_UP_JOBS_NEXT).all(session, scope.last_rowid, scope.end_rowid, limit)) as { position: string }[];
    const put = db.prepare(see("CAST(? AS INTEGER)"));
    for (const row of rows) put.run(row.position);
    const done = rows.length < limit;
    db.prepare("UPDATE session_up_job_scopes SET last_rowid = CAST(? AS INTEGER), complete = ? WHERE session = ?")
      .run(rows.at(-1)?.position ?? scope.last_rowid, done ? 1 : 0, session);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
