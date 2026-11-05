import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { backfillVaultMembers, initializeVaultMembers, vaultMembersComplete } from "../src/vault/member-index.ts";

function fixture() {
  const db = new DatabaseSync(":memory:");
  db.exec("CREATE TABLE vaults (ws TEXT NOT NULL, id TEXT NOT NULL, seq INTEGER NOT NULL, body TEXT NOT NULL, PRIMARY KEY (ws, id))");
  const put = (ws: string, id: string, members: string[], seq = 0) => db.prepare("INSERT INTO vaults VALUES (?,?,?,?) ON CONFLICT(ws,id) DO UPDATE SET seq=excluded.seq,body=excluded.body")
    .run(ws, id, seq, JSON.stringify({ ws, id, members, seq }));
  const members = (ws: string, sub: string) => db.prepare("SELECT vault FROM vault_member_lookup WHERE ws=? AND sub=? ORDER BY vault").all(ws, sub).map((v) => v.vault);
  return { db, put, members };
}

test("old vault members are prepared in bounded batches while changes on either side stay current", () => {
  const { db, put, members } = fixture();
  try {
    for (let i = 0; i < 6; i++) put("w", `v${i}`, [i % 2 ? "bob" : "alice"]);
    put("other", "v", ["alice"]);
    initializeVaultMembers(db);
    assert.equal(backfillVaultMembers(db, "w", 2), false);
    put("w", "v0", ["bob"], 1);
    put("w", "v1", ["alice", "alice"], 1);
    put("w", "v5", ["alice"], 1);
    db.prepare("DELETE FROM vaults WHERE ws='w' AND id='v4'").run();
    while (!backfillVaultMembers(db, "w", 2)) {}
    assert.equal(vaultMembersComplete(db, "w"), true);
    assert.equal(vaultMembersComplete(db, "other"), false);
    assert.deepEqual(members("w", "alice"), ["v1", "v2", "v5"]);
    assert.deepEqual(members("w", "bob"), ["v0", "v3"]);
    assert.deepEqual(members("other", "alice"), []);
    while (!backfillVaultMembers(db, "other", 2)) {}
    assert.deepEqual(members("other", "alice"), ["v"]);
    const plan = (db.prepare("EXPLAIN QUERY PLAN SELECT vault FROM vault_member_lookup WHERE ws=? AND sub=? ORDER BY vault").all("w", "alice") as { detail: string }[]).map((r) => r.detail).join("\n");
    assert.match(plan, /SEARCH vault_member_lookup USING PRIMARY KEY/);
  } finally { db.close(); }
});

test("a vault version with unchanged members does not rewrite their lookup", () => {
  const { db, put, members } = fixture();
  try {
    initializeVaultMembers(db);
    backfillVaultMembers(db, "w");
    put("w", "v", ["alice", "bob"]);
    const count = () => (db.prepare("SELECT total_changes() AS n").get() as { n: number }).n;
    const before = count();
    put("w", "v", ["alice", "bob"], 1);
    assert.equal(count() - before, 1);
    assert.deepEqual(members("w", "alice"), ["v"]);
    put("w", "v", ["bob", "carol"], 2);
    assert.deepEqual(members("w", "alice"), []);
    assert.deepEqual(members("w", "bob"), ["v"]);
    assert.deepEqual(members("w", "carol"), ["v"]);
  } finally { db.close(); }
});

test("vault versions do not write a member lookup before that workspace is prepared", () => {
  const { db, put, members } = fixture();
  try {
    initializeVaultMembers(db);
    const count = () => (db.prepare("SELECT total_changes() AS n").get() as { n: number }).n;
    const before = count();
    put("w", "v", ["alice", "bob"]);
    assert.equal(count() - before, 1);
    assert.deepEqual(members("w", "alice"), []);
    assert.equal(backfillVaultMembers(db, "w"), true);
    assert.deepEqual(members("w", "alice"), ["v"]);
    put("w", "v", ["bob", "carol"], 1);
    assert.deepEqual(members("w", "alice"), []);
    assert.deepEqual(members("w", "carol"), ["v"]);
  } finally { db.close(); }
});

test("a failed vault member batch rolls its entries and cursor back together", () => {
  const { db, put, members } = fixture();
  try {
    put("w", "v", ["alice"]);
    initializeVaultMembers(db);
    db.exec("CREATE TRIGGER fail_member BEFORE INSERT ON vault_member_lookup BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    assert.throws(() => backfillVaultMembers(db, "w"), /test failure/);
    assert.equal(vaultMembersComplete(db, "w"), false);
    assert.deepEqual(members("w", "alice"), []);
    db.exec("DROP TRIGGER fail_member");
    assert.equal(backfillVaultMembers(db, "w"), true);
    assert.deepEqual(members("w", "alice"), ["v"]);
  } finally { db.close(); }
});

test("unreadable old vaults do not stop preparation and are cleared when rewritten", () => {
  const { db, put, members } = fixture();
  try {
    db.prepare("INSERT INTO vaults VALUES('w','broken',0,?)").run("{broken");
    db.prepare("INSERT INTO vaults VALUES('w','legacy',0,?)").run(JSON.stringify({ members: "alice" }));
    put("w", "valid", ["alice"]);
    initializeVaultMembers(db);
    while (!backfillVaultMembers(db, "w", 2)) {}
    const invalid = () => db.prepare("SELECT vault FROM vault_member_invalid WHERE ws='w' ORDER BY vault").all().map((row) => row.vault);
    assert.deepEqual(invalid(), ["broken", "legacy"]);
    assert.deepEqual(members("w", "alice"), ["valid"]);
    put("w", "broken", ["bob"], 1);
    db.prepare("DELETE FROM vaults WHERE ws='w' AND id='legacy'").run();
    assert.deepEqual(invalid(), []);
    assert.deepEqual(members("w", "bob"), ["broken"]);
  } finally { db.close(); }
});
