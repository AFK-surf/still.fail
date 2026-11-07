import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { LAST_MESSAGE_KEYED, LastMessageUnavailable, lastMessage, makeStore } from "../src/read/store.ts";
import { archiveLastKey, archiveLastRead, archiveLastStep } from "../src/store/archive-last.ts";
import { installLegacySaid, legacySaidStep } from "../src/store/legacy-said-build.ts";
import { installSaidState } from "../src/store/said-state.ts";
import { newMessage, Store } from "../src/store/store.ts";

function finish(db: DatabaseSync, thread: number) {
  for (let i = 0; i < 100; i++) {
    const step = archiveLastStep(db, thread);
    assert.ok(step.visited <= 64);
    if (step.done) return;
  }
  assert.fail("the requested chat did not finish");
}

for (const scenario of ["non-message-letters", "missing-letter-index"] as const)
  test(`notification reader bounds a tail with ${scenario}`, () => {
    const visits: number[] = [];
    for (const size of [80, 800]) {
      const dir = mkdtempSync(join(tmpdir(), "notice-last-gap-")), path = join(dir, "stillfail.db");
      let store = Store.open(path);
      const thread = store.openThread("ember", "CHAT", `notice-${scenario}-${size}`, null, "me").id;
      const put = store.db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,ts,at,letter)
        VALUES(?,?,?,?,'agent','worker',?,?,?,?)`);
      put.run(thread, 1, "message", null, "message", "t1", 1, null);
      store.db.exec("BEGIN");
      for (let n = 2; n <= size + 1; n++) put.run(thread, n, "edit", 1, `edit-${n}`, `t${n}`, n,
        scenario === "non-message-letters" ? "{}" : null);
      store.db.exec("COMMIT");
      installLegacySaid(store.db); store.db.exec("DROP INDEX entries_said"); installSaidState(store.db);
      while (!legacySaidStep(store.db, 64).ready) { /* prepare */ }
      store.close(); store = Store.open(path);
      const db = store.db;
      try {
        if (scenario === "missing-letter-index") db.exec("DROP INDEX entries_letters");
        let visited = 0, instrumented = false;
        db.function("visit_notice_entry", (n) => { visited++; return n; });
        const counted = new Proxy(db, { get(target, property) {
          if (property === "prepare") return (sql: string) => {
            const traced = sql.replace(/e\.thread=(\?1|\?)(?!\d)/g,
              (_match, parameter: string) => `e.thread=${parameter} AND visit_notice_entry(e.n)=e.n`);
            if (traced !== sql && sql.includes("FROM entries e")) instrumented = true;
            return target.prepare(traced);
          };
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        } });
        const reader = makeStore(counted, dir);
        assert.throws(() => lastMessage(reader, thread), LastMessageUnavailable);
        assert.ok(instrumented && visited > 0, "the source tail was counted");
        visits.push(visited);
        finish(db, thread);
        const last = lastMessage(reader, thread);
        assert.equal(last?.n, 1);
        assert.equal(last?.text, `edit-${size + 1}`);
      } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
    }
    assert.ok(visits[1]! <= visits[0]! + 4 && visits[1]! <= 70,
      `${scenario} candidates for 80 / 800 entries: ${visits.join(" / ")}`);
  });

test("a time-only guard remains usable and gains a message key when a reader needs it", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "last-v1-guard", null, "me").id;
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,1,'message','agent','worker','hello',1)`).run(thread);
    const edit = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?,'edit',1,'agent','worker','updated',?)`);
    for (let n = 2; n < 90; n++) edit.run(thread, n, n);
    db.exec("DROP INDEX entries_letters");
    finish(db, thread);
    // The previously released worker leaves before_n NULL on a completed time-only guard.
    db.prepare("UPDATE archive_last_guard SET before_n=NULL WHERE thread=?").run(thread);
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 1 });
    assert.deepEqual(archiveLastKey(db, thread), { known: false, n: null });
    assert.throws(() => lastMessage(makeStore(db, "/unused"), thread), LastMessageUnavailable);
    finish(db, thread);
    assert.deepEqual(archiveLastKey(db, thread), { known: true, n: "1" });
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 1 });
    assert.equal(lastMessage(makeStore(db, "/unused"), thread)?.text, "updated");
    const oldReader = db.prepare(`SELECT g.at FROM archive_last_meta m CROSS JOIN archive_last_guard g
      WHERE m.id=1 AND g.thread=? AND g.epoch=m.epoch AND g.ready=1`).get(thread);
    assert.equal(oldReader?.at, 1, "the old time-only reader can use the new guard");
  } finally { store.close(); }
});

test("a completed empty time-only guard needs no message scan", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "last-empty-guard", null, "me").id;
    const edit = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at)
      VALUES(?,?,'edit','agent','worker',?)`);
    for (let n = 1; n <= 100; n++) edit.run(thread, n, n);
    finish(db, thread);
    assert.deepEqual(archiveLastKey(db, thread), { known: true, n: null });
    assert.equal(lastMessage(makeStore(db, "/unused"), thread), null);
  } finally { store.close(); }
});

test("the guarded message key retains all 64 bits", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "last-large-message-key", null, "me").id;
    const n = 9007199254741001n;
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,?,'agent','worker',1)`);
    put.run(thread, n, "message");
    for (let i = 1n; i <= 90n; i++) put.run(thread, n + i, "edit");
    db.exec("DROP INDEX entries_letters");
    assert.deepEqual(archiveLastKey(db, thread), { known: false, n: null });
    finish(db, thread);
    assert.deepEqual(archiveLastKey(db, thread), { known: true, n: n.toString() });
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 1 });
  } finally { store.close(); }
});

test("a native message remains immediately readable through a long ordinary edit tail", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "last-native-tail", null, "me").id;
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,1,'message','agent','worker','hello',1)`).run(thread);
    const edit = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?,'edit',1,'agent','worker',?,?)`);
    for (let n = 2; n <= 150; n++) edit.run(thread, n, `edit-${n}`, n);
    assert.equal(lastMessage(makeStore(db, "/unused"), thread)?.text, "edit-150");
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM archive_last_guard").get()?.n, 0);
    db.exec("DROP INDEX entries_letters");
    assert.throws(() => lastMessage(makeStore(db, "/unused"), thread), LastMessageUnavailable);
    finish(db, thread);
    assert.equal(lastMessage(makeStore(db, "/unused"), thread)?.text, "edit-150");
  } finally { store.close(); }
});

for (const latest of ["letter", "ordinary"] as const)
  test(`the notification reader preserves the latest ${latest} message through a long tail`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("ember", "CHAT", `last-${latest}`, null, "me").id;
      const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,letter)
        VALUES(?,?,?,?,'agent','worker',?,?,?)`);
      const letter = { way: "in", title: "old", link: null };
      put.run(thread, 1, "message", null, "first", 1, null);
      put.run(thread, 2, "message", null, "letter", 2, JSON.stringify(letter));
      if (latest === "ordinary") put.run(thread, 3, "message", null, "ordinary", 3, null);
      const expected = latest === "letter" ? 2 : 3;
      for (let n = 4; n <= 150; n++) put.run(thread, n, "edit", expected, `edited-${n}`, n, null);
      const reader = makeStore(db, "/unused");
      if (latest === "letter") {
        assert.throws(() => lastMessage(reader, thread), LastMessageUnavailable);
        finish(db, thread);
      }
      const message = lastMessage(reader, thread);
      assert.equal(message?.n, expected);
      assert.equal(message?.text, "edited-150");
      assert.deepEqual(message?.letter, latest === "letter" ? letter : undefined);
    } finally { store.close(); }
  });

test("an old writer replacing the last message invalidates its prepared key", () => {
  const dir = mkdtempSync(join(tmpdir(), "notice-last-replace-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db, old = new DatabaseSync(path);
  try {
    const thread = store.openThread("ember", "CHAT", "notice-replace", null, "me").id;
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES
      (?,1,'message','agent','worker','first',1),(?,2,'message','agent','worker','second',2)`).run(thread, thread);
    const edit = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'edit','agent','worker',?)`);
    for (let n = 3; n < 100; n++) edit.run(thread, n, n);
    db.exec("DROP INDEX entries_letters");
    finish(db, thread);
    assert.deepEqual(archiveLastKey(db, thread), { known: true, n: "2" });
    old.prepare(`INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,at)
      VALUES(?,2,'edit','agent','worker',2)`).run(thread);
    assert.throws(() => lastMessage(makeStore(db, dir), thread), LastMessageUnavailable);
    finish(db, thread);
    assert.deepEqual(archiveLastKey(db, thread), { known: true, n: "1" });
    assert.equal(lastMessage(makeStore(db, dir), thread)?.text, "first");
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("the message key and merged text share a snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "notice-last-snapshot-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db, writer = new DatabaseSync(path);
  try {
    const thread = store.openThread("ember", "CHAT", "notice-snapshot", null, "me").id;
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,1,'message','agent','worker','before',1)`).run(thread);
    let changed = false;
    const counted = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === LAST_MESSAGE_KEYED && !changed) {
          changed = true;
          writer.prepare("UPDATE entries SET text='after' WHERE thread=? AND n=1").run(thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const reader = makeStore(counted, dir);
    assert.equal(lastMessage(reader, thread)?.text, "before");
    assert.ok(changed);
    assert.equal(lastMessage(reader, thread)?.text, "after");
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a turn notice waits for handover, prepares its chats together and keeps their edited text", async () => {
  const dir = mkdtempSync(join(tmpdir(), "notice-last-worker-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    store.insertSession({ key: "k", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w",
      token: "t", createdAt: 1, lastActiveAt: 1, createdBy: "ada@x.com" });
    const threads = [0, 1].map((i) => store.openThread("ember", "CHAT", `notice-worker-${i}`, null, "ada@x.com").id);
    for (const thread of threads) store.joinThread(thread, "k", "ember");
    store.startTurn("turn", "k", "input");
    const messages = threads.map((thread) => store.insertMessage(newMessage(thread, "1.1", "agent", "k", "before"))[0]);
    store.endTurn("turn", "completed", null, "final", null);
    const edit = store.db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?,'edit',?,'agent','k',?,?)`);
    store.db.exec("BEGIN");
    for (let i = 0; i < threads.length; i++)
      for (let n = 2; n <= 150; n++) edit.run(threads[i]!, n, messages[i]!, `edit-${i}-${n}`, n);
    store.db.exec("COMMIT");
    store.db.exec("DROP INDEX entries_letters");
    const batches: number[][] = [];
    const prepare = readers.prepareArchiveLast.bind(readers);
    readers.prepareArchiveLast = (ids, signal) => { batches.push([...ids]); return prepare(ids, signal); };
    const waiting = readers.read("turnNotices", { key: "k", since: 0, ended: null, lang: "zh" }, "zh", { told: true });
    await readers.read("turnNotices", { key: "missing", since: 0, ended: null, lang: "zh" }, "zh", { told: true });
    assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM archive_last_guard").get()?.n, 0);
    assert.deepEqual(batches.map((ids) => ids.sort((a, b) => a - b)), [threads]);
    previous.resolve();
    const result = JSON.parse(await waiting);
    assert.deepEqual(result.notices.map((n: any) => [n.kind, n.to, n.text, n.seq]).sort(),
      [["done", ["ada@x.com"], "edit-0-150", messages[0]], ["done", ["ada@x.com"], "edit-1-150", messages[1]]].sort());
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("cancelling one pending turn notice does not cancel another for the same chat", async () => {
  const dir = mkdtempSync(join(tmpdir(), "notice-last-cancel-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  const controller = new AbortController();
  try {
    store.insertSession({ key: "k", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w",
      token: "t", createdAt: 1, lastActiveAt: 1, createdBy: "ada@x.com" });
    const thread = store.openThread("ember", "CHAT", "notice-cancel", null, "ada@x.com").id;
    store.joinThread(thread, "k", "ember");
    store.startTurn("turn", "k", "input");
    const [message] = store.insertMessage(newMessage(thread, "1.1", "agent", "k", "before"));
    store.endTurn("turn", "completed", null, "final", null);
    const edit = store.db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?,'edit',?,'agent','k',?,?)`);
    store.db.exec("BEGIN");
    for (let n = 2; n <= 150; n++) edit.run(thread, n, message, `edit-${n}`, n);
    store.db.exec("COMMIT");
    store.db.exec("DROP INDEX entries_letters");
    const args = { key: "k", since: 0, ended: null, lang: "zh" };
    const abandoned = readers.read("turnNotices", args, "zh", { told: true, signal: controller.signal });
    const kept = readers.read("turnNotices", args, "zh", { told: true });
    await readers.read("turnNotices", { ...args, key: "missing" }, "zh", { told: true });
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM archive_last_guard").get()?.n, 0);
    previous.resolve();
    const result = JSON.parse(await kept);
    assert.deepEqual(result.notices.map((n: any) => [n.text, n.seq]), [["edit-150", message]]);
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
