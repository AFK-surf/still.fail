// A session's connection bindings. The old table is keyed by connection; this lookup is keyed by session and preserves
// the original row order. Older bindings are copied in bounded batches while the triggers follow both old and new writers.
import type { DatabaseSync } from "node:sqlite";

const VERSION = 1;
export const SESSION_BINDINGS_PENDING = "session binding index is still being prepared";
export const SESSION_BINDINGS_FIRST = `SELECT CAST(rowid AS TEXT) AS position FROM bindings
  WHERE rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?`;
export const SESSION_BINDINGS_NEXT = `SELECT CAST(rowid AS TEXT) AS position FROM bindings
  WHERE rowid > CAST(? AS INTEGER) AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?`;
export const SESSION_BINDINGS_SELECTED = `SELECT i.session, i.connect FROM json_each(?) k
  CROSS JOIN session_binding_rows i WHERE i.session = k.value ORDER BY i.binding_rowid`;
export const SESSION_BINDINGS_DELETE = `DELETE FROM bindings WHERE rowid IN
  (SELECT binding_rowid FROM session_binding_rows WHERE session = ?)`;

// NULL connection keys do not conflict with each other in SQLite. A replacement can still displace one by rowid.
const displaced = (connect: string, rowid: string) => `SELECT b.rowid, b.session_key, b.connect FROM bindings b
  WHERE ${connect} IS NOT NULL AND b.connect = ${connect}
  UNION SELECT b.rowid, b.session_key, b.connect FROM bindings b WHERE b.rowid = ${rowid}`;
export const SESSION_BINDINGS_DISPLACED = displaced("?1", "?2");
const stage = (old: boolean) => `DELETE FROM session_binding_replaced;
  INSERT INTO session_binding_replaced (binding_rowid, session, connect) ${displaced("NEW.connect", "NEW.rowid")}
    ${old ? "UNION SELECT OLD.rowid, OLD.session_key, OLD.connect" : ""};`;
const see = (rowid: string) => `INSERT INTO session_binding_rows (session, binding_rowid, connect)
  SELECT b.session_key, b.rowid, b.connect FROM bindings b WHERE b.rowid = ${rowid}
    AND NOT EXISTS (SELECT 1 FROM session_binding_rows i WHERE i.session = b.session_key AND i.binding_rowid = b.rowid);`;
const reconcile = `DELETE FROM session_binding_rows WHERE (session, binding_rowid) IN
    (SELECT session, binding_rowid FROM session_binding_replaced)
  AND NOT EXISTS (SELECT 1 FROM bindings b WHERE b.rowid = session_binding_rows.binding_rowid
    AND b.session_key = session_binding_rows.session AND b.connect IS session_binding_rows.connect);
  INSERT INTO session_binding_rows (session, binding_rowid, connect)
    SELECT b.session_key, b.rowid, b.connect FROM session_binding_replaced r CROSS JOIN bindings b ON b.rowid = r.binding_rowid
    WHERE NOT EXISTS (SELECT 1 FROM session_binding_rows i WHERE i.session = b.session_key AND i.binding_rowid = b.rowid);
  DELETE FROM session_binding_replaced;`;

export function installSessionBindingsIndex(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'session_binding_meta'").get() !== undefined;
  if (installed()) { sessionBindingsReady(db); return; }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE session_binding_meta (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL, last_rowid INTEGER,
        end_rowid INTEGER, complete INTEGER NOT NULL) WITHOUT ROWID;
      INSERT INTO session_binding_meta (id, version, last_rowid, end_rowid, complete)
        SELECT 1, ${VERSION}, NULL, (SELECT rowid FROM bindings ORDER BY rowid DESC LIMIT 1),
          NOT EXISTS (SELECT 1 FROM bindings LIMIT 1);
      CREATE TABLE session_binding_rows (session TEXT NOT NULL, binding_rowid INTEGER NOT NULL, connect TEXT,
        PRIMARY KEY (session, binding_rowid)) WITHOUT ROWID;
      CREATE TABLE session_binding_replaced (binding_rowid INTEGER PRIMARY KEY, session TEXT NOT NULL, connect TEXT);
      CREATE TRIGGER session_binding_before_add BEFORE INSERT ON bindings BEGIN ${stage(false)} END;
      CREATE TRIGGER session_binding_add AFTER INSERT ON bindings BEGIN ${reconcile} ${see("NEW.rowid")} END;
      CREATE TRIGGER session_binding_before_change BEFORE UPDATE ON bindings
        WHEN OLD.rowid IS NOT NEW.rowid OR OLD.connect IS NOT NEW.connect OR OLD.session_key IS NOT NEW.session_key
        BEGIN ${stage(true)} END;
      CREATE TRIGGER session_binding_change AFTER UPDATE ON bindings
        WHEN OLD.rowid IS NOT NEW.rowid OR OLD.connect IS NOT NEW.connect OR OLD.session_key IS NOT NEW.session_key
        BEGIN ${reconcile} ${see("NEW.rowid")} END;
      CREATE TRIGGER session_binding_drop AFTER DELETE ON bindings BEGIN
        DELETE FROM session_binding_rows WHERE session = OLD.session_key AND binding_rowid = OLD.rowid;
      END;
    `);
    else sessionBindingsReady(db);
    db.exec("COMMIT");
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

function checkVersion(version: number): void {
  if (version !== VERSION) throw new Error(`session binding index version ${version} is incompatible with ${VERSION}`);
}

export function sessionBindingsReady(db: DatabaseSync): boolean {
  const meta = db.prepare("SELECT version, complete FROM session_binding_meta WHERE id = 1").get() as { version: number; complete: number } | undefined;
  if (meta === undefined) throw new Error("session binding index version marker is missing");
  checkVersion(meta.version);
  return meta.complete === 1;
}

export function sessionBindingsStep(db: DatabaseSync, limit = 256): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("session binding batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const meta = db.prepare(`SELECT version, CAST(last_rowid AS TEXT) AS last_rowid, CAST(end_rowid AS TEXT) AS end_rowid, complete
      FROM session_binding_meta WHERE id = 1`).get() as { version: number; last_rowid: string | null; end_rowid: string | null; complete: number } | undefined;
    if (meta === undefined) throw new Error("session binding index version marker is missing");
    checkVersion(meta.version);
    if (meta.complete === 1) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const rows = (meta.last_rowid === null
      ? db.prepare(SESSION_BINDINGS_FIRST).all(meta.end_rowid, limit)
      : db.prepare(SESSION_BINDINGS_NEXT).all(meta.last_rowid, meta.end_rowid, limit)) as { position: string }[];
    const put = db.prepare(see("CAST(? AS INTEGER)"));
    for (const row of rows) put.run(row.position);
    const done = rows.length < limit;
    db.prepare("UPDATE session_binding_meta SET last_rowid = CAST(? AS INTEGER), complete = ? WHERE id = 1")
      .run(rows.at(-1)?.position ?? meta.last_rowid, done ? 1 : 0);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
