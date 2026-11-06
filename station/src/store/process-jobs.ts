// Jobs without a process group include waiting remote tasks. Keep only running groups here, so a memory or resources
// check need not read that queue. Old jobs are brought forward in small batches and older writers maintain the keys.
import type { DatabaseSync, StatementSync } from "node:sqlite";

const VERSION = 1;
const EXISTS = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'process_job_meta'";
const statements = new WeakMap<DatabaseSync, Map<string, StatementSync>>();
const presence = new WeakMap<DatabaseSync, boolean>();
function statement(db: DatabaseSync, sql: string): StatementSync {
  let cached = statements.get(db);
  if (cached === undefined) { cached = new Map(); statements.set(db, cached); }
  let result = cached.get(sql);
  if (result === undefined) { result = db.prepare(sql); cached.set(sql, result); }
  return result;
}

const active = (row: string) => `(${row}.state = 'running' AND ${row}.pgid IS NOT NULL)`;
const changed = `OLD.rowid IS NOT NEW.rowid OR OLD.id IS NOT NEW.id OR OLD.token IS NOT NEW.token
  OR ${active("OLD")} IS NOT ${active("NEW")} OR EXISTS (SELECT 1 FROM process_job_replaced)`;
// Seek each unique identity before testing the state. Putting the OR and the state in one WHERE lets SQLite choose
// jobs_up(state) instead, rereading the entire running queue on each insert.
const conflict = (id: string, token: string, rowid: string) => `SELECT j.id FROM (
  SELECT rowid AS position FROM jobs WHERE id = ${id}
  UNION SELECT rowid FROM jobs WHERE token = ${token}
  UNION SELECT rowid FROM jobs WHERE rowid = ${rowid}
) p CROSS JOIN jobs j ON j.rowid = p.position WHERE ${active("j")} AND j.id IS NOT NULL`;
export const PROCESS_JOB_CONFLICT = conflict("?1", "?2", "?3");
const conflicts = conflict("NEW.id", "NEW.token", "NEW.rowid");
const stage = (old: boolean) => `DELETE FROM process_job_replaced WHERE job IS NOT NULL;
  INSERT INTO process_job_replaced (job) ${conflicts}
    ${old ? `UNION SELECT OLD.id WHERE OLD.id IS NOT NULL AND ${active("OLD")}` : ""};`;
const see = (rowid: string) => `INSERT INTO process_job_rows (job)
  SELECT j.id FROM jobs j WHERE j.rowid = ${rowid} AND j.id IS NOT NULL AND ${active("j")}
    AND NOT EXISTS (SELECT 1 FROM process_job_rows p WHERE p.job = j.id);`;
const reconcile = `DELETE FROM process_job_rows WHERE job IN (SELECT job FROM process_job_replaced)
    AND NOT EXISTS (SELECT 1 FROM jobs j WHERE j.id = process_job_rows.job AND ${active("j")});
  INSERT INTO process_job_rows (job)
    SELECT j.id FROM process_job_replaced p CROSS JOIN jobs j ON j.id = p.job
    WHERE ${active("j")} AND NOT EXISTS (SELECT 1 FROM process_job_rows r WHERE r.job = j.id);
  DELETE FROM process_job_replaced WHERE job IS NOT NULL;`;

export const PROCESS_JOB_END = "SELECT CAST(rowid AS TEXT) AS position FROM jobs INDEXED BY jobs_state WHERE state = 'running' ORDER BY rowid DESC LIMIT 1";
export const PROCESS_JOB_FIRST = `SELECT CAST(rowid AS TEXT) AS position FROM jobs INDEXED BY jobs_state
  WHERE state = 'running' AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?`;
export const PROCESS_JOB_NEXT = `SELECT CAST(rowid AS TEXT) AS position FROM jobs INDEXED BY jobs_state
  WHERE state = 'running' AND rowid > CAST(? AS INTEGER) AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?`;
export const PROCESS_JOBS = `SELECT j.id, j.session_key, j.name, j.port, j.pgid FROM process_job_rows p
  CROSS JOIN jobs j ON j.id = p.job WHERE j.state = 'running' AND j.pgid IS NOT NULL
  ORDER BY j.started_at DESC, j.port, j.rowid`;
export const PROCESS_JOB_NULL_ID = "SELECT 1 FROM jobs WHERE id IS NULL AND state = 'running' AND pgid IS NOT NULL LIMIT 1";

export type ProcessJob = { id: string; sessionKey: string; name: string; port: number | null; pgid: number };

export function hasProcessJobs(db: DatabaseSync): boolean {
  const known = presence.get(db);
  if (known !== undefined) return known;
  const found = statement(db, EXISTS).get() !== undefined;
  presence.set(db, found);
  return found;
}

/// The worker may install the lookup on its own connection.
export function refreshProcessJobs(db: DatabaseSync): boolean {
  presence.delete(db);
  return hasProcessJobs(db);
}

export function installProcessJobs(db: DatabaseSync): void {
  if (refreshProcessJobs(db)) { processJobsReady(db); return; }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!refreshProcessJobs(db)) {
      db.exec(`
        CREATE TABLE process_job_meta (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL,
          complete INTEGER NOT NULL, cursor INTEGER, end_rowid INTEGER, schema_version INTEGER) WITHOUT ROWID;
        INSERT INTO process_job_meta (id, version, complete, cursor, end_rowid) VALUES (1, ${VERSION}, 0, NULL,
          CAST((${PROCESS_JOB_END}) AS INTEGER));
        CREATE TABLE process_job_rows (job TEXT PRIMARY KEY) WITHOUT ROWID;
        CREATE TABLE process_job_replaced (job TEXT PRIMARY KEY) WITHOUT ROWID;
        CREATE TRIGGER process_job_before_add BEFORE INSERT ON jobs
          WHEN EXISTS (SELECT 1 FROM process_job_replaced) OR EXISTS (${conflicts}) BEGIN ${stage(false)} END;
        CREATE TRIGGER process_job_add AFTER INSERT ON jobs
          WHEN ${active("NEW")} OR EXISTS (SELECT 1 FROM process_job_replaced) BEGIN ${reconcile} ${see("NEW.rowid")} END;
        CREATE TRIGGER process_job_before_change BEFORE UPDATE ON jobs WHEN ${changed} BEGIN ${stage(true)} END;
        CREATE TRIGGER process_job_change AFTER UPDATE ON jobs WHEN ${changed} BEGIN ${reconcile} ${see("NEW.rowid")} END;
        CREATE TRIGGER process_job_drop AFTER DELETE ON jobs WHEN ${active("OLD")} BEGIN
          DELETE FROM process_job_rows WHERE job = OLD.id;
        END;
      `);
      const schema = (db.prepare("PRAGMA schema_version").get() as { schema_version: number }).schema_version;
      db.prepare("UPDATE process_job_meta SET schema_version = ? WHERE id = 1").run(schema);
    } else processJobsReady(db);
    db.exec("COMMIT");
    presence.set(db, true);
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function processJobsReady(db: DatabaseSync): boolean {
  if (!hasProcessJobs(db)) return false;
  const meta = statement(db, "SELECT version, complete FROM process_job_meta WHERE id = 1").get() as
    { version: number; complete: number } | undefined;
  if (meta?.version !== VERSION) throw new Error(`process job index version ${meta?.version ?? "missing"} is incompatible with ${VERSION}`);
  return meta.complete === 1;
}

/// A VACUUM can renumber old job rowids between batches. The lookup stores stable ids; if the schema cookie changes,
/// start its bounded cursor over so no row moved behind that cursor is missed.
export function processJobsStep(db: DatabaseSync, limit = 64): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("process job batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const meta = db.prepare(`SELECT version, complete, CAST(cursor AS TEXT) AS cursor,
      CAST(end_rowid AS TEXT) AS end_rowid, schema_version FROM process_job_meta WHERE id = 1`).get() as
      { version: number; complete: number; cursor: string | null; end_rowid: string | null; schema_version: number } | undefined;
    if (meta?.version !== VERSION) throw new Error(`process job index version ${meta?.version ?? "missing"} is incompatible with ${VERSION}`);
    if (meta.complete === 1) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const schema = (db.prepare("PRAGMA schema_version").get() as { schema_version: number }).schema_version;
    let { cursor, end_rowid } = meta;
    if (schema !== meta.schema_version) {
      cursor = null;
      end_rowid = (db.prepare(PROCESS_JOB_END).get() as { position: string } | undefined)?.position ?? null;
    }
    const rows = end_rowid === null ? [] : (cursor === null
      ? db.prepare(PROCESS_JOB_FIRST).all(end_rowid, limit)
      : db.prepare(PROCESS_JOB_NEXT).all(cursor, end_rowid, limit)) as { position: string }[];
    const put = db.prepare(see("CAST(? AS INTEGER)"));
    for (const row of rows) put.run(row.position);
    const done = rows.length < limit;
    db.prepare("UPDATE process_job_meta SET cursor = CAST(? AS INTEGER), end_rowid = CAST(? AS INTEGER), complete = ?, schema_version = ? WHERE id = 1")
      .run(rows.at(-1)?.position ?? cursor, end_rowid, done ? 1 : 0, schema);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

/// Read readiness, compatibility and rows in one snapshot; until ready keep the old immediate answer.
export function processJobs(db: DatabaseSync): ProcessJob[] | null {
  if (!hasProcessJobs(db)) return null;
  db.exec("BEGIN");
  try {
    if (!processJobsReady(db) || statement(db, PROCESS_JOB_NULL_ID).get() !== undefined) { db.exec("COMMIT"); return null; }
    const rows = statement(db, PROCESS_JOBS).all() as { id: string; session_key: string; name: string; port: number | null; pgid: number }[];
    db.exec("COMMIT");
    return rows.map((r) => ({ id: r.id, sessionKey: r.session_key, name: r.name, port: r.port, pgid: r.pgid }));
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
