import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import * as readStore from "../src/read/store.ts";
import { installLegacyEdits } from "../src/store/legacy-edits-build.ts";
import { installLegacySaid, legacySaidStep } from "../src/store/legacy-said-build.ts";
import { pageLetterStep } from "../src/store/page-letter-index.ts";
import { installSaidState } from "../src/store/said-state.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

test("an opened chat's recent authors do not need unprepared old edits", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "old-edits", null, null).id;
    db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,1,'message','1.1','agent','opener','opening',1)").run(thread);
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'agent','other','edit',2)");
    for (let n = 2; n <= 801; n++) edit.run(thread, n, n + 10000);
    edit.run(thread, 9007199254740993n, 1);
    installLegacyEdits(db);
    addClientColumn(db);
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        assert.doesNotMatch(sql, /\bmerged\b/i, "an author check has no need to merge edits");
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = readStore.makeStore(observed, "");
    assert.equal(readStore.openedChatSaid(read, thread, "opener", true), true);
    assert.equal(readStore.openedChatSaid(read, thread, "nobody", true), false);
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
  } finally { store.close(); }
});

test("only the latest 200 messages count, and local and peer author rules remain distinct", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "boundary", null, null).id;
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,letter,at)
      VALUES(?,?,?,?,?,?,?,?,?)`);
    db.exec("BEGIN");
    put.run(thread, 1, "message", "1.1", "agent", "opener", "old", null, 1);
    put.run(thread, 2, "message", "2.1", "person", "opener", "person", null, 2);
    for (let n = 3; n <= 201; n++) put.run(thread, n, "message", `${n}.1`, "person", "other", "other", null, n);
    put.run(thread, 202, "edit", null, "agent", "opener", "not a message", "old-letter", 202);
    db.exec("COMMIT");
    const read = readStore.makeStore(db, "");
    assert.equal(readStore.openedChatSaid(read, thread, "opener", true), false);
    assert.equal(readStore.openedChatSaid(read, thread, "opener", false), true);
    assert.equal(readStore.openedChatSaid(read, thread, "absent", false), false);
    put.run(thread, 203, "message", "203.1", "agent", "opener", "letter", "old-letter", 203);
    assert.equal(readStore.openedChatSaid(read, thread, "opener", true), true);
    assert.equal(readStore.openedChatSaid(read, thread, "opener", false), true);
  } finally { store.close(); }
});

function oldPage(path = ":memory:") {
  const store = Store.open(path), db = store.db;
  const thread = store.openThread("ember", "CHAT", "old-page", null, null).id;
  const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,?,?,?,?,?,?)");
  db.exec("BEGIN");
  put.run(thread, 1, "message", "agent", "opener", "opening", 1);
  for (let n = 2; n <= 301; n++) put.run(thread, n, "edit", "agent", "other", "edit", n);
  db.exec("COMMIT");
  installLegacySaid(db);
  db.exec("DROP INDEX entries_said");
  installSaidState(db);
  return { store, db, thread };
}

test("a long unprepared message tail is left to bounded preparation", () => {
  const { store, db, thread } = oldPage();
  try {
    const read = readStore.makeStore(db, "");
    assert.throws(() => readStore.openedChatSaid(read, thread, "opener", true), /legacy said lookup pending/);
    assert.equal(db.prepare("SELECT scanned FROM legacy_said_meta WHERE id=1").get()?.scanned, 0);
    while (!legacySaidStep(db).ready) { /* prepare */ }
    assert.equal(readStore.openedChatSaid(read, thread, "opener", true), true);
  } finally { store.close(); }
});

for (const missingIndex of [false, true]) test(`a long ${missingIndex ? "unindexed" : "non-message letter"} tail is prepared before checking authors`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "old-letter", null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,letter,author_kind,author,text,at) VALUES(?,?,?,?,?,?,?,?)");
    put.run(thread, 1, "message", null, "agent", "opener", "opening", 1);
    for (let n = 2; n <= 301; n++) put.run(thread, n, "edit", missingIndex ? null : "letter", "agent", "other", "edit", n);
    if (missingIndex) db.exec("DROP INDEX entries_letters");
    const read = readStore.makeStore(db, "");
    assert.throws(() => readStore.openedChatSaid(read, thread, "opener", true), /page letter lookup pending/);
    while (!pageLetterStep(db, thread).done) { /* prepare */ }
    assert.equal(readStore.openedChatSaid(read, thread, "opener", true), true);
  } finally { store.close(); }
});

test("the selected message keys and their authors share one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "opened-author-snapshot-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db, writer = new DatabaseSync(path);
  try {
    const thread = store.openThread("ember", "CHAT", "snapshot", null, null).id;
    db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,1,'message','1.1','agent','opener','opening',1)").run(thread);
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === readStore.PAGE_LETTER_CANDIDATES && !changed) {
          changed = true;
          writer.prepare("UPDATE entries SET author='other' WHERE thread=? AND n=1").run(thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = readStore.makeStore(observed, dir);
    assert.equal(readStore.openedChatSaid(read, thread, "opener", true), true);
    assert.ok(changed);
    assert.equal(readStore.openedChatSaid(read, thread, "opener", true), false);
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("opened-chat author checks share old page preparation after handover when one cancels", async () => {
  const dir = mkdtempSync(join(tmpdir(), "opened-author-reader-")), path = join(dir, "stillfail.db");
  const { store, thread } = oldPage(path);
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  const controller = new AbortController();
  try {
    const args = { thread, author: "opener", agentOnly: true };
    const abandoned = readers.read("openedChatSaid", args, "en", { signal: controller.signal });
    const kept = readers.read("openedChatSaid", args, "en");
    void abandoned.catch(() => {}); void kept.catch(() => {});
    const empty = store.openThread("ember", "CHAT", "empty", null, null).id;
    assert.equal(JSON.parse(await readers.read("openedChatSaid", { ...args, thread: empty }, "en")), false);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    assert.equal(JSON.parse(await kept), true);
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
