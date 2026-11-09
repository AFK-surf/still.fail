import assert from "node:assert/strict";
import { test } from "node:test";
import { listBindings, makeStore } from "../src/read/store.ts";
import { installSessionBindingsIndex, sessionBindingsReady, sessionBindingsStep } from "../src/store/session-bindings-index.ts";
import { Store } from "../src/store/store.ts";

function dropIndex(store: Store) {
  const db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'session_binding_%'").all() as { name: string }[])
    db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE session_binding_rows; DROP TABLE session_binding_replaced; DROP TABLE session_binding_meta");
}

function check(store: Store) {
  const db = store.db;
  const expected = db.prepare("SELECT session_key AS session, CAST(rowid AS TEXT) AS position, connect FROM bindings ORDER BY session_key, rowid").all();
  const actual = db.prepare("SELECT session, CAST(binding_rowid AS TEXT) AS position, connect FROM session_binding_rows ORDER BY session, binding_rowid").all();
  assert.deepEqual(actual, expected);
  const read = makeStore(db, "/none");
  const bindings = db.prepare("SELECT connect, session_key FROM bindings").all();
  const groups = new Map<string, unknown[]>();
  for (const r of bindings) groups.set(r.session_key as string, [...(groups.get(r.session_key as string) ?? []), r.connect]);
  for (const key of ["one", "two", "three", "absent"]) {
    assert.deepEqual(listBindings(read, [key]).get(key), groups.get(key));
  }
  const selected = listBindings(read, ["one", "two", "one"]);
  assert.deepEqual(selected.get("one"), groups.get("one"));
  assert.deepEqual(selected.get("two"), groups.get("two"));
}

for (const recursive of [false, true]) test(`binding lookup follows mixed replacements (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), reference = Store.open(":memory:");
  const db = store.db;
  try {
    for (const d of [db, reference.db]) d.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    dropIndex(reference);
    const statements = (source: typeof db) => ({
      put: source.prepare("INSERT OR REPLACE INTO bindings(rowid,connect,session_key) VALUES (?,?,?)"),
      change: source.prepare("UPDATE OR REPLACE bindings SET rowid=?, connect=?, session_key=? WHERE rowid=?"),
      drop: source.prepare("DELETE FROM bindings WHERE rowid=?"),
    });
    const actual = statements(db), before = statements(reference.db);
    const rows = (source: typeof db) => source.prepare("SELECT rowid AS id,connect,session_key FROM bindings ORDER BY rowid").all();
    let seed = 0x12345678;
    const next = (n: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
    for (let i = 0; i < 300; i++) {
      const rowid = next(19) - 5, connect = next(5) === 0 ? null : `c${next(8)}`, session = ["one", "two", "three"][next(3)]!;
      const method = i % 5 === 0 ? "drop" : i % 5 === 1 ? "change" : "put";
      const args = method === "drop" ? [rowid] : method === "change" ? [rowid, connect, session, next(19) - 5] : [rowid, connect, session];
      const run = (ops: ReturnType<typeof statements>) => {
        try { ops[method].run(...args); return null; }
        catch (error) { return (error as { errcode?: number }).errcode; }
      };
      assert.equal(run(actual), run(before), `conflict policy at operation ${i}`);
      assert.deepEqual(rows(db), rows(reference.db), `bindings at operation ${i}`);
      check(store);
    }
  } finally { store.close(); reference.close(); }
});

for (const recursive of [false, true]) for (const alias of ["rowid", "_rowid_", "oid"]) {
  test(`replacing a binding by ${alias} preserves session lookups (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
      db.exec("INSERT INTO bindings(rowid,connect,session_key) VALUES(1,'z','one'),(2,'a','two'),(3,NULL,'one'),(4,NULL,'one')");
      db.exec(`UPDATE OR REPLACE bindings SET ${alias}=2, session_key='three' WHERE rowid=1`);
      check(store);
      db.exec(`INSERT OR REPLACE INTO bindings(${alias},connect,session_key) VALUES(3,'a','one')`);
      check(store);
    } finally { store.close(); }
  });
}

test("old bindings are indexed in bounded steps as they change", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    dropIndex(store);
    for (let i = 0; i < 8; i++) db.prepare("INSERT INTO bindings(connect,session_key) VALUES(?,?)").run(`old-${i}`, i % 2 ? "one" : "two");
    installSessionBindingsIndex(db);
    assert.equal(sessionBindingsReady(db), false);
    assert.deepEqual(listBindings(makeStore(db, "/none"), []), new Map());
    assert.throws(() => listBindings(makeStore(db, "/none"), ["one"]), /still being prepared/);
    assert.deepEqual(sessionBindingsStep(db, 2), { done: false, visited: 2 });
    db.exec("UPDATE bindings SET rowid=2000, session_key='three' WHERE connect='old-3'");
    db.exec("UPDATE bindings SET rowid=-2, session_key='one' WHERE connect='old-4'");
    db.exec("DELETE FROM bindings WHERE connect='old-5'");
    let steps = 0;
    while (!sessionBindingsReady(db)) {
      db.prepare("INSERT INTO bindings(connect,session_key) VALUES(?, 'three')").run(`new-${steps}`);
      assert.ok(sessionBindingsStep(db, 2).visited <= 2);
      assert.ok(++steps < 10);
    }
    check(store);
  } finally { store.close(); }
});

test("a failed binding batch rolls back its rows and cursor", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    dropIndex(store);
    db.exec("INSERT INTO bindings(connect,session_key) VALUES('a','one'),('b','two')");
    installSessionBindingsIndex(db);
    db.exec("CREATE TRIGGER fail_binding BEFORE INSERT ON session_binding_rows WHEN NEW.session='two' BEGIN SELECT RAISE(ABORT,'failed batch'); END");
    assert.throws(() => sessionBindingsStep(db, 10), /failed batch/);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM session_binding_rows").get()!.n, 0);
    assert.equal(db.prepare("SELECT last_rowid FROM session_binding_meta").get()!.last_rowid, null);
    db.exec("DROP TRIGGER fail_binding");
    assert.deepEqual(sessionBindingsStep(db, 10), { done: true, visited: 2 });
    check(store);
  } finally { store.close(); }
});

test("64-bit old binding rowids are indexed without loss", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    dropIndex(store);
    db.exec("INSERT INTO bindings(rowid,connect,session_key) VALUES(-9007199254740993,'low','one'),(9007199254740993,'high','two')");
    installSessionBindingsIndex(db);
    assert.deepEqual(sessionBindingsStep(db, 1), { done: false, visited: 1 });
    assert.deepEqual(sessionBindingsStep(db, 1), { done: false, visited: 1 });
    assert.deepEqual(sessionBindingsStep(db, 1), { done: true, visited: 0 });
    check(store);
  } finally { store.close(); }
});

test("an incompatible binding index is neither read nor built", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec("INSERT INTO bindings(connect,session_key) VALUES('a','one'); UPDATE session_binding_meta SET version=2");
    assert.throws(() => listBindings(makeStore(db, "/none"), ["one"]), /session binding.*version/i);
    assert.throws(() => sessionBindingsStep(db), /session binding.*version/i);
  } finally { store.close(); }
});
