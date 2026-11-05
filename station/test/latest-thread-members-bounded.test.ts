import assert from "node:assert/strict";
import { test } from "node:test";
import { installLatestThreadIndex, prepareLatestThreadStep } from "../src/store/latest-thread-index.ts";
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
            if (sql.includes("FROM latest_thread_rows r")) {
              const observed = sql.replace("WHERE r.session=?1", "WHERE r.session=?1 AND visited_latest_member(r.thread)=r.thread");
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
      installLatestThreadIndex(db);
      while (!prepareLatestThreadStep(db, "s").done) { /* bounded batches */ }
      const before = read();
      assert.ok(traced && before > 0);
      add(41, 400);
      const after = read();
      assert.equal(after, before, `finding the chat visited ${before}, then ${after}, memberships`);
    } finally { store.close(); }
  });
}

test("a synchronous read requests old multi-chat preparation and keeps its immediate answer", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installLatestThreadIndex(db);
    const a = store.openThread("slack", "C", "a", null, null);
    const b = store.openThread("slack", "C", "b", null, null);
    const requested: string[] = [];
    (store as any).requestLatestThread = (session: string) => { requested.push(session); };
    store.joinThread(a.id, "s", "a");
    assert.equal(store.latestThread("s")?.thread.id, a.id);
    assert.deepEqual(requested, [], "one membership needs no prepared order");
    store.joinThread(b.id, "s", "b");
    db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',NULL)").run(a.id);
    assert.equal(store.latestThread("s")?.thread.id, a.id);
    assert.deepEqual(requested, ["s"]);
    while (!prepareLatestThreadStep(db, "s", 1).done) { /* bounded batches */ }
    db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',NULL)").run(b.id);
    assert.equal(store.latestThread("s")?.thread.id, b.id);
    assert.deepEqual(requested, ["s"], "a prepared order is read directly");
  } finally { store.close(); }
});
