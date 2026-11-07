import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { backfillVaultMembers } from "../src/vault/member-index.ts";
import { VaultStore } from "../src/vault/store.ts";

function fixture() {
  const db = new DatabaseSync(":memory:");
  const vaults = new VaultStore(db);
  const vault = { ws: "w", id: "v", seq: 0, owner: "alice", members: ["alice"], epoch: 0 };
  const deleted = { ...vault, seq: 1, epoch: 1, members: [], deleted: true };
  const item = { ws: "w", vault: "v", id: "i", version: 0, epoch: 0 };
  vaults.putVault(vault as never);
  vaults.putItem(item as never);
  return { db, vaults, vault, deleted, item };
}

test("a failed deletion does not leave a deleted vault with its old items", () => {
  const f = fixture();
  try {
    backfillVaultMembers(f.db, "w");
    f.db.exec("CREATE TRIGGER reject_item_deletion BEFORE DELETE ON vault_items BEGIN SELECT RAISE(ABORT, 'cannot delete'); END");
    assert.throws(() => f.vaults.putVault(f.deleted as never), /cannot delete/);
    assert.deepEqual(f.vaults.vault("w", "v"), f.vault);
    assert.deepEqual(f.vaults.items("w", "v"), [f.item]);
    assert.equal(f.db.prepare("SELECT 1 FROM vault_member_lookup WHERE ws=? AND sub=? AND vault=?").get("w", "alice", "v") !== undefined, true);
    f.db.exec("DROP TRIGGER reject_item_deletion");
    f.vaults.putVault(f.deleted as never);
    assert.deepEqual(f.vaults.vault("w", "v"), f.deleted);
    assert.deepEqual(f.vaults.items("w", "v"), []);
  } finally { f.db.close(); }
});

test("vault deletion can be rolled back by an enclosing transaction", () => {
  const f = fixture();
  try {
    f.db.exec("BEGIN IMMEDIATE");
    f.vaults.putVault(f.deleted as never);
    assert.deepEqual(f.vaults.items("w", "v"), []);
    f.db.exec("ROLLBACK");
    assert.deepEqual(f.vaults.vault("w", "v"), f.vault);
    assert.deepEqual(f.vaults.items("w", "v"), [f.item]);
  } finally { f.db.close(); }
});
