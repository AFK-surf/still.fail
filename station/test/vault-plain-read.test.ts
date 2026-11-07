import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PlainStore } from "../src/vault/plain.ts";

test("plain item and limit reads see other connections' changes and respect a transaction snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-plain-read-")), path = join(dir, "db");
  const db = new DatabaseSync(path), other = new DatabaseSync(path);
  try {
    db.exec("PRAGMA journal_mode=WAL");
    const plain = new PlainStore(db), writer = new PlainStore(other);
    const item = { ws: "w", id: "i", owner: "owner@example.com", version: 0, kind: "token" as const, name: "first",
      fields: { value: "test-only" }, notes: "", listing: { name: "first", kind: "token" as const, modes: ["env" as const], hosts: [] }, at: 1 };
    writer.put(item);
    assert.equal(writer.setLasts("w", item.owner, "once", 1), null);
    assert.equal(plain.itemSnapshot("w", "i")?.value.name, "first");
    assert.deepEqual(plain.lasts("w", item.owner), { lasts: "once", at: 1 });
    assert.equal(plain.itemSnapshot("other", "i"), null);
    assert.equal(plain.lasts("other", item.owner), null);

    writer.put({ ...item, version: 1, name: "second" });
    assert.equal(writer.setLasts("w", item.owner, "hour", 2), null);
    assert.equal(plain.itemSnapshot("w", "i")?.value.name, "second");
    assert.deepEqual(plain.lasts("w", item.owner), { lasts: "hour", at: 2 });

    db.exec("BEGIN");
    assert.equal(plain.itemSnapshot("w", "i")?.value.name, "second");
    writer.put({ ...item, version: 2, name: "third" });
    assert.equal(writer.setLasts("w", item.owner, "chat", 3), null);
    assert.equal(plain.itemSnapshot("w", "i")?.value.name, "second");
    assert.deepEqual(plain.lasts("w", item.owner), { lasts: "hour", at: 2 });
    db.exec("COMMIT");
    assert.equal(plain.itemSnapshot("w", "i")?.value.name, "third");
    assert.deepEqual(plain.lasts("w", item.owner), { lasts: "chat", at: 3 });
    other.exec("ALTER TABLE vault_plain ADD COLUMN extra TEXT; ALTER TABLE vault_plain_lasts ADD COLUMN extra TEXT");
    assert.equal(plain.itemSnapshot("w", "i")?.value.name, "third");
    assert.deepEqual(plain.lasts("w", item.owner), { lasts: "chat", at: 3 });
    other.exec("DELETE FROM vault_plain; DELETE FROM vault_plain_lasts");
    assert.equal(plain.itemSnapshot("w", "i"), null);
    assert.equal(plain.lasts("w", item.owner), null);
  } finally { other.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});
