import assert from "node:assert/strict";
import { constants, DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { makeStore, saidOf } from "../src/read/store.ts";
import { installSaidState, saidBoundary, saidScanStep, SAID_LATEST, SAID_STATE, type SaidScan } from "../src/store/said-state.ts";
import { Store } from "../src/store/store.ts";

test("installing sidebar state does not read old messages", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`CREATE TABLE entries(thread INTEGER, n INTEGER, kind TEXT, author_kind TEXT, author TEXT, letter TEXT, ts TEXT,
        PRIMARY KEY(thread,n));
      CREATE INDEX entries_said ON entries(thread,n,author_kind,author,letter) WHERE kind='message' AND letter IS NULL;
      CREATE TABLE thread_state(thread INTEGER PRIMARY KEY, last_n INTEGER NOT NULL, said_n INTEGER, person_n INTEGER, letters INTEGER NOT NULL);
      CREATE TABLE thread_people(thread INTEGER, author TEXT, first_n INTEGER, PRIMARY KEY(thread,author)) WITHOUT ROWID;
      CREATE TRIGGER thread_state_add AFTER INSERT ON entries BEGIN SELECT 1; END;
      INSERT INTO entries VALUES(1,1,'message','person','old',NULL,'old');
      INSERT INTO thread_state VALUES(1,1,1,1,0);`);
    db.setAuthorizer((action, table, column) => action === constants.SQLITE_READ && table === "entries" && column
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { installSaidState(db); } finally { db.setAuthorizer(null); }
    assert.equal(db.prepare("SELECT said_other_known FROM thread_state WHERE thread=1").get()?.said_other_known, 0);
    installSaidState(db);
  } finally { db.close(); }
});

test("an old chat is read in bounded slices and same-person appends do not restart the work", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "old", null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES (?,?,'message',?,?,?,?)");
    db.exec("BEGIN");
    put.run(thread, 1, "agent", "s", "t1", 1);
    for (let n = 2; n <= 501; n++) put.run(thread, n, "person", "a", `t${n}`, n);
    db.exec("COMMIT");
    db.prepare("UPDATE thread_state SET said_other_known=0 WHERE thread=?").run(thread);
    const initial = saidScanStep(db, thread, null);
    assert.equal(initial.done, false);
    assert.equal(initial.visited, 0);
    let scan = initial.scan;
    const first = saidScanStep(db, thread, scan);
    assert.equal(first.visited, 64);
    scan = first.scan;
    const token = scan?.token;
    put.run(thread, 502, "person", "a", "t502", 502);
    assert.equal(db.prepare("SELECT token FROM said_state_guard WHERE thread=?").get(thread)?.token, token);
    let visited = first.visited;
    for (;;) {
      const step = saidScanStep(db, thread, scan);
      assert.ok(step.visited <= 64);
      visited += step.visited;
      scan = step.scan;
      if (step.done) break;
    }
    assert.equal(visited, 500);
    const latest = db.prepare(SAID_LATEST).get(thread) as any;
    const state = db.prepare(SAID_STATE).get(thread) as any;
    assert.deepEqual(saidBoundary(state, latest), { known: true, other: 1 });
    assert.equal(db.prepare("SELECT 1 FROM said_state_guard WHERE thread=?").get(thread), undefined);
    assert.deepEqual(saidOf(makeStore(db, "/none"), thread), { n: 502, authorKind: "person", author: "a", other: 1 });
  } finally { store.close(); }
});

test("a change after an old slice is read cannot publish its stale result", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "race", null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES (?,?,'message',?,?,?,?)");
    put.run(thread, 1, "agent", "s", "t1", 1);
    for (let n = 2; n <= 30; n++) put.run(thread, n, "person", "a", `t${n}`, n);
    db.prepare("UPDATE thread_state SET said_other_known=0 WHERE thread=?").run(thread);
    let scan = saidScanStep(db, thread, null).scan;
    let changed = false;
    const raced = saidScanStep(db, thread, scan, 64, () => {
      if (!changed) {
        changed = true;
        db.prepare("UPDATE entries SET author='b' WHERE thread=? AND n=20").run(thread);
      }
      return true;
    });
    assert.ok(changed);
    assert.equal(raced.done, false);
    assert.equal(raced.scan, null);
    scan = null;
    for (;;) {
      const step = saidScanStep(db, thread, scan);
      scan = step.scan;
      if (step.done) break;
    }
    assert.deepEqual(saidOf(makeStore(db, "/none"), thread), { n: 30, authorKind: "person", author: "a", other: 20 });
  } finally { store.close(); }
});

test("a partial deletion can leave a missing thread state without leaving an incorrect answer", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "removed", null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES (?,?,'message',?,?,?,?)");
    put.run(thread, 1, "agent", "s", "t1", 1);
    for (let n = 2; n <= 10; n++) put.run(thread, n, "person", "a", `t${n}`, n);
    db.prepare("DELETE FROM entries WHERE thread=? AND n=5").run(thread);
    assert.equal(db.prepare("SELECT 1 FROM thread_state WHERE thread=?").get(thread), undefined);
    const finish = () => {
      let scan: SaidScan | null = null;
      for (;;) {
        const step = saidScanStep(db, thread, scan);
        scan = step.scan;
        if (step.done) return;
      }
    };
    finish();
    assert.deepEqual(saidOf(makeStore(db, "/none"), thread), { n: 10, authorKind: "person", author: "a", other: 1 });
    put.run(thread, 11, "person", "a", "t11", 11);
    assert.deepEqual(saidOf(makeStore(db, "/none"), thread), { n: 11, authorKind: "person", author: "a", other: 1 });
    put.run(thread, 5, "person", "b", "new5", 5);
    assert.equal(db.prepare("SELECT 1 FROM said_state_guard WHERE thread=?").get(thread), undefined);
    finish();
    assert.deepEqual(saidOf(makeStore(db, "/none"), thread), { n: 11, authorKind: "person", author: "a", other: 5 });
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`sidebar state follows appends and invalidates on older writes (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    const thread = store.openThread("ember", "EMBER", "chat", null, null).id;
    const insert = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,ts,at,letter)
      VALUES (?,?,?,?,?,?,?,?)`);
    const read = makeStore(db, "/no-station-config");
    const latest = db.prepare(`SELECT n, author_kind, author FROM entries
      WHERE thread=? AND kind='message' AND letter IS NULL ORDER BY n DESC LIMIT 1`);
    const different = db.prepare(`SELECT n FROM entries WHERE thread=? AND kind='message' AND letter IS NULL
      AND NOT (author_kind='person' AND author=?) ORDER BY n DESC LIMIT 1`);
    const check = () => {
      const row = latest.get(thread) as { n: number; author_kind: string; author: string } | undefined;
      const expected = row === undefined ? null : {
        n: row.n, authorKind: row.author_kind, author: row.author,
        other: row.author_kind !== "person" ? row.n : (different.get(thread, row.author)?.n ?? null),
      };
      assert.deepEqual(saidOf(read, thread), expected);
    };
    const put = (n: number, kind: string, authorKind: string, author: string, letter: string | null = null) => {
      insert.run(thread, n, kind, authorKind, author, `t${n}`, n, letter);
      check();
    };
    put(1, "message", "person", "a");
    put(2, "message", "person", "a");
    put(3, "message", "person", "b", "letter");
    put(4, "edit", "person", "b");
    put(5, "message", "person", "b");
    put(6, "message", "agent", "s");
    put(7, "message", "person", "a");
    put(8, "message", "person", "a");
    assert.deepEqual(saidOf(read, thread), { n: 8, authorKind: "person", author: "a", other: 6 });
    assert.equal(db.prepare("SELECT said_other_known FROM thread_state WHERE thread=?").get(thread)?.said_other_known, 1);

    // Old writers may insert out of order, replace by sequence or timestamp, ignore a conflict, or edit/delete a row.
    db.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES (?,8,'message','agent','x','ignored',8)`).run(thread);
    check();
    db.prepare(`INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES (?,5,'message','person','c','t7',5)`).run(thread);
    check();
    db.prepare("UPDATE entries SET author='b' WHERE thread=? AND n=8").run(thread);
    check();
    db.prepare("DELETE FROM entries WHERE thread=? AND n=8").run(thread);
    check();
    put(9, "message", "person", "b");
  } finally { store.close(); }
});
