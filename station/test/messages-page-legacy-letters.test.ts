import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { makeStore, messagesBefore, PAGE_LETTER_CANDIDATES } from "../src/read/store.ts";
import { installLegacySaid, legacySaidStep } from "../src/store/legacy-said-build.ts";
import { PAGE_LETTER_KEYS, pageLetterStep } from "../src/store/page-letter-index.ts";
import { installSaidState } from "../src/store/said-state.ts";
import { I64_MAX, toMessage } from "../src/store/rows.ts";
import { Store } from "../src/store/store.ts";

function oldPage(size: number, legacy: boolean, missingIndex: boolean, path = ":memory:") {
  const store = Store.open(path), db = store.db;
  const thread = store.openThread("ember", "CHAT", `old-letter-page-${size}-${legacy}-${missingIndex}`, null, null).id;
  const put = db.prepare(`INSERT INTO entries(thread,n,kind,letter,author_kind,author,text,at)
    VALUES(?,?,?,?,?,?,?,?)`);
  db.exec("BEGIN");
  put.run(thread, 1, "message", null, "agent", "worker", "kept", 1);
  for (let n = 2; n <= size + 1; n++)
    put.run(thread, n, "edit", missingIndex ? null : "old-letter", "agent", "worker", `other-${n}`, n);
  db.exec("COMMIT");
  if (legacy) {
    installLegacySaid(db);
    db.exec("DROP INDEX entries_said");
    installSaidState(db);
    while (!legacySaidStep(db).ready) { /* prepare */ }
  }
  if (missingIndex) db.exec("DROP INDEX entries_letters");
  return { store, db, thread };
}

for (const legacy of [false, true]) for (const missing of [false, true])
  test(`a page leaves a long ${missing ? "unindexed" : "non-message letter"} tail to bounded preparation (legacy ${legacy})`, () => {
    for (const size of [80, 800]) {
      const { store, db, thread } = oldPage(size, legacy, missing);
      try {
        const read = makeStore(db, "/unused");
        assert.throws(() => messagesBefore(read, thread, null, 1), /page letter lookup pending/);
        while (!pageLetterStep(db, thread).done) { /* prepare */ }
        assert.deepEqual(messagesBefore(read, thread, null, 1).map((m) => m.text), ["kept"]);
      } finally { store.close(); }
    }
  });

test("an ordinary message below a truncated letter tail cannot hide an older letter-message", () => {
  const { store, db, thread } = oldPage(80, false, false);
  try {
    db.prepare("UPDATE entries SET kind='message',text='letter' WHERE thread=? AND n=10").run(thread);
    const read = makeStore(db, "/unused");
    assert.throws(() => messagesBefore(read, thread, null, 1), /page letter lookup pending/);
    while (!pageLetterStep(db, thread).done) { /* prepare */ }
    assert.deepEqual(messagesBefore(read, thread, null, 2).map((m) => m.text), ["kept", "letter"]);
  } finally { store.close(); }
});

test("prepared pages keep the original boundaries and order across old writes", () => {
  const { store, db, thread } = oldPage(150, false, false);
  try {
    db.prepare("UPDATE entries SET kind='message' WHERE thread=? AND n IN (5,20,80,145)").run(thread);
    db.prepare("UPDATE entries SET letter=NULL WHERE thread=? AND n IN (20,145)").run(thread);
    while (!pageLetterStep(db, thread).done) { /* prepare */ }
    const read = makeStore(db, "/unused");
    const reference = db.prepare("SELECT * FROM merged WHERE thread=? AND n<? ORDER BY n DESC LIMIT ?");
    const check = () => {
      for (const before of [null, 1, 3, 50, 100, 151, 200]) for (const limit of [0, 1, 2, 3, 10, 40]) {
        const expected = reference.all(thread, before ?? I64_MAX, limit).map(toMessage).reverse();
        assert.deepEqual(messagesBefore(read, thread, before, limit), expected, `before=${before} limit=${limit}`);
      }
    };
    check();
    db.prepare("UPDATE entries SET kind='edit' WHERE thread=? AND n=80").run(thread);
    db.prepare("UPDATE entries SET kind='message' WHERE thread=? AND n=90").run(thread);
    db.prepare("UPDATE entries SET letter='letter' WHERE thread=? AND n=145").run(thread);
    db.prepare("UPDATE entries SET letter=NULL WHERE thread=? AND n=5").run(thread);
    check();
  } finally { store.close(); }
});

test("a page can use the ordinary index past a long tail without letter metadata", () => {
  const { store, db, thread } = oldPage(800, false, false);
  try {
    db.prepare("UPDATE entries SET letter=NULL WHERE thread=?").run(thread);
    assert.deepEqual(messagesBefore(makeStore(db, "/unused"), thread, null, 1).map((m) => m.text), ["kept"]);
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name='page_letter_scopes'").get(), undefined);
  } finally { store.close(); }
});

for (const missing of [false, true]) for (const size of [64, 65])
  test(`a page handles ${size} ${missing ? "unindexed" : "non-message letter"} candidates`, () => {
    const { store, db, thread } = oldPage(size, false, missing);
    try {
      const read = makeStore(db, "/unused");
      if (size === 64) assert.deepEqual(messagesBefore(read, thread, null, 1).map((m) => m.text), ["kept"]);
      else assert.throws(() => messagesBefore(read, thread, null, 1), /page letter lookup pending/);
    } finally { store.close(); }
  });

for (const missing of [false, true])
  test(`a ${missing ? "raw" : "bounded index"} letter probe preserves an unrelated 64-bit key`, () => {
    const { store, db, thread } = oldPage(80, false, missing);
    try {
      db.prepare(`INSERT INTO entries(thread,n,kind,letter,author_kind,author,at)
        VALUES(?,9007199254740993,'edit',?,'agent','worker',1)`).run(thread, missing ? null : "letter");
      const read = makeStore(db, "/unused");
      assert.throws(() => messagesBefore(read, thread, null, 1), /page letter lookup pending/);
      while (!pageLetterStep(db, thread).done) { /* prepare */ }
      assert.deepEqual(messagesBefore(read, thread, null, 1).map((m) => m.text), ["kept"]);
    } finally { store.close(); }
  });

test("letter candidates and their returned messages share one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "page-letter-snapshot-")), path = join(dir, "stillfail.db");
  const { store, db, thread } = oldPage(2, false, false, path), writer = new DatabaseSync(path);
  try {
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === PAGE_LETTER_CANDIDATES && !changed) {
          changed = true;
          writer.prepare("UPDATE entries SET kind='message',text='later' WHERE thread=? AND n=3").run(thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = makeStore(observed, dir);
    assert.deepEqual(messagesBefore(read, thread, null, 2).map((m) => m.text), ["kept"]);
    assert.ok(changed);
    assert.deepEqual(messagesBefore(read, thread, null, 2).map((m) => m.text), ["kept", "later"]);
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a prepared letter lookup and its returned messages share one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "page-letter-ready-snapshot-")), path = join(dir, "stillfail.db");
  const { store, db, thread } = oldPage(2, false, false, path), writer = new DatabaseSync(path);
  try {
    db.prepare("UPDATE entries SET kind='message',text='letter' WHERE thread=? AND n=2").run(thread);
    while (!pageLetterStep(db, thread).done) { /* prepare */ }
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === PAGE_LETTER_KEYS && !changed) {
          changed = true;
          writer.prepare("UPDATE entries SET kind='edit' WHERE thread=? AND n=2").run(thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = makeStore(observed, dir);
    assert.deepEqual(messagesBefore(read, thread, null, 2).map((m) => m.text), ["kept", "letter"]);
    assert.ok(changed);
    assert.deepEqual(messagesBefore(read, thread, null, 2).map((m) => m.text), ["kept"]);
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("letter page preparation is shared after handover when one reader cancels", async () => {
  const dir = mkdtempSync(join(tmpdir(), "page-letter-worker-")), path = join(dir, "stillfail.db");
  const { store, thread } = oldPage(150, false, false, path);
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  const controller = new AbortController();
  try {
    const args = { thread, limit: 1 };
    const abandoned = readers.read("latestMessages", args, "en", { signal: controller.signal });
    const kept = readers.read("latestMessages", args, "en");
    const empty = store.openThread("ember", "CHAT", "empty-page-letter", null, null).id;
    assert.deepEqual(JSON.parse(await readers.read("latestMessages", { thread: empty, limit: 1 }, "en")), []);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    assert.deepEqual(JSON.parse(await kept).map((m: { text: string }) => m.text), ["kept"]);
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const missing of [false, true])
  test(`a recent page remains readable with an ${missing ? "unindexed" : "invalid letter"} tail`, () => {
    const { store, db, thread } = oldPage(80, false, missing);
    try {
      db.prepare(`INSERT INTO entries(thread,n,kind,letter,author_kind,author,text,at)
        VALUES(?,82,'message','letter','agent','worker','recent letter',82)`).run(thread);
      assert.deepEqual(messagesBefore(makeStore(db, "/unused"), thread, null, 1).map((m) => m.text), ["recent letter"]);
    } finally { store.close(); }
  });
