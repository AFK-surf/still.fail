import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { installLegacyAgent, legacyAgentDrain, legacyAgentStep, LEGACY_ASKED_DURING } from "../src/store/legacy-agent-build.ts";

function database() {
  const dir = mkdtempSync(join(tmpdir(),"legacy-agent-")), path = join(dir,"store.db"), db = new DatabaseSync(path);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE entries(thread INTEGER NOT NULL,n INTEGER NOT NULL,kind TEXT NOT NULL,author_kind TEXT NOT NULL,
      author TEXT NOT NULL,letter TEXT,ts TEXT,at INTEGER NOT NULL,text TEXT,PRIMARY KEY(thread,n));
    CREATE UNIQUE INDEX entries_ts ON entries(thread,ts) WHERE ts IS NOT NULL`);
  return { db,path,close() { db.close(); rmSync(dir,{ recursive: true,force: true }); } };
}

const put = (db: DatabaseSync,thread: number,n: number,at: number,kind = "message",authorKind = "agent",ts = `${n}`) =>
  db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,letter,ts,at) VALUES(?,?,?,?,'a',NULL,?,?)")
    .run(thread,n,kind,authorKind,ts,at);
const expected = (db: DatabaseSync,thread: number,from: number,to: number) => db.prepare(`SELECT MAX(n) n FROM entries
  WHERE thread=? AND kind='message' AND author_kind='agent' AND at>=? AND at<=?`).get(thread,from,to)!.n;
const actual = (db: DatabaseSync,thread: number,from: number,to: number) => db.prepare(LEGACY_ASKED_DURING).get(thread,from,to)!.n;

for (const recursive of [false,true]) test(`an old agent-time lookup follows previous writers while preparing (recursive triggers ${recursive})`, () => {
  const rig = database(), { db } = rig, old = new DatabaseSync(rig.path);
  try {
    old.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    for (let n=1;n<=400;n++) { put(db,1,n,500-n,"message",n%2 ? "agent" : "person"); if (n<=40) put(db,2,n,n); }
    installLegacyAgent(db);
    const same = () => {
      for (const thread of [1,2,3]) for (const [from,to] of [[0,100],[100,200],[200,500],[1,1000]]) {
        assert.equal(actual(db,thread,from,to),expected(db,thread,from,to));
      }
    };
    same();
    assert.deepEqual(legacyAgentStep(db,8),{ ready: false,visited: 8 });
    old.prepare("UPDATE entries SET at=10 WHERE thread=1 AND n=3").run();
    old.prepare("UPDATE entries SET kind='edit' WHERE thread=1 AND n=5").run();
    old.prepare("UPDATE entries SET author_kind='agent',at=15 WHERE thread=1 AND n=4").run();
    old.prepare("INSERT OR REPLACE INTO entries VALUES(1,350,'message','person','p',NULL,'1',5,NULL)").run();
    const displaced = old.prepare("SELECT rowid id FROM entries WHERE thread=1 AND n=7").get()!.id;
    old.prepare("INSERT OR REPLACE INTO entries(rowid,thread,n,kind,author_kind,author,at) VALUES(?,3,1,'message','agent','a',99)").run(displaced);
    old.prepare("DELETE FROM entries WHERE thread=2 AND n=1").run();
    put(old,1,0,13,"message","agent","before");
    same();
    let result;
    do { result = legacyAgentStep(db,8); assert.ok(result.visited<=8); same(); } while (!result.ready);
    old.prepare("UPDATE entries SET at=22 WHERE thread=1 AND n=3").run();
    old.prepare("INSERT OR IGNORE INTO entries VALUES(1,8,'message','agent','ignored',NULL,'ignored',50,NULL)").run();
    same();
    while (legacyAgentDrain(db,8)) same();
    same();
    assert.deepEqual(db.prepare("SELECT thread,at,n FROM legacy_agent_build ORDER BY thread,at,n").all(),
      db.prepare("SELECT thread,at,n FROM entries WHERE kind='message' AND author_kind='agent' ORDER BY thread,at,n").all());
  } finally { old.close(); rig.close(); }
});

for (const alias of ["rowid","_rowid_","oid"]) test(`an old writer replacing an agent by ${alias} keeps time lookup exact`, () => {
  const rig = database(), { db } = rig, old = new DatabaseSync(rig.path);
  try {
    put(db,1,1,10); put(db,2,2,20); put(db,3,3,30);
    while (!legacyAgentStep(db,2).ready) { /* prepare */ }
    const displaced = old.prepare("SELECT rowid id FROM entries WHERE thread=2 AND n=2").get()!.id;
    old.prepare(`UPDATE OR REPLACE entries SET ${alias}=? WHERE thread=1 AND n=1`).run(displaced);
    for (const thread of [1,2,3]) assert.equal(actual(db,thread,0,100),expected(db,thread,0,100));
    while (legacyAgentDrain(db,2)) for (const thread of [1,2,3]) assert.equal(actual(db,thread,0,100),expected(db,thread,0,100));
  } finally { old.close(); rig.close(); }
});

test("agent-time preparation rolls back its cursor and staged keys together", () => {
  const rig = database(), { db } = rig;
  try {
    for (let n=1;n<=40;n++) put(db,1,n,100-n);
    installLegacyAgent(db);
    db.exec(`CREATE TRIGGER fail_agent_batch BEFORE INSERT ON legacy_agent_build WHEN NEW.n=4 BEGIN
      SELECT RAISE(ABORT,'batch interrupted'); END`);
    assert.throws(() => legacyAgentStep(db,8),/batch interrupted/);
    assert.equal(db.prepare("SELECT COUNT(*) n FROM legacy_agent_build").get()?.n,0);
    assert.equal(db.prepare("SELECT cursor_n FROM legacy_agent_meta").get()?.cursor_n,null);
    db.exec("DROP TRIGGER fail_agent_batch");
    while (!legacyAgentStep(db,8).ready) { /* retry */ }
    for (const [from,to] of [[0,50],[51,100]]) assert.equal(actual(db,1,from,to),expected(db,1,from,to));
  } finally { rig.close(); }
});

test("an old agent-time cleanup batch reads only a bounded number of dirty keys", () => {
  const counts: number[] = [];
  for (const size of [80, 800]) {
    const rig = database(), { db } = rig;
    try {
      for (let n = 1; n <= size; n++) put(db, 1, n, n);
      installLegacyAgent(db);
      while (!legacyAgentStep(db).ready) { /* prepare */ }
      db.exec("UPDATE entries SET at=at+1000 WHERE thread=1");
      let read = 0, observed = false;
      db.function("visit_agent_dirty", () => { read++; return 1; });
      const traced = new Proxy(db, { get(target, property) {
        if (property === "prepare") return (sql: string) => {
          if (sql.includes("FROM legacy_agent_dirty") && sql.includes("ORDER BY") && sql.includes("LIMIT 1")) {
            const plan = target.prepare(`EXPLAIN QUERY PLAN ${sql}`).all().map((r) => String(r.detail)).join(" | ");
            assert.doesNotMatch(plan, /TEMP B-TREE/, plan);
            const measured = sql.replace(" ORDER BY", " WHERE visit_agent_dirty() ORDER BY");
            assert.notEqual(measured, sql);
            observed = true;
            return target.prepare(measured);
          }
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      assert.equal(legacyAgentDrain(traced, 1), 1);
      assert.ok(observed && read > 0, "the dirty-key lookup was observed");
      counts.push(read);
    } finally { rig.close(); }
  }
  assert.ok(counts[1]! <= counts[0]! + 1 && counts[1]! <= 2,
    `dirty keys read for 80 / 800 pending keys: ${counts.join(" / ")}`);
});

test("old agent-time cleanup follows numeric order, including 64-bit keys", () => {
  const rig = database(), { db } = rig;
  try {
    installLegacyAgent(db);
    assert.equal(legacyAgentStep(db).ready, true);
    const put = db.prepare("INSERT INTO legacy_agent_dirty(thread,n,old_at) VALUES(?,?,NULL)");
    put.run(2, 2); put.run(2, 100); put.run(2, 9007199254740993n); put.run(10, 1);
    assert.equal(legacyAgentDrain(db, 1), 1);
    assert.deepEqual(db.prepare(`SELECT CAST(d.thread AS TEXT) AS thread,CAST(d.n AS TEXT) AS n
      FROM legacy_agent_dirty d ORDER BY d.thread,d.n`).all().map((r) => [r.thread, r.n]),
    [["2", "100"], ["2", "9007199254740993"], ["10", "1"]]);
  } finally { rig.close(); }
});

test("unrelated edits and author changes do not add agent-time work", () => {
  const rig = database(), { db } = rig;
  try {
    put(db,1,1,1);
    while (!legacyAgentStep(db,8).ready) { /* prepare */ }
    for (let n=2;n<=401;n++) put(db,1,n,n,"edit","person");
    db.exec("UPDATE entries SET author='changed' WHERE thread=1");
    db.exec("DELETE FROM entries WHERE thread=1 AND kind='edit'");
    assert.equal(db.prepare("SELECT COUNT(*) n FROM legacy_agent_dirty").get()?.n,0);
    assert.equal(actual(db,1,0,10),1);
  } finally { rig.close(); }
});

test("agent-time lookup does not visit unrelated changed times", () => {
  const rig = database(), { db } = rig;
  try {
    for (let n=1;n<=400;n++) { if (n<=40) put(db,1,n,1000+n); put(db,2,n,1000+n); }
    while (!legacyAgentStep(db,16).ready) { /* prepare */ }
    db.exec("UPDATE entries SET at=at+1000");
    let visited = 0;
    db.function("visit_changed_agent", (_n) => { visited++; return 1; });
    const traced = LEGACY_ASKED_DURING.replace("AND t.thread=?1 AND t.at>=?2",
      "AND t.thread=?1 AND visit_changed_agent(t.n) AND t.at>=?2");
    assert.notEqual(traced,LEGACY_ASKED_DURING);
    const query = db.prepare(traced);
    const visits = (thread: number) => { visited = 0; assert.equal(query.get(thread,0,10)!.n,null); return visited; };
    assert.deepEqual([visits(1),visits(2)],[0,0]);
  } finally { rig.close(); }
});

test("agent-time lookup seeks only the requested prepared time range", () => {
  const rig = database(), { db } = rig;
  try {
    for (let n=1;n<=400;n++) { if (n<=40) put(db,1,n,n); put(db,2,n,n); }
    while (!legacyAgentStep(db,16).ready) { /* prepare */ }
    let visited = 0;
    db.function("visit_prepared_agent", (_n) => { visited++; return 1; });
    const traced = LEGACY_ASKED_DURING.replace("AND s.thread=?1 AND s.at>=?2",
      "AND s.thread=?1 AND visit_prepared_agent(s.n) AND s.at>=?2");
    assert.notEqual(traced,LEGACY_ASKED_DURING);
    const query = db.prepare(traced);
    const visits = (thread: number) => { visited = 0; assert.equal(query.get(thread,10,10)!.n,10); return visited; };
    assert.deepEqual([visits(1),visits(2)],[1,1]);
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${LEGACY_ASKED_DURING}`).all(1,10,10) as { detail: string }[])
      .map((r) => r.detail).join(" | ");
    assert.match(plan,/SEARCH s USING PRIMARY KEY \(thread=\? AND at>\? AND at<\?\)/);
    assert.match(plan,/SEARCH t USING PRIMARY KEY \(thread=\? AND at>\? AND at<\?\)/);
    assert.doesNotMatch(plan,/SCAN (s|t)\b/);
  } finally { rig.close(); }
});

test("ignored invalid writes do not make an older writer fail", () => {
  const rig = database(), { db } = rig;
  try {
    put(db,1,1,10);
    while (!legacyAgentStep(db,8).ready) { /* prepare */ }
    assert.doesNotThrow(() => db.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,author_kind,author,at)
      VALUES(?,NULL,'message','agent','a',20)`).run(1));
    assert.doesNotThrow(() => db.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,author_kind,author,at)
      VALUES(?,2,'message','agent','a',NULL)`).run(1));
    assert.doesNotThrow(() => db.prepare("UPDATE OR IGNORE entries SET at=NULL WHERE thread=1 AND n=1").run());
    assert.equal(actual(db,1,0,100),expected(db,1,0,100));
    while (legacyAgentDrain(db,8)) { /* reconcile */ }
    assert.equal(actual(db,1,0,100),1);
  } finally { rig.close(); }
});

for (const recursive of [false,true]) test(`nested replacement exposes each current agent time (recursive triggers ${recursive})`, () => {
  const rig = database(), { db } = rig;
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"};
      CREATE TRIGGER nested_agent BEFORE INSERT ON entries WHEN NEW.text='outer' BEGIN
        INSERT OR REPLACE INTO entries VALUES(NEW.thread,NEW.n,'message','agent','nested',NULL,'nested',50,'inner');
      END;`);
    put(db,1,1,10);
    while (!legacyAgentStep(db,8).ready) { /* prepare */ }
    const at = (n: number) => LEGACY_ASKED_DURING.replaceAll("?1","NEW.thread").replaceAll("?2",String(n)).replaceAll("?3",String(n));
    db.exec(`CREATE TABLE observed(which TEXT,n INTEGER);
      CREATE TRIGGER observe_agent AFTER INSERT ON entries WHEN NEW.text IN ('inner','outer') BEGIN
        INSERT INTO observed SELECT NEW.text,(${at(50)}) WHERE NEW.text='inner';
        INSERT INTO observed SELECT NEW.text,(${at(70)}) WHERE NEW.text='outer';
      END;`);
    db.exec("INSERT OR REPLACE INTO entries VALUES(1,1,'message','agent','outer',NULL,'outer',70,'outer')");
    assert.deepEqual(db.prepare("SELECT which,n FROM observed ORDER BY rowid").all().map((r) => ({ ...r })),
      [{ which:"inner",n:1 },{ which:"outer",n:1 }]);
    for (const [from,to] of [[0,10],[50,50],[70,70]]) assert.equal(actual(db,1,from,to),expected(db,1,from,to));
    while (legacyAgentDrain(db,8)) { /* reconcile */ }
    assert.equal(actual(db,1,70,70),1);
  } finally { rig.close(); }
});

for (const recursive of [false,true]) test(`nested person and agent replacements keep the right time (recursive triggers ${recursive})`, () => {
  const rig = database(), { db } = rig;
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"};
      CREATE TRIGGER nested_agent_before_person BEFORE INSERT ON entries WHEN NEW.text='outer-person' BEGIN
        INSERT OR REPLACE INTO entries VALUES(NEW.thread,NEW.n,'message','agent','nested',NULL,'nested-agent',50,'inner-agent');
      END;
      CREATE TRIGGER nested_person_before_agent BEFORE INSERT ON entries WHEN NEW.text='outer-agent' BEGIN
        INSERT OR REPLACE INTO entries VALUES(NEW.thread,NEW.n,'message','person','nested',NULL,'nested-person',60,'inner-person');
      END;`);
    while (!legacyAgentStep(db,8).ready) { /* prepare */ }
    const at = (n: number) => LEGACY_ASKED_DURING.replaceAll("?1","NEW.thread").replaceAll("?2",String(n)).replaceAll("?3",String(n));
    db.exec(`CREATE TABLE observed(which TEXT,n INTEGER);
      CREATE TRIGGER observe_nested AFTER INSERT ON entries BEGIN
        INSERT INTO observed SELECT NEW.text,(${at(50)}) WHERE NEW.text='inner-agent';
        INSERT INTO observed SELECT NEW.text,(${at(50)}) WHERE NEW.text='outer-person';
        INSERT INTO observed SELECT NEW.text,(${at(60)}) WHERE NEW.text='inner-person';
        INSERT INTO observed SELECT NEW.text,(${at(70)}) WHERE NEW.text='outer-agent';
      END;`);
    db.exec("INSERT OR REPLACE INTO entries VALUES(1,1,'message','person','outer',NULL,'outer-person',50,'outer-person')");
    db.exec("INSERT OR REPLACE INTO entries VALUES(1,2,'message','agent','outer',NULL,'outer-agent',70,'outer-agent')");
    assert.deepEqual(db.prepare("SELECT which,n FROM observed ORDER BY rowid").all().map((r) => ({ ...r })),
      [{ which:"inner-agent",n:1 },{ which:"outer-person",n:null },{ which:"inner-person",n:null },{ which:"outer-agent",n:2 }]);
    for (const [from,to] of [[50,50],[60,60],[70,70],[0,100]]) assert.equal(actual(db,1,from,to),expected(db,1,from,to));
    while (legacyAgentDrain(db,8)) { /* reconcile */ }
    assert.equal(actual(db,1,0,100),2);
  } finally { rig.close(); }
});

for (const recursive of [false,true]) test(`agent-time reconciliation remains exact when later triggers replace entries (recursive triggers ${recursive})`, () => {
  const rig = database(), { db } = rig;
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    for (let n=1;n<=3;n++) put(db,1,n,n*10);
    while (!legacyAgentStep(db,8).ready) { /* prepare */ }
    db.exec(`CREATE TRIGGER later_person BEFORE INSERT ON entries WHEN NEW.text='outer-person' BEGIN
        INSERT OR REPLACE INTO entries VALUES(NEW.thread,NEW.n,'message','agent','inner',NULL,'inner-person',60,'inner-agent');
      END;
      CREATE TRIGGER later_agent BEFORE INSERT ON entries WHEN NEW.text='outer-agent' BEGIN
        INSERT OR REPLACE INTO entries VALUES(NEW.thread,NEW.n,'message','person','inner',NULL,'inner-agent',60,'inner-person');
      END;
      CREATE TRIGGER later_agent_again BEFORE INSERT ON entries WHEN NEW.text='outer-again' BEGIN
        INSERT OR REPLACE INTO entries VALUES(NEW.thread,NEW.n,'message','agent','inner',NULL,'inner-again',80,'inner-again');
      END;`);
    const at = (n: number) => LEGACY_ASKED_DURING.replaceAll("?1","NEW.thread").replaceAll("?2",String(n)).replaceAll("?3",String(n));
    db.exec(`CREATE TABLE later_observed(which TEXT,n INTEGER);
      CREATE TRIGGER later_observe AFTER INSERT ON entries BEGIN
        INSERT INTO later_observed SELECT NEW.text,(${at(60)}) WHERE NEW.text IN ('inner-agent','outer-person','inner-person');
        INSERT INTO later_observed SELECT NEW.text,(${at(70)}) WHERE NEW.text='outer-agent';
        INSERT INTO later_observed SELECT NEW.text,(${at(80)}) WHERE NEW.text='inner-again';
        INSERT INTO later_observed SELECT NEW.text,(${at(90)}) WHERE NEW.text='outer-again';
      END;`);
    db.exec("INSERT OR REPLACE INTO entries VALUES(1,1,'message','person','outer',NULL,'outer-person',50,'outer-person')");
    db.exec("INSERT OR REPLACE INTO entries VALUES(1,2,'message','agent','outer',NULL,'outer-agent',70,'outer-agent')");
    db.exec("INSERT OR REPLACE INTO entries VALUES(1,3,'message','agent','outer',NULL,'outer-again',90,'outer-again')");
    assert.deepEqual(db.prepare("SELECT which,n FROM later_observed ORDER BY rowid").all().map((r) => ({ ...r })),
      [{ which:"inner-agent",n:1 },{ which:"outer-person",n:null },{ which:"inner-person",n:null },
        { which:"outer-agent",n:2 },{ which:"inner-again",n:3 },{ which:"outer-again",n:3 }]);
    for (const [from,to] of [[10,10],[20,20],[30,30],[60,60],[70,70],[80,80],[90,90],[0,100]])
      assert.equal(actual(db,1,from,to),expected(db,1,from,to));
    while (legacyAgentDrain(db,2)) { /* reconcile */ }
    assert.deepEqual(db.prepare("SELECT thread,at,n FROM legacy_agent_build ORDER BY thread,at,n").all(),
      db.prepare("SELECT thread,at,n FROM entries WHERE kind='message' AND author_kind='agent' ORDER BY thread,at,n").all());
  } finally { rig.close(); }
});

test("many changes to one agent time are removed in bounded batches", () => {
  const rig = database(), { db } = rig;
  try {
    put(db,1,1,0);
    while (!legacyAgentStep(db,8).ready) { /* prepare */ }
    const update = db.prepare("UPDATE entries SET at=? WHERE thread=1 AND n=1");
    for (let at=1;at<=400;at++) update.run(at);
    let removed = 0, read = 0;
    db.function("visit_agent_cleanup", () => { removed++; return 1; });
    db.function("visit_agent_time_read", (_at) => { read++; return 1; });
    db.exec("CREATE TRIGGER count_agent_cleanup AFTER DELETE ON legacy_agent_times BEGIN SELECT visit_agent_cleanup(); END");
    const counted = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql.includes("FROM legacy_agent_times INDEXED BY legacy_agent_times_by_key")) {
          const traced = sql.replace("AND n=CAST(?2 AS INTEGER)","AND n=CAST(?2 AS INTEGER) AND visit_agent_time_read(at)");
          assert.notEqual(traced,sql);
          sql = traced;
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target,property,target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    let batches = 0, visited: number;
    do {
      removed = 0; read = 0;
      visited = legacyAgentDrain(counted,8);
      assert.ok(visited<=8);
      assert.ok(removed<=8,`one batch removed ${removed} candidate times`);
      assert.ok(read<=9,`one batch read ${read} candidate times`);
      assert.equal(actual(db,1,400,400),1);
      assert.equal(actual(db,1,0,399),null);
      batches++;
    } while (visited);
    assert.ok(batches>2);
    assert.equal(db.prepare("SELECT COUNT(*) n FROM legacy_agent_times").get()?.n,0);
    assert.equal(db.prepare("SELECT COUNT(*) n FROM legacy_agent_dirty").get()?.n,0);
    assert.deepEqual(db.prepare("SELECT thread,at,n FROM legacy_agent_build").all().map((r) => ({ ...r })),[{ thread:1,at:400,n:1 }]);
  } finally { rig.close(); }
});

for (const recursive of [false,true]) test(`time lookup agrees with entries through interleaved changes (recursive triggers ${recursive})`, () => {
  const rig = database(), { db } = rig, old = new DatabaseSync(rig.path);
  try {
    old.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    for (let thread=1;thread<=3;thread++) for (let n=1;n<=30;n++)
      put(db,thread,n,100-n,"message",n%2 ? "agent" : "person",`seed-${n}`);
    installLegacyAgent(db);
    const insert = old.prepare(`INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,letter,ts,at)
      VALUES(?,?,?,?,'a',?,?,?)`);
    let seed = 0x58a1b239;
    const next = (range: number) => { seed = (Math.imul(seed,1664525)+1013904223) >>> 0; return seed % range; };
    let ready = false;
    for (let i=1;i<=500;i++) {
      const thread=1+next(3), n=1+next(45), at=next(160)-30, target=1+next(45);
      switch (i%6) {
        case 0: old.prepare("DELETE FROM entries WHERE thread=? AND n=?").run(thread,n); break;
        case 1: old.prepare("UPDATE entries SET at=? WHERE thread=? AND n=?").run(at,thread,n); break;
        case 2: old.prepare("UPDATE OR REPLACE entries SET n=?,at=? WHERE thread=? AND n=?").run(target,at,thread,n); break;
        default: insert.run(thread,n,i%6 === 3 ? "edit" : "message",i%5 === 0 ? "person" : "agent",
          i%11 === 0 ? "letter" : null,`t-${next(25)}`,at); break;
      }
      if (!ready && i%17===0) ready = legacyAgentStep(db,7).ready;
      if (!ready && i===180) while (!(ready = legacyAgentStep(db,7).ready)) { /* finish */ }
      if (ready && i%13===0) legacyAgentDrain(db,7);
      for (const t of [1,2,3]) for (const [from,to] of [[-30,0],[1,50],[51,130],[-30,130]]) {
        assert.equal(actual(db,t,from,to),expected(db,t,from,to),`write ${i}, thread ${t}, ${from}..${to}`);
      }
    }
    while (!ready) ready = legacyAgentStep(db,7).ready;
    while (legacyAgentDrain(db,7)) { /* reconcile */ }
    assert.deepEqual(db.prepare("SELECT thread,at,n FROM legacy_agent_build ORDER BY thread,at,n").all(),
      db.prepare("SELECT thread,at,n FROM entries WHERE kind='message' AND author_kind='agent' ORDER BY thread,at,n").all());
    assert.equal(db.prepare("SELECT COUNT(*) n FROM legacy_agent_times").get()?.n,0);
  } finally { old.close(); rig.close(); }
});

test("agent-time cursors and ranges preserve SQLite's 64-bit integers", () => {
  const rig = database(), { db } = rig;
  try {
    const insert = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','agent','a',?)");
    const min = -9223372036854775808n, max = 9223372036854775807n;
    insert.run(1,min,max); insert.run(1,max,min);
    while (!legacyAgentStep(db,1).ready) { /* prepare */ }
    const got = db.prepare(LEGACY_ASKED_DURING), want = db.prepare(`SELECT MAX(n) n FROM entries WHERE thread=?
      AND kind='message' AND author_kind='agent' AND at>=? AND at<=?`);
    got.setReadBigInts(true); want.setReadBigInts(true);
    for (const [from,to] of [[min,min],[max,max],[min,max]] as const)
      assert.deepEqual(got.get(1,from,to),want.get(1,from,to));
    db.prepare("UPDATE entries SET at=? WHERE thread=1 AND n=?").run(max,max);
    for (const [from,to] of [[min,min],[max,max],[min,max]] as const)
      assert.deepEqual(got.get(1,from,to),want.get(1,from,to));
    while (legacyAgentDrain(db,1)) { /* reconcile */ }
    assert.deepEqual(got.get(1,min,max),want.get(1,min,max));
  } finally { rig.close(); }
});
