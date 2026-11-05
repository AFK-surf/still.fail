import assert from "node:assert/strict";
import { test } from "node:test";
import { POST_AFTER_INDEXED, Store } from "../src/store/store.ts";

test("finding a session's next post does not read unrelated chat history", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "chat", null, null).id;
    const put = db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, ts, at) VALUES (?, ?, 'message', ?, ?, ?, ?)");
    db.exec("BEGIN");
    for (let n = 1; n <= 5_000; n++) put.run(thread, n, n % 2 ? "person" : "agent", "someone-else", `m${n}`, n);
    db.exec("COMMIT");
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${POST_AFTER_INDEXED}`).all(thread, "wanted", 0, 0) as { detail: string }[];
    assert.ok(plan.some(({ detail }) => /SEARCH e USING INDEX .*thread=\? AND n>\? AND n<\?/.test(detail)), JSON.stringify(plan));

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
          } else if (sql.includes("WITH first(bucket)") && sql.includes("e.author_kind = 'agent'")) {
            traced = true;
            sql = sql.replaceAll("WHERE e.thread = ?1", "WHERE visit_post_entry(e.n) AND e.thread = ?1");
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

for (const recursive of [false, true]) test(`the indexed lookup agrees with the messages after replacements (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const threads = ["one", "two"].map((name) => store.openThread("ember", "CHAT", name, null, null).id);
    const put = db.prepare("INSERT OR REPLACE INTO entries (thread,n,kind,author_kind,author,ts,at) VALUES (?,?,?,?,?,?,?)");
    const remove = db.prepare("DELETE FROM entries WHERE thread=? AND n=?");
    const oracle = db.prepare("SELECT n,ts FROM entries WHERE thread=? AND n>? AND kind='message' AND author_kind='agent' AND author=? ORDER BY n LIMIT 1");
    let seed = 126_483;
    const random = (limit: number) => {
      seed = (Math.imul(seed, 1_664_525) + 1_013_904_223) >>> 0;
      return Math.floor(seed / 0x1_0000_0000 * limit);
    };
    for (let i = 0; i < 400; i++) {
      const thread = threads[random(threads.length)]!;
      const n = random(340) - 80;
      if (random(5) === 0) remove.run(thread, n);
      else put.run(thread, n, random(5) ? "message" : "edit", random(4) ? "agent" : "person", `s${random(3)}`, random(4) ? `t${random(180)}` : null, n);
      for (const which of threads) {
        const after = random(340) - 80;
        const author = `s${random(4)}`;
        const expected = oracle.get(which, after, author);
        assert.deepEqual(store.postAfter(author, which, after), expected ? { n: expected.n, ts: expected.ts } : null);
      }
    }
  } finally { store.close(); }
});
