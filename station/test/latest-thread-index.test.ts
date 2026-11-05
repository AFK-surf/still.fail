import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { join } from "node:path";
import { test } from "node:test";
import { indexedLatestThread, installLatestThreadIndex, LATEST_THREAD_INDEXED, LATEST_THREAD_REFRESH_UPDATING, latestThreadReady, prepareLatestThreadStep } from "../src/store/latest-thread-index.ts";
import { Store } from "../src/store/store.ts";

function prepare(store: Store, session: string, limit = 16) {
  let visited = 0, batches = 0, done = false;
  while (!done) {
    const step = prepareLatestThreadStep(store.db, session, limit);
    assert.ok(step.visited <= limit);
    ({ done } = step); visited += step.visited; batches++;
  }
  return { visited, batches };
}

// Keep the original query as the oracle even after Store.latestThread is switched to the prepared order.
function originalLatestId(db: DatabaseSync, session: string): number | null {
  const row = db.prepare(`SELECT t.id FROM thread_sessions ts JOIN threads t ON t.id=ts.thread WHERE ts.session=?
    ORDER BY (SELECT d.rowid FROM deliveries d INDEXED BY deliveries_session
      WHERE d.session=ts.session AND d.thread=ts.thread ORDER BY d.rowid DESC LIMIT 1) DESC,
    ts.joined_at DESC,ts.rowid DESC LIMIT 1`).get(session);
  return row ? Number(row.id) : null;
}

test("a prepared session finds the same latest delivery or last membership", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const one = store.openThread("ember", "EMBER", "one", null, null);
    const two = store.openThread("slack", "C", "two", null, null);
    const unjoined = store.openThread("slack", "C", "unjoined", null, null);
    store.joinThread(one.id, "s", "ember");
    store.joinThread(two.id, "s", "slack");
    store.joinThread(one.id, "without", "ember");
    store.joinThread(two.id, "without", "slack");
    db.prepare("UPDATE thread_sessions SET joined_at=10 WHERE session IN ('s','without')").run();
    db.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES(999999,'s','orphan',100)").run();
    const put = db.prepare("INSERT INTO deliveries(rowid,thread,n,session,delivered_at) VALUES(?,?,1,'s',NULL)");
    put.run(-2, one.id); put.run(-1, two.id); put.run(100, unjoined.id);
    installLatestThreadIndex(db);
    assert.throws(() => indexedLatestThread(db, "s"), /still being prepared/);
    assert.deepEqual(prepare(store, "s", 2), { visited: 3, batches: 2 });
    prepare(store, "without");
    prepare(store, "empty");
    for (const session of ["s", "without", "empty"]) {
      assert.equal(latestThreadReady(db, session), true);
      assert.equal(indexedLatestThread(db, session)?.id ?? null, originalLatestId(db, session));
    }
    assert.equal(indexedLatestThread(db, "s")?.id, two.id, "negative delivery rowids still precede no delivery");
  } finally { store.close(); }
});

test("a prepared session reads one ordered candidate as old memberships grow", () => {
  const counts: number[] = [];
  for (const size of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec("BEGIN");
      for (let n = 0; n <= size; n++) {
        const thread = store.openThread("slack", "C", `chat-${n}`, null, null);
        store.joinThread(thread.id, "s", "slack");
      }
      db.exec("COMMIT");
      installLatestThreadIndex(db);
      assert.equal(prepare(store, "s").visited, size + 1);
      let visited = 0;
      db.function("latest_candidate_visited", (thread) => { visited++; return thread; });
      const observed = LATEST_THREAD_INDEXED.replace("WHERE r.session=?1", "WHERE r.session=?1 AND latest_candidate_visited(r.thread)=r.thread");
      const plan = (sql: string) => db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all("s").map((row) => String(row.detail));
      assert.deepEqual(plan(observed), plan(LATEST_THREAD_INDEXED));
      assert.match(plan(LATEST_THREAD_INDEXED).join("\n"), /SEARCH r USING PRIMARY KEY \(session=\?\)/);
      assert.doesNotMatch(plan(LATEST_THREAD_INDEXED).join("\n"), /TEMP B-TREE/);
      assert.equal(db.prepare(observed).get("s")?.id, originalLatestId(db, "s"));
      counts.push(visited);
    } finally { store.close(); }
  }
  assert.deepEqual(counts, [1, 1]);
});

test("a prepared order follows deliveries, membership changes and missing threads", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const a = store.openThread("slack", "C", "a", null, null);
    const b = store.openThread("slack", "C", "b", null, null);
    const c = store.openThread("slack", "C", "c", null, null);
    store.joinThread(a.id, "s", "a");
    store.joinThread(b.id, "s", "b");
    installLatestThreadIndex(db);
    prepare(store, "s");
    const check = () => assert.equal(indexedLatestThread(db, "s")?.id ?? null, originalLatestId(db, "s"));
    check();
    const add = db.prepare("INSERT INTO deliveries(rowid,thread,n,session,delivered_at) VALUES(?,?,1,'s',NULL)");
    add.run(100, a.id); check();
    add.run(101, b.id); check();
    db.prepare("DELETE FROM deliveries WHERE rowid=101").run(); check();
    store.joinThread(c.id, "s", "c"); check();
    add.run(102, c.id); check();
    db.prepare("DELETE FROM thread_sessions WHERE thread=? AND session='s'").run(c.id); check();
    db.prepare("DELETE FROM threads WHERE id=?").run(a.id); check();
    db.prepare("INSERT INTO threads(id,surface,channel,thread_ts,created_at) VALUES(?,'slack','C','a-restored',1)").run(a.id); check();
    db.prepare("UPDATE thread_sessions SET joined_at=1000 WHERE thread=? AND session='s'").run(b.id); check();
  } finally { store.close(); }
});

test("a membership replaced behind an old-session cursor is not missed", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const members: number[] = [];
    db.exec("BEGIN");
    for (let n = 0; n < 40; n++) {
      const thread = store.openThread("slack", "C", `old-${n}`, null, null);
      store.joinThread(thread.id, "s", "slack"); members.push(thread.id);
    }
    db.exec("COMMIT");
    const first = db.prepare("SELECT rowid FROM thread_sessions WHERE session='s' AND thread=?").get(members[0]!)!.rowid;
    const replacement = store.openThread("slack", "C", "replacement", null, null);
    installLatestThreadIndex(db);
    assert.deepEqual(prepareLatestThreadStep(db, "s", 8), { done: false, visited: 8 });
    db.prepare("INSERT OR REPLACE INTO thread_sessions(rowid,thread,session,connect,joined_at) VALUES(?,?,'s','new',10000)")
      .run(first, replacement.id);
    db.prepare("INSERT INTO deliveries(rowid,thread,n,session,delivered_at) VALUES(500,?,1,'s',NULL)").run(replacement.id);
    prepare(store, "s", 8);
    assert.equal(indexedLatestThread(db, "s")?.id, replacement.id);
    assert.equal(indexedLatestThread(db, "s")?.id, originalLatestId(db, "s"));
    const actual = db.prepare("SELECT member_rowid,thread FROM latest_thread_rows WHERE session='s' ORDER BY member_rowid").all();
    const expected = db.prepare("SELECT m.rowid AS member_rowid,m.thread FROM thread_sessions m JOIN threads t ON t.id=m.thread WHERE m.session='s' ORDER BY m.rowid").all();
    assert.deepEqual(actual, expected);
  } finally { store.close(); }
});

test("a delivery ahead of the preparation cursor follows a missing and restored thread", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const a = store.openThread("slack", "C", "a", null, null);
    const b = store.openThread("slack", "C", "b", null, null);
    store.joinThread(a.id, "s", "a"); store.joinThread(b.id, "s", "b");
    const put = db.prepare("INSERT INTO deliveries(rowid,thread,n,session,delivered_at) VALUES(?,?,1,'s',NULL)");
    put.run(50, a.id);
    installLatestThreadIndex(db);
    assert.deepEqual(prepareLatestThreadStep(db, "s", 1), { done: false, visited: 1 });
    put.run(100, b.id);
    db.prepare("DELETE FROM threads WHERE id=?").run(b.id);
    db.prepare("DELETE FROM deliveries WHERE rowid=100").run();
    put.run(10, b.id);
    prepare(store, "s", 1);
    db.prepare("INSERT INTO threads(id,surface,channel,thread_ts,created_at) VALUES(?,'slack','C','restored',1)").run(b.id);
    assert.equal(indexedLatestThread(db, "s")?.id, originalLatestId(db, "s"));
    assert.equal(indexedLatestThread(db, "s")?.id, a.id);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM latest_thread_rows WHERE session='s' AND thread=?").get(b.id)?.n, 1);
  } finally { store.close(); }
});

test("readiness and the selected conversation share a snapshot with another writer", () => {
  const dir = mkdtempSync(join(process.cwd(), ".latest-thread-snapshot-")), path = join(dir, "station.db");
  const store = Store.open(path), db = store.db;
  let writer: DatabaseSync | undefined;
  try {
    const a = store.openThread("slack", "C", "a", null, null);
    const b = store.openThread("slack", "C", "b", null, null);
    store.joinThread(a.id, "s", "a"); store.joinThread(b.id, "s", "b");
    db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',NULL)").run(a.id);
    installLatestThreadIndex(db); prepare(store, "s");
    writer = new DatabaseSync(path);
    let interleaved = false;
    const observed = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const statement = target.prepare(sql);
          if (!sql.startsWith("SELECT complete FROM latest_thread_scopes")) return statement;
          return new Proxy(statement, {
            get(s, p) {
              if (p === "get") return (...args: any[]) => {
                const row = s.get(...args);
                writer!.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',NULL)").run(b.id);
                interleaved = true;
                return row;
              };
              const value = Reflect.get(s, p, s);
              return typeof value === "function" ? value.bind(s) : value;
            },
          });
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    assert.equal(indexedLatestThread(observed, "s")?.id, a.id);
    assert.equal(interleaved, true);
    assert.equal(indexedLatestThread(db, "s")?.id, b.id);
    assert.equal(originalLatestId(db, "s"), b.id);
  } finally { writer?.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a changed thread does not inspect memberships of unprepared sessions", () => {
  const counts: number[] = [];
  for (const others of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("slack", "C", "shared", null, null);
      store.joinThread(thread.id, "tracked", "slack");
      db.exec("BEGIN");
      for (let n = 0; n < others; n++) store.joinThread(thread.id, `other-${n}`, "slack");
      db.exec("COMMIT");
      let visited = 0, instrumented = 0;
      db.function("latest_thread_member_visited", (session) => { visited++; return session; });
      const tables = ["thread_sessions", "latest_thread_members"];
      // Store.open installs the real triggers. Recreate their thread-membership selects with the counter, preserving
      // their query plan, rather than relying on a second installation that now correctly does nothing.
      const triggers = db.prepare("SELECT name,sql FROM sqlite_master WHERE type='trigger' AND name LIKE 'latest_thread_%'").all() as { name: string; sql: string }[];
      for (const trigger of triggers) {
        let sql = trigger.sql;
        for (const table of tables) {
          const from = `SELECT m.session,m.thread FROM ${table} m WHERE m.thread IN (`;
          const into = `SELECT m.session,m.thread FROM ${table} m WHERE latest_thread_member_visited(m.session)=m.session AND m.thread IN (`;
          if (sql.includes(from)) sql = sql.replaceAll(from, into);
        }
        if (sql !== trigger.sql) {
          assert.match(trigger.name, /^latest_thread_[a-z_]+$/);
          db.exec(`DROP TRIGGER "${trigger.name}"`);
          db.exec(sql);
          instrumented++;
        }
      }
      assert.ok(instrumented > 0);
      prepare(store, "tracked");
      const table = db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='latest_thread_members'").get()
        ? "latest_thread_members" : "thread_sessions";
      const plain = `SELECT m.session,m.thread FROM ${table} m WHERE m.thread IN (?)`;
      const observed = `SELECT m.session,m.thread FROM ${table} m WHERE latest_thread_member_visited(m.session)=m.session AND m.thread IN (?)`;
      const plan = (sql: string) => db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(thread.id).map((r) => r.detail);
      assert.deepEqual(plan(observed), plan(plain), "counting preserves the membership query's plan");
      visited = 0;
      db.prepare("DELETE FROM threads WHERE id=?").run(thread.id);
      assert.equal(indexedLatestThread(db, "tracked"), null);
      counts.push(visited);
    } finally { store.close(); }
  }
  assert.deepEqual(counts, [1, 1]);
});

test("opening an existing shared conversation does not stage its tracked memberships", () => {
  const counts: number[] = [], oldWriterIds: number[] = [], ignoredUpdateIds: number[] = [];
  for (const members of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const shared = store.openThread("slack", "C", "shared", null, null);
      const occupied = store.openThread("slack", "C", "occupied", null, null);
      db.exec("BEGIN");
      for (let n = 0; n < members; n++) store.joinThread(shared.id, `s-${n}`, "slack");
      db.exec("COMMIT");
      for (let n = 0; n < members; n++) prepare(store, `s-${n}`);
      assert.equal(db.prepare("SELECT COUNT(*) AS n FROM latest_thread_changed").get()?.n, 0);
      assert.equal(store.openThread("slack", "C", "shared", null, null).id, shared.id);
      counts.push(Number(db.prepare("SELECT COUNT(*) AS n FROM latest_thread_changed").get()?.n));
      assert.equal(db.prepare("SELECT COUNT(*) AS n FROM latest_thread_adding_ids").get()?.n, 0,
        "this station does not attempt an insert for an existing conversation");
      // An older writer can still attempt the insert, or ignore a conflicting update. Neither operation needs
      // a snapshot for each tracked member, and the original order remains readable.
      db.prepare("INSERT OR IGNORE INTO threads(surface,channel,thread_ts,created_at) VALUES('slack','C','shared',1)").run();
      oldWriterIds.push(Number(db.prepare("SELECT COUNT(*) AS n FROM latest_thread_adding_ids").get()?.n));
      assert.equal(db.prepare("SELECT COUNT(*) AS n FROM latest_thread_changed").get()?.n, 0);
      db.prepare("UPDATE OR IGNORE threads SET thread_ts='occupied' WHERE id=?").run(shared.id);
      ignoredUpdateIds.push(Number(db.prepare("SELECT COUNT(*) AS n FROM latest_thread_updating_ids").get()?.n));
      assert.equal(db.prepare("SELECT COUNT(*) AS n FROM latest_thread_updating").get()?.n, 0);
      assert.equal(indexedLatestThread(db, "s-0")?.id, shared.id);
      db.prepare("UPDATE threads SET thread_ts='renamed' WHERE id=?").run(occupied.id);
      assert.equal(indexedLatestThread(db, "s-0")?.id, shared.id);
    } finally { store.close(); }
  }
  assert.deepEqual(counts, [0, 0], "a no-op does not write a row for each tracked session");
  assert.deepEqual(oldWriterIds, [1, 1]);
  assert.deepEqual(ignoredUpdateIds, [2, 2]);
});

test("a nested change seeks only its affected outer-update snapshot", () => {
  const counts: number[] = [];
  for (const others of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    try {
      installLatestThreadIndex(db);
      const put = db.prepare("INSERT INTO latest_thread_updating VALUES(?,?,0,0,0,NULL,NULL)");
      put.run("target", 1);
      for (let n = 0; n < others; n++) put.run(`other-${n}`, n + 2);
      db.prepare("INSERT INTO latest_thread_changed VALUES('target',1,0,0,0,NULL,NULL)").run();
      let visited = 0;
      db.function("latest_update_visited", (session) => { visited++; return session; });
      const observed = LATEST_THREAD_REFRESH_UPDATING.replace("WHERE (session,thread) IN", "WHERE latest_update_visited(session)=session AND (session,thread) IN");
      assert.notEqual(observed, LATEST_THREAD_REFRESH_UPDATING);
      const plan = (sql: string) => db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all().map((r) => String(r.detail));
      assert.deepEqual(plan(observed), plan(LATEST_THREAD_REFRESH_UPDATING));
      assert.match(plan(observed).join("\n"), /SEARCH latest_thread_updating USING PRIMARY KEY/);
      db.exec(observed);
      counts.push(visited);
    } finally { store.close(); }
  }
  assert.deepEqual(counts, [1, 1]);
});

for (const recursive of [false, true]) {
  test(`the reverse membership set follows tracked writes and session removal (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? 1 : 0}`);
      const session = (key: string) => store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc",
        workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1 });
      session("s1"); session("s2");
      const a = store.openThread("slack", "C", "a", null, null);
      const b = store.openThread("slack", "C", "b", null, null);
      store.joinThread(a.id, "s1", "a"); store.joinThread(b.id, "s1", "b");
      store.joinThread(a.id, "s2", "a"); store.joinThread(a.id, "untracked", "a");
      db.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES(999999,'s1','orphan',9)").run();
      installLatestThreadIndex(db); prepare(store, "s1"); prepare(store, "s2");
      const check = () => {
        assert.deepEqual(db.prepare("SELECT thread,session FROM latest_thread_members ORDER BY thread,session").all(),
          db.prepare(`SELECT m.thread,m.session FROM thread_sessions m JOIN latest_thread_scopes s ON s.session=m.session
            ORDER BY m.thread,m.session`).all());
        for (const s of ["s1", "s2"].filter((key) => latestThreadReady(db, key)))
          assert.equal(indexedLatestThread(db, s)?.id ?? null, originalLatestId(db, s));
      };
      check();
      db.prepare("DELETE FROM threads WHERE id=?").run(a.id); check();
      db.prepare("INSERT INTO threads(id,surface,channel,thread_ts,created_at) VALUES(?,'slack','C','restored',1)").run(a.id); check();
      const first = db.prepare("SELECT rowid FROM thread_sessions WHERE thread=? AND session='s1'").get(b.id)!.rowid;
      db.exec("BEGIN");
      db.prepare("INSERT OR REPLACE INTO thread_sessions(rowid,thread,session,connect,joined_at) VALUES(?,999999,'s2','new',10)").run(first);
      check();
      db.exec("ROLLBACK"); check();
      db.prepare("INSERT OR REPLACE INTO thread_sessions(rowid,thread,session,connect,joined_at) VALUES(?,999999,'s2','new',10)").run(first);
      check();
      db.prepare("DELETE FROM thread_sessions WHERE thread=999999 AND session='s1'").run(); check();
      db.prepare("DELETE FROM sessions WHERE key='s1'").run(); check();
      session("s1"); prepare(store, "s1"); check();
    } finally { store.close(); }
  });
}

for (const recursive of [false, true]) {
  test(`updates replacing other deliveries or memberships keep every affected order (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? 1 : 0}`);
      const a = store.openThread("slack", "C", "a", null, null);
      const b = store.openThread("slack", "C", "b", null, null);
      const c = store.openThread("slack", "C", "c", null, null);
      const d = store.openThread("slack", "C", "d", null, null);
      store.joinThread(a.id, "s1", "a"); store.joinThread(c.id, "s1", "c");
      store.joinThread(b.id, "s2", "b"); store.joinThread(d.id, "s2", "d");
      const put = db.prepare("INSERT INTO deliveries(rowid,thread,n,session,delivered_at) VALUES(?,?,1,?,NULL)");
      put.run(100, a.id, "s1"); put.run(99, c.id, "s1"); put.run(101, b.id, "s2"); put.run(98, d.id, "s2");
      installLatestThreadIndex(db); prepare(store, "s1"); prepare(store, "s2");
      const check = () => {
        for (const s of ["s1", "s2"])
          assert.equal(indexedLatestThread(db, s)?.id ?? null, originalLatestId(db, s));
        assert.deepEqual(db.prepare("SELECT thread,session FROM latest_thread_members ORDER BY thread,session").all(),
          db.prepare(`SELECT m.thread,m.session FROM thread_sessions m JOIN latest_thread_scopes s ON s.session=m.session
            ORDER BY m.thread,m.session`).all());
        const actual = db.prepare("SELECT session,thread,has_last,last_delivery,joined_at,member_rowid FROM latest_thread_rows ORDER BY session,thread").all();
        const expected = db.prepare(`SELECT m.session,m.thread,d.rowid IS NOT NULL AS has_last,COALESCE(d.rowid,0) AS last_delivery,
          m.joined_at,m.rowid AS member_rowid FROM thread_sessions m JOIN latest_thread_scopes s ON s.session=m.session
          JOIN threads t ON t.id=m.thread LEFT JOIN deliveries d ON d.rowid=(SELECT rowid FROM deliveries
            WHERE session=m.session AND thread=m.thread ORDER BY rowid DESC LIMIT 1) ORDER BY m.session,m.thread`).all();
        assert.deepEqual(actual, expected);
      };
      check();
      const replaceDelivery = db.prepare("UPDATE OR REPLACE deliveries SET rowid=101,thread=?,session='s2' WHERE rowid=100");
      db.exec("BEGIN"); replaceDelivery.run(b.id); check(); db.exec("ROLLBACK"); check();
      replaceDelivery.run(b.id); check();
      const source = db.prepare("SELECT rowid FROM thread_sessions WHERE session='s1' AND thread=?").get(a.id)!.rowid;
      const other = db.prepare("SELECT rowid FROM thread_sessions WHERE session='s1' AND thread=?").get(c.id)!.rowid;
      const replaceMember = db.prepare("UPDATE OR REPLACE thread_sessions SET rowid=?,thread=?,session='s2' WHERE rowid=?");
      db.exec("BEGIN"); replaceMember.run(other, b.id, source); check(); db.exec("ROLLBACK"); check();
      replaceMember.run(other, b.id, source); check();
    } finally { store.close(); }
  });
}

test("an ignored update cannot disturb later deliveries or a no-op update", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const a = store.openThread("slack", "C", "a", null, null);
    const b = store.openThread("slack", "C", "b", null, null);
    store.joinThread(a.id, "s", "a"); store.joinThread(b.id, "s", "b");
    const put = db.prepare("INSERT INTO deliveries(rowid,thread,n,session,delivered_at) VALUES(?,?,1,'s',NULL)");
    put.run(100, a.id); put.run(101, b.id);
    installLatestThreadIndex(db); prepare(store, "s");
    db.prepare("UPDATE OR IGNORE deliveries SET rowid=101 WHERE rowid=100").run();
    db.prepare("INSERT INTO deliveries(rowid,thread,n,session,delivered_at) VALUES(102,?,2,'s',NULL)").run(a.id);
    db.prepare("UPDATE deliveries SET n=n WHERE rowid=102").run();
    assert.equal(indexedLatestThread(db, "s")?.id, a.id);
    assert.equal(indexedLatestThread(db, "s")?.id, originalLatestId(db, "s"));
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM latest_thread_rows WHERE session='s' AND thread=?").get(a.id)?.n, 1);
    db.prepare("UPDATE deliveries SET n=3 WHERE rowid=102").run();
    assert.equal(indexedLatestThread(db, "s")?.id, originalLatestId(db, "s"));
  } finally { store.close(); }
});

for (const recursive of [false, true]) {
  test(`a thread update replacing another thread keeps the latest order (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? 1 : 0}`);
      const a = store.openThread("slack", "C", "a", null, null);
      const b = store.openThread("slack", "C", "b", null, null);
      store.joinThread(a.id, "s", "a"); store.joinThread(b.id, "s", "b");
      const put = db.prepare("INSERT INTO deliveries(rowid,thread,n,session,delivered_at) VALUES(?,?,1,'s',NULL)");
      put.run(100, a.id); put.run(101, b.id);
      installLatestThreadIndex(db); prepare(store, "s");
      db.prepare("UPDATE OR REPLACE threads SET thread_ts='b' WHERE id=?").run(a.id);
      assert.equal(indexedLatestThread(db, "s")?.id, a.id);
      assert.equal(indexedLatestThread(db, "s")?.id, originalLatestId(db, "s"));
      assert.equal(db.prepare("SELECT COUNT(*) AS n FROM latest_thread_rows WHERE session='s'").get()?.n, 1);
    } finally { store.close(); }
  });
}

for (const recursive of [false, true]) {
  test(`interleaved source writes agree with the original order (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? 1 : 0}`);
      for (const s of ["s0", "s1", "s2"]) store.insertSession({ key: s, connect: "ember", runtime: "claude", profile: "cc",
        workspace: `/w/${s}`, token: s, createdAt: 1, lastActiveAt: 1 });
      for (let id = 1; id <= 8; id++) db.prepare("INSERT INTO threads(id,surface,channel,thread_ts,created_at) VALUES(?,'slack','C',?,1)").run(id, `t${id}`);
      installLatestThreadIndex(db);
      for (const s of ["s0", "s1", "s2"]) prepare(store, s);
      let state = 0x3250ab41;
      const pick = (n: number) => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return (state >>> 8) % n; };
      const session = () => `s${pick(3)}`, thread = () => 1 + pick(8), memberId = () => 1 + pick(20), deliveryId = () => 1 + pick(40);
      const expected = db.prepare(`SELECT m.session,m.thread,d.rowid IS NOT NULL AS has_last,COALESCE(d.rowid,0) AS last_delivery,
        m.joined_at,m.rowid AS member_rowid FROM thread_sessions m JOIN latest_thread_scopes s ON s.session=m.session
        JOIN threads t ON t.id=m.thread LEFT JOIN deliveries d ON d.rowid=(SELECT rowid FROM deliveries
          WHERE session=m.session AND thread=m.thread ORDER BY rowid DESC LIMIT 1) ORDER BY m.session,m.thread`);
      const actual = db.prepare("SELECT session,thread,has_last,last_delivery,joined_at,member_rowid FROM latest_thread_rows ORDER BY session,thread");
      const members = db.prepare("SELECT thread,session FROM latest_thread_members ORDER BY thread,session");
      const wantedMembers = db.prepare(`SELECT m.thread,m.session FROM thread_sessions m JOIN latest_thread_scopes s ON s.session=m.session
        ORDER BY m.thread,m.session`);
      const check = (at: number) => {
        assert.deepEqual(actual.all(), expected.all(), `ordered rows after step ${at}`);
        assert.deepEqual(members.all(), wantedMembers.all(), `tracked members after step ${at}`);
        for (const s of ["s0", "s1", "s2"])
          assert.equal(indexedLatestThread(db, s)?.id ?? null, originalLatestId(db, s), `${s} after step ${at}`);
      };
      for (let n = 0; n < 240; n++) {
        const rollback = n % 11 === 0;
        if (rollback) db.exec("BEGIN");
        switch (pick(8)) {
          case 0: db.prepare("INSERT OR REPLACE INTO thread_sessions(rowid,thread,session,connect,joined_at) VALUES(?,?,?,'c',?)")
            .run(memberId(), thread(), session(), pick(9) / 2); break;
          case 1: db.prepare("UPDATE OR REPLACE thread_sessions SET rowid=?,thread=?,session=?,joined_at=? WHERE rowid=?")
            .run(memberId(), thread(), session(), pick(9) / 2, memberId()); break;
          case 2: db.prepare("DELETE FROM thread_sessions WHERE rowid=?").run(memberId()); break;
          case 3: db.prepare("INSERT OR REPLACE INTO deliveries(rowid,thread,n,session,delivered_at) VALUES(?,?,?,?,NULL)")
            .run(deliveryId(), thread(), 1 + pick(4), session()); break;
          case 4: db.prepare("UPDATE OR REPLACE deliveries SET rowid=?,thread=?,n=?,session=? WHERE rowid=?")
            .run(deliveryId(), thread(), 1 + pick(4), session(), deliveryId()); break;
          case 5: db.prepare("DELETE FROM deliveries WHERE rowid=?").run(deliveryId()); break;
          case 6: db.prepare("INSERT OR REPLACE INTO threads(id,surface,channel,thread_ts,created_at) VALUES(?,'slack','C',?,1)")
            .run(thread(), `t${thread()}`); break;
          case 7: db.prepare("DELETE FROM threads WHERE id=?").run(thread()); break;
        }
        check(n);
        if (rollback) { db.exec("ROLLBACK"); check(n); }
      }
    } finally { store.close(); }
  });
}

for (const recursive of [false, true]) for (const alias of ["rowid", "_rowid_", "oid"]) {
  test(`a prepared order follows ${alias} replacements and rollback (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? 1 : 0}`);
      const a = store.openThread("slack", "C", "a", null, null);
      const b = store.openThread("slack", "C", "b", null, null);
      store.joinThread(a.id, "s1", "a"); store.joinThread(b.id, "s1", "b");
      store.joinThread(a.id, "s2", "a"); store.joinThread(b.id, "s2", "b");
      const add = db.prepare("INSERT INTO deliveries(rowid,thread,n,session,delivered_at) VALUES(?,?,? ,?,NULL)");
      add.run(100, a.id, 1, "s1"); add.run(101, b.id, 1, "s2");
      installLatestThreadIndex(db); prepare(store, "s1"); prepare(store, "s2");
      const check = () => {
        for (const s of ["s1", "s2"])
          assert.equal(indexedLatestThread(db, s)?.id ?? null, originalLatestId(db, s));
        assert.deepEqual(db.prepare("SELECT thread,session FROM latest_thread_members ORDER BY thread,session").all(),
          db.prepare(`SELECT m.thread,m.session FROM thread_sessions m JOIN latest_thread_scopes s ON s.session=m.session
            ORDER BY m.thread,m.session`).all());
      };
      check();
      db.exec("BEGIN");
      db.prepare(`INSERT OR REPLACE INTO deliveries(${alias},thread,n,session,delivered_at) VALUES(100,?,2,'s2',NULL)`).run(a.id);
      check();
      db.exec("ROLLBACK");
      check();
      db.prepare(`INSERT OR REPLACE INTO deliveries(${alias},thread,n,session,delivered_at) VALUES(100,?,2,'s2',NULL)`).run(a.id);
      check();
      db.prepare("INSERT OR IGNORE INTO deliveries(thread,n,session,delivered_at) VALUES(?,2,'s2',NULL)").run(a.id);
      check();
      add.run(102, b.id, 2, "s1");
      check();
      // One replacement can displace both a different rowid and an existing (thread,session) pair.
      const member = db.prepare("SELECT rowid FROM thread_sessions WHERE thread=? AND session='s1'").get(a.id)!.rowid;
      const replace = db.prepare(`INSERT OR REPLACE INTO thread_sessions(${alias},thread,session,connect,joined_at) VALUES(?,?,'s2','b',10)`);
      db.exec("BEGIN"); replace.run(member, b.id); check(); db.exec("ROLLBACK"); check();
      replace.run(member, b.id); check();
    } finally { store.close(); }
  });
}
