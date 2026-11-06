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
export const LEGACY_LAST_DECISION_REPAIR = `SELECT d.result FROM legacy_decision_session_repair p
  INDEXED BY legacy_decision_session_repair_by_session CROSS JOIN decision_checks d ON d.id=p.id
  WHERE p.session=?1 ORDER BY p.id DESC LIMIT 1`;

type SessionTable = "legacy_decision_session" | "legacy_decision_session_repair";
function sessionState(db: DatabaseSync, table: SessionTable): number | null {
  if (!exists(db, "table", `${table}_meta`)) return null;
  if (!exists(db, "table", table))
    throw new Error("legacy decision-session metadata has no lookup");
  const row = db.prepare(`SELECT version,complete FROM ${table}_meta WHERE id=1`).get() as
    { version: number; complete: number } | undefined;
  if (!row || row.version !== VERSION || (row.complete !== 0 && row.complete !== 1
    && !(table === "legacy_decision_session_repair" && row.complete === 2)))
    throw new Error("legacy decision-session lookup has an unsupported version");
  return row.complete;
}
function hasSessionLookup(db: DatabaseSync, table: SessionTable): boolean {
  const state = sessionState(db, table);
  return state !== null && state !== 2 && exists(db, "index", `${table}_by_session`);
}
export const hasLegacyDecisionSession = (db: DatabaseSync): boolean => hasSessionLookup(db, "legacy_decision_session");
export const hasDecisionSessionRepair = (db: DatabaseSync): boolean => hasSessionLookup(db, "legacy_decision_session_repair");

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
// If the old auxiliary index was removed, its table may still be in use by older connections. Build a fresh, empty
// lookup beside it; never create an index synchronously over the populated old table.
const REPAIR_SCHEMA = SCHEMA.replaceAll("legacy_decision_session", "legacy_decision_session_repair");
const REPAIR_TRIGGERS = SCHEMA.slice(SCHEMA.indexOf("CREATE TRIGGER")).replaceAll("legacy_decision_session", "legacy_decision_session_repair");
const REPAIR_INDEX = "CREATE INDEX legacy_decision_session_repair_by_session ON legacy_decision_session_repair(session)";

/// Recheck both the row bound and another opener under the writer lock.
export function installDecisionSessionIndex(db: DatabaseSync): void {
  const native = () => exists(db, "index", "decision_checks_session");
  const available = () => native() || hasLegacyDecisionSession(db) || hasSharedDecisionSession(db) || hasDecisionSessionRepair(db);
  if (available() || sessionState(db, "legacy_decision_session_repair") === 2) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!available() && sessionState(db, "legacy_decision_session_repair") !== 2) {
      if (db.prepare("SELECT 1 FROM decision_checks LIMIT 1 OFFSET 63").get() === undefined) db.exec(DECISION_SESSION_INDEX);
      else if (sessionState(db, "legacy_decision_session_repair") !== null) {
        // Its index was removed too. Stop tracking writes while the unusable table is emptied in bounded batches;
        // after it is empty, the worker reinstalls its index and triggers and scans from a new source watermark.
        db.exec(`DROP TRIGGER IF EXISTS legacy_decision_session_repair_insert;
          DROP TRIGGER IF EXISTS legacy_decision_session_repair_update;
          DROP TRIGGER IF EXISTS legacy_decision_session_repair_delete;
          UPDATE legacy_decision_session_repair_meta SET complete=2 WHERE id=1`);
      }
      else if (exists(db, "table", "legacy_decision_session_meta")) db.exec(REPAIR_SCHEMA);
      else db.exec(SCHEMA);
    }
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

type Meta = { version: number; complete: number; cursor: string | null; end_id: string | null };
const meta = (db: DatabaseSync, table: SessionTable) => db.prepare(`SELECT version,complete,CAST(cursor AS TEXT) cursor,
  CAST(end_id AS TEXT) end_id FROM ${table}_meta WHERE id=1`).get() as Meta;

function sessionIndexStep(db: DatabaseSync, table: SessionTable, limit: number): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > BATCH) throw new RangeError("decision-session batch must be 1–64");
  if (table === "legacy_decision_session_repair" ? !decisionSessionRepairNeedsWork(db) : !hasSessionLookup(db, table))
    return { done: true, visited: 0 };
  db.exec("BEGIN IMMEDIATE");
  try {
    if (table === "legacy_decision_session_repair" && sessionState(db, table) === 2) {
      const removed = db.prepare(`DELETE FROM ${table} WHERE id IN (SELECT id FROM ${table} ORDER BY id LIMIT ?)`).run(limit).changes;
      if (db.prepare(`SELECT 1 FROM ${table} LIMIT 1`).get() === undefined) {
        db.exec(`${REPAIR_INDEX}; ${REPAIR_TRIGGERS}`);
        db.exec(`UPDATE ${table}_meta SET complete=0,cursor=NULL,end_id=(SELECT MAX(id) FROM decision_checks) WHERE id=1`);
      }
      db.exec("COMMIT");
      return { done: false, visited: Number(removed) };
    }
    // Another connection can remove the index between the initial check and this writer lock.
    if (!hasSessionLookup(db, table)) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const m = meta(db, table);
    if (m.version !== VERSION) throw new Error("unsupported legacy decision-session preparation");
    if (m.complete === 1) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const rows = m.end_id === null ? [] : (m.cursor === null
      ? db.prepare(`SELECT CAST(id AS TEXT) id FROM decision_checks WHERE id<=CAST(?1 AS INTEGER)
          ORDER BY decision_checks.id LIMIT ?2`).all(m.end_id, limit)
      : db.prepare(`SELECT CAST(id AS TEXT) id FROM decision_checks WHERE id>CAST(?1 AS INTEGER) AND id<=CAST(?2 AS INTEGER)
          ORDER BY decision_checks.id LIMIT ?3`).all(m.cursor, m.end_id, limit)) as { id: string }[];
    const put = db.prepare(`INSERT INTO ${table}(id,session)
      SELECT id,session FROM decision_checks d WHERE d.id=CAST(?1 AS INTEGER)
        AND NOT EXISTS (SELECT 1 FROM ${table} l WHERE l.id=d.id)`);
    for (const row of rows) put.run(row.id);
    const done = rows.length < limit;
    db.prepare(`UPDATE ${table}_meta SET cursor=CAST(? AS INTEGER),complete=? WHERE id=1`)
      .run(rows.at(-1)?.id ?? m.cursor, done ? 1 : 0);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export const decisionSessionIndexStep = (db: DatabaseSync, limit = BATCH) => sessionIndexStep(db, "legacy_decision_session", limit);
export const decisionSessionRepairStep = (db: DatabaseSync, limit = BATCH) => sessionIndexStep(db, "legacy_decision_session_repair", limit);
export function decisionSessionIndexNeedsWork(db: DatabaseSync): boolean {
  return hasLegacyDecisionSession(db) && meta(db, "legacy_decision_session").complete === 0;
}
export function decisionSessionRepairNeedsWork(db: DatabaseSync): boolean {
  const state = sessionState(db, "legacy_decision_session_repair");
  return state === 2 || (state === 0 && hasDecisionSessionRepair(db));
}
