// The session list's candidates by workspace and archive state. Old rows are copied in bounded batches; the triggers
// keep the index current even while an older station writes to the same database.
import type { DatabaseSync } from "node:sqlite";

const VERSION = 1;
export const SESSION_LIST_PENDING = "session list index is still being prepared";
export const SESSION_LIST_FIRST = `SELECT CAST(rowid AS TEXT) AS position, key FROM sessions
  WHERE rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?`;
export const SESSION_LIST_NEXT = `SELECT CAST(rowid AS TEXT) AS position, key FROM sessions
  WHERE rowid > CAST(? AS INTEGER) AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?`;

// The scope contains one workspace, and at most one more for the home workspace's pre-workspace sessions. The index
// first seeks both the workspace and archive state; a requested connect is also part of that seek.
const scoped = (connect: boolean) => `WITH scope(kind, ws) AS (SELECT 1, ?1 UNION ALL SELECT 0, '' WHERE ?2)
  SELECT s.* FROM scope w CROSS JOIN session_list_rows i
  CROSS JOIN sessions s ON s.key = i.session
  WHERE i.kind = w.kind AND i.ws = w.ws AND i.archived = ?3${connect ? " AND i.connect = ?4" : ""}
  ORDER BY s.last_active_at DESC, s.rowid ASC`;
export const SESSION_LIST_SCOPE = scoped(false);
export const SESSION_LIST_SCOPE_CONNECT = scoped(true);
export const SESSION_LIST_CONNECT = `SELECT s.* FROM session_list_rows i INDEXED BY session_list_connect
  CROSS JOIN sessions s ON s.key = i.session WHERE i.archived = ?1 AND i.connect = ?2
  ORDER BY s.last_active_at DESC, s.rowid ASC`;

const kind = (row: string) => `CASE WHEN ${row}.ws IS NULL THEN 0 ELSE 1 END`;
const scope = (row: string) => `COALESCE(${row}.ws, '')`;
const archive = (row: string) => `(${row}.archived_at IS NOT NULL)`;
const values = (row: string) => `${row}.key, ${kind(row)}, ${scope(row)}, ${archive(row)}, ${row}.connect`;
const displaced = (key: string, token: string, rowid: string) => `SELECT ${values("s")} FROM sessions s WHERE s.key = ${key}
  UNION SELECT ${values("s")} FROM sessions s WHERE s.token = ${token}
  UNION SELECT ${values("s")} FROM sessions s WHERE s.rowid = ${rowid}`;
export const SESSION_LIST_DISPLACED = displaced("?1", "?2", "?3");
const stage = (old: boolean) => `DELETE FROM session_list_replaced;
  INSERT INTO session_list_replaced (session, kind, ws, archived, connect) ${displaced("NEW.key", "NEW.token", "NEW.rowid")}
    ${old ? `UNION SELECT ${values("OLD")}` : ""};`;
const matches = (index: string, row: string) => `${index}.kind = ${kind(row)} AND ${index}.ws = ${scope(row)}
  AND ${index}.archived = ${archive(row)} AND ${index}.connect = ${row}.connect AND ${index}.session = ${row}.key`;
// An outer OR REPLACE also changes conflict policies in a trigger; skip existing rows rather than INSERT OR IGNORE.
const see = (key: string) => `INSERT INTO session_list_rows (session, kind, ws, archived, connect)
  SELECT ${values("s")} FROM sessions s WHERE s.key = ${key}
    AND NOT EXISTS (SELECT 1 FROM session_list_rows i WHERE ${matches("i", "s")});`;
const reconcile = `DELETE FROM session_list_rows WHERE (kind, ws, archived, connect, session) IN
    (SELECT kind, ws, archived, connect, session FROM session_list_replaced)
  AND NOT EXISTS (SELECT 1 FROM sessions s WHERE s.key = session_list_rows.session AND ${matches("session_list_rows", "s")});
  INSERT INTO session_list_rows (session, kind, ws, archived, connect)
    SELECT ${values("s")} FROM session_list_replaced r
    CROSS JOIN sessions s ON s.key = r.session
    WHERE NOT EXISTS (SELECT 1 FROM session_list_rows i WHERE ${matches("i", "s")});
  DELETE FROM session_list_replaced;`;

export function installSessionListIndex(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'session_list_meta'").get() !== undefined;
  if (installed()) { sessionListReady(db); return; }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE session_list_meta (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL, last_rowid INTEGER,
        end_rowid INTEGER, complete INTEGER NOT NULL) WITHOUT ROWID;
      INSERT INTO session_list_meta (id, version, last_rowid, end_rowid, complete)
        SELECT 1, ${VERSION}, NULL, (SELECT rowid FROM sessions ORDER BY rowid DESC LIMIT 1),
          NOT EXISTS (SELECT 1 FROM sessions LIMIT 1);
      CREATE TABLE session_list_rows (kind INTEGER NOT NULL, ws TEXT NOT NULL, archived INTEGER NOT NULL,
        connect TEXT NOT NULL, session TEXT NOT NULL, PRIMARY KEY (kind, ws, archived, connect, session)) WITHOUT ROWID;
      CREATE INDEX session_list_connect ON session_list_rows (archived, connect, kind, ws, session);
      CREATE TABLE session_list_replaced (session TEXT PRIMARY KEY, kind INTEGER NOT NULL, ws TEXT NOT NULL,
        archived INTEGER NOT NULL, connect TEXT NOT NULL) WITHOUT ROWID;
      CREATE TRIGGER session_list_before_add BEFORE INSERT ON sessions BEGIN ${stage(false)} END;
      CREATE TRIGGER session_list_add AFTER INSERT ON sessions BEGIN ${reconcile} ${see("NEW.key")} END;
      CREATE TRIGGER session_list_before_change BEFORE UPDATE ON sessions
        WHEN OLD.key IS NOT NEW.key OR OLD.token IS NOT NEW.token OR OLD.rowid IS NOT NEW.rowid
          OR OLD.connect IS NOT NEW.connect OR OLD.ws IS NOT NEW.ws
          OR (OLD.archived_at IS NULL) IS NOT (NEW.archived_at IS NULL) BEGIN ${stage(true)} END;
      CREATE TRIGGER session_list_change AFTER UPDATE ON sessions
        WHEN OLD.key IS NOT NEW.key OR OLD.token IS NOT NEW.token OR OLD.rowid IS NOT NEW.rowid
          OR OLD.connect IS NOT NEW.connect OR OLD.ws IS NOT NEW.ws
          OR (OLD.archived_at IS NULL) IS NOT (NEW.archived_at IS NULL) BEGIN ${reconcile} ${see("NEW.key")} END;
      CREATE TRIGGER session_list_drop AFTER DELETE ON sessions BEGIN
        DELETE FROM session_list_rows WHERE ${matches("session_list_rows", "OLD")};
      END;
    `);
    else sessionListReady(db);
    db.exec("COMMIT");
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

function checkVersion(version: number): void {
  if (version !== VERSION) throw new Error(`session list index version ${version} is incompatible with ${VERSION}`);
}

export function sessionListReady(db: DatabaseSync): boolean {
  const meta = db.prepare("SELECT version, complete FROM session_list_meta WHERE id = 1").get() as { version: number; complete: number } | undefined;
  if (meta === undefined) throw new Error("session list index version marker is missing");
  checkVersion(meta.version);
  return meta.complete === 1;
}

export function sessionListStep(db: DatabaseSync, limit = 256): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("session list batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const meta = db.prepare(`SELECT version, CAST(last_rowid AS TEXT) AS last_rowid, CAST(end_rowid AS TEXT) AS end_rowid, complete
      FROM session_list_meta WHERE id = 1`).get() as { version: number; last_rowid: string | null; end_rowid: string | null; complete: number } | undefined;
    if (meta === undefined) throw new Error("session list index version marker is missing");
    checkVersion(meta.version);
    if (meta.complete === 1) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const rows = (meta.last_rowid === null
      ? db.prepare(SESSION_LIST_FIRST).all(meta.end_rowid, limit)
      : db.prepare(SESSION_LIST_NEXT).all(meta.last_rowid, meta.end_rowid, limit)) as { position: string; key: string }[];
    const put = db.prepare(see("?"));
    for (const row of rows) put.run(row.key);
    const done = rows.length < limit;
    db.prepare("UPDATE session_list_meta SET last_rowid = CAST(? AS INTEGER), complete = ? WHERE id = 1")
      .run(rows.at(-1)?.position ?? meta.last_rowid, done ? 1 : 0);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
