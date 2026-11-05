import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";

for (const delivered of [false, true]) {
  test(`finding the latest chat ${delivered ? "with a delivery" : "without deliveries"} does not traverse older memberships`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const current = store.openThread("ember", "EMBER", "current", null, null);
      store.joinThread(current.id, "s", "ember");
      db.prepare("UPDATE thread_sessions SET joined_at=100 WHERE thread=? AND session='s'").run(current.id);
      if (delivered) db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',1)").run(current.id);
      const add = (from: number, to: number) => {
        db.exec("BEGIN");
        for (let n = from; n <= to; n++) {
          const old = store.openThread("slack", "C", `old-${n}`, null, null);
          store.joinThread(old.id, "s", "slack");
          db.prepare("UPDATE thread_sessions SET joined_at=1 WHERE thread=? AND session='s'").run(old.id);
        }
        db.exec("COMMIT");
      };
      let visits = 0, traced = false;
      db.function("visited_latest_member", (thread) => { visits++; return thread; });
      const proxy = new Proxy(db, {
        get(target, property) {
          if (property === "prepare") return (sql: string) => {
            if (sql.includes("FROM thread_sessions ts JOIN threads t") && sql.includes("FROM deliveries d")) {
              const observed = sql.replace("WHERE ts.session = ?", "WHERE ts.session = ? AND visited_latest_member(ts.thread)=ts.thread");
              assert.notEqual(observed, sql);
              const plan = (text: string) => target.prepare(`EXPLAIN QUERY PLAN ${text}`).all("s").map((row) => row.detail);
              assert.deepEqual(plan(observed), plan(sql), "the counter preserves the actual query plan");
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
      const read = () => { visits = 0; assert.equal(store.latestThread("s")?.thread.id, current.id); return visits; };
      add(1, 40);
      const before = read();
      assert.ok(traced && before > 0);
      add(41, 400);
      const after = read();
      assert.equal(after, before, `finding the chat visited ${before}, then ${after}, memberships`);
    } finally { store.close(); }
  });
}
