import type { DatabaseSync } from "node:sqlite";

// WIP: requested sessions only. The static builder and read below are not yet kept current by source writes and must
// not be used by the station until the write, replacement, deletion and interleaving paths are implemented.
const VERSION = 1;
export const LATEST_THREAD_INDEXED = `SELECT t.*,m.connect FROM latest_thread_rows r
  CROSS JOIN thread_sessions m ON m.session=r.session AND m.thread=r.thread
  CROSS JOIN threads t ON t.id=r.thread WHERE r.session=?1
  ORDER BY r.has_last DESC,r.last_delivery DESC,r.joined_at DESC,r.member_rowid DESC LIMIT 1`;

export function installLatestThreadIndex(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='latest_thread_meta'").get() !== undefined;
  if (installed()) { checkLatestThreadIndex(db); return; }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`CREATE TABLE latest_thread_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL) WITHOUT ROWID;
      INSERT INTO latest_thread_meta VALUES(1,${VERSION});
      CREATE TABLE latest_thread_scopes(session TEXT PRIMARY KEY,scan_after INTEGER,scan_end INTEGER,
        complete INTEGER NOT NULL DEFAULT 0) WITHOUT ROWID;
      CREATE TABLE latest_thread_rows(session TEXT NOT NULL,has_last INTEGER NOT NULL,last_delivery INTEGER NOT NULL,
        joined_at NOT NULL,member_rowid INTEGER NOT NULL,thread INTEGER NOT NULL,
        PRIMARY KEY(session,has_last DESC,last_delivery DESC,joined_at DESC,member_rowid DESC)) WITHOUT ROWID;`);
    else checkLatestThreadIndex(db);
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function checkLatestThreadIndex(db: DatabaseSync): void {
  const row = db.prepare("SELECT version FROM latest_thread_meta WHERE id=1").get() as { version: number } | undefined;
  if (row?.version !== VERSION) throw new Error(`latest thread index version ${row?.version ?? "missing"} is incompatible with ${VERSION}`);
}

export function latestThreadReady(db: DatabaseSync, session: string): boolean {
  checkLatestThreadIndex(db);
  return (db.prepare("SELECT complete FROM latest_thread_scopes WHERE session=?").get(session) as { complete: number } | undefined)?.complete === 1;
}

/// Read readiness and the candidate from one database snapshot.
export function indexedLatestThread(db: DatabaseSync, session: string): Record<string, unknown> | null {
  db.exec("SAVEPOINT latest_thread_read");
  try {
    if (!latestThreadReady(db, session)) throw new Error("latest thread is still being prepared");
    return db.prepare(LATEST_THREAD_INDEXED).get(session) ?? null;
  } finally { db.exec("RELEASE latest_thread_read"); }
}

const candidate = `SELECT m.session,m.thread,m.rowid AS member_rowid,m.joined_at,
  (SELECT d.rowid FROM deliveries d INDEXED BY deliveries_session WHERE d.session=m.session AND d.thread=m.thread
    ORDER BY d.rowid DESC LIMIT 1) AS last_delivery
  FROM thread_sessions m JOIN threads t ON t.id=m.thread WHERE m.session=?1 AND m.rowid=?2`;
const addCandidate = `INSERT INTO latest_thread_rows(session,has_last,last_delivery,joined_at,member_rowid,thread)
  SELECT c.session,c.last_delivery IS NOT NULL,COALESCE(c.last_delivery,0),c.joined_at,c.member_rowid,c.thread
  FROM (${candidate}) c WHERE NOT EXISTS (SELECT 1 FROM latest_thread_rows r WHERE r.session=c.session
    AND r.has_last=(c.last_delivery IS NOT NULL) AND r.last_delivery=COALESCE(c.last_delivery,0)
    AND r.joined_at IS c.joined_at AND r.member_rowid=c.member_rowid)`;

/// Begin and advance an old session's walk in transactions bounded by `limit` source memberships.
export function prepareLatestThreadStep(db: DatabaseSync, session: string, limit = 64): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 128) throw new RangeError("latest thread batch must be between 1 and 128");
  db.exec("BEGIN IMMEDIATE");
  try {
    checkLatestThreadIndex(db);
    db.prepare(`INSERT INTO latest_thread_scopes(session,scan_end)
      SELECT ?1,(SELECT rowid FROM thread_sessions INDEXED BY thread_sessions_session WHERE session=?1 ORDER BY rowid DESC LIMIT 1)
      WHERE NOT EXISTS (SELECT 1 FROM latest_thread_scopes WHERE session=?1)`).run(session);
    const state = db.prepare("SELECT scan_after,scan_end,complete FROM latest_thread_scopes WHERE session=?");
    state.setReadBigInts(true);
    const scope = state.get(session) as { scan_after: bigint | null; scan_end: bigint | null; complete: bigint };
    if (scope.complete === 1n) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const scan = db.prepare(scope.scan_after === null
      ? "SELECT rowid FROM thread_sessions INDEXED BY thread_sessions_session WHERE session=?1 AND rowid<=?2 ORDER BY rowid LIMIT ?3"
      : "SELECT rowid FROM thread_sessions INDEXED BY thread_sessions_session WHERE session=?1 AND rowid>?2 AND rowid<=?3 ORDER BY rowid LIMIT ?4");
    scan.setReadBigInts(true);
    const rows = (scope.scan_after === null ? scan.all(session, scope.scan_end, limit)
      : scan.all(session, scope.scan_after, scope.scan_end, limit)) as { rowid: bigint }[];
    const put = db.prepare(addCandidate);
    for (const row of rows) put.run(session, row.rowid);
    const done = rows.length < limit;
    db.prepare("UPDATE latest_thread_scopes SET scan_after=?,complete=? WHERE session=?")
      .run(rows.at(-1)?.rowid ?? scope.scan_after, done ? 1 : 0, session);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
