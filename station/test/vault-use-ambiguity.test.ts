import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { backfillUseAudit, backfillUsePreparation, initializeUseIndex, PLAIN_USES_AMBIGUOUS,
  repairAmbiguousUses, tryReadUses, UseIndex, VAULT_USES_AMBIGUOUS } from "../src/vault/use-index.ts";

function database(path = ":memory:") {
  const db = new DatabaseSync(path);
  db.exec(`CREATE TABLE vault_requests (ws TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL,
    status TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY (ws,id));`);
  initializeUseIndex(db);
  return db;
}

const body = (id: string, fields: string) => `{"item":"${id}","session":"s","status":"granted",${fields}}`;
const query = (vault = "v", owner: string | null = null, limit = 10) => ({ id: 1, ws: "w", vault, owner, limit });
const items = (bodies: string[] | null) => bodies?.map((value) => (JSON.parse(value) as { item: string }).item) ?? null;
const prepare = (db: DatabaseSync) => { while (!backfillUsePreparation(db, "w")) {} };

test("a limited page merges corrected and ordinary uses in time and id order", async () => {
  const db = database(), index = new UseIndex(db);
  try {
    const put = db.prepare("INSERT INTO vault_requests VALUES('w',?,'s','granted',?)");
    put.run("a", body("a", '"vault":"v","at":20'));
    put.run("b", body("b", '"vault":"wrong","vault":"v","at":20'));
    put.run("c", body("c", '"vault":"v","at":99,"at":19'));
    put.run("d", body("d", '"vault":"v","vault":"wrong","at":100'));
    put.run("e", body("e", '"vault":"v","save":{"typed":true},"save":null,"at":18'));
    put.run("f", body("f", '"vault":"v","save":null,"save":{"typed":true},"at":101'));
    assert.deepEqual(items(await index.read("w", "v", null, 3)), ["b", "a", "c"]);
    assert.deepEqual(items(await index.read("w", "v", null, 10)), ["b", "a", "c", "e"]);
    assert.deepEqual(items(await index.read("w", "wrong", null, 2)), ["d"]);
  } finally { await index.close(); db.close(); }
});

test("isolated high and low surrogate identities remain distinct from each other and the replacement character", async () => {
  const db = database(), index = new UseIndex(db);
  try {
    const put = db.prepare("INSERT INTO vault_requests VALUES('w',?,'s','granted',?)");
    const owners = ["\ud800@example.test", "\udc00@example.test", "\ufffd@example.test"];
    for (let i = 0; i < owners.length; i++) put.run(`r${i}`, body(`r${i}`, `"vault":"plain","owner":${JSON.stringify(owners[i])},"at":${i}`));
    for (let i = 0; i < owners.length; i++) assert.deepEqual(items(await index.read("w", "plain", owners[i], 10)), [`r${i}`]);
    const vaults = ["\ud800", "\udc00", "\ufffd"];
    for (let i = 0; i < vaults.length; i++) put.run(`v${i}`, body(`v${i}`, `"vault":${JSON.stringify(vaults[i])},"at":${i}`));
    for (let i = 0; i < vaults.length; i++) assert.deepEqual(items(await index.read("w", vaults[i], null, 10)), [`v${i}`]);
  } finally { await index.close(); db.close(); }
});

test("embedded NUL identity values remain distinct from their prefixes", async () => {
  const db = database(), index = new UseIndex(db);
  try {
    const put = db.prepare("INSERT INTO vault_requests VALUES('w',?,'s','granted',?)");
    for (const [i, owner] of ["alice@example.test", "alice@example.test\0x"].entries())
      put.run(`p${i}`, body(`p${i}`, `"vault":"plain","owner":${JSON.stringify(owner)},"at":${i}`));
    assert.deepEqual(items(await index.read("w", "plain", "alice@example.test", 10)), ["p0"]);
    assert.deepEqual(items(await index.read("w", "plain", "alice@example.test\0x", 10)), ["p1"]);
    for (const [i, vault] of ["v", "v\0x"].entries())
      put.run(`v${i}`, body(`v${i}`, `"vault":${JSON.stringify(vault)},"at":${i}`));
    assert.deepEqual(items(await index.read("w", "v", null, 10)), ["v0"]);
    assert.deepEqual(items(await index.read("w", "v\0x", null, 10)), ["v1"]);
  } finally { await index.close(); db.close(); }
});

test("an empty vault or owner remains an exact identity for an exceptional use", async () => {
  const db = database(), index = new UseIndex(db);
  try {
    const put = db.prepare("INSERT INTO vault_requests VALUES('w',?,'s','granted',?)");
    put.run("v", body("v", '"vault":"wrong","vault":"","at":1'));
    put.run("p", body("p", '"vault":"plain","owner":"wrong","owner":"","at":2'));
    assert.deepEqual(items(await index.read("w", "", null, 10)), ["v"]);
    assert.deepEqual(items(await index.read("w", "plain", "", 10)), ["p"]);
  } finally { await index.close(); db.close(); }
});

test("an exceptional use does not make a large stored timestamp unreadable", async () => {
  const db = database(), index = new UseIndex(db);
  try {
    const put = db.prepare("INSERT INTO vault_requests VALUES('w',?,'s','granted',?)");
    put.run("large", body("large", '"vault":"v","at":9007199254740993'));
    put.run("small", body("small", '"vault":"plain","owner":"alice","at":-9007199254740993'));
    put.run("other", body("other", '"vault":"wrong","vault":"elsewhere","at":1'));
    assert.deepEqual(items(await index.read("w", "v", null, 10)), ["large"]);
    assert.deepEqual(items(await index.read("w", "plain", "alice", 10)), ["small"]);
  } finally { await index.close(); db.close(); }
});

test("an old index is audited in batches while an older prepared writer changes both sides of the cursor", () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-use-audit-")), path = join(dir, "data.sqlite");
  const db = new DatabaseSync(path);
  db.exec(`PRAGMA journal_mode=WAL; CREATE TABLE vault_requests (ws TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL,
    status TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY (ws,id));`);
  const other = new DatabaseSync(path);
  const put = other.prepare(`INSERT INTO vault_requests VALUES('w',?,'s','granted',?)
    ON CONFLICT(ws,id) DO UPDATE SET status=excluded.status,body=excluded.body`);
  initializeUseIndex(db);
  const normal = (id: string, at: number) => body(id, `"vault":"v","at":${at}`);
  const ambiguous = (id: string, at: number) => body(id, `"vault":"wrong","vault":"v","at":${at}`);
  try {
    for (const [i, id] of ["a", "b", "c", "d"].entries()) put.run(id, id === "b" ? ambiguous(id, i) : normal(id, i));
    prepare(db);
    // The preceding version had only the SQLite JSON-path index.
    db.exec("DELETE FROM vault_use_ambiguous_v2; DELETE FROM vault_use_ambiguous_audit_v2");
    assert.equal(tryReadUses(db, query()), null);
    assert.equal(backfillUseAudit(db, "w", 2), false);
    put.run("a", ambiguous("a", 8));
    put.run("b", normal("b", 7));
    put.run("d", ambiguous("d", 6));
    while (!backfillUseAudit(db, "w", 2)) {}
    assert.equal(tryReadUses(db, query()), null, "dirty exceptional requests cannot be read yet");
    while (!repairAmbiguousUses(db, "w", 2)) {}
    assert.deepEqual(items(tryReadUses(db, query())), ["a", "b", "d", "c"]);
    put.run("a", normal("a", 1));
    assert.deepEqual(items(tryReadUses(db, query())), ["b", "d", "c", "a"]);
  } finally { other.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("failed audit and repair batches roll their cursors and dirty rows back", () => {
  const db = database();
  try {
    db.prepare("INSERT INTO vault_requests VALUES('w','r','s','granted',?)")
      .run(body("r", '"vault":"wrong","vault":"v","at":1'));
    prepare(db);
    db.exec("DELETE FROM vault_use_ambiguous_v2; DELETE FROM vault_use_ambiguous_audit_v2");
    db.exec("CREATE TRIGGER fail_audit BEFORE INSERT ON vault_use_ambiguous_v2 BEGIN SELECT RAISE(ABORT,'audit failure'); END");
    assert.throws(() => backfillUseAudit(db, "w"), /audit failure/);
    assert.equal(db.prepare("SELECT 1 FROM vault_use_ambiguous_audit_v2 WHERE ws='w'").get(), undefined);
    db.exec("DROP TRIGGER fail_audit");
    assert.equal(backfillUseAudit(db, "w"), true);
    db.exec("CREATE TRIGGER fail_repair BEFORE UPDATE ON vault_use_ambiguous_v2 BEGIN SELECT RAISE(ABORT,'repair failure'); END");
    assert.throws(() => repairAmbiguousUses(db, "w"), /repair failure/);
    assert.equal((db.prepare("SELECT dirty FROM vault_use_ambiguous_v2 WHERE ws='w' AND id='r'").get() as { dirty: number }).dirty, 1);
    db.exec("DROP TRIGGER fail_repair");
    assert.equal(repairAmbiguousUses(db, "w"), true);
    assert.deepEqual(items(tryReadUses(db, query())), ["r"]);
  } finally { db.close(); }
});

for (const recursive of [false, true]) test(`rowid replacement does not return an unrelated use (recursive: ${recursive})`, () => {
  const db = database();
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    db.prepare("INSERT INTO vault_requests VALUES('w','old','s','granted',?)")
      .run(body("old", '"vault":"wrong","vault":"v","at":1'));
    prepare(db);
    const row = db.prepare("SELECT rowid AS n FROM vault_requests WHERE ws='w' AND id='old'").get() as { n: number };
    db.prepare("INSERT OR REPLACE INTO vault_requests(rowid,ws,id,session,status,body) VALUES(?,'w','new','s','granted',?)")
      .run(row.n, body("new", '"vault":"other","at":2'));
    assert.deepEqual(items(tryReadUses(db, query())), []);
    assert.deepEqual(items(tryReadUses(db, query("other"))), ["new"]);
  } finally { db.close(); }
});

test("readiness and page selection see the same WAL snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-use-snapshot-")), path = join(dir, "data.sqlite");
  const db = database(path);
  db.exec("PRAGMA journal_mode=WAL");
  const other = new DatabaseSync(path);
  try {
    db.prepare("INSERT INTO vault_requests VALUES('w','r','s','granted',?)").run(body("r", '"vault":"v","at":1'));
    prepare(db);
    let changed = false;
    const observed = new Proxy(db, { get(target, key) {
      if (key === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!sql.includes("dirty = 1 LIMIT 1")) return statement;
        return new Proxy(statement, { get(query, method) {
          if (method === "get") return (...args: never[]) => {
            const row = query.get(...args);
            if (!changed) {
              changed = true;
              other.prepare("UPDATE vault_requests SET body=? WHERE ws='w' AND id='r'")
                .run(body("r", '"vault":"v","vault":"other","at":1'));
            }
            return row;
          };
          const value = Reflect.get(query, method, query);
          return typeof value === "function" ? value.bind(query) : value;
        } });
      };
      const value = Reflect.get(target, key, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(items(tryReadUses(observed, query())), ["r"]);
    assert.equal(tryReadUses(db, query()), null);
    assert.equal(repairAmbiguousUses(db, "w"), true);
    assert.deepEqual(items(tryReadUses(db, query())), []);
    assert.deepEqual(items(tryReadUses(db, query("other"))), ["r"]);
  } finally { other.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a dirty exceptional use is recovered by the file-backed reader after reopening", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-use-reopen-")), path = join(dir, "data.sqlite");
  let db = database(path);
  db.exec("PRAGMA journal_mode=WAL");
  db.prepare("INSERT INTO vault_requests VALUES('w','r','s','granted',?)")
    .run(body("r", '"vault":"wrong","vault":"v","at":1'));
  prepare(db);
  db.prepare("UPDATE vault_requests SET body=? WHERE ws='w' AND id='r'")
    .run(body("r", '"vault":"wrong","vault":"v","at":2'));
  assert.equal(tryReadUses(db, query()), null);
  db.close();
  db = new DatabaseSync(path);
  const index = new UseIndex(db);
  try {
    assert.deepEqual(items(await index.read("w", "v", null, 10)), ["r"]);
    assert.equal((db.prepare("SELECT dirty FROM vault_use_ambiguous_v2 WHERE ws='w' AND id='r'").get() as { dirty: number }).dirty, 0);
  } finally { await index.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a use page leaves its caller's outer transaction under the caller's control", () => {
  const db = database();
  try {
    db.prepare("INSERT INTO vault_requests VALUES('w','r','s','granted',?)")
      .run(body("r", '"vault":"wrong","vault":"v","at":1'));
    prepare(db);
    db.exec("BEGIN");
    assert.deepEqual(items(tryReadUses(db, query())), ["r"]);
    db.prepare("DELETE FROM vault_requests WHERE ws='w' AND id='r'").run();
    db.exec("ROLLBACK");
    assert.deepEqual(items(tryReadUses(db, query())), ["r"]);
  } finally { db.close(); }
});

test("both halves of an exceptional page use their scoped time indexes", () => {
  const db = database();
  try {
    const shared = (db.prepare(`EXPLAIN QUERY PLAN ${VAULT_USES_AMBIGUOUS}`)
      .all("w", "v", Buffer.from("v", "utf16le"), 1, 10) as { detail: string }[]).map((r) => r.detail).join("\n");
    const plain = (db.prepare(`EXPLAIN QUERY PLAN ${PLAIN_USES_AMBIGUOUS}`)
      .all("w", "plain", "a", Buffer.from("plain", "utf16le"), Buffer.from("a", "utf16le"), 1, 10) as { detail: string }[])
      .map((r) => r.detail).join("\n");
    assert.match(shared, /SEARCH u USING COVERING INDEX vault_use_lookup_vault \(ws=\? AND vault=\?\)/);
    assert.match(shared, /SEARCH a USING (?:COVERING )?INDEX vault_use_ambiguous_vault_v2 \(ws=\? AND vault=\?\)/);
    assert.match(plain, /SEARCH u USING COVERING INDEX vault_use_lookup_owner \(ws=\? AND vault=\? AND owner=\?\)/);
    assert.match(plain, /SEARCH a USING (?:COVERING )?INDEX vault_use_ambiguous_owner_v2 \(ws=\? AND vault=\? AND owner=\?\)/);
    assert.doesNotMatch(`${shared}\n${plain}`, /TEMP B-TREE/);
  } finally { db.close(); }
});
