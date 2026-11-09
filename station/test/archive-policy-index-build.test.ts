import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { archivePolicyIndexNeedsWork, archivePolicyIndexStep, hasLegacyArchivePolicy, installArchivePolicyIndex, LEGACY_ARCHIVE_POLICY } from "../src/store/archive-policy-index.ts";

const schema = `CREATE TABLE archive_policy(id INTEGER PRIMARY KEY,at INTEGER NOT NULL,policy TEXT NOT NULL,
  author TEXT NOT NULL,summary TEXT NOT NULL,ws TEXT);`;
const indexes = (db: DatabaseSync, name: string) => db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name=?").get(name);
const insert = (db: DatabaseSync) => db.prepare("INSERT INTO archive_policy VALUES(?,?,?, ?,?,?)");
const keys = (db: DatabaseSync, table: string) => db.prepare(`SELECT CAST(id AS TEXT) id,ws FROM ${table} ORDER BY id`).all().map(r => ({...r}));
function seed(db: DatabaseSync, n: number) {
  const put = insert(db);
  for (let id=1; id<=n; id++) put.run(id,id,`policy${id}`,`author${id}`,`summary${id}`,id%3 === 0 ? null : `ws${id%3}`);
}
function finish(db: DatabaseSync, limit=7) {
  let batches=0;
  while (true) {
    const {done,visited} = archivePolicyIndexStep(db,limit);
    assert.ok(visited<=limit, `a batch visited ${visited} policies`);
    batches++;
    if (done) return batches;
    assert.ok(batches<1000, "preparation did not finish");
  }
}
function assertLookup(db: DatabaseSync) {
  const indexed=db.prepare(LEGACY_ARCHIVE_POLICY);
  const original=db.prepare("SELECT id,at,policy,author,summary FROM archive_policy WHERE ws IS ? ORDER BY id DESC LIMIT 1");
  for (const ws of ["ws1","ws2","missing",null]) assert.deepEqual(indexed.get(ws),original.get(ws));
}

test("small stores use the native index; large stores copy old policy rows in bounded batches", () => {
  for (const size of [40,400]) {
    const db = new DatabaseSync(":memory:");
    try {
      db.exec(schema); seed(db,size);
      let visited=0;
      db.function("visit_policy_install", {deterministic:true}, () => { visited++; return 1; });
      const observed = new Proxy(db, {get(target,property) {
        if (property === "prepare") return (sql: string) => target.prepare(sql === "SELECT 1 FROM archive_policy LIMIT 1 OFFSET 63"
          ? "SELECT 1 FROM archive_policy WHERE visit_policy_install() LIMIT 1 OFFSET 63" : sql);
        if (property === "exec") return (sql: string) => {
          if (sql === "CREATE INDEX IF NOT EXISTS archive_policy_by_ws ON archive_policy(ws)") {
            target.exec("CREATE INDEX archive_policy_instrumented ON archive_policy(ws) WHERE visit_policy_install()");
            target.exec("DROP INDEX archive_policy_instrumented");
          }
          return target.exec(sql);
        };
        const value=Reflect.get(target,property,target);
        return typeof value === "function" ? value.bind(target) : value;
      }});
      installArchivePolicyIndex(observed);
      assert.ok(visited <= 2*64, `installation visited ${visited} rows`);
      assert.equal(indexes(db,"archive_policy_by_ws") !== undefined,size<64);
      if (size<64) { assert.equal(hasLegacyArchivePolicy(db),false); continue; }
      assert.equal(hasLegacyArchivePolicy(db),true);
      assert.equal(keys(db,"archive_policy_lookup").length,0);
      assertLookup(db);
      assert.ok(finish(db)>1);
      assert.equal(archivePolicyIndexNeedsWork(db),false);
      assert.deepEqual(keys(db,"archive_policy_lookup"),keys(db,"archive_policy"));
      assertLookup(db);
      const plan = db.prepare(`EXPLAIN QUERY PLAN ${LEGACY_ARCHIVE_POLICY}`).all("ws1").map(r=>r.detail).join(" | ");
      assert.match(plan,/archive_policy_lookup_ws/);
    } finally { db.close(); }
  }
});

for (const journal of ["DELETE","WAL"]) for (const recursive of [false,true]) {
  test(`an older writer stays consistent through preparation (${journal}, recursive ${recursive})`, () => {
    const dir=mkdtempSync(join(tmpdir(),"archive-policy-build-")),path=join(dir,"store.db");
    const db=new DatabaseSync(path),old=new DatabaseSync(path);
    try {
      db.exec(`${schema} PRAGMA journal_mode=${journal}`);
      old.exec(`PRAGMA recursive_triggers=${recursive ? 1 : 0}`);
      const put=insert(old),replace=old.prepare("INSERT OR REPLACE INTO archive_policy VALUES(?,?,?,?,?,?)");
      seed(old,100);
      installArchivePolicyIndex(db);
      assert.deepEqual(archivePolicyIndexStep(db,7),{done:false,visited:7});
      assertLookup(db);
      replace.run(2,200,"replacement","author","replacement","ws2");
      old.prepare("UPDATE archive_policy SET ws=? WHERE id=?").run("ws1",50);
      old.prepare("UPDATE archive_policy SET id=? WHERE id=?").run(120,70);
      old.prepare("DELETE FROM archive_policy WHERE id=?").run(80);
      put.run(200,200,"new","author","new",null);
      old.prepare("INSERT OR IGNORE INTO archive_policy VALUES(?,?,?,?,?,?)").run(2,201,"ignored","author","ignored","ws1");
      assertLookup(db);
      finish(db);
      assert.deepEqual(keys(db,"archive_policy_lookup"),keys(db,"archive_policy"));
      assertLookup(db);
      replace.run(200,300,"later","author","later","ws1");
      old.prepare("DELETE FROM archive_policy WHERE id=99").run();
      assert.deepEqual(keys(db,"archive_policy_lookup"),keys(db,"archive_policy"));
      assertLookup(db);
    } finally { old.close(); db.close(); rmSync(dir,{recursive:true,force:true}); }
  });
}

for (const recursive of [false,true]) for (const installedFirst of [false,true]) {
  test(`nested old writes keep the lookup current (recursive ${recursive}, installed first ${installedFirst})`, () => {
    const db=new DatabaseSync(":memory:");
    try {
      db.exec(`${schema} PRAGMA recursive_triggers=${recursive ? 1 : 0}`); seed(db,80);
      const external = () => db.exec(`CREATE TRIGGER nested_policy AFTER INSERT ON archive_policy WHEN NEW.id=101 BEGIN
        INSERT OR REPLACE INTO archive_policy VALUES(2,300,'nested','a','nested','ws2');
        UPDATE archive_policy SET ws='ws1' WHERE id=3;
        DELETE FROM archive_policy WHERE id=4;
      END`);
      if (!installedFirst) external();
      installArchivePolicyIndex(db);
      if (installedFirst) external();
      archivePolicyIndexStep(db,7);
      insert(db).run(101,101,"new","a","new","ws1");
      assertLookup(db); finish(db);
      assert.deepEqual(keys(db,"archive_policy_lookup"),keys(db,"archive_policy"));
      assertLookup(db);
    } finally { db.close(); }
  });
}

test("a failed copy rolls back its rows and cursor and can be retried", () => {
  const db=new DatabaseSync(":memory:");
  try {
    db.exec(schema); seed(db,80); installArchivePolicyIndex(db);
    const before=db.prepare("SELECT * FROM archive_policy_lookup_meta").get();
    db.exec("CREATE TRIGGER fail_policy BEFORE INSERT ON archive_policy_lookup WHEN NEW.id=3 BEGIN SELECT RAISE(ABORT,'injected'); END");
    assert.throws(()=>archivePolicyIndexStep(db,7),/injected/);
    assert.deepEqual(db.prepare("SELECT * FROM archive_policy_lookup_meta").get(),before);
    assert.equal(keys(db,"archive_policy_lookup").length,0);
    db.exec("DROP TRIGGER fail_policy"); finish(db);
    assert.deepEqual(keys(db,"archive_policy_lookup"),keys(db,"archive_policy"));
  } finally { db.close(); }
});

test("preparation preserves integer keys beyond JavaScript's exact range", () => {
  const db=new DatabaseSync(":memory:");
  try {
    db.exec(schema); seed(db,65);
    const put=insert(db);
    put.run(9007199254740993n,1,"large1","a","one","large");
    put.run(9007199254740995n,1,"large2","a","two","large");
    installArchivePolicyIndex(db); finish(db,3);
    assert.deepEqual(keys(db,"archive_policy_lookup"),keys(db,"archive_policy"));
    const latest=db.prepare(`SELECT CAST(id AS TEXT) id FROM (${LEGACY_ARCHIVE_POLICY})`).get("large");
    assert.equal(latest?.id,"9007199254740995");
  } finally { db.close(); }
});

for (const winner of ["old writes","native index","another opener"] as const) {
  test(`installation rechecks ${winner} under the writer lock`, () => {
    const dir=mkdtempSync(join(tmpdir(),"archive-policy-race-")),path=join(dir,"store.db");
    const db=new DatabaseSync(path),old=new DatabaseSync(path,{timeout:5000});
    try {
      db.exec(`${schema} PRAGMA journal_mode=WAL`); seed(db,winner === "old writes" ? 40 : 100);
      let intercepted=false;
      const observed=new Proxy(db,{get(target,property) {
        if (property === "exec") return (sql: string) => {
          if (sql === "BEGIN IMMEDIATE" && !intercepted) {
            intercepted=true;
            if (winner === "old writes") {
              const put=insert(old);
              for (let id=41;id<=100;id++) put.run(id,id,"p","a","s","ws1");
            } else if (winner === "native index") old.exec("CREATE INDEX archive_policy_by_ws ON archive_policy(ws)");
            else installArchivePolicyIndex(old);
          }
          return target.exec(sql);
        };
        const value=Reflect.get(target,property,target);
        return typeof value === "function" ? value.bind(target) : value;
      }});
      installArchivePolicyIndex(observed);
      assert.equal(intercepted,true);
      assert.equal(indexes(db,"archive_policy_by_ws") !== undefined,winner === "native index");
      assert.equal(hasLegacyArchivePolicy(db),winner !== "native index");
      if (winner !== "native index") { finish(db); assert.deepEqual(keys(db,"archive_policy_lookup"),keys(db,"archive_policy")); }
    } finally { old.close(); db.close(); rmSync(dir,{recursive:true,force:true}); }
  });
}

test("a failed installation leaves existing policies intact and can be retried", () => {
  const db=new DatabaseSync(":memory:");
  try {
    db.exec(schema); seed(db,80);
    const before=keys(db,"archive_policy");
    db.exec("CREATE TRIGGER archive_policy_lookup_insert AFTER INSERT ON archive_policy BEGIN SELECT 1; END");
    assert.throws(()=>installArchivePolicyIndex(db),/already exists/);
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='archive_policy_lookup_meta'").get(),undefined);
    assert.deepEqual(keys(db,"archive_policy"),before);
    db.exec("DROP TRIGGER archive_policy_lookup_insert");
    installArchivePolicyIndex(db); finish(db);
    assert.deepEqual(keys(db,"archive_policy_lookup"),before);
  } finally { db.close(); }
});

for (const recursive of [false,true]) for (const first of [false,true]) for (const timing of ["BEFORE","AFTER"]) {
  for (const operation of ["INSERT","UPDATE","DELETE"]) {
    test(`nested ${timing} ${operation} keeps keys current (recursive ${recursive}, installed first ${first})`, () => {
      const db=new DatabaseSync(":memory:");
      try {
        db.exec(`${schema} PRAGMA recursive_triggers=${recursive ? 1 : 0}`); seed(db,80);
        if (operation !== "INSERT") insert(db).run(101,101,"new","a","new","ws1");
        const source=operation === "INSERT" ? "NEW" : "OLD";
        const external=()=>db.exec(`CREATE TRIGGER nested_action ${timing} ${operation} ON archive_policy WHEN ${source}.id=101 BEGIN
          INSERT OR REPLACE INTO archive_policy VALUES(2,300,'nested','a','nested','ws2');
          UPDATE archive_policy SET ws='ws1' WHERE id=3;
          DELETE FROM archive_policy WHERE id=4;
        END`);
        if (!first) external();
        installArchivePolicyIndex(db);
        if (first) external();
        archivePolicyIndexStep(db,7);
        if (operation === "INSERT") insert(db).run(101,101,"new","a","new","ws1");
        else if (operation === "UPDATE") db.exec("UPDATE archive_policy SET summary='changed' WHERE id=101");
        else db.exec("DELETE FROM archive_policy WHERE id=101");
        assertLookup(db); finish(db);
        assert.deepEqual(keys(db,"archive_policy_lookup"),keys(db,"archive_policy"));
        assertLookup(db);
      } finally { db.close(); }
    });
  }
}

test("a rolled-back older write does not leave policy lookup keys behind", () => {
  const db=new DatabaseSync(":memory:");
  try {
    db.exec(schema); seed(db,80); installArchivePolicyIndex(db); finish(db);
    db.exec("BEGIN");
    db.exec("UPDATE archive_policy SET ws='other' WHERE id=1; DELETE FROM archive_policy WHERE id=2;");
    insert(db).run(101,101,"new","a","new",null);
    db.exec("ROLLBACK");
    assert.deepEqual(keys(db,"archive_policy_lookup"),keys(db,"archive_policy"));
    assertLookup(db);
  } finally { db.close(); }
});

for (const recursive of [false,true]) for (const first of [false,true]) for (const timing of ["BEFORE","AFTER"]) {
  for (const prepared of [false,true]) {
    test(`a nested ${timing} replacement of the same policy id is exact (recursive ${recursive}, installed first ${first}, prepared ${prepared})`, () => {
      const db=new DatabaseSync(":memory:");
      try {
        db.exec(`${schema} PRAGMA recursive_triggers=${recursive ? 1 : 0}`); seed(db,80);
        const external=()=>db.exec(`CREATE TRIGGER nested_same ${timing} INSERT ON archive_policy WHEN NEW.summary='outer' BEGIN
          INSERT OR REPLACE INTO archive_policy VALUES(NEW.id,2,'nested','a','inner','ws2'); END`);
        if (!first) external();
        installArchivePolicyIndex(db);
        if (first) external();
        if (prepared) finish(db); else archivePolicyIndexStep(db,7);
        db.prepare("INSERT OR REPLACE INTO archive_policy VALUES(?,?,?,?,?,?)").run(101,1,"outer","a","outer","ws1");
        assertLookup(db);
        if (!prepared) finish(db);
        assert.deepEqual(keys(db,"archive_policy_lookup"),keys(db,"archive_policy"));
        assertLookup(db);
      } finally { db.close(); }
    });
  }
}
