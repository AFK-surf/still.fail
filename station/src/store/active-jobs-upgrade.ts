// Older stores may have a large running queue. Prepare the two existing active-job lookups without exposing a
// partial table to older readers, and keep them current while jobs change. Each batch holds the writer for at most
// 64 job keys; before publication callers still answer from jobs itself.
import type { DatabaseSync } from "node:sqlite";

const VERSION = 1;
const exists = (db: DatabaseSync, type: string, name: string) =>
  db.prepare("SELECT 1 FROM sqlite_master WHERE type = ? AND name = ?").get(type, name) !== undefined;
const active = (row: string) => `${row}.state = 'running'`;
const conflict = (other: boolean) => `SELECT j.session_key AS session, j.id AS job FROM (
  SELECT rowid AS position FROM jobs WHERE id = NEW.id
  UNION SELECT rowid FROM jobs WHERE token = NEW.token
  UNION SELECT rowid FROM jobs WHERE rowid = NEW.rowid
) p CROSS JOIN jobs j ON j.rowid = p.position WHERE ${active("j")} AND j.id IS NOT NULL
  ${other ? "AND j.rowid IS NOT OLD.rowid" : ""}`;
export const ACTIVE_JOB_CONFLICT = conflict(false).replaceAll("NEW.id", "?1").replaceAll("NEW.token", "?2").replaceAll("NEW.rowid", "?3");
const changed = `OLD.rowid IS NOT NEW.rowid OR OLD.id IS NOT NEW.id OR OLD.token IS NOT NEW.token
  OR OLD.session_key IS NOT NEW.session_key OR OLD.state IS NOT NEW.state OR OLD.watch IS NOT NEW.watch
  OR EXISTS (SELECT 1 FROM active_job_upgrade_replaced)`;
const stage = (other: boolean) => `DELETE FROM active_job_upgrade_replaced WHERE session IS NOT NULL;
  INSERT INTO active_job_upgrade_replaced (session, job) ${conflict(other)};`;

function statements(watches: boolean, others: boolean) {
  const see = (rowid: string) => `${watches ? `
    INSERT INTO active_job_watch_build (job, session, token)
      SELECT j.id, j.session_key, j.token FROM jobs j WHERE j.rowid = ${rowid} AND j.state = 'running' AND j.watch <> 0
        AND (j.id IS NOT NULL OR (SELECT complete FROM active_job_upgrade WHERE id = 1) = 1)
        AND NOT EXISTS (SELECT 1 FROM active_job_watch_build w WHERE w.job = j.id);` : ""}${others ? `
    INSERT INTO active_job_other_build (session, job)
      SELECT j.session_key, j.id FROM jobs j WHERE j.rowid = ${rowid} AND j.state = 'running' AND j.watch = 0
        AND (j.id IS NOT NULL OR (SELECT complete FROM active_job_upgrade WHERE id = 1) = 1)
        AND NOT EXISTS (SELECT 1 FROM active_job_other_build a WHERE a.session = j.session_key AND a.job = j.id);` : ""}`;
  const reconcile = `${watches ? `
    DELETE FROM active_job_watch_build WHERE job IN (SELECT job FROM active_job_upgrade_replaced)
      AND NOT EXISTS (SELECT 1 FROM jobs j WHERE j.id = active_job_watch_build.job AND j.state = 'running'
        AND j.watch <> 0 AND j.session_key = active_job_watch_build.session AND j.token = active_job_watch_build.token);
    INSERT INTO active_job_watch_build (job, session, token)
      SELECT j.id, j.session_key, j.token FROM active_job_upgrade_replaced r CROSS JOIN jobs j ON j.id = r.job
      WHERE j.state = 'running' AND j.watch <> 0 AND NOT EXISTS (SELECT 1 FROM active_job_watch_build w WHERE w.job = j.id);` : ""}${others ? `
    DELETE FROM active_job_other_build WHERE (session, job) IN (SELECT session, job FROM active_job_upgrade_replaced)
      AND NOT EXISTS (SELECT 1 FROM jobs j WHERE j.id = active_job_other_build.job AND j.state = 'running'
        AND j.watch = 0 AND j.session_key = active_job_other_build.session);
    INSERT INTO active_job_other_build (session, job)
      SELECT j.session_key, j.id FROM active_job_upgrade_replaced r CROSS JOIN jobs j ON j.id = r.job
      WHERE j.state = 'running' AND j.watch = 0
        AND NOT EXISTS (SELECT 1 FROM active_job_other_build a WHERE a.session = j.session_key AND a.job = j.id);` : ""}
    DELETE FROM active_job_upgrade_replaced WHERE session IS NOT NULL;`;
  const drop = `${watches ? "DELETE FROM active_job_watch_build WHERE job = OLD.id;" : ""}
    ${others ? "DELETE FROM active_job_other_build WHERE session = OLD.session_key AND job = OLD.id;" : ""}`;
  return { see, reconcile, drop };
}

export const ACTIVE_JOB_END = "SELECT CAST(rowid AS TEXT) AS position FROM jobs INDEXED BY jobs_state WHERE state = 'running' ORDER BY rowid DESC LIMIT 1";
export const ACTIVE_JOB_NULL_ID = "SELECT 1 FROM jobs INDEXED BY sqlite_autoindex_jobs_1 WHERE id IS NULL AND state = 'running' LIMIT 1";
export const ACTIVE_JOB_FIRST = `SELECT CAST(rowid AS TEXT) AS position FROM jobs INDEXED BY jobs_state
  WHERE state = 'running' AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?`;
export const ACTIVE_JOB_NEXT = `SELECT CAST(rowid AS TEXT) AS position FROM jobs INDEXED BY jobs_state
  WHERE state = 'running' AND rowid > CAST(? AS INTEGER) AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?`;

type Meta = { version: number; complete: number; watches: number; others: number; cursor: string | null; end_rowid: string | null; schema_version: number };
function meta(db: DatabaseSync): Meta | null {
  if (!exists(db, "table", "active_job_upgrade")) return null;
  const row = db.prepare(`SELECT version, complete, watches, others, CAST(cursor AS TEXT) AS cursor,
    CAST(end_rowid AS TEXT) AS end_rowid, schema_version FROM active_job_upgrade WHERE id = 1`).get() as Meta | undefined;
  if (row?.version !== VERSION) throw new Error(`active job upgrade version ${row?.version ?? "missing"} is incompatible with ${VERSION}`);
  return row;
}

export function activeJobUpgradeReady(db: DatabaseSync): boolean {
  const ready = exists(db, "table", "active_watch_jobs") && exists(db, "table", "active_other_jobs");
  return ready && (exists(db, "index", "active_other_remote_jobs") || activeRemoteJobsReady(db));
}

export function installActiveJobUpgrade(db: DatabaseSync): void {
  const current = meta(db);
  if (current !== null || (exists(db, "table", "active_watch_jobs") && exists(db, "table", "active_other_jobs"))) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (meta(db) === null) {
      const watches = !exists(db, "table", "active_watch_jobs");
      const others = !exists(db, "table", "active_other_jobs");
      if (watches || others) {
        const sql = statements(watches, others);
        db.exec(`CREATE TABLE active_job_upgrade (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL,
          complete INTEGER NOT NULL, watches INTEGER NOT NULL, others INTEGER NOT NULL, cursor INTEGER,
          end_rowid INTEGER, schema_version INTEGER) WITHOUT ROWID;
          INSERT INTO active_job_upgrade VALUES (1, ${VERSION}, 0, ${watches ? 1 : 0}, ${others ? 1 : 0}, NULL,
            CAST((${ACTIVE_JOB_END}) AS INTEGER), NULL);
          CREATE TABLE active_job_upgrade_replaced (session TEXT NOT NULL, job TEXT NOT NULL, PRIMARY KEY (session, job)) WITHOUT ROWID;
          ${watches ? `CREATE TABLE active_job_watch_build (job TEXT PRIMARY KEY, session TEXT NOT NULL, token TEXT NOT NULL UNIQUE) WITHOUT ROWID;
            CREATE INDEX active_watch_jobs_session ON active_job_watch_build (session);` : ""}
          ${others ? `CREATE TABLE active_job_other_build (session TEXT NOT NULL, job TEXT NOT NULL, PRIMARY KEY (session, job)) WITHOUT ROWID;
            CREATE INDEX active_other_remote_jobs ON active_job_other_build (job) WHERE job >= 'remote_' AND job < 'remote\`';` : ""}
          CREATE TRIGGER active_job_upgrade_before_add BEFORE INSERT ON jobs
            WHEN EXISTS (SELECT 1 FROM active_job_upgrade_replaced) OR EXISTS (${conflict(false)}) BEGIN ${stage(false)} END;
          CREATE TRIGGER active_job_upgrade_add AFTER INSERT ON jobs
            WHEN ${active("NEW")} OR EXISTS (SELECT 1 FROM active_job_upgrade_replaced) BEGIN ${sql.reconcile} ${sql.see("NEW.rowid")} END;
          CREATE TRIGGER active_job_upgrade_before_change BEFORE UPDATE ON jobs
            WHEN EXISTS (SELECT 1 FROM active_job_upgrade_replaced)
              OR ((OLD.rowid IS NOT NEW.rowid OR OLD.id IS NOT NEW.id OR OLD.token IS NOT NEW.token)
                AND EXISTS (${conflict(true)})) BEGIN ${stage(true)} END;
          CREATE TRIGGER active_job_upgrade_change AFTER UPDATE ON jobs WHEN ${changed} BEGIN ${sql.drop} ${sql.reconcile} ${sql.see("NEW.rowid")} END;
          CREATE TRIGGER active_job_upgrade_drop AFTER DELETE ON jobs WHEN ${active("OLD")} BEGIN ${sql.drop} END;`);
        const schema = (db.prepare("PRAGMA schema_version").get() as { schema_version: number }).schema_version;
        db.prepare("UPDATE active_job_upgrade SET schema_version = ? WHERE id = 1").run(schema);
      }
    }
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

/// A VACUUM can change rowids between batches; schema changes restart the bounded walk, while triggers keep all
/// changes since the walk began. The final rename publishes the complete tables and their prebuilt indexes together.
export function activeJobUpgradeStep(db: DatabaseSync, limit = 64): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("active job batch must be positive");
  installActiveJobUpgrade(db);
  const initial = meta(db);
  if (initial === null || initial.complete === 1) return activeRemoteJobsStep(db, limit);
  db.exec("BEGIN IMMEDIATE");
  try {
    const current = meta(db)!;
    if (current.complete === 1) { db.exec("COMMIT"); return { done: activeJobUpgradeReady(db), visited: 0 }; }
    const schema = (db.prepare("PRAGMA schema_version").get() as { schema_version: number }).schema_version;
    let { cursor, end_rowid } = current;
    if (schema !== current.schema_version) {
      cursor = null;
      end_rowid = (db.prepare(ACTIVE_JOB_END).get() as { position: string } | undefined)?.position ?? null;
    }
    const rows = end_rowid === null ? [] : (cursor === null
      ? db.prepare(ACTIVE_JOB_FIRST).all(end_rowid, limit)
      : db.prepare(ACTIVE_JOB_NEXT).all(cursor, end_rowid, limit)) as { position: string }[];
    const sql = statements(current.watches === 1, current.others === 1);
    const puts = sql.see("CAST(? AS INTEGER)").split(";").map((s) => s.trim()).filter(Boolean).map((s) => db.prepare(s));
    for (const row of rows) for (const put of puts) put.run(row.position);
    const finished = rows.length < limit;
    if (finished) {
      // A pre-index writer could make an active row without an id. It cannot be represented in either lookup, so
      // continue answering from jobs until it is gone instead of publishing an incomplete index or rejecting it.
      if (db.prepare(ACTIVE_JOB_NULL_ID).get() !== undefined) throw new Error("a running job without an id cannot yet be indexed");
      if (current.watches) db.exec("ALTER TABLE active_job_watch_build RENAME TO active_watch_jobs");
      if (current.others) db.exec("ALTER TABLE active_job_other_build RENAME TO active_other_jobs");
    }
    db.prepare("UPDATE active_job_upgrade SET cursor = CAST(? AS INTEGER), end_rowid = CAST(? AS INTEGER), complete = ?, schema_version = ? WHERE id = 1")
      .run(rows.at(-1)?.position ?? cursor, end_rowid, finished ? 1 : 0, schema);
    db.exec("COMMIT");
    return { done: finished && activeJobUpgradeReady(db), visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

// An older store can already have active_other_jobs but lack its later remote-only index. Building that SQLite index
// would scan the entire table in one writer transaction, so keep the remote keys in a separately prepared table instead.
const REMOTE = "job >= 'remote_' AND job < 'remote`'";
export const ACTIVE_REMOTE_FIRST = "SELECT session, job FROM active_other_jobs WHERE (session, job) <= (?, ?) ORDER BY session, job LIMIT ?";
export const ACTIVE_REMOTE_NEXT = "SELECT session, job FROM active_other_jobs WHERE (session, job) > (?, ?) AND (session, job) <= (?, ?) ORDER BY session, job LIMIT ?";
function activeRemoteJobsReady(db: DatabaseSync): boolean {
  if (!exists(db, "table", "active_remote_job_meta")) return false;
  const row = db.prepare("SELECT version, complete FROM active_remote_job_meta WHERE id = 1").get() as
    { version: number; complete: number } | undefined;
  return row?.version === VERSION && row.complete === 1;
}

export function activeRemoteJobsAvailable(db: DatabaseSync): boolean {
  return activeRemoteJobsReady(db);
}

export const REMOTE_QUEUE_PREPARED = `SELECT * FROM (
  SELECT j.id, j.session_key, j.started_at, j.queued, j.screen, j.small, j.rowid AS queue_rowid FROM active_watch_jobs w
    CROSS JOIN jobs j ON j.id = w.job WHERE w.job >= 'remote_' AND w.job < 'remote\`'
  UNION ALL
  SELECT j.id, j.session_key, j.started_at, j.queued, j.screen, j.small, j.rowid AS queue_rowid FROM active_remote_job_rows a
    CROSS JOIN jobs j ON j.id = a.job WHERE a.job >= 'remote_' AND a.job < 'remote\`'
) ORDER BY started_at DESC, queue_rowid`;

function installActiveRemoteJobs(db: DatabaseSync): void {
  if (exists(db, "index", "active_other_remote_jobs") || exists(db, "table", "active_remote_job_meta")
    || !exists(db, "table", "active_other_jobs")) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!exists(db, "index", "active_other_remote_jobs") && !exists(db, "table", "active_remote_job_meta")) db.exec(`
      CREATE TABLE active_remote_job_meta (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL,
        complete INTEGER NOT NULL, cursor_session TEXT, cursor_job TEXT, end_session TEXT, end_job TEXT) WITHOUT ROWID;
      INSERT INTO active_remote_job_meta SELECT 1, ${VERSION}, 0, NULL, NULL,
        (SELECT session FROM active_other_jobs ORDER BY session DESC, job DESC LIMIT 1),
        (SELECT job FROM active_other_jobs ORDER BY session DESC, job DESC LIMIT 1);
      CREATE TABLE active_remote_job_rows (job TEXT NOT NULL, session TEXT NOT NULL, PRIMARY KEY (job, session)) WITHOUT ROWID;
      CREATE TRIGGER active_remote_job_add AFTER INSERT ON active_other_jobs WHEN NEW.job >= 'remote_' AND NEW.job < 'remote\`' BEGIN
        INSERT OR IGNORE INTO active_remote_job_rows VALUES (NEW.job, NEW.session);
      END;
      CREATE TRIGGER active_remote_job_drop AFTER DELETE ON active_other_jobs WHEN OLD.job >= 'remote_' AND OLD.job < 'remote\`' BEGIN
        DELETE FROM active_remote_job_rows WHERE job = OLD.job AND session = OLD.session;
      END;
      CREATE TRIGGER active_remote_job_change AFTER UPDATE ON active_other_jobs BEGIN
        DELETE FROM active_remote_job_rows WHERE job = OLD.job AND session = OLD.session;
        INSERT OR IGNORE INTO active_remote_job_rows SELECT NEW.job, NEW.session WHERE NEW.job >= 'remote_' AND NEW.job < 'remote\`';
      END;`);
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

function activeRemoteJobsStep(db: DatabaseSync, limit: number): { done: boolean; visited: number } {
  if (exists(db, "index", "active_other_remote_jobs")) return { done: activeJobUpgradeReady(db), visited: 0 };
  installActiveRemoteJobs(db);
  if (!exists(db, "table", "active_remote_job_meta")) return { done: false, visited: 0 };
  db.exec("BEGIN IMMEDIATE");
  try {
    const row = db.prepare("SELECT * FROM active_remote_job_meta WHERE id = 1").get() as
      { version: number; complete: number; cursor_session: string | null; cursor_job: string | null; end_session: string | null; end_job: string | null };
    if (row.version !== VERSION) throw new Error(`active remote job version ${row.version} is incompatible with ${VERSION}`);
    if (row.complete === 1) { db.exec("COMMIT"); return { done: activeJobUpgradeReady(db), visited: 0 }; }
    const rows = row.end_session === null ? [] : (row.cursor_session === null
      ? db.prepare(ACTIVE_REMOTE_FIRST)
        .all(row.end_session, row.end_job, limit)
      : db.prepare(ACTIVE_REMOTE_NEXT)
        .all(row.cursor_session, row.cursor_job, row.end_session, row.end_job, limit)) as { session: string; job: string }[];
    const add = db.prepare(`INSERT OR IGNORE INTO active_remote_job_rows SELECT job, session FROM active_other_jobs
      WHERE session = ? AND job = ? AND ${REMOTE}`);
    for (const value of rows) add.run(value.session, value.job);
    const last = rows.at(-1);
    const done = rows.length < limit;
    db.prepare("UPDATE active_remote_job_meta SET cursor_session = ?, cursor_job = ?, complete = ? WHERE id = 1")
      .run(last?.session ?? row.cursor_session, last?.job ?? row.cursor_job, done ? 1 : 0);
    db.exec("COMMIT");
    return { done: done && activeJobUpgradeReady(db), visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
