import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { makeStore, saidOf, SaidUnavailable } from "../src/read/store.ts";
import { installLegacySaid, legacySaidDrain, legacySaidDrainThread, legacySaidStep } from "../src/store/legacy-said-build.ts";
import { installSaidState, saidScanStep, type SaidScan } from "../src/store/said-state.ts";
import { Store } from "../src/store/store.ts";

for (const scenario of ["changed-away", "ignored"] as const)
  test(`a sidebar read does bounded work with ${scenario} old keys`, () => {
    const visits: number[] = [];
    for (const size of [80, 800]) {
      const store = Store.open(":memory:"), db = store.db;
      try {
        const thread = store.openThread("ember", "CHAT", `said-read-${scenario}-${size}`, null, null).id;
        const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES(?,?,'message','agent','worker',?,?)");
        put.run(thread, 1, "occupied", 1);
        if (scenario === "changed-away") for (let n = 2; n <= size + 1; n++) put.run(thread, n, `t-${n}`, n);
        installLegacySaid(db);
        db.exec("DROP INDEX entries_said");
        installSaidState(db);
        while (!legacySaidStep(db, 64).ready) { /* prepare */ }
        if (scenario === "changed-away") db.prepare("UPDATE entries SET letter='letter' WHERE thread=? AND n>1").run(thread);
        else {
          const ignored = db.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,author_kind,author,ts,at)
            VALUES(?,?,'message','agent','worker','occupied',?)`);
          for (let n = 2; n <= size + 1; n++) ignored.run(thread, n, n);
        }
        let visited = 0;
        db.function("visit_said_read", (n) => { visited++; return n; });
        const counted = new Proxy(db, { get(target, property) {
          if (property === "prepare") return (sql: string) => target.prepare(sql.replaceAll(
            "CROSS JOIN entries e ON e.thread=d.thread AND e.n=d.n",
            "CROSS JOIN entries e ON e.thread=d.thread AND e.n=visit_said_read(d.n)")
            .replace("FROM entries e WHERE e.thread=?", "FROM entries e WHERE e.thread=? AND visit_said_read(e.n)=e.n")
            .replace("FROM entries WHERE thread=? ORDER BY n DESC LIMIT 65",
              "FROM entries WHERE thread=? AND visit_said_read(n)=n ORDER BY n DESC LIMIT 65"));
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        } });
        const read = makeStore(counted, "/none");
        let answer: ReturnType<typeof saidOf> | undefined;
        try { answer = saidOf(read, thread); }
        catch (error) { if (!(error instanceof SaidUnavailable)) throw error; }
        visits.push(visited);
        if (answer === undefined) {
          let scan: SaidScan | null = null;
          let done = false;
          for (let i = 0; i < 100 && !done; i++) {
            visited = 0;
            const step = saidScanStep(counted, thread, scan);
            assert.ok(step.visited <= 64 && visited <= 70, `one preparation slice examined ${step.visited} / ${visited} keys`);
            scan = step.scan;
            done = step.done;
          }
          assert.ok(done, "the requested chat becomes readable");
          answer = saidOf(read, thread);
        }
        assert.deepEqual(answer, { n: 1, authorKind: "agent", author: "worker", other: 1 });
      } finally { store.close(); }
    }
    assert.ok(visits[1]! <= visits[0]! + 4 && visits[1]! <= 70,
      `sidebar candidates visited for 80 / 800 changed keys: ${visits.join(" / ")}`);
  });

for (const pending of [0, 63, 64, 65]) test(`a prepared sidebar handles ${pending} changed keys`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", `said-pending-${pending}`, null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES(?,?,?,?,?,?,?)");
    put.run(thread,1,"message","agent","worker","occupied",1);
    put.run(thread,2,"message","person","alice","said",2);
    for (let n=3;n<=131;n++) put.run(thread,n,"edit","agent","worker",`edit-${n}`,n);
    installLegacySaid(db);
    db.exec("DROP INDEX entries_said");
    installSaidState(db);
    while (!legacySaidStep(db,64).ready) { /* prepare */ }
    if (pending > 0) {
      db.prepare("UPDATE entries SET author='temporary' WHERE thread=? AND n=1").run(thread);
      db.prepare("UPDATE entries SET author='worker' WHERE thread=? AND n=1").run(thread);
    }
    const ignored = db.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,author_kind,author,ts,at)
      VALUES(?,?,'message','agent','worker','occupied',?)`);
    for (let n=132;n<132+Math.max(0,pending-1);n++) ignored.run(thread,n,n);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM legacy_said_dirty WHERE thread=?").get(thread)?.n,pending);
    const read = makeStore(db,"/none");
    if (pending <= 64) assert.deepEqual(saidOf(read,thread),{ n:2,authorKind:"person",author:"alice",other:1 });
    else {
      assert.throws(() => saidOf(read,thread),SaidUnavailable);
      let scan: SaidScan | null = null, done = false;
      for (let i=0;i<10 && !done;i++) {
        const step=saidScanStep(db,thread,scan);
        assert.ok(step.visited <= 64);
        scan=step.scan; done=step.done;
      }
      assert.ok(done);
      assert.deepEqual(saidOf(read,thread),{ n:2,authorKind:"person",author:"alice",other:1 });
    }
  } finally { store.close(); }
});

test("requested dirty keys drain only that chat and a failed batch rolls back", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const a=store.openThread("ember","CHAT","said-drain-a",null,null).id;
    const b=store.openThread("ember","CHAT","said-drain-b",null,null).id;
    const put=db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','alice',?)");
    for (const thread of [a,b]) for (let n=1;n<=80;n++) put.run(thread,n,n);
    installLegacySaid(db);
    db.exec("DROP INDEX entries_said");
    installSaidState(db);
    while (!legacySaidStep(db,64).ready) { /* prepare */ }
    db.prepare("UPDATE entries SET author='bob' WHERE thread IN (?,?)").run(a,b);
    const remaining=(thread: number) => db.prepare("SELECT COUNT(*) AS n FROM legacy_said_dirty WHERE thread=?").get(thread)!.n;
    db.exec(`CREATE TRIGGER fail_said_drain BEFORE INSERT ON legacy_said_build WHEN NEW.thread=${a}
      BEGIN SELECT RAISE(ABORT,'stop drain'); END`);
    assert.throws(() => legacySaidDrainThread(db,a,64),/stop drain/);
    assert.equal(remaining(a),80);
    assert.equal(remaining(b),80);
    db.exec("DROP TRIGGER fail_said_drain");
    assert.equal(legacySaidDrainThread(db,a,64),64);
    assert.equal(remaining(a),16);
    assert.equal(remaining(b),80);
    assert.equal(legacySaidDrainThread(db,a,64),16);
    assert.equal(remaining(a),0);
  } finally { store.close(); }
});

for (const scope of ["all", "thread"] as const) {
  const label = scope === "all" ? "global" : "per-chat";
  test(`a ${label} dirty batch visits only a bounded number of keys`, () => {
    const visits: number[] = [];
    for (const size of [80, 800]) {
      const store = Store.open(":memory:"), db = store.db;
      try {
        installLegacySaid(db);
        const put = db.prepare("INSERT INTO legacy_said_dirty(thread,n) VALUES(?,?)");
        for (let n = 1; n <= size; n++) put.run(2,n);
        for (let n = 1; n <= size; n++) put.run(10,n);
        let visited = 0, instrumented = false;
        db.function("visit_dirty_key", (n) => { visited++; return n; });
        const counted = new Proxy(db, { get(target, property) {
          if (property === "prepare") return (sql: string) => {
            if (sql.startsWith("SELECT CAST(") && sql.includes("FROM legacy_said_dirty")) {
              sql = sql.replace(/(FROM legacy_said_dirty(?: d)?)( WHERE (?:d\.)?thread=\?)? ORDER BY/,
                (_match, table: string, where: string | undefined) => {
                  instrumented = true;
                  const n = table.endsWith(" d") ? "d.n" : "n";
                  return `${table}${where ? `${where} AND` : " WHERE"} visit_dirty_key(${n})=${n} ORDER BY`;
                });
            }
            return target.prepare(sql);
          };
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        } });
        assert.equal(scope === "all" ? legacySaidDrain(counted,64) : legacySaidDrainThread(counted,2,64),64);
        assert.ok(instrumented, "the dirty-key selection was counted");
        visits.push(visited);
      } finally { store.close(); }
    }
    assert.ok(visits[1]! <= visits[0]! + 2 && visits[1]! <= 65,
      `dirty keys visited for 80 / 800 keys: ${visits.join(" / ")}`);
  });

  test(`a ${label} dirty batch follows numeric key order including 64-bit keys`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      installLegacySaid(db);
      const put = db.prepare("INSERT INTO legacy_said_dirty(thread,n) VALUES(?,?)");
      for (const n of [2n,10n,100n,9007199254740993n]) put.run(2,n);
      put.run(10,1);
      assert.equal(scope === "all" ? legacySaidDrain(db,2) : legacySaidDrainThread(db,2,2),2);
      const remaining = db.prepare(`SELECT CAST(thread AS TEXT) AS thread,CAST(n AS TEXT) AS n
        FROM legacy_said_dirty ORDER BY legacy_said_dirty.thread,legacy_said_dirty.n`).all();
      assert.deepEqual(remaining.map((row) => [row.thread,row.n]),
        [["2","100"],["2","9007199254740993"],["10","1"]]);
    } finally { store.close(); }
  });
}

test("an unrelated 64-bit entry does not make a bounded sidebar probe decode its key", () => {
  const store=Store.open(":memory:"), db=store.db;
  try {
    const thread=store.openThread("ember","CHAT","said-large-edit",null,null).id;
    const put=db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES(?,?,?,?,?,?,1)");
    put.run(thread,1,"message","agent","worker","occupied");
    const base=9007199254741000n;
    for (let n=0n;n<70n;n++) put.run(thread,base+n,"edit","agent","worker",`edit-${n}`);
    installLegacySaid(db);
    db.exec("DROP INDEX entries_said");
    installSaidState(db);
    while (!legacySaidStep(db,64).ready) { /* prepare */ }
    const ignored=db.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,author_kind,author,ts,at)
      VALUES(?,?,'message','agent','worker','occupied',1)`);
    for (let n=2;n<=66;n++) ignored.run(thread,n);
    const read=makeStore(db,"/none");
    assert.throws(() => saidOf(read,thread),SaidUnavailable);
    while (legacySaidDrainThread(db,thread,64)) { /* fold */ }
    assert.deepEqual(saidOf(read,thread),{ n:1,authorKind:"agent",author:"worker",other:1 });
  } finally { store.close(); }
});

test("an old writer can change an already scanned boundary while dirty keys are being folded", () => {
  const dir = mkdtempSync(join(tmpdir(),"legacy-said-drain-writer-"));
  const path = join(dir,"stillfail.db"), store = Store.open(path), db = store.db;
  const old = new DatabaseSync(path);
  try {
    const thread = store.openThread("ember","CHAT","said-drain-writer",null,null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES(?,?,'message',?,?,?,?)");
    put.run(thread,1,"agent","worker","t1",1);
    for (let n=2;n<=200;n++) put.run(thread,n,"person","alice",`t${n}`,n);
    installLegacySaid(db);
    db.exec("DROP INDEX entries_said");
    installSaidState(db);
    while (!legacySaidStep(db,64).ready) { /* prepare */ }
    db.prepare("UPDATE thread_state SET said_other_known=0 WHERE thread=?").run(thread);
    let scan = saidScanStep(db,thread,null).scan;
    assert.ok(scan);
    const first = saidScanStep(db,thread,scan);
    assert.equal(first.visited,64);
    scan = first.scan;
    assert.ok(scan);
    old.prepare("UPDATE entries SET author='bob' WHERE thread=? AND n=160").run(thread);
    const ignored = old.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,author_kind,author,ts,at)
      VALUES(?,?,'message','agent','worker','t1',?)`);
    for (let n=400;n<500;n++) ignored.run(thread,n,n);
    let changed = false;
    const drain = saidScanStep(db,thread,scan,64,() => {
      old.prepare("UPDATE entries SET author='carol' WHERE thread=? AND n=180").run(thread);
      changed = true;
      return true;
    });
    assert.ok(changed);
    assert.ok(drain.visited <= 64);
    scan = drain.scan;
    let done = false;
    for (let i=0;i<30 && !done;i++) {
      const step = saidScanStep(db,thread,scan);
      assert.ok(step.visited <= 64);
      scan = step.scan; done = step.done;
    }
    assert.ok(done);
    assert.deepEqual(saidOf(makeStore(db,dir),thread),
      { n:200,authorKind:"person",author:"alice",other:180 });
  } finally { old.close(); store.close(); rmSync(dir,{ recursive:true,force:true }); }
});

test("a sidebar read keeps its snapshot when an old writer creates a dirty backlog", () => {
  const dir = mkdtempSync(join(tmpdir(),"legacy-said-read-snapshot-"));
  const path = join(dir,"stillfail.db"), store = Store.open(path), db = store.db;
  const old = new DatabaseSync(path);
  try {
    const thread = store.openThread("ember","CHAT","said-read-snapshot",null,null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES(?,?,?,?,?,?,?)");
    put.run(thread,1,"message","agent","worker","t1",1);
    put.run(thread,2,"message","person","alice","t2",2);
    for (let n=3;n<=71;n++) put.run(thread,n,"edit","agent","worker",`t${n}`,n);
    installLegacySaid(db);
    db.exec("DROP INDEX entries_said");
    installSaidState(db);
    while (!legacySaidStep(db,64).ready) { /* prepare */ }
    let changed = false;
    const interleaved = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!sql.includes("FROM entries e WHERE e.thread=? ORDER BY e.n DESC LIMIT 1")) return statement;
        return new Proxy(statement, { get(query, member) {
          if (member === "get") return (...args: unknown[]) => {
            const result = query.get(...args as Parameters<typeof query.get>);
            if (!changed) {
              old.exec("BEGIN IMMEDIATE");
              const ignored = old.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,author_kind,author,ts,at)
                VALUES(?,?,'message','agent','worker','t1',?)`);
              for (let n=100;n<170;n++) ignored.run(thread,n,n);
              old.prepare("UPDATE entries SET author='bob' WHERE thread=? AND n=2").run(thread);
              old.exec("COMMIT");
              changed = true;
            }
            return result;
          };
          const value = Reflect.get(query,member,query);
          return typeof value === "function" ? value.bind(query) : value;
        } });
      };
      const value = Reflect.get(target,property,target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(saidOf(makeStore(interleaved,dir),thread),
      { n:2,authorKind:"person",author:"alice",other:1 });
    assert.ok(changed);
    const read = makeStore(db,dir);
    assert.throws(() => saidOf(read,thread),SaidUnavailable);
    let scan: SaidScan | null = null, done = false;
    for (let i=0;i<20 && !done;i++) {
      const step = saidScanStep(db,thread,scan);
      assert.ok(step.visited <= 64);
      scan = step.scan; done = step.done;
    }
    assert.ok(done);
    assert.deepEqual(saidOf(read,thread),{ n:2,authorKind:"person",author:"bob",other:1 });
  } finally { old.close(); store.close(); rmSync(dir,{ recursive:true,force:true }); }
});

test("a sidebar waits for handover and resumes after its changed keys are folded", async () => {
  const dir=mkdtempSync(join(tmpdir(),"legacy-said-request-"));
  const store=Store.open(join(dir,"stillfail.db")), db=store.db;
  const previous=Promise.withResolvers<void>();
  const readers=new Readers(dir,1,undefined,1,{ previousGone: previous.promise });
  try {
    store.insertSession({ key:"s",connect:"ember",runtime:"claude",profile:"cc",workspace:"/w/s",
      token:"s",createdAt:1,lastActiveAt:1 });
    const thread=store.openThread("ember","CHAT","said-request",null,null).id;
    store.joinThread(thread,"s","ember");
    const put=db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','agent','worker',?)");
    for (let n=1;n<=150;n++) put.run(thread,n,n);
    installLegacySaid(db);
    db.exec("DROP INDEX entries_said");
    installSaidState(db);
    while (!legacySaidStep(db,64).ready) { /* prepare */ }
    db.prepare("UPDATE entries SET letter='letter' WHERE thread=? AND n>1").run(thread);
    const viewer={ sub:"me",email:"me",name:"Me",role:"owner",workspace:"w",device:"d" } as const;
    const pending=readers.read("sharedChats",{ viewer,sessions:null,threads:null },"en");
    await readers.read("sharedChats",{ viewer,sessions:[],threads:[] },"en");
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM legacy_said_dirty WHERE thread=?").get(thread)?.n,149);
    previous.resolve();
    const rows=JSON.parse(await pending) as any[];
    assert.deepEqual(rows.find((row) => row.thread === thread)?.said,
      { n:1,authorKind:"agent",author:"worker",other:1 });
    assert.ok(Number(db.prepare("SELECT COUNT(*) AS n FROM legacy_said_dirty WHERE thread=?").get(thread)?.n) <= 64);
  } finally {
    previous.resolve(); readers.close(); store.close();
    rmSync(dir,{ recursive:true,force:true });
  }
});
