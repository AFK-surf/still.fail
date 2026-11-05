// The current members of each vault, for finding a member's vaults without reading everyone else's.
// Old vaults are filled in small transactions; triggers keep versions written on either side of the cursor current.
import type { DatabaseSync } from "node:sqlite";

const SCHEMA = `
CREATE TABLE IF NOT EXISTS vault_member_lookup (
  ws TEXT NOT NULL, sub TEXT NOT NULL, vault TEXT NOT NULL, PRIMARY KEY (ws, sub, vault)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS vault_member_backfill (
  ws TEXT PRIMARY KEY, after_id TEXT, done INTEGER NOT NULL
) WITHOUT ROWID;
CREATE TRIGGER IF NOT EXISTS vault_member_add AFTER INSERT ON vaults BEGIN
  INSERT INTO vault_member_lookup
    SELECT NEW.ws, m.value, NEW.id FROM json_each(NEW.body, '$.members') m WHERE m.type = 'text'
    ON CONFLICT(ws, sub, vault) DO NOTHING;
END;
CREATE TRIGGER IF NOT EXISTS vault_member_change AFTER UPDATE ON vaults
  WHEN OLD.ws IS NOT NEW.ws OR OLD.id IS NOT NEW.id
    OR json_extract(OLD.body, '$.members') IS NOT json_extract(NEW.body, '$.members') BEGIN
  DELETE FROM vault_member_lookup WHERE ws = OLD.ws AND vault = OLD.id AND sub IN
    (SELECT value FROM json_each(OLD.body, '$.members') WHERE type = 'text');
  INSERT INTO vault_member_lookup
    SELECT NEW.ws, m.value, NEW.id FROM json_each(NEW.body, '$.members') m WHERE m.type = 'text'
    ON CONFLICT(ws, sub, vault) DO NOTHING;
END;
CREATE TRIGGER IF NOT EXISTS vault_member_drop AFTER DELETE ON vaults BEGIN
  DELETE FROM vault_member_lookup WHERE ws = OLD.ws AND vault = OLD.id AND sub IN
    (SELECT value FROM json_each(OLD.body, '$.members') WHERE type = 'text');
END;
`;

export function initializeVaultMembers(db: DatabaseSync): void {
  db.exec("SAVEPOINT vault_member_schema");
  try {
    db.exec(SCHEMA);
    db.exec("RELEASE vault_member_schema");
  } catch (error) {
    db.exec("ROLLBACK TO vault_member_schema");
    db.exec("RELEASE vault_member_schema");
    throw error;
  }
}

export function vaultMembersComplete(db: DatabaseSync, ws: string): boolean {
  return (db.prepare("SELECT done FROM vault_member_backfill WHERE ws = ?").get(ws) as { done: number } | undefined)?.done === 1;
}

/// Consider at most `limit` vaults. The cursor and their entries commit together.
export function backfillVaultMembers(db: DatabaseSync, ws: string, limit = 32): boolean {
  db.exec("BEGIN IMMEDIATE");
  try {
    db.prepare("INSERT OR IGNORE INTO vault_member_backfill (ws, after_id, done) VALUES (?, NULL, 0)").run(ws);
    const state = db.prepare("SELECT after_id, done FROM vault_member_backfill WHERE ws = ?").get(ws) as { after_id: string | null; done: number };
    if (state.done) {
      db.exec("COMMIT");
      return true;
    }
    const rows = (state.after_id === null
      ? db.prepare("SELECT id FROM vaults WHERE ws = ? ORDER BY id LIMIT ?").all(ws, limit)
      : db.prepare("SELECT id FROM vaults WHERE ws = ? AND id > ? ORDER BY id LIMIT ?").all(ws, state.after_id, limit)) as { id: string }[];
    const add = db.prepare(`INSERT OR IGNORE INTO vault_member_lookup
      SELECT v.ws, m.value, v.id FROM vaults v JOIN json_each(v.body, '$.members') m
      WHERE v.ws = ? AND v.id = ? AND m.type = 'text'`);
    for (const row of rows) add.run(ws, row.id);
    const done = rows.length < limit;
    db.prepare("UPDATE vault_member_backfill SET after_id = ?, done = ? WHERE ws = ?")
      .run(rows.at(-1)?.id ?? state.after_id, done ? 1 : 0, ws);
    db.exec("COMMIT");
    return done;
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}
