import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { makeStore, messagesBefore, MESSAGES_FROM_KEYS } from "../src/read/store.ts";
import { installLegacyEdits, legacyEditDrain, legacyEditStep } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { toMessage } from "../src/store/rows.ts";
import { Store } from "../src/store/store.ts";

function oldPage(size: number, path = ":memory:") {
  const store = Store.open(path), db = store.db;
  const thread = store.openThread("ember", "CHAT", `old-page-${size}`, null, null).id;
  db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
  const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
    VALUES(?,?,?,?,'agent','worker',?,?)`);
  put.run(thread, 1, "message", null, "first", 1);
  put.run(thread, 2, "message", null, "second", 2);
  put.run(thread, 3, "edit", 1, "first edited", 3);
  db.exec("BEGIN");
  for (let n = 4; n <= size + 3; n++) put.run(thread, n, "edit", n + 1000, `other-${n}`, n);
  db.exec("COMMIT");
  installLegacyEdits(db);
  addClientColumn(db);
  return { store, db, thread };
}

test("an old message page waits for bounded edit preparation and retains its exact messages", () => {
  for (const size of [80, 800]) {
    const { store, db, thread } = oldPage(size);
    try {
      const expected = db.prepare("SELECT * FROM merged WHERE thread=? ORDER BY n").all(thread).map(toMessage);
      const reader = makeStore(db, "/unused");
      assert.throws(() => messagesBefore(reader, thread, null, 2), { status: 503, message: "legacy edit lookup pending" });
      while (!legacyEditStep(db).ready) { /* prepare */ }
      while (legacyEditDrain(db) > 0) { /* reconcile */ }
      assert.deepEqual(messagesBefore(reader, thread, null, 2), expected);
      assert.deepEqual(messagesBefore(reader, thread, 2, 1), expected.slice(0, 1));
    } finally { store.close(); }
  }
});

test("a short page remains readable while another old chat is being prepared", () => {
  const { store, db } = oldPage(800);
  try {
    const thread = store.openThread("ember", "CHAT", "short-old-page", null, null).id;
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?,?,?,'agent','worker',?,?)`);
    put.run(thread, 1, "message", null, "before", 1);
    put.run(thread, 2, "message", null, "next", 2);
    put.run(thread, 3, "edit", 1, "after", 3);
    const expected = db.prepare("SELECT * FROM merged WHERE thread=? ORDER BY n").all(thread).map(toMessage);
    const reader = makeStore(db, "/unused");
    assert.deepEqual(messagesBefore(reader, thread, null, 2), expected);
    assert.deepEqual(messagesBefore(reader, thread, 2, 1), expected.slice(0, 1));
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
  } finally { store.close(); }
});

test("an old page preserves a recent edit with a 64-bit entry key", () => {
  const { store, db, thread } = oldPage(80);
  try {
    db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?,'edit',1,'agent','worker','large edit',100)`).run(thread, 9007199254740993n);
    assert.deepEqual(messagesBefore(makeStore(db, "/unused"), thread, 2, 1).map((m) => m.text), ["large edit"]);
  } finally { store.close(); }
});

test("an old page keeps numeric message order while edit preparation is pending", () => {
  const { store, db } = oldPage(800);
  try {
    const thread = store.openThread("ember", "CHAT", "ordered-old-page", null, null).id;
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'message','agent','worker',?,?)`);
    for (const n of [2, 10, 100]) put.run(thread, n, `message-${n}`, n);
    const reader = makeStore(db, "/unused");
    assert.deepEqual(messagesBefore(reader, thread, null, 3).map((m) => m.n), [2, 10, 100]);
    assert.deepEqual(messagesBefore(reader, thread, null, 2).map((m) => m.n), [10, 100]);
  } finally { store.close(); }
});

for (const changed of [64, 65])
  test(`a message page handles ${changed} pending edit keys`, () => {
    const { store, db, thread } = oldPage(changed);
    try {
      while (!legacyEditStep(db).ready) { /* prepare */ }
      db.prepare("UPDATE entries SET target=target+1 WHERE thread=? AND n>=4").run(thread);
      assert.equal(db.prepare("SELECT COUNT(*) AS n FROM legacy_edit_dirty").get()?.n, changed);
      const reader = makeStore(db, "/unused");
      if (changed === 64) assert.deepEqual(messagesBefore(reader, thread, null, 2).map((m) => m.text), ["first edited", "second"]);
      else assert.throws(() => messagesBefore(reader, thread, null, 2), { status: 503, message: "legacy edit lookup pending" });
      while (legacyEditDrain(db) > 0) { /* reconcile */ }
      assert.deepEqual(messagesBefore(reader, thread, null, 2).map((m) => m.text), ["first edited", "second"]);
    } finally { store.close(); }
  });

test("a page and its edit readiness use one snapshot when an old writer changes edits", () => {
  const dir = mkdtempSync(join(tmpdir(), "page-edit-snapshot-")), path = join(dir, "stillfail.db");
  const { store, db, thread } = oldPage(65, path), writer = new DatabaseSync(path);
  try {
    while (!legacyEditStep(db).ready) { /* prepare */ }
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === MESSAGES_FROM_KEYS && !changed) {
          changed = true;
          writer.prepare("UPDATE entries SET target=1 WHERE thread=? AND n>=4").run(thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const reader = makeStore(observed, dir);
    assert.deepEqual(messagesBefore(reader, thread, null, 2).map((m) => m.text), ["first edited", "second"]);
    assert.ok(changed);
    assert.throws(() => messagesBefore(reader, thread, null, 2), { status: 503, message: "legacy edit lookup pending" });
    while (legacyEditDrain(db) > 0) { /* reconcile */ }
    assert.deepEqual(messagesBefore(reader, thread, null, 2).map((m) => m.text), ["other-68", "second"]);
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("old message pages share preparation after handover, even if one reader cancels", async () => {
  const dir = mkdtempSync(join(tmpdir(), "page-edit-worker-")), path = join(dir, "stillfail.db");
  const { store, db, thread } = oldPage(150, path);
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  const controller = new AbortController();
  try {
    const args = { thread, limit: 2 };
    const abandoned = readers.read("latestMessages", args, "zh", { signal: controller.signal });
    const kept = readers.read("latestMessages", args, "zh");
    const empty = store.openThread("ember", "CHAT", "empty-page", null, null).id;
    assert.deepEqual(JSON.parse(await readers.read("latestMessages", { thread: empty, limit: 2 }, "zh")), []);
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    const messages = JSON.parse(await kept);
    assert.deepEqual(messages.map((m: { text: string }) => m.text), ["first edited", "second"]);
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
