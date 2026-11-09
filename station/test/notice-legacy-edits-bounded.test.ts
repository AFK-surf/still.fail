import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { LAST_MESSAGE_RECENT_EDIT, lastMessage, makeStore } from "../src/read/store.ts";
import { installLegacyEdits, legacyEditDrain, legacyEditStep } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { toMessage } from "../src/store/rows.ts";
import { newMessage, Store } from "../src/store/store.ts";

function oldStore(size: number, prepared: boolean, path = ":memory:", oldIndex = false) {
  const store = Store.open(path), db = store.db;
  const thread = store.openThread("ember", "CHAT", `notice-old-edits-${size}-${prepared}`, null, null).id;
  db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
  if (oldIndex) db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL");
  const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
    VALUES(?,?,?,?,'agent','worker',?,?)`);
  put.run(thread, 1, "message", null, "original", 1);
  db.exec("BEGIN");
  for (let n = 2; n <= size + 1; n++) put.run(thread, n, "edit", prepared ? 1 : n + 1000, `edit-${n}`, n);
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
  test(`a notice leaves a long old edit lookup to bounded preparation (prepared ${prepared})`, () => {
    for (const size of [80, 800]) {
      const { store, db, thread } = oldStore(size, prepared);
      try {
        let mergedReads = 0, visited = 0;
        db.function("visit_notice_edit_tail", (n) => { visited++; return n; });
        const observed = new Proxy(db, { get(target, property) {
          if (property === "prepare") return (sql: string) => {
            if (sql === "SELECT * FROM merged WHERE thread=?1 AND n=CAST(?2 AS INTEGER)") mergedReads++;
            if (sql === LAST_MESSAGE_RECENT_EDIT)
              sql = sql.replace("thread=?1 ORDER BY", "thread=?1 AND visit_notice_edit_tail(n)=n ORDER BY");
            return target.prepare(sql);
          };
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        } });
        const reader = makeStore(observed, "/unused");
        assert.throws(() => lastMessage(reader, thread), { status: 503, message: "legacy edit lookup pending" });
        assert.equal(mergedReads, 0, "the unbounded lookup was not started");
        assert.equal(visited, 65, "the tail probe visited only one bounded slice");
        while (!legacyEditStep(db).ready) { /* prepare */ }
        while (legacyEditDrain(db) > 0) { /* reconcile */ }
        assert.equal(lastMessage(reader, thread)?.text, "original");
      } finally { store.close(); }
    }
  });

test("a recent edit is readable while older edits are still being prepared", () => {
  const { store, db, thread } = oldStore(800, false);
  try {
    db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,802,'edit',1,'agent','worker','recent',802)`).run(thread);
    const message = lastMessage(makeStore(db, "/unused"), thread);
    assert.equal(message?.text, "recent");
    assert.equal(message?.editedAt, 802);
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
  } finally { store.close(); }
});

test("the bounded edit probe keeps the last message's complete merged fields", () => {
  const { store, db, thread } = oldStore(80, false);
  try {
    db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,attachments,quotes,at)
      VALUES(?,82,'edit',1,'agent','worker',NULL,'[]','[]',82)`).run(thread);
    const expected = db.prepare("SELECT * FROM merged WHERE thread=? AND n=1").get(thread);
    assert.ok(expected);
    assert.deepEqual(lastMessage(makeStore(db, "/unused"), thread), toMessage(expected));
  } finally { store.close(); }
});

test("the 65-entry tail includes its oldest edit and waits for an older one", () => {
  const { store, db, thread } = oldStore(80, false);
  try {
    const reader = makeStore(db, "/unused");
    db.prepare("UPDATE entries SET target=1 WHERE thread=? AND n=17").run(thread);
    assert.equal(lastMessage(reader, thread)?.text, "edit-17");
    db.prepare("UPDATE entries SET target=1017 WHERE thread=? AND n=17").run(thread);
    db.prepare("UPDATE entries SET target=1 WHERE thread=? AND n=16").run(thread);
    assert.throws(() => lastMessage(reader, thread), { status: 503, message: "legacy edit lookup pending" });
  } finally { store.close(); }
});

test("the bounded edit probe preserves a 64-bit edit key", () => {
  const { store, db, thread } = oldStore(80, false);
  try {
    db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?,'edit',1,'agent','worker','large key',100)`).run(thread, 9007199254740993n);
    assert.equal(lastMessage(makeStore(db, "/unused"), thread)?.text, "large key");
  } finally { store.close(); }
});

test("a short chat stays readable while another old chat is being prepared", () => {
  const { store, db } = oldStore(800, false);
  try {
    const thread = store.openThread("ember", "CHAT", "short-notice", null, null).id;
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,1,'message','agent','worker','short',1)`).run(thread);
    assert.equal(lastMessage(makeStore(db, "/unused"), thread)?.text, "short");
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
  } finally { store.close(); }
});

test("a small old edit index lookup stays readable before global preparation", () => {
  const { store, db, thread } = oldStore(800, false, ":memory:", true);
  try {
    const reader = makeStore(db, "/unused");
    assert.equal(lastMessage(reader, thread)?.text, "original");
    db.prepare("UPDATE entries SET target=1 WHERE thread=? AND n=2").run(thread);
    assert.equal(lastMessage(reader, thread)?.text, "edit-2");
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
  } finally { store.close(); }
});

test("the old edit index answers 64 matches and waits for 65", () => {
  const { store, db, thread } = oldStore(800, false, ":memory:", true);
  try {
    const reader = makeStore(db, "/unused");
    db.prepare("UPDATE entries SET target=1 WHERE thread=? AND n BETWEEN 2 AND 66").run(thread);
    assert.throws(() => lastMessage(reader, thread), { status: 503, message: "legacy edit lookup pending" });
    db.prepare("UPDATE entries SET target=1066 WHERE thread=? AND n=66").run(thread);
    assert.equal(lastMessage(reader, thread)?.text, "edit-65");
  } finally { store.close(); }
});

test("a new native index does not make the existing legacy view safe until it is rebuilt", () => {
  const { store, db, thread } = oldStore(80, false);
  try {
    const reader = makeStore(db, "/unused");
    assert.throws(() => lastMessage(reader, thread), { status: 503, message: "legacy edit lookup pending" });
    db.exec("CREATE INDEX entries_edits ON entries(thread,target,n) WHERE target IS NOT NULL");
    assert.throws(() => lastMessage(reader, thread), { status: 503, message: "legacy edit lookup pending" });
    addClientColumn(db);
    assert.equal(lastMessage(reader, thread)?.text, "original");
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
  } finally { store.close(); }
});

test("the edit readiness probe and message use the same snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "notice-edit-snapshot-")), path = join(dir, "stillfail.db");
  const { store, db, thread } = oldStore(65, true, path), writer = new DatabaseSync(path);
  try {
    while (legacyEditDrain(db) > 0) { /* reconcile */ }
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql.includes("SELECT scanned=1 AND NOT EXISTS") && !changed) {
          changed = true;
          writer.prepare("UPDATE entries SET target=1 WHERE thread=? AND target=2").run(thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const reader = makeStore(observed, dir);
    assert.equal(lastMessage(reader, thread)?.text, "original");
    assert.ok(changed);
    assert.equal(lastMessage(reader, thread)?.text, "edit-66");
    writer.prepare("UPDATE entries SET target=3 WHERE thread=? AND target=1").run(thread);
    assert.throws(() => lastMessage(reader, thread), { status: 503, message: "legacy edit lookup pending" });
    while (legacyEditDrain(db) > 0) { /* reconcile */ }
    assert.equal(lastMessage(reader, thread)?.text, "original");
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("notices share old edit preparation after handover and cancellation", async () => {
  const dir = mkdtempSync(join(tmpdir(), "notice-edit-worker-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  const controller = new AbortController();
  try {
    store.insertSession({ key: "k", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w",
      token: "t", createdAt: 1, lastActiveAt: 1, createdBy: "ada@x.com" });
    const thread = store.openThread("ember", "CHAT", "notice-old-edit-worker", null, "ada@x.com").id;
    store.joinThread(thread, "k", "ember");
    store.startTurn("turn", "k", "input");
    const [message] = store.insertMessage(newMessage(thread, "1.1", "agent", "k", "before"));
    store.endTurn("turn", "completed", null, "final", null);
    store.db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    const edit = store.db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?,'edit',?,'agent','k',?,?)`);
    store.db.exec("BEGIN");
    edit.run(thread, 2, message, "edited", 2);
    for (let n = 3; n <= 150; n++) edit.run(thread, n, n + 1000, `other-${n}`, n);
    store.db.exec("COMMIT");
    installLegacyEdits(store.db);
    addClientColumn(store.db);
    const args = { key: "k", since: 0, ended: null, lang: "zh" };
    const abandoned = readers.read("turnNotices", args, "zh", { told: true, signal: controller.signal });
    const kept = readers.read("turnNotices", args, "zh", { told: true });
    await readers.read("turnNotices", { ...args, key: "missing" }, "zh", { told: true });
    assert.equal(store.db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    const result = JSON.parse(await kept);
    assert.deepEqual(result.notices.map((n: any) => [n.text, n.seq]), [["edited", message]]);
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const changed of [64, 65])
  test(`a notice handles ${changed} pending old edit keys`, () => {
    const { store, db, thread } = oldStore(changed, true);
    try {
      const reader = makeStore(db, "/unused");
      assert.equal(db.prepare("SELECT COUNT(*) AS n FROM legacy_edit_dirty").get()?.n, changed);
      if (changed <= 64) assert.equal(lastMessage(reader, thread)?.text, "original");
      else assert.throws(() => lastMessage(reader, thread), { status: 503, message: "legacy edit lookup pending" });
    } finally { store.close(); }
  });
