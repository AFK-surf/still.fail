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

test("incompatible session list index versions cannot be read or built", () => {
  const { store, db, add } = fixture();
  try {
    add("one", "x", "mine");
    db.exec("UPDATE session_list_meta SET version=2");
    assert.throws(() => listedSessions(makeStore(db, "/none"), null, false, { workspace: "mine", home: false }), /session list.*version/i);
    assert.throws(() => sessionListStep(db), /session list.*version/i);
  } finally { store.close(); }
});
