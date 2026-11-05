// Pending vault requests: filled a bounded batch at a time from old requests and maintained with each change.
// Creating an ordinary SQLite index over the old table would scan and sort the entire history at station startup.
import type { DatabaseSync } from "node:sqlite";

// `save` follows JavaScript truthiness: a plain-library request or a save is decided by its owner, a use of a vault
// by its current members. In particular an old null, false, zero or empty-string save is not a save.
const ownerDecision = (body: string) => `json_extract(${body}, '$.vault') = 'plain' OR CASE json_type(${body}, '$.save')
  WHEN 'object' THEN 1 WHEN 'array' THEN 1 WHEN 'true' THEN 1
  WHEN 'text' THEN length(json_extract(${body}, '$.save')) > 0
  WHEN 'integer' THEN json_extract(${body}, '$.save') != 0
  WHEN 'real' THEN json_extract(${body}, '$.save') != 0 ELSE 0 END`;

const values = (row: string) => `${row}.ws, ${row}.id, json_extract(${row}.body, '$.owner'), json_extract(${row}.body, '$.vault'),
  CASE WHEN ${ownerDecision(`${row}.body`)} THEN 1 ELSE 0 END, json_extract(${row}.body, '$.at')`;

const changed = `OLD.ws IS NOT NEW.ws OR OLD.id IS NOT NEW.id OR OLD.status IS NOT NEW.status
  OR json_extract(OLD.body, '$.owner') IS NOT json_extract(NEW.body, '$.owner')
  OR json_extract(OLD.body, '$.vault') IS NOT json_extract(NEW.body, '$.vault')
  OR json_type(OLD.body, '$.save') IS NOT json_type(NEW.body, '$.save')
  OR json_extract(OLD.body, '$.save') IS NOT json_extract(NEW.body, '$.save')
  OR json_extract(OLD.body, '$.at') IS NOT json_extract(NEW.body, '$.at')`;

const SCHEMA = `
CREATE TABLE IF NOT EXISTS vault_pending_lookup (
  ws TEXT NOT NULL, id TEXT NOT NULL, owner TEXT, vault TEXT, owner_decides INTEGER NOT NULL, at,
  PRIMARY KEY (ws, id)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS vault_pending_owner ON vault_pending_lookup (ws, owner_decides, owner, id);
CREATE INDEX IF NOT EXISTS vault_pending_vault ON vault_pending_lookup (ws, owner_decides, vault, id);
CREATE INDEX IF NOT EXISTS vault_pending_at ON vault_pending_lookup (ws, at, id);
CREATE TABLE IF NOT EXISTS vault_pending_backfill (
  ws TEXT PRIMARY KEY, after_id TEXT, done INTEGER NOT NULL
) WITHOUT ROWID;
CREATE TRIGGER IF NOT EXISTS vault_pending_add AFTER INSERT ON vault_requests WHEN NEW.status = 'pending' BEGIN
  INSERT OR REPLACE INTO vault_pending_lookup VALUES (${values("NEW")});
END;
CREATE TRIGGER IF NOT EXISTS vault_pending_change AFTER UPDATE ON vault_requests WHEN ${changed} BEGIN
  DELETE FROM vault_pending_lookup WHERE ws = OLD.ws AND id = OLD.id;
  INSERT OR REPLACE INTO vault_pending_lookup SELECT ${values("NEW")} WHERE NEW.status = 'pending';
END;
CREATE TRIGGER IF NOT EXISTS vault_pending_drop AFTER DELETE ON vault_requests BEGIN
  DELETE FROM vault_pending_lookup WHERE ws = OLD.ws AND id = OLD.id;
END;
`;

export const PENDING_BODIES = `SELECT r.body FROM vault_pending_lookup p
  JOIN vault_requests r ON r.ws = p.ws AND r.id = p.id WHERE p.ws = ? ORDER BY p.id`;
export const PENDING_BACKFILL_AFTER = "SELECT id FROM vault_requests WHERE ws = ? AND id > ? ORDER BY id LIMIT ?";

export function initializePendingIndex(db: DatabaseSync): void {
  db.exec(SCHEMA);
}

export function pendingIndexComplete(db: DatabaseSync, ws: string): boolean {
  return (db.prepare("SELECT done FROM vault_pending_backfill WHERE ws = ?").get(ws) as { done: number } | undefined)?.done === 1;
}

/// One transaction reads at most `limit` old request ids. The triggers keep writes ahead of and behind its cursor.
export function backfillPendingIndex(db: DatabaseSync, ws: string, limit = 32): boolean {
  db.exec("BEGIN IMMEDIATE");
  try {
    db.prepare("INSERT OR IGNORE INTO vault_pending_backfill (ws, after_id, done) VALUES (?, NULL, 0)").run(ws);
    const state = db.prepare("SELECT after_id, done FROM vault_pending_backfill WHERE ws = ?").get(ws) as { after_id: string | null; done: number };
    if (state.done) {
      db.exec("COMMIT");
      return true;
    }
    const rows = (state.after_id === null
      ? db.prepare("SELECT id FROM vault_requests WHERE ws = ? ORDER BY id LIMIT ?").all(ws, limit)
      : db.prepare(PENDING_BACKFILL_AFTER).all(ws, state.after_id, limit)) as { id: string }[];
    const add = db.prepare(`INSERT OR IGNORE INTO vault_pending_lookup
      SELECT ${values("r")} FROM vault_requests r WHERE r.ws = ? AND r.id = ? AND r.status = 'pending'`);
    for (const row of rows) add.run(ws, row.id);
    const done = rows.length < limit;
    db.prepare("UPDATE vault_pending_backfill SET after_id = ?, done = ? WHERE ws = ?")
      .run(rows.at(-1)?.id ?? state.after_id, done ? 1 : 0, ws);
    db.exec("COMMIT");
    return done;
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}
