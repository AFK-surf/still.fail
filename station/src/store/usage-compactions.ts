// Main-thread calls and the compaction at each call. Old calls are added in bounded transactions off the main thread;
// inserting or deleting a call can change only that call and its immediate successor.
import type { DatabaseSync } from "node:sqlite";
import { COMPACTED_FROM } from "./rows.ts";
import { retiredUsage } from "./usage-retire.ts";

// The old append-only table remains available to older station versions. Its former trigger looked backward through
// subagent calls; its replacement takes the result already maintained in the main-call index.
const KEEP_NEW_CALLS = `
DROP TRIGGER IF EXISTS usage_compactions_add;
CREATE TRIGGER usage_compactions_add AFTER INSERT ON usage WHEN NEW.subagent = 0 BEGIN
  INSERT OR IGNORE INTO usage_main_calls VALUES (NEW.session, NEW.at, NEW.id, NEW.profile, NEW.model, NEW.context);
  INSERT INTO usage_compactions SELECT at, model, point FROM usage_compaction_events WHERE id = NEW.id;
END;
`;

const SCHEMA = `
CREATE TABLE usage_main_calls (
  session TEXT NOT NULL, at INTEGER NOT NULL, id TEXT NOT NULL, profile TEXT, model TEXT, context INTEGER,
  PRIMARY KEY (session, at, id)
) WITHOUT ROWID;
CREATE TABLE usage_compaction_events (id TEXT PRIMARY KEY, at INTEGER NOT NULL, model TEXT NOT NULL, point INTEGER NOT NULL) WITHOUT ROWID;
CREATE INDEX usage_compaction_events_at ON usage_compaction_events (at);
CREATE TABLE usage_compaction_backfill (id INTEGER PRIMARY KEY CHECK (id = 1), after_rowid INTEGER, end_rowid INTEGER, done INTEGER NOT NULL);
INSERT INTO usage_compaction_backfill SELECT 1, NULL, MAX(rowid), COUNT(*) = 0 FROM (SELECT rowid FROM usage ORDER BY rowid DESC LIMIT 1);

CREATE TRIGGER usage_main_calls_add AFTER INSERT ON usage_main_calls BEGIN
  INSERT INTO usage_compaction_events
    SELECT NEW.id, NEW.at, NEW.model, p.context FROM (
      SELECT context, profile, model FROM usage_main_calls
      WHERE session = NEW.session AND (at, id) < (NEW.at, NEW.id) ORDER BY at DESC, id DESC LIMIT 1) p
    WHERE NEW.model IS NOT NULL AND p.context >= ${COMPACTED_FROM} AND NEW.context * 2 < p.context
      AND p.profile IS NEW.profile AND p.model IS NEW.model;
  DELETE FROM usage_compaction_events WHERE id = (
    SELECT id FROM usage_main_calls WHERE session = NEW.session AND (at, id) > (NEW.at, NEW.id) ORDER BY at, id LIMIT 1);
  INSERT INTO usage_compaction_events
    SELECT n.id, n.at, n.model, NEW.context FROM (
      SELECT id, at, model, profile, context FROM usage_main_calls
      WHERE session = NEW.session AND (at, id) > (NEW.at, NEW.id) ORDER BY at, id LIMIT 1) n
    WHERE n.model IS NOT NULL AND NEW.context >= ${COMPACTED_FROM} AND n.context * 2 < NEW.context
      AND NEW.profile IS n.profile AND NEW.model IS n.model;
END;
CREATE TRIGGER usage_main_calls_drop AFTER DELETE ON usage_main_calls BEGIN
  DELETE FROM usage_compaction_events WHERE id = OLD.id;
  DELETE FROM usage_compaction_events WHERE id = (
    SELECT id FROM usage_main_calls WHERE session = OLD.session AND (at, id) > (OLD.at, OLD.id) ORDER BY at, id LIMIT 1);
  INSERT INTO usage_compaction_events
    SELECT n.id, n.at, n.model, p.context FROM (
      SELECT id, at, model, profile, context FROM usage_main_calls
      WHERE session = OLD.session AND (at, id) > (OLD.at, OLD.id) ORDER BY at, id LIMIT 1) n,
    (SELECT context, profile, model FROM usage_main_calls
      WHERE session = OLD.session AND (at, id) < (OLD.at, OLD.id) ORDER BY at DESC, id DESC LIMIT 1) p
    WHERE n.model IS NOT NULL AND p.context >= ${COMPACTED_FROM} AND n.context * 2 < p.context
      AND p.profile IS n.profile AND p.model IS n.model;
END;
CREATE TRIGGER usage_main_calls_usage_drop AFTER DELETE ON usage WHEN OLD.subagent = 0 BEGIN
  DELETE FROM usage_main_calls WHERE session = OLD.session AND at = OLD.at AND id = OLD.id;
END;
CREATE TRIGGER usage_main_calls_usage_change AFTER UPDATE OF id, session, at, profile, model, context, subagent ON usage BEGIN
  DELETE FROM usage_main_calls WHERE OLD.subagent = 0 AND session = OLD.session AND at = OLD.at AND id = OLD.id;
  INSERT OR IGNORE INTO usage_main_calls
    SELECT NEW.session, NEW.at, NEW.id, NEW.profile, NEW.model, NEW.context WHERE NEW.subagent = 0;
END;
${KEEP_NEW_CALLS}
`;

/// Install only empty tables and triggers. The last old row is found by rowid, not by scanning history.
export function installUsageCompactions(db: DatabaseSync): void {
  if (retiredUsage(db)) return;
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_compaction_backfill'").get() !== undefined;
  const triggerCurrent = () => ((db.prepare("SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = 'usage_compactions_add'").get() as { sql: string } | undefined)?.sql ?? "").includes("INSERT OR IGNORE INTO usage_main_calls");
  if (installed() && triggerCurrent()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(SCHEMA);
    else if (!triggerCurrent()) db.exec(KEEP_NEW_CALLS);
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}

export function usageCompactionsReady(db: DatabaseSync): boolean {
  if (retiredUsage(db)) return false;
  return (db.prepare("SELECT done FROM usage_compaction_backfill WHERE id = 1").get() as { done: number }).done === 1;
}

/// The cursor, calls and resulting compactions commit together. New writes are indexed by the trigger even if their
/// rowid falls inside the remaining range; INSERT OR IGNORE makes a later pass over one harmless.
export function backfillUsageCompactions(db: DatabaseSync, limit = 32): { done: boolean; processed: number } {
  db.exec("BEGIN IMMEDIATE");
  try {
    const state = db.prepare("SELECT after_rowid, end_rowid, done FROM usage_compaction_backfill WHERE id = 1").get() as { after_rowid: number | null; end_rowid: number; done: number };
    if (state.done) {
      db.exec("COMMIT");
      return { done: true, processed: 0 };
    }
    const columns = "SELECT rowid, session, at, id, profile, model, context, subagent FROM usage";
    const rows = (state.after_rowid === null
      ? db.prepare(`${columns} WHERE rowid <= ? ORDER BY rowid LIMIT ?`).all(state.end_rowid, limit)
      : db.prepare(`${columns} WHERE rowid > ? AND rowid <= ? ORDER BY rowid LIMIT ?`).all(state.after_rowid, state.end_rowid, limit)) as {
        rowid: number; session: string; at: number; id: string; profile: string | null; model: string | null; context: number | null; subagent: number;
      }[];
    const insert = db.prepare("INSERT OR IGNORE INTO usage_main_calls VALUES (?, ?, ?, ?, ?, ?)");
    for (const r of rows) if (r.subagent === 0) insert.run(r.session, r.at, r.id, r.profile, r.model, r.context);
    const after = rows.at(-1)?.rowid ?? state.end_rowid;
    const done = rows.length < limit || after >= state.end_rowid;
    db.prepare("UPDATE usage_compaction_backfill SET after_rowid = ?, done = ? WHERE id = 1").run(after, done ? 1 : 0);
    db.exec("COMMIT");
    return { done, processed: rows.length };
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}
