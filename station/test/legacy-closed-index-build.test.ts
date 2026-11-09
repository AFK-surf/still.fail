import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { CLOSED_CARDS_INDEXED, CLOSED_CHAT_SAMPLE, CLOSED_TIME_SAMPLE, LEGACY_CLOSED_CARDS, closedCardsReady, closedCardsStep, hasLegacyClosedCards, installClosedCardsIndex } from "../src/store/legacy-closed-cards.ts";

const schema = `CREATE TABLE closed_cards(thread INTEGER NOT NULL,n INTEGER NOT NULL,viewer TEXT NOT NULL,at INTEGER NOT NULL,
  PRIMARY KEY(thread,n));`;
const make = () => { const db = new DatabaseSync(":memory:"); db.exec(schema); return db; };
const finish = (db: DatabaseSync, thread: number) => { while (!closedCardsStep(db, thread).done) {} };
const rows = (db: DatabaseSync, sql: string, ...args: (number | string)[]) => db.prepare(sql).all(...args).map((row) => ({ ...row }));

test("a requested old chat is prepared in bounded slices and no other chat is read", () => {
  const db = make();
  try {
    const put = db.prepare("INSERT INTO closed_cards VALUES(?,?,?,?)");
    for (let n = 1; n <= 400; n++) { put.run(1,n,"person",n % 11); put.run(2,n,"person",n); }
    installClosedCardsIndex(db);
    assert.equal(hasLegacyClosedCards(db), true);
    assert.equal(closedCardsReady(db, 1), false);
    assert.deepEqual(closedCardsStep(db, 1), { done: false, visited: 64 });
    assert.equal(closedCardsReady(db, 1), false);
    assert.deepEqual(rows(db, "SELECT thread FROM legacy_closed_scopes"), [{ thread: 1 }]);
    finish(db, 1);
    assert.equal(closedCardsReady(db, 1), true);
    assert.equal(closedCardsReady(db, 2), false);
    assert.deepEqual(rows(db, LEGACY_CLOSED_CARDS + " ORDER BY c.at,c.rowid", 1, 6),
      rows(db, "SELECT thread,n,viewer,at,rowid AS ordering FROM closed_cards WHERE thread=? AND at>=? ORDER BY at,rowid", 1, 6));
    const plan = rows(db, "EXPLAIN QUERY PLAN " + LEGACY_CLOSED_CARDS, 1, 6).map((r) => r.detail).join(" ");
    assert.match(plan, /SEARCH k USING INDEX legacy_closed_by_time \(thread=\? AND at>\?\)/);
    assert.match(plan, /SEARCH c USING INTEGER PRIMARY KEY \(rowid=\?\)/);
  } finally { db.close(); }
});

test("small stores keep the native lookup, large stores retain exact integer cursors", () => {
  const small = make(), large = make();
  try {
    const putSmall = small.prepare("INSERT INTO closed_cards VALUES(1,?,'p',?)");
    for (let n = 1; n <= 63; n++) putSmall.run(n,n);
    installClosedCardsIndex(small);
    assert.deepEqual(closedCardsStep(small, 1), { done: true, visited: 0 });
    assert.equal(rows(small, CLOSED_CARDS_INDEXED, 1, 1).length, 63);
    large.exec(`INSERT INTO closed_cards VALUES(1,9223372036854775806,'p',1);
      INSERT INTO closed_cards VALUES(1,9007199254740992,'p',2);
      INSERT INTO closed_cards VALUES(1,9007199254740993,'p',3);`);
    const put = large.prepare("INSERT INTO closed_cards VALUES(2,?,'p',?)");
    for (let n = 1; n <= 64; n++) put.run(n,n);
    installClosedCardsIndex(large);
    for (let i = 0; i < 3; i++) assert.equal(closedCardsStep(large, 1, 1).visited, 1);
    assert.equal(closedCardsStep(large, 1, 1).done, true);
    assert.deepEqual(rows(large, "SELECT CAST(n AS TEXT) AS n FROM legacy_closed_cards WHERE thread=1 ORDER BY n"), [
      { n: "9007199254740992" }, { n: "9007199254740993" }, { n: "9223372036854775806" },
    ]);
  } finally { small.close(); large.close(); }
});

test("first-read probes have a fixed cost when unrelated or old records grow", () => {
  const counts: number[][] = [];
  for (const size of [40, 400]) {
    const db = make();
    try {
      db.exec("CREATE INDEX closed_cards_at ON closed_cards(at)");
      const put = db.prepare("INSERT INTO closed_cards VALUES(?,?,?,?)");
      for (let n=1;n<=size;n++) { put.run(1,n,"p",100); put.run(2,n,"p",100); }
      let visited = 0;
      db.function("visit_closed_probe", (_n) => { visited++; return 1; });
      const chat = CLOSED_CHAT_SAMPLE.replace("WHERE c.thread=?1", "WHERE c.thread=?1 AND visit_closed_probe(c.n)");
      const time = CLOSED_TIME_SAMPLE.replace("WHERE at>=?", "WHERE at>=? AND visit_closed_probe(n)");
      assert.notEqual(chat, CLOSED_CHAT_SAMPLE); assert.notEqual(time, CLOSED_TIME_SAMPLE);
      db.prepare(chat).all(1,50); const chatCount = visited; visited = 0;
      db.prepare(time).all(50, "[1]"); counts.push([chatCount,visited]);
      const plan = rows(db, "EXPLAIN QUERY PLAN " + chat, 1, 50).map((r) => r.detail).join(" ");
      assert.match(plan, /SEARCH c USING INDEX .*\(thread=\?\)/);
      const timePlan = rows(db, "EXPLAIN QUERY PLAN " + time, 50, "[1]").map((r) => r.detail).join(" ");
      assert.match(timePlan, /SEARCH closed_cards USING INDEX closed_cards_at \(at>\?\)/);
    } finally { db.close(); }
  }
  assert.deepEqual(counts, [[40,65],[65,65]]);
});

test("a prepared answer window skips old and unrelated closed cards", () => {
  const counts: number[] = [];
  for (const size of [40,400]) {
    const db = make();
    try {
      const put = db.prepare("INSERT INTO closed_cards VALUES(?,?,?,?)");
      put.run(1,1,"p",100);
      for (let n=2;n<=size+1;n++) { put.run(1,n,"p",0); put.run(2,n,"p",100); }
      installClosedCardsIndex(db); finish(db,1); finish(db,2);
      let visited = 0;
      db.function("visit_closed_answer", (_n) => { visited++; return 1; });
      const sql = LEGACY_CLOSED_CARDS.replace("AND k.at>=?", "AND k.at>=? AND visit_closed_answer(k.n)");
      assert.notEqual(sql, LEGACY_CLOSED_CARDS);
      assert.equal(db.prepare(sql).all(1,50).length,1);
      counts.push(visited);
    } finally { db.close(); }
  }
  assert.deepEqual(counts,[1,1]);
});

test("preparation retries if a native index disappears between its checks", () => {
  const db = make();
  try {
    const put = db.prepare("INSERT INTO closed_cards VALUES(1,?,'p',?)");
    for (let n=1;n<=100;n++) put.run(n,n);
    db.exec("CREATE INDEX closed_cards_thread_at ON closed_cards(thread,at)");
    let dropped = false;
    const raced = new Proxy(db, { get(target, property) {
      if (property !== "prepare") {
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      }
      return (sql: string) => {
        const statement = target.prepare(sql);
        if (sql !== "SELECT 1 FROM sqlite_master WHERE type=? AND name=?") return statement;
        return new Proxy(statement, { get(query, method) {
          if (method === "get") return (...args: any[]) => {
            const found = query.get(...args);
            if (!dropped && args[1] === "closed_cards_thread_at" && found) {
              dropped = true;
              db.exec("DROP INDEX closed_cards_thread_at");
            }
            return found;
          };
          const value = Reflect.get(query, method, query);
          return typeof value === "function" ? value.bind(query) : value;
        } });
      };
    } });
    assert.deepEqual(closedCardsStep(raced, 1), { done: false, visited: 0 });
    assert.equal(dropped, true);
    finish(db, 1);
    assert.equal(closedCardsReady(db, 1), true);
    assert.equal(rows(db, "SELECT n FROM legacy_closed_cards WHERE thread=1").length, 100);
  } finally { db.close(); }
});

for (const recursive of [false, true]) for (const when of ["BEFORE", "AFTER"]) {
  for (const by of ["number", "rowid"]) for (const installFirst of [false, true]) {
    test(`old ${when.toLowerCase()} ${by} replacement keeps closed cards current (recursive ${recursive}, installed first ${installFirst})`, () => {
      const db = make();
      try {
        db.exec(`PRAGMA recursive_triggers=${recursive ? 1 : 0};`);
        const put = db.prepare("INSERT INTO closed_cards(rowid,thread,n,viewer,at) VALUES(?,99,?,'old',?)");
        for (let n = 1; n <= 64; n++) put.run(10000+n,n,n);
        const nested = `CREATE TRIGGER nested ${when} INSERT ON closed_cards WHEN NEW.viewer='outer' BEGIN
          INSERT OR REPLACE INTO closed_cards(rowid,thread,n,viewer,at)
          VALUES(${by === "rowid" ? "NEW.rowid" : "900"},${by === "rowid" ? "2" : "NEW.thread"},
            ${by === "number" ? "NEW.n" : "99"},'inner',999); END;`;
        if (installFirst) installClosedCardsIndex(db);
        db.exec(nested);
        if (!installFirst) installClosedCardsIndex(db);
        finish(db, 1); finish(db, 2);
        const check = () => assert.deepEqual(
          rows(db, "SELECT thread,n,at,source_rowid AS id FROM legacy_closed_cards ORDER BY thread,n"),
          rows(db, "SELECT thread,n,at,rowid AS id FROM closed_cards WHERE thread IN (1,2) ORDER BY thread,n"));
        db.exec("INSERT INTO closed_cards(rowid,thread,n,viewer,at) VALUES(1,1,1,'a',10),(2,1,2,'b',20)"); check();
        db.exec("INSERT OR REPLACE INTO closed_cards(rowid,thread,n,viewer,at) VALUES(3,1,3,'outer',30)"); check();
        db.exec("INSERT OR IGNORE INTO closed_cards(rowid,thread,n,viewer,at) VALUES(4,1,1,'ignored',50)"); check();
        db.exec("UPDATE OR REPLACE closed_cards SET rowid=1,thread=2,n=4,at=60 WHERE thread=1 AND n=2"); check();
        db.exec("DELETE FROM closed_cards WHERE thread=2 AND n=4"); check();
      } finally { db.close(); }
    });
  }
}

for (const recursive of [false, true]) for (const when of ["BEFORE", "AFTER"]) {
  for (const operation of ["UPDATE", "DELETE"]) for (const installFirst of [false, true]) {
    test(`closed cards follow nested ${when.toLowerCase()} ${operation.toLowerCase()} writes (recursive ${recursive}, installed first ${installFirst})`, () => {
      const db = make();
      try {
        db.exec(`PRAGMA recursive_triggers=${recursive ? 1 : 0};`);
        const put = db.prepare("INSERT INTO closed_cards(rowid,thread,n,viewer,at) VALUES(?,99,?,'old',?)");
        for (let n=1;n<=64;n++) put.run(10000+n,n,n);
        const nested = `CREATE TRIGGER nested ${when} ${operation} ON closed_cards
          WHEN ${operation === "UPDATE" ? "NEW.viewer" : "OLD.viewer"}='outer' BEGIN
          INSERT OR REPLACE INTO closed_cards(rowid,thread,n,viewer,at)
          VALUES(${operation === "UPDATE" ? "NEW.rowid" : when === "BEFORE" ? "3" : "OLD.rowid"},2,99,'inner',999); END;`;
        if (installFirst) installClosedCardsIndex(db);
        db.exec(nested);
        if (!installFirst) installClosedCardsIndex(db);
        finish(db,1); finish(db,2);
        db.exec(`INSERT INTO closed_cards(rowid,thread,n,viewer,at) VALUES(1,1,1,${operation === "DELETE" ? "'outer'" : "'a'"},10);
          INSERT INTO closed_cards(rowid,thread,n,viewer,at) VALUES(2,2,2,'b',20);`);
        if (operation === "UPDATE") db.exec("UPDATE OR REPLACE closed_cards SET rowid=3,n=3,viewer='outer',at=30 WHERE rowid=1");
        else db.exec("DELETE FROM closed_cards WHERE rowid=1");
        assert.deepEqual(rows(db,"SELECT thread,n,at,source_rowid AS id FROM legacy_closed_cards ORDER BY thread,n"),
          rows(db,"SELECT thread,n,at,rowid AS id FROM closed_cards WHERE thread IN (1,2) ORDER BY thread,n"));
      } finally { db.close(); }
    });
  }
}
