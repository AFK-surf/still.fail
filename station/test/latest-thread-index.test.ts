import assert from "node:assert/strict";
import { test } from "node:test";
import { indexedLatestThread, installLatestThreadIndex, LATEST_THREAD_INDEXED, latestThreadReady, prepareLatestThreadStep } from "../src/store/latest-thread-index.ts";
import { Store } from "../src/store/store.ts";

function prepare(store: Store, session: string, limit = 16) {
  let visited = 0, batches = 0, done = false;
  while (!done) {
    const step = prepareLatestThreadStep(store.db, session, limit);
    assert.ok(step.visited <= limit);
    ({ done } = step); visited += step.visited; batches++;
  }
  return { visited, batches };
}

test("a prepared session finds the same latest delivery or last membership", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const one = store.openThread("ember", "EMBER", "one", null, null);
    const two = store.openThread("slack", "C", "two", null, null);
    const unjoined = store.openThread("slack", "C", "unjoined", null, null);
    store.joinThread(one.id, "s", "ember");
    store.joinThread(two.id, "s", "slack");
    store.joinThread(one.id, "without", "ember");
    store.joinThread(two.id, "without", "slack");
    db.prepare("UPDATE thread_sessions SET joined_at=10 WHERE session IN ('s','without')").run();
    db.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES(999999,'s','orphan',100)").run();
    const put = db.prepare("INSERT INTO deliveries(rowid,thread,n,session,delivered_at) VALUES(?,?,1,'s',NULL)");
    put.run(-2, one.id); put.run(-1, two.id); put.run(100, unjoined.id);
    installLatestThreadIndex(db);
    assert.throws(() => indexedLatestThread(db, "s"), /still being prepared/);
    assert.deepEqual(prepare(store, "s", 2), { visited: 3, batches: 2 });
    prepare(store, "without");
    prepare(store, "empty");
    for (const session of ["s", "without", "empty"]) {
      assert.equal(latestThreadReady(db, session), true);
      assert.equal(indexedLatestThread(db, session)?.id ?? null, store.latestThread(session)?.thread.id ?? null);
    }
    assert.equal(indexedLatestThread(db, "s")?.id, two.id, "negative delivery rowids still precede no delivery");
  } finally { store.close(); }
});

test("a prepared session reads one ordered candidate as old memberships grow", () => {
  const counts: number[] = [];
  for (const size of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec("BEGIN");
      for (let n = 0; n <= size; n++) {
        const thread = store.openThread("slack", "C", `chat-${n}`, null, null);
        store.joinThread(thread.id, "s", "slack");
      }
      db.exec("COMMIT");
      installLatestThreadIndex(db);
      assert.equal(prepare(store, "s").visited, size + 1);
      let visited = 0;
      db.function("latest_candidate_visited", (thread) => { visited++; return thread; });
      const observed = LATEST_THREAD_INDEXED.replace("WHERE r.session=?1", "WHERE r.session=?1 AND latest_candidate_visited(r.thread)=r.thread");
      const plan = (sql: string) => db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all("s").map((row) => String(row.detail));
      assert.deepEqual(plan(observed), plan(LATEST_THREAD_INDEXED));
      assert.match(plan(LATEST_THREAD_INDEXED).join("\n"), /SEARCH r USING PRIMARY KEY \(session=\?\)/);
      assert.doesNotMatch(plan(LATEST_THREAD_INDEXED).join("\n"), /TEMP B-TREE/);
      assert.equal(db.prepare(observed).get("s")?.id, store.latestThread("s")?.thread.id);
      counts.push(visited);
    } finally { store.close(); }
  }
  assert.deepEqual(counts, [1, 1]);
});

test("a prepared order follows deliveries, membership changes and missing threads", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const a = store.openThread("slack", "C", "a", null, null);
    const b = store.openThread("slack", "C", "b", null, null);
    const c = store.openThread("slack", "C", "c", null, null);
    store.joinThread(a.id, "s", "a");
    store.joinThread(b.id, "s", "b");
    installLatestThreadIndex(db);
    prepare(store, "s");
    const check = () => assert.equal(indexedLatestThread(db, "s")?.id ?? null, store.latestThread("s")?.thread.id ?? null);
    check();
    const add = db.prepare("INSERT INTO deliveries(rowid,thread,n,session,delivered_at) VALUES(?,?,1,'s',NULL)");
    add.run(100, a.id); check();
    add.run(101, b.id); check();
    db.prepare("DELETE FROM deliveries WHERE rowid=101").run(); check();
    store.joinThread(c.id, "s", "c"); check();
    add.run(102, c.id); check();
    db.prepare("DELETE FROM thread_sessions WHERE thread=? AND session='s'").run(c.id); check();
    db.prepare("DELETE FROM threads WHERE id=?").run(a.id); check();
    db.prepare("INSERT INTO threads(id,surface,channel,thread_ts,created_at) VALUES(?,'slack','C','a-restored',1)").run(a.id); check();
    db.prepare("UPDATE thread_sessions SET joined_at=1000 WHERE thread=? AND session='s'").run(b.id); check();
  } finally { store.close(); }
});

for (const recursive of [false, true]) for (const alias of ["rowid", "_rowid_", "oid"]) {
  test(`a prepared order follows ${alias} replacements and rollback (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? 1 : 0}`);
      const a = store.openThread("slack", "C", "a", null, null);
      const b = store.openThread("slack", "C", "b", null, null);
      store.joinThread(a.id, "s1", "a"); store.joinThread(b.id, "s1", "b");
      store.joinThread(a.id, "s2", "a"); store.joinThread(b.id, "s2", "b");
      const add = db.prepare("INSERT INTO deliveries(rowid,thread,n,session,delivered_at) VALUES(?,?,? ,?,NULL)");
      add.run(100, a.id, 1, "s1"); add.run(101, b.id, 1, "s2");
      installLatestThreadIndex(db); prepare(store, "s1"); prepare(store, "s2");
      const check = () => { for (const s of ["s1", "s2"])
        assert.equal(indexedLatestThread(db, s)?.id ?? null, store.latestThread(s)?.thread.id ?? null); };
      check();
      db.exec("BEGIN");
      db.prepare(`INSERT OR REPLACE INTO deliveries(${alias},thread,n,session,delivered_at) VALUES(100,?,2,'s2',NULL)`).run(a.id);
      check();
      db.exec("ROLLBACK");
      check();
      db.prepare(`INSERT OR REPLACE INTO deliveries(${alias},thread,n,session,delivered_at) VALUES(100,?,2,'s2',NULL)`).run(a.id);
      check();
      db.prepare("INSERT OR IGNORE INTO deliveries(thread,n,session,delivered_at) VALUES(?,2,'s2',NULL)").run(a.id);
      check();
      add.run(102, b.id, 2, "s1");
      check();
    } finally { store.close(); }
  });
}
