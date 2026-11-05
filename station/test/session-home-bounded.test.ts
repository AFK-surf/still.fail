import assert from "node:assert/strict";
import { test } from "node:test";
import { sessionThreadOf } from "../src/sessions/others.ts";
import { SESSION_HOME_THREAD, Store } from "../src/store/store.ts";

test("finding a session's own conversation does not traverse its other memberships", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const own = store.openThreadOf("ember", "EMBER", "own", null, null, "s");
    store.joinThread(own.id, "s", "ember");
    const add = (from: number, to: number) => {
      db.exec("BEGIN");
      for (let n = from; n <= to; n++) {
        const other = store.openThread("slack", "C", `old-${n}`, null, null);
        store.joinThread(other.id, "s", "slack");
      }
      db.exec("COMMIT");
    };
    let visits = 0, traced = false;
    db.function("visited_session_home", (thread) => { visits++; return thread; });
    const proxy = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          let observed = sql;
          if (sql.includes("FROM thread_sessions ts JOIN threads t") && sql.includes("ORDER BY ts.joined_at DESC")) {
            observed = sql.replace("WHERE ts.session = ?", "WHERE ts.session = ? AND visited_session_home(ts.thread)=ts.thread");
          } else if (sql.includes("threads_home") && sql.includes("ts.connect")) {
            observed = sql.replace("t.home = ?1", "t.home = ?1 AND visited_session_home(t.id)=t.id");
          }
          if (observed !== sql) {
            const plan = (text: string) => target.prepare(`EXPLAIN QUERY PLAN ${text}`).all("s").map((row) => row.detail);
            assert.deepEqual(plan(observed), plan(sql));
            traced = true;
          }
          return target.prepare(observed);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    (store as any).db = proxy;
    const read = () => { visits = 0; assert.equal(sessionThreadOf({ store } as any, "s").thread.id, own.id); return visits; };
    add(1, 40);
    const before = read();
    assert.ok(traced && before > 0);
    add(41, 400);
    const after = read();
    assert.equal(after, before, `finding the owned chat read ${before}, then ${after}, candidates`);
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${SESSION_HOME_THREAD}`).all("s").map((row) => String(row.detail)).join("\n");
    assert.match(plan, /SEARCH t USING INDEX threads_home \(home=\?\)/);
    assert.match(plan, /SEARCH ts USING INDEX sqlite_autoindex_thread_sessions_1 \(thread=\? AND session=\?\)/);
  } finally { store.close(); }
});

test("an owned conversation must be joined and keeps the most recent membership order", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const one = store.openThreadOf("ember", "EMBER", "one", null, null, "s");
    const two = store.openThreadOf("ember", "EMBER", "two", null, null, "s");
    const absent = store.openThreadOf("ember", "EMBER", "absent", null, null, "s");
    const other = store.openThread("slack", "C", "other", null, null);
    store.joinThread(one.id, "s", "first");
    store.joinThread(two.id, "s", "second");
    store.joinThread(other.id, "s", "other");
    db.prepare("UPDATE thread_sessions SET joined_at=10 WHERE session='s'").run();
    assert.equal(sessionThreadOf({ store } as any, "s").thread.id, two.id, "rowid breaks an equal-time tie");
    assert.equal(sessionThreadOf({ store } as any, "s").connect, "second");
    db.prepare("UPDATE thread_sessions SET joined_at=11 WHERE thread=? AND session='s'").run(one.id);
    assert.equal(sessionThreadOf({ store } as any, "s").thread.id, one.id);
    db.prepare("DELETE FROM thread_sessions WHERE session='s' AND thread IN (?,?)").run(one.id, two.id);
    assert.notEqual(absent.id, other.id);
    assert.equal(sessionThreadOf({ store } as any, "s").thread.id, other.id, "an unjoined owned chat is not selected");
    db.prepare("DELETE FROM thread_sessions WHERE session='s'").run();
    assert.throws(() => sessionThreadOf({ store } as any, "s"), /no conversation yet/);
  } finally { store.close(); }
});
