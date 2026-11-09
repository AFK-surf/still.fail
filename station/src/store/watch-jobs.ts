// A chat's active watches. The job table remains the source; only running watches are kept here so naming a chat
// never has to read all the jobs its agents ran before.
import type { DatabaseSync } from "node:sqlite";
import { ACTIVE_JOB_NULL_ID } from "./active-jobs-upgrade.ts";

export const HAS_ACTIVE_WATCH = `SELECT 1 FROM thread_sessions t
  CROSS JOIN active_watch_jobs w INDEXED BY active_watch_jobs_session ON w.session = t.session
  WHERE t.thread = ? LIMIT 1`;
export const HAS_SESSION_ACTIVE_WATCH = "SELECT 1 FROM active_watch_jobs INDEXED BY active_watch_jobs_session WHERE session = ? LIMIT 1";
export const HAS_ACTIVE_WATCH_BEFORE_UPGRADE = `SELECT 1 FROM thread_sessions t
  CROSS JOIN jobs j INDEXED BY jobs_by_session ON j.session_key = t.session
  WHERE t.thread = ? AND j.state = 'running' AND j.watch <> 0 LIMIT 1`;
export const HAS_SESSION_ACTIVE_WATCH_BEFORE_UPGRADE = `SELECT 1 FROM jobs INDEXED BY jobs_by_session
  WHERE session_key = ? AND state = 'running' AND watch <> 0 LIMIT 1`;
export const ACTIVE_WATCHES_AT_INSTALL = "SELECT id, session_key, token FROM jobs INDEXED BY jobs_state WHERE state = 'running' AND watch <> 0";

/// A small old database can still install immediately. The check is repeated under the writer lock: a previous
/// station may have started more jobs since the first read. Larger stores are prepared on a worker.
export function activeJobsFitAtOpen(db: DatabaseSync): boolean {
  return db.prepare("SELECT 1 FROM jobs INDEXED BY jobs_state WHERE state = 'running' LIMIT 1 OFFSET 64").get() === undefined
    && db.prepare(ACTIVE_JOB_NULL_ID).get() === undefined;
}

export function activeJobsUpgradePending(db: DatabaseSync): boolean {
  if (db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'active_job_upgrade'").get() === undefined) return false;
  return db.prepare("SELECT 1 FROM active_job_upgrade WHERE id = 1 AND complete = 0").get() !== undefined;
}

/// Install the lookup with the writers, and bring over only watches running now through the jobs' state index.
export function installActiveWatches(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'active_watch_jobs'").get() !== undefined;
  if (installed()) return;
  if (activeJobsUpgradePending(db) || !activeJobsFitAtOpen(db)) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    // A previous writer can REPLACE a job by its unique token with recursive triggers off. Remember that token so the
    // insertion's trigger can remove the displaced watch even when it had a different id.
    if (!installed() && !activeJobsUpgradePending(db) && activeJobsFitAtOpen(db)) db.exec(`
      CREATE TABLE active_watch_jobs (job TEXT PRIMARY KEY, session TEXT NOT NULL, token TEXT NOT NULL UNIQUE) WITHOUT ROWID;
      CREATE INDEX active_watch_jobs_session ON active_watch_jobs (session);
      CREATE TRIGGER active_watch_job_add AFTER INSERT ON jobs
        WHEN (NEW.state = 'running' AND NEW.watch <> 0)
          OR EXISTS (SELECT 1 FROM active_watch_jobs WHERE job = NEW.id OR token = NEW.token) BEGIN
        DELETE FROM active_watch_jobs WHERE job = NEW.id OR token = NEW.token;
        INSERT INTO active_watch_jobs SELECT NEW.id, NEW.session_key, NEW.token WHERE NEW.state = 'running' AND NEW.watch <> 0;
      END;
      CREATE TRIGGER active_watch_job_change AFTER UPDATE OF id, session_key, state, watch, token ON jobs
        WHEN (OLD.id IS NOT NEW.id OR OLD.session_key IS NOT NEW.session_key OR OLD.state IS NOT NEW.state
          OR OLD.watch IS NOT NEW.watch OR OLD.token IS NOT NEW.token)
          AND ((OLD.state = 'running' AND OLD.watch <> 0) OR (NEW.state = 'running' AND NEW.watch <> 0)
            OR EXISTS (SELECT 1 FROM active_watch_jobs WHERE job = NEW.id OR token = NEW.token)) BEGIN
        DELETE FROM active_watch_jobs WHERE job IN (OLD.id, NEW.id) OR token = NEW.token;
        INSERT INTO active_watch_jobs SELECT NEW.id, NEW.session_key, NEW.token WHERE NEW.state = 'running' AND NEW.watch <> 0;
      END;
      CREATE TRIGGER active_watch_job_drop AFTER DELETE ON jobs WHEN OLD.state = 'running' AND OLD.watch <> 0 BEGIN
        DELETE FROM active_watch_jobs WHERE job = OLD.id;
      END;
      INSERT INTO active_watch_jobs ${ACTIVE_WATCHES_AT_INSTALL};
    `);
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}
