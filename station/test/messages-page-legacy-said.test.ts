import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { LEGACY_SAID_PAGE_TAIL, makeStore, messagesBefore } from "../src/read/store.ts";
import { installLegacyEdits, legacyEditStep } from "../src/store/legacy-edits-build.ts";
import { installLegacySaid, legacySaidDrainThread, legacySaidStep } from "../src/store/legacy-said-build.ts";
import { installSaidState } from "../src/store/said-state.ts";
import { LEGACY_MESSAGES_BEFORE } from "../src/store/rows.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

function oldPage(size: number, path = ":memory:") {
  const store = Store.open(path), db = store.db;
  const thread = store.openThread("ember", "CHAT", `old-said-page-${size}`, null, null).id;
  const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
    VALUES(?,?,'message','agent','worker',?,?)`);
  put.run(thread, 1, "kept", 1);
  db.exec("BEGIN");
  for (let n = 2; n <= size + 1; n++) put.run(thread, n, `later-${n}`, n);
  db.exec("COMMIT");
  installLegacySaid(db);
  db.exec("DROP INDEX entries_said");
  installSaidState(db);
  while (!legacySaidStep(db).ready) { /* prepare */ }
  db.prepare("UPDATE entries SET kind='edit' WHERE thread=? AND n>1").run(thread);
  return { store, db, thread };
}

test("a page with a changed-away old message tail waits after one bounded probe", () => {
  for (const size of [80, 800]) {
    const { store, db, thread } = oldPage(size);
    try {
      let visited = 0;
      db.function("visit_said_page_tail", (n) => { visited++; return n; });
      const observed = new Proxy(db, { get(target, property) {
        if (property === "prepare") return (sql: string) => {
          if (sql === LEGACY_SAID_PAGE_TAIL)
            sql = sql.replace("e.thread=?1 AND e.n<?2", "e.thread=?1 AND visit_said_page_tail(e.n)=e.n AND e.n<?2");
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      const read = makeStore(observed, "/unused");
      assert.throws(() => messagesBefore(read, thread, null, 1), /sidebar said state pending/);
      assert.equal(visited, 65);
      while (legacySaidDrainThread(db, thread) > 0) { /* reconcile */ }
      assert.deepEqual(messagesBefore(read, thread, null, 1).map((m) => m.text), ["kept"]);
    } finally { store.close(); }
  }
});

for (const changed of [64, 65])
  test(`an old page handles ${changed} changed message keys`, () => {
    const { store, db, thread } = oldPage(changed);
    try {
      const read = makeStore(db, "/unused");
      if (changed === 64) assert.deepEqual(messagesBefore(read, thread, null, 1).map((m) => m.text), ["kept"]);
      else assert.throws(() => messagesBefore(read, thread, null, 1), /sidebar said state pending/);
      while (legacySaidDrainThread(db, thread) > 0) { /* reconcile */ }
      assert.deepEqual(messagesBefore(read, thread, null, 1).map((m) => m.text), ["kept"]);
    } finally { store.close(); }
  });

test("a recent page remains readable during a long changed-key backlog", () => {
  const { store, db, thread } = oldPage(800);
  try {
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'message','agent','worker',?,?)`);
    put.run(thread, 802, "recent-1", 802);
    put.run(thread, 803, "recent-2", 803);
    db.prepare(`INSERT INTO entries(thread,n,kind,letter,author_kind,author,text,at)
      VALUES(?,804,'message','letter','agent','worker','recent-letter',804)`).run(thread);
    const read = makeStore(db, "/unused");
    assert.deepEqual(messagesBefore(read, thread, null, 2).map((m) => m.text), ["recent-2", "recent-letter"]);
    assert.throws(() => messagesBefore(read, thread, 802, 1), /sidebar said state pending/);
    assert.deepEqual(messagesBefore(read, thread, null, 0), []);
  } finally { store.close(); }
});

test("the old page probe preserves an unrelated 64-bit entry key", () => {
  const { store, db, thread } = oldPage(80);
  try {
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'edit','agent','worker','other',100)`).run(thread, 9007199254740993n);
    assert.throws(() => messagesBefore(makeStore(db, "/unused"), thread, null, 1), /sidebar said state pending/);
  } finally { store.close(); }
});

test("a page with both kinds of old preparation keeps the edit-read boundary", () => {
  const { store, db, thread } = oldPage(150);
  try {
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    installLegacyEdits(db);
    addClientColumn(db);
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,152,'message','agent','worker','recent',152)`).run(thread);
    const read = makeStore(db, "/unused");
    assert.throws(() => messagesBefore(read, thread, null, 1), { status: 503, message: "legacy edit lookup pending" });
    while (!legacyEditStep(db).ready) { /* prepare */ }
    assert.deepEqual(messagesBefore(read, thread, null, 1).map((m) => m.text), ["recent"]);
  } finally { store.close(); }
});

test("a page and its changed-key readiness share one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "page-said-snapshot-")), path = join(dir, "stillfail.db");
  const { store, db, thread } = oldPage(65, path), writer = new DatabaseSync(path);
  try {
    db.prepare("UPDATE entries SET kind='message' WHERE thread=? AND n>1").run(thread);
    while (legacySaidDrainThread(db, thread) > 0) { /* reconcile */ }
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === LEGACY_MESSAGES_BEFORE && !changed) {
          changed = true;
          writer.prepare("UPDATE entries SET kind='edit' WHERE thread=? AND n>1").run(thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = makeStore(observed, dir);
    assert.deepEqual(messagesBefore(read, thread, null, 1).map((m) => m.text), ["later-66"]);
    assert.ok(changed);
    assert.throws(() => messagesBefore(read, thread, null, 1), /sidebar said state pending/);
    while (legacySaidDrainThread(db, thread) > 0) { /* reconcile */ }
    assert.deepEqual(messagesBefore(read, thread, null, 1).map((m) => m.text), ["kept"]);
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("old pages share changed-key preparation after handover and cancellation", async () => {
  const dir = mkdtempSync(join(tmpdir(), "page-said-worker-")), path = join(dir, "stillfail.db");
  const { store, db, thread } = oldPage(150, path);
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  const controller = new AbortController();
  try {
    const args = { thread, limit: 1 };
    const abandoned = readers.read("latestMessages", args, "en", { signal: controller.signal });
    const kept = readers.read("latestMessages", args, "en");
    const empty = store.openThread("ember", "CHAT", "empty-page-said", null, null).id;
    assert.deepEqual(JSON.parse(await readers.read("latestMessages", { thread: empty, limit: 1 }, "en")), []);
    assert.ok(Number(db.prepare("SELECT COUNT(*) AS n FROM legacy_said_dirty WHERE thread=?").get(thread)?.n) > 64);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    assert.deepEqual(JSON.parse(await kept).map((m: { text: string }) => m.text), ["kept"]);
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
