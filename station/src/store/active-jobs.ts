// Jobs running without watch. Watched jobs are kept separately by watch-jobs.ts so an older station can keep using its
// watch lookup while a newer one checks the running limit without reading a session's completed jobs.
import type { DatabaseSync } from "node:sqlite";

export const RUNNING_LIMIT = `SELECT job FROM (
  SELECT job FROM active_watch_jobs INDEXED BY active_watch_jobs_session WHERE session = ?1
  UNION ALL
  SELECT job FROM active_other_jobs INDEXED BY active_other_jobs_session WHERE session = ?1
) LIMIT 1 OFFSET ?2`;
export const OTHER_JOBS_AT_INSTALL = "SELECT id, session_key, token FROM jobs INDEXED BY jobs_state WHERE state = 'running' AND watch = 0";

/// Install the lookup and its writers atomically. Only currently running jobs are read on upgrade.
export function installOtherActiveJobs(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'active_other_jobs'").get() !== undefined;
  if (installed()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    // Remember the token too: REPLACE can displace a different id by its unique token without firing DELETE triggers.
    if (!installed()) db.exec(`
      CREATE TABLE active_other_jobs (job TEXT PRIMARY KEY, session TEXT NOT NULL, token TEXT NOT NULL UNIQUE) WITHOUT ROWID;
      CREATE INDEX active_other_jobs_session ON active_other_jobs (session);
      CREATE TRIGGER active_other_job_add AFTER INSERT ON jobs
        WHEN (NEW.state = 'running' AND NEW.watch = 0)
          OR EXISTS (SELECT 1 FROM active_other_jobs WHERE job = NEW.id OR token = NEW.token) BEGIN
        DELETE FROM active_other_jobs WHERE job = NEW.id OR token = NEW.token;
        INSERT INTO active_other_jobs SELECT NEW.id, NEW.session_key, NEW.token WHERE NEW.state = 'running' AND NEW.watch = 0;
      END;
      CREATE TRIGGER active_other_job_change AFTER UPDATE OF id, session_key, state, watch, token ON jobs
        WHEN (OLD.id IS NOT NEW.id OR OLD.session_key IS NOT NEW.session_key OR OLD.state IS NOT NEW.state
          OR OLD.watch IS NOT NEW.watch OR OLD.token IS NOT NEW.token)
          AND ((OLD.state = 'running' AND OLD.watch = 0) OR (NEW.state = 'running' AND NEW.watch = 0)
            OR EXISTS (SELECT 1 FROM active_other_jobs WHERE job = NEW.id OR token = NEW.token)) BEGIN
        DELETE FROM active_other_jobs WHERE job IN (OLD.id, NEW.id) OR token = NEW.token;
        INSERT INTO active_other_jobs SELECT NEW.id, NEW.session_key, NEW.token WHERE NEW.state = 'running' AND NEW.watch = 0;
      END;
      CREATE TRIGGER active_other_job_drop AFTER DELETE ON jobs WHEN OLD.state = 'running' AND OLD.watch = 0 BEGIN
        DELETE FROM active_other_jobs WHERE job = OLD.id;
      END;
      INSERT INTO active_other_jobs ${OTHER_JOBS_AT_INSTALL};
    `);
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}
