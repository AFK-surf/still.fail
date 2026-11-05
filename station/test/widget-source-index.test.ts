import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants, DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { installWidgetSources, WIDGET_SOURCE, WIDGET_SOURCE_POSITIONS_FIRST, WIDGET_SOURCE_POSITIONS_NEXT, widgetSourcesReady, widgetSourcesStep } from "../src/store/widget-sources.ts";

const original = `SELECT t.channel, t.thread_ts, json_extract(a.value, '$.name') AS name FROM merged m
  JOIN threads t ON t.id = m.thread JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = ?1, json_each(m.attachments) a
  WHERE m.attachments IS NOT NULL AND json_extract(a.value, '$.path') = ?2 ORDER BY m.created_at DESC LIMIT 1`;
const plain = (row: unknown) => row === undefined ? null : { ...(row as object) };
const beforeIndex = (db: DatabaseSync) => db.exec(`
  DROP TRIGGER widget_source_before_add; DROP TRIGGER widget_source_add; DROP TRIGGER widget_source_fast_add;
  DROP TRIGGER widget_source_before_change; DROP TRIGGER widget_source_change;
  DROP TRIGGER widget_source_drop; DROP TRIGGER widget_source_drop_thread;
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
      assert.equal(widgetSourcesStep(db, first).done, true);
      assert.equal(widgetSourcesStep(db, second).done, true);
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
  for (const alias of ["rowid", "_rowid_", "oid"]) {
    test(`replacing an entry by ${alias} removes its former widget source (recursive triggers ${recursive})`, () => {
      const store = Store.open(":memory:"), db = store.db;
      try {
        db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
        const first = store.openThread("ember", "EMBER", "first", null, null).id;
        const second = store.openThread("ember", "EMBER", "second", null, null).id;
        widgetSourcesStep(db, first); widgetSourcesStep(db, second);
        store.joinThread(first, "a", "ember"); store.joinThread(second, "a", "ember");
        const path = "/w/item.html", files = (name: string) => JSON.stringify([{ path, name }]);
        const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,attachments)
          VALUES(?,1,'message','agent','a',?,?)`);
        put.run(first, 10, files("first")); put.run(second, 20, files("second"));
        const target = (db.prepare("SELECT rowid FROM entries WHERE thread=? AND n=1").get(second) as { rowid: number }).rowid;
        db.prepare(`UPDATE OR REPLACE entries SET ${alias}=? WHERE thread=? AND n=1`).run(target, first);
        assert.deepEqual(plain(db.prepare(WIDGET_SOURCE).get("a", path)), plain(db.prepare(original).get("a", path)));
      } finally { store.close(); }
    });
  }
  test(`an unrequested thread replacing a tracked row keeps the source exact (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      const tracked = store.openThread("ember", "EMBER", "tracked", null, null).id;
      const other = store.openThread("ember", "EMBER", "other", null, null).id;
      widgetSourcesStep(db, tracked);
      store.joinThread(tracked, "a", "ember");
      const path = "/w/item.html", files = JSON.stringify([{ path, name: "tracked" }]);
      db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,attachments)
        VALUES(?,1,'message','agent','a',1,?)`).run(tracked, files);
      const rowid = (db.prepare("SELECT rowid FROM entries WHERE thread=? AND n=1").get(tracked) as { rowid: number }).rowid;
      // IGNORE may leave a stage; the next unrelated write must clear it without losing the tracked source.
      db.prepare(`INSERT OR IGNORE INTO entries(rowid,thread,n,kind,author_kind,author,at,attachments)
        VALUES(?, ?,2,'message','agent','a',2,'[]')`).run(rowid, other);
      db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,attachments)
        VALUES(?,3,'message','agent','a',3,'[]')`).run(other);
      assert.deepEqual(plain(db.prepare(WIDGET_SOURCE).get("a", path)), plain(db.prepare(original).get("a", path)));
      db.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,kind,author_kind,author,at,attachments)
        VALUES(?, ?,4,'message','agent','a',4,'[]')`).run(rowid, other);
      assert.deepEqual(plain(db.prepare(WIDGET_SOURCE).get("a", path)), plain(db.prepare(original).get("a", path)));
    } finally { store.close(); }
  });
  test(`widget sources agree with the original after mixed writes (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      const threads = ["one", "two", "unrequested"].map((name) => store.openThread("ember", "EMBER", name, null, null).id);
      for (const thread of threads.slice(0, 2)) { widgetSourcesStep(db, thread); store.joinThread(thread, "a", "ember"); }
      const paths = ["/w/one", "/w/two", "/w/three"];
      let seed = 71239;
      const next = (max: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % max; };
      const files = () => next(4) === 0 ? "[]" : JSON.stringify([{ path: paths[next(paths.length)], name: `n${next(9)}` }]);
      const insert = db.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,kind,target,ts,author_kind,author,at,attachments)
        VALUES(?,?,?,?,?,?,'agent','a',?,?)`);
      const ignore = db.prepare(`INSERT OR IGNORE INTO entries(rowid,thread,n,kind,target,ts,author_kind,author,at,attachments)
        VALUES(?,?,?,?,?,?,'agent','a',?,?)`);
      const update = db.prepare(`UPDATE OR REPLACE entries SET rowid=?,thread=?,n=?,kind=?,target=?,ts=?,at=?,attachments=? WHERE rowid=?`);
      for (let step = 0; step < 100; step++) {
        const current = db.prepare("SELECT rowid FROM entries ORDER BY rowid").all() as { rowid: number }[];
        const action = current.length === 0 ? 0 : next(4);
        if (action === 3) {
          db.prepare("DELETE FROM entries WHERE rowid=?").run(current[next(current.length)]!.rowid);
        } else {
          const kind = next(3) === 0 ? "edit" : "message";
          const args = [next(25) + 1, threads[next(threads.length)]!, next(16) - 3, kind,
            kind === "edit" ? next(16) - 3 : null, next(4) === 0 ? `ts-${next(8)}` : null, next(20), files()] as const;
          if (action === 2) update.run(...args, current[next(current.length)]!.rowid);
          else (action === 1 ? ignore : insert).run(...args);
        }
        for (const path of paths)
          assert.deepEqual(plain(db.prepare(WIDGET_SOURCE).get("a", path)), plain(db.prepare(original).get("a", path)), `step ${step}, ${path}`);
      }
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

test("old widget preparation skips edits that are not messages", () => {
  const visited = (edits: number) => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      beforeIndex(db);
      const thread = store.openThread("ember", "EMBER", "edits", null, null).id;
      const files = JSON.stringify([{ path: "/w/item", name: "item" }]);
      const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,at,attachments)
        VALUES(?,?,?,?,'agent','a',?,?)`);
      put.run(thread, 1, "message", null, 1, files);
      for (let n = 2; n <= edits + 1; n++) put.run(thread, n, "edit", 1, n, files);
      installWidgetSources(db);
      let total = 0;
      for (;;) {
        const result = widgetSourcesStep(db, thread, 16);
        total += result.visited;
        if (result.done) return total;
      }
    } finally { store.close(); }
  };
  assert.deepEqual([visited(40), visited(400)], [1, 1]);
});

for (const missing of [null, "entries_said", "entries_letters"] as const) test(`old widget preparation orders message numbers numerically across batches${missing ? ` without ${missing}` : ""}`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    beforeIndex(db);
    const thread = store.openThread("ember", "EMBER", "numbered", null, null).id;
    store.joinThread(thread, "a", "ember");
    const path = "/w/item.html";
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,attachments)
      VALUES(?,?,'message','agent','a',?,?)`);
    for (let n = 1; n <= 15; n++) {
      const files = n === 2 || n === 9 ? JSON.stringify([{ path, name: `source-${n}` }]) : "[]";
      put.run(thread, n, n, files);
    }
    if (missing) db.exec(`DROP INDEX ${missing}`);
    installWidgetSources(db);
    while (!widgetSourcesStep(db, thread, 3).done) {}
    assert.deepEqual(plain(db.prepare(WIDGET_SOURCE).get("a", path)), plain(db.prepare(original).get("a", path)));
    assert.equal((db.prepare(WIDGET_SOURCE).get("a", path) as { name: string }).name, "source-9");
  } finally { store.close(); }
});

test("old widget preparation seeks the ordinary and legacy message indexes", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    for (const [sql, args] of [
      [WIDGET_SOURCE_POSITIONS_FIRST, [1, "100", 2]],
      [WIDGET_SOURCE_POSITIONS_NEXT, [1, "1", "100", 2]],
    ] as const) {
      const plan = (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((row) => row.detail).join("\n");
      assert.match(plan, /SEARCH entries USING (?:COVERING )?INDEX entries_said \(thread=\?/);
      assert.match(plan, /SEARCH entries USING (?:COVERING )?INDEX entries_letters \(thread=\?/);
    }
  } finally { store.close(); }
});

for (const missing of [null, "entries_said", "entries_letters"] as const) {
  test(`old widget preparation keeps ordinary and letter messages${missing ? ` without ${missing}` : ""}`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      beforeIndex(db);
      const thread = store.openThread("ember", "EMBER", "old-letters", null, null).id;
      store.joinThread(thread, "a", "ember");
      const path = "/w/item.html", files = (name: string) => JSON.stringify([{ path, name }]);
      const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,at,attachments,letter)
        VALUES(?,?,?,?,'agent','a',?,?,?)`);
      put.run(thread, 1, "message", null, 1, files("ordinary"), null);
      put.run(thread, 2, "edit", 1, 2, files("edited"), null);
      put.run(thread, 3, "message", null, 3, files("letter"), "{}");
      put.run(thread, 4, "edit", 3, 4, files("letter edited"), "{}");
      put.run(thread, 5, "message", null, 5, "[]", null);
      if (missing) db.exec(`DROP INDEX ${missing}`);
      installWidgetSources(db);
      let batches = 0;
      for (;;) {
        const result = widgetSourcesStep(db, thread, 2);
        assert.ok(result.visited <= 2);
        batches++;
        if (result.done) break;
        assert.ok(batches < 10);
      }
      assert.deepEqual(plain(db.prepare(WIDGET_SOURCE).get("a", path)), plain(db.prepare(original).get("a", path)));
      assert.equal((db.prepare(WIDGET_SOURCE).get("a", path) as { name: string }).name, "letter edited");
    } finally { store.close(); }
  });
}

test("an edit that leaves the effective files unchanged does not rewrite them", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installWidgetSources(db);
    const thread = store.openThread("ember", "EMBER", "same", null, null).id;
    assert.equal(widgetSourcesStep(db, thread).done, true);
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

test("a message inserted after its edit is indexed with that edit's files", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "late-message", null, null).id;
    widgetSourcesStep(db, thread);
    store.joinThread(thread, "a", "ember");
    const path = "/w/item.html", files = JSON.stringify([{ path, name: "edited" }]);
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,at,attachments)
      VALUES(?,?,?,?,'agent','a',?,?)`);
    put.run(thread, 10, "edit", 1, 10, files);
    put.run(thread, 1, "message", null, 1, "[]");
    assert.deepEqual(plain(db.prepare(WIDGET_SOURCE).get("a", path)), plain(db.prepare(original).get("a", path)));
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
    put.run(thread, "-9223372036854775808", 1, "[]");
    put.run(thread, "9223372036854775807", 2, files);
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

test("a writer between the old-position read and batch commit cannot be missed", () => {
  const dir = mkdtempSync(join(tmpdir(), "widget-step-race-")), path = join(dir, "station.db");
  const store = Store.open(path), db = store.db;
  let other: DatabaseSync | null = null;
  try {
    beforeIndex(db);
    const thread = store.openThread("ember", "EMBER", "race", null, null).id;
    store.joinThread(thread, "a", "ember");
    const pathName = "/w/item.html", files = (name: string) => JSON.stringify([{ path: pathName, name }]);
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,attachments)
      VALUES(?,1,'message','agent','a',1,?)`).run(thread, files("old"));
    installWidgetSources(db);
    other = new DatabaseSync(path);
    let wrote = false;
    const watched = new Proxy(db, {
      get(target, key) {
        if (key === "prepare") return (sql: string) => {
          const statement = target.prepare(sql);
          if (!sql.startsWith("SELECT CAST(n AS TEXT) AS n FROM")) return statement;
          return new Proxy(statement, {
            get(s, name) {
              if (name === "all") return (...args: Parameters<typeof s.all>) => {
                const rows = s.all(...args);
                if (!wrote) {
                  wrote = true;
                  other!.prepare("UPDATE entries SET at=100,attachments=? WHERE thread=? AND n=1").run(files("changed"), thread);
                  other!.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,attachments)
                    VALUES(?,-1,'message','agent','a',200,?)`).run(thread, files("behind"));
                }
                return rows;
              };
              const value = Reflect.get(s, name, s);
              return typeof value === "function" ? value.bind(s) : value;
            },
          });
        };
        const value = Reflect.get(target, key, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    }) as DatabaseSync;
    assert.equal(widgetSourcesStep(watched, thread, 4).done, true);
    assert.equal(wrote, true);
    assert.deepEqual(plain(db.prepare(WIDGET_SOURCE).get("a", pathName)), plain(db.prepare(original).get("a", pathName)));
  } finally { other?.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a delivery reads all widget sources from one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "widget-snapshot-")), path = join(dir, "station.db");
  const store = Store.open(path), db = store.db, other = new DatabaseSync(path);
  try {
    const thread = store.openThread("ember", "EMBER", "snapshot", null, null).id;
    widgetSourcesStep(db, thread);
    store.joinThread(thread, "a", "ember");
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,attachments)
      VALUES(?,?,'message','agent','a',?,?)`);
    const files = (name: string, file: string) => JSON.stringify([{ name, path: file }]);
    put.run(thread, 1, 10, files("first", "/w/first"));
    put.run(thread, 2, 20, files("old", "/w/second"));
    store.putWidgetState("a", "/w/first", "{}", "1");
    store.putWidgetState("a", "/w/second", "{}", "2");
    let wrote = false;
    db.function("during_widget_read", (name) => {
      if (!wrote) {
        wrote = true;
        other.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,attachments)
          VALUES(?,3,'message','agent','a',30,?)`).run(thread, files("new", "/w/second"));
      }
      return name;
    });
    db.exec(`ALTER TABLE widget_source_rows RENAME TO widget_source_rows_test;
      CREATE VIEW widget_source_rows AS SELECT thread,n,slot,path,at,during_widget_read(name) AS name FROM widget_source_rows_test;`);
    assert.deepEqual(store.untoldWidgetModels("a").map((row) => row.name), ["first", "old"]);
    assert.deepEqual(store.untoldWidgetModels("a").map((row) => row.name), ["first", "new"]);
  } finally { other.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a bad attachment does not make a message write fail", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installWidgetSources(db);
    const thread = store.openThread("ember", "EMBER", "bad", null, null).id;
    assert.equal(widgetSourcesStep(db, thread).done, true);
    store.joinThread(thread, "a", "ember");
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at,attachments) VALUES(?,1,'message','agent','a',1,?)")
      .run(thread, "not json");
    assert.ok(db.prepare("SELECT 1 FROM widget_source_invalid WHERE thread=? AND n=1").get(thread));
    store.putWidgetState("a", "/w/item.html", "{}", "selected");
    assert.throws(() => store.untoldWidgetModels("a"), /malformed JSON/);
    db.prepare("UPDATE entries SET attachments='[]' WHERE thread=? AND n=1").run(thread);
    assert.deepEqual(store.untoldWidgetModels("a"), [{ path: "/w/item.html", name: "item.html", thread: null, model: "selected" }]);
  } finally { store.close(); }
});

test("a noncanonical attachment that SQLite can read keeps its original widget source", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "json5", null, null).id;
    widgetSourcesStep(db, thread);
    store.joinThread(thread, "a", "ember");
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,attachments)
      VALUES(?,1,'message','agent','a',1,?)`).run(thread, "[{path:'/w/item.html',name:'json5.html'}]");
    const path = "/w/item.html", expected = plain(db.prepare(original).get("a", path));
    assert.deepEqual(expected, { channel: "EMBER", thread_ts: "json5", name: "json5.html" });
    store.putWidgetState("a", path, "{}", "selected");
    assert.equal(store.untoldWidgetModels("a")[0]?.name, "json5.html");
  } finally { store.close(); }
});

test("a failed widget index installation leaves no partial tables or triggers", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    beforeIndex(db);
    db.setAuthorizer((action, name) => action === constants.SQLITE_INSERT && name === "widget_source_meta"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    assert.throws(() => installWidgetSources(db));
    db.setAuthorizer(null);
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name LIKE 'widget_source_%'").get(), undefined);
    installWidgetSources(db);
  } finally { db.setAuthorizer(null); store.close(); }
});

test("widget source ties follow the original membership and attachment order", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const first = store.openThread("ember", "EMBER", "first", null, null).id;
    const second = store.openThread("ember", "EMBER", "second", null, null).id;
    widgetSourcesStep(db, first); widgetSourcesStep(db, second);
    store.joinThread(second, "a", "ember"); store.joinThread(first, "a", "ember");
    const path = "/w/item.html", put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,attachments)
      VALUES(?,?,'message','agent','a',5,?)`);
    put.run(first, 1, JSON.stringify([{ path, name: "first" }, { path, name: "duplicate" }]));
    put.run(second, 1, JSON.stringify([{ path, name: "second" }]));
    const check = () => assert.deepEqual(plain(db.prepare(WIDGET_SOURCE).get("a", path)), plain(db.prepare(original).get("a", path)));
    check();
    db.prepare("DELETE FROM thread_sessions WHERE thread=? AND session='a'").run(second);
    check();
  } finally { store.close(); }
});

test("a failed widget source batch rolls back its rows and cursor", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    beforeIndex(db);
    const thread = store.openThread("ember", "EMBER", "rollback", null, null).id;
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,attachments)
      VALUES(?,?,'message','agent','a',?,?)`);
    for (const n of [1, 2]) put.run(thread, n, n, JSON.stringify([{ path: `/w/${n}`, name: String(n) }]));
    installWidgetSources(db);
    db.exec("CREATE TRIGGER fail_widget_batch BEFORE INSERT ON widget_source_rows WHEN NEW.n=2 BEGIN SELECT RAISE(ABORT,'failed batch'); END");
    assert.throws(() => widgetSourcesStep(db, thread, 4), /failed batch/);
    assert.equal(db.prepare("SELECT count(*) AS n FROM widget_source_rows").get()?.n, 0);
    assert.deepEqual(plain(db.prepare("SELECT last_n,complete FROM widget_source_scopes WHERE thread=?").get(thread)),
      { last_n: null, complete: 0 });
    db.exec("DROP TRIGGER fail_widget_batch");
    assert.deepEqual(widgetSourcesStep(db, thread, 4), { done: true, visited: 2 });
    assert.equal(db.prepare("SELECT count(*) AS n FROM widget_source_rows").get()?.n, 2);
  } finally { store.close(); }
});

test("an incompatible widget index is neither read nor prepared", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "version", null, null).id;
    store.joinThread(thread, "a", "ember");
    store.putWidgetState("a", "/w/item.html", "{}", "selected");
    db.exec("UPDATE widget_source_meta SET version=2");
    assert.throws(() => widgetSourcesStep(db, thread), /widget source.*version/i);
    assert.throws(() => store.untoldWidgetModels("a"), /widget source.*version/i);
  } finally { store.close(); }
});
