import assert from "node:assert/strict";
import { test } from "node:test";
import { archiveMarksReady, archiveMarksStep, installArchiveMarkIndex } from "../src/store/archive-mark-index.ts";
import { Store } from "../src/store/store.ts";

function dropIndex(store: Store) {
  const db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND (name LIKE 'archive_pin_%' OR name LIKE 'archive_keep_%')").all() as { name: string }[])
    db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE archive_pin_rows; DROP TABLE archive_keep_rows; DROP TABLE archive_pin_replaced; DROP TABLE archive_keep_replaced; DROP TABLE archive_mark_meta");
}

function check(store: Store) {
  const db = store.db;
  for (const [source, key, lookup] of [["pins", "session", "archive_pin_rows"], ["kept_chats", "thread", "archive_keep_rows"]]) {
    const expected = db.prepare(`SELECT ${key} AS value, CAST(rowid AS TEXT) AS position FROM ${source} ORDER BY ${key}, rowid`).all();
    const actual = db.prepare(`SELECT ${key} AS value, CAST(position AS TEXT) AS position FROM ${lookup} i ORDER BY i.${key}, i.position`).all();
    assert.deepEqual(actual, expected, source);
  }
}

for (const recursive of [false, true]) test(`archive marks follow mixed replacements (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), reference = Store.open(":memory:");
  const db = store.db;
  try {
    dropIndex(store);
    dropIndex(reference);
    for (const d of [db, reference.db]) d.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    installArchiveMarkIndex(db);
    assert.equal(archiveMarksReady(db), true);
    let seed = 0x12345678;
    const next = (n: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
    for (let i = 0; i < 500; i++) {
      const isPin = i % 2 === 0, table = isPin ? "pins" : "kept_chats", key = isPin ? "session" : "thread";
      const id = next(17) - 4, viewer = `v${next(9)}`, value = isPin ? `s${next(6)}` : next(6);
      const method = i % 5 === 0 ? "delete" : i % 5 === 1 ? "update" : "insert";
      const sql = method === "delete" ? `DELETE FROM ${table} WHERE rowid=?`
        : method === "update" ? `UPDATE OR REPLACE ${table} SET rowid=?, viewer=?, ${key}=? WHERE rowid=?`
        : `INSERT OR REPLACE INTO ${table} (rowid,viewer,${key}${isPin ? ",at" : ""}) VALUES (?,?,?${isPin ? ",1" : ""})`;
      const args = method === "delete" ? [id] : method === "update" ? [id, viewer, value, next(17) - 4] : [id, viewer, value];
      const run = (source: typeof db) => {
        try { source.prepare(sql).run(...args); return null; }
        catch (error) { return (error as { errcode?: number }).errcode; }
      };
      assert.equal(run(db), run(reference.db), `conflict policy at operation ${i}`);
      if (i % 10 === 0) check(store);
    }
    check(store);
  } finally { store.close(); reference.close(); }
});

test("old marks are prepared in bounded batches as writers change them", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    dropIndex(store);
    for (let i = 0; i < 8; i++) {
      db.prepare("INSERT INTO pins(viewer,session,at) VALUES(?,?,1)").run(`p${i}`, `s${i % 2}`);
      db.prepare("INSERT INTO kept_chats(viewer,thread) VALUES(?,?)").run(`p${i}`, i % 2);
    }
    installArchiveMarkIndex(db);
    assert.equal(archiveMarksReady(db), false);
    assert.deepEqual(archiveMarksStep(db, 2), { done: false, visited: 2 });
    db.exec("UPDATE pins SET rowid=2000,session='moved' WHERE viewer='p3'; DELETE FROM kept_chats WHERE viewer='p4'");
    let steps = 0;
    while (!archiveMarksReady(db)) {
      db.prepare("INSERT INTO pins(viewer,session,at) VALUES(?, 'new',1)").run(`new-${steps}`);
      assert.ok(archiveMarksStep(db, 2).visited <= 2);
      assert.ok(++steps < 20);
    }
    check(store);
  } finally { store.close(); }
});

test("a failed mark batch rolls back the rows and its cursor", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    dropIndex(store);
    db.exec("INSERT INTO kept_chats(viewer,thread) VALUES('a',1),('b',2)");
    installArchiveMarkIndex(db);
    db.exec("CREATE TRIGGER fail_archive_mark BEFORE INSERT ON archive_keep_rows WHEN NEW.thread=2 BEGIN SELECT RAISE(ABORT,'failed batch'); END");
    assert.throws(() => archiveMarksStep(db, 10), /failed batch/);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM archive_keep_rows").get()!.n, 0);
    assert.equal(db.prepare("SELECT last_rowid FROM archive_mark_meta WHERE kind='kept'").get()!.last_rowid, null);
    db.exec("DROP TRIGGER fail_archive_mark");
    assert.deepEqual(archiveMarksStep(db, 10), { done: true, visited: 2 });
    check(store);
  } finally { store.close(); }
});

test("wide rowids and incompatible versions are handled without losing marks", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    dropIndex(store);
    db.exec("INSERT INTO pins(rowid,viewer,session,at) VALUES(-9007199254740993,'a','one',1),(9007199254740993,'b','two',1)");
    installArchiveMarkIndex(db);
    assert.deepEqual(archiveMarksStep(db, 1), { done: false, visited: 1 });
    assert.deepEqual(archiveMarksStep(db, 1), { done: false, visited: 1 });
    assert.deepEqual(archiveMarksStep(db, 1), { done: true, visited: 0 });
    check(store);
    db.exec("UPDATE archive_mark_meta SET version=2 WHERE kind='pins'");
    assert.throws(() => archiveMarksReady(db), /archive mark index version/i);
    assert.throws(() => archiveMarksStep(db), /archive mark index version/i);
  } finally { store.close(); }
});
