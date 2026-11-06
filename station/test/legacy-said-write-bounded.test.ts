import assert from "node:assert/strict";
import type { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { makeStore, saidOf } from "../src/read/store.ts";
import { installLegacySaid, legacySaidStep } from "../src/store/legacy-said-build.ts";
import { installSaidState } from "../src/store/said-state.ts";
import { Store } from "../src/store/store.ts";

function traceWrites(db: DatabaseSync, trace: (sql: string) => string): void {
  let replaced = 0;
  for (const name of ["said_state_before_insert", "thread_state_add"]) {
    const original = String(db.prepare("SELECT sql FROM sqlite_master WHERE type='trigger' AND name=?").get(name)!.sql);
    const traced = trace(original);
    if (traced !== original) { db.exec(`DROP TRIGGER ${name}; ${traced}`); replaced++; }
  }
  assert.ok(replaced > 0, "instrument the installed write triggers");
}

for (const scenario of ["changed-away", "ignored"] as const) test(`an old writer's append skips ${scenario} messages`, () => {
  const visits: number[] = [];
  for (const size of [80, 800]) {
    const store = Store.open(":memory:");
    const db = store.db;
    try {
      const thread = store.openThread("ember", "CHAT", `said-${scenario}-${size}`, null, null).id;
      const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,letter,ts,at)
        VALUES(?,?,'message','person','alice',NULL,?,?)`);
      put.run(thread, 1, "occupied", 1);
      if (scenario === "changed-away") for (let n = 2; n <= size + 1; n++) put.run(thread,n,`t-${n}`,n);
      installLegacySaid(db);
      db.exec("DROP INDEX entries_said");
      installSaidState(db);
      while (!legacySaidStep(db, 64).ready) { /* prepare */ }
      if (scenario === "changed-away") db.prepare("UPDATE entries SET letter='letter' WHERE thread=? AND n>1").run(thread);
      else {
        const ignored = db.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,author_kind,author,ts,at)
          VALUES(?,?,'message','person','alice','occupied',?)`);
        for (let n = 2; n <= size + 1; n++) ignored.run(thread,n,n);
      }
      let visited = 0;
      db.function("visit_pending_said_write", (n) => { visited++; return n; });
      traceWrites(db, (sql) => sql.replaceAll("CROSS JOIN entries e ON e.thread=d.thread AND e.n=d.n",
        "CROSS JOIN entries e ON e.thread=d.thread AND e.n=visit_pending_said_write(d.n)")
        .replaceAll("FROM entries WHERE thread=NEW.thread",
          "FROM entries WHERE thread=NEW.thread AND visit_pending_said_write(n)=n"));
      visited = 0;
      put.run(thread,size+2,"new",size+2);
      visits.push(visited);
      assert.ok(visited > 0, "the append executed the traced lookup");
      assert.deepEqual(saidOf(makeStore(db,"/none"),thread),
        { n:size+2,authorKind:"person",author:"alice",other:null });
    } finally { store.close(); }
  }
  assert.ok(visits[1]! <= visits[0]! + 4 && visits[1]! <= 150, `${scenario} candidates visited by append: ${visits.join(" / ")}`);
});

for (const prepared of [false, true]) for (const tail of [0, 63, 64, 65, 129])
  for (const author of ["alice", "bob"]) test(`an old append keeps its sidebar answer (${prepared ? "prepared" : "preparing"}, ${tail} edits, ${author})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("ember", "CHAT", `said-tail-${prepared}-${tail}-${author}`, null, null).id;
      const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at)
        VALUES(?,?,?,?,?,?)`);
      put.run(thread,1,"message","agent","worker",1);
      put.run(thread,2,"message","person","alice",2);
      for (let n = 3; n < tail + 3; n++) put.run(thread,n,"edit","agent","worker",n);
      installLegacySaid(db);
      db.exec("DROP INDEX entries_said");
      installSaidState(db);
      if (prepared) while (!legacySaidStep(db,64).ready) { /* prepare */ }
      db.prepare(`INSERT INTO said_state_guard(thread,token,author,other_n,ready) VALUES(?,'existing','alice',1,1)
        ON CONFLICT(thread) DO UPDATE SET token=excluded.token,author=excluded.author,other_n=excluded.other_n,ready=1`).run(thread);

      put.run(thread,tail+3,"message","person",author,tail+3);
      const state = db.prepare("SELECT said_other_known,said_other_n FROM thread_state WHERE thread=?").get(thread)!;
      const provable = prepared || tail <= 64;
      if (provable) assert.deepEqual({ ...state }, { said_other_known: 1, said_other_n: author === "alice" ? 1 : 2 });
      else assert.equal(state.said_other_known, 0, "a boundary beyond the probe remains unknown");
      assert.equal(db.prepare("SELECT token FROM said_state_guard WHERE thread=?").get(thread)?.token,
        author === "alice" && provable ? "existing" : undefined);
      assert.deepEqual(saidOf(makeStore(db,"/none"),thread), {
        n:tail+3,authorKind:"person",author,other:author === "alice" ? 1 : 2,
      });
    } finally { store.close(); }
  });

for (const dirty of [0, 63, 64, 65]) test(`a prepared old lookup handles ${dirty} pending keys before an append`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", `old-said-dirty-${dirty}`, null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES(?,?,?,?,?,?,?)");
    put.run(thread,1,"message","agent","worker","first",1);
    put.run(thread,2,"message","person","alice","occupied",2);
    for (let n=3;n<=70;n++) put.run(thread,n,"edit","agent","worker",`edit-${n}`,n);
    installLegacySaid(db);
    db.exec("DROP INDEX entries_said");
    installSaidState(db);
    while (!legacySaidStep(db,64).ready) { /* prepare */ }
    const ignored = db.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,author_kind,author,ts,at)
      VALUES(?,?,'message','person','alice','occupied',?)`);
    for (let n=0;n<Math.max(0,dirty-1);n++) ignored.run(thread,100+n,100+n);
    assert.equal(db.prepare("SELECT COUNT(*) AS c FROM legacy_said_dirty WHERE thread=?").get(thread)?.c,dirty);
    db.prepare("UPDATE thread_state SET said_other_known=1,said_other_n=1 WHERE thread=?").run(thread);
    db.prepare(`INSERT INTO said_state_guard(thread,token,author,other_n,ready) VALUES(?,'existing','alice',1,1)
      ON CONFLICT(thread) DO UPDATE SET token=excluded.token,author=excluded.author,other_n=excluded.other_n,ready=1`).run(thread);
    put.run(thread,1000,"message","person","alice","new",1000);
    assert.equal(db.prepare("SELECT said_other_known FROM thread_state WHERE thread=?").get(thread)?.said_other_known,dirty<=64 ? 1 : 0);
    assert.equal(db.prepare("SELECT token FROM said_state_guard WHERE thread=?").get(thread)?.token,dirty<=64 ? "existing" : undefined);
    assert.deepEqual(saidOf(makeStore(db,"/none"),thread),{ n:1000,authorKind:"person",author:"alice",other:1 });
  } finally { store.close(); }
});

for (const dirty of [0, 63]) test(`a prepared old write skips unrelated history with ${dirty} pending keys`, () => {
  const visits: number[] = [];
  for (const size of [80, 800, 8000]) {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("ember", "CHAT", `prepared-said-${dirty}-${size}`, null, null).id;
      const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,?,?,?,?)");
      for (let n=1;n<=size;n++) put.run(thread,n,"message",n===1 ? "agent" : "person",n===1 ? "worker" : "alice",n);
      for (let n=size+1;n<=size+70;n++) put.run(thread,n,"edit","agent","worker",n);
      installLegacySaid(db);
      db.exec("DROP INDEX entries_said");
      installSaidState(db);
      while (!legacySaidStep(db,64).ready) { /* prepare */ }
      if (dirty) db.prepare("UPDATE entries SET letter='letter' WHERE thread=? AND n>? AND n<=?")
        .run(thread,size-dirty,size);
      db.prepare(`INSERT INTO said_state_guard(thread,token,author,other_n,ready) VALUES(?,'existing','alice',1,1)
        ON CONFLICT(thread) DO UPDATE SET token=excluded.token,author=excluded.author,other_n=excluded.other_n,ready=1`).run(thread);
      let visited = 0;
      db.function("visit_prepared_said_write", (n) => { visited++; return n; });
      traceWrites(db, (sql) => sql.replaceAll("s.thread=NEW.thread", "s.thread=NEW.thread AND visit_prepared_said_write(s.n)=s.n")
        .replaceAll("CROSS JOIN entries e ON e.thread=d.thread AND e.n=d.n",
          "CROSS JOIN entries e ON e.thread=d.thread AND e.n=visit_prepared_said_write(d.n)")
        .replaceAll("FROM entries WHERE thread=NEW.thread", "FROM entries WHERE thread=NEW.thread AND visit_prepared_said_write(n)=n"));
      visited = 0;
      put.run(thread,size+71,"message","person","bob",size+71);
      visits.push(visited);
      assert.ok(visited > 0, "the append executed the traced lookup");
      assert.deepEqual(saidOf(makeStore(db,"/none"),thread),
        { n:size+71,authorKind:"person",author:"bob",other:size-dirty });
    } finally { store.close(); }
  }
  assert.ok(visits[2]! <= visits[0]! + 4 && visits[2]! < 500, `prepared candidates visited by append: ${visits.join(" / ")}`);
});

test("an old edit does not probe the previous messages", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "old-said-edit-probe", null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,?,?,?,?)");
    put.run(thread,1,"message","person","alice",1);
    installLegacySaid(db);
    db.exec("DROP INDEX entries_said");
    installSaidState(db);
    while (!legacySaidStep(db,64).ready) { /* prepare */ }
    let visited = 0;
    db.function("visit_said_edit", (n) => { visited++; return n; });
    traceWrites(db, (sql) => sql.replaceAll("FROM entries WHERE thread=NEW.thread",
      "FROM entries WHERE thread=NEW.thread AND visit_said_edit(n)=n"));
    visited = 0;
    put.run(thread,2,"edit","agent","worker",2);
    assert.equal(visited,0);
    assert.deepEqual(saidOf(makeStore(db,"/none"),thread),{ n:1,authorKind:"person",author:"alice",other:null });
  } finally { store.close(); }
});

test("a prepared old write preserves message keys beyond JavaScript's exact integer range", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "prepared-said-wide-key", null, null).id;
    const base = 9007199254741000n;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,?,?,?,1)");
    put.run(thread,base,"message","agent","worker");
    put.run(thread,base+1n,"message","person","alice");
    for (let n=2n;n<=71n;n++) put.run(thread,base+n,"edit","agent","worker");
    installLegacySaid(db);
    db.exec("DROP INDEX entries_said");
    installSaidState(db);
    while (!legacySaidStep(db,64).ready) { /* prepare */ }
    put.run(thread,base+72n,"message","person","bob");
    const state = db.prepare("SELECT said_other_known, CAST(said_other_n AS TEXT) AS n FROM thread_state WHERE thread=?").get(thread);
    assert.deepEqual({ ...state }, { said_other_known: 1, n: String(base+1n) });
  } finally { store.close(); }
});

test("an old store replaces previously installed message-state triggers", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "old-said-trigger", null, null).id;
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at)
      VALUES(?,?,'message','person',?,?)`);
    put.run(thread,1,"alice",1);
    installLegacySaid(db);
    db.exec(`DROP INDEX entries_said;
      DROP TRIGGER said_state_before_insert; DROP TRIGGER thread_state_add;
      CREATE TRIGGER said_state_before_insert BEFORE INSERT ON entries BEGIN
        SELECT n FROM legacy_said WHERE thread=NEW.thread ORDER BY n DESC LIMIT 1;
      END;
      CREATE TRIGGER thread_state_add AFTER INSERT ON entries BEGIN
        SELECT n FROM legacy_said WHERE thread=NEW.thread ORDER BY n DESC LIMIT 1;
      END;`);
    installSaidState(db);
    installSaidState(db);
    put.run(thread,2,"bob",2);
    assert.equal(db.prepare("SELECT said_n FROM thread_state WHERE thread=?").get(thread)?.said_n,2);
    assert.deepEqual(saidOf(makeStore(db,"/none"),thread),
      { n:2,authorKind:"person",author:"bob",other:1 });
  } finally { store.close(); }
});

for (const mode of ["native", "legacy"]) for (const outer of [100, 101]) for (const installedFirst of [false, true])
  test(`a nested append keeps the ${mode} sidebar exact (outer ${outer}, nested trigger first ${installedFirst})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("ember", "CHAT", `nested-order-${mode}-${outer}-${installedFirst}`, null, null).id;
      const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,?,?,?,?)");
      put.run(thread,1,"message","agent","worker",1);
      put.run(thread,2,"message","person","alice",2);
      for (let n=3;n<=70;n++) put.run(thread,n,"edit","agent","worker",n);
      const inner = outer === 100 ? 101 : 100;
      const nested = `CREATE TRIGGER nested_said_order BEFORE INSERT ON entries WHEN NEW.n=${outer} BEGIN
        INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(NEW.thread,${inner},'message','person','bob',${inner});
      END;`;
      if (installedFirst) db.exec(nested);
      if (mode === "legacy") { installLegacySaid(db); db.exec("DROP INDEX entries_said"); }
      else db.exec("DROP TRIGGER said_state_before_insert");
      installSaidState(db);
      if (mode === "legacy") while (!legacySaidStep(db,64).ready) { /* prepare */ }
      if (!installedFirst) db.exec(nested);
      put.run(thread,outer,"message","person","alice",outer);
      assert.deepEqual(saidOf(makeStore(db,"/none"),thread), {
        n:101,authorKind:"person",author:outer === 101 ? "alice" : "bob",other:100,
      });
    } finally { store.close(); }
  });

for (const tail of [0, 64, 65, 129]) test(`a missing sidebar state stays exact after ${tail} old edits`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", `old-empty-said-${tail}`, null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,?,?,?,?)");
    for (let n = 1; n <= tail; n++) put.run(thread,n,"edit","agent","worker",n);
    installLegacySaid(db);
    db.exec("DROP INDEX entries_said");
    installSaidState(db);
    db.prepare("DELETE FROM thread_state WHERE thread=?").run(thread);
    put.run(thread,tail+1,"message","person","alice",tail+1);
    assert.equal(db.prepare("SELECT said_other_known FROM thread_state WHERE thread=?").get(thread)?.said_other_known,
      tail < 65 ? 1 : 0);
    assert.deepEqual(saidOf(makeStore(db,"/none"),thread),
      { n:tail+1,authorKind:"person",author:"alice",other:null });
  } finally { store.close(); }
});

for (const recursive of [false, true]) for (const timing of ["BEFORE", "AFTER"])
  for (const installedFirst of [false, true]) for (const action of ["delete", "replace", "append"])
    test(`nested ${timing} ${action} keeps the old sidebar exact (recursive ${recursive}, installed first ${installedFirst})`, () => {
      const store = Store.open(":memory:"), db = store.db;
      try {
        db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
        const thread = store.openThread("ember", "CHAT", `nested-${recursive}-${timing}-${installedFirst}-${action}`, null, null).id;
        const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES(?,?,?,?,?,?,?)`);
        put.run(thread,1,"message","agent","worker","first",1);
        put.run(thread,2,"message","person","alice","second",2);
        for (let n=3;n<=70;n++) put.run(thread,n,"edit","agent","worker",`edit-${n}`,n);
        const statement = action === "delete" ? `DELETE FROM entries WHERE thread=NEW.thread AND n=2;`
          : action === "replace" ? `INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,ts,at)
            VALUES(NEW.thread,2,'message','person','bob','nested-replace',2);`
          : `INSERT INTO entries(thread,n,kind,author_kind,author,ts,at)
            VALUES(NEW.thread,101,'message','person','bob','nested-append',101);`;
        const nested = `CREATE TRIGGER nested_said_write ${timing} INSERT ON entries WHEN NEW.n=100 BEGIN ${statement} END;`;
        if (!installedFirst) db.exec(nested);
        installLegacySaid(db);
        db.exec("DROP INDEX entries_said");
        installSaidState(db);
        while (!legacySaidStep(db,64).ready) { /* prepare */ }
        if (installedFirst) db.exec(nested);
        put.run(thread,100,"message","person","alice","outer",100);

        const latest = db.prepare(`SELECT n,author_kind,author FROM entries WHERE thread=? AND kind='message'
          AND letter IS NULL ORDER BY n DESC LIMIT 1`).get(thread) as { n:number;author_kind:string;author:string };
        const other = latest.author_kind !== "person" ? latest.n : db.prepare(`SELECT n FROM entries WHERE thread=?
          AND kind='message' AND letter IS NULL AND NOT (author_kind='person' AND author=?) ORDER BY n DESC LIMIT 1`)
          .get(thread,latest.author)?.n ?? null;
        assert.deepEqual(saidOf(makeStore(db,"/none"),thread),
          { n:latest.n,authorKind:latest.author_kind,author:latest.author,other });
      } finally { store.close(); }
    });

for (const recursive of [false, true]) for (const installedFirst of [false, true])
  test(`an ignored outer insert keeps a nested message visible (recursive ${recursive}, installed first ${installedFirst})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      const thread = store.openThread("ember", "CHAT", `nested-ignore-${recursive}-${installedFirst}`, null, null).id;
      db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,1,'message','agent','worker',1)").run(thread);
      const nested = `CREATE TRIGGER nested_said_ignore BEFORE INSERT ON entries WHEN NEW.n=100 BEGIN
        INSERT INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES(NEW.thread,101,'message','person','bob','same-ts',101);
      END;`;
      if (!installedFirst) db.exec(nested);
      installLegacySaid(db);
      db.exec("DROP INDEX entries_said");
      installSaidState(db);
      while (!legacySaidStep(db,64).ready) { /* prepare */ }
      if (installedFirst) db.exec(nested);
      db.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,author_kind,author,ts,at)
        VALUES(?,100,'message','person','alice','same-ts',100)`).run(thread);
      assert.deepEqual(saidOf(makeStore(db,"/none"),thread),
        { n:101,authorKind:"person",author:"bob",other:1 });
      assert.equal(db.prepare("SELECT 1 FROM entries WHERE thread=? AND n=100").get(thread),undefined);
    } finally { store.close(); }
  });
