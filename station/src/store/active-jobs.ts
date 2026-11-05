// Jobs running without watch. Watched jobs are kept separately by watch-jobs.ts so an older station can keep using its
// watch lookup while a newer one checks the running limit without reading a session's completed jobs.
import type { DatabaseSync } from "node:sqlite";

/// The jobs that count as work for the machine's awake check. Watched services use the watch lookup; all jobs without
/// a port use the existing state-and-port index. A watched job without a port is taken only from the first side.
export const AWAKE_JOBS = `SELECT j.session_key, j.started_at FROM active_watch_jobs w
  CROSS JOIN jobs j ON j.id = w.job WHERE j.state = 'running' AND j.watch <> 0
  UNION ALL
  SELECT session_key, started_at FROM jobs INDEXED BY jobs_up WHERE state = 'running' AND port IS NULL AND watch = 0`;

export const RUNNING_LIMIT = `SELECT job FROM (
  SELECT job FROM active_watch_jobs INDEXED BY active_watch_jobs_session WHERE session = ?1
  UNION ALL
  SELECT job FROM active_other_jobs WHERE session = ?1
) LIMIT 1 OFFSET ?2`;
/// A stopped wait ends its running watches and commands, but leaves services running.
export const RUNNING_WAIT_JOBS = `SELECT j.id FROM (
  SELECT job FROM active_watch_jobs INDEXED BY active_watch_jobs_session WHERE session = ?1
  UNION ALL
  SELECT job FROM active_other_jobs WHERE session = ?1
) active CROSS JOIN jobs j ON j.id = active.job
WHERE j.watch <> 0 OR j.port IS NULL
ORDER BY j.started_at DESC`;
/// An archived session stops every running job and each service waiting to restart. The second seek visits only
/// exited services station-wide, not the session's completed commands (which can grow with its history).
export const UP_JOBS_OF_SESSION = `SELECT id FROM (
  SELECT j.id, j.started_at FROM (
    SELECT job FROM active_watch_jobs INDEXED BY active_watch_jobs_session WHERE session = ?1
    UNION ALL
    SELECT job FROM active_other_jobs WHERE session = ?1
  ) active CROSS JOIN jobs j ON j.id = active.job
  UNION ALL
  SELECT id, started_at FROM jobs INDEXED BY jobs_up WHERE state = 'exited' AND port IS NOT NULL AND session_key = ?1
) ORDER BY started_at DESC`;
export const OTHER_JOBS_AT_INSTALL = "SELECT session_key, id FROM jobs INDEXED BY jobs_state WHERE state = 'running' AND watch = 0";

/// The remote queue's running and waiting jobs. Both lookups seek the remote id prefix, including watched tasks;
/// rowid preserves the former running-jobs query's order when several jobs have the same start time.
export const REMOTE_QUEUE_JOBS = `SELECT * FROM (
  SELECT j.id, j.session_key, j.started_at, j.queued, j.screen, j.small, j.rowid AS queue_rowid FROM active_watch_jobs w
    CROSS JOIN jobs j ON j.id = w.job WHERE w.job >= 'remote_' AND w.job < 'remote\`'
  UNION ALL
  SELECT j.id, j.session_key, j.started_at, j.queued, j.screen, j.small, j.rowid AS queue_rowid FROM active_other_jobs a INDEXED BY active_other_remote_jobs
    CROSS JOIN jobs j ON j.id = a.job WHERE a.job >= 'remote_' AND a.job < 'remote\`'
) ORDER BY started_at DESC, queue_rowid`;

/// Only the active ordinary jobs are scanned once on upgrade; subsequent writes to local jobs do not touch the index.
export function installRemoteQueueIndex(db: DatabaseSync): void {
  db.exec(`CREATE INDEX IF NOT EXISTS active_other_remote_jobs ON active_other_jobs (job)
    WHERE job >= 'remote_' AND job < 'remote\`'`);
}

/// Install the lookup and its writers atomically. Only currently running jobs are read on upgrade.
export function installOtherActiveJobs(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'active_other_jobs'").get() !== undefined;
  if (installed()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    // REPLACE can remove another id by its token without firing DELETE triggers. Stage only conflicting old active
    // jobs before a write; an ignored write may leave the stage behind, so the next insert or update clears it first.
    // The WHERE on its DELETEs keeps SQLite from dirtying the empty staging table on every ordinary job write.
    if (!installed()) db.exec(`
      CREATE TABLE active_other_jobs (session TEXT NOT NULL, job TEXT NOT NULL, PRIMARY KEY (session, job)) WITHOUT ROWID;
      CREATE TABLE active_other_replaced (session TEXT NOT NULL, job TEXT NOT NULL, PRIMARY KEY (session, job)) WITHOUT ROWID;
      CREATE TRIGGER active_other_job_before_add BEFORE INSERT ON jobs
        WHEN EXISTS (SELECT 1 FROM active_other_replaced)
          OR EXISTS (SELECT 1 FROM jobs WHERE id = NEW.id OR token = NEW.token) BEGIN
        DELETE FROM active_other_replaced WHERE session IS NOT NULL;
        INSERT INTO active_other_replaced
          SELECT session_key, id FROM jobs WHERE (id = NEW.id OR token = NEW.token) AND state = 'running' AND watch = 0;
      END;
      CREATE TRIGGER active_other_job_add AFTER INSERT ON jobs
        WHEN (NEW.state = 'running' AND NEW.watch = 0) OR EXISTS (SELECT 1 FROM active_other_replaced) BEGIN
        DELETE FROM active_other_jobs WHERE (session, job) IN (SELECT session, job FROM active_other_replaced);
        DELETE FROM active_other_replaced WHERE session IS NOT NULL;
        INSERT INTO active_other_jobs SELECT NEW.session_key, NEW.id WHERE NEW.state = 'running' AND NEW.watch = 0;
      END;
      CREATE TRIGGER active_other_job_before_change BEFORE UPDATE OF id, session_key, state, watch, token ON jobs
        WHEN OLD.id IS NOT NEW.id OR OLD.token IS NOT NEW.token OR EXISTS (SELECT 1 FROM active_other_replaced) BEGIN
        DELETE FROM active_other_replaced WHERE session IS NOT NULL;
        INSERT INTO active_other_replaced SELECT session_key, id FROM jobs
          WHERE (OLD.id IS NOT NEW.id OR OLD.token IS NOT NEW.token) AND id <> OLD.id
            AND (id = NEW.id OR token = NEW.token) AND state = 'running' AND watch = 0;
      END;
      CREATE TRIGGER active_other_job_change AFTER UPDATE OF id, session_key, state, watch, token ON jobs
        WHEN ((OLD.id IS NOT NEW.id OR OLD.session_key IS NOT NEW.session_key OR OLD.state IS NOT NEW.state
          OR OLD.watch IS NOT NEW.watch) AND ((OLD.state = 'running' AND OLD.watch = 0) OR (NEW.state = 'running' AND NEW.watch = 0)))
          OR EXISTS (SELECT 1 FROM active_other_replaced) BEGIN
        DELETE FROM active_other_jobs WHERE (session = OLD.session_key AND job = OLD.id)
          OR (session, job) IN (SELECT session, job FROM active_other_replaced);
        DELETE FROM active_other_replaced WHERE session IS NOT NULL;
        INSERT INTO active_other_jobs SELECT NEW.session_key, NEW.id WHERE NEW.state = 'running' AND NEW.watch = 0;
      END;
      CREATE TRIGGER active_other_job_drop AFTER DELETE ON jobs WHEN OLD.state = 'running' AND OLD.watch = 0 BEGIN
        DELETE FROM active_other_jobs WHERE session = OLD.session_key AND job = OLD.id;
      END;
      INSERT INTO active_other_jobs ${OTHER_JOBS_AT_INSTALL};
    `);
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}
