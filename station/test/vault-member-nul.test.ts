import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { backfillVaultMembers, hasInvalidVaultMembers, VAULT_MEMBERS_INVALID, vaultMembersComplete } from "../src/vault/member-index.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";

const normal = (id: string, member = "bob") => JSON.stringify({ ws: "w", id, seq: 0, members: [member] });
const ambiguous = (id: string) => `{"ws":"w","id":"${id}","seq":0,"members\\u0000ignored":["bob"],"members":["alice"]}`;

function world(db = new DatabaseSync(":memory:")) {
  const vaults = new VaultStore(db);
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => ({ ws: "w" } as never),
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  const insert = db.prepare("INSERT INTO vaults(ws,id,seq,body) VALUES('w',?,0,?)");
  const request = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)");
  const add = (id: string, body = normal(id)) => {
    insert.run(id, body);
    request.run(`r-${id}`, JSON.stringify({ ws: "w", id: `r-${id}`, session: "s", vault: id,
      at: 0, item: "i", mode: "env", status: "pending" }));
  };
  const pending = (sub = "alice") => secrets.pending("w", { ws: "w" } as never,
    { sub, email: `${sub}@example.test` }).map((r) => r.id);
  const visible = () => vaults.memberVaults("w", "alice").filter((v) => v.members.includes("alice")).map((v) => v.id);
  return { db, vaults, secrets, add, pending, visible };
}

for (const after of [false, true]) test(`a NUL-suffixed members field written ${after ? "after" : "before"} preparation keeps pending requests and vault lists`, async () => {
  const f = world();
  try {
    f.add("mine", after ? normal("mine") : ambiguous("mine"));
    for (let i = 0; i < 40; i++) f.add(`other-${String(i).padStart(2, "0")}`);
    if (!after) assert.deepEqual(f.pending(), ["r-mine"]);
    await f.secrets.preparePending("w", true);
    if (after) f.db.prepare("UPDATE vaults SET body=? WHERE ws='w' AND id='mine'").run(ambiguous("mine"));
    assert.equal(hasInvalidVaultMembers(f.db, "w"), true);
    assert.deepEqual(f.pending(), ["r-mine"]);
    assert.deepEqual(f.visible(), ["mine"]);
    assert.deepEqual(f.pending("bob").includes("r-mine"), false);
    f.db.prepare("UPDATE vaults SET body=? WHERE ws='w' AND id='mine'").run(normal("mine", "alice"));
    assert.equal(hasInvalidVaultMembers(f.db, "w"), false);
    assert.deepEqual(f.pending(), ["r-mine"]);
    assert.deepEqual(f.visible(), ["mine"]);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("an old member index is checked in batches while another connection writes on both sides of its cursor", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-member-nul-")), path = join(dir, "data.sqlite");
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode=WAL");
  const other = new DatabaseSync(path), f = world(db);
  try {
    for (const id of ["a", "b", "c", "d"]) f.add(id, id === "b" ? ambiguous(id) : normal(id));
    while (!backfillVaultMembers(db, "w", 2)) {}
    // Simulate an index completed before the NUL audit existed.
    db.exec("DELETE FROM vault_member_nul_v4; DELETE FROM vault_member_nul_audit_v4");
    assert.equal(vaultMembersComplete(db, "w"), false);
    assert.deepEqual(f.pending(), ["r-b"]);
    assert.equal(backfillVaultMembers(db, "w", 2), false);
    const audit = db.prepare("SELECT after_id,done FROM vault_member_nul_audit_v4 WHERE ws='w'").get() as { after_id: string; done: number };
    assert.deepEqual([audit.after_id, audit.done], ["b", 0]);
    const write = other.prepare("UPDATE vaults SET body=? WHERE ws='w' AND id=?");
    write.run(ambiguous("a"), "a");
    write.run(normal("b", "alice"), "b");
    write.run(ambiguous("d"), "d");
    while (!backfillVaultMembers(db, "w", 2)) {}
    assert.equal(vaultMembersComplete(db, "w"), true);
    assert.deepEqual(db.prepare("SELECT vault FROM vault_member_nul_v4 WHERE ws='w' ORDER BY vault").all().map((r) => r.vault), ["a", "d"]);
    assert.deepEqual(f.pending(), ["r-a", "r-b", "r-d"]);
    write.run(normal("a", "alice"), "a");
    write.run(normal("d", "alice"), "d");
    assert.equal(hasInvalidVaultMembers(db, "w"), false);
    assert.deepEqual(f.pending(), ["r-a", "r-b", "r-d"]);
  } finally { await f.secrets.close(); other.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a previously prepared list stays available during its background NUL audit", async () => {
  const f = world();
  try {
    f.add("mine", ambiguous("mine"));
    for (let i = 0; i < 100; i++) f.add(`other-${String(i).padStart(3, "0")}`);
    while (!backfillVaultMembers(f.db, "w")) {}
    await f.secrets.preparePending("w", true);
    f.db.exec("DELETE FROM vault_member_nul_v4; DELETE FROM vault_member_nul_audit_v4");
    await f.secrets.preparePending("w", true);
    assert.equal(vaultMembersComplete(f.db, "w"), false);
    assert.deepEqual(f.pending(), ["r-mine"]);
    assert.deepEqual(f.visible(), ["mine"]);
    for (let i = 0; i < 20 && !vaultMembersComplete(f.db, "w"); i++) await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(vaultMembersComplete(f.db, "w"), true);
    assert.deepEqual(f.pending(), ["r-mine"]);
    assert.deepEqual(f.visible(), ["mine"]);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("a failed NUL audit rolls its marker and cursor back together", async () => {
  const f = world();
  try {
    f.add("mine", ambiguous("mine"));
    f.db.exec("CREATE TRIGGER fail_nul_audit BEFORE INSERT ON vault_member_nul_v4 BEGIN SELECT RAISE(ABORT,'audit failure'); END");
    assert.throws(() => backfillVaultMembers(f.db, "w"), /audit failure/);
    assert.equal(f.db.prepare("SELECT 1 FROM vault_member_nul_audit_v4 WHERE ws='w'").get(), undefined);
    assert.equal(f.db.prepare("SELECT 1 FROM vault_member_lookup WHERE ws='w'").get(), undefined);
    f.db.exec("DROP TRIGGER fail_nul_audit");
    assert.equal(backfillVaultMembers(f.db, "w"), true);
    assert.deepEqual(f.pending(), ["r-mine"]);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("an older connection's prepared write is checked after the NUL audit is installed", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-member-nul-old-")), path = join(dir, "data.sqlite");
  const old = new DatabaseSync(path);
  old.exec("PRAGMA journal_mode=WAL; CREATE TABLE vaults(ws TEXT NOT NULL,id TEXT NOT NULL,seq INTEGER NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))");
  const write = old.prepare(`INSERT INTO vaults(ws,id,seq,body) VALUES('w','mine',0,?)
    ON CONFLICT(ws,id) DO UPDATE SET seq=excluded.seq,body=excluded.body`);
  write.run(normal("mine"));
  const db = new DatabaseSync(path), f = world(db);
  try {
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r-mine','s','pending',?)")
      .run(JSON.stringify({ ws: "w", id: "r-mine", session: "s", vault: "mine", at: 0, item: "i", mode: "env", status: "pending" }));
    await f.secrets.preparePending("w", true);
    assert.deepEqual(f.pending(), []);
    write.run(ambiguous("mine"));
    assert.deepEqual(f.pending(), ["r-mine"]);
    write.run(normal("mine", "alice"));
    assert.equal(hasInvalidVaultMembers(db, "w"), false);
    assert.deepEqual(f.pending(), ["r-mine"]);
  } finally { await f.secrets.close(); db.close(); old.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const recursive of [false, true]) test(`a rowid replacement does not leave a NUL marker blocking the index (recursive: ${recursive})`, () => {
  const db = new DatabaseSync(":memory:");
  new VaultStore(db);
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    db.prepare("INSERT INTO vaults(ws,id,seq,body) VALUES('w','mine',0,?)").run(ambiguous("mine"));
    assert.equal(backfillVaultMembers(db, "w"), true);
    assert.equal(hasInvalidVaultMembers(db, "w"), true);
    const row = db.prepare("SELECT rowid AS n FROM vaults WHERE ws='w' AND id='mine'").get() as { n: number };
    db.prepare("INSERT OR REPLACE INTO vaults(rowid,ws,id,seq,body) VALUES(?,'w','other',0,?)").run(row.n, normal("other"));
    assert.equal(hasInvalidVaultMembers(db, "w"), false);
  } finally { db.close(); }
});

test("an unrelated NUL key does not prevent using the member index", () => {
  const db = new DatabaseSync(":memory:"), vaults = new VaultStore(db);
  try {
    for (let i = 0; i < 40; i++) vaults.putVault({ ws: "w", id: `v${i}`, seq: 0, members: [i === 0 ? "alice" : "bob"] } as never);
    db.prepare("UPDATE vaults SET body=? WHERE ws='w' AND id='v0'")
      .run('{"ws":"w","id":"v0","other\\u0000ignored":1,"members":["alice"]}');
    while (!backfillVaultMembers(db, "w")) {}
    assert.equal(hasInvalidVaultMembers(db, "w"), false);
    assert.deepEqual(vaults.memberVaults("w", "alice").map((v) => v.id), ["v0"]);
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${VAULT_MEMBERS_INVALID}`).all("w", "w", "w") as { detail: string }[])
      .map((row) => row.detail).join("\n");
    assert.match(plan, /SEARCH n USING PRIMARY KEY \(ws=\?\)[\s\S]*SEARCH v USING (?:COVERING )?INDEX .*\(ws=\? AND id=\?\)/);
  } finally { db.close(); }
});
