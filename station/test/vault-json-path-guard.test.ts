import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { backfillPendingNulAudit, initializePendingIndex, pendingAuditComplete, PENDING_NUL_FIELDS } from "../src/vault/pending-index.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";

const viewer = { sub: "alice", email: "alice@example.test" }, lock = { ws: "w" } as never;
function fixture(now = 0) {
  const db = new DatabaseSync(":memory:"), vaults = new VaultStore(db);
  vaults.putVault({ ws: "w", id: "mine", seq: 0, members: ["alice"] } as never);
  vaults.putVault({ ws: "w", id: "theirs", seq: 0, members: ["bob"] } as never);
  const secrets = new Secrets({ db, data: ".", now: () => now * 1000, home: () => "w", lock: () => lock,
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  const put = (fields: string, status = "pending") => db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s',?,?)")
    .run(status, `{"ws":"w","id":"r","session":"s",${fields},"item":"r","mode":"env","status":"${status}"}`);
  return { db, secrets, put };
}

for (const [field, fields] of [
  ["vault", '"vault\\u0000suffix":"theirs","vault":"mine","at":0'],
  ["owner", '"vault":"plain","owner\\u0000suffix":"bob@example.test","owner":"alice@example.test","at":0'],
  ["save", '"vault":"theirs","owner":"alice@example.test","save\\u0000suffix":null,"save":{"typed":true},"at":0'],
] as const) for (const when of ["before", "after"] as const) {
  test(`a NUL-suffixed ${field} key written ${when} preparation keeps the actual field`, async () => {
    const f = fixture();
    try {
      if (when === "before") f.put(fields);
      await f.secrets.preparePending("w", true);
      if (when === "after") f.put(fields);
      assert.deepEqual(f.secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
    } finally { await f.secrets.close(); f.db.close(); }
  });
}

test("a NUL-suffixed time key cannot hide an overdue request", async () => {
  const f = fixture(200_000);
  try {
    f.put('"vault":"theirs","at\\u0000suffix":200000,"at":0');
    await f.secrets.preparePending("w", true);
    assert.deepEqual(f.secrets.pending("w", lock, viewer), []);
    assert.equal((f.db.prepare("SELECT status FROM vault_requests WHERE ws='w' AND id='r'").get() as { status: string }).status, "expired");
  } finally { await f.secrets.close(); f.db.close(); }
});

test("an old pending index remains available while its NUL-field audit resumes", async () => {
  const f = fixture();
  try {
    f.put('"vault\\u0000suffix":"theirs","vault":"mine","at":0');
    const insert = f.db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)");
    for (let i = 0; i < 128; i++) {
      const id = `z${String(i).padStart(3, "0")}`;
      insert.run(id, JSON.stringify({ ws: "w", id, session: "s", vault: "theirs", at: 0, item: id, mode: "env", status: "pending" }));
    }
    await f.secrets.preparePending("w", true);
    f.db.exec("DELETE FROM vault_pending_nul_audit_v3; DELETE FROM vault_pending_nul_v3");
    await f.secrets.preparePending("w", true);
    assert.equal(pendingAuditComplete(f.db, "w"), false);
    assert.deepEqual(f.secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
    for (let i = 0; i < 20 && !pendingAuditComplete(f.db, "w"); i++) await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(pendingAuditComplete(f.db, "w"), true);
    assert.deepEqual(f.secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("a failed NUL audit rolls back and a later batch can finish", async () => {
  const f = fixture();
  try {
    f.put('"vault\\u0000suffix":"theirs","vault":"mine","at":0');
    await f.secrets.preparePending("w", true);
    f.db.exec("DELETE FROM vault_pending_nul_audit_v3; DELETE FROM vault_pending_nul_v3");
    f.db.exec("CREATE TRIGGER fail_nul_audit BEFORE INSERT ON vault_pending_nul_v3 BEGIN SELECT RAISE(ABORT,'audit failure'); END");
    assert.throws(() => backfillPendingNulAudit(f.db, "w"), /audit failure/);
    assert.equal(f.db.prepare("SELECT 1 FROM vault_pending_nul_audit_v3 WHERE ws='w'").get(), undefined);
    f.db.exec("DROP TRIGGER fail_nul_audit");
    assert.equal(backfillPendingNulAudit(f.db, "w"), true);
    assert.deepEqual(f.secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
    const plan = (f.db.prepare(`EXPLAIN QUERY PLAN ${PENDING_NUL_FIELDS}`).all("w") as { detail: string }[]).map((r) => r.detail).join("\n");
    assert.match(plan, /SEARCH n USING PRIMARY KEY \(ws=\?\)[\s\S]*SEARCH r USING INDEX .*\(ws=\? AND id=\?\)/);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("a completed NUL audit follows an update even when SQLite's first value stays the same", async () => {
  const f = fixture();
  try {
    f.put('"vault":"theirs","at":0');
    await f.secrets.preparePending("w", true);
    const update = f.db.prepare("UPDATE vault_requests SET body=? WHERE ws='w' AND id='r'");
    const body = (fields: string) => `{"ws":"w","id":"r","session":"s",${fields},"item":"r","mode":"env","status":"pending"}`;
    update.run(body('"vault\\u0000suffix":"theirs","vault":"mine","at":0'));
    assert.deepEqual(f.secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
    update.run(body('"vault":"theirs","at":0'));
    assert.deepEqual(f.secrets.pending("w", lock, viewer), []);
    assert.deepEqual(f.db.prepare("SELECT id FROM vault_pending_nul_v3 WHERE ws='w'").all(), []);
    update.run(body('"vault":"mine","at":0,"note":"a \\u0000 value"'));
    assert.deepEqual(f.secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
    assert.deepEqual(f.db.prepare("SELECT id FROM vault_pending_nul_v3 WHERE ws='w'").all(), []);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("a NUL audit catches writes on both sides of its cursor from another connection", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-pending-nul-")), path = join(dir, "data.sqlite");
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode=WAL");
  const other = new DatabaseSync(path), vaults = new VaultStore(db);
  vaults.putVault({ ws: "w", id: "mine", seq: 0, members: ["alice"] } as never);
  vaults.putVault({ ws: "w", id: "theirs", seq: 0, members: ["bob"] } as never);
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => lock,
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  const body = (id: string, nul: boolean) => `{"ws":"w","id":"${id}","session":"s",${nul ? '"vault\\u0000suffix":"theirs","vault":"mine"' : '"vault":"theirs"'},"at":0,"item":"i","mode":"env","status":"pending"}`;
  try {
    const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)");
    for (const id of ["a", "b", "c", "d"]) insert.run(id, body(id, id === "b" || id === "c"));
    await secrets.preparePending("w", true);
    db.exec("DELETE FROM vault_pending_nul_audit_v3; DELETE FROM vault_pending_nul_v3");
    const write = other.prepare("UPDATE vault_requests SET body=? WHERE ws='w' AND id=?");
    assert.equal(backfillPendingNulAudit(db, "w", 2), false);
    write.run(body("a", true), "a");
    write.run(body("b", false), "b");
    write.run(body("c", false), "c");
    write.run(body("d", true), "d");
    other.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','aa','s','pending',?)").run(body("aa", true));
    while (!backfillPendingNulAudit(db, "w", 2)) {}
    assert.deepEqual(db.prepare("SELECT id FROM vault_pending_nul_v3 WHERE ws='w' ORDER BY id").all().map((r) => r.id), ["a", "aa", "d"]);
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["a", "aa", "d"]);
  } finally { await secrets.close(); other.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an old connection's prepared write updates the NUL marker after the triggers are installed", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-pending-nul-old-")), path = join(dir, "data.sqlite");
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode=WAL");
  const vaults = new VaultStore(db);
  vaults.putVault({ ws: "w", id: "mine", seq: 0, members: ["alice"] } as never);
  vaults.putVault({ ws: "w", id: "theirs", seq: 0, members: ["bob"] } as never);
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => lock,
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  const old = new DatabaseSync(path);
  try {
    const normal = '{"ws":"w","id":"r","session":"s","vault":"theirs","at":0,"item":"i","mode":"env","status":"pending"}';
    const nul = '{"ws":"w","id":"r","session":"s","vault\\u0000suffix":"theirs","vault":"mine","at":0,"item":"i","mode":"env","status":"pending"}';
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s','pending',?)").run(normal);
    await secrets.preparePending("w", true);
    db.exec("DROP TRIGGER vault_pending_nul_add_v3; DROP TRIGGER vault_pending_nul_change_v3; DROP TRIGGER vault_pending_nul_drop_v3");
    const write = old.prepare("UPDATE vault_requests SET body=? WHERE ws='w' AND id='r'");
    initializePendingIndex(db);
    write.run(nul);
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
    write.run(normal);
    assert.deepEqual(secrets.pending("w", lock, viewer), []);
  } finally { await secrets.close(); old.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("NUL audit readiness and candidate reads use the same snapshot", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-pending-nul-snapshot-")), path = join(dir, "data.sqlite");
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode=WAL");
  const other = new DatabaseSync(path);
  let armed = false;
  const observed = new Proxy(db, { get(target, key) {
    if (key === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      if (sql !== "SELECT done FROM vault_pending_nul_audit_v3 WHERE ws = ?") return statement;
      return new Proxy(statement, { get(query, method) {
        if (method === "get") return (...args: never[]) => {
          const result = query.get(...args);
          if (armed) {
            armed = false;
            other.prepare("UPDATE vault_requests SET body=? WHERE ws='w' AND id='r'")
              .run('{"ws":"w","id":"r","session":"s","vault\\u0000suffix":"theirs","vault":"mine","at":0,"item":"i","mode":"env","status":"pending"}');
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
  vaults.putVault({ ws: "w", id: "mine", seq: 0, members: ["alice"] } as never);
  vaults.putVault({ ws: "w", id: "theirs", seq: 0, members: ["bob"] } as never);
  const secrets = new Secrets({ db: observed, data: ".", now: () => 0, home: () => "w", lock: () => lock,
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  try {
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s','pending',?)")
      .run('{"ws":"w","id":"r","session":"s","vault":"mine","at":0,"item":"i","mode":"env","status":"pending"}');
    await secrets.preparePending("w", true);
    armed = true;
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
    assert.equal(armed, false);
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["r"]);
  } finally { await secrets.close(); other.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const [name, fields, vault] of [
  ["duplicate vault", '"vault":"mine","vault":"theirs","at":0', "mine"],
  ["NUL-suffixed vault", '"vault\\u0000suffix":"mine","vault":"theirs","at":0', "mine"],
  ["duplicate owner", '"vault":"plain","owner":"alice@example.test","owner":"bob@example.test","at":0', "plain"],
  ["duplicate save", '"vault":"mine","save":null,"save":{"typed":true},"at":0', "mine"],
] as const) {
  test(`a ${name} cannot expose a use outside its parsed scope`, async () => {
    const f = fixture();
    try {
      f.put(fields, "granted");
      assert.deepEqual(await f.secrets.uses("w", vault === "plain" ? null : lock, vault, viewer), []);
    } finally { await f.secrets.close(); f.db.close(); }
  });
}
