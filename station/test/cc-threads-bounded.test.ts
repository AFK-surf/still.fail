import assert from "node:assert/strict";
import { test } from "node:test";
import { CC_THREADS_SQL } from "../src/store/rows.ts";
import { Store } from "../src/store/store.ts";

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
    const read = () => store.ccThreads(home).map(({ thread, connect }) => [thread.id, connect]);
    assert.deepEqual(read(), [[later, "a-slack"], [shared, "a-slack"], [empty, "b-slack"]]);
    store.leaveThread(later, "a");
    assert.deepEqual(read(), [[later, "a-slack"], [shared, "a-slack"], [empty, "b-slack"]]);
    db.prepare("UPDATE entries SET at=5 WHERE thread=? AND n=2").run(later);
    assert.deepEqual(read(), [[shared, "a-slack"], [later, "a-slack"], [empty, "b-slack"]]);
    db.prepare("DELETE FROM thread_sessions WHERE thread=? AND session='a'").run(shared);
    assert.deepEqual(read(), [[shared, "b-slack"], [later, "a-slack"], [empty, "b-slack"]]);
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
    db.function("visited_cc_candidate", (_id) => { visits++; return 1; });
    const sql = CC_THREADS_SQL.replace("t.surface !=", "visited_cc_candidate(t.id) AND t.surface !=");
    assert.notEqual(sql, CC_THREADS_SQL, "the original candidate lookup is observed");
    const read = () => db.prepare(sql).all(home).map((row) => row.id);
    assert.deepEqual(read(), recent);
    const before = visits;
    assert.ok(before > 0);
    for (let n = 40; n < 400; n++) add(`old-${n}`, n + 1);
    visits = 0;
    assert.deepEqual(read(), recent);
    assert.equal(visits, before, `copy destinations visited ${before} candidates, then ${visits}`);
  } finally { store.close(); }
});
