// Prepare a missing decision-by-session lookup in bounded transactions for an older store.
import type { DatabaseSync } from "node:sqlite";
import { hasLegacyDecisionTime } from "./legacy-decision-time.ts";

const VERSION = 1;
const BATCH = 64;
const exists = (db: DatabaseSync, type: string, name: string) =>
  db.prepare("SELECT 1 FROM sqlite_master WHERE type=? AND name=?").get(type, name) !== undefined;

export class DecisionSessionsUnavailable extends Error {
  constructor() { super("decision session lookup is not ready"); }
}

export const DECISION_SESSION_INDEX =
  "CREATE INDEX IF NOT EXISTS decision_checks_session ON decision_checks (session, id)";

/// Seek one session after its lookup is complete. During preparation, the Store uses its bounded tail instead.
export function legacyLastDecision(shared: boolean): string {
  const table = shared ? "legacy_decision_time" : "legacy_decision_session";
  const index = shared ? "legacy_decision_time_by_session" : "legacy_decision_session_by_session";
  return `SELECT d.result FROM ${table} p INDEXED BY ${index}
    CROSS JOIN decision_checks d ON d.id=p.id WHERE p.session=?1 ORDER BY p.id DESC LIMIT 1`;
}
export const LEGACY_LAST_DECISION_SHARED = legacyLastDecision(true);
export const LEGACY_LAST_DECISION_SEPARATE = legacyLastDecision(false);

export function hasLegacyDecisionSession(db: DatabaseSync): boolean {
  if (!exists(db, "table", "legacy_decision_session_meta")) return false;
  if (!exists(db, "table", "legacy_decision_session") || !exists(db, "index", "legacy_decision_session_by_session"))
    throw new Error("legacy decision-session metadata has no lookup");
  const row = db.prepare("SELECT version,complete FROM legacy_decision_session_meta WHERE id=1").get() as
    { version: number; complete: number } | undefined;
  if (!row || row.version !== VERSION || (row.complete !== 0 && row.complete !== 1))
    throw new Error("legacy decision-session lookup has an unsupported version");
  return true;
}

/// A time lookup installed while both native indexes were missing carries the session index in the same table.
export function hasSharedDecisionSession(db: DatabaseSync): boolean {
  if (!exists(db, "index", "legacy_decision_time_by_session")) return false;
  if (!hasLegacyDecisionTime(db)) throw new Error("shared decision-session index has no time lookup");
  return true;
}

const reconcile = (ids: string) => `DELETE FROM legacy_decision_session WHERE id IN (${ids});
  INSERT INTO legacy_decision_session(id,session) SELECT id,session FROM decision_checks WHERE id IN (${ids});`;
const SCHEMA = `
CREATE TABLE legacy_decision_session_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL,
  complete INTEGER NOT NULL,cursor INTEGER,end_id INTEGER) WITHOUT ROWID;
INSERT INTO legacy_decision_session_meta VALUES(1,${VERSION},0,NULL,(SELECT MAX(id) FROM decision_checks));
CREATE TABLE legacy_decision_session(id INTEGER PRIMARY KEY,session TEXT NOT NULL);
CREATE INDEX legacy_decision_session_by_session ON legacy_decision_session(session);
CREATE TRIGGER legacy_decision_session_insert AFTER INSERT ON decision_checks BEGIN
  INSERT INTO legacy_decision_session(id,session) SELECT id,session FROM decision_checks WHERE id=NEW.id
  ON CONFLICT(id) DO UPDATE SET session=excluded.session;
END;
CREATE TRIGGER legacy_decision_session_update AFTER UPDATE OF id,session ON decision_checks
  WHEN OLD.id IS NOT NEW.id OR OLD.session IS NOT NEW.session BEGIN ${reconcile("OLD.id,NEW.id")} END;
CREATE TRIGGER legacy_decision_session_delete AFTER DELETE ON decision_checks BEGIN ${reconcile("OLD.id")} END;`;

/// Recheck both the row bound and another opener under the writer lock.
export function installDecisionSessionIndex(db: DatabaseSync): void {
  const native = () => exists(db, "index", "decision_checks_session");
  if (native() || hasLegacyDecisionSession(db) || hasSharedDecisionSession(db)) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!native() && !hasLegacyDecisionSession(db) && !hasSharedDecisionSession(db)) {
      if (db.prepare("SELECT 1 FROM decision_checks LIMIT 1 OFFSET 63").get() === undefined) db.exec(DECISION_SESSION_INDEX);
      else db.exec(SCHEMA);
    }
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

type Meta = { version: number; complete: number; cursor: string | null; end_id: string | null };
const meta = (db: DatabaseSync) => db.prepare(`SELECT version,complete,CAST(cursor AS TEXT) cursor,
  CAST(end_id AS TEXT) end_id FROM legacy_decision_session_meta WHERE id=1`).get() as Meta;

export function decisionSessionIndexStep(db: DatabaseSync, limit = BATCH): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > BATCH) throw new RangeError("decision-session batch must be 1–64");
  if (!hasLegacyDecisionSession(db)) return { done: true, visited: 0 };
  db.exec("BEGIN IMMEDIATE");
  try {
    const m = meta(db);
    if (m.version !== VERSION) throw new Error("unsupported legacy decision-session preparation");
    if (m.complete === 1) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const rows = m.end_id === null ? [] : (m.cursor === null
      ? db.prepare(`SELECT CAST(id AS TEXT) id FROM decision_checks WHERE id<=CAST(?1 AS INTEGER)
          ORDER BY decision_checks.id LIMIT ?2`).all(m.end_id, limit)
      : db.prepare(`SELECT CAST(id AS TEXT) id FROM decision_checks WHERE id>CAST(?1 AS INTEGER) AND id<=CAST(?2 AS INTEGER)
          ORDER BY decision_checks.id LIMIT ?3`).all(m.cursor, m.end_id, limit)) as { id: string }[];
    const put = db.prepare(`INSERT INTO legacy_decision_session(id,session)
      SELECT id,session FROM decision_checks d WHERE d.id=CAST(?1 AS INTEGER)
        AND NOT EXISTS (SELECT 1 FROM legacy_decision_session l WHERE l.id=d.id)`);
    for (const row of rows) put.run(row.id);
    const done = rows.length < limit;
    db.prepare("UPDATE legacy_decision_session_meta SET cursor=CAST(? AS INTEGER),complete=? WHERE id=1")
      .run(rows.at(-1)?.id ?? m.cursor, done ? 1 : 0);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function decisionSessionIndexNeedsWork(db: DatabaseSync): boolean {
  return hasLegacyDecisionSession(db) && meta(db).complete === 0;
}
