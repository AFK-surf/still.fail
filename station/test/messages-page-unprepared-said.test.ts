import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { LEGACY_SAID_PAGE_TAIL, makeStore, messagesBefore } from "../src/read/store.ts";
import { installLegacyEdits, legacyEditStep } from "../src/store/legacy-edits-build.ts";
import { installLegacySaid, LEGACY_SAID_PAGE_STATE, legacySaidDrainThread, legacySaidStep } from "../src/store/legacy-said-build.ts";
import { installSaidState } from "../src/store/said-state.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

function oldPage(size: number, path = ":memory:") {
  const store = Store.open(path), db = store.db;
  const thread = store.openThread("ember", "CHAT", `unprepared-page-${size}`, null, null).id;
  const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
    VALUES(?,?,?,?,?,?,?)`);
  db.exec("BEGIN");
  put.run(thread, 1, "message", "agent", "worker", "kept", 1);
  for (let n = 2; n <= size + 1; n++) put.run(thread, n, "edit", "agent", "worker", `other-${n}`, n);
  db.exec("COMMIT");
  installLegacySaid(db);
  db.exec("DROP INDEX entries_said");
  installSaidState(db);
  return { store, db, thread };
}

test("page readiness seeks only the requested chat's changed keys", () => {
  const { store, db, thread } = oldPage(0);
  try {
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${LEGACY_SAID_PAGE_STATE}`).all(thread).map((row) => String(row.detail));
    assert.ok(plan.some((row) => /SEARCH legacy_said_dirty USING PRIMARY KEY \(thread=\?\)/.test(row)), plan.join("\n"));
  } finally { store.close(); }
});

test("a page waits for bounded old message preparation after a long non-message tail", () => {
  for (const size of [80, 800]) {
    const { store, db, thread } = oldPage(size);
    try {
      let visited = 0;
      db.function("visit_unprepared_page_tail", (n) => { visited++; return n; });
      const observed = new Proxy(db, { get(target, property) {
        if (property === "prepare") return (sql: string) => {
          if (sql === LEGACY_SAID_PAGE_TAIL)
            sql = sql.replace("e.thread=?1 AND e.n<?2", "e.thread=?1 AND visit_unprepared_page_tail(e.n)=e.n AND e.n<?2");
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      const read = makeStore(observed, "/unused");
      assert.throws(() => messagesBefore(read, thread, null, 1), { status: 503, message: "legacy said lookup pending" });
      assert.equal(visited, 65);
      assert.equal(db.prepare("SELECT scanned FROM legacy_said_meta WHERE id=1").get()?.scanned, 0);
      while (!legacySaidStep(db).ready) { /* prepare */ }
      assert.deepEqual(messagesBefore(read, thread, null, 1).map((m) => m.text), ["kept"]);
    } finally { store.close(); }
  }
});

for (const size of [64, 65]) test(`an unprepared page handles a tail of ${size} other entries`, () => {
  const { store, db, thread } = oldPage(size);
  try {
    const read = makeStore(db, "/unused");
    if (size === 64) assert.deepEqual(messagesBefore(read, thread, null, 1).map((m) => m.text), ["kept"]);
    else assert.throws(() => messagesBefore(read, thread, null, 1), { status: 503, message: "legacy said lookup pending" });
  } finally { store.close(); }
});

test("short or recent pages remain readable while old message keys are prepared", () => {
  const { store, db, thread } = oldPage(80);
  try {
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,letter,author_kind,author,text,at)
      VALUES(?,?,'message',?,'agent','worker',?,?)`);
    put.run(thread, 82, null, "recent", 82);
    put.run(thread, 83, "letter", "recent letter", 83);
    const read = makeStore(db, "/unused");
    assert.deepEqual(messagesBefore(read, thread, null, 2).map((m) => m.text), ["recent", "recent letter"]);
    assert.deepEqual(messagesBefore(read, thread, null, 0), []);
    assert.throws(() => messagesBefore(read, thread, 82, 1), { status: 503, message: "legacy said lookup pending" });
    assert.equal(db.prepare("SELECT scanned FROM legacy_said_meta WHERE id=1").get()?.scanned, 0);
  } finally { store.close(); }
});

test("an unprepared page preserves unrelated 64-bit entry keys", () => {
  const { store, db, thread } = oldPage(80);
  try {
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'edit','agent','worker','other',100)`).run(thread, 9007199254740993n);
    assert.throws(() => messagesBefore(makeStore(db, "/unused"), thread, null, 1),
      { status: 503, message: "legacy said lookup pending" });
  } finally { store.close(); }
});

test("a recent page still waits for its unprepared old edits", () => {
  const { store, db, thread } = oldPage(80);
  try {
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    installLegacyEdits(db);
    addClientColumn(db);
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,82,'message','agent','worker','recent',82)`).run(thread);
    const read = makeStore(db, "/unused");
    assert.throws(() => messagesBefore(read, thread, null, 1), { status: 503, message: "legacy edit lookup pending" });
    while (!legacyEditStep(db).ready) { /* prepare */ }
    assert.deepEqual(messagesBefore(read, thread, null, 1).map((m) => m.text), ["recent"]);
    assert.equal(db.prepare("SELECT scanned FROM legacy_said_meta WHERE id=1").get()?.scanned, 0);
  } finally { store.close(); }
});

test("a page reconciles old writes that arrive during the initial scan", () => {
  const { store, db, thread } = oldPage(80);
  try {
    assert.equal(legacySaidStep(db).ready, false);
    db.prepare("UPDATE entries SET kind='message' WHERE thread=? AND n>1").run(thread);
    db.prepare("UPDATE entries SET kind='edit' WHERE thread=? AND n>1").run(thread);
    while (!legacySaidStep(db).ready) { /* prepare */ }
    const read = makeStore(db, "/unused");
    assert.throws(() => messagesBefore(read, thread, null, 1), /sidebar said state pending/);
    while (legacySaidDrainThread(db, thread) > 0) { /* reconcile */ }
    assert.deepEqual(messagesBefore(read, thread, null, 1).map((m) => m.text), ["kept"]);
  } finally { store.close(); }
});

test("an unprepared page and its probe share a snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "page-unprepared-snapshot-")), path = join(dir, "stillfail.db");
  const { store, db, thread } = oldPage(64, path), writer = new DatabaseSync(path);
  try {
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === LEGACY_SAID_PAGE_TAIL && !changed) {
          changed = true;
          writer.prepare("UPDATE entries SET kind='message',text='later' WHERE thread=? AND n=65").run(thread);
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

test("unprepared pages share work after handover when one reader cancels", async () => {
  const dir = mkdtempSync(join(tmpdir(), "page-unprepared-worker-")), path = join(dir, "stillfail.db");
  const { store, db, thread } = oldPage(150, path);
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  const controller = new AbortController();
  try {
    const args = { thread, limit: 1 };
    const abandoned = readers.read("latestMessages", args, "en", { signal: controller.signal });
    const kept = readers.read("latestMessages", args, "en");
    const empty = store.openThread("ember", "CHAT", "empty-unprepared-page", null, null).id;
    assert.deepEqual(JSON.parse(await readers.read("latestMessages", { thread: empty, limit: 1 }, "en")), []);
    assert.equal(db.prepare("SELECT scanned FROM legacy_said_meta WHERE id=1").get()?.scanned, 0);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    assert.deepEqual(JSON.parse(await kept).map((m: { text: string }) => m.text), ["kept"]);
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
