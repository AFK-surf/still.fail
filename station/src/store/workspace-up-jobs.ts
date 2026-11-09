// Work in progress: a workspace's sessions with jobs up. Callers must not use this until old up jobs have been copied.
import type { DatabaseSync } from "node:sqlite";

const VERSION = 1;
const PORT_BATCHES_PER_GUARD = 8;
const up = (row: string) => `(${row}.state = 'running' OR (${row}.state = 'exited' AND ${row}.port IS NOT NULL))`;
const odd = (session: string, ws: string) => `(typeof(${session}) <> 'text'
  OR instr(CAST(${session} AS BLOB), x'00') > 0 OR ${session} GLOB '*[^ -~]*'
  OR (${ws} IS NOT NULL AND (typeof(${ws}) <> 'text' OR instr(CAST(${ws} AS BLOB), x'00') > 0
    OR ${ws} GLOB '*[^ -~]*')))`;
const fields = (session: string, ws: string) => `CASE WHEN ${odd(session, ws)} THEN 2 WHEN ${ws} IS NULL THEN 1 ELSE 0 END,
  CASE WHEN ${odd(session, ws)} OR ${ws} IS NULL THEN '' ELSE ${ws} END`;
const conflict = `ON CONFLICT(session) DO UPDATE SET scope=excluded.scope, ws=excluded.ws
  WHERE scope IS NOT excluded.scope OR ws IS NOT excluded.ws`;
const put = (session: string) => `INSERT INTO workspace_up_sessions(session,scope,ws)
  SELECT x.session, ${fields("x.session", "s.ws")} FROM (SELECT ${session} AS session) x
  LEFT JOIN sessions s ON s.key=x.session
  WHERE EXISTS (SELECT 1 FROM session_up_job_rows u WHERE u.session=x.session) ${conflict};`;
const refreshStaged = `DELETE FROM workspace_up_sessions WHERE session IN (SELECT session FROM workspace_up_session_replaced)
    AND NOT EXISTS (SELECT 1 FROM session_up_job_rows u WHERE u.session=workspace_up_sessions.session);
  INSERT INTO workspace_up_sessions(session,scope,ws)
    SELECT r.session, ${fields("r.session", "s.ws")} FROM workspace_up_session_replaced r
    LEFT JOIN sessions s ON s.key=r.session
    WHERE EXISTS (SELECT 1 FROM session_up_job_rows u WHERE u.session=r.session) ${conflict};`;
const displaced = `SELECT s.key FROM sessions s WHERE (s.key=NEW.key OR s.token=NEW.token OR s.rowid=NEW.rowid)
  AND EXISTS (SELECT 1 FROM workspace_up_sessions p WHERE p.session=s.key)`;
const clearStaged = "DELETE FROM workspace_up_session_replaced WHERE session IS NOT NULL;";

/// Candidate jobs for one workspace; unusual identities remain for the reader's JavaScript visibility check.
export const WORKSPACE_UP_JOBS = `WITH wanted AS (
  SELECT session FROM workspace_up_sessions INDEXED BY workspace_up_sessions_scope WHERE scope=0 AND ws=?1
  UNION ALL SELECT session FROM workspace_up_sessions INDEXED BY workspace_up_sessions_scope WHERE scope=1 AND ws='' AND ?2
  UNION ALL SELECT session FROM workspace_up_sessions INDEXED BY workspace_up_sessions_scope WHERE scope=2 AND ws=''
) SELECT j.* FROM wanted w CROSS JOIN session_up_job_rows u ON u.session=w.session
  CROSS JOIN jobs j ON j.rowid=u.job_rowid
  ORDER BY j.started_at DESC, (j.state <> 'running'), j.port, j.rowid`;

/// Install writers without scanning the old jobs. An incomplete index must never be used to answer a read.
export function installWorkspaceUpJobs(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='workspace_up_meta'").get() !== undefined;
  if (installed()) { workspaceUpJobsReady(db); return; }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) {
      db.exec(`
      CREATE TABLE workspace_up_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL,phase INTEGER NOT NULL,
        last_port,last_rowid INTEGER,running_end INTEGER,guard_end INTEGER,guard_last INTEGER,port_batches INTEGER NOT NULL,
        ready INTEGER NOT NULL) WITHOUT ROWID;
      INSERT INTO workspace_up_meta SELECT 1,${VERSION},0,NULL,NULL,
        (SELECT rowid FROM jobs INDEXED BY jobs_state WHERE state='running' ORDER BY rowid DESC LIMIT 1),
        (SELECT rowid FROM jobs INDEXED BY jobs_state WHERE state='exited' ORDER BY rowid DESC LIMIT 1),NULL,0,
        (SELECT fresh FROM session_up_job_meta WHERE id=1)=1 AND NOT EXISTS (SELECT 1 FROM session_up_job_rows LIMIT 1);
      CREATE TABLE workspace_up_sessions(session TEXT PRIMARY KEY,scope INTEGER NOT NULL,ws TEXT NOT NULL) WITHOUT ROWID;
      CREATE INDEX workspace_up_sessions_scope ON workspace_up_sessions(scope,ws,session);
      CREATE TABLE workspace_up_session_replaced(session TEXT PRIMARY KEY) WITHOUT ROWID;

      CREATE TRIGGER workspace_up_row_add AFTER INSERT ON session_up_job_rows
      WHEN NOT EXISTS (SELECT 1 FROM workspace_up_sessions WHERE session=NEW.session)
      BEGIN ${put("NEW.session")} END;
      CREATE TRIGGER workspace_up_row_drop AFTER DELETE ON session_up_job_rows
      WHEN NOT EXISTS (SELECT 1 FROM session_up_job_rows WHERE session=OLD.session)
      BEGIN DELETE FROM workspace_up_sessions WHERE session=OLD.session; END;
      CREATE TRIGGER workspace_up_before_session_add BEFORE INSERT ON sessions
      WHEN EXISTS (SELECT 1 FROM workspace_up_session_replaced) OR EXISTS (${displaced})
      BEGIN ${clearStaged} INSERT OR IGNORE INTO workspace_up_session_replaced ${displaced}; END;
      CREATE TRIGGER workspace_up_after_session_add AFTER INSERT ON sessions
      BEGIN ${refreshStaged} ${put("NEW.key")} ${clearStaged} END;
      -- A workspace-only change cannot displace another session; the after trigger can refresh it directly.
      CREATE TRIGGER workspace_up_before_session_change BEFORE UPDATE ON sessions
      WHEN OLD.rowid IS NOT NEW.rowid OR OLD.key IS NOT NEW.key OR OLD.token IS NOT NEW.token
      BEGIN ${clearStaged}
        INSERT OR IGNORE INTO workspace_up_session_replaced SELECT OLD.key
          WHERE EXISTS (SELECT 1 FROM workspace_up_sessions WHERE session=OLD.key);
        INSERT OR IGNORE INTO workspace_up_session_replaced ${displaced};
      END;
      CREATE TRIGGER workspace_up_after_session_change AFTER UPDATE ON sessions
      WHEN OLD.rowid IS NOT NEW.rowid OR OLD.key IS NOT NEW.key OR OLD.token IS NOT NEW.token OR OLD.ws IS NOT NEW.ws
      BEGIN ${refreshStaged} ${put("NEW.key")} ${clearStaged} END;
      CREATE TRIGGER workspace_up_after_session_drop AFTER DELETE ON sessions
      WHEN EXISTS (SELECT 1 FROM workspace_up_sessions WHERE session=OLD.key)
      BEGIN ${put("OLD.key")} END;

      `);
      // During the copy an up job can move behind the cursor without changing whether it is up. Once the copy is
      // complete, the regular writers already follow every job, so this trigger has no remaining work to do.
      if (!workspaceUpJobsReady(db)) db.exec(`CREATE TRIGGER workspace_up_copy_moved AFTER UPDATE OF state,port ON jobs
        WHEN ${up("NEW")}
        BEGIN INSERT INTO session_up_job_rows(session,job_rowid)
          SELECT NEW.session_key,NEW.rowid WHERE NOT EXISTS
            (SELECT 1 FROM session_up_job_rows WHERE session=NEW.session_key AND job_rowid=NEW.rowid); END;`);
    } else workspaceUpJobsReady(db);
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function workspaceUpJobsReady(db: DatabaseSync): boolean {
  const meta = db.prepare("SELECT version,ready FROM workspace_up_meta WHERE id=1").get() as { version: number; ready: number } | undefined;
  if (!meta || meta.version !== VERSION) throw new Error(`workspace up jobs index version ${meta?.version ?? "missing"} is incompatible with ${VERSION}`);
  return meta.ready === 1;
}

// The equal-port seek must include rowid: a tuple comparison here starts at the port and rereads all its earlier jobs.
export const WORKSPACE_UP_SAME_PORT = `SELECT j.rowid,j.port FROM jobs j INDEXED BY jobs_up
  WHERE j.state=? AND j.port=(SELECT last_port FROM workspace_up_meta WHERE id=1)
    AND j.rowid>(SELECT last_rowid FROM workspace_up_meta WHERE id=1) ORDER BY j.rowid LIMIT ?`;
export const WORKSPACE_UP_LATER_PORTS = `SELECT j.rowid,j.port FROM jobs j INDEXED BY jobs_up
  WHERE j.state=? AND j.port>(SELECT last_port FROM workspace_up_meta WHERE id=1) ORDER BY j.port,j.rowid LIMIT ?`;

// Use the state/rowid index to reach a fixed end even if jobs are added while the copy runs. Keep the cursor in SQLite
// so neither 64-bit rowids nor unusual port values pass through JavaScript numbers or strings.
export const WORKSPACE_UP_OLD_ROWIDS = (cursor: "last_rowid" | "guard_last", end: "running_end" | "guard_end", first: boolean) =>
  `SELECT j.rowid,NULL FROM jobs j INDEXED BY jobs_state WHERE j.state=?
    AND j.rowid<=(SELECT ${end} FROM workspace_up_meta WHERE id=1)
    ${first ? "" : `AND j.rowid>(SELECT ${cursor} FROM workspace_up_meta WHERE id=1)`} ORDER BY j.rowid LIMIT ?`;

/// Copy old up jobs in batches. Exited services normally use jobs_up; every eighth batch yields to a state/rowid scan
/// so a stream of new services cannot keep the copy open. That second scan may also read old inactive jobs.
export function workspaceUpJobsStep(db: DatabaseSync, limit = 256): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("workspace up job batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    if (workspaceUpJobsReady(db)) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const cursor = db.prepare(`SELECT phase,port_batches,last_rowid IS NULL AS first,guard_last IS NULL AS guard_first
      FROM workspace_up_meta WHERE id=1`).get() as { phase: number; port_batches: number; first: number; guard_first: number };
    const guard = cursor.phase === 1 && cursor.port_batches >= PORT_BATCHES_PER_GUARD;
    db.exec("CREATE TEMP TABLE IF NOT EXISTS workspace_up_batch(job_rowid INTEGER PRIMARY KEY,port); DELETE FROM workspace_up_batch;");
    if (cursor.phase === 0) {
      db.prepare(`INSERT INTO workspace_up_batch ${WORKSPACE_UP_OLD_ROWIDS("last_rowid", "running_end", !!cursor.first)}`)
        .run("running", limit);
    } else if (guard) {
      db.prepare(`INSERT INTO workspace_up_batch ${WORKSPACE_UP_OLD_ROWIDS("guard_last", "guard_end", !!cursor.guard_first)}`)
        .run("exited", limit);
    } else if (cursor.first) {
      db.prepare(`INSERT INTO workspace_up_batch SELECT j.rowid,j.port FROM jobs j INDEXED BY jobs_up
        WHERE j.state='exited' AND j.port IS NOT NULL ORDER BY j.port,j.rowid LIMIT ?`).run(limit);
    } else {
      db.prepare(`INSERT INTO workspace_up_batch ${WORKSPACE_UP_SAME_PORT}`).run("exited",limit);
      const same = (db.prepare("SELECT COUNT(*) AS n FROM workspace_up_batch").get() as { n: number }).n;
      if (same < limit) db.prepare(`INSERT INTO workspace_up_batch ${WORKSPACE_UP_LATER_PORTS}`).run("exited",limit-same);
    }
    const count = (db.prepare("SELECT COUNT(*) AS n FROM workspace_up_batch").get() as { n: number }).n;
    db.exec(`INSERT INTO session_up_job_rows(session,job_rowid)
      SELECT j.session_key,j.rowid FROM workspace_up_batch b CROSS JOIN jobs j ON j.rowid=b.job_rowid
      WHERE ${up("j")} AND NOT EXISTS (SELECT 1 FROM session_up_job_rows u WHERE u.session=j.session_key AND u.job_rowid=j.rowid);
      INSERT INTO workspace_up_sessions(session,scope,ws)
      SELECT DISTINCT j.session_key, ${fields("j.session_key", "s.ws")} FROM workspace_up_batch b
        CROSS JOIN jobs j ON j.rowid=b.job_rowid LEFT JOIN sessions s ON s.key=j.session_key
      WHERE ${up("j")} ${conflict};`);
    const done = cursor.phase === 1 && count < limit;
    if (count < limit) db.prepare("UPDATE workspace_up_meta SET phase=?,last_port=NULL,last_rowid=NULL,ready=? WHERE id=1")
      .run(cursor.phase + 1, done ? 1 : 0);
    else if (cursor.phase === 0) db.exec(`UPDATE workspace_up_meta SET
      last_rowid=(SELECT MAX(job_rowid) FROM workspace_up_batch) WHERE id=1`);
    else if (guard) db.exec(`UPDATE workspace_up_meta SET port_batches=0,
      guard_last=(SELECT MAX(job_rowid) FROM workspace_up_batch) WHERE id=1`);
    else db.exec(`UPDATE workspace_up_meta SET port_batches=port_batches+1,
      last_port=(SELECT port FROM workspace_up_batch ORDER BY port DESC,job_rowid DESC LIMIT 1),
      last_rowid=(SELECT job_rowid FROM workspace_up_batch ORDER BY port DESC,job_rowid DESC LIMIT 1) WHERE id=1`);
    if (done) db.exec("DROP TRIGGER workspace_up_copy_moved");
    db.exec("COMMIT");
    return { done, visited: count };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
