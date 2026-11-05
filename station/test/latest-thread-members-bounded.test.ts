import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { installLatestThreadIndex, LATEST_THREAD_ATTEMPT, prepareLatestThreadStep } from "../src/store/latest-thread-index.ts";
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
      let visits = 0, smallVisits = 0, traced = false;
      db.function("visited_latest_member", (thread) => { visits++; return thread; });
      db.function("visited_small_member", (thread) => { smallVisits++; return thread; });
      const proxy = new Proxy(db, {
        get(target, property) {
          if (property === "prepare") return (sql: string) => {
            if (sql.includes("FROM latest_thread_rows r")) {
              const observed = sql.replace("WHERE r.session=?1", "WHERE r.session=?1 AND visited_latest_member(r.thread)=r.thread")
                .replace("SELECT thread FROM thread_sessions INDEXED BY thread_sessions_session",
                  "SELECT visited_small_member(thread) AS thread FROM thread_sessions INDEXED BY thread_sessions_session");
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
      const read = () => {
        visits = 0; smallVisits = 0;
        assert.equal(store.latestThread("s")?.thread.id, current.id);
        return [visits, smallVisits];
      };
      add(1, 40);
      installLatestThreadIndex(db);
      while (!prepareLatestThreadStep(db, "s").done) { /* bounded batches */ }
      const before = read();
      assert.ok(traced && before[0]! > 0);
      assert.equal(before[1], 2);
      add(41, 400);
      const after = read();
      assert.deepEqual(after, before, `finding the chat visited ${before}, then ${after}, memberships`);
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

test("a store refuses an incompatible latest-conversation index without preparing it", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const requested: string[] = [];
    store.requestLatestThread = (session) => { requested.push(session); };
    db.exec("UPDATE latest_thread_meta SET version=2 WHERE id=1");
    assert.throws(() => store.latestThread("s"), /latest thread index version 2 is incompatible/);
    assert.throws(() => prepareLatestThreadStep(db, "s"), /latest thread index version 2 is incompatible/);
    assert.deepEqual(requested, []);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM latest_thread_scopes").get()?.n, 0);
  } finally { store.close(); }
});

test("the single-chat check and its answer share a snapshot with another writer", () => {
  const dir = mkdtempSync(join(process.cwd(), ".latest-single-snapshot-")), path = join(dir, "station.db");
  const store = Store.open(path), db = store.db;
  let writer: DatabaseSync | undefined;
  try {
    const first = store.openThread("slack", "C", "first", null, null);
    const second = store.openThread("slack", "C", "second", null, null);
    store.joinThread(first.id, "s", "first");
    writer = new DatabaseSync(path);
    let interleaved = false;
    db.function("join_during_latest", (thread) => {
      if (!interleaved) {
        writer!.exec("BEGIN");
        writer!.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES(?,'s','second',2)").run(second.id);
        writer!.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',NULL)").run(second.id);
        writer!.exec("COMMIT");
        interleaved = true;
      }
      return thread;
    });
    const observed = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          if (sql !== LATEST_THREAD_ATTEMPT) return target.prepare(sql);
          const traced = sql.replace("SELECT thread FROM thread_sessions INDEXED BY thread_sessions_session",
            "SELECT join_during_latest(thread) AS thread FROM thread_sessions INDEXED BY thread_sessions_session");
          assert.notEqual(traced, sql);
          const plan = (query: string) => target.prepare(`EXPLAIN QUERY PLAN ${query}`).all("s").map((row) => row.detail);
          assert.deepEqual(plan(traced), plan(sql));
          return target.prepare(traced);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    Object.defineProperty(store, "db", { value: observed, configurable: true });
    assert.equal(store.latestThread("s")?.thread.id, first.id);
    assert.equal(interleaved, true);
    assert.equal(store.latestThread("s")?.thread.id, second.id);
  } finally {
    Object.defineProperty(store, "db", { value: db, configurable: true });
    writer?.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a prepared store read keeps its snapshot while a delivery changes the latest chat", () => {
  const dir = mkdtempSync(join(process.cwd(), ".latest-prepared-snapshot-")), path = join(dir, "station.db");
  const store = Store.open(path), db = store.db;
  let writer: DatabaseSync | undefined;
  try {
    const first = store.openThread("slack", "C", "first", null, null);
    const second = store.openThread("slack", "C", "second", null, null);
    store.joinThread(first.id, "s", "first"); store.joinThread(second.id, "s", "second");
    db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',NULL)").run(first.id);
    while (!prepareLatestThreadStep(db, "s").done) { /* bounded batches */ }
    writer = new DatabaseSync(path);
    let interleaved = false;
    db.function("deliver_during_latest", (thread) => {
      if (!interleaved) {
        writer!.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',NULL)").run(second.id);
        interleaved = true;
      }
      return thread;
    });
    const observed = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          if (sql !== LATEST_THREAD_ATTEMPT) return target.prepare(sql);
          const traced = sql.replace("SELECT thread FROM thread_sessions INDEXED BY thread_sessions_session",
            "SELECT deliver_during_latest(thread) AS thread FROM thread_sessions INDEXED BY thread_sessions_session");
          assert.notEqual(traced, sql);
          const plan = (query: string) => target.prepare(`EXPLAIN QUERY PLAN ${query}`).all("s").map((row) => row.detail);
          assert.deepEqual(plan(traced), plan(sql));
          return target.prepare(traced);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    Object.defineProperty(store, "db", { value: observed, configurable: true });
    assert.equal(store.latestThread("s")?.thread.id, first.id);
    assert.equal(interleaved, true);
    assert.equal(store.latestThread("s")?.thread.id, second.id);
  } finally {
    Object.defineProperty(store, "db", { value: db, configurable: true });
    writer?.close(); store.close(); rmSync(dir, { recursive: true, force: true });
  }
});
