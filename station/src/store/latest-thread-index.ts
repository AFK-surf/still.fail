import type { DatabaseSync } from "node:sqlite";

// WIP: requested sessions only. This is not connected to station reads while its write and preparation paths are
// being verified, including high-fanout thread changes, old writers and concurrent snapshots.
const VERSION = 1;
export const LATEST_THREAD_INDEXED = `SELECT t.*,m.connect FROM latest_thread_rows r
  CROSS JOIN thread_sessions m ON m.session=r.session AND m.thread=r.thread
  CROSS JOIN threads t ON t.id=r.thread WHERE r.session=?1
  ORDER BY r.has_last DESC,r.last_delivery DESC,r.joined_at DESC,r.member_rowid DESC LIMIT 1`;

const lastDelivery = (session: string, thread: string, extra = "") => `(SELECT d.rowid FROM deliveries d INDEXED BY deliveries_session
  WHERE d.session=${session} AND d.thread=${thread} ${extra} ORDER BY d.rowid DESC LIMIT 1)`;
const priorDelivery = lastDelivery("NEW.session", "NEW.thread", "AND d.rowid<>NEW.rowid");
const changed = "EXISTS (SELECT 1 FROM latest_thread_changed LIMIT 1)";
const stage = (keys: string) => `DELETE FROM latest_thread_changed;
  INSERT INTO latest_thread_changed(session,thread,old_valid,old_has,old_last,old_joined,old_member)
    SELECT k.session,k.thread,m.rowid IS NOT NULL AND t.id IS NOT NULL,
      ${lastDelivery("k.session", "k.thread")} IS NOT NULL,COALESCE(${lastDelivery("k.session", "k.thread")},0),m.joined_at,m.rowid
    FROM (${keys}) k LEFT JOIN thread_sessions m ON m.session=k.session AND m.thread=k.thread
      LEFT JOIN threads t ON t.id=k.thread
    WHERE k.session IS NOT NULL AND k.thread IS NOT NULL
      AND EXISTS (SELECT 1 FROM latest_thread_scopes s WHERE s.session=k.session);`;
// The changed set holds the old ordered keys before a source write. An ignored insert may leave it behind, but did
// not change the source or the order; the next staged write clears it before collecting its own affected pairs.
const reconcile = `DELETE FROM latest_thread_rows WHERE (session,has_last,last_delivery,joined_at,member_rowid) IN
    (SELECT session,old_has,old_last,old_joined,old_member FROM latest_thread_changed WHERE old_valid=1);
  DELETE FROM latest_thread_members WHERE (thread,session) IN
    (SELECT x.thread,x.session FROM latest_thread_changed x WHERE NOT EXISTS
      (SELECT 1 FROM thread_sessions m WHERE m.thread=x.thread AND m.session=x.session));
  INSERT INTO latest_thread_members(thread,session)
    SELECT m.thread,m.session FROM latest_thread_changed x
      CROSS JOIN thread_sessions m ON m.thread=x.thread AND m.session=x.session
    WHERE NOT EXISTS (SELECT 1 FROM latest_thread_members r WHERE r.thread=m.thread AND r.session=m.session);
  INSERT INTO latest_thread_rows(session,has_last,last_delivery,joined_at,member_rowid,thread)
    SELECT m.session,d.rowid IS NOT NULL,COALESCE(d.rowid,0),m.joined_at,m.rowid,m.thread
    FROM latest_thread_changed x CROSS JOIN thread_sessions m ON m.session=x.session AND m.thread=x.thread
      CROSS JOIN threads t ON t.id=m.thread
      LEFT JOIN deliveries d ON d.rowid=${lastDelivery("m.session", "m.thread")}
    WHERE NOT EXISTS (SELECT 1 FROM latest_thread_rows r WHERE r.session=m.session AND r.has_last=(d.rowid IS NOT NULL)
      AND r.last_delivery=COALESCE(d.rowid,0) AND r.joined_at IS m.joined_at AND r.member_rowid=m.rowid);
  DELETE FROM latest_thread_changed;`;
const deliveryKeys = (update: boolean) => `SELECT NEW.session AS session,NEW.thread AS thread
  UNION SELECT d.session,d.thread FROM deliveries d WHERE d.rowid=NEW.rowid
  UNION SELECT d.session,d.thread FROM deliveries d WHERE d.thread=NEW.thread AND d.n=NEW.n AND d.session=NEW.session
  ${update ? "UNION SELECT OLD.session,OLD.thread" : ""}`;
const memberKeys = (update: boolean) => `SELECT NEW.session AS session,NEW.thread AS thread
  UNION SELECT m.session,m.thread FROM thread_sessions m WHERE m.rowid=NEW.rowid
  UNION SELECT m.session,m.thread FROM thread_sessions m WHERE m.thread=NEW.thread AND m.session=NEW.session
  ${update ? "UNION SELECT OLD.session,OLD.thread" : ""}`;
const threadKeys = (ids: string) => `SELECT m.session,m.thread FROM latest_thread_members m WHERE m.thread IN (${ids})`;
const displacedThread = `(SELECT id FROM threads WHERE surface=NEW.surface AND channel=NEW.channel AND thread_ts=NEW.thread_ts)`;
const deliveryConflict = `EXISTS (SELECT 1 FROM deliveries WHERE rowid=NEW.rowid)
  OR EXISTS (SELECT 1 FROM deliveries WHERE thread=NEW.thread AND n=NEW.n AND session=NEW.session)`;
const memberConflict = `EXISTS (SELECT 1 FROM thread_sessions WHERE rowid=NEW.rowid)
  OR EXISTS (SELECT 1 FROM thread_sessions WHERE thread=NEW.thread AND session=NEW.session)`;

// A normal new delivery needs no staging or second identity index. Its previous last row is the last row other than
// NEW, sought in the existing (session,thread) index; removing and reinserting the ordered row touches one tree.
const fastDelivery = `DELETE FROM latest_thread_rows WHERE session=NEW.session AND thread=NEW.thread
    AND has_last=(${priorDelivery} IS NOT NULL) AND last_delivery=COALESCE(${priorDelivery},0)
    AND joined_at IS (SELECT joined_at FROM thread_sessions WHERE session=NEW.session AND thread=NEW.thread)
    AND member_rowid=(SELECT rowid FROM thread_sessions WHERE session=NEW.session AND thread=NEW.thread);
  INSERT INTO latest_thread_rows(session,has_last,last_delivery,joined_at,member_rowid,thread)
    SELECT m.session,1,NEW.rowid,m.joined_at,m.rowid,m.thread FROM thread_sessions m
    WHERE m.session=NEW.session AND m.thread=NEW.thread AND NOT EXISTS
      (SELECT 1 FROM latest_thread_rows r WHERE r.session=m.session AND r.has_last=1 AND r.last_delivery=NEW.rowid
        AND r.joined_at IS m.joined_at AND r.member_rowid=m.rowid);`;
const fastMember = `INSERT INTO latest_thread_members(thread,session)
    SELECT m.thread,m.session FROM thread_sessions m WHERE m.session=NEW.session AND m.thread=NEW.thread
      AND EXISTS (SELECT 1 FROM latest_thread_scopes s WHERE s.session=m.session)
      AND NOT EXISTS (SELECT 1 FROM latest_thread_members r WHERE r.thread=m.thread AND r.session=m.session);
  INSERT INTO latest_thread_rows(session,has_last,last_delivery,joined_at,member_rowid,thread)
    SELECT m.session,d.rowid IS NOT NULL,COALESCE(d.rowid,0),m.joined_at,m.rowid,m.thread
    FROM thread_sessions m CROSS JOIN threads t ON t.id=m.thread
      LEFT JOIN deliveries d ON d.rowid=${lastDelivery("m.session", "m.thread")}
    WHERE m.session=NEW.session AND m.thread=NEW.thread AND EXISTS
      (SELECT 1 FROM latest_thread_scopes s WHERE s.session=m.session) AND NOT EXISTS
      (SELECT 1 FROM latest_thread_rows r WHERE r.session=m.session AND r.has_last=(d.rowid IS NOT NULL)
        AND r.last_delivery=COALESCE(d.rowid,0) AND r.joined_at IS m.joined_at AND r.member_rowid=m.rowid);`;

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
        PRIMARY KEY(session,has_last DESC,last_delivery DESC,joined_at DESC,member_rowid DESC)) WITHOUT ROWID;
      -- Only tracked memberships, including those whose thread is temporarily missing. This bounds thread changes
      -- by the requested sessions without adding another index to every delivery.
      CREATE TABLE latest_thread_members(thread INTEGER NOT NULL,session TEXT NOT NULL,
        PRIMARY KEY(thread,session)) WITHOUT ROWID;
      CREATE TABLE latest_thread_changed(session TEXT NOT NULL,thread INTEGER NOT NULL,old_valid INTEGER NOT NULL,
        old_has INTEGER NOT NULL,old_last INTEGER NOT NULL,old_joined,old_member INTEGER,
        PRIMARY KEY(session,thread)) WITHOUT ROWID;

      CREATE TRIGGER latest_delivery_before_add BEFORE INSERT ON deliveries
        WHEN ${changed} OR ${deliveryConflict} BEGIN ${stage(deliveryKeys(false))} END;
      CREATE TRIGGER latest_delivery_add AFTER INSERT ON deliveries WHEN ${changed} BEGIN ${reconcile} END;
      CREATE TRIGGER latest_delivery_fast_add AFTER INSERT ON deliveries
        WHEN EXISTS (SELECT 1 FROM latest_thread_scopes WHERE session=NEW.session)
          AND EXISTS (SELECT 1 FROM thread_sessions m JOIN threads t ON t.id=m.thread
            WHERE m.session=NEW.session AND m.thread=NEW.thread)
          AND (${priorDelivery} IS NULL OR NEW.rowid>${priorDelivery}) BEGIN ${fastDelivery} END;
      CREATE TRIGGER latest_delivery_before_change BEFORE UPDATE OF rowid,_rowid_,oid,thread,n,session ON deliveries
        WHEN OLD.rowid IS NOT NEW.rowid OR OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n OR OLD.session IS NOT NEW.session
        BEGIN ${stage(deliveryKeys(true))} END;
      CREATE TRIGGER latest_delivery_change AFTER UPDATE OF rowid,_rowid_,oid,thread,n,session ON deliveries
        WHEN ${changed} BEGIN ${reconcile} END;
      CREATE TRIGGER latest_delivery_before_drop BEFORE DELETE ON deliveries
        BEGIN ${stage("SELECT OLD.session AS session,OLD.thread AS thread")} END;
      CREATE TRIGGER latest_delivery_drop AFTER DELETE ON deliveries WHEN ${changed} BEGIN ${reconcile} END;

      CREATE TRIGGER latest_member_before_add BEFORE INSERT ON thread_sessions
        WHEN ${changed} OR ${memberConflict} BEGIN ${stage(memberKeys(false))} END;
      CREATE TRIGGER latest_member_add AFTER INSERT ON thread_sessions WHEN ${changed} BEGIN ${reconcile} END;
      CREATE TRIGGER latest_member_fast_add AFTER INSERT ON thread_sessions BEGIN ${fastMember} END;
      CREATE TRIGGER latest_member_before_change BEFORE UPDATE OF rowid,_rowid_,oid,thread,session,joined_at ON thread_sessions
        WHEN OLD.rowid IS NOT NEW.rowid OR OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session OR OLD.joined_at IS NOT NEW.joined_at
        BEGIN ${stage(memberKeys(true))} END;
      CREATE TRIGGER latest_member_change AFTER UPDATE OF rowid,_rowid_,oid,thread,session,joined_at ON thread_sessions
        WHEN ${changed} BEGIN ${reconcile} END;
      CREATE TRIGGER latest_member_before_drop BEFORE DELETE ON thread_sessions
        BEGIN ${stage("SELECT OLD.session AS session,OLD.thread AS thread")} END;
      CREATE TRIGGER latest_member_drop AFTER DELETE ON thread_sessions WHEN ${changed} BEGIN ${reconcile} END;

      CREATE TRIGGER latest_thread_before_add BEFORE INSERT ON threads
        BEGIN ${stage(threadKeys(`NEW.id,${displacedThread}`))} END;
      CREATE TRIGGER latest_thread_add AFTER INSERT ON threads BEGIN
        INSERT INTO latest_thread_changed(session,thread,old_valid,old_has,old_last,old_joined,old_member)
          SELECT m.session,m.thread,0,0,0,NULL,NULL FROM latest_thread_members m WHERE m.thread=NEW.id
            AND NOT EXISTS (SELECT 1 FROM latest_thread_changed x WHERE x.session=m.session AND x.thread=m.thread);
        ${reconcile}
      END;
      CREATE TRIGGER latest_thread_before_change BEFORE UPDATE OF id,surface,channel,thread_ts ON threads
        WHEN OLD.id IS NOT NEW.id OR OLD.surface IS NOT NEW.surface OR OLD.channel IS NOT NEW.channel OR OLD.thread_ts IS NOT NEW.thread_ts
        BEGIN ${stage(threadKeys(`OLD.id,NEW.id,${displacedThread}`))} END;
      CREATE TRIGGER latest_thread_change AFTER UPDATE OF id,surface,channel,thread_ts ON threads
        WHEN ${changed} BEGIN ${reconcile} END;
      CREATE TRIGGER latest_thread_before_drop BEFORE DELETE ON threads
        BEGIN ${stage(threadKeys("OLD.id"))} END;
      CREATE TRIGGER latest_thread_drop AFTER DELETE ON threads WHEN ${changed} BEGIN ${reconcile} END;
      CREATE TRIGGER latest_thread_session_drop AFTER DELETE ON sessions BEGIN
        DELETE FROM latest_thread_members WHERE (thread,session) IN
          (SELECT thread,session FROM thread_sessions INDEXED BY thread_sessions_session WHERE session=OLD.key);
        DELETE FROM latest_thread_rows WHERE session=OLD.key;
        DELETE FROM latest_thread_changed WHERE session=OLD.key;
        DELETE FROM latest_thread_scopes WHERE session=OLD.key;
      END;`);
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
const addMember = `INSERT INTO latest_thread_members(thread,session)
  SELECT m.thread,m.session FROM thread_sessions m WHERE m.session=?1 AND m.rowid=?2
    AND NOT EXISTS (SELECT 1 FROM latest_thread_members r WHERE r.thread=m.thread AND r.session=m.session)`;

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
    const put = db.prepare(addCandidate), putMember = db.prepare(addMember);
    for (const row of rows) { putMember.run(session, row.rowid); put.run(session, row.rowid); }
    const done = rows.length < limit;
    db.prepare("UPDATE latest_thread_scopes SET scan_after=?,complete=? WHERE session=?")
      .run(rows.at(-1)?.rowid ?? scope.scan_after, done ? 1 : 0, session);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
