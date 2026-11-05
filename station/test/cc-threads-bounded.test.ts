import assert from "node:assert/strict";
import { test } from "node:test";
import { CC_SESSION_KEYS, CcIndexPreparation, CcSessionsUnavailable } from "../src/store/cc-thread-index.ts";
import { Store } from "../src/store/store.ts";

function prepared(store: Store, thread: number): ReturnType<Store["ccThreads"]> {
  const work = new CcIndexPreparation();
  for (;;) {
    try { return store.ccThreads(thread); }
    catch (error) {
      if (!(error instanceof CcSessionsUnavailable)) throw error;
      for (const session of error.sessions) while (!work.step(store.db, session).done) {}
    }
  }
}

test("copy destinations keep shared membership and the last entry's order", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const home = store.openThread("ember", "EMBER", "home", null, null).id;
    store.joinThread(home, "a", "ember");
    store.joinThread(home, "b", "ember");
    const shared = store.openThread("slack:one", "C", "shared", null, null).id;
    const later = store.openThread("slack:one", "C", "later", null, null).id;
    const empty = store.openThread("slack:one", "C", "empty", null, null).id;
    const other = store.openThread("slack:one", "C", "other", null, null).id;
    store.joinThread(shared, "a", "a-slack"); store.joinThread(shared, "b", "b-slack");
    store.joinThread(later, "a", "a-slack"); store.joinThread(empty, "b", "b-slack");
    store.joinThread(other, "another", "other-slack");
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,at)
      VALUES(?,?,?,?,'person','viewer',?)`);
    put.run(shared, 1, "message", null, 20);
    put.run(later, 1, "message", null, 10);
    put.run(later, 2, "edit", 1, 30);
    put.run(other, 1, "message", null, 1_000);
    const read = () => prepared(store, home).map(({ thread, connect }) => [thread.id, connect]);
    assert.deepEqual(read(), [[later, "a-slack"], [shared, "a-slack"], [empty, "b-slack"]]);
    store.leaveThread(later, "a");
    assert.deepEqual(read(), [[later, "a-slack"], [shared, "a-slack"], [empty, "b-slack"]]);
    db.prepare("UPDATE entries SET at=5 WHERE thread=? AND n=2").run(later);
    assert.deepEqual(read(), [[shared, "a-slack"], [later, "a-slack"], [empty, "b-slack"]]);
    db.prepare("DELETE FROM thread_sessions WHERE thread=? AND session='a'").run(shared);
    assert.deepEqual(read(), [[shared, "b-slack"], [later, "a-slack"], [empty, "b-slack"]]);
  } finally { store.close(); }
});

test("shared copy destinations are counted once before the twenty most recent are chosen", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const home = store.openThread("ember", "EMBER", "home-many", null, null).id;
    store.joinThread(home, "a", "ember");
    store.joinThread(home, "b", "ember");
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at)
      VALUES(?,1,'message','person','viewer',?)`);
    const destinations = Array.from({ length: 25 }, (_, n) => {
      const id = store.openThread("slack:one", "C", `destination-${n}`, null, null).id;
      store.joinThread(id, "a", "slack");
      if (n >= 13) store.joinThread(id, "b", "slack");
      put.run(id, n + 1);
      return id;
    });
    assert.deepEqual(prepared(store, home).map(({ thread }) => thread.id), destinations.slice(5).reverse());
  } finally { store.close(); }
});

test("copy destinations with the same last entry time use creation time and thread id", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const home = store.openThread("ember", "EMBER", "home-ties", null, null).id;
    store.joinThread(home, "agent", "ember");
    const make = (name: string, created: number, at: number | null) => {
      const id = store.openThread("slack:one", "C", name, null, null).id;
      store.joinThread(id, "agent", "slack");
      db.prepare("UPDATE threads SET created_at=? WHERE id=?").run(created, id);
      if (at !== null) db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at)
        VALUES(?,1,'message','person','viewer',?)`).run(id, at);
      return id;
    };
    const first = make("first", 10, 5), second = make("second", 20, 5);
    const third = make("third", 20, 5), empty = make("empty", 30, null);
    assert.deepEqual(prepared(store, home).map(({ thread }) => thread.id), [third, second, first, empty]);
  } finally { store.close(); }
});

test("a chat's copy destinations do not traverse its older linked threads", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const home = store.openThread("ember", "EMBER", "home", null, null).id;
    store.joinThread(home, "agent", "ember");
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at)
      VALUES(?,1,'message','person','viewer',?)`);
    const add = (name: string, at: number) => {
      const thread = store.openThread("slack:one", "C", name, null, null).id;
      store.joinThread(thread, "agent", "slack");
      put.run(thread, at);
      return thread;
    };
    const recent = Array.from({ length: 20 }, (_, n) => add(`recent-${n}`, 100_000 + n)).reverse();
    for (let n = 0; n < 40; n++) add(`old-${n}`, n + 1);
    let visits = 0;
    db.function("visited_cc_candidate", (id) => { visits++; return id; });
    const sql = CC_SESSION_KEYS.replace("CAST(thread AS TEXT)", "visited_cc_candidate(thread)");
    assert.notEqual(sql, CC_SESSION_KEYS, "the per-session candidate lookup is observed");
    const read = () => db.prepare(sql).all("agent").map((row) => row.thread);
    assert.deepEqual(prepared(store, home).map((row) => row.thread.id), recent);
    assert.deepEqual(read(), recent);
    const before = visits;
    assert.ok(before > 0);
    for (let n = 40; n < 400; n++) add(`old-${n}`, n + 1);
    assert.deepEqual(prepared(store, home).map((row) => row.thread.id), recent);
    visits = 0;
    assert.deepEqual(read(), recent);
    assert.equal(visits, before, `copy destinations visited ${before} candidates, then ${visits}`);
  } finally { store.close(); }
});
