// The current members of each vault, for finding a member's vaults without reading everyone else's.
// Old vaults are filled in small transactions; triggers keep versions written on either side of the cursor current.
import type { DatabaseSync } from "node:sqlite";
import { installSchema } from "./schema-install.ts";

// Old databases may contain unreadable vault bodies. Keep those separate so they neither stop another vault's
// preparation nor silently change the old request-list behavior when one of them is actually referenced.
const validMembers = (body: string) => `CASE WHEN json_valid(${body}) THEN
  CASE WHEN json_type(${body}, '$.members') = 'array' THEN 1 ELSE 0 END ELSE 0 END`;
const membersBody = (body: string) => `CASE WHEN (${validMembers(body)}) = 1 THEN ${body} ELSE '{"members":[]}' END`;
// SQLite's json_extract picks the first duplicate key, while JSON.parse uses the last one. Until the old index is
// rebuilt with those semantics, a workspace containing such a body must use the original request scan.
const duplicateMembers = (body: string) => `CASE WHEN json_valid(${body}) THEN EXISTS
  (SELECT 1 FROM json_each(${body}) WHERE key = 'members' LIMIT 1 OFFSET 1) ELSE 0 END`;
// A JSON path matches only the prefix before a NUL in an object key, unlike JavaScript property lookup.
const nulMembers = (body: string) => `CASE WHEN instr(${body}, '\\u0000') > 0 AND json_valid(${body}) THEN EXISTS
  (SELECT 1 FROM json_each(${body}) WHERE instr(key, char(0)) > 0
    AND substr(key, 1, instr(key, char(0)) - 1) = 'members') ELSE 0 END`;

const SCHEMA = `
CREATE TABLE IF NOT EXISTS vault_member_lookup (
  ws TEXT NOT NULL, sub TEXT NOT NULL, vault TEXT NOT NULL, PRIMARY KEY (ws, sub, vault)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS vault_member_invalid (
  ws TEXT NOT NULL, vault TEXT NOT NULL, PRIMARY KEY (ws, vault)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS vault_member_backfill (
  ws TEXT PRIMARY KEY, after_id TEXT, done INTEGER NOT NULL
) WITHOUT ROWID;
-- An older completed member index may already have indexed the first of two members fields. Audit it in batches;
-- triggers cover writes on both sides of the cursor, including writes from a previous Station.
CREATE TABLE IF NOT EXISTS vault_member_duplicates_v2 (
  ws TEXT NOT NULL, vault TEXT NOT NULL, PRIMARY KEY (ws, vault)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS vault_member_audit_v2 (
  ws TEXT PRIMARY KEY, after_id TEXT, done INTEGER NOT NULL
) WITHOUT ROWID;
-- Older change triggers compared only json_extract's SQL value. An array and a string containing the array's JSON
-- can have the same value, so repair old lookups and invalid markers before trusting them.
CREATE TABLE IF NOT EXISTS vault_member_type_audit_v3 (
  ws TEXT PRIMARY KEY, after_id TEXT, done INTEGER NOT NULL
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS vault_member_nul_v4 (
  ws TEXT NOT NULL, vault TEXT NOT NULL, PRIMARY KEY (ws, vault)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS vault_member_nul_audit_v4 (
  ws TEXT PRIMARY KEY, after_id TEXT, done INTEGER NOT NULL
) WITHOUT ROWID;
CREATE TRIGGER IF NOT EXISTS vault_member_add AFTER INSERT ON vaults
  WHEN EXISTS (SELECT 1 FROM vault_member_backfill WHERE ws = NEW.ws) BEGIN
  INSERT INTO vault_member_invalid SELECT NEW.ws, NEW.id WHERE (${validMembers("NEW.body")}) = 0
    ON CONFLICT(ws, vault) DO NOTHING;
  INSERT INTO vault_member_lookup
    SELECT NEW.ws, m.value, NEW.id FROM json_each(${membersBody("NEW.body")}, '$.members') m WHERE m.type = 'text'
    ON CONFLICT(ws, sub, vault) DO NOTHING;
END;
CREATE TRIGGER IF NOT EXISTS vault_member_change AFTER UPDATE ON vaults
  WHEN (OLD.ws IS NOT NEW.ws OR OLD.id IS NOT NEW.id
    OR CASE WHEN json_valid(OLD.body) AND json_valid(NEW.body)
      THEN json_extract(OLD.body, '$.members') IS NOT json_extract(NEW.body, '$.members')
      ELSE OLD.body IS NOT NEW.body END)
    AND (EXISTS (SELECT 1 FROM vault_member_backfill WHERE ws = OLD.ws)
      OR EXISTS (SELECT 1 FROM vault_member_backfill WHERE ws = NEW.ws)) BEGIN
  DELETE FROM vault_member_invalid WHERE ws = OLD.ws AND vault = OLD.id;
  INSERT INTO vault_member_invalid SELECT NEW.ws, NEW.id WHERE (${validMembers("NEW.body")}) = 0
    AND EXISTS (SELECT 1 FROM vault_member_backfill WHERE ws = NEW.ws)
    ON CONFLICT(ws, vault) DO NOTHING;
  DELETE FROM vault_member_lookup WHERE ws = OLD.ws AND vault = OLD.id AND sub IN
    (SELECT value FROM json_each(${membersBody("OLD.body")}, '$.members') WHERE type = 'text');
  INSERT INTO vault_member_lookup
    SELECT NEW.ws, m.value, NEW.id FROM json_each(${membersBody("NEW.body")}, '$.members') m WHERE m.type = 'text'
      AND EXISTS (SELECT 1 FROM vault_member_backfill WHERE ws = NEW.ws)
    ON CONFLICT(ws, sub, vault) DO NOTHING;
END;
CREATE TRIGGER IF NOT EXISTS vault_member_drop AFTER DELETE ON vaults
  WHEN EXISTS (SELECT 1 FROM vault_member_backfill WHERE ws = OLD.ws) BEGIN
  DELETE FROM vault_member_invalid WHERE ws = OLD.ws AND vault = OLD.id;
  DELETE FROM vault_member_lookup WHERE ws = OLD.ws AND vault = OLD.id AND sub IN
    (SELECT value FROM json_each(${membersBody("OLD.body")}, '$.members') WHERE type = 'text');
END;
CREATE TRIGGER IF NOT EXISTS vault_member_type_add_v3 AFTER INSERT ON vaults
  WHEN EXISTS (SELECT 1 FROM vault_member_invalid WHERE ws = NEW.ws AND vault = NEW.id)
    AND (${validMembers("NEW.body")}) = 1 BEGIN
  DELETE FROM vault_member_invalid WHERE ws = NEW.ws AND vault = NEW.id;
END;
CREATE TRIGGER IF NOT EXISTS vault_member_type_change_v3 AFTER UPDATE ON vaults
  WHEN OLD.body IS NOT NEW.body AND (${validMembers("OLD.body")}) IS NOT (${validMembers("NEW.body")})
    AND (EXISTS (SELECT 1 FROM vault_member_backfill WHERE ws = OLD.ws)
      OR EXISTS (SELECT 1 FROM vault_member_backfill WHERE ws = NEW.ws)) BEGIN
  DELETE FROM vault_member_invalid WHERE ws = OLD.ws AND vault = OLD.id;
  INSERT OR IGNORE INTO vault_member_invalid SELECT NEW.ws, NEW.id WHERE (${validMembers("NEW.body")}) = 0
    AND EXISTS (SELECT 1 FROM vault_member_backfill WHERE ws = NEW.ws);
  DELETE FROM vault_member_lookup WHERE ws = OLD.ws AND vault = OLD.id AND sub IN
    (SELECT value FROM json_each(${membersBody("OLD.body")}, '$.members') WHERE type = 'text');
  INSERT OR IGNORE INTO vault_member_lookup
    SELECT NEW.ws, m.value, NEW.id FROM json_each(${membersBody("NEW.body")}, '$.members') m WHERE m.type = 'text'
      AND EXISTS (SELECT 1 FROM vault_member_backfill WHERE ws = NEW.ws);
END;
CREATE TRIGGER IF NOT EXISTS vault_member_duplicate_add_v2 AFTER INSERT ON vaults
  WHEN EXISTS (SELECT 1 FROM vault_member_audit_v2 WHERE ws = NEW.ws) BEGIN
  DELETE FROM vault_member_duplicates_v2 WHERE ws = NEW.ws AND vault = NEW.id;
  INSERT OR IGNORE INTO vault_member_duplicates_v2 SELECT NEW.ws, NEW.id WHERE (${duplicateMembers("NEW.body")}) = 1;
END;
CREATE TRIGGER IF NOT EXISTS vault_member_duplicate_change_v2 AFTER UPDATE ON vaults
  WHEN (OLD.ws IS NOT NEW.ws OR OLD.id IS NOT NEW.id OR OLD.body IS NOT NEW.body)
    AND (EXISTS (SELECT 1 FROM vault_member_audit_v2 WHERE ws = OLD.ws)
      OR EXISTS (SELECT 1 FROM vault_member_audit_v2 WHERE ws = NEW.ws)) BEGIN
  DELETE FROM vault_member_duplicates_v2 WHERE ws = OLD.ws AND vault = OLD.id;
  DELETE FROM vault_member_duplicates_v2 WHERE ws = NEW.ws AND vault = NEW.id;
  INSERT OR IGNORE INTO vault_member_duplicates_v2 SELECT NEW.ws, NEW.id
    WHERE EXISTS (SELECT 1 FROM vault_member_audit_v2 WHERE ws = NEW.ws) AND (${duplicateMembers("NEW.body")}) = 1;
END;
CREATE TRIGGER IF NOT EXISTS vault_member_duplicate_drop_v2 AFTER DELETE ON vaults
  WHEN EXISTS (SELECT 1 FROM vault_member_audit_v2 WHERE ws = OLD.ws) BEGIN
  DELETE FROM vault_member_duplicates_v2 WHERE ws = OLD.ws AND vault = OLD.id;
END;
CREATE TRIGGER IF NOT EXISTS vault_member_nul_add_v4 AFTER INSERT ON vaults
  WHEN EXISTS (SELECT 1 FROM vault_member_nul_audit_v4 WHERE ws = NEW.ws) BEGIN
  DELETE FROM vault_member_nul_v4 WHERE ws = NEW.ws AND vault = NEW.id;
  INSERT OR IGNORE INTO vault_member_nul_v4 SELECT NEW.ws, NEW.id WHERE (${nulMembers("NEW.body")}) = 1;
END;
CREATE TRIGGER IF NOT EXISTS vault_member_nul_change_v4 AFTER UPDATE ON vaults
  WHEN (OLD.ws IS NOT NEW.ws OR OLD.id IS NOT NEW.id OR OLD.body IS NOT NEW.body)
    AND (EXISTS (SELECT 1 FROM vault_member_nul_audit_v4 WHERE ws = OLD.ws)
      OR EXISTS (SELECT 1 FROM vault_member_nul_audit_v4 WHERE ws = NEW.ws)) BEGIN
  DELETE FROM vault_member_nul_v4 WHERE ws = OLD.ws AND vault = OLD.id;
  DELETE FROM vault_member_nul_v4 WHERE ws = NEW.ws AND vault = NEW.id;
  INSERT OR IGNORE INTO vault_member_nul_v4 SELECT NEW.ws, NEW.id
    WHERE EXISTS (SELECT 1 FROM vault_member_nul_audit_v4 WHERE ws = NEW.ws) AND (${nulMembers("NEW.body")}) = 1;
END;
CREATE TRIGGER IF NOT EXISTS vault_member_nul_drop_v4 AFTER DELETE ON vaults
  WHEN EXISTS (SELECT 1 FROM vault_member_nul_audit_v4 WHERE ws = OLD.ws) BEGIN
  DELETE FROM vault_member_nul_v4 WHERE ws = OLD.ws AND vault = OLD.id;
END;
`;

export function initializeVaultMembers(db: DatabaseSync): void {
  installSchema(db, "vault_member_schema", SCHEMA);
}

export function vaultMembersComplete(db: DatabaseSync, ws: string): boolean {
  const state = db.prepare(`SELECT b.done, a.done AS audited, t.done AS type_audited, n.done AS nul_audited FROM vault_member_backfill b
    LEFT JOIN vault_member_audit_v2 a ON a.ws = b.ws LEFT JOIN vault_member_type_audit_v3 t ON t.ws = b.ws
    LEFT JOIN vault_member_nul_audit_v4 n ON n.ws = b.ws
    WHERE b.ws = ?`).get(ws) as { done: number; audited: number | null; type_audited: number | null; nul_audited: number | null } | undefined;
  return state?.done === 1 && state.audited === 1 && state.type_audited === 1 && state.nul_audited === 1;
}

/// An index begun by an older station can still be scanned around while its audit is prepared in the background.
export function vaultMembersStarted(db: DatabaseSync, ws: string): boolean {
  return db.prepare("SELECT 1 FROM vault_member_backfill WHERE ws = ?").get(ws) !== undefined;
}

// A rowid replacement can leave a marker for a removed vault when recursive triggers are off. Check only marked
// vaults, and keep that table on the outside so a normal workspace does not scan all of its vaults.
export const VAULT_MEMBERS_INVALID = `SELECT 1 FROM vault_member_invalid i CROSS JOIN vaults v ON v.ws = i.ws AND v.id = i.vault WHERE i.ws = ?
  UNION ALL SELECT 1 FROM vault_member_duplicates_v2 d CROSS JOIN vaults v ON v.ws = d.ws AND v.id = d.vault
    WHERE d.ws = ?
  UNION ALL SELECT 1 FROM vault_member_nul_v4 n CROSS JOIN vaults v ON v.ws = n.ws AND v.id = n.vault
    WHERE n.ws = ? LIMIT 1`;

export function hasInvalidVaultMembers(db: DatabaseSync, ws: string): boolean {
  return db.prepare(VAULT_MEMBERS_INVALID).get(ws, ws, ws) !== undefined;
}

/// Consider at most `limit` vaults. The cursor and their entries commit together.
export function backfillVaultMembers(db: DatabaseSync, ws: string, limit = 32): boolean {
  db.exec("BEGIN IMMEDIATE");
  try {
    db.prepare("INSERT OR IGNORE INTO vault_member_backfill (ws, after_id, done) VALUES (?, NULL, 0)").run(ws);
    db.prepare("INSERT OR IGNORE INTO vault_member_audit_v2 (ws, after_id, done) VALUES (?, NULL, 0)").run(ws);
    db.prepare("INSERT OR IGNORE INTO vault_member_type_audit_v3 (ws, after_id, done) VALUES (?, NULL, 0)").run(ws);
    db.prepare("INSERT OR IGNORE INTO vault_member_nul_audit_v4 (ws, after_id, done) VALUES (?, NULL, 0)").run(ws);
    const state = db.prepare("SELECT after_id, done FROM vault_member_backfill WHERE ws = ?").get(ws) as { after_id: string | null; done: number };
    const audit = db.prepare("SELECT after_id, done FROM vault_member_audit_v2 WHERE ws = ?").get(ws) as { after_id: string | null; done: number };
    const types = db.prepare("SELECT after_id, done FROM vault_member_type_audit_v3 WHERE ws = ?").get(ws) as { after_id: string | null; done: number };
    const nul = db.prepare("SELECT after_id, done FROM vault_member_nul_audit_v4 WHERE ws = ?").get(ws) as { after_id: string | null; done: number };
    if (state.done && audit.done && types.done && nul.done) {
      db.exec("COMMIT");
      return true;
    }
    // A new lookup and its audit advance together. An existing lookup with a different cursor is audited afterwards.
    const auditBatch = !audit.done && (state.done !== 0 || state.after_id === audit.after_id);
    const after = !state.done ? state.after_id : !audit.done ? audit.after_id : !types.done ? types.after_id : nul.after_id;
    const typeBatch = !types.done && types.after_id === after;
    const nulBatch = !nul.done && nul.after_id === after;
    const rows = (after === null
      ? db.prepare("SELECT id FROM vaults WHERE ws = ? ORDER BY id LIMIT ?").all(ws, limit)
      : db.prepare("SELECT id FROM vaults WHERE ws = ? AND id > ? ORDER BY id LIMIT ?").all(ws, after, limit)) as { id: string }[];
    const done = rows.length < limit;
    if (!state.done) {
      const invalid = db.prepare(`INSERT OR IGNORE INTO vault_member_invalid SELECT v.ws, v.id FROM vaults v
        WHERE v.ws = ? AND v.id = ? AND (${validMembers("v.body")}) = 0`);
      const add = db.prepare(`INSERT OR IGNORE INTO vault_member_lookup
        SELECT v.ws, m.value, v.id FROM vaults v JOIN json_each(${membersBody("v.body")}, '$.members') m
        WHERE v.ws = ? AND v.id = ? AND m.type = 'text'`);
      for (const row of rows) { invalid.run(ws, row.id); add.run(ws, row.id); }
      db.prepare("UPDATE vault_member_backfill SET after_id = ?, done = ? WHERE ws = ?")
        .run(rows.at(-1)?.id ?? state.after_id, done ? 1 : 0, ws);
    }
    if (auditBatch) {
      const clear = db.prepare("DELETE FROM vault_member_duplicates_v2 WHERE ws = ? AND vault = ?");
      const add = db.prepare(`INSERT OR IGNORE INTO vault_member_duplicates_v2 SELECT v.ws, v.id FROM vaults v
        WHERE v.ws = ? AND v.id = ? AND (${duplicateMembers("v.body")}) = 1`);
      for (const row of rows) { clear.run(ws, row.id); add.run(ws, row.id); }
      db.prepare("UPDATE vault_member_audit_v2 SET after_id = ?, done = ? WHERE ws = ?")
        .run(rows.at(-1)?.id ?? audit.after_id, done ? 1 : 0, ws);
    }
    if (typeBatch) {
      // The first preparation already inserted these members and marked invalid bodies. An older completed lookup
      // needs both repaired; a stale invalid marker can occur in either case.
      const clear = db.prepare(`DELETE FROM vault_member_invalid WHERE ws = ? AND vault = ? AND EXISTS
        (SELECT 1 FROM vaults v WHERE v.ws = ? AND v.id = ? AND (${validMembers("v.body")}) = 1)`);
      if (!state.done) {
        for (const row of rows) clear.run(ws, row.id, ws, row.id);
      } else {
        const add = db.prepare(`INSERT OR IGNORE INTO vault_member_lookup
          SELECT v.ws, m.value, v.id FROM vaults v JOIN json_each(${membersBody("v.body")}, '$.members') m
          WHERE v.ws = ? AND v.id = ? AND m.type = 'text'`);
        const invalid = db.prepare(`INSERT OR IGNORE INTO vault_member_invalid SELECT v.ws, v.id FROM vaults v
          WHERE v.ws = ? AND v.id = ? AND (${validMembers("v.body")}) = 0`);
        for (const row of rows) { add.run(ws, row.id); clear.run(ws, row.id, ws, row.id); invalid.run(ws, row.id); }
      }
      db.prepare("UPDATE vault_member_type_audit_v3 SET after_id = ?, done = ? WHERE ws = ?")
        .run(rows.at(-1)?.id ?? types.after_id, done ? 1 : 0, ws);
    }
    if (nulBatch) {
      const clear = db.prepare("DELETE FROM vault_member_nul_v4 WHERE ws = ? AND vault = ?");
      const add = db.prepare(`INSERT OR IGNORE INTO vault_member_nul_v4 SELECT v.ws, v.id FROM vaults v
        WHERE v.ws = ? AND v.id = ? AND (${nulMembers("v.body")}) = 1`);
      for (const row of rows) { clear.run(ws, row.id); add.run(ws, row.id); }
      db.prepare("UPDATE vault_member_nul_audit_v4 SET after_id = ?, done = ? WHERE ws = ?")
        .run(rows.at(-1)?.id ?? nul.after_id, done ? 1 : 0, ws);
    }
    db.exec("COMMIT");
    return (state.done !== 0 || done) && (audit.done !== 0 || (auditBatch && done))
      && (types.done !== 0 || (typeBatch && done)) && (nul.done !== 0 || (nulBatch && done));
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}
