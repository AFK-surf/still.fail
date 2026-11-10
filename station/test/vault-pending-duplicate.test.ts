import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { backfillPendingAudit, initializePendingIndex, pendingAuditComplete, PENDING_DUPLICATES } from "../src/vault/pending-index.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";

const viewer = { sub: "alice", email: "alice@example.test" };
const lock = { ws: "w" } as never;

function fixture(now = 0) {
  const db = new DatabaseSync(":memory:"), vaults = new VaultStore(db);
  vaults.putVault({ ws: "w", id: "alice-v", seq: 0, members: ["alice"] } as never);
  vaults.putVault({ ws: "w", id: "bob-v", seq: 0, members: ["bob"] } as never);
  const secrets = new Secrets({ db, data: ".", now: () => now * 1000, home: () => "w", lock: () => lock,
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  const put = (fields: string) => db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s','pending',?)")
    .run(`{"ws":"w","id":"r","session":"s",${fields},"item":"i","mode":"env","status":"pending"}`);
  return { db, secrets, put };
}

for (const [name, fields] of [
  ["vault", '"vault":"bob-v","vault":"alice-v","at":0'],
  ["escaped vault", '"vault":"bob-v","\\u0076ault":"alice-v","at":0'],
  ["owner", '"vault":"plain","owner":"bob@example.test","owner":"alice@example.test","at":0'],
  ["save", '"vault":"bob-v","owner":"alice@example.test","save":null,"save":{"typed":true},"at":0'],
  ["save removed", '"vault":"alice-v","owner":"bob@example.test","save":{"typed":true},"save":null,"at":0'],
] as const) {
  for (const when of ["before", "after"] as const) {
    test(`a duplicate ${name} field written ${when} preparation keeps its last value`, async () => {
      const { db, secrets, put } = fixture();
      try {
        if (when === "before") put(fields);
        await secrets.preparePending("w", true);
        if (when === "after") put(fields);
        assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
      } finally { await secrets.close(); db.close(); }
    });
  }
}

for (const when of ["before", "after"] as const) {
  test(`a duplicate time field written ${when} preparation still expires another member's request`, async () => {
    const { db, secrets, put } = fixture(200_000);
    try {
      const fields = '"vault":"bob-v","at":200000,"at":0';
      if (when === "before") put(fields);
      await secrets.preparePending("w", true);
      if (when === "after") put(fields);
      assert.deepEqual(secrets.pending("w", lock, viewer), []);
      assert.equal((db.prepare("SELECT status FROM vault_requests WHERE ws = 'w' AND id = 'r'").get() as { status: string }).status, "expired");
    } finally { await secrets.close(); db.close(); }
  });
}

test("adding and removing a duplicate without changing its first value updates the list", async () => {
  const { db, secrets, put } = fixture();
  try {
    put('"vault":"bob-v","at":0');
    await secrets.preparePending("w", true);
    const read = () => secrets.pending("w", lock, viewer).map((r) => r.id);
    const write = db.prepare("UPDATE vault_requests SET body=? WHERE ws='w' AND id='r'");
    assert.deepEqual(read(), []);
    write.run('{"ws":"w","id":"r","session":"s","vault":"bob-v","vault":"alice-v","at":0,"item":"i","mode":"env","status":"pending"}');
    assert.deepEqual(read(), ["r"]);
    write.run('{"ws":"w","id":"r","session":"s","vault":"bob-v","at":0,"item":"i","mode":"env","status":"pending"}');
    assert.deepEqual(read(), []);
    assert.deepEqual(db.prepare("SELECT id FROM vault_pending_duplicates_v2 WHERE ws='w'").all(), []);
  } finally { await secrets.close(); db.close(); }
});

test("duplicate request candidates start at their markers and fetch each request by key", async () => {
  const { db, secrets } = fixture();
  try {
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${PENDING_DUPLICATES}`).all("w") as { detail: string }[])
      .map((row) => row.detail).join("\n");
    assert.match(plan, /SEARCH d USING PRIMARY KEY \(ws=\?\)[\s\S]*SEARCH r USING INDEX .*\(ws=\? AND id=\?\)/);
  } finally { await secrets.close(); db.close(); }
});

test("an old pending index is audited in batches while another connection changes requests", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-pending-audit-")), path = join(dir, "data.sqlite");
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode=WAL");
  const other = new DatabaseSync(path), vaults = new VaultStore(db);
  vaults.putVault({ ws: "w", id: "alice-v", seq: 0, members: ["alice"] } as never);
  vaults.putVault({ ws: "w", id: "bob-v", seq: 0, members: ["bob"] } as never);
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => lock,
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  const body = (id: string, duplicate: boolean) => `{"ws":"w","id":"${id}","session":"s","vault":"bob-v",${duplicate ? '"vault":"alice-v",' : ""}"at":0,"item":"i","mode":"env","status":"pending"}`;
  const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)");
  try {
    for (const id of ["a", "b", "c", "d"]) insert.run(id, body(id, id === "b" || id === "c"));
    await secrets.preparePending("w", true);
    db.exec("DELETE FROM vault_pending_audit_v2; DELETE FROM vault_pending_duplicates_v2");
    const write = other.prepare("UPDATE vault_requests SET body=? WHERE ws='w' AND id=?");
    assert.equal(backfillPendingAudit(db, "w", 2), false);
    assert.deepEqual({ ...db.prepare("SELECT after_id,done FROM vault_pending_audit_v2 WHERE ws='w'").get() }, { after_id: "b", done: 0 });
    write.run(body("a", true), "a");
    write.run(body("b", false), "b");
    write.run(body("c", false), "c");
    write.run(body("d", true), "d");
    other.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','aa','s','pending',?)").run(body("aa", true));
    while (!backfillPendingAudit(db, "w", 2)) {}
    assert.deepEqual(db.prepare("SELECT id FROM vault_pending_duplicates_v2 WHERE ws='w' ORDER BY id").all().map((r) => r.id), ["a", "aa", "d"]);
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["a", "aa", "d"]);
  } finally { await secrets.close(); other.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a failed pending audit rolls its marker and cursor back together", async () => {
  const { db, secrets, put } = fixture();
  try {
    put('"vault":"bob-v","vault":"alice-v","at":0');
    await secrets.preparePending("w", true);
    db.exec("DELETE FROM vault_pending_audit_v2; DELETE FROM vault_pending_duplicates_v2");
    db.exec("CREATE TRIGGER fail_pending_audit BEFORE INSERT ON vault_pending_duplicates_v2 BEGIN SELECT RAISE(ABORT,'audit failure'); END");
    assert.throws(() => backfillPendingAudit(db, "w"), /audit failure/);
    assert.equal(db.prepare("SELECT 1 FROM vault_pending_audit_v2 WHERE ws='w'").get(), undefined);
    assert.equal(db.prepare("SELECT 1 FROM vault_pending_duplicates_v2 WHERE ws='w'").get(), undefined);
    db.exec("DROP TRIGGER fail_pending_audit");
    assert.equal(backfillPendingAudit(db, "w"), true);
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
  } finally { await secrets.close(); db.close(); }
});

test("an old pending list remains available while its audit runs in the background", async () => {
  const { db, secrets, put } = fixture();
  try {
    put('"vault":"bob-v","vault":"alice-v","at":0');
    const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)");
    for (let i = 0; i < 128; i++) {
      const id = `z${String(i).padStart(3, "0")}`;
      insert.run(id, JSON.stringify({ ws: "w", id, session: "s", vault: "bob-v", at: 0, item: "i", mode: "env", status: "pending" }));
    }
    await secrets.preparePending("w", true);
    db.exec("DELETE FROM vault_pending_audit_v2; DELETE FROM vault_pending_duplicates_v2");
    await secrets.preparePending("w", true);
    assert.equal(pendingAuditComplete(db, "w"), false);
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
    for (let i = 0; i < 20 && !pendingAuditComplete(db, "w"); i++) await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(pendingAuditComplete(db, "w"), true);
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
  } finally { await secrets.close(); db.close(); }
});

test("an interrupted old pending index is completed before auditing its earlier requests", async () => {
  const { db, secrets, put } = fixture();
  try {
    put('"vault":"bob-v","vault":"alice-v","at":0');
    const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)");
    for (let i = 0; i < 128; i++) {
      const id = `z${String(i).padStart(3, "0")}`;
      insert.run(id, JSON.stringify({ ws: "w", id, session: "s", vault: "bob-v", at: 0, item: "i", mode: "env", status: "pending" }));
    }
    await secrets.preparePending("w", true);
    db.exec("DELETE FROM vault_pending_audit_v2; DELETE FROM vault_pending_duplicates_v2; UPDATE vault_pending_backfill SET after_id='z031',done=0 WHERE ws='w'; DELETE FROM vault_pending_lookup WHERE ws='w' AND id>'z031'");
    await secrets.preparePending("w", true);
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
    for (let i = 0; i < 30 && !pendingAuditComplete(db, "w"); i++) await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(pendingAuditComplete(db, "w"), true);
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
  } finally { await secrets.close(); db.close(); }
});

test("a failed background pending audit leaves the list usable and can be retried", async () => {
  const { db, secrets, put } = fixture();
  try {
    put('"vault":"bob-v","vault":"alice-v","at":0');
    await secrets.preparePending("w", true);
    db.exec("DELETE FROM vault_pending_audit_v2; DELETE FROM vault_pending_duplicates_v2");
    db.exec("CREATE TRIGGER fail_pending_audit BEFORE INSERT ON vault_pending_duplicates_v2 BEGIN SELECT RAISE(ABORT,'audit failure'); END");
    await secrets.preparePending("w", true);
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(pendingAuditComplete(db, "w"), false);
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
    db.exec("DROP TRIGGER fail_pending_audit");
    await secrets.preparePending("w", true);
    for (let i = 0; i < 20 && !pendingAuditComplete(db, "w"); i++) await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(pendingAuditComplete(db, "w"), true);
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
  } finally { await secrets.close(); db.close(); }
});

test("a file-backed pending list does not wait for its old audit, and can stop during it", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-pending-background-")), path = join(dir, "data.sqlite");
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode=WAL");
  const vaults = new VaultStore(db);
  vaults.putVault({ ws: "w", id: "alice-v", seq: 0, members: ["alice"] } as never);
  vaults.putVault({ ws: "w", id: "bob-v", seq: 0, members: ["bob"] } as never);
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => lock,
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  try {
    const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)");
    insert.run("r", '{"ws":"w","id":"r","session":"s","vault":"bob-v","vault":"alice-v","at":0,"item":"i","mode":"env","status":"pending"}');
    db.exec("BEGIN");
    for (let i = 0; i < 2048; i++) {
      const id = `z${String(i).padStart(4, "0")}`;
      insert.run(id, JSON.stringify({ ws: "w", id, session: "s", vault: "bob-v", at: 0, item: "i", mode: "env", status: "pending" }));
    }
    db.exec("COMMIT");
    await secrets.preparePending("w", true);
    db.exec("DELETE FROM vault_pending_audit_v2; DELETE FROM vault_pending_duplicates_v2");
    await secrets.preparePending("w", true);
    assert.equal(pendingAuditComplete(db, "w"), false);
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
  } finally { await secrets.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
  await new Promise<void>((resolve) => setImmediate(resolve));
});

test("an older connection's prepared update is checked after the audit triggers are installed", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-pending-old-writer-")), path = join(dir, "data.sqlite");
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode=WAL");
  const vaults = new VaultStore(db);
  vaults.putVault({ ws: "w", id: "alice-v", seq: 0, members: ["alice"] } as never);
  vaults.putVault({ ws: "w", id: "bob-v", seq: 0, members: ["bob"] } as never);
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => lock,
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  const old = new DatabaseSync(path);
  try {
    const normal = '{"ws":"w","id":"r","session":"s","vault":"bob-v","at":0,"item":"i","mode":"env","status":"pending"}';
    const duplicate = '{"ws":"w","id":"r","session":"s","vault":"bob-v","vault":"alice-v","at":0,"item":"i","mode":"env","status":"pending"}';
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s','pending',?)").run(normal);
    await secrets.preparePending("w", true);
    db.exec("DROP TRIGGER vault_pending_duplicate_add_v2; DROP TRIGGER vault_pending_duplicate_change_v2; DROP TRIGGER vault_pending_duplicate_drop_v2");
    const write = old.prepare("UPDATE vault_requests SET body=? WHERE ws='w' AND id='r'");
    initializePendingIndex(db);
    write.run(duplicate);
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
    write.run(normal);
    assert.deepEqual(secrets.pending("w", lock, viewer), []);
  } finally { await secrets.close(); old.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("pending audit readiness and duplicate candidates share a snapshot", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-pending-snapshot-")), path = join(dir, "data.sqlite");
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode=WAL");
  const other = new DatabaseSync(path);
  let armed = false;
  const observed = new Proxy(db, { get(target, key) {
    if (key === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      if (sql !== "SELECT done FROM vault_pending_audit_v2 WHERE ws = ?") return statement;
      return new Proxy(statement, { get(query, method) {
        if (method === "get") return (...args: never[]) => {
          const result = query.get(...args);
          if (armed) {
            armed = false;
            other.prepare("UPDATE vault_requests SET body=? WHERE ws='w' AND id='r'")
              .run('{"ws":"w","id":"r","session":"s","vault":"bob-v","vault":"alice-v","at":0,"item":"i","mode":"env","status":"pending"}');
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
  vaults.putVault({ ws: "w", id: "alice-v", seq: 0, members: ["alice"] } as never);
  vaults.putVault({ ws: "w", id: "bob-v", seq: 0, members: ["bob"] } as never);
  const secrets = new Secrets({ db: observed, data: ".", now: () => 0, home: () => "w", lock: () => lock,
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  try {
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s','pending',?)")
      .run('{"ws":"w","id":"r","session":"s","vault":"alice-v","at":0,"item":"i","mode":"env","status":"pending"}');
    await secrets.preparePending("w", true);
    armed = true;
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
    assert.equal(armed, false);
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
  } finally { await secrets.close(); other.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const recursive of [false, true]) test(`a rowid replacement does not return an unrelated orphan marker (recursive: ${recursive})`, async () => {
  const { db, secrets, put } = fixture();
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    put('"vault":"bob-v","vault":"alice-v","at":0');
    await secrets.preparePending("w", true);
    const row = db.prepare("SELECT rowid AS n FROM vault_requests WHERE ws='w' AND id='r'").get() as { n: number };
    const body = JSON.stringify({ ws: "w", id: "other", session: "s", vault: "bob-v", at: 0, item: "i", mode: "env", status: "pending" });
    db.prepare("INSERT OR REPLACE INTO vault_requests(rowid,ws,id,session,status,body) VALUES(?,'w','other','s','pending',?)").run(row.n, body);
    assert.deepEqual(secrets.pending("w", lock, viewer), []);
    assert.deepEqual(db.prepare(PENDING_DUPLICATES).all("w"), []);
  } finally { await secrets.close(); db.close(); }
});
