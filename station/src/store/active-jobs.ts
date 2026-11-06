// Jobs running without watch. Watched jobs are kept separately by watch-jobs.ts so an older station can keep using its
// watch lookup while a newer one checks the running limit without reading a session's completed jobs.
import type { DatabaseSync } from "node:sqlite";
import { activeJobsFitAtOpen, activeJobsUpgradePending } from "./watch-jobs.ts";

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
/// A stopped wait ends its running watches and commands, but leaves services running. Ties keep watches before
/// ordinary jobs, and job order within each group, as the active lookups previously returned them.
export const RUNNING_WAIT_JOBS = `SELECT j.id FROM (
  SELECT job FROM active_watch_jobs INDEXED BY active_watch_jobs_session WHERE session = ?1
  UNION ALL
  SELECT job FROM active_other_jobs WHERE session = ?1
) active CROSS JOIN jobs j ON j.id = active.job
WHERE j.watch <> 0 OR j.port IS NULL
ORDER BY j.started_at DESC, (j.watch = 0), j.id`;
/// An archived session stops every running job and each service waiting to restart. The second seek visits only
/// exited services station-wide, not the session's completed commands (which can grow with its history). Equal start
/// times retain the active lookups' order, followed by restarting services in their port order.
export const UP_JOBS_OF_SESSION = `SELECT id FROM (
  SELECT j.id, j.started_at, (j.watch = 0) AS sort_kind, j.id AS sort_id, NULL AS sort_port, j.rowid AS sort_rowid FROM (
    SELECT job FROM active_watch_jobs INDEXED BY active_watch_jobs_session WHERE session = ?1
    UNION ALL
    SELECT job FROM active_other_jobs WHERE session = ?1
  ) active CROSS JOIN jobs j ON j.id = active.job
  UNION ALL
  SELECT id, started_at, 2 AS sort_kind, NULL AS sort_id, port AS sort_port, rowid AS sort_rowid
    FROM jobs INDEXED BY jobs_up WHERE state = 'exited' AND port IS NOT NULL AND session_key = ?1
) ORDER BY started_at DESC, sort_kind, sort_id, sort_port, sort_rowid`;
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

/// While an old store is being prepared, the original jobs table remains the source of each answer.
export const AWAKE_JOBS_BEFORE_UPGRADE = `SELECT session_key, started_at FROM jobs INDEXED BY jobs_state
  WHERE state = 'running' AND (watch <> 0 OR port IS NULL)`;
export const RUNNING_LIMIT_BEFORE_UPGRADE = `SELECT id FROM jobs INDEXED BY jobs_by_session
  WHERE session_key = ?1 AND state = 'running' LIMIT 1 OFFSET ?2`;
export const RUNNING_WAIT_JOBS_BEFORE_UPGRADE = `SELECT id FROM jobs INDEXED BY jobs_by_session
  WHERE session_key = ?1 AND state = 'running' AND (watch <> 0 OR port IS NULL)
  ORDER BY started_at DESC, (watch = 0), id`;
export const UP_JOBS_BEFORE_UPGRADE = `SELECT id FROM jobs INDEXED BY jobs_by_session
  WHERE session_key = ?1 AND (state = 'running' OR (state = 'exited' AND port IS NOT NULL))
  ORDER BY started_at DESC, CASE WHEN state = 'running' THEN (watch = 0) ELSE 2 END,
    CASE WHEN state = 'running' THEN id END, CASE WHEN state = 'exited' THEN port END, rowid`;
export const REMOTE_QUEUE_BEFORE_UPGRADE = `SELECT id, session_key, started_at, queued, screen, small FROM jobs
  WHERE id >= 'remote_' AND id < 'remote\`' AND state = 'running' ORDER BY started_at DESC, rowid`;

/// Only the active ordinary jobs are scanned once on upgrade; subsequent writes to local jobs do not touch the index.
export function installRemoteQueueIndex(db: DatabaseSync): void {
  const index = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = 'active_other_remote_jobs'").get() !== undefined;
  const table = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'active_other_jobs'").get() !== undefined;
  const preparing = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'active_remote_job_meta'").get() !== undefined;
  const small = () => db.prepare("SELECT 1 FROM active_other_jobs LIMIT 1 OFFSET 64").get() === undefined;
  if (index() || !table() || preparing() || !small()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!index() && table() && !preparing() && small()) db.exec(`CREATE INDEX active_other_remote_jobs ON active_other_jobs (job)
      WHERE job >= 'remote_' AND job < 'remote\`'`);
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

/// Install the lookup and its writers atomically. Only currently running jobs are read on upgrade.
export function installOtherActiveJobs(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'active_other_jobs'").get() !== undefined;
  if (installed()) return;
  if (activeJobsUpgradePending(db) || !activeJobsFitAtOpen(db)) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    // REPLACE can remove another id by its token without firing DELETE triggers. Stage only conflicting old active
    // jobs before a write; an ignored write may leave the stage behind, so the next insert or update clears it first.
    // The WHERE on its DELETEs keeps SQLite from dirtying the empty staging table on every ordinary job write.
    if (!installed() && !activeJobsUpgradePending(db) && activeJobsFitAtOpen(db)) db.exec(`
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
