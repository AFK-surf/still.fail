import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { makeStore, saidOf } from "../src/read/store.ts";
import { installLegacySaid, legacySaidStep } from "../src/store/legacy-said-build.ts";
import { installSaidState } from "../src/store/said-state.ts";
import { Store } from "../src/store/store.ts";

for (const mode of ["native", "legacy"]) for (const recursive of [false,true]) for (const op of ["insert", "update"])
  for (const guarded of [false,true])
  test(`rowid ${op} keeps another ${mode} thread's boundary exact (recursive ${recursive}, guarded ${guarded})`, () => {
    const store=Store.open(":memory:"), db=store.db;
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      const a=store.openThread("ember","CHAT",`a-${mode}-${recursive}-${op}`,null,null).id;
      const b=store.openThread("ember","CHAT",`b-${mode}-${recursive}-${op}`,null,null).id;
      const put=db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message',?,?,?)");
      put.run(a,1,"agent","worker",1);
      put.run(a,2,"person","bob",2);
      put.run(a,3,"person","alice",3);
      put.run(a,4,"person","alice",4);
      put.run(b,1,"agent","worker",1);
      if (mode === "legacy") {
        installLegacySaid(db);
        db.exec("DROP INDEX entries_said");
        installSaidState(db);
        while (!legacySaidStep(db,64).ready) { /* prepare */ }
      }
      if (guarded) {
        db.prepare("UPDATE thread_state SET said_other_known=0 WHERE thread=?").run(a);
        db.prepare("INSERT INTO said_state_guard(thread,token,author,other_n,ready) VALUES(?,'scan','alice',2,1)").run(a);
      }
      assert.deepEqual(saidOf(makeStore(db,"/none"),a),{ n:4,authorKind:"person",author:"alice",other:2 });
      const id=db.prepare("SELECT rowid AS id FROM entries WHERE thread=? AND n=2").get(a)!.id;
      if (op === "insert") db.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,kind,author_kind,author,at)
        VALUES(?,?,2,'message','person','other',2)`).run(id,b);
      else db.prepare("UPDATE OR REPLACE entries SET rowid=? WHERE thread=? AND n=1").run(id,b);
      if (guarded) assert.equal(db.prepare("SELECT token FROM said_state_guard WHERE thread=?").get(a),undefined);
      assert.deepEqual(saidOf(makeStore(db,"/none"),a),{ n:4,authorKind:"person",author:"alice",other:1 });
    } finally { store.close(); }
  });

for (const mode of ["native", "legacy"]) test(`a rowid replacement by an edit invalidates the displaced ${mode} thread`, () => {
  const store=Store.open(":memory:"), db=store.db;
  try {
    const a=store.openThread("ember","CHAT",`a-edit-${mode}`,null,null).id;
    const b=store.openThread("ember","CHAT",`b-edit-${mode}`,null,null).id;
    const put=db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message',?,?,?)");
    put.run(a,1,"agent","worker",1);
    put.run(a,2,"person","bob",2);
    put.run(a,3,"person","alice",3);
    db.prepare("UPDATE entries SET rowid=-1 WHERE thread=? AND n=2").run(a);
    if (mode === "legacy") {
      installLegacySaid(db);
      db.exec("DROP INDEX entries_said");
      installSaidState(db);
      while (!legacySaidStep(db,64).ready) { /* prepare */ }
    }
    db.prepare("UPDATE thread_state SET said_other_known=1,said_other_n=2 WHERE thread=?").run(a);
    db.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,kind,author_kind,author,at)
      VALUES(-1,?,1,'edit','agent','worker',1)`).run(b);
    assert.deepEqual(saidOf(makeStore(db,"/none"),a),{ n:3,authorKind:"person",author:"alice",other:1 });
  } finally { store.close(); }
});

for (const mode of ["native", "legacy"]) for (const alias of ["rowid", "_rowid_", "oid"])
  test(`a ${mode} update through ${alias} invalidates the displaced thread`, () => {
    const store=Store.open(":memory:"), db=store.db;
    try {
      const a=store.openThread("ember","CHAT",`alias-a-${mode}-${alias}`,null,null).id;
      const b=store.openThread("ember","CHAT",`alias-b-${mode}-${alias}`,null,null).id;
      const put=db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message',?,?,?)");
      put.run(a,1,"agent","worker",1);
      put.run(a,2,"person","bob",2);
      put.run(a,3,"person","alice",3);
      put.run(b,1,"agent","worker",1);
      if (mode === "legacy") {
        installLegacySaid(db);
        db.exec("DROP INDEX entries_said");
        installSaidState(db);
        while (!legacySaidStep(db,64).ready) { /* prepare */ }
      }
      assert.deepEqual(saidOf(makeStore(db,"/none"),a),{ n:3,authorKind:"person",author:"alice",other:2 });
      const id=db.prepare("SELECT rowid AS id FROM entries WHERE thread=? AND n=2").get(a)!.id;
      db.prepare(`UPDATE OR REPLACE entries SET ${alias}=? WHERE thread=? AND n=1`).run(id,b);
      assert.deepEqual(saidOf(makeStore(db,"/none"),a),{ n:3,authorKind:"person",author:"alice",other:1 });
    } finally { store.close(); }
  });

test("a text-only edit does not run the sidebar invalidation trigger", () => {
  const store=Store.open(":memory:"), db=store.db;
  try {
    const thread=store.openThread("ember","CHAT","text-only-sidebar",null,null).id;
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,1,'message','person','bob',1)").run(thread);
    let invoked=false;
    db.setAuthorizer((action, _table, _column, _dbName, source) => {
      if (source === "said_state_before_update") invoked=true;
      return constants.SQLITE_OK;
    });
    try { db.prepare("UPDATE entries SET text='changed' WHERE thread=? AND n=1").run(thread); }
    finally { db.setAuthorizer(null); }
    assert.equal(invoked,false);
    assert.deepEqual(saidOf(makeStore(db,"/none"),thread),{ n:1,authorKind:"person",author:"bob",other:null });
  } finally { store.close(); }
});

test("an old native store upgrades its sidebar triggers", () => {
  const store=Store.open(":memory:"), db=store.db;
  try {
    const a=store.openThread("ember","CHAT","rowid-old-native-a",null,null).id;
    const b=store.openThread("ember","CHAT","rowid-old-native-b",null,null).id;
    const put=db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message',?,?,?)");
    put.run(a,1,"agent","worker",1);
    put.run(a,2,"person","bob",2);
    put.run(a,3,"person","alice",3);
    put.run(b,1,"agent","worker",1);
    db.exec(`DROP TRIGGER said_state_before_insert; DROP TRIGGER thread_state_add; DROP TRIGGER said_state_before_update;
      CREATE TRIGGER said_state_before_insert BEFORE INSERT ON entries BEGIN
        SELECT n FROM entries INDEXED BY entries_said WHERE thread=NEW.thread AND kind='message' AND letter IS NULL LIMIT 1;
      END;
      CREATE TRIGGER thread_state_add AFTER INSERT ON entries BEGIN SELECT 1; END;
      CREATE TRIGGER said_state_before_update BEFORE UPDATE OF thread,n,kind,author_kind,author,letter,ts ON entries BEGIN SELECT 1; END;`);
    installSaidState(db);
    const before=String(db.prepare("SELECT sql FROM sqlite_master WHERE type='trigger' AND name='thread_state_add'").get()!.sql);
    installSaidState(db);
    assert.equal(db.prepare("SELECT sql FROM sqlite_master WHERE type='trigger' AND name='thread_state_add'").get()!.sql,before);
    const id=db.prepare("SELECT rowid AS id FROM entries WHERE thread=? AND n=2").get(a)!.id;
    db.prepare("UPDATE OR REPLACE entries SET rowid=? WHERE thread=? AND n=1").run(id,b);
    assert.deepEqual(saidOf(makeStore(db,"/none"),a),{ n:3,authorKind:"person",author:"alice",other:1 });
  } finally { store.close(); }
});
