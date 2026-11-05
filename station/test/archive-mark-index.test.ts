import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync, constants } from "node:sqlite";
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

for (const recursive of [false, true]) for (const alias of ["rowid", "_rowid_", "oid"]) {
  test(`replacing old marks by ${alias} leaves both lookups exact (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
      db.exec("INSERT INTO pins(rowid,viewer,session,at) VALUES(1,'a','one',1),(2,'b','two',1),(3,'c','one',1)");
      db.exec("INSERT INTO kept_chats(rowid,viewer,thread) VALUES(1,'a',1),(2,'b',2),(3,'c',1)");
      db.exec(`UPDATE OR REPLACE pins SET ${alias}=2,viewer='c',session='one' WHERE rowid=1`);
      db.exec(`UPDATE OR REPLACE kept_chats SET ${alias}=2,viewer='c',thread=1 WHERE rowid=1`);
      check(store);
      db.exec(`INSERT OR REPLACE INTO pins(${alias},viewer,session,at) VALUES(2,'b','two',1)`);
      db.exec(`INSERT OR REPLACE INTO kept_chats(${alias},viewer,thread) VALUES(2,'b',2)`);
      check(store);
    } finally { store.close(); }
  });
}

test("ignored mark writes leave the next changes and lookups exact", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec("INSERT INTO pins(rowid,viewer,session,at) VALUES(1,'a','one',1),(2,'b','two',1)");
    db.exec("INSERT INTO kept_chats(rowid,viewer,thread) VALUES(1,'a',1),(2,'b',2)");
    db.exec("INSERT OR IGNORE INTO pins(viewer,session,at) VALUES('a','one',2)");
    db.exec("INSERT OR IGNORE INTO kept_chats(viewer,thread) VALUES('a',1)");
    db.exec("UPDATE OR IGNORE pins SET rowid=2,viewer='b',session='two' WHERE rowid=1");
    db.exec("UPDATE OR IGNORE kept_chats SET rowid=2,viewer='b',thread=2 WHERE rowid=1");
    check(store);
    db.exec("DELETE FROM pins WHERE rowid=2; DELETE FROM kept_chats WHERE rowid=2");
    db.exec("INSERT INTO pins(rowid,viewer,session,at) VALUES(2,'c','three',1)");
    db.exec("INSERT INTO kept_chats(rowid,viewer,thread) VALUES(2,'c',3)");
    check(store);
  } finally { store.close(); }
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

test("another connection's old writes stay exact during and after mark preparation", () => {
  const dir = mkdtempSync(join(tmpdir(), "archive-mark-writers-")), path = join(dir, "station.db");
  const store = Store.open(path), db = store.db, old = new DatabaseSync(path);
  try {
    dropIndex(store);
    db.exec("INSERT INTO pins(rowid,viewer,session,at) VALUES(1,'a','one',1),(2,'b','two',1),(3,'c','three',1)");
    db.exec("INSERT INTO kept_chats(rowid,viewer,thread) VALUES(1,'a',1),(2,'b',2),(3,'c',3)");
    installArchiveMarkIndex(db);
    assert.deepEqual(archiveMarksStep(db, 1), { done: false, visited: 1 });
    old.exec("UPDATE OR REPLACE kept_chats SET rowid=-30,thread=4 WHERE viewer='b'; DELETE FROM kept_chats WHERE viewer='a'");
    old.exec("UPDATE OR REPLACE pins SET rowid=1000,session='four' WHERE viewer='b'; DELETE FROM pins WHERE viewer='a'");
    old.exec("INSERT INTO pins(viewer,session,at) VALUES('d','new',1); INSERT INTO kept_chats(viewer,thread) VALUES('d',5)");
    while (!archiveMarksReady(db)) assert.ok(archiveMarksStep(db, 1).visited <= 1);
    check(store);
    old.exec("DELETE FROM pins WHERE viewer='c'; DELETE FROM kept_chats WHERE viewer='c'");
    old.exec("INSERT OR REPLACE INTO pins(viewer,session,at) VALUES('d','new',2); UPDATE kept_chats SET thread=6 WHERE viewer='d'");
    check(store);
    assert.equal(store.archiveMarks().pinned("four"), true);
    assert.equal(store.archiveMarks().pinned("three"), false);
    assert.equal(store.archiveMarks().kept(6), true);
    assert.equal(store.archiveMarks().kept(3), false);
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a failed version marker leaves no partially installed archive mark lookup", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    dropIndex(store);
    db.setAuthorizer((action, name) => action === constants.SQLITE_INSERT && name === "archive_mark_meta"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    assert.throws(() => installArchiveMarkIndex(db));
    db.setAuthorizer(null);
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name LIKE 'archive_pin_%' OR name LIKE 'archive_keep_%' OR name='archive_mark_meta'").get(), undefined);
    installArchiveMarkIndex(db);
    assert.equal(archiveMarksReady(db), true);
  } finally { db.setAuthorizer(null); store.close(); }
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
