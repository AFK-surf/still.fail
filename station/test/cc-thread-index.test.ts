import assert from "node:assert/strict";
import { test } from "node:test";
import type { DatabaseSync } from "node:sqlite";
import { Store } from "../src/store/store.ts";
import {
  ccSessionReady, ccSessionRows, dispatchCcOrderStep, installCcIndex,
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
