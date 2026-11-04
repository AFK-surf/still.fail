import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";

test("finding a session's next post does not read unrelated chat history", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "chat", null, null).id;
    const put = db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, ts, at) VALUES (?, ?, 'message', ?, ?, ?, ?)");
    db.exec("BEGIN");
    for (let n = 1; n <= 5_000; n++) put.run(thread, n, n % 2 ? "person" : "agent", "someone-else", `m${n}`, n);
    db.exec("COMMIT");

    // Count entries considered before their author is checked, including entries that do not match.
    let visited = 0;
    let traced = false;
    db.function("visit_post_entry", (_n) => { visited++; return 1; });
    const instrumented = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          if (sql.includes("FROM entries WHERE thread = ? AND n > ?") && sql.includes("author_kind = 'agent'")) {
            traced = true;
            sql = sql.replace("FROM entries WHERE thread = ?", "FROM entries WHERE visit_post_entry(n) AND thread = ?");
          } else if (sql.includes("CROSS JOIN entries e") && sql.includes("e.author_kind = 'agent'")) {
            traced = true;
            sql = sql.replace("WHERE e.thread = ?1", "WHERE visit_post_entry(e.n) AND e.thread = ?1");
          }
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    Object.defineProperty(store, "db", { value: instrumented, configurable: true });
    try {
      assert.equal(store.postAfter("wanted", thread, 0), null);
      assert.ok(traced, "the entries lookup was instrumented");
      assert.ok(visited <= 128, `an absent post should not scan the chat's other messages (visited ${visited})`);
      put.run(thread, 5_001, "agent", "wanted", "found", 5_001);
      db.prepare("UPDATE entries SET author = 'wanted' WHERE thread = ? AND n = 2").run(thread);
      visited = 0;
      assert.deepEqual(store.postAfter("wanted", thread, 2), { n: 5_001, ts: "found" });
      assert.ok(visited <= 128, `at most two numbered blocks are examined (visited ${visited})`);
      put.run(thread, 5_100, "agent", "wanted", null, 5_100);
      assert.deepEqual(store.postAfter("wanted", thread, 5_001), { n: 5_100, ts: null });
      put.run(thread, -65, "agent", "wanted", "negative-first", -65);
      put.run(thread, -1, "agent", "wanted", "negative-second", -1);
      assert.deepEqual(store.postAfter("wanted", thread, -66), { n: -65, ts: "negative-first" });
      assert.deepEqual(store.postAfter("wanted", thread, -65), { n: -1, ts: "negative-second" });
    } finally {
      Object.defineProperty(store, "db", { value: db, configurable: true });
    }
  } finally { store.close(); }
});
