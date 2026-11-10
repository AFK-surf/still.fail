import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PAGE_LETTER_KEYS, pageLetterGcNeedsWork, pageLetterGcStep, pageLetterReady,
  pageLetterStep } from "../src/store/page-letter-index.ts";
import { buildLegacyEntryLookups } from "../src/store/legacy-said-builder.ts";
import { Store } from "../src/store/store.ts";

const MAX = "9223372036854775807";

function make(path = ":memory:") {
  const store = Store.open(path), db = store.db;
  const thread = store.openThread("ember", "CHAT", "page-letters", null, null).id;
  const put = db.prepare(`INSERT INTO entries(thread,n,kind,letter,ts,author_kind,author,text,at)
    VALUES(?,?,?,?,?,'agent','worker','words',1)`);
  return { store, db, thread, put };
}

function finish(db: Store["db"], thread: number) {
  for (let i = 0; i < 100; i++) {
    const step = pageLetterStep(db, thread);
    assert.ok(step.visited <= 64);
    if (step.done) return;
  }
  assert.fail("letter lookup did not finish");
}

function keys(db: Store["db"], thread: number, before = MAX, limit = 100) {
  const token = pageLetterReady(db, thread);
  assert.ok(token, "the requested chat is prepared");
  return (db.prepare(PAGE_LETTER_KEYS).all(thread, token, before, limit) as { n: string }[]).map((r) => r.n);
}

for (const missingIndex of [false, true])
  test(`letter page keys are built in bounded batches${missingIndex ? " without the old index" : ""}`, () => {
    const { store, db, thread, put } = make();
    try {
      db.exec("BEGIN");
      for (let n = 1; n <= 150; n++) put.run(thread, n, n % 37 === 0 ? "message" : "edit", "old-letter", null);
      db.exec("COMMIT");
      if (missingIndex) db.exec("DROP INDEX entries_letters");
      assert.equal(pageLetterReady(db, thread), null);
      const first = pageLetterStep(db, thread);
      assert.deepEqual(first, { done: false, visited: 64 });
      // A writer can change both already visited and not-yet-visited keys while the scan is in progress.
      db.prepare("UPDATE entries SET kind='message' WHERE thread=? AND n IN (2,120)").run(thread);
      finish(db, thread);
      assert.deepEqual(keys(db, thread), ["148", "120", "111", "74", "37", "2"]);
      assert.deepEqual(keys(db, thread, "111", 2), ["74", "37"]);
    } finally { store.close(); }
  });

test("old writes, ignored inserts and replacement conflicts reconcile the actual letter messages", () => {
  const { store, db, thread, put } = make();
  try {
    put.run(thread, 1, "message", "letter", "one");
    put.run(thread, 2, "message", "letter", "two");
    put.run(thread, 3, "edit", "letter", "three");
    finish(db, thread);
    db.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,letter,author_kind,author,at)
      VALUES(?,3,'message','letter','agent','worker',1)`).run(thread);
    db.prepare(`INSERT OR REPLACE INTO entries(thread,n,kind,letter,ts,author_kind,author,at)
      VALUES(?,4,'edit','letter','one','agent','worker',1)`).run(thread);
    db.prepare(`INSERT OR REPLACE INTO entries(thread,n,kind,letter,author_kind,author,at)
      VALUES(?,2,'message',NULL,'agent','worker',1)`).run(thread);
    put.run(thread, 5, "message", "letter", "five");
    assert.deepEqual(keys(db, thread), ["5"]);
    finish(db, thread);
    assert.deepEqual(keys(db, thread), ["5"]);
  } finally { store.close(); }
});

test("a connection opened before the index tracks writes during preparation", () => {
  const dir = mkdtempSync(join(tmpdir(), "page-letter-old-writer-")), path = join(dir, "stillfail.db");
  const { store, db, thread, put } = make(path), old = new DatabaseSync(path);
  try {
    for (let n = 1; n <= 150; n++) put.run(thread, n, n === 1 ? "message" : "edit", "letter", `s${n}`);
    assert.deepEqual(pageLetterStep(db, thread), { done: false, visited: 64 });
    old.prepare("UPDATE entries SET kind='message' WHERE thread=? AND n IN (2,120)").run(thread);
    old.prepare(`INSERT OR REPLACE INTO entries(thread,n,kind,letter,ts,author_kind,author,at)
      VALUES(?,151,'edit','letter','s1','agent','worker',1)`).run(thread);
    finish(db, thread);
    assert.deepEqual(keys(db, thread), ["120", "2"]);
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("nested writes and a replacement by rowid keep both chats' keys current", () => {
  const { store, db, thread, put } = make();
  try {
    const other = store.openThread("ember", "CHAT", "other-page-letters", null, null).id;
    put.run(thread, 1, "message", "letter", "one");
    put.run(other, 9, "message", "letter", "nine");
    finish(db, thread); finish(db, other);
    db.exec(`CREATE TRIGGER test_nested_page AFTER INSERT ON entries WHEN NEW.n=10 BEGIN
      UPDATE entries SET kind='edit' WHERE thread=NEW.thread AND n=1;
    END`);
    put.run(thread, 10, "message", "letter", "ten");
    const row = db.prepare("SELECT rowid AS id FROM entries WHERE thread=? AND n=9").get(other) as { id: number };
    db.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,kind,letter,author_kind,author,at)
      VALUES(?,? ,11,'message','letter','agent','worker',1)`).run(row.id, thread);
    assert.deepEqual(keys(db, thread), ["11", "10"]);
    assert.deepEqual(keys(db, other), []);
  } finally { store.close(); }
});

test("one replacement marks every row displaced by n, ts and rowid", () => {
  const { store, db, thread, put } = make();
  try {
    const other = store.openThread("ember", "CHAT", "replace-victim", null, null).id;
    put.run(thread, 1, "message", "letter", "one");
    put.run(thread, 2, "message", "letter", "two");
    put.run(other, 3, "message", "letter", "three");
    finish(db, thread); finish(db, other);
    const row = db.prepare("SELECT rowid AS id FROM entries WHERE thread=? AND n=3").get(other) as { id: number };
    db.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,kind,letter,ts,author_kind,author,at)
      VALUES(?,?,1,'edit','letter','two','agent','worker',1)`).run(row.id, thread);
    assert.deepEqual(keys(db, thread), []);
    assert.deepEqual(keys(db, other), []);
  } finally { store.close(); }
});

test("a large changed-key backlog is left to bounded reconciliation", () => {
  const { store, db, thread, put } = make();
  try {
    finish(db, thread);
    db.exec("BEGIN");
    for (let n = 1; n <= 65; n++) put.run(thread, n, "message", "letter", null);
    db.exec("COMMIT");
    assert.equal(pageLetterReady(db, thread), null);
    const step = pageLetterStep(db, thread);
    assert.deepEqual(step, { done: true, visited: 64 });
    assert.equal(keys(db, thread).length, 65);
  } finally { store.close(); }
});

test("64-bit letter keys stay numeric and retain their exact value", () => {
  const { store, db, thread } = make();
  try {
    db.prepare(`INSERT INTO entries(thread,n,kind,letter,author_kind,author,at)
      VALUES(?,9007199254740993,'message','letter','agent','worker',1),
            (?,9007199254740995,'message','letter','agent','worker',1)`).run(thread, thread);
    finish(db, thread);
    assert.deepEqual(keys(db, thread), ["9007199254740995", "9007199254740993"]);
    assert.deepEqual(keys(db, thread, "9007199254740995"), ["9007199254740993"]);
  } finally { store.close(); }
});

test("a removed trigger invalidates the old scope and reclaims its rows in bounded batches", () => {
  const { store, db, thread, put } = make();
  try {
    for (let n = 1; n <= 150; n++) put.run(thread, n, "message", "letter", null);
    finish(db, thread);
    db.exec("DROP TRIGGER page_letter_delete");
    db.prepare("DELETE FROM entries WHERE thread=? AND n=1").run(thread);
    assert.equal(pageLetterReady(db, thread), null);
    finish(db, thread);
    assert.equal(keys(db, thread, MAX, 200).length, 149);
    assert.equal(pageLetterGcNeedsWork(db), true);
    let calls = 0;
    while (pageLetterGcNeedsWork(db)) {
      assert.ok(pageLetterGcStep(db).visited <= 64);
      assert.ok(++calls < 20);
    }
    assert.equal((db.prepare("SELECT count(*) AS n FROM page_letter_rows").get() as { n: number }).n, 149);
  } finally { store.close(); }
});

test("deleting and recreating a thread isolates and gradually reclaims its former keys", () => {
  const { store, db, thread, put } = make();
  try {
    for (let n = 1; n <= 150; n++) put.run(thread, n, "message", "letter", null);
    finish(db, thread);
    db.prepare("DELETE FROM entries WHERE thread=?").run(thread);
    db.prepare("DELETE FROM threads WHERE id=?").run(thread);
    db.prepare(`INSERT INTO threads(id,surface,channel,thread_ts,created_at) VALUES(?,'ember','CHAT','recreated',1)`).run(thread);
    put.run(thread, 1, "message", "letter", null);
    finish(db, thread);
    assert.deepEqual(keys(db, thread), ["1"]);
    let calls = 0;
    while (pageLetterGcNeedsWork(db)) {
      assert.ok(pageLetterGcStep(db).visited <= 64);
      assert.ok(++calls < 20);
    }
    assert.equal((db.prepare("SELECT count(*) AS n FROM page_letter_rows").get() as { n: number }).n, 1);
  } finally { store.close(); }
});

test("the background builder reclaims deleted scopes after handover", async () => {
  const dir = mkdtempSync(join(tmpdir(), "page-letter-gc-worker-"));
  const { store, db, thread, put } = make(join(dir, "stillfail.db"));
  const previous = Promise.withResolvers<void>();
  const builder = buildLegacyEntryLookups(store, previous.promise);
  try {
    for (let n = 1; n <= 150; n++) put.run(thread, n, "message", "letter", null);
    finish(db, thread);
    db.prepare("DELETE FROM entries WHERE thread=?").run(thread);
    db.prepare("DELETE FROM threads WHERE id=?").run(thread);
    assert.equal(pageLetterGcNeedsWork(db), true);
    builder.wake();
    await new Promise((resolve) => setTimeout(resolve, 50));
    assert.equal(pageLetterGcNeedsWork(db), true);
    previous.resolve();
    for (let i = 0; i < 400 && pageLetterGcNeedsWork(db); i++)
      await new Promise((resolve) => setTimeout(resolve, 25));
    assert.equal(pageLetterGcNeedsWork(db), false);
  } finally { previous.resolve(); await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("idle page-letter cleanup does not probe the database for ordinary message events", async () => {
  const { store, db, thread } = make();
  let checking = false, probes = 0;
  const observedDb = new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => {
      if (checking && sql === "PRAGMA schema_version") probes++;
      return target.prepare(sql);
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const observedStore = new Proxy(store, { get(target, property) {
    if (property === "db") return observedDb;
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const builder = buildLegacyEntryLookups(observedStore, Promise.resolve());
  try {
    await builder.ready;
    await new Promise((resolve) => setTimeout(resolve, 30));
    checking = true;
    for (let n = 1; n <= 5; n++)
      store.insertMessage({ thread, ts: `${n}`, authorKind: "agent", author: "worker", text: "words" });
    assert.equal(probes, 0);
  } finally { await builder.close(); store.close(); }
});
