import type { DatabaseSync } from "node:sqlite";

// The effective files of a message, keyed by the path a widget reports. Old threads are prepared on demand; triggers
// follow both old and new station processes while they are prepared. The source of truth remains the merged view.
const VERSION = 1;

export class WidgetSourcesUnavailable extends Error {
  constructor(readonly threads: readonly number[]) { super("widget sources are still being prepared"); }
}

// Within each thread, take only its newest matching attachment. The outer ordering compares those candidates in the
// same order as the original thread_sessions/merged query when timestamps tie.
export const WIDGET_SOURCE = `SELECT t.channel, t.thread_ts, i.name FROM thread_sessions ts
  JOIN threads t ON t.id = ts.thread
  JOIN widget_source_rows i ON (i.thread, i.n, i.slot) = (
    SELECT x.thread, x.n, x.slot FROM widget_source_rows x
    WHERE x.thread = ts.thread AND x.path = ?2 ORDER BY x.at DESC, x.n, x.slot LIMIT 1
  ) WHERE ts.session = ?1 ORDER BY i.at DESC, ts.rowid LIMIT 1`;

const candidates = (row: string) => `SELECT ${row}.thread AS thread, ${row}.n AS n WHERE ${row}.kind = 'message'
  UNION SELECT ${row}.thread, ${row}.target WHERE ${row}.target IS NOT NULL`;
const conflicts = `SELECT e.thread, e.n FROM entries e WHERE e.thread = NEW.thread AND e.n = NEW.n AND e.kind = 'message'
  UNION SELECT e.thread, e.target FROM entries e WHERE e.thread = NEW.thread AND e.n = NEW.n AND e.target IS NOT NULL
  UNION SELECT e.thread, e.n FROM entries e WHERE NEW.ts IS NOT NULL AND e.thread = NEW.thread AND e.ts = NEW.ts AND e.kind = 'message'
  UNION SELECT e.thread, e.target FROM entries e WHERE NEW.ts IS NOT NULL AND e.thread = NEW.thread AND e.ts = NEW.ts AND e.target IS NOT NULL
  UNION SELECT e.thread, e.n FROM entries e WHERE e.rowid = NEW.rowid AND e.kind = 'message'
  UNION SELECT e.thread, e.target FROM entries e WHERE e.rowid = NEW.rowid AND e.target IS NOT NULL`;
const stage = (updating: boolean) => `DELETE FROM widget_source_changed;
  INSERT INTO widget_source_changed (thread, n, existed, attachments, at, dirty)
    SELECT k.thread, k.n, m.n IS NOT NULL, m.attachments, m.created_at, 0
    FROM (${candidates("NEW")} UNION ${conflicts}${updating ? ` UNION ${candidates("OLD")}` : ""}) k
    LEFT JOIN merged m ON m.thread = k.thread AND m.n = k.n;`;
const changed = `(c.dirty = 1 OR c.existed IS NOT (m.n IS NOT NULL)
  OR c.attachments IS NOT m.attachments OR c.at IS NOT m.created_at)`;
const affected = `SELECT c.thread, c.n FROM widget_source_changed c
  LEFT JOIN merged m ON m.thread = c.thread AND m.n = c.n WHERE ${changed}`;
const validAttachments = `CASE WHEN json_valid(m.attachments) THEN m.attachments ELSE '[]' END`;
const pathOf = `CASE WHEN json_valid(a.value) THEN json_extract(a.value, '$.path') END`;
const nameOf = `CASE WHEN json_valid(a.value) THEN json_extract(a.value, '$.name') END`;

// A malformed attachment was already an error in the old lookup. Remember it without making the write itself fail.
const invalid = `(m.attachments IS NOT NULL AND (NOT json_valid(m.attachments) OR EXISTS
  (SELECT 1 FROM json_each(${validAttachments}) a WHERE a.value IS NOT NULL AND NOT json_valid(a.value))))`;
const insertRows = (messages: string) => `INSERT INTO widget_source_rows (thread,n,slot,path,at,name)
  SELECT m.thread, m.n, a.id, ${pathOf}, m.created_at, ${nameOf}
  FROM (${messages}) k CROSS JOIN merged m ON m.thread = k.thread AND m.n = k.n
  CROSS JOIN json_each(${validAttachments}) a
  WHERE typeof(${pathOf}) = 'text' AND NOT EXISTS (SELECT 1 FROM widget_source_rows i
    WHERE i.thread = m.thread AND i.n = m.n AND i.slot = a.id);`;
const insertInvalid = (messages: string) => `INSERT INTO widget_source_invalid (thread,n)
  SELECT m.thread, m.n FROM (${messages}) k CROSS JOIN merged m ON m.thread = k.thread AND m.n = k.n
  WHERE ${invalid} AND NOT EXISTS (SELECT 1 FROM widget_source_invalid i WHERE i.thread = m.thread AND i.n = m.n);`;
const reconcile = `DELETE FROM widget_source_rows WHERE (thread,n) IN (${affected});
  DELETE FROM widget_source_invalid WHERE (thread,n) IN (${affected});
  ${insertRows(affected)} ${insertInvalid(affected)} DELETE FROM widget_source_changed;`;
const oldMessages = `SELECT OLD.thread AS thread, OLD.n AS n WHERE OLD.kind = 'message'
  UNION SELECT OLD.thread, OLD.target WHERE OLD.target IS NOT NULL`;
const afterDelete = `DELETE FROM widget_source_rows WHERE (thread,n) IN (${oldMessages});
  DELETE FROM widget_source_invalid WHERE (thread,n) IN (${oldMessages});
  ${insertRows(oldMessages)} ${insertInvalid(oldMessages)}
  UPDATE widget_source_changed SET dirty = 1 WHERE (thread,n) IN (${oldMessages});`;
const updated = `OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n OR OLD.kind IS NOT NEW.kind
  OR OLD.target IS NOT NEW.target OR OLD.ts IS NOT NEW.ts OR OLD.attachments IS NOT NEW.attachments OR OLD.at IS NOT NEW.at`;

export function installWidgetSources(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='widget_source_meta'").get() !== undefined;
  if (installed()) { widgetSourcesFresh(db); return; }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE widget_source_meta (id INTEGER PRIMARY KEY CHECK (id=1), version INTEGER NOT NULL, fresh INTEGER NOT NULL) WITHOUT ROWID;
      INSERT INTO widget_source_meta SELECT 1, ${VERSION}, NOT EXISTS (SELECT 1 FROM entries LIMIT 1);
      CREATE TABLE widget_source_scopes (thread INTEGER PRIMARY KEY, last_n INTEGER, end_n INTEGER, complete INTEGER NOT NULL) WITHOUT ROWID;
      CREATE TABLE widget_source_rows (thread INTEGER NOT NULL, n INTEGER NOT NULL, slot INTEGER NOT NULL,
        path TEXT NOT NULL, at INTEGER NOT NULL, name, PRIMARY KEY(thread,n,slot)) WITHOUT ROWID;
      CREATE INDEX widget_source_by_path ON widget_source_rows (thread,path,at DESC,n,slot);
      CREATE TABLE widget_source_invalid (thread INTEGER NOT NULL, n INTEGER NOT NULL, PRIMARY KEY(thread,n)) WITHOUT ROWID;
      CREATE TABLE widget_source_changed (thread INTEGER NOT NULL, n INTEGER NOT NULL, existed INTEGER NOT NULL,
        attachments TEXT, at INTEGER, dirty INTEGER NOT NULL, PRIMARY KEY(thread,n)) WITHOUT ROWID;
      CREATE TRIGGER widget_source_before_add BEFORE INSERT ON entries BEGIN ${stage(false)} END;
      CREATE TRIGGER widget_source_add AFTER INSERT ON entries BEGIN ${reconcile} END;
      CREATE TRIGGER widget_source_before_change BEFORE UPDATE OF thread,n,kind,target,ts,attachments,at ON entries
        WHEN ${updated} BEGIN ${stage(true)} END;
      CREATE TRIGGER widget_source_change AFTER UPDATE OF thread,n,kind,target,ts,attachments,at ON entries
        WHEN ${updated} BEGIN ${reconcile} END;
      CREATE TRIGGER widget_source_drop AFTER DELETE ON entries BEGIN ${afterDelete} END;
      CREATE TRIGGER widget_source_new_thread AFTER INSERT ON threads
        WHEN NOT EXISTS (SELECT 1 FROM entries WHERE thread=NEW.id)
        BEGIN INSERT INTO widget_source_scopes (thread,last_n,end_n,complete)
          SELECT NEW.id,NULL,NULL,1 WHERE NOT EXISTS (SELECT 1 FROM widget_source_scopes WHERE thread=NEW.id); END;
    `);
    else widgetSourcesFresh(db);
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function widgetSourcesFresh(db: DatabaseSync): boolean {
  const meta = db.prepare("SELECT version, fresh FROM widget_source_meta WHERE id=1").get() as { version: number; fresh: number } | undefined;
  if (!meta || meta.version !== VERSION) throw new Error(`widget source index version ${meta?.version ?? "missing"} is incompatible with ${VERSION}`);
  return meta.fresh === 1;
}

export function widgetSourcesReady(db: DatabaseSync, thread: number): boolean {
  if (widgetSourcesFresh(db)) return true;
  return (db.prepare("SELECT complete FROM widget_source_scopes WHERE thread=?").get(thread) as { complete: number } | undefined)?.complete === 1;
}

type Scope = { last_n: string | null; end_n: string | null; complete: number };
const scopeOf = (db: DatabaseSync, thread: number): Scope | undefined => db.prepare(
  "SELECT CAST(last_n AS TEXT) AS last_n, CAST(end_n AS TEXT) AS end_n, complete FROM widget_source_scopes WHERE thread=?",
).get(thread) as Scope | undefined;

/// Prepare one old thread in bounded batches. Read cold positions before taking the writer; triggers preserve any
/// changes between that read and the primary-key recheck made while committing the batch.
export function widgetSourcesStep(db: DatabaseSync, thread: number, limit = 128): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 128) throw new RangeError("widget source batch must be between 1 and 128");
  if (widgetSourcesReady(db, thread)) return { done: true, visited: 0 };
  if (!scopeOf(db, thread)) {
    db.exec("BEGIN IMMEDIATE");
    try {
      db.prepare(`INSERT INTO widget_source_scopes (thread,last_n,end_n,complete)
        SELECT ?,NULL,(SELECT n FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1),0
        WHERE NOT EXISTS (SELECT 1 FROM widget_source_scopes WHERE thread=?)`).run(thread, thread, thread);
      db.exec("COMMIT");
    } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
  }
  const before = scopeOf(db, thread)!;
  if (before.complete === 1) return { done: true, visited: 0 };
  const positions = (before.last_n === null
    ? db.prepare("SELECT CAST(n AS TEXT) AS n FROM entries WHERE thread=? AND n<=CAST(? AS INTEGER) ORDER BY n LIMIT ?").all(thread, before.end_n, limit)
    : db.prepare("SELECT CAST(n AS TEXT) AS n FROM entries WHERE thread=? AND n>CAST(? AS INTEGER) AND n<=CAST(? AS INTEGER) ORDER BY n LIMIT ?").all(thread, before.last_n, before.end_n, limit)) as { n: string }[];
  db.exec("BEGIN IMMEDIATE");
  try {
    const now = scopeOf(db, thread);
    if (!now || now.last_n !== before.last_n || now.end_n !== before.end_n || now.complete !== before.complete) {
      db.exec("COMMIT"); return { done: now?.complete === 1, visited: 0 };
    }
    const message = "SELECT ? AS thread, CAST(? AS INTEGER) AS n";
    const addRows = db.prepare(insertRows(message));
    const addInvalid = db.prepare(insertInvalid(message));
    for (const position of positions) { addRows.run(thread, position.n); addInvalid.run(thread, position.n); }
    const done = positions.length < limit;
    db.prepare("UPDATE widget_source_scopes SET last_n=CAST(? AS INTEGER), complete=? WHERE thread=?")
      .run(positions.at(-1)?.n ?? before.last_n, done ? 1 : 0, thread);
    db.exec("COMMIT");
    return { done, visited: positions.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
