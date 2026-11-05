import assert from "node:assert/strict";
import { test } from "node:test";
import { DatabaseSync } from "node:sqlite";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Store } from "../src/store/store.ts";
import { CC_THREADS_SQL } from "../src/store/rows.ts";
import {
  CC_SESSION_ROWS, CcIndexPreparation, CcSessionsUnavailable, ccSessionReady, ccSessionRows, dispatchCcOrderStep, indexedCcThreads, installCcIndex,
  scanCcSessionStep, settleCcSessionStep, trackCcSession,
} from "../src/store/cc-thread-index.ts";

function finish(db: DatabaseSync, session: string, size = 4): void {
  for (let n = 0; n < 1_000 && !ccSessionReady(db, session); n++) {
    scanCcSessionStep(db, session, size);
    dispatchCcOrderStep(db, size);
    settleCcSessionStep(db, session);
  }
  assert.equal(ccSessionReady(db, session), true, "the requested session can be prepared");
}

function put(db: DatabaseSync, thread: number, n: number, at: number): void {
  db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at)
    VALUES(?,?,'message','person','viewer',?)`).run(thread, n, at);
}

test("a requested session's copy destinations are prepared in batches and stay current across older writes", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const ids = Array.from({ length: 12 }, (_, i) => {
      const id = store.openThread("slack:one", "C", `target-${i}`, null, null).id;
      store.joinThread(id, "agent", "slack");
      put(db, id, 1, i + 1);
      return id;
    });
    installCcIndex(db);
    trackCcSession(db, "agent");
    assert.equal(ccSessionReady(db, "agent"), false);
    assert.ok(scanCcSessionStep(db, "agent", 3).visited <= 3);
    // This older writer touches a member already passed by the scan and adds one after the saved boundary.
    put(db, ids[0]!, 2, 100);
    const added = store.openThread("slack:one", "C", "added", null, null).id;
    store.joinThread(added, "agent", "slack");
    put(db, added, 1, 200);
    finish(db, "agent", 3);
    assert.deepEqual(ccSessionRows(db, "agent", 3).map((r) => r.thread), [added, ids[0], ids[11]]);
    assert.equal(ccSessionReady(db, "another"), false);
  } finally { store.close(); }
});

test("a shared destination changed during distribution leaves every requested session up to date", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const shared = store.openThread("slack:one", "C", "shared", null, null).id;
    const other = store.openThread("slack:one", "C", "other", null, null).id;
    for (const session of ["a", "b", "c"]) {
      store.joinThread(shared, session, "slack");
      store.joinThread(other, session, "slack");
    }
    put(db, shared, 1, 10); put(db, other, 1, 20);
    installCcIndex(db);
    for (const session of ["a", "b", "c"]) { trackCcSession(db, session); finish(db, session); }
    put(db, shared, 2, 30);
    assert.ok(dispatchCcOrderStep(db, 1).visited <= 1);
    assert.equal(ccSessionReady(db, "a"), false);
    // The dispatch has already visited one member; changing the same thread must not lose it or restart forever.
    put(db, shared, 3, 40);
    store.joinThread(shared, "0", "slack");
    trackCcSession(db, "0");
    for (const session of ["0", "a", "b", "c"]) finish(db, session, 1);
    for (const session of ["0", "a", "b", "c"])
      assert.equal(ccSessionRows(db, session, 1)[0]?.thread, shared);
  } finally { store.close(); }
});

test("newly requested sessions cannot extend an in-progress distribution forever", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const shared = store.openThread("slack:one", "C", "growing", null, null).id;
    for (const session of ["a", "b"]) store.joinThread(shared, session, "slack");
    put(db, shared, 1, 10);
    installCcIndex(db);
    for (const session of ["a", "b"]) { trackCcSession(db, session); finish(db, session); }
    put(db, shared, 2, 20);
    assert.equal(dispatchCcOrderStep(db, 1).done, false);
    const added: string[] = [];
    let done = false;
    for (let n = 0; n < 4 && !done; n++) {
      const session = `z${n}`;
      added.push(session); store.joinThread(shared, session, "slack");
      trackCcSession(db, session); scanCcSessionStep(db, session, 1);
      done = dispatchCcOrderStep(db, 1).done;
    }
    assert.equal(done, true, "the distribution has a finite membership boundary");
    for (const session of ["a", "b", ...added]) {
      finish(db, session, 1);
      assert.equal(ccSessionRows(db, session, 1)[0]?.thread, shared);
    }
  } finally { store.close(); }
});

test("a destination's surface, time, membership and removal are reflected after preparation", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const first = store.openThread("slack:one", "C", "first", null, null).id;
    const second = store.openThread("slack:one", "C", "second", null, null).id;
    store.joinThread(first, "agent", "slack"); store.joinThread(second, "agent", "slack");
    put(db, first, 1, 10); put(db, second, 1, 20);
    installCcIndex(db); trackCcSession(db, "agent"); finish(db, "agent");
    assert.deepEqual(ccSessionRows(db, "agent", 20).map((r) => r.thread), [second, first]);
    db.prepare("UPDATE entries SET at=30 WHERE thread=? AND n=1").run(first);
    assert.equal(ccSessionReady(db, "agent"), false);
    finish(db, "agent");
    assert.deepEqual(ccSessionRows(db, "agent", 20).map((r) => r.thread), [first, second]);
    db.prepare("UPDATE threads SET surface='ember' WHERE id=?").run(first);
    db.prepare("DELETE FROM thread_sessions WHERE thread=? AND session=?").run(second, "agent");
    finish(db, "agent");
    assert.deepEqual(ccSessionRows(db, "agent", 20), []);
  } finally { store.close(); }
});

test("merging a source chat's session candidates preserves its original twenty destinations and connects", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const home = store.openThread("ember", "EMBER", "multi", null, null).id;
    store.joinThread(home, "b", "ember"); store.joinThread(home, "a", "ember");
    for (let n = 0; n < 35; n++) {
      const id = store.openThread("slack:one", "C", `target-${n}`, null, null).id;
      if (n % 3 !== 0) store.joinThread(id, "b", "b-slack");
      if (n % 3 !== 1) store.joinThread(id, "a", "a-slack");
      put(db, id, 1, n % 7);
    }
    installCcIndex(db); trackCcSession(db, "a"); finish(db, "a");
    assert.throws(() => indexedCcThreads(db, home), (error: unknown) =>
      error instanceof CcSessionsUnavailable && error.sessions.length === 1 && error.sessions[0] === "b");
    trackCcSession(db, "b"); finish(db, "b");
    const before = db.prepare(CC_THREADS_SQL).all(home).map((r) => ({ id: r.id, connect: r.connect }));
    const after = indexedCcThreads(db, home).map((r) => ({ id: r.id, connect: r.connect }));
    assert.deepEqual(after, before);
    assert.equal(after.length, 20);
  } finally { store.close(); }
});

test("merged copy destinations keep SQLite's ordering of old non-integer entry times", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const home = store.openThread("ember", "EMBER", "old-times", null, null).id;
    store.joinThread(home, "a", "ember"); store.joinThread(home, "b", "ember");
    for (const [n, at] of [1, 5.5, "old", null].entries()) {
      const id = store.openThread("slack:one", "C", `old-${n}`, null, null).id;
      store.joinThread(id, n % 2 ? "a" : "b", "slack");
      if (at !== null) db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at)
        VALUES(?,1,'message','person','viewer',?)`).run(id, at);
    }
    installCcIndex(db);
    for (const session of ["a", "b"]) { trackCcSession(db, session); finish(db, session); }
    assert.deepEqual(indexedCcThreads(db, home).map((r) => r.id), db.prepare(CC_THREADS_SQL).all(home).map((r) => r.id));
  } finally { store.close(); }
});

for (const recursive of [false, true]) {
  for (const alias of ["rowid", "_rowid_", "oid"]) test(`copy destination rows agree after ${alias} replacements and rollback (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      const home = store.openThread("ember", "EMBER", "home", null, null).id;
      store.joinThread(home, "agent", "ember");
      const ids = Array.from({ length: 6 }, (_, n) => {
        const id = store.openThread("slack:one", "C", `target-${n}`, null, null).id;
        store.joinThread(id, "agent", "slack"); put(db, id, 1, n + 1); return id;
      });
      installCcIndex(db); trackCcSession(db, "agent"); finish(db, "agent");
      const matches = () => {
        finish(db, "agent");
        assert.deepEqual(ccSessionRows(db, "agent", 20).map((r) => r.thread),
          store.ccThreads(home).map((r) => r.thread.id));
      };
      matches();
      db.exec("BEGIN");
      db.prepare("UPDATE entries SET at=1000 WHERE thread=? AND n=1").run(ids[0]);
      assert.equal(ccSessionReady(db, "agent"), false);
      db.exec("ROLLBACK");
      assert.equal(ccSessionReady(db, "agent"), true);
      matches();
      const member = db.prepare("SELECT rowid FROM thread_sessions WHERE thread=? AND session='agent'").get(ids[0]) as { rowid: number };
      db.prepare(`INSERT OR REPLACE INTO thread_sessions(${alias},thread,session,connect,joined_at)
        VALUES(?,?,'another','slack',1)`).run(member.rowid, ids[1]);
      matches();
      const entry = db.prepare("SELECT rowid FROM entries WHERE thread=? AND n=1").get(ids[2]) as { rowid: number };
      db.prepare(`INSERT OR REPLACE INTO entries(${alias},thread,n,kind,author_kind,author,at)
        VALUES(?,?,2,'message','person','viewer',100)`).run(entry.rowid, ids[3]);
      matches();
      const displacedMember = db.prepare("SELECT rowid FROM thread_sessions WHERE thread=? AND session='agent'")
        .get(ids[3]) as { rowid: number };
      db.prepare(`UPDATE OR REPLACE thread_sessions SET ${alias}=? WHERE thread=? AND session='agent'`)
        .run(displacedMember.rowid, ids[2]);
      matches();
      const displacedEntry = db.prepare("SELECT rowid FROM entries WHERE thread=? AND n=1").get(ids[4]) as { rowid: number };
      db.prepare(`UPDATE OR REPLACE entries SET ${alias}=? WHERE thread=? AND n=1`)
        .run(displacedEntry.rowid, ids[5]);
      matches();
      db.prepare("UPDATE threads SET surface='ember' WHERE id=?").run(ids[4]);
      matches();
      db.prepare(`INSERT OR REPLACE INTO threads(surface,channel,thread_ts,created_at)
        VALUES('slack:one','C','target-5',200)`).run();
      matches();
    } finally { store.close(); }
  });
}

test("a prepared session seeks its newest destinations independently of older ones", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const add = (name: string, at: number) => {
      const id = store.openThread("slack:one", "C", name, null, null).id;
      store.joinThread(id, "agent", "slack"); put(db, id, 1, at); return id;
    };
    const newest = Array.from({ length: 20 }, (_, n) => add(`new-${n}`, 1_000 + n)).reverse();
    for (let n = 0; n < 40; n++) add(`old-${n}`, n);
    installCcIndex(db); trackCcSession(db, "agent"); finish(db, "agent");
    let visited = 0;
    db.function("visited_cc_row", (id) => { visited++; return id; });
    const observed = CC_SESSION_ROWS.replace("SELECT thread,", "SELECT visited_cc_row(thread) AS thread,");
    assert.notEqual(observed, CC_SESSION_ROWS);
    const read = () => db.prepare(observed).all("agent", 20).map((r) => r.thread);
    assert.deepEqual(read(), newest);
    const before = visited;
    for (let n = 40; n < 400; n++) add(`old-${n}`, n);
    finish(db, "agent"); visited = 0;
    assert.deepEqual(read(), newest);
    assert.equal(visited, before);
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${CC_SESSION_ROWS}`).all("agent", 20).map((r) => String(r.detail));
    assert.ok(plan.some((line) => line.includes("cc_session_order")), plan.join("\n"));
    assert.ok(!plan.some((line) => line.includes("TEMP B-TREE")), plan.join("\n"));
  } finally { store.close(); }
});

test("a shared destination's writes queue one bounded distribution", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const shared = store.openThread("slack:one", "C", "many", null, null).id;
    for (let n = 0; n < 40; n++) store.joinThread(shared, `agent-${n}`, "slack");
    put(db, shared, 1, 1);
    installCcIndex(db);
    for (let n = 0; n < 40; n++) { const key = `agent-${n}`; trackCcSession(db, key); finish(db, key); }
    put(db, shared, 2, 2); put(db, shared, 3, 3);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM cc_order_dispatch").get() as { n: number }).n, 1);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM cc_session_dirty").get() as { n: number }).n, 0);
    assert.deepEqual(dispatchCcOrderStep(db, 3), { done: false, visited: 3 });
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM cc_session_dirty").get() as { n: number }).n, 3);
  } finally { store.close(); }
});

test("a short copy destination request finishes while a longer session is prepared", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    for (let n = 0; n < 30; n++) {
      const id = store.openThread("slack:one", "C", `long-${n}`, null, null).id;
      store.joinThread(id, "long", "slack"); put(db, id, 1, n);
    }
    const short = store.openThread("slack:one", "C", "short", null, null).id;
    store.joinThread(short, "short", "slack"); put(db, short, 1, 100);
    installCcIndex(db);
    const prep = new CcIndexPreparation();
    let shortDone = false;
    for (let n = 0; n < 6 && !shortDone; n++) {
      assert.ok(prep.step(db, "long", 2).visited <= 2);
      const result = prep.step(db, "short", 2);
      assert.ok(result.visited <= 2); shortDone = result.done;
    }
    assert.equal(shortDone, true);
    assert.equal(ccSessionReady(db, "long"), false);
    assert.equal(ccSessionRows(db, "short", 1)[0]?.thread, short);
  } finally { store.close(); }
});

test("an incompatible copy destination index is neither read nor prepared", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installCcIndex(db);
    db.prepare("UPDATE cc_index_meta SET version=2 WHERE id=1").run();
    assert.throws(() => trackCcSession(db, "agent"), /incompatible/);
    assert.throws(() => ccSessionReady(db, "agent"), /incompatible/);
    assert.throws(() => dispatchCcOrderStep(db), /incompatible/);
  } finally { store.close(); }
});

test("another writer cannot be missed during preparation or between readiness and a read", () => {
  const dir = mkdtempSync(join(tmpdir(), "cc-index-")), store = Store.open(join(dir, "station.db")), db = store.db;
  let other: DatabaseSync | null = null;
  try {
    const ids = Array.from({ length: 6 }, (_, n) => {
      const id = store.openThread("slack:one", "C", `target-${n}`, null, null).id;
      store.joinThread(id, "agent", "slack"); put(db, id, 1, n); return id;
    });
    installCcIndex(db); trackCcSession(db, "agent");
    assert.equal(scanCcSessionStep(db, "agent", 2).done, false);
    other = new DatabaseSync(join(dir, "station.db"));
    put(other, ids[0]!, 2, 100);
    finish(db, "agent", 2);
    assert.equal(ccSessionRows(db, "agent", 1)[0]?.thread, ids[0]);
    db.exec("BEGIN");
    assert.equal(ccSessionReady(db, "agent"), true);
    put(other, ids[1]!, 2, 200);
    // The read still sees the state in which readiness was checked.
    assert.equal(ccSessionRows(db, "agent", 1)[0]?.thread, ids[0]);
    db.exec("COMMIT");
    assert.equal(ccSessionReady(db, "agent"), false);
    finish(db, "agent", 2);
    assert.equal(ccSessionRows(db, "agent", 1)[0]?.thread, ids[1]);
  } finally { other?.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
