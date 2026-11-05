import assert from "node:assert/strict";
import { test } from "node:test";
import { listedSessions, makeStore } from "../src/read/store.ts";
import { installSessionListIndex, sessionListReady, sessionListStep } from "../src/store/session-list-index.ts";
import { Store } from "../src/store/store.ts";

function dropIndex(store: Store) {
  const db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'session_list_%'").all() as { name: string }[])
    db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE session_list_rows; DROP TABLE session_list_replaced; DROP TABLE session_list_meta");
}

function fixture() {
  const store = Store.open(":memory:"), db = store.db;
  const add = (key: string, connect: string, ws: string | null, token = key) => store.insertSession({
    key, connect, runtime: "claude", profile: "cc", workspace: "/work", token, createdAt: 1, lastActiveAt: 1, ws,
  });
  const exact = () => {
    const read = makeStore(db, "/no-station-config");
    for (const viewer of [null, { workspace: "mine", home: false }, { workspace: "mine", home: true }]) {
      for (const connect of [null, "x", "y"]) for (const archived of [false, true]) {
        const where = [archived ? "archived_at IS NOT NULL" : "archived_at IS NULL"];
        const args: (string | number)[] = [];
        if (viewer !== null) {
          where.push(viewer.home ? "(ws = ? OR ws IS NULL)" : "ws = ?");
          args.push(viewer.workspace);
        }
        if (connect !== null) { where.push("connect = ?"); args.push(connect); }
        const expected = db.prepare(`SELECT key FROM sessions WHERE ${where.join(" AND ")} ORDER BY last_active_at DESC, rowid ASC`)
          .all(...args).map((row) => row.key);
        assert.deepEqual(listedSessions(read, connect, archived, viewer).map((row) => row.key), expected);
      }
    }
  };
  return { store, db, add, exact };
}

for (const recursive of [false, true]) test(`session list candidates follow replacements and moves (recursive triggers ${recursive})`, () => {
  const { store, db, add, exact } = fixture();
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    add("one", "x", "mine"); add("two", "y", null); add("three", "x", "other"); exact();
    db.exec("UPDATE sessions SET archived_at=5, ws='mine', connect='y' WHERE key='three'"); exact();
    db.exec("UPDATE sessions SET archived_at=NULL, last_active_at=3 WHERE key='three'"); exact();
    db.exec("INSERT OR REPLACE INTO sessions (key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws,archived_at) VALUES ('new','y','thread','claude','cc','/w','two',1,4,'mine',2)"); exact();
    const id = db.prepare("SELECT rowid AS id FROM sessions WHERE key='one'").get()!.id;
    db.prepare("UPDATE OR REPLACE sessions SET rowid=?, ws=NULL WHERE key='new'").run(id); exact();
    db.exec("UPDATE OR REPLACE sessions SET key='three', token='three', archived_at=NULL WHERE key='new'"); exact();
    db.exec("DELETE FROM sessions WHERE key='three'"); exact();
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`session list candidates stay exact through mixed replacements (recursive triggers ${recursive})`, () => {
  const { store, db } = fixture(), reference = fixture();
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    reference.db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    dropIndex(reference.store);
    const statements = (source: typeof db) => ({
      put: source.prepare("INSERT OR REPLACE INTO sessions (rowid,key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws,archived_at) VALUES (?,?,?,'thread','claude','cc','/w',?,1,1,?,?)"),
      change: source.prepare("UPDATE OR REPLACE sessions SET rowid=?, key=?, token=?, connect=?, ws=?, archived_at=? WHERE key=?"),
      drop: source.prepare("DELETE FROM sessions WHERE key=?"),
    });
    const actual = statements(db), before = statements(reference.db);
    const sessions = (source: typeof db) => source.prepare("SELECT rowid AS rowid,key,token,connect,ws,archived_at FROM sessions ORDER BY key").all();
    const candidates = () => db.prepare("SELECT session,ws,connect,archived FROM session_list_rows ORDER BY session").all();
    const expected = () => db.prepare("SELECT key AS session,ws,connect,archived_at IS NOT NULL AS archived FROM sessions ORDER BY key").all();
    let seed = 0x12345678;
    const next = (n: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
    for (let i = 0; i < 200; i++) {
      const rowid = next(23) - 5, key = `s${next(13)}`, token = `t${next(13)}`, connect = `c${next(4)}`;
      const ws = [null, "", "mine", "other"][next(4)]!, archived = next(2) ? 2 : null;
      const method = i % 4 === 0 ? "drop" : i % 4 === 1 ? "change" : "put";
      const args = method === "drop" ? [key] : method === "change" ? [rowid, key, token, connect, ws, archived, `s${next(13)}`] : [rowid, key, connect, token, ws, archived];
      const run = (ops: ReturnType<typeof statements>) => {
        try { ops[method].run(...args); return null; }
        catch (error) { return (error as { errcode?: number }).errcode; }
      };
      assert.equal(run(actual), run(before), `conflict policy at operation ${i}`);
      assert.deepEqual(sessions(db), sessions(reference.db), `sessions at operation ${i}`);
      assert.deepEqual(candidates(), expected(), `session list candidates at operation ${i}`);
    }
  } finally { store.close(); reference.store.close(); }
});

test("old sessions are indexed in bounded batches while they change", () => {
  const { store, db, add, exact } = fixture();
  try {
    dropIndex(store);
    for (let i = 0; i < 8; i++) add(`old-${i}`, i % 2 ? "x" : "y", i % 3 ? "mine" : null);
    installSessionListIndex(db);
    assert.equal(sessionListReady(db), false);
    assert.throws(() => listedSessions(makeStore(db, "/none"), null, false, { workspace: "mine", home: false }), /still being prepared/);
    assert.deepEqual(sessionListStep(db, 2), { done: false, visited: 2 });
    db.exec("UPDATE sessions SET rowid=2000, ws='other', archived_at=1 WHERE key='old-3'");
    db.exec("UPDATE sessions SET rowid=-2, connect='x' WHERE key='old-4'");
    db.exec("DELETE FROM sessions WHERE key='old-5'");
    add("new", "x", "mine");
    let steps = 0;
    while (!sessionListReady(db)) {
      assert.ok(sessionListStep(db, 2).visited <= 2);
      assert.ok(++steps < 10);
    }
    exact();
  } finally { store.close(); }
});

test("a failed old-session batch rolls back its cursor and candidates", () => {
  const { store, db, add, exact } = fixture();
  try {
    dropIndex(store); add("one", "x", "mine"); add("two", "x", "mine");
    installSessionListIndex(db);
    db.exec("CREATE TRIGGER fail_session_list BEFORE INSERT ON session_list_rows WHEN NEW.session='two' BEGIN SELECT RAISE(ABORT, 'failed batch'); END");
    assert.throws(() => sessionListStep(db, 10), /failed batch/);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM session_list_rows").get()!.n, 0);
    assert.equal(db.prepare("SELECT last_rowid FROM session_list_meta WHERE id=1").get()!.last_rowid, null);
    db.exec("DROP TRIGGER fail_session_list");
    assert.deepEqual(sessionListStep(db, 10), { done: true, visited: 2 });
    exact();
  } finally { store.close(); }
});

test("64-bit old session rowids do not prevent preparing a session list", () => {
  const { store, db, add, exact } = fixture();
  try {
    dropIndex(store);
    add("low", "x", "mine"); add("high", "y", null);
    db.exec("UPDATE sessions SET rowid=CAST('-9007199254740993' AS INTEGER) WHERE key='low'");
    db.exec("UPDATE sessions SET rowid=CAST('9007199254740993' AS INTEGER) WHERE key='high'");
    installSessionListIndex(db);
    assert.deepEqual(sessionListStep(db, 1), { done: false, visited: 1 });
    assert.deepEqual(sessionListStep(db, 1), { done: false, visited: 1 });
    assert.deepEqual(sessionListStep(db, 1), { done: true, visited: 0 });
    exact();
  } finally { store.close(); }
});

test("incompatible session list index versions cannot be read or built", () => {
  const { store, db, add } = fixture();
  try {
    add("one", "x", "mine");
    db.exec("UPDATE session_list_meta SET version=2");
    assert.throws(() => listedSessions(makeStore(db, "/none"), null, false, { workspace: "mine", home: false }), /session list.*version/i);
    assert.throws(() => sessionListStep(db), /session list.*version/i);
  } finally { store.close(); }
});
