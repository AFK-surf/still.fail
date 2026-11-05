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
