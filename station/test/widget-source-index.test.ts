import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { installWidgetSources, WIDGET_SOURCE, widgetSourcesReady, widgetSourcesStep } from "../src/store/widget-sources.ts";

const original = `SELECT t.channel, t.thread_ts, json_extract(a.value, '$.name') AS name FROM merged m
  JOIN threads t ON t.id = m.thread JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = ?1, json_each(m.attachments) a
  WHERE m.attachments IS NOT NULL AND json_extract(a.value, '$.path') = ?2 ORDER BY m.created_at DESC LIMIT 1`;
const plain = (row: unknown) => row === undefined ? null : { ...(row as object) };
const beforeIndex = (db: DatabaseSync) => db.exec(`
  DROP TRIGGER widget_source_before_add; DROP TRIGGER widget_source_add;
  DROP TRIGGER widget_source_before_change; DROP TRIGGER widget_source_change;
  DROP TRIGGER widget_source_drop; DROP TRIGGER widget_source_new_thread; DROP TRIGGER widget_source_drop_thread;
  DROP TABLE widget_source_rows; DROP TABLE widget_source_invalid;
  DROP TABLE widget_source_changed; DROP TABLE widget_source_scopes; DROP TABLE widget_source_meta;
`);

for (const recursive of [false, true]) {
  test(`widget sources follow replacements and edits (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      installWidgetSources(db);
      db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      const first = store.openThread("ember", "EMBER", "first", null, null).id;
      const second = store.openThread("ember", "EMBER", "second", null, null).id;
      store.joinThread(first, "a", "ember");
      store.joinThread(second, "a", "ember");
      const path = "/w/item.html", files = (name: string) => JSON.stringify([{ path, name }]);
      const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,ts,author_kind,author,at,attachments)
        VALUES(?,?,?,?,?,'agent','a',?,?)`);
      const replace = db.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,kind,target,ts,author_kind,author,at,attachments)
        VALUES(?,?,?,?,?,?,'agent','a',?,?)`);
      const check = () => assert.deepEqual(plain(db.prepare(WIDGET_SOURCE).get("a", path)), plain(db.prepare(original).get("a", path)));
      put.run(first, 1, "message", null, "first", 20, files("first")); check();
      put.run(second, 1, "message", null, "second", 40, files("second")); check();
      put.run(second, 2, "edit", 1, null, 50, "[]"); check();
      put.run(first, 2, "edit", 1, null, 60, files("updated")); check();
      put.run(first, 3, "edit", 1, null, 70, files("updated")); check();
      db.prepare("UPDATE entries SET attachments=? WHERE thread=? AND n=?").run(files("back"), second, 2); check();
      const rowid = (db.prepare("SELECT rowid FROM entries WHERE thread=? AND n=1").get(first) as { rowid: number }).rowid;
      replace.run(rowid, second, 4, "message", null, "replaced", 100, files("replacement")); check();
      replace.run(12345, second, 5, "message", null, "second", 90, files("same-ts")); check();
      db.prepare("DELETE FROM entries WHERE thread=? AND n=?").run(second, 5); check();
      db.prepare("DELETE FROM entries WHERE thread=? AND n=?").run(second, 2); check();
      db.prepare("DELETE FROM thread_sessions WHERE thread=? AND session='a'").run(second); check();
    } finally { store.close(); }
  });
}

test("old widget sources are built in bounded batches while messages change", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    beforeIndex(db);
    const thread = store.openThread("ember", "EMBER", "old", null, null).id;
    store.joinThread(thread, "a", "ember");
    const path = "/w/item.html", files = (name: string) => JSON.stringify([{ path, name }]);
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,at,attachments)
      VALUES(?,?,?,?,'agent','a',?,?)`);
    put.run(thread, 1, "message", null, 1, files("before"));
    for (let n = 2; n <= 12; n++) put.run(thread, n, "message", null, n, "[]");
    installWidgetSources(db);
    assert.equal(widgetSourcesReady(db, thread), false);
    assert.deepEqual(widgetSourcesStep(db, thread, 3), { done: false, visited: 3 });
    // A new message inserted behind the cursor must be indexed by its writer, not missed by preparation.
    put.run(thread, -2, "message", null, 99, files("inserted behind"));
    put.run(thread, 13, "edit", 1, 13, files("edited"));
    db.prepare("UPDATE entries SET attachments=? WHERE thread=? AND n=?").run(files("late"), thread, 10);
    for (;;) {
      const result = widgetSourcesStep(db, thread, 3);
      assert.ok(result.visited <= 3);
      if (result.done) break;
    }
    assert.equal(widgetSourcesReady(db, thread), true);
    assert.deepEqual(plain(db.prepare(WIDGET_SOURCE).get("a", path)), plain(db.prepare(original).get("a", path)));
  } finally { store.close(); }
});

test("an edit that leaves the effective files unchanged does not rewrite them", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installWidgetSources(db);
    const thread = store.openThread("ember", "EMBER", "same", null, null).id;
    const files = JSON.stringify([{ path: "/w/item.html", name: "item" }]);
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,at,attachments)
      VALUES(?,?,?,?,'agent','a',?,?)`);
    put.run(thread, 1, "message", null, 1, files);
    db.exec(`CREATE TEMP TABLE source_writes (n INTEGER NOT NULL);
      CREATE TEMP TRIGGER source_insert AFTER INSERT ON widget_source_rows BEGIN INSERT INTO source_writes VALUES (1); END;
      CREATE TEMP TRIGGER source_delete AFTER DELETE ON widget_source_rows BEGIN INSERT INTO source_writes VALUES (1); END;`);
    put.run(thread, 2, "edit", 1, 2, files);
    assert.equal((db.prepare("SELECT count(*) AS n FROM source_writes").get() as { n: number }).n, 0);
  } finally { store.close(); }
});

test("old message numbers beyond JavaScript's safe integers are prepared without loss", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    beforeIndex(db);
    const thread = store.openThread("ember", "EMBER", "wide", null, null).id;
    store.joinThread(thread, "a", "ember");
    const path = "/w/item.html", files = JSON.stringify([{ path, name: "wide" }]);
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,attachments)
      VALUES(?,CAST(? AS INTEGER),'message','agent','a',?,?)`);
    put.run(thread, "-9007199254740993", 1, "[]");
    put.run(thread, "9007199254740993", 2, files);
    installWidgetSources(db);
    assert.deepEqual(widgetSourcesStep(db, thread, 1), { done: false, visited: 1 });
    assert.deepEqual(widgetSourcesStep(db, thread, 1), { done: false, visited: 1 });
    assert.deepEqual(widgetSourcesStep(db, thread, 1), { done: true, visited: 0 });
    assert.deepEqual(plain(db.prepare(WIDGET_SOURCE).get("a", path)), plain(db.prepare(original).get("a", path)));
  } finally { store.close(); }
});

test("another connection's writes remain exact during and after old-thread preparation", () => {
  const dir = mkdtempSync(join(tmpdir(), "widget-writers-")), path = join(dir, "station.db");
  const store = Store.open(path), db = store.db;
  let other: DatabaseSync | null = null;
  try {
    beforeIndex(db);
    const thread = store.openThread("ember", "EMBER", "writers", null, null).id;
    store.joinThread(thread, "a", "ember");
    const pathName = "/w/item.html", files = (name: string) => JSON.stringify([{ path: pathName, name }]);
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,at,attachments)
      VALUES(?,?,?,?,'agent','a',?,?)`);
    put.run(thread, 1, "message", null, 1, files("first"));
    for (let n = 2; n <= 8; n++) put.run(thread, n, "message", null, n, "[]");
    installWidgetSources(db);
    other = new DatabaseSync(path);
    assert.equal(widgetSourcesStep(db, thread, 2).done, false);
    other.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,at,attachments)
      VALUES(?,9,'edit',1,'agent','a',9,?)`).run(thread, files("edited"));
    while (!widgetSourcesStep(db, thread, 2).done) {}
    const check = () => assert.deepEqual(plain(db.prepare(WIDGET_SOURCE).get("a", pathName)),
      plain(db.prepare(original).get("a", pathName)));
    check();
    other.prepare(`INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,at,attachments)
      VALUES(?,8,'message','agent','a',100,?)`).run(thread, files("newest"));
    check();
    other.prepare("DELETE FROM entries WHERE thread=? AND n=8").run(thread);
    check();
  } finally { other?.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a bad attachment does not make a message write fail", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installWidgetSources(db);
    const thread = store.openThread("ember", "EMBER", "bad", null, null).id;
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at,attachments) VALUES(?,1,'message','agent','a',1,?)")
      .run(thread, "not json");
    assert.ok(db.prepare("SELECT 1 FROM widget_source_invalid WHERE thread=? AND n=1").get(thread));
  } finally { store.close(); }
});
