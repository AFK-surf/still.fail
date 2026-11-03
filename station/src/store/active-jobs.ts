// Jobs running without watch. Watched jobs are kept separately by watch-jobs.ts so an older station can keep using its
// watch lookup while a newer one checks the running limit without reading a session's completed jobs.
import type { DatabaseSync } from "node:sqlite";

export const RUNNING_LIMIT = `SELECT job FROM (
  SELECT job FROM active_watch_jobs INDEXED BY active_watch_jobs_session WHERE session = ?1
  UNION ALL
  SELECT job FROM active_other_jobs WHERE session = ?1
) LIMIT 1 OFFSET ?2`;
export const OTHER_JOBS_AT_INSTALL = "SELECT session_key, id FROM jobs INDEXED BY jobs_state WHERE state = 'running' AND watch = 0";

/// Install the lookup and its writers atomically. Only currently running jobs are read on upgrade.
export function installOtherActiveJobs(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'active_other_jobs'").get() !== undefined;
  if (installed()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    // REPLACE can remove another id by its token without firing DELETE triggers. Stage only conflicting old active
    // jobs before a write; an ignored write may leave the stage behind, so the next insert or update clears it first.
    if (!installed()) db.exec(`
      CREATE TABLE active_other_jobs (session TEXT NOT NULL, job TEXT NOT NULL, PRIMARY KEY (session, job)) WITHOUT ROWID;
      CREATE TABLE active_other_replaced (session TEXT NOT NULL, job TEXT NOT NULL, PRIMARY KEY (session, job)) WITHOUT ROWID;
      CREATE TRIGGER active_other_job_before_add BEFORE INSERT ON jobs
        WHEN EXISTS (SELECT 1 FROM active_other_replaced)
          OR EXISTS (SELECT 1 FROM jobs WHERE id = NEW.id OR token = NEW.token) BEGIN
        DELETE FROM active_other_replaced;
        INSERT INTO active_other_replaced
          SELECT session_key, id FROM jobs WHERE (id = NEW.id OR token = NEW.token) AND state = 'running' AND watch = 0;
      END;
      CREATE TRIGGER active_other_job_add AFTER INSERT ON jobs
        WHEN (NEW.state = 'running' AND NEW.watch = 0) OR EXISTS (SELECT 1 FROM active_other_replaced) BEGIN
        DELETE FROM active_other_jobs WHERE (session, job) IN (SELECT session, job FROM active_other_replaced);
        DELETE FROM active_other_replaced;
        INSERT INTO active_other_jobs SELECT NEW.session_key, NEW.id WHERE NEW.state = 'running' AND NEW.watch = 0;
      END;
      CREATE TRIGGER active_other_job_before_change BEFORE UPDATE OF id, session_key, state, watch, token ON jobs
        WHEN OLD.id IS NOT NEW.id OR OLD.token IS NOT NEW.token OR EXISTS (SELECT 1 FROM active_other_replaced) BEGIN
        DELETE FROM active_other_replaced;
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
        DELETE FROM active_other_replaced;
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
