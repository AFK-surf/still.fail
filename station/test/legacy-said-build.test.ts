import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { installLegacySaid, legacySaidDrain, legacySaidStep, LEGACY_HAS_UNREAD, LEGACY_SAID_LATEST, LEGACY_UNREAD, publishLegacySaid } from "../src/store/legacy-said-build.ts";
import { installSaidState } from "../src/store/said-state.ts";

function database() {
  const dir = mkdtempSync(join(tmpdir(),"legacy-said-"));
  const path = join(dir,"store.db");
  const db = new DatabaseSync(path);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE entries(thread INTEGER NOT NULL,n INTEGER NOT NULL,kind TEXT NOT NULL,
      author_kind TEXT NOT NULL,author TEXT NOT NULL,letter TEXT,ts TEXT,text TEXT,PRIMARY KEY(thread,n));
    CREATE UNIQUE INDEX entries_ts ON entries(thread,ts) WHERE ts IS NOT NULL`);
  return { db,path,close() { db.close(); rmSync(dir,{ recursive: true,force: true }); } };
}

const row = (db: DatabaseSync,thread: number,n: number,author: string,ts = `${n}`) =>
  db.prepare("INSERT INTO entries VALUES(?,?,'message','person',?,NULL,?,NULL)").run(thread,n,author,ts);
const visible = (db: DatabaseSync) => db.prepare(`SELECT CAST(thread AS TEXT) thread,CAST(n AS TEXT) n,author_kind,author
  FROM legacy_said ORDER BY thread,n`).all().map((r) => ({ ...r }));
const expected = (db: DatabaseSync) => db.prepare(`SELECT CAST(thread AS TEXT) thread,CAST(n AS TEXT) n,author_kind,author
  FROM entries WHERE kind='message' AND letter IS NULL ORDER BY thread,n`).all().map((r) => ({ ...r }));

for (const recursive of [false,true]) test(`a legacy message index follows previous writers and replacements (recursive triggers ${recursive})`, () => {
  const rig = database();
  const { db } = rig;
  const old = new DatabaseSync(rig.path);
  try {
    old.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    for (let n = 1; n <= 400; n++) row(db,1,n,`p-${n}`);
    row(db,2,1,"other");
    installLegacySaid(db);
    assert.equal(publishLegacySaid(db),false);
    assert.deepEqual(legacySaidStep(db,16),{ ready: false,visited: 16 });
    old.prepare("INSERT OR REPLACE INTO entries VALUES(1,350,'message','person','by-ts',NULL,'1',NULL)").run();
    old.prepare("INSERT OR REPLACE INTO entries VALUES(1,2,'message','person','by-n',NULL,'new-2',NULL)").run();
    old.prepare("UPDATE entries SET author='changed' WHERE thread=1 AND n=3").run();
    old.prepare("UPDATE entries SET letter='letter' WHERE thread=1 AND n=4").run();
    old.prepare("DELETE FROM entries WHERE thread=2 AND n=1").run();
    const displaced = old.prepare("SELECT rowid AS id FROM entries WHERE thread=1 AND n=5").get()!.id;
    old.prepare("INSERT OR REPLACE INTO entries(rowid,thread,n,kind,author_kind,author,letter,ts) VALUES(?,3,1,'message','person','by-rowid',NULL,'r')").run(displaced);
    row(old,1,0,"before","before");
    row(old,4,1,"after","after");
    let result;
    do { result = legacySaidStep(db,16); assert.ok(result.visited <= 16); } while (!result.ready);
    assert.equal(publishLegacySaid(db),true);
    assert.deepEqual(visible(db),expected(db));
    old.prepare("INSERT OR IGNORE INTO entries VALUES(1,6,'message','person','ignored',NULL,'ignored',NULL)").run();
    old.prepare("DELETE FROM entries WHERE thread=1 AND n=7").run();
    old.prepare("UPDATE entries SET n=700,ts='moved' WHERE thread=1 AND n=8").run();
    assert.deepEqual(visible(db),expected(db));
    while (legacySaidDrain(db,16)) { assert.deepEqual(visible(db),expected(db)); }
    assert.deepEqual(visible(db),expected(db));
  } finally { old.close(); rig.close(); }
});

for (const recursive of [false,true]) for (const alias of ["rowid", "_rowid_", "oid"]) {
  test(`an old writer replacing a message by ${alias} keeps the lookup exact (recursive triggers ${recursive})`, () => {
    const rig = database(), { db } = rig, old = new DatabaseSync(rig.path);
    try {
      old.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      row(db,1,1,"first"); row(db,2,2,"displaced"); row(db,3,3,"other");
      while (!legacySaidStep(db,2).ready) { /* prepare */ }
      assert.equal(publishLegacySaid(db),true);
      const displaced = old.prepare("SELECT rowid id FROM entries WHERE thread=2 AND n=2").get()!.id;
      old.prepare(`UPDATE OR REPLACE entries SET ${alias}=? WHERE thread=1 AND n=1`).run(displaced);
      assert.deepEqual(visible(db),expected(db));
      while (legacySaidDrain(db,2)) assert.deepEqual(visible(db),expected(db));
      assert.deepEqual(visible(db),expected(db));
    } finally { old.close(); rig.close(); }
  });
}

test("other triggers see the current message even through a nested replacement", () => {
  const rig = database();
  const { db } = rig;
  try {
    // Created first, so the preparation's BEFORE trigger can run before this older trigger.
    db.exec(`CREATE TRIGGER nested_entry BEFORE INSERT ON entries WHEN NEW.text='outer' BEGIN
      INSERT OR REPLACE INTO entries VALUES(NEW.thread,NEW.n,'message','person','nested',NULL,'nested','inner');
    END`);
    while (!legacySaidStep(db,8).ready) { /* prepare */ }
    assert.equal(publishLegacySaid(db),true);
    db.exec(`CREATE TABLE observed(author TEXT);
      CREATE TRIGGER observe_entry AFTER INSERT ON entries WHEN NEW.text='outer' BEGIN
        INSERT INTO observed SELECT author FROM legacy_said WHERE thread=NEW.thread AND n=NEW.n;
      END`);
    db.prepare("INSERT OR REPLACE INTO entries VALUES(1,1,'message','person','outer',NULL,'outer','outer')").run();
    assert.deepEqual(db.prepare("SELECT author FROM observed").all().map((r) => r.author),["outer"]);
    assert.deepEqual(visible(db),expected(db));
  } finally { rig.close(); }
});

test("the view seeks one chat and its requested message range", () => {
  const rig = database();
  const { db } = rig;
  try {
    for (let n = 1; n <= 200; n++) { row(db,1,n,`a-${n}`); row(db,2,n,`b-${n}`); }
    while (!legacySaidStep(db,16).ready) { /* prepare */ }
    assert.equal(publishLegacySaid(db),true);
    db.prepare("DELETE FROM entries WHERE thread=1 AND n<=20").run();
    const plan = (db.prepare("EXPLAIN QUERY PLAN SELECT n,author FROM legacy_said WHERE thread=? AND n>? ORDER BY n LIMIT ?")
      .all(1,100,10) as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan,/SEARCH s USING PRIMARY KEY \(thread=\? AND n>\?\)/);
    assert.match(plan,/SEARCH d USING PRIMARY KEY \(thread=\? AND n>\?\)/);
    assert.doesNotMatch(plan,/SCAN (?:s|d|e)|USE TEMP B-TREE/);
    assert.deepEqual(visible(db),expected(db));
  } finally { rig.close(); }
});

test("the latest prepared message does not visit the rest of a chat's history", () => {
  const rig = database(), { db } = rig;
  try {
    for (let n = 1; n <= 400; n++) { if (n <= 40) row(db,1,n,"short"); row(db,2,n,"long"); }
    assert.equal(legacySaidStep(db,16).ready, false);
    let visited = 0, fallback = 0;
    db.function("visit_prepared_message", (_n) => { visited++; return 1; });
    db.function("visit_fallback_message", (_n) => { fallback++; return 1; });
    const traced = LEGACY_SAID_LATEST.replace("AND NOT EXISTS (SELECT 1 FROM legacy_said_dirty d WHERE d.thread=s.thread AND d.n=s.n)",
      "AND visit_prepared_message(s.n) AND NOT EXISTS (SELECT 1 FROM legacy_said_dirty d WHERE d.thread=s.thread AND d.n=s.n)")
      .replace("m.scanned=0 AND e.thread=?1", "m.scanned=0 AND visit_fallback_message(e.n) AND e.thread=?1");
    assert.notEqual(traced,LEGACY_SAID_LATEST);
    assert.match(traced,/visit_prepared_message\(s\.n\)/);
    assert.match(traced,/visit_fallback_message\(e\.n\)/);
    const latest = db.prepare(traced);
    const visits = (thread: number) => { visited = 0; fallback = 0; latest.get(thread); return { prepared: visited, fallback }; };
    assert.deepEqual([visits(1),visits(2)],[{ prepared: 0, fallback: 1 },{ prepared: 0, fallback: 1 }]);
    while (!legacySaidStep(db,16).ready) { /* prepare */ }
    assert.deepEqual([visits(1),visits(2)],[{ prepared: 1, fallback: 0 },{ prepared: 1, fallback: 0 }]);
  } finally { rig.close(); }
});

test("the latest message does not reread an older prepared key for every changed latest key", () => {
  const rig = database(), { db } = rig;
  try {
    for (let n = 1; n <= 400; n++) { if (n <= 40) row(db,1,n,"short"); row(db,2,n,"long"); }
    while (!legacySaidStep(db,16).ready) { /* prepare */ }
    db.prepare("UPDATE entries SET author='changed' WHERE thread IN (1,2)").run();
    let visited = 0;
    db.function("visit_changed_latest", (_n) => { visited++; return 1; });
    const traced = LEGACY_SAID_LATEST.replace("AND NOT EXISTS (SELECT 1 FROM legacy_said_dirty d WHERE d.thread=s.thread AND d.n=s.n)",
      "AND visit_changed_latest(s.n) AND NOT EXISTS (SELECT 1 FROM legacy_said_dirty d WHERE d.thread=s.thread AND d.n=s.n)");
    assert.notEqual(traced,LEGACY_SAID_LATEST);
    const latest = db.prepare(traced);
    const visits = (thread: number, n: number) => { visited = 0; assert.equal(latest.get(thread)?.n,n); return visited; };
    assert.ok(visits(1,40) <= 1);
    assert.ok(visits(2,400) <= 1);
  } finally { rig.close(); }
});

test("the latest lookup agrees with entries across interleaved replacements and i64 boundaries", () => {
  const rig = database(), { db } = rig;
  try {
    const put = db.prepare("INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,letter,ts) VALUES(?,?,?,?,?,?,?)");
    put.run(1,-9223372036854775808n,"message","person","minimum",null,"min");
    put.run(2,9223372036854775807n,"message","agent","maximum",null,"max");
    for (let n=1;n<=60;n++) put.run(1,n,"message","person",`p-${n%3}`,null,`t-${n}`);
    while (!legacySaidStep(db,8).ready) { /* prepare */ }
    const latest = db.prepare(LEGACY_SAID_LATEST);
    const expected = db.prepare("SELECT n,author_kind,author FROM entries WHERE thread=? AND kind='message' AND letter IS NULL ORDER BY n DESC LIMIT 1");
    latest.setReadBigInts(true); expected.setReadBigInts(true);
    const same = () => { for (const thread of [1,2,3]) assert.deepEqual(latest.get(thread),expected.get(thread)); };
    same();
    let seed = 0x12345678;
    const next = (range: number) => { seed = (Math.imul(seed,1664525)+1013904223) >>> 0; return seed % range; };
    for (let i=0;i<160;i++) {
      const thread = 1+next(3), n = 1+next(90);
      if (i%4 === 0) db.prepare("DELETE FROM entries WHERE thread=? AND n=?").run(thread,n);
      else if (i%4 === 1) db.prepare("UPDATE entries SET author=? WHERE thread=? AND n=?").run(`changed-${i}`,thread,n);
      else put.run(thread,n,i%7 === 0 ? "edit" : "message",i%5 === 0 ? "agent" : "person",`new-${i}`,
        i%11 === 0 ? "letter" : null,`replace-${i}`);
      same();
      if (i%13 === 0) { legacySaidDrain(db,8); same(); }
    }
    db.prepare("DELETE FROM entries WHERE thread=1 AND n>0").run();
    same();
    while (legacySaidDrain(db,8)) same();
    same();
  } finally { rig.close(); }
});

test("unrelated edits do not add work to the message lookup", () => {
  const rig = database(), { db } = rig;
  try {
    row(db,1,1,"original");
    while (!legacySaidStep(db,8).ready) { /* prepare */ }
    const edit = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,letter,ts) VALUES(1,?,'edit','person','p',NULL,?)");
    for (let n=2;n<=401;n++) {
      edit.run(n,`edit-${n}`);
      if (n === 41 || n === 401) assert.equal(db.prepare("SELECT COUNT(*) c FROM legacy_said_dirty").get()?.c,0);
    }
    db.prepare("UPDATE entries SET author='changed' WHERE thread=1 AND kind='edit'").run();
    db.prepare("DELETE FROM entries WHERE thread=1 AND kind='edit'").run();
    assert.equal(db.prepare("SELECT COUNT(*) c FROM legacy_said_dirty").get()?.c,0);
    assert.equal(db.prepare(LEGACY_SAID_LATEST).get(1)?.n,1);
  } finally { rig.close(); }
});

test("appending to an existing thread finds its previous message only once", () => {
  const rig = database(), { db } = rig;
  try {
    db.exec(`CREATE TABLE thread_state(thread INTEGER PRIMARY KEY,last_n INTEGER,said_n INTEGER,person_n INTEGER,letters INTEGER);
      CREATE TABLE thread_people(thread INTEGER,author TEXT,first_n INTEGER,PRIMARY KEY(thread,author));
      CREATE TRIGGER thread_state_add AFTER INSERT ON entries BEGIN SELECT 1; END;`);
    row(db,1,1,"first");
    db.exec("INSERT INTO thread_state VALUES(1,1,1,1,0)");
    while (!legacySaidStep(db,8).ready) { /* prepare */ }
    let visited = 0;
    db.function("visit_write_lookup", (_n) => { visited++; return 1; });
    let replacements = 0;
    const counted = new Proxy(db, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        if (sql.includes("CREATE TRIGGER said_state_before_insert")) {
          const traced = sql.replaceAll("s.thread=NEW.thread", "s.thread=NEW.thread AND (s.n=NEW.n OR visit_write_lookup(s.n))")
            .replaceAll("FROM entries WHERE thread=NEW.thread", "FROM entries WHERE thread=NEW.thread AND (n=NEW.n OR visit_write_lookup(n))");
          assert.notEqual(traced,sql);
          replacements++;
          sql = traced;
        }
        return target.exec(sql);
      };
      const value = Reflect.get(target,property,target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    installSaidState(counted);
    assert.equal(replacements,1);
    row(db,1,2,"second");
    assert.ok(visited <= 1,`the previous message was visited ${visited} times`);
    assert.deepEqual({ ...db.prepare("SELECT said_n,said_other_n,said_other_known FROM thread_state WHERE thread=1").get() },
      { said_n: 2,said_other_n: 1,said_other_known: 1 });
    db.exec("DELETE FROM thread_state WHERE thread=1");
    row(db,1,3,"third");
    assert.equal(db.prepare("SELECT said_other_known FROM thread_state WHERE thread=1").get()?.said_other_known,0);
    row(db,2,1,"first");
    assert.equal(db.prepare("SELECT said_other_known FROM thread_state WHERE thread=2").get()?.said_other_known,1);
  } finally { rig.close(); }
});

for (const recursive of [false,true]) test(`nested replacements involving edits keep the message lookup exact (recursive triggers ${recursive})`, () => {
  const rig = database(), { db } = rig;
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"};
      CREATE TRIGGER nested_edit BEFORE INSERT ON entries WHEN NEW.text='outer-edit' BEGIN
        INSERT OR REPLACE INTO entries VALUES(NEW.thread,NEW.n,'message','person','nested',NULL,'nested-message','inner');
      END;
      CREATE TRIGGER nested_message BEFORE INSERT ON entries WHEN NEW.text='outer-message' BEGIN
        INSERT OR REPLACE INTO entries VALUES(NEW.thread,NEW.n,'edit','person','nested',NULL,'nested-edit','inner');
      END;`);
    row(db,1,1,"existing");
    while (!legacySaidStep(db,8).ready) { /* prepare */ }
    db.prepare("INSERT OR REPLACE INTO entries VALUES(1,2,'edit','person','outer',NULL,'outer-edit','outer-edit')").run();
    assert.deepEqual(visible(db),expected(db));
    db.prepare("INSERT OR REPLACE INTO entries VALUES(1,3,'message','person','outer',NULL,'outer-message','outer-message')").run();
    assert.deepEqual(visible(db),expected(db));
    db.prepare("INSERT OR REPLACE INTO entries VALUES(1,4,'edit','person','outer',NULL,'1','outer-edit')").run();
    assert.deepEqual(visible(db),expected(db));
    while (legacySaidDrain(db,2)) assert.deepEqual(visible(db),expected(db));
    assert.deepEqual(visible(db),expected(db));
  } finally { rig.close(); }
});

test("each old-message batch seeks its next key range", () => {
  const rig = database();
  const { db } = rig;
  try {
    for (let n=1;n<=400;n++) { row(db,1,n,"a"); row(db,2,n,"b"); }
    let visited = 0,queries = 0;
    db.function("visit_old_said", () => { visited++; return 1; });
    const counted = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql.includes("SELECT CAST(e.thread AS TEXT) thread,CAST(e.n AS TEXT) n,e.kind,e.letter,e.author_kind,e.author")) {
          queries++;
          sql = sql.replace(/FROM entries e\s+WHERE/,"FROM entries e WHERE visit_old_said() AND");
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target,property,target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    let result;
    do {
      visited = 0;
      result = legacySaidStep(counted,16);
      assert.ok(visited <= 16,`a batch read ${visited} entries`);
    } while (!result.ready);
    assert.ok(queries > 2);
    assert.equal(publishLegacySaid(db),true);
    assert.deepEqual(visible(db),expected(db));
  } finally { rig.close(); }
});

test("unread counts correct only the changed keys in the requested range", () => {
  const rig = database();
  const { db } = rig;
  try {
    for (let n=1;n<=128;n++) { row(db,1,n,`p-${n%4}`); row(db,2,n,"other"); }
    while (!legacySaidStep(db,16).ready) { /* prepare */ }
    assert.equal(publishLegacySaid(db),true);
    db.prepare("DELETE FROM entries WHERE thread=1 AND n IN (2,5,127)").run();
    db.prepare("UPDATE entries SET author='changed' WHERE thread=1 AND n=3").run();
    db.prepare("UPDATE entries SET letter='letter' WHERE thread=1 AND n=4").run();
    db.prepare("INSERT OR REPLACE INTO entries VALUES(1,7,'edit','agent','agent',NULL,'replacement',NULL)").run();
    row(db,1,129,"new","new");
    db.prepare("UPDATE entries SET author='unrelated' WHERE thread=2 AND n<=100").run();
    const original = db.prepare(`SELECT COUNT(*) c FROM entries e WHERE e.thread=?1 AND e.n>?2
      AND e.kind='message' AND e.letter IS NULL AND NOT (e.author_kind='person' AND e.author IN (SELECT value FROM json_each(?3)))`);
    const count = db.prepare(LEGACY_UNREAD);
    const any = db.prepare(LEGACY_HAS_UNREAD);
    for (const thread of [1,2,3]) for (const before of [0,3,127,129]) for (const self of [[],["p-1","new"]]) {
      const args = [thread,before,JSON.stringify(self)] as const;
      const want = original.get(...args)!.c;
      assert.equal(count.get(...args)!.c,want);
      assert.equal(any.get(...args)!.c,want === 0 ? 0 : 1);
    }
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${LEGACY_UNREAD}`).all(1,3,"[]") as { detail: string }[])
      .map((r) => r.detail).join(" | ");
    assert.match(plan,/SEARCH s USING PRIMARY KEY \(thread=\? AND n>\?\)/);
    assert.match(plan,/SEARCH d USING PRIMARY KEY \(thread=\? AND n>\?\)/);
    assert.match(plan,/SEARCH e USING INDEX sqlite_autoindex_entries_1 \(thread=\? AND n=\?\)/);
  } finally { rig.close(); }
});

test("the prepared count and its corrections use the same snapshot", () => {
  const rig = database();
  const { db } = rig;
  const old = new DatabaseSync(rig.path);
  try {
    row(db,1,1,"self");
    row(db,1,2,"other");
    while (!legacySaidStep(db,8).ready) { /* prepare */ }
    assert.equal(publishLegacySaid(db),true);
    db.function("write_during_count", () => {
      old.prepare("UPDATE entries SET author='changed' WHERE thread=1 AND n=1").run();
      return 0;
    });
    const interleaved = LEGACY_UNREAD.replace("\n  - (SELECT COUNT(*)", "\n  + write_during_count() - (SELECT COUNT(*)");
    assert.notEqual(interleaved,LEGACY_UNREAD);
    assert.equal(db.prepare(interleaved).get(1,0,'["self"]')!.c,1);
    assert.equal(db.prepare(LEGACY_UNREAD).get(1,0,'["self"]')!.c,2);
  } finally { old.close(); rig.close(); }
});
