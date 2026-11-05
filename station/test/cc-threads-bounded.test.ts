import assert from "node:assert/strict";
import { test } from "node:test";
import { CC_THREADS_SQL } from "../src/store/rows.ts";
import { Store } from "../src/store/store.ts";

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
