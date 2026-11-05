import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";

function fixture() {
  const store = Store.open(":memory:");
  store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/s", token: "s", createdAt: 1, lastActiveAt: 1 });
  const thread = (name: string) => store.openThread("ember", "CHAT", name, null, null).id;
  return { store, thread };
}

test("a session's latest chat follows delivery order and falls back to its latest membership", () => {
  const { store, thread } = fixture();
  try {
    assert.equal(store.latestThread("s"), null);
    const first = thread("first"), second = thread("second"), unjoined = thread("unjoined");
    store.joinThread(first, "s", "first-connect");
    store.joinThread(second, "s", "second-connect");
    store.db.prepare("UPDATE thread_sessions SET joined_at = 1 WHERE session = 's'").run();
    // An orphan membership is ignored, even if it was joined most recently.
    store.db.prepare("INSERT INTO thread_sessions (thread, session, connect, joined_at) VALUES (999999, 's', 'missing', 999)").run();
    assert.equal(store.latestThread("s")?.thread.id, second);
    const put = store.db.prepare("INSERT INTO deliveries (rowid, thread, n, session, delivered_at) VALUES (?, ?, ?, ?, ?)");
    put.run(100, second, 1, "s", 10);
    put.run(101, first, 1, "s", null); // Pending deliveries count too, as before.
    put.run(102, unjoined, 1, "s", 10);
    put.run(103, first, 1, "other", 10);
    assert.equal(store.latestThread("s")?.thread.id, first);
    assert.equal(store.latestThread("s")?.connect, "first-connect");
    store.db.prepare("DELETE FROM deliveries WHERE rowid = 101").run();
    assert.equal(store.latestThread("s")?.thread.id, second);
    store.db.prepare("DELETE FROM deliveries WHERE rowid = 100").run();
    assert.equal(store.latestThread("s")?.thread.id, second);
  } finally { store.close(); }
});

test("finding the latest chat seeks one delivery per joined chat", () => {
  const { store, thread } = fixture();
  const db = store.db;
  try {
    const id = thread("long");
    store.joinThread(id, "s", "ember");
    const put = db.prepare("INSERT INTO deliveries (thread, n, session, delivered_at) VALUES (?, ?, 's', 1)");
    db.exec("BEGIN");
    for (let n = 1; n <= 5_000; n++) put.run(id, n);
    db.exec("COMMIT");
    let visited = 0;
    db.function("visit_latest_delivery", (_row) => { visited++; return 1; });
    const traced = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(
          sql.includes("ts.connect") && sql.includes("FROM deliveries d")
            ? sql.replace("WHERE d.session =", "WHERE visit_latest_delivery(d.rowid) AND d.session =")
            : sql,
        );
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    Object.defineProperty(store, "db", { value: traced, configurable: true });
    try {
      assert.equal(store.latestThread("s")?.thread.id, id);
      assert.ok(visited > 0 && visited <= 2, `the existing session and thread index seeks past old deliveries (visited ${visited})`);
    } finally { Object.defineProperty(store, "db", { value: db, configurable: true }); }
  } finally { store.close(); }
});

test("a session without deliveries finds its fallback without loading a list of memberships", () => {
  const { store, thread } = fixture();
  try {
    const id = thread("joined");
    store.joinThread(id, "s", "ember");
    store.sessionThreads = () => { throw new Error("enumerated all memberships"); };
    assert.equal(store.latestThread("s")?.thread.id, id);
    assert.equal(store.latestThread("missing"), null);
  } finally { store.close(); }
});
