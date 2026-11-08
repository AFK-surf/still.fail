import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { backfillVaultMembers, hasInvalidVaultMembers, VAULT_MEMBERS_INVALID, vaultMembersComplete } from "../src/vault/member-index.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";

test("a member field changed from an array to the same text uses the original pending-list behavior", async () => {
  const db = new DatabaseSync(":memory:"), vaults = new VaultStore(db);
  vaults.putVault({ ws: "w", id: "v", seq: 0, members: ["alice-alias"] } as never);
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => ({ ws: "w" } as never),
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  try {
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s','pending',?)")
      .run(JSON.stringify({ ws: "w", id: "r", session: "s", vault: "v", at: 0, item: "i", mode: "env", status: "pending" }));
    await secrets.preparePending("w", true);
    const pending = () => secrets.pending("w", { ws: "w" } as never, { sub: "alice", email: "alice@example.test" }).map((r) => r.id);
    assert.deepEqual(pending(), []);
    db.prepare("UPDATE vaults SET body=? WHERE ws='w' AND id='v'")
      .run(JSON.stringify({ ws: "w", id: "v", members: '["alice-alias"]' }));
    // JSON.parse exposes a string whose includes() finds alice; SQLite json_extract returns the same SQL text for
    // the former array and the new string, so an index change test must compare their JSON types as well.
    assert.deepEqual(pending(), ["r"]);
  } finally { await secrets.close(); db.close(); }
});

test("changing the same text back to an array restores its members in the ready index", () => {
  const db = new DatabaseSync(":memory:"), vaults = new VaultStore(db);
  try {
    vaults.putVault({ ws: "w", id: "v", seq: 0, members: '["alice"]' } as never);
    assert.equal(backfillVaultMembers(db, "w"), true);
    assert.equal(hasInvalidVaultMembers(db, "w"), true);
    db.prepare("UPDATE vaults SET body=? WHERE ws='w' AND id='v'")
      .run(JSON.stringify({ ws: "w", id: "v", members: ["alice"] }));
    assert.equal(hasInvalidVaultMembers(db, "w"), false);
    assert.deepEqual(db.prepare("SELECT sub FROM vault_member_lookup WHERE ws='w' AND vault='v'").all().map((r) => r.sub), ["alice"]);
    db.prepare("UPDATE vaults SET body=? WHERE ws='w' AND id='v'")
      .run(JSON.stringify({ ws: "w", id: "v", members: '["alice"]' }));
    assert.equal(hasInvalidVaultMembers(db, "w"), true);
  } finally { db.close(); }
});

test("an old completed lookup is repaired in batches while a prepared old writer changes vaults", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-member-type-")), path = join(dir, "data.sqlite");
  const old = new DatabaseSync(path);
  old.exec("PRAGMA journal_mode=WAL");
  const original = new VaultStore(old);
  original.putVault({ ws: "w", id: "a", seq: 0, members: ["alice-alias"] } as never);
  original.putVault({ ws: "w", id: "b", seq: 0, members: '["alice"]' } as never);
  while (!backfillVaultMembers(old, "w", 1)) {}
  // Emulate the older trigger and its complete v1/v2 lookup before installing the new audit.
  old.exec("DROP TRIGGER vault_member_type_add_v3; DROP TRIGGER vault_member_type_change_v3; DELETE FROM vault_member_type_audit_v3");
  const write = old.prepare("UPDATE vaults SET body=? WHERE ws='w' AND id=?");
  write.run(JSON.stringify({ ws: "w", id: "a", members: '["alice-alias"]' }), "a");
  write.run(JSON.stringify({ ws: "w", id: "b", members: ["alice"] }), "b");
  assert.equal(old.prepare("SELECT 1 FROM vault_member_invalid WHERE ws='w' AND vault='a'").get(), undefined);
  assert.equal(old.prepare("SELECT 1 FROM vault_member_lookup WHERE ws='w' AND sub='alice' AND vault='b'").get(), undefined);
  const db = new DatabaseSync(path), vaults = new VaultStore(db);
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => ({ ws: "w" } as never),
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  try {
    const request = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)");
    for (const id of ["a", "b"]) request.run(`r-${id}`, JSON.stringify({ ws: "w", id: `r-${id}`, session: "s",
      vault: id, at: 0, item: "i", mode: "env", status: "pending" }));
    const pending = () => secrets.pending("w", { ws: "w" } as never, { sub: "alice", email: "alice@example.test" }).map((r) => r.id);
    assert.equal(vaultMembersComplete(db, "w"), false);
    assert.deepEqual(pending(), ["r-a", "r-b"]);
    assert.equal(backfillVaultMembers(db, "w", 1), false);
    // This statement was prepared on the old connection before the replacement triggers were installed.
    write.run(JSON.stringify({ ws: "w", id: "a", members: ["alice-alias"] }), "a");
    while (!backfillVaultMembers(db, "w", 1)) {}
    assert.equal(vaultMembersComplete(db, "w"), true);
    assert.equal(hasInvalidVaultMembers(db, "w"), false);
    assert.deepEqual(db.prepare("SELECT vault FROM vault_member_lookup WHERE ws='w' AND sub='alice'").all().map((r) => r.vault), ["b"]);
    await secrets.preparePending("w", true);
    assert.deepEqual(pending(), ["r-b"]);
    write.run(JSON.stringify({ ws: "w", id: "a", members: '["alice-alias"]' }), "a");
    assert.deepEqual(pending(), ["r-a", "r-b"]);
  } finally { await secrets.close(); db.close(); old.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a failed type audit rolls back its repairs and cursor", () => {
  const db = new DatabaseSync(":memory:"), vaults = new VaultStore(db);
  try {
    vaults.putVault({ ws: "w", id: "v", seq: 0, members: ["alice"] } as never);
    assert.equal(backfillVaultMembers(db, "w"), true);
    db.exec("DELETE FROM vault_member_type_audit_v3; DELETE FROM vault_member_lookup");
    db.exec("CREATE TRIGGER fail_member_type BEFORE INSERT ON vault_member_lookup BEGIN SELECT RAISE(ABORT,'type audit failure'); END");
    assert.throws(() => backfillVaultMembers(db, "w"), /type audit failure/);
    assert.equal(db.prepare("SELECT 1 FROM vault_member_type_audit_v3 WHERE ws='w'").get(), undefined);
    assert.equal(db.prepare("SELECT 1 FROM vault_member_lookup WHERE ws='w'").get(), undefined);
    db.exec("DROP TRIGGER fail_member_type");
    assert.equal(backfillVaultMembers(db, "w"), true);
    assert.deepEqual(db.prepare("SELECT sub FROM vault_member_lookup WHERE ws='w'").all().map((r) => r.sub), ["alice"]);
  } finally { db.close(); }
});

for (const recursive of [false, true]) test(`replacing an invalid vault clears its old marker (recursive: ${recursive})`, () => {
  const db = new DatabaseSync(":memory:"), vaults = new VaultStore(db);
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    vaults.putVault({ ws: "w", id: "v", seq: 0, members: '["alice"]' } as never);
    assert.equal(backfillVaultMembers(db, "w"), true);
    assert.equal(hasInvalidVaultMembers(db, "w"), true);
    db.prepare("INSERT OR REPLACE INTO vaults(ws,id,seq,body) VALUES('w','v',1,?)")
      .run(JSON.stringify({ ws: "w", id: "v", members: ["alice"] }));
    assert.equal(hasInvalidVaultMembers(db, "w"), false);
    assert.deepEqual(db.prepare("SELECT sub FROM vault_member_lookup WHERE ws='w' AND vault='v'").all().map((r) => r.sub), ["alice"]);
  } finally { db.close(); }
});

for (const recursive of [false, true]) test(`a rowid replacement does not leave an unrelated invalid marker blocking the index (recursive: ${recursive})`, () => {
  const db = new DatabaseSync(":memory:"), vaults = new VaultStore(db);
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    vaults.putVault({ ws: "w", id: "v", seq: 0, members: '["alice"]' } as never);
    assert.equal(backfillVaultMembers(db, "w"), true);
    const row = db.prepare("SELECT rowid AS n FROM vaults WHERE ws='w' AND id='v'").get() as { n: number };
    db.prepare("INSERT OR REPLACE INTO vaults(rowid,ws,id,seq,body) VALUES(?,'w','other',0,?)")
      .run(row.n, JSON.stringify({ ws: "w", id: "other", members: ["alice"] }));
    assert.equal(hasInvalidVaultMembers(db, "w"), false);
  } finally { db.close(); }
});

test("checking invalid members starts at the marker, not all vaults in the workspace", () => {
  const db = new DatabaseSync(":memory:");
  new VaultStore(db);
  try {
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${VAULT_MEMBERS_INVALID}`).all("w", "w", "w") as { detail: string }[])
      .map((row) => row.detail).join("\n");
    assert.match(plan, /SEARCH i USING PRIMARY KEY \(ws=\?\)[\s\S]*SEARCH v USING (?:COVERING )?INDEX .*\(ws=\? AND id=\?\)/);
  } finally { db.close(); }
});

test("a completed old index stays available while its type audit runs in the background", async () => {
  const db = new DatabaseSync(":memory:"), vaults = new VaultStore(db);
  for (let i = 0; i < 100; i++) vaults.putVault({ ws: "w", id: `v${String(i).padStart(3, "0")}`, seq: 0,
    members: [i === 0 ? "alice" : "bob"] } as never);
  while (!backfillVaultMembers(db, "w", 32)) {}
  db.exec("DELETE FROM vault_member_type_audit_v3");
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => ({ ws: "w" } as never),
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  try {
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s','pending',?)")
      .run(JSON.stringify({ ws: "w", id: "r", session: "s", vault: "v000", at: 0, item: "i", mode: "env", status: "pending" }));
    const pending = () => secrets.pending("w", { ws: "w" } as never, { sub: "alice", email: "alice@example.test" }).map((r) => r.id);
    await secrets.preparePending("w", true);
    assert.equal(vaultMembersComplete(db, "w"), false);
    assert.deepEqual(pending(), ["r"]);
    for (let i = 0; i < 20 && !vaultMembersComplete(db, "w"); i++) await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(vaultMembersComplete(db, "w"), true);
    assert.deepEqual(pending(), ["r"]);
  } finally { await secrets.close(); db.close(); }
});

for (const { description, members, expected } of [
  { description: "changing type", members: '["alice"]', expected: ["r"] },
  { description: "being removed", members: ["bob"], expected: [] },
]) test(`a member ${description} after the readiness check is checked again`, async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-member-snapshot-")), path = join(dir, "data.sqlite");
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode=WAL");
  new VaultStore(db);
  const other = new DatabaseSync(path);
  const write = other.prepare("UPDATE vaults SET body=? WHERE ws='w' AND id='v'");
  let armed = false;
  const observed = new Proxy(db, { get(target, key) {
    if (key === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      if (!sql.includes("FROM vault_member_invalid i CROSS JOIN vaults")) return statement;
      return new Proxy(statement, { get(query, method) {
        if (method === "get") return (...args: never[]) => {
          const result = query.get(...args);
          if (armed) {
            armed = false;
            write.run(JSON.stringify({ ws: "w", id: "v", members }));
          }
          return result;
        };
        const value = Reflect.get(query, method, query);
        return typeof value === "function" ? value.bind(query) : value;
      } });
    };
    const value = Reflect.get(target, key, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const vaults = new VaultStore(observed);
  vaults.putVault({ ws: "w", id: "v", seq: 0, members: ["alice"] } as never);
  const secrets = new Secrets({ db: observed, data: ".", now: () => 0, home: () => "w", lock: () => ({ ws: "w" } as never),
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  try {
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s','pending',?)")
      .run(JSON.stringify({ ws: "w", id: "r", session: "s", vault: "v", at: 0, item: "i", mode: "env", status: "pending" }));
    await secrets.preparePending("w", true);
    armed = true;
    assert.deepEqual(secrets.pending("w", { ws: "w" } as never, { sub: "alice", email: "alice@example.test" }).map((r) => r.id), expected);
    assert.equal(armed, false);
  } finally { await secrets.close(); other.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("the pending-list snapshot leaves an outer transaction under its caller's control", async () => {
  const db = new DatabaseSync(":memory:"), vaults = new VaultStore(db);
  vaults.putVault({ ws: "w", id: "v", seq: 0, members: ["alice"] } as never);
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => ({ ws: "w" } as never),
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  try {
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s','pending',?)")
      .run(JSON.stringify({ ws: "w", id: "r", session: "s", vault: "v", at: 0, item: "i", mode: "env", status: "pending" }));
    await secrets.preparePending("w", true);
    db.exec("BEGIN");
    vaults.putVault({ ws: "w", id: "other", seq: 0, members: ["bob"] } as never);
    assert.deepEqual(secrets.pending("w", { ws: "w" } as never, { sub: "alice", email: "alice@example.test" }).map((r) => r.id), ["r"]);
    db.exec("ROLLBACK");
    assert.equal(vaults.vault("w", "other"), null);
  } finally { await secrets.close(); db.close(); }
});
