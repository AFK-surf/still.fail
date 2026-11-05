import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";

test("naming a session's most recent chat does not traverse its older chats", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const latest = store.openThread("ember", "EMBER", "latest", null, null).id;
    store.joinThread(latest, "s", "ember");
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,1,'message','person','p',100)").run(latest);
    const add = (from: number, to: number) => {
      db.exec("BEGIN");
      for (let n = from; n <= to; n++) {
        const old = store.openThread("slack", "C", `old-${n}`, null, null).id;
        store.joinThread(old, "s", "slack");
      }
      db.exec("COMMIT");
    };
    let visits = 0, traced = false;
    db.function("visited_session_chat", (thread) => { visits++; return thread; });
    const proxy = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const marker = "WHERE m.session = ?";
          if (sql.includes("SELECT t.* FROM thread_sessions m JOIN threads t ON t.id = m.thread") && sql.includes(marker)) {
            const observed = sql.replace(marker, `${marker} AND visited_session_chat(m.thread)=m.thread`);
            const plan = (s: string) => target.prepare(`EXPLAIN QUERY PLAN ${s}`).all("s").map((r) => r.detail);
            assert.deepEqual(plan(observed), plan(sql), "counting keeps the actual query plan");
            traced = true;
            return target.prepare(observed);
          }
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    (store as any).db = proxy;
    const read = () => {
      visits = 0;
      assert.equal(store.sessionChat("s")?.thread.id, latest);
      return visits;
    };
    add(1, 40);
    const before = read();
    assert.ok(traced && before > 0, "the chat lookup's candidates are counted");
    add(41, 400);
    const after = read();
    assert.equal(after, before, `naming the chat visited ${before}, then ${after}, linked chats`);
  } finally { store.close(); }
});
