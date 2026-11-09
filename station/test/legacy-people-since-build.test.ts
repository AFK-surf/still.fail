import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { hasLegacyPeopleSince, hasNativePeopleSince, installPeopleSinceIndex, LEGACY_PEOPLE_SINCE,
  peopleSinceReady, peopleSinceStep } from "../src/store/legacy-people-since.ts";

const schema = `CREATE TABLE threads(id INTEGER PRIMARY KEY);
  CREATE TABLE entries(thread INTEGER NOT NULL,n INTEGER NOT NULL,kind TEXT NOT NULL,ts TEXT,
  author_kind TEXT NOT NULL,author TEXT NOT NULL,at INTEGER NOT NULL,PRIMARY KEY(thread,n));
  CREATE UNIQUE INDEX entries_ts ON entries(thread,ts) WHERE ts IS NOT NULL;`;
const make = () => { const db = new DatabaseSync(":memory:"); db.exec(schema + " INSERT INTO threads VALUES(1),(2)"); return db; };
const rows = (db: DatabaseSync, sql: string, ...args: (number | string)[]) => db.prepare(sql).all(...args).map((r) => ({ ...r }));
const finish = (db: DatabaseSync, thread: number) => { while (!peopleSinceStep(db, thread).done) {} };

test("a requested chat's old people-time lookup is prepared in bounded slices", () => {
  const db = make();
  try {
    const put = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,at) VALUES(?,?,'message',?,?,'a',?)");
    for (let n=1;n<=400;n++) { put.run(1,n,`a-${n}`,n % 3 ? "agent" : "person",n % 17); put.run(2,n,`b-${n}`,"person",n); }
    installPeopleSinceIndex(db);
    assert.equal(hasLegacyPeopleSince(db), true);
    assert.equal(hasNativePeopleSince(db), false);
    assert.equal(peopleSinceReady(db,1), false);
    assert.deepEqual(peopleSinceStep(db,1), { done: false, visited: 64 });
    assert.deepEqual(rows(db,"SELECT thread FROM legacy_people_time_scopes"), [{ thread: 1 }]);
    finish(db,1);
    assert.equal(peopleSinceReady(db,1), true);
    assert.equal(peopleSinceReady(db,2), false);
    assert.deepEqual(rows(db,LEGACY_PEOPLE_SINCE + " ORDER BY e.n",1,6),
      rows(db,"SELECT thread,n FROM entries WHERE thread=? AND at>=? AND kind='message' AND author_kind='person' ORDER BY n",1,6));
    const plan = rows(db,"EXPLAIN QUERY PLAN " + LEGACY_PEOPLE_SINCE,1,6).map((r) => r.detail).join(" ");
    assert.match(plan,/SEARCH k USING INDEX legacy_people_time_by_at \(thread=\? AND at>\?\)/);
    assert.match(plan,/SEARCH e USING INTEGER PRIMARY KEY \(rowid=\?\)/);
  } finally { db.close(); }
});

test("small stores retain the native index and large old keys keep their exact values", () => {
  const small = make(), large = make();
  try {
    const putSmall = small.prepare("INSERT INTO entries VALUES(1,?,'message',NULL,'person','p',?)");
    for (let n=1;n<=63;n++) putSmall.run(n,n);
    installPeopleSinceIndex(small);
    assert.equal(hasNativePeopleSince(small),true);
    assert.deepEqual(peopleSinceStep(small,1), { done: true, visited: 0 });
    large.exec(`INSERT INTO entries VALUES(1,9223372036854775806,'message',NULL,'person','p',1);
      INSERT INTO entries VALUES(1,9007199254740992,'message',NULL,'person','p',2);
      INSERT INTO entries VALUES(1,9007199254740993,'message',NULL,'person','p',3);`);
    const put = large.prepare("INSERT INTO entries VALUES(2,?,'message',NULL,'person','p',?)");
    for (let n=1;n<=64;n++) put.run(n,n);
    installPeopleSinceIndex(large);
    for (let i=0;i<3;i++) assert.equal(peopleSinceStep(large,1,1).visited,1);
    assert.equal(peopleSinceStep(large,1,1).done,true);
    assert.deepEqual(rows(large,"SELECT CAST(n AS TEXT) AS n FROM legacy_people_time_rows WHERE thread=1 ORDER BY n"), [
      { n:"9007199254740992" }, { n:"9007199254740993" }, { n:"9223372036854775806" },
    ]);
  } finally { small.close(); large.close(); }
});

for (const recursive of [false,true]) test(`old writes and ignored or replaced conflicts keep people-time rows current (recursive ${recursive})`, () => {
  const db = make();
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? 1 : 0}`);
    const fill = db.prepare("INSERT INTO entries(rowid,thread,n,kind,ts,author_kind,author,at) VALUES(10000+?,99,?,'message',NULL,'agent','a',?)");
    for (let n=1;n<=64;n++) fill.run(n,n,n);
    installPeopleSinceIndex(db); finish(db,1); finish(db,2);
    const check = () => assert.deepEqual(
      rows(db,"SELECT source_rowid AS id,thread,n,at FROM legacy_people_time_rows WHERE thread IN (1,2) ORDER BY id"),
      rows(db,"SELECT rowid AS id,thread,n,at FROM entries WHERE thread IN (1,2) AND kind='message' AND author_kind='person' ORDER BY id"));
    db.exec(`INSERT INTO entries(rowid,thread,n,kind,ts,author_kind,author,at) VALUES
      (1,1,1,'message','one','person','p',10),(2,1,2,'message','two','person','p',20),
      (3,2,1,'message','three','person','p',30)`); check();
    db.exec("INSERT OR IGNORE INTO entries(rowid,thread,n,kind,ts,author_kind,author,at) VALUES(4,1,99,'message','one','person','p',40)"); check();
    db.exec("INSERT OR REPLACE INTO entries(rowid,thread,n,kind,ts,author_kind,author,at) VALUES(4,1,3,'message','one','person','p',40)"); check();
    db.exec("UPDATE OR REPLACE entries SET thread=1,n=4,ts='two',author_kind='agent',at=50 WHERE rowid=3"); check();
    db.exec("UPDATE entries SET author_kind='person',at=60 WHERE rowid=3"); check();
    db.exec("UPDATE entries SET author_kind='agent' WHERE rowid=4"); check();
    db.exec("DELETE FROM entries WHERE rowid=3"); check();
  } finally { db.close(); }
});

test("an unprepared chat replacing a prepared chat's rowid removes its old candidate", () => {
  const db = make();
  try {
    const fill = db.prepare("INSERT INTO entries(rowid,thread,n,kind,ts,author_kind,author,at) VALUES(10000+?,99,?,'message',NULL,'agent','a',?)");
    for (let n=1;n<=64;n++) fill.run(n,n,n);
    installPeopleSinceIndex(db); finish(db,1);
    db.exec("INSERT INTO entries(rowid,thread,n,kind,ts,author_kind,author,at) VALUES(1,1,1,'message','one','person','p',10)");
    assert.equal(rows(db,LEGACY_PEOPLE_SINCE,1,0).length,1);
    db.exec("INSERT OR REPLACE INTO entries(rowid,thread,n,kind,ts,author_kind,author,at) VALUES(1,2,1,'message','two','person','p',20)");
    assert.deepEqual(rows(db,LEGACY_PEOPLE_SINCE,1,0),[]);
    assert.equal(peopleSinceReady(db,2),false);
  } finally { db.close(); }
});

test("one replacement can displace three people through rowid, number and timestamp", () => {
  const db = make();
  try {
    const fill = db.prepare("INSERT INTO entries(rowid,thread,n,kind,ts,author_kind,author,at) VALUES(10000+?,99,?,'message',NULL,'agent','a',?)");
    for (let n=1;n<=64;n++) fill.run(n,n,n);
    installPeopleSinceIndex(db); finish(db,1); finish(db,2);
    db.exec(`INSERT INTO entries(rowid,thread,n,kind,ts,author_kind,author,at) VALUES
      (1,2,1,'message','other','person','p',10),
      (2,1,2,'message','number','person','p',20),
      (3,1,3,'message','timestamp','person','p',30);
      INSERT OR REPLACE INTO entries(rowid,thread,n,kind,ts,author_kind,author,at)
      VALUES(1,1,2,'message','timestamp','person','p',40)`);
    assert.deepEqual(rows(db,"SELECT source_rowid AS id,thread,n,at FROM legacy_people_time_rows ORDER BY id"),
      rows(db,"SELECT rowid AS id,thread,n,at FROM entries WHERE author_kind='person' AND kind='message' ORDER BY id"));
  } finally { db.close(); }
});

test("deleting a prepared chat removes its people-time state", () => {
  const db = make();
  try {
    const put = db.prepare("INSERT INTO entries VALUES(1,?,'message',NULL,'person','p',?)");
    for (let n=1;n<=64;n++) put.run(n,n);
    installPeopleSinceIndex(db); finish(db,1);
    db.exec("DELETE FROM entries WHERE thread=1; DELETE FROM threads WHERE id=1");
    assert.deepEqual(rows(db,"SELECT thread FROM legacy_people_time_scopes"),[]);
    assert.deepEqual(rows(db,"SELECT thread,n FROM legacy_people_time_rows"),[]);
    assert.deepEqual(peopleSinceStep(db,1),{ done:true, visited:0 });
    assert.deepEqual(rows(db,"SELECT thread FROM legacy_people_time_scopes"),[]);
    db.exec("INSERT INTO threads VALUES(1)");
    put.run(1,100);
    assert.equal(peopleSinceReady(db,1),false);
    finish(db,1);
    assert.deepEqual(rows(db,"SELECT thread,n,at FROM legacy_people_time_rows"),[{ thread:1,n:1,at:100 }]);
  } finally { db.close(); }
});

for (const recursive of [false,true]) for (const when of ["BEFORE","AFTER"]) for (const installedFirst of [false,true])
  test(`nested ${when.toLowerCase()} writes reconcile people-time rows (recursive ${recursive}, installed first ${installedFirst})`, () => {
    const db = make();
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? 1 : 0}`);
      const fill = db.prepare("INSERT INTO entries(rowid,thread,n,kind,ts,author_kind,author,at) VALUES(10000+?,99,?,'message',NULL,'agent','a',?)");
      for (let n=1;n<=64;n++) fill.run(n,n,n);
      const nested = `CREATE TRIGGER people_time_nested ${when} INSERT ON entries WHEN NEW.author='outer' BEGIN
        INSERT OR REPLACE INTO entries(rowid,thread,n,kind,ts,author_kind,author,at)
        VALUES(NEW.rowid,2,99,'message','nested','person','inner',999); END;`;
      if (installedFirst) installPeopleSinceIndex(db);
      db.exec(nested);
      if (!installedFirst) installPeopleSinceIndex(db);
      finish(db,1); finish(db,2);
      db.exec("INSERT OR REPLACE INTO entries(rowid,thread,n,kind,ts,author_kind,author,at) VALUES(1,1,1,'message','one','person','outer',10)");
      assert.deepEqual(rows(db,"SELECT source_rowid AS id,thread,n,at FROM legacy_people_time_rows WHERE thread IN (1,2) ORDER BY id"),
        rows(db,"SELECT rowid AS id,thread,n,at FROM entries WHERE thread IN (1,2) AND kind='message' AND author_kind='person' ORDER BY id"));
    } finally { db.close(); }
  });

for (const recursive of [false,true]) for (const when of ["BEFORE","AFTER"]) for (const installedFirst of [false,true])
  for (const action of ["update","delete"]) test(`nested ${when.toLowerCase()} ${action} keeps people-time rows current (recursive ${recursive}, installed first ${installedFirst})`, () => {
    const db = make();
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? 1 : 0}`);
      const fill = db.prepare("INSERT INTO entries(rowid,thread,n,kind,ts,author_kind,author,at) VALUES(10000+?,99,?,'message',NULL,'agent','a',?)");
      for (let n=1;n<=64;n++) fill.run(n,n,n);
      db.exec(`INSERT INTO entries(rowid,thread,n,kind,ts,author_kind,author,at) VALUES
        (1,1,1,'message','outer','person','outer',10),(2,2,2,'message','inner','person','inner',20)`);
      const nested = `CREATE TRIGGER people_time_nested ${when} ${action === "update" ? "UPDATE" : "DELETE"} ON entries
        WHEN OLD.author='outer' BEGIN ${action === "update"
          ? "UPDATE entries SET at=200,author_kind='agent' WHERE rowid=2;"
          : "DELETE FROM entries WHERE rowid=2;"} END;`;
      if (installedFirst) installPeopleSinceIndex(db);
      db.exec(nested);
      if (!installedFirst) installPeopleSinceIndex(db);
      finish(db,1); finish(db,2);
      db.exec(action === "update" ? "UPDATE entries SET at=100 WHERE rowid=1" : "DELETE FROM entries WHERE rowid=1");
      assert.deepEqual(rows(db,"SELECT source_rowid AS id,thread,n,at FROM legacy_people_time_rows ORDER BY id"),
        rows(db,"SELECT rowid AS id,thread,n,at FROM entries WHERE author_kind='person' AND kind='message' ORDER BY id"));
    } finally { db.close(); }
  });
