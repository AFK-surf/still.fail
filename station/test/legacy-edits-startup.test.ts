import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { addEditIndex } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

for (const oldIndex of [false,true]) test(`opening an old store bounds edit-index installation (old index ${oldIndex})`, () => {
  const counts: number[] = [];
  for (const size of [40,400]) {
    const store=Store.open(":memory:"),db=store.db;
    try {
      const thread=store.openThread("ember","CHAT",`legacy-edits-install-${size}`,null,null).id;
      const put=db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,at) VALUES(?,?,'edit',1,'person','p',?)");
      for (let n=1;n<=size;n++) put.run(thread,n,n);
      db.exec(`DROP INDEX entries_edits; ${oldIndex ? "CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL" : ""}`);
      const visited=new Set<string>();
      db.function("visit_edit_install",{deterministic:true},(n) => { visited.add(String(n)); return 1; });
      const observed=new Proxy(db,{get(target,property) {
        if (property === "exec") return (sql: string) => {
          if (sql.includes("CREATE INDEX IF NOT EXISTS entries_edits")) {
            const traced=sql.replace("WHERE target IS NOT NULL","WHERE visit_edit_install(n) AND target IS NOT NULL");
            assert.notEqual(traced,sql); sql=traced;
          }
          return target.exec(sql);
        };
        if (property === "prepare") return (sql: string) => target.prepare(sql === "SELECT 1 FROM entries LIMIT 1 OFFSET 63"
          ? "SELECT 1 FROM entries WHERE visit_edit_install(n) LIMIT 1 OFFSET 63" : sql);
        const value=Reflect.get(target,property,target);
        return typeof value === "function" ? value.bind(target) : value;
      }}) as DatabaseSync;
      addEditIndex(observed);
      counts.push(visited.size);
      assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_edits'").get() !== undefined,size < 64);
      if (size > 64) assert.equal(db.prepare("SELECT old_index FROM legacy_edit_meta").get()?.old_index,oldIndex ? 1 : 0);
    } finally { store.close(); }
  }
  assert.deepEqual(counts,[40,64]);
});

for (const winner of ["old writes","native index"]) test(`edit installation rechecks ${winner} under the writer lock`, () => {
  const dir=mkdtempSync(join(tmpdir(),"legacy-edit-start-")),path=join(dir,"station.db");
  const store=Store.open(path),db=store.db;
  const thread=store.openThread("ember","CHAT","legacy-edit-race",null,null).id;
  const put=db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','p',?)");
  for (let n=1;n<=(winner === "old writes" ? 40 : 100);n++) put.run(thread,n,n);
  db.exec("DROP INDEX entries_edits");
  const old=new DatabaseSync(path,{timeout:5000});
  try {
    let begins=0;
    const observed=new Proxy(db,{get(target,property) {
      if (property === "exec") return (sql: string) => {
        if (sql === "BEGIN IMMEDIATE") {
          begins++;
          if (winner === "old writes" && begins === 1) {
            old.exec("BEGIN");
            const insert=old.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','p',?)");
            for (let n=41;n<=100;n++) insert.run(thread,n,n);
            old.exec("COMMIT");
          } else if (winner === "native index" && begins === 2) {
            old.exec("CREATE INDEX entries_edits ON entries(thread,target,n) WHERE target IS NOT NULL");
          }
        }
        return target.exec(sql);
      };
      const value=Reflect.get(target,property,target);
      return typeof value === "function" ? value.bind(target) : value;
    }}) as DatabaseSync;
    addEditIndex(observed);
    assert.equal(begins,2);
    const native=db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_edits'").get();
    const staged=db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='legacy_edit_meta'").get();
    assert.equal(native !== undefined,winner === "native index");
    assert.equal(staged !== undefined,winner === "old writes");
  } finally { old.close(); store.close(); rmSync(dir,{recursive:true,force:true}); }
});
