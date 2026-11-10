import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { sessionOps } from "../src/read/ops-sessions.ts";
import { firstText, lastSaid, LAST_MESSAGE_RECENT_EDIT, makeStore } from "../src/read/store.ts";
import { installLegacyEdits, legacyEditDrain, legacyEditStep } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

const viewer = { sub: "me", email: "me", name: "Me", role: "owner", workspace: "w", device: "d" } as const;

function oldSidebar(size: number, prepared: boolean, path = ":memory:") {
  const store = Store.open(path), db = store.db;
  const thread = store.openThread("ember", "CHAT", `sidebar-old-edits-${size}-${prepared}`, null, null).id;
  db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
  const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
    VALUES(?,?,?,?,?,?,?,?)`);
  put.run(thread, 1, "message", null, "person", "me", "original", 1);
  db.exec("BEGIN");
  for (let n = 2; n <= size + 1; n++)
    put.run(thread, n, "edit", prepared ? 1 : n + 1000, "agent", "worker", `edit-${n}`, n);
  db.exec("COMMIT");
  installLegacyEdits(db);
  if (prepared) {
    while (!legacyEditStep(db).ready) { /* prepare */ }
    db.prepare("UPDATE entries SET target=2 WHERE thread=? AND target=1").run(thread);
  }
  addClientColumn(db);
  return { store, db, thread };
}

for (const prepared of [false, true])
  test(`sidebar message and first text wait for bounded old edit preparation (prepared ${prepared})`, () => {
    for (const size of [80, 800]) {
      const { store, db, thread } = oldSidebar(size, prepared);
      try {
        const read = makeStore(db, "/unused");
        assert.throws(() => lastSaid(read, thread), { status: 503, message: "legacy edit lookup pending" });
        assert.throws(() => firstText(read, thread), { status: 503, message: "legacy edit lookup pending" });
        while (!legacyEditStep(db).ready) { /* prepare */ }
        while (legacyEditDrain(db) > 0) { /* reconcile */ }
        assert.equal(lastSaid(read, thread)?.text, "original");
        assert.equal(firstText(read, thread), "original");
      } finally { store.close(); }
    }
  });

for (const changed of [64, 65])
  test(`sidebar reads handle ${changed} pending old edit keys`, () => {
    const { store, db, thread } = oldSidebar(changed, true);
    try {
      const read = makeStore(db, "/unused");
      if (changed === 64) {
        assert.equal(lastSaid(read, thread)?.text, "original");
        assert.equal(firstText(read, thread), "original");
      } else {
        assert.throws(() => lastSaid(read, thread), { status: 503, message: "legacy edit lookup pending" });
        assert.throws(() => firstText(read, thread), { status: 503, message: "legacy edit lookup pending" });
      }
      while (legacyEditDrain(db) > 0) { /* reconcile */ }
      assert.equal(lastSaid(read, thread)?.text, "original");
      assert.equal(firstText(read, thread), "original");
    } finally { store.close(); }
  });

test("a short chat and a recent 64-bit edit remain readable while old edits are prepared", () => {
  const { store, db, thread } = oldSidebar(800, false);
  try {
    const short = store.openThread("ember", "CHAT", "short-sidebar-edit", null, null).id;
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,1,'message','person','me','short',1)`).run(short);
    db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?,'edit',1,'agent','worker',?,2)`).run(thread, 9007199254740993n, "字".repeat(350));
    const read = makeStore(db, "/unused");
    assert.equal(lastSaid(read, short)?.text, "short");
    assert.equal(firstText(read, short), "short");
    assert.equal(lastSaid(read, thread)?.text, "字".repeat(350));
    assert.equal(firstText(read, thread), "字".repeat(300));
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
  } finally { store.close(); }
});

test("first text preserves a null edited value", () => {
  const { store, db, thread } = oldSidebar(80, false);
  try {
    db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,82,'edit',1,'agent','worker',NULL,82)`).run(thread);
    const read = makeStore(db, "/unused");
    assert.equal(lastSaid(read, thread)?.text, "");
    assert.equal(firstText(read, thread), null);
  } finally { store.close(); }
});

for (const kind of ["lastSaid", "firstText"] as const)
  test(`${kind} keeps its snapshot while an old connection changes edits`, () => {
    const dir = mkdtempSync(join(tmpdir(), "sidebar-edit-snapshot-")), path = join(dir, "stillfail.db");
    const { store, db, thread } = oldSidebar(65, true, path), writer = new DatabaseSync(path);
    try {
      while (legacyEditDrain(db) > 0) { /* reconcile */ }
      let changed = false;
      const observed = new Proxy(db, { get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const reading = kind === "lastSaid" ? sql.startsWith("SELECT m.* FROM thread_state")
            : sql.startsWith("SELECT substr(m.text, 1, 300) AS t FROM thread_state");
          if (reading && !changed) {
            changed = true;
            writer.prepare("UPDATE entries SET target=1 WHERE thread=? AND target=2").run(thread);
          }
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      const read = makeStore(observed, dir);
      const get = () => kind === "lastSaid" ? lastSaid(read, thread)?.text : firstText(read, thread);
      assert.equal(get(), "original");
      assert.ok(changed);
      assert.equal(get(), "edit-66");
    } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
  });

for (const kind of ["lastSaid", "firstText"] as const)
  test(`${kind} keeps its snapshot during the bounded old-edit probe`, () => {
    const dir = mkdtempSync(join(tmpdir(), "sidebar-edit-probe-snapshot-")), path = join(dir, "stillfail.db");
    const { store, db, thread } = oldSidebar(80, false, path);
    db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,82,'edit',1,'agent','worker','before',82)`).run(thread);
    const writer = new DatabaseSync(path);
    try {
      let changed = false;
      const observed = new Proxy(db, { get(target, property) {
        if (property === "prepare") return (sql: string) => {
          if (sql === LAST_MESSAGE_RECENT_EDIT && !changed) {
            changed = true;
            writer.prepare("UPDATE entries SET text='after' WHERE thread=? AND n=82").run(thread);
          }
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      const read = makeStore(observed, dir);
      const get = () => kind === "lastSaid" ? lastSaid(read, thread)?.text : firstText(read, thread);
      assert.equal(get(), "before");
      assert.ok(changed);
      assert.equal(get(), "after");
    } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
  });

test("a thread read propagates the pending lookup and retries after handover", async () => {
  const dir = mkdtempSync(join(tmpdir(), "sidebar-legacy-edit-reader-")), path = join(dir, "stillfail.db");
  const { store, db, thread } = oldSidebar(150, false, path);
  const args = { id: String(thread), viewer, lang: "en" };
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  const controller = new AbortController();
  try {
    assert.throws(() => sessionOps.thread!(makeStore(db, dir), args), { status: 503, message: "legacy edit lookup pending" });
    const abandoned = readers.read("thread", args, "en", { signal: controller.signal });
    const waiting = readers.read("thread", args, "en");
    const empty = store.openThread("ember", "CHAT", "empty-sidebar-edit", null, null).id;
    assert.deepEqual(JSON.parse(await readers.read("latestMessages", { thread: empty, limit: 2 }, "en")), []);
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    const result = JSON.parse(await waiting);
    assert.equal(result?.lastMessage?.text, "original");
    assert.equal(result?.firstText, "original");
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
