import type { DatabaseSync } from "node:sqlite";

/// A store written before the per-login lookup was added.
export function withoutLoginKeys(db: DatabaseSync): void {
  db.exec(`DROP TRIGGER IF EXISTS login_card_keys_insert;
    DROP TRIGGER IF EXISTS login_card_keys_update_same;
    DROP TRIGGER IF EXISTS login_card_keys_update_moved;
    DROP TRIGGER IF EXISTS login_card_keys_delete;
    DROP TABLE IF EXISTS login_card_meta;
    DROP TABLE IF EXISTS login_card_keys;`);
}
