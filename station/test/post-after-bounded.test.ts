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
    } finally {
      Object.defineProperty(store, "db", { value: db, configurable: true });
    }
  } finally { store.close(); }
});
