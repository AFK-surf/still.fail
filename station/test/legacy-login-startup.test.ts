import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";
import { withoutLoginKeys } from "./legacy-login-fixture.ts";

test("an older store does not build the login-card index over all entries under one writer", () => {
  const counts: number[] = [];
  for (const size of [40,400]) {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("ember","CHAT",`legacy-login-${size}`,null,null).id;
      const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at,card) VALUES(?,?,'message','agent','a',?,?)");
      for (let n=1;n<=size;n++) put.run(thread,n,n,n%10 === 0 ? JSON.stringify({type:"login",login:`old${n}`}) : null);
      withoutLoginKeys(db);
      db.exec("DROP INDEX entries_login_cards");
      const visited = new Set<string>();
      db.function("visit_login_install", { deterministic: true }, (n) => { visited.add(String(n)); return 1; });
      const observed = new Proxy(db, { get(target,property) {
        if (property === "exec") return (sql: string) => {
          if (sql.includes("CREATE INDEX IF NOT EXISTS entries_login_cards")) {
            const traced = sql.replace("WHERE card LIKE", "WHERE visit_login_install(n) AND card LIKE");
            assert.notEqual(traced,sql);
            // Count the index build, then leave the original predicate in place for the preparation's indexed reads.
            target.exec(traced);
            target.exec("DROP INDEX entries_login_cards");
          }
          return target.exec(sql);
        };
        if (property === "prepare") return (sql: string) => target.prepare(sql === "SELECT 1 FROM entries LIMIT 1 OFFSET 63"
          ? "SELECT 1 FROM entries WHERE visit_login_install(n) LIMIT 1 OFFSET 63" : sql);
        const value = Reflect.get(target,property,target);
        return typeof value === "function" ? value.bind(target) : value;
      } }) as DatabaseSync;
      addClientColumn(observed);
      counts.push(visited.size);
    } finally { store.close(); }
  }
  assert.deepEqual(counts,[40,64]);
});

for (const winner of ["old writes","native index"]) test(`login-card installation rechecks ${winner} under the writer lock`, () => {
  const dir=mkdtempSync(join(tmpdir(),"legacy-login-start-")),path=join(dir,"station.db");
  const store=Store.open(path),db=store.db;
  const thread=store.openThread("ember","CHAT","legacy-login-race",null,null).id;
  const put=db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','agent','a',?)");
  for (let n=1;n<=(winner === "old writes" ? 40 : 100);n++) put.run(thread,n,n);
  withoutLoginKeys(db);
  db.exec("DROP INDEX entries_login_cards");
  const old=new DatabaseSync(path,{timeout:5000});
  try {
    let begins=0;
    const observed=new Proxy(db,{ get(target,property) {
      if (property === "exec") return (sql: string) => {
        if (sql === "BEGIN IMMEDIATE") {
          begins++;
          if (winner === "old writes" && begins === 1) {
            old.exec("BEGIN");
            const insert=old.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','agent','a',?)");
            for (let n=41;n<=100;n++) insert.run(thread,n,n);
            old.exec("COMMIT");
          } else if (winner === "native index" && begins === 2) {
            old.exec(`CREATE INDEX entries_login_cards ON entries(thread,n) WHERE card LIKE '%"login"%'`);
          }
        }
        return target.exec(sql);
      };
      const value=Reflect.get(target,property,target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    addClientColumn(observed);
    assert.equal(begins,2);
    const native=db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_login_cards'").get();
    const staged=db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='login_card_meta'").get();
    assert.equal(native !== undefined,winner === "native index");
    assert.ok(staged, "the per-login lookup is installed after either race");
  } finally { old.close(); store.close(); rmSync(dir,{recursive:true,force:true}); }
});
