import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { installWidgetSources, WIDGET_SOURCE, widgetSourcesReady, widgetSourcesStep } from "../src/store/widget-sources.ts";

const original = `SELECT t.channel, t.thread_ts, json_extract(a.value, '$.name') AS name FROM merged m
  JOIN threads t ON t.id = m.thread JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = ?1, json_each(m.attachments) a
  WHERE m.attachments IS NOT NULL AND json_extract(a.value, '$.path') = ?2 ORDER BY m.created_at DESC LIMIT 1`;
const plain = (row: unknown) => row === undefined ? null : { ...(row as object) };

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
