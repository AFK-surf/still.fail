// Reverse lookups for the marks that keep a chat out of automatic archive. The source tables are keyed by viewer;
// these tables are keyed by the candidate. Old marks are prepared in bounded batches while triggers follow writers.
import type { DatabaseSync } from "node:sqlite";

const VERSION = 1;
export const ARCHIVE_PIN_EXISTS = "SELECT 1 FROM archive_pin_rows WHERE session = ? LIMIT 1";
export const ARCHIVE_KEEP_EXISTS = "SELECT 1 FROM archive_keep_rows WHERE thread = ? LIMIT 1";

type Kind = "pins" | "kept";
const parts = (kind: Kind) => kind === "pins"
  ? { source: "pins", key: "session", rows: "archive_pin_rows", staged: "archive_pin_replaced" }
  : { source: "kept_chats", key: "thread", rows: "archive_keep_rows", staged: "archive_keep_replaced" };

function triggers(kind: Kind): string {
  const { source, key, rows, staged } = parts(kind);
  const prefix = kind === "pins" ? "archive_pin" : "archive_keep";
  const displaced = `SELECT rowid, ${key} FROM ${source} WHERE viewer = NEW.viewer AND ${key} = NEW.${key}
    UNION SELECT rowid, ${key} FROM ${source} WHERE rowid = NEW.rowid`;
  const stage = (update: boolean) => `DELETE FROM ${staged}; INSERT INTO ${staged} (position, value) ${displaced}
    ${update ? `UNION SELECT OLD.rowid, OLD.${key}` : ""};`;
  const reconcile = `DELETE FROM ${rows} WHERE (${key}, position) IN (SELECT value, position FROM ${staged})
      AND NOT EXISTS (SELECT 1 FROM ${source} s WHERE s.rowid = ${rows}.position AND s.${key} IS ${rows}.${key});
    INSERT INTO ${rows} (${key}, position) SELECT s.${key}, s.rowid FROM ${staged} r CROSS JOIN ${source} s ON s.rowid = r.position
      WHERE NOT EXISTS (SELECT 1 FROM ${rows} i WHERE i.${key} IS s.${key} AND i.position = s.rowid);
    DELETE FROM ${staged};`;
  const see = `INSERT INTO ${rows} (${key}, position) SELECT s.${key}, s.rowid FROM ${source} s WHERE s.rowid = NEW.rowid
    AND NOT EXISTS (SELECT 1 FROM ${rows} i WHERE i.${key} IS s.${key} AND i.position = s.rowid);`;
  const changed = `OLD.rowid IS NOT NEW.rowid OR OLD.viewer IS NOT NEW.viewer OR OLD.${key} IS NOT NEW.${key}`;
  return `
    CREATE TRIGGER ${prefix}_before_add BEFORE INSERT ON ${source} BEGIN ${stage(false)} END;
    CREATE TRIGGER ${prefix}_add AFTER INSERT ON ${source} BEGIN ${reconcile} ${see} END;
    CREATE TRIGGER ${prefix}_before_change BEFORE UPDATE ON ${source} WHEN ${changed} BEGIN ${stage(true)} END;
    CREATE TRIGGER ${prefix}_change AFTER UPDATE ON ${source} WHEN ${changed} BEGIN ${reconcile} ${see} END;
    CREATE TRIGGER ${prefix}_drop AFTER DELETE ON ${source} BEGIN
      DELETE FROM ${rows} WHERE ${key} IS OLD.${key} AND position = OLD.rowid;
    END;`;
}

export function installArchiveMarkIndex(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='archive_mark_meta'").get() !== undefined;
  if (installed()) { archiveMarksReady(db); return; }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE archive_mark_meta (kind TEXT PRIMARY KEY, version INTEGER NOT NULL, last_rowid INTEGER,
        end_rowid INTEGER, complete INTEGER NOT NULL) WITHOUT ROWID;
      INSERT INTO archive_mark_meta SELECT 'pins', ${VERSION}, NULL, (SELECT rowid FROM pins ORDER BY rowid DESC LIMIT 1),
        NOT EXISTS (SELECT 1 FROM pins LIMIT 1);
      INSERT INTO archive_mark_meta SELECT 'kept', ${VERSION}, NULL, (SELECT rowid FROM kept_chats ORDER BY rowid DESC LIMIT 1),
        NOT EXISTS (SELECT 1 FROM kept_chats LIMIT 1);
      CREATE TABLE archive_pin_rows (session TEXT NOT NULL, position INTEGER NOT NULL, PRIMARY KEY (session, position)) WITHOUT ROWID;
      CREATE TABLE archive_keep_rows (thread INTEGER NOT NULL, position INTEGER NOT NULL, PRIMARY KEY (thread, position)) WITHOUT ROWID;
      CREATE TABLE archive_pin_replaced (position INTEGER PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE archive_keep_replaced (position INTEGER PRIMARY KEY, value INTEGER NOT NULL);
      ${triggers("pins")}
      ${triggers("kept")}
    `);
    else archiveMarksReady(db);
    db.exec("COMMIT");
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

type Meta = { kind: Kind; version: number; last_rowid: string | null; end_rowid: string | null; complete: number };
function markers(db: DatabaseSync): Meta[] {
  const rows = db.prepare(`SELECT kind, version, CAST(last_rowid AS TEXT) AS last_rowid,
    CAST(end_rowid AS TEXT) AS end_rowid, complete FROM archive_mark_meta ORDER BY kind`).all() as Meta[];
  if (rows.length !== 2 || rows[0]?.kind !== "kept" || rows[1]?.kind !== "pins") throw new Error("archive mark index version marker is missing");
  for (const row of rows) if (row.version !== VERSION) throw new Error(`archive mark index version ${row.version} is incompatible with ${VERSION}`);
  return rows;
}

export function archiveMarksReady(db: DatabaseSync): boolean { return markers(db).every((m) => m.complete === 1); }

export function archiveMarksStep(db: DatabaseSync, limit = 256): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("archive mark batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const all = markers(db);
    const meta = all.find((m) => m.complete !== 1);
    if (meta === undefined) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const { source, key, rows } = parts(meta.kind);
    const positions = (meta.last_rowid === null
      ? db.prepare(`SELECT CAST(rowid AS TEXT) AS position FROM ${source} WHERE rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?`).all(meta.end_rowid, limit)
      : db.prepare(`SELECT CAST(rowid AS TEXT) AS position FROM ${source} WHERE rowid > CAST(? AS INTEGER) AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?`).all(meta.last_rowid, meta.end_rowid, limit)) as { position: string }[];
    const put = db.prepare(`INSERT INTO ${rows} (${key}, position) SELECT s.${key}, s.rowid FROM ${source} s WHERE s.rowid = CAST(? AS INTEGER)
      AND NOT EXISTS (SELECT 1 FROM ${rows} i WHERE i.${key} IS s.${key} AND i.position = s.rowid)`);
    for (const row of positions) put.run(row.position);
    const finished = positions.length < limit;
    db.prepare("UPDATE archive_mark_meta SET last_rowid = CAST(? AS INTEGER), complete = ? WHERE kind = ?")
      .run(positions.at(-1)?.position ?? meta.last_rowid, finished ? 1 : 0, meta.kind);
    db.exec("COMMIT");
    return { done: finished && all.every((m) => m.kind === meta.kind || m.complete === 1), visited: positions.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
