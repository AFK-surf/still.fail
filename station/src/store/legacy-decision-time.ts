// Build a missing decision-time lookup in bounded transactions for an older, populated store.
import type { DatabaseSync } from "node:sqlite";

const VERSION = 1;
const BATCH = 64;
const exists = (db: DatabaseSync, type: string, name: string) =>
  db.prepare("SELECT 1 FROM sqlite_master WHERE type=? AND name=?").get(type, name) !== undefined;

export const DECISION_TIME_INDEX = "CREATE INDEX IF NOT EXISTS decision_checks_lately ON decision_checks (created_at, session)";

export function hasLegacyDecisionTime(db: DatabaseSync): boolean {
  if (!exists(db, "table", "legacy_decision_time_meta")) return false;
  if (!exists(db, "table", "legacy_decision_time"))
    throw new Error("legacy decision-time metadata has no lookup");
  const row = db.prepare("SELECT version,complete FROM legacy_decision_time_meta WHERE id=1").get() as
    { version: number; complete: number } | undefined;
  if (!row || row.version !== VERSION || (row.complete !== 0 && row.complete !== 1))
    throw new Error("legacy decision-time lookup has an unsupported version");
  return true;
}

// Read the source after each actual write: ignored writes have no AFTER trigger, and REPLACE may silently remove a row.
// Re-reading both ids also handles another trigger changing or deleting the row during a nested write.
const reconcile = (ids: string) => `DELETE FROM legacy_decision_time WHERE id IN (${ids});
  INSERT INTO legacy_decision_time(id,created_at,session)
    SELECT id,created_at,session FROM decision_checks WHERE id IN (${ids});`;
const LEGACY_SCHEMA = `
  CREATE TABLE legacy_decision_time_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL,
    complete INTEGER NOT NULL,cursor INTEGER,end_id INTEGER) WITHOUT ROWID;
  INSERT INTO legacy_decision_time_meta VALUES(1,${VERSION},0,NULL,(SELECT MAX(id) FROM decision_checks));
  CREATE TABLE legacy_decision_time(id INTEGER PRIMARY KEY,created_at INTEGER NOT NULL,session TEXT NOT NULL);
  CREATE INDEX legacy_decision_time_at ON legacy_decision_time(created_at,session);
  CREATE TRIGGER legacy_decision_time_insert AFTER INSERT ON decision_checks BEGIN
    INSERT INTO legacy_decision_time(id,created_at,session)
      SELECT id,created_at,session FROM decision_checks WHERE id=NEW.id
      ON CONFLICT(id) DO UPDATE SET created_at=excluded.created_at,session=excluded.session;
  END;
  CREATE TRIGGER legacy_decision_time_update AFTER UPDATE OF id,created_at,session ON decision_checks
    WHEN OLD.id IS NOT NEW.id OR OLD.created_at IS NOT NEW.created_at OR OLD.session IS NOT NEW.session
    BEGIN ${reconcile("OLD.id,NEW.id")} END;
  CREATE TRIGGER legacy_decision_time_delete AFTER DELETE ON decision_checks BEGIN ${reconcile("OLD.id")} END;`;

/// Choose while holding the writer lock: another old connection or opener may have changed the table or index.
export function installDecisionTimeIndex(db: DatabaseSync): void {
  const native = () => exists(db, "index", "decision_checks_lately");
  if (native() || hasLegacyDecisionTime(db)) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!native() && !hasLegacyDecisionTime(db)) {
      if (db.prepare("SELECT 1 FROM decision_checks LIMIT 1 OFFSET 63").get() === undefined) db.exec(DECISION_TIME_INDEX);
      else db.exec(LEGACY_SCHEMA);
    }
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

type Meta = { version: number; complete: number; cursor: string | null; end_id: string | null };
const meta = (db: DatabaseSync) => db.prepare(`SELECT version,complete,CAST(cursor AS TEXT) cursor,CAST(end_id AS TEXT) end_id
  FROM legacy_decision_time_meta WHERE id=1`).get() as Meta;

/// Copy at most 64 ids, in the same transaction as progress; trigger updates are already reflected in the source.
export function decisionTimeIndexStep(db: DatabaseSync, limit = BATCH): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > BATCH) throw new RangeError("decision-time batch must be 1–64");
  if (!hasLegacyDecisionTime(db)) return { done: true, visited: 0 };
  db.exec("BEGIN IMMEDIATE");
  try {
    const m = meta(db);
    if (m.version !== VERSION) throw new Error("unsupported legacy decision-time preparation");
    if (m.complete === 1) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const rows = m.end_id === null ? [] : (m.cursor === null
      ? db.prepare(`SELECT CAST(id AS TEXT) id FROM decision_checks WHERE id<=CAST(?1 AS INTEGER)
          ORDER BY decision_checks.id LIMIT ?2`).all(m.end_id, limit)
      : db.prepare(`SELECT CAST(id AS TEXT) id FROM decision_checks WHERE id>CAST(?1 AS INTEGER) AND id<=CAST(?2 AS INTEGER)
          ORDER BY decision_checks.id LIMIT ?3`).all(m.cursor, m.end_id, limit)) as { id: string }[];
    const put = db.prepare(`INSERT INTO legacy_decision_time(id,created_at,session)
      SELECT id,created_at,session FROM decision_checks d WHERE d.id=CAST(?1 AS INTEGER)
        AND NOT EXISTS (SELECT 1 FROM legacy_decision_time l WHERE l.id=d.id)`);
    for (const row of rows) put.run(row.id);
    const done = rows.length < limit;
    db.prepare("UPDATE legacy_decision_time_meta SET cursor=CAST(? AS INTEGER),complete=? WHERE id=1")
      .run(rows.at(-1)?.id ?? m.cursor, done ? 1 : 0);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function decisionTimeIndexNeedsWork(db: DatabaseSync): boolean {
  return hasLegacyDecisionTime(db) && meta(db).complete === 0;
}
