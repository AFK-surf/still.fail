import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { backfillVaultMembers, hasInvalidVaultMembers, VAULT_MEMBERS_INVALID, vaultMembersComplete } from "../src/vault/member-index.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";

function world() {
  const db = new DatabaseSync(":memory:");
  const vaults = new VaultStore(db);
  vaults.putVault({ ws: "w", id: "v", seq: 0, members: ["bob"] } as never);
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => ({ ws: "w" } as never),
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s','pending',?)")
    .run(JSON.stringify({ ws: "w", id: "r", session: "s", vault: "v", at: 0, item: "i", mode: "env", status: "pending" }));
  const duplicate = () => db.prepare("UPDATE vaults SET body=? WHERE ws='w' AND id='v'")
    .run('{"ws":"w","id":"v","members":["bob"],"members":["alice"]}');
  const pending = (sub: string) => secrets.pending("w", { ws: "w" } as never, { sub, email: `${sub}@example.test` }).map((r) => r.id);
  return { db, secrets, duplicate, pending };
}

test("the duplicate check starts with markers rather than scanning the workspace's vaults", () => {
  const db = new DatabaseSync(":memory:");
  new VaultStore(db);
  try {
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${VAULT_MEMBERS_INVALID}`).all("w", "w") as { detail: string }[])
      .map((row) => row.detail).join("\n");
    assert.match(plan, /SEARCH d USING PRIMARY KEY \(ws=\?\)[\s\S]*SEARCH v USING (?:COVERING )?INDEX .*\(ws=\? AND id=\?\)/);
  } finally { db.close(); }
});

test("preparing a member lookup keeps the last members field of an old vault", async () => {
  const f = world();
  try {
    f.duplicate();
    assert.deepEqual(f.pending("alice"), ["r"]);
    await f.secrets.preparePending("w", true);
    assert.deepEqual(f.pending("alice"), ["r"]);
    assert.deepEqual(f.pending("bob"), []);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("a duplicate members field written after preparation is checked from its last value", async () => {
  const f = world();
  try {
    await f.secrets.preparePending("w", true);
    assert.deepEqual(f.pending("alice"), []);
    f.duplicate();
    assert.deepEqual(f.pending("alice"), ["r"]);
    assert.deepEqual(f.pending("bob"), []);
    f.db.prepare("UPDATE vaults SET body=? WHERE ws='w' AND id='v'")
      .run(JSON.stringify({ ws: "w", id: "v", members: ["alice"] }));
    assert.equal(hasInvalidVaultMembers(f.db, "w"), false);
    assert.deepEqual(f.pending("alice"), ["r"]);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("an old completed index is checked in batches while another connection changes vaults", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-member-audit-")), path = join(dir, "data.sqlite");
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode=WAL");
  const other = new DatabaseSync(path);
  const vaults = new VaultStore(db);
  const normal = (id: string, sub = "bob") => JSON.stringify({ ws: "w", id, members: [sub] });
  const duplicate = (id: string) => `{"ws":"w","id":"${id}","members":["bob"],"members":["alice"]}`;
  const insert = db.prepare("INSERT INTO vaults(ws,id,seq,body) VALUES('w',?,0,?)");
  for (const id of ["a", "b", "c", "d"]) insert.run(id, id === "b" || id === "c" ? duplicate(id) : normal(id));
  // Simulate the index written by the previous implementation, which used each body's first members field.
  db.prepare("INSERT INTO vault_member_backfill(ws,after_id,done) VALUES('w','d',1)").run();
  for (const id of ["a", "b", "c", "d"]) db.prepare("INSERT INTO vault_member_lookup VALUES('w','bob',?)").run(id);
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => ({ ws: "w" } as never),
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  try {
    assert.equal(vaultMembersComplete(db, "w"), false);
    assert.equal(backfillVaultMembers(db, "w", 2), false);
    const audit = db.prepare("SELECT after_id,done FROM vault_member_audit_v2 WHERE ws='w'").get() as { after_id: string; done: number };
    assert.equal(audit.after_id, "b");
    assert.equal(audit.done, 0);
    const write = other.prepare("UPDATE vaults SET body=? WHERE ws='w' AND id=?");
    write.run(duplicate("a"), "a");
    write.run(normal("b", "alice"), "b");
    write.run(normal("c"), "c");
    write.run(duplicate("d"), "d");
    // The escaped spelling is the same JSON property name, and this insert falls before the saved cursor.
    other.prepare("INSERT INTO vaults(ws,id,seq,body) VALUES('w','aa',0,?)")
      .run('{"ws":"w","id":"aa","members":["bob"],"member\\u0073":["alice"]}');
    while (!backfillVaultMembers(db, "w", 2)) {}
    assert.equal(vaultMembersComplete(db, "w"), true);
    assert.deepEqual(db.prepare("SELECT vault FROM vault_member_duplicates_v2 WHERE ws='w' ORDER BY vault").all().map((r) => r.vault), ["a", "aa", "d"]);
    const request = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)");
    for (const id of ["a", "aa", "b", "c", "d"]) request.run(`r-${id}`, JSON.stringify({ ws: "w", id: `r-${id}`,
      session: "s", vault: id, at: 0, item: "i", mode: "env", status: "pending" }));
    await secrets.preparePending("w", true);
    const pending = () => secrets.pending("w", { ws: "w" } as never, { sub: "alice", email: "alice@example.test" }).map((r) => r.id);
    assert.deepEqual(pending(), ["r-a", "r-aa", "r-b", "r-d"]);
    for (const id of ["a", "aa", "d"]) write.run(normal(id, "alice"), id);
    assert.equal(hasInvalidVaultMembers(db, "w"), false);
    assert.deepEqual(pending(), ["r-a", "r-aa", "r-b", "r-d"]);
  } finally { await secrets.close(); other.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a failed duplicate audit rolls back its marker and cursor", async () => {
  const f = world();
  try {
    f.duplicate();
    f.db.exec("CREATE TRIGGER fail_duplicate_audit BEFORE INSERT ON vault_member_duplicates_v2 BEGIN SELECT RAISE(ABORT,'audit failure'); END");
    assert.throws(() => backfillVaultMembers(f.db, "w", 32), /audit failure/);
    assert.equal(f.db.prepare("SELECT 1 FROM vault_member_audit_v2 WHERE ws='w'").get(), undefined);
    assert.equal(f.db.prepare("SELECT 1 FROM vault_member_lookup WHERE ws='w'").get(), undefined);
    f.db.exec("DROP TRIGGER fail_duplicate_audit");
    assert.equal(backfillVaultMembers(f.db, "w", 32), true);
    await f.secrets.preparePending("w", true);
    assert.deepEqual(f.pending("alice"), ["r"]);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("an older connection's prepared write is checked after the audit is installed", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-member-old-writer-")), path = join(dir, "data.sqlite");
  const old = new DatabaseSync(path);
  old.exec("PRAGMA journal_mode=WAL; CREATE TABLE vaults(ws TEXT NOT NULL,id TEXT NOT NULL,seq INTEGER NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))");
  const write = old.prepare(`INSERT INTO vaults(ws,id,seq,body) VALUES('w','v',0,?)
    ON CONFLICT(ws,id) DO UPDATE SET seq=excluded.seq,body=excluded.body`);
  write.run('{"ws":"w","id":"v","members":["bob"]}');
  const db = new DatabaseSync(path), vaults = new VaultStore(db);
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => ({ ws: "w" } as never),
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  try {
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s','pending',?)")
      .run(JSON.stringify({ ws: "w", id: "r", session: "s", vault: "v", at: 0, item: "i", mode: "env", status: "pending" }));
    await secrets.preparePending("w", true);
    const pending = () => secrets.pending("w", { ws: "w" } as never, { sub: "alice", email: "alice@example.test" }).map((r) => r.id);
    assert.deepEqual(pending(), []);
    write.run('{"ws":"w","id":"v","members":["bob"],"members":["alice"]}');
    assert.deepEqual(pending(), ["r"]);
    write.run('{"ws":"w","id":"v","members":["alice"]}');
    assert.equal(hasInvalidVaultMembers(db, "w"), false);
    assert.deepEqual(pending(), ["r"]);
  } finally { await secrets.close(); db.close(); old.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const recursive of [false, true]) test(`a rowid replacement does not leave an unrelated duplicate blocking the index (recursive: ${recursive})`, () => {
  const db = new DatabaseSync(":memory:"), vaults = new VaultStore(db);
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    vaults.putVault({ ws: "w", id: "v", seq: 0, members: ["bob"] } as never);
    db.prepare("UPDATE vaults SET body=? WHERE ws='w' AND id='v'")
      .run('{"ws":"w","id":"v","members":["bob"],"members":["alice"]}');
    assert.equal(backfillVaultMembers(db, "w"), true);
    assert.equal(hasInvalidVaultMembers(db, "w"), true);
    const row = db.prepare("SELECT rowid AS n FROM vaults WHERE ws='w' AND id='v'").get() as { n: number };
    db.prepare("INSERT OR REPLACE INTO vaults(rowid,ws,id,seq,body) VALUES(?,'w','other',0,?)")
      .run(row.n, '{"ws":"w","id":"other","members":["alice"]}');
    assert.equal(hasInvalidVaultMembers(db, "w"), false);
  } finally { db.close(); }
});

async function oldPreparedWorld() {
  const f = world();
  f.duplicate();
  const insert = f.db.prepare("INSERT INTO vaults(ws,id,seq,body) VALUES('w',?,0,?)");
  for (let i = 0; i < 100; i++) {
    const id = `z${String(i).padStart(3, "0")}`;
    insert.run(id, JSON.stringify({ ws: "w", id, members: ["bob"] }));
  }
  f.db.prepare("INSERT INTO vault_member_backfill VALUES('w','z099',1)").run();
  f.db.prepare("INSERT INTO vault_member_lookup SELECT ws,'bob',id FROM vaults WHERE ws='w'").run();
  await f.secrets.preparePending("w", false);
  return f;
}

test("an existing list remains available while its old member index is audited", async () => {
  const f = await oldPreparedWorld();
  try {
    await Promise.all(Array.from({ length: 5 }, () => f.secrets.preparePending("w", true)));
    assert.equal(vaultMembersComplete(f.db, "w"), false);
    assert.deepEqual(f.pending("alice"), ["r"]);
    for (let i = 0; i < 20 && !vaultMembersComplete(f.db, "w"); i++) await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(vaultMembersComplete(f.db, "w"), true);
    assert.deepEqual(f.pending("alice"), ["r"]);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("stopping during a background member audit does not use the closed database", async () => {
  const f = await oldPreparedWorld();
  await f.secrets.preparePending("w", true);
  assert.equal(vaultMembersComplete(f.db, "w"), false);
  await f.secrets.close();
  f.db.close();
  await new Promise<void>((resolve) => setImmediate(resolve));
});

test("an interrupted older member index is finished before its audit restarts at the beginning", () => {
  const db = new DatabaseSync(":memory:");
  new VaultStore(db);
  try {
    const insert = db.prepare("INSERT INTO vaults(ws,id,seq,body) VALUES('w',?,0,?)");
    for (const id of ["a", "b", "c", "d", "e"]) insert.run(id, id === "a" || id === "e"
      ? `{"ws":"w","id":"${id}","members":["bob"],"members":["alice"]}`
      : JSON.stringify({ ws: "w", id, members: ["bob"] }));
    db.prepare("INSERT INTO vault_member_backfill VALUES('w','b',0)").run();
    for (const id of ["a", "b"]) db.prepare("INSERT INTO vault_member_lookup VALUES('w','bob',?)").run(id);
    assert.equal(backfillVaultMembers(db, "w", 2), false);
    assert.equal(backfillVaultMembers(db, "w", 2), false);
    assert.equal(vaultMembersComplete(db, "w"), false);
    while (!backfillVaultMembers(db, "w", 2)) {}
    assert.deepEqual(db.prepare("SELECT vault FROM vault_member_duplicates_v2 WHERE ws='w' ORDER BY vault").all().map((r) => r.vault), ["a", "e"]);
  } finally { db.close(); }
});

test("an interrupted old member index also keeps the list available while it resumes", async () => {
  const f = await oldPreparedWorld();
  try {
    f.db.prepare("UPDATE vault_member_backfill SET after_id='v',done=0 WHERE ws='w'").run();
    await f.secrets.preparePending("w", true);
    assert.equal(vaultMembersComplete(f.db, "w"), false);
    assert.deepEqual(f.pending("alice"), ["r"]);
    for (let i = 0; i < 20 && !vaultMembersComplete(f.db, "w"); i++) await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(vaultMembersComplete(f.db, "w"), true);
    assert.deepEqual(f.pending("alice"), ["r"]);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("a failed background audit leaves the list available and a later read retries it", async () => {
  const f = await oldPreparedWorld();
  try {
    f.db.exec("CREATE TRIGGER fail_duplicate_audit BEFORE INSERT ON vault_member_duplicates_v2 BEGIN SELECT RAISE(ABORT,'audit failure'); END");
    await f.secrets.preparePending("w", true);
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(vaultMembersComplete(f.db, "w"), false);
    assert.deepEqual(f.pending("alice"), ["r"]);
    f.db.exec("DROP TRIGGER fail_duplicate_audit");
    await f.secrets.preparePending("w", true);
    for (let i = 0; i < 20 && !vaultMembersComplete(f.db, "w"); i++) await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(vaultMembersComplete(f.db, "w"), true);
    assert.deepEqual(f.pending("alice"), ["r"]);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("a file-backed list does not wait for its old member index audit", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-member-background-")), path = join(dir, "data.sqlite");
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode=WAL");
  const vaults = new VaultStore(db), insert = db.prepare("INSERT INTO vaults(ws,id,seq,body) VALUES('w',?,0,?)");
  for (let i = 0; i < 128; i++) {
    const id = `v${String(i).padStart(3, "0")}`;
    insert.run(id, i === 0 ? `{"ws":"w","id":"${id}","members":["bob"],"members":["alice"]}`
      : JSON.stringify({ ws: "w", id, members: ["bob"] }));
  }
  db.prepare("INSERT INTO vault_member_backfill VALUES('w','v127',1)").run();
  db.prepare("INSERT INTO vault_member_lookup SELECT ws,'bob',id FROM vaults WHERE ws='w'").run();
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => ({ ws: "w" } as never),
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  try {
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s','pending',?)")
      .run(JSON.stringify({ ws: "w", id: "r", session: "s", vault: "v000", at: 0, item: "i", mode: "env", status: "pending" }));
    await secrets.preparePending("w", false);
    await secrets.preparePending("w", true);
    assert.equal(vaultMembersComplete(db, "w"), false);
    assert.deepEqual(secrets.pending("w", { ws: "w" } as never, { sub: "alice", email: "alice@example.test" }).map((r) => r.id), ["r"]);
  } finally { await secrets.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});
