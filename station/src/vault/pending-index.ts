// Pending vault requests: filled a bounded batch at a time from old requests and maintained with each change.
// Creating an ordinary SQLite index over the old table would scan and sort the entire history at station startup.
import type { DatabaseSync } from "node:sqlite";
import { backfillVaultMembers, vaultMembersComplete } from "./member-index.ts";

// `save` follows JavaScript truthiness: a plain-library request or a save is decided by its owner, a use of a vault
// by its current members. In particular an old null, false, zero or empty-string save is not a save.
const ownerDecision = (body: string) => `json_extract(${body}, '$.vault') = 'plain' OR CASE json_type(${body}, '$.save')
  WHEN 'object' THEN 1 WHEN 'array' THEN 1 WHEN 'true' THEN 1
  WHEN 'text' THEN json_extract(${body}, '$.save') != ''
  WHEN 'integer' THEN json_extract(${body}, '$.save') != 0
  WHEN 'real' THEN json_extract(${body}, '$.save') != 0 ELSE 0 END`;

const decidesByOwner = (body: string) => `CASE WHEN ${ownerDecision(body)} THEN 1 ELSE 0 END`;
const decisionTarget = (body: string) => `CASE WHEN ${ownerDecision(body)}
  THEN json_extract(${body}, '$.owner') ELSE json_extract(${body}, '$.vault') END`;
const values = (row: string) => `${row}.ws, ${row}.id, ${decidesByOwner(`${row}.body`)},
  ${decisionTarget(`${row}.body`)}, json_extract(${row}.body, '$.at')`;

const changed = `OLD.ws IS NOT NEW.ws OR OLD.id IS NOT NEW.id OR OLD.status IS NOT NEW.status
  OR (${decidesByOwner("OLD.body")}) IS NOT (${decidesByOwner("NEW.body")})
  OR (${decisionTarget("OLD.body")}) IS NOT (${decisionTarget("NEW.body")})
  OR json_extract(OLD.body, '$.at') IS NOT json_extract(NEW.body, '$.at')`;

const SCHEMA = `
CREATE TABLE IF NOT EXISTS vault_pending_lookup (
  ws TEXT NOT NULL, id TEXT NOT NULL, owner_decides INTEGER NOT NULL, decider TEXT, at,
  PRIMARY KEY (ws, id)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS vault_pending_decider ON vault_pending_lookup (ws, owner_decides, decider, id);
CREATE INDEX IF NOT EXISTS vault_pending_at ON vault_pending_lookup (ws, at, id);
CREATE TABLE IF NOT EXISTS vault_pending_backfill (
  ws TEXT PRIMARY KEY, after_id TEXT, done INTEGER NOT NULL
) WITHOUT ROWID;
CREATE TRIGGER IF NOT EXISTS vault_pending_add AFTER INSERT ON vault_requests
  WHEN NEW.status = 'pending' AND EXISTS (SELECT 1 FROM vault_pending_backfill WHERE ws = NEW.ws) BEGIN
  INSERT OR REPLACE INTO vault_pending_lookup VALUES (${values("NEW")});
END;
CREATE TRIGGER IF NOT EXISTS vault_pending_change AFTER UPDATE ON vault_requests
  WHEN CASE WHEN (EXISTS (SELECT 1 FROM vault_pending_backfill WHERE ws = OLD.ws)
      OR EXISTS (SELECT 1 FROM vault_pending_backfill WHERE ws = NEW.ws))
    AND (OLD.status = 'pending' OR NEW.status = 'pending') THEN (${changed}) ELSE 0 END BEGIN
  DELETE FROM vault_pending_lookup WHERE ws = OLD.ws AND id = OLD.id;
  INSERT OR REPLACE INTO vault_pending_lookup SELECT ${values("NEW")}
    WHERE NEW.status = 'pending' AND EXISTS (SELECT 1 FROM vault_pending_backfill WHERE ws = NEW.ws);
END;
CREATE TRIGGER IF NOT EXISTS vault_pending_drop AFTER DELETE ON vault_requests
  WHEN OLD.status = 'pending' AND EXISTS (SELECT 1 FROM vault_pending_backfill WHERE ws = OLD.ws) BEGIN
  DELETE FROM vault_pending_lookup WHERE ws = OLD.ws AND id = OLD.id;
END;
`;

export const PENDING_BODIES = `SELECT r.body FROM vault_pending_lookup p
  JOIN vault_requests r ON r.ws = p.ws AND r.id = p.id WHERE p.ws = ? ORDER BY p.id`;
export const PENDING_OWN = `SELECT r.id, r.body FROM vault_pending_lookup p INDEXED BY vault_pending_decider
  JOIN vault_requests r ON r.ws = p.ws AND r.id = p.id
  WHERE p.ws = ? AND p.owner_decides = 1 AND p.decider = ?`;
// CROSS JOIN keeps the member's vaults on the outside: no scan of other vaults' waiting requests.
export const PENDING_MEMBER = `SELECT r.id, r.body FROM vault_member_lookup m
  CROSS JOIN vault_pending_lookup p INDEXED BY vault_pending_decider
  JOIN vault_requests r ON r.ws = p.ws AND r.id = p.id
  WHERE m.ws = ? AND m.sub = ? AND p.ws = m.ws AND p.owner_decides = 0 AND p.decider = m.vault`;
export const PENDING_DUE = `SELECT r.id, r.body FROM vault_pending_lookup p INDEXED BY vault_pending_at
  JOIN vault_requests r ON r.ws = p.ws AND r.id = p.id WHERE p.ws = ? AND p.at <= ?`;
// Old malformed timestamps are tested in JavaScript too. Restrict each query to the relevant index range.
export const PENDING_NO_TIME = `SELECT r.id, r.body FROM vault_pending_lookup p INDEXED BY vault_pending_at
  JOIN vault_requests r ON r.ws = p.ws AND r.id = p.id WHERE p.ws = ? AND p.at IS NULL`;
export const PENDING_OTHER_TIME = `SELECT r.id, r.body FROM vault_pending_lookup p INDEXED BY vault_pending_at
  JOIN vault_requests r ON r.ws = p.ws AND r.id = p.id WHERE p.ws = ? AND p.at >= ''`;
export const PENDING_SEED_FIRST = `SELECT r.id, r.body FROM vault_pending_lookup p
  JOIN vault_requests r ON r.ws = p.ws AND r.id = p.id WHERE p.ws = ? ORDER BY p.id LIMIT ?`;
export const PENDING_SEED = `SELECT r.id, r.body FROM vault_pending_lookup p
  JOIN vault_requests r ON r.ws = p.ws AND r.id = p.id WHERE p.ws = ? AND p.id > ? ORDER BY p.id LIMIT ?`;
export const PENDING_BACKFILL_AFTER = "SELECT id FROM vault_requests WHERE ws = ? AND id > ? ORDER BY id LIMIT ?";
export function initializePendingIndex(db: DatabaseSync): void {
  db.exec("SAVEPOINT vault_pending_schema");
  try {
    db.exec(SCHEMA);
    db.exec("RELEASE vault_pending_schema");
  } catch (error) {
    db.exec("ROLLBACK TO vault_pending_schema");
    db.exec("RELEASE vault_pending_schema");
    throw error;
  }
}

export function pendingIndexComplete(db: DatabaseSync, ws: string): boolean {
  return (db.prepare("SELECT done FROM vault_pending_backfill WHERE ws = ?").get(ws) as { done: number } | undefined)?.done === 1;
}

// Test and embedded stores can use Secrets without a VaultStore. A real VaultStore creates this lookup with vaults.
export function hasVaultMembers(db: DatabaseSync): boolean {
  return db.prepare("SELECT 1 FROM sqlite_schema WHERE type = 'table' AND name = 'vault_member_backfill'").get() !== undefined;
}

export function pendingPreparationComplete(db: DatabaseSync, ws: string, members: boolean): boolean {
  return pendingIndexComplete(db, ws) && (!members || !hasVaultMembers(db) || vaultMembersComplete(db, ws));
}

/// At most one request or vault batch per turn, so both share the worker fairly with foreground writes.
export function backfillPendingPreparation(db: DatabaseSync, ws: string, members: boolean): boolean {
  if (!pendingIndexComplete(db, ws)) {
    if (!backfillPendingIndex(db, ws)) return false;
    return !members || !hasVaultMembers(db) || vaultMembersComplete(db, ws);
  }
  return !members || !hasVaultMembers(db) || vaultMembersComplete(db, ws) || backfillVaultMembers(db, ws);
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
