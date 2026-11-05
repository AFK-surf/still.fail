import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { autoArchive, startAutoArchiveTimer } from "../src/sessions/lifecycle.ts";
import { saidScanStep, type SaidScan } from "../src/store/said-state.ts";
import { Store } from "../src/store/store.ts";
import { Rig } from "./hub-fakes.ts";

const later = () => Date.now() + 3 * 86_400_000;

function chat(r: Rig, name: string, who: "agent" | "person", firstOther = false) {
  const thread = r.store.openThread("ember", "EMBER", name, null, "me").id;
  const put = r.store.db.prepare("INSERT INTO entries (thread,n,kind,author_kind,author,text,at) VALUES (?,?,'message',?,?,?,?)");
  r.store.db.exec("BEGIN");
  if (firstOther) put.run(thread, 1, "agent", "a", "first", 1);
  for (let n = 2; n <= 5_001; n++) put.run(thread, n, who, who === "agent" ? "a" : "me", "hello", n);
  r.store.db.exec("COMMIT");
  return thread;
}

function track(r: Rig) {
  const db = r.store.db;
  let visited = 0;
  db.function("visit_archive_unread", (_n) => { visited++; return 1; });
  Object.defineProperty(r.store, "db", { configurable: true, value: new Proxy(db, {
    get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(
        sql.includes("SELECT COUNT(*) AS c FROM entries")
          ? sql.replace("AND NOT (author_kind", "AND visit_archive_unread(n) IS NOT NULL AND NOT (author_kind")
          : sql.includes("INDEXED BY entries_said") && sql.includes("ORDER BY n DESC")
            ? sql.replace("ORDER BY n DESC", "AND visit_archive_unread(n) IS NOT NULL ORDER BY n DESC")
            : sql,
      );
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  }) });
  return { visited: () => visited, restore: () => Object.defineProperty(r.store, "db", { configurable: true, value: db }) };
}

function timers() {
  let next: { ms: number; run: () => void } | null = null;
  return {
    after(ms: number, run: () => void) {
      const task = { ms, run }; next = task;
      return () => { if (next === task) next = null; };
    },
    fire(ms: number) {
      const task = next; assert.ok(task); assert.equal(task.ms, ms);
      next = null; task.run();
    },
    pending: () => next?.ms ?? null,
  };
}

test("auto-archive does not count a long run of unread messages", async () => {
  const r = new Rig();
  try {
    const thread = chat(r, "unread", "agent");
    const trace = track(r);
    try {
      autoArchive(r.hub, later());
      assert.equal(r.store.getThread(thread)?.hiddenAt, null);
      assert.ok(trace.visited() <= 64, `the decision visited ${trace.visited()} messages`);
    } finally { trace.restore(); }
  } finally { await r.close(); }
});

test("auto-archive does not scan a long run of the starter's messages", async () => {
  const r = new Rig();
  try {
    const thread = chat(r, "own", "person", true);
    r.store.setRead("me", thread, 1);
    const trace = track(r);
    try {
      autoArchive(r.hub, later());
      assert.notEqual(r.store.getThread(thread)?.hiddenAt, null);
      assert.ok(trace.visited() <= 64, `the decision visited ${trace.visited()} messages`);
    } finally { trace.restore(); }
  } finally { await r.close(); }
});

test("the archive check ignores letters and the starter's messages", async () => {
  const r = new Rig();
  try {
    const thread = r.store.openThread("ember", "EMBER", "mixed", null, "me").id;
    const put = r.store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at,letter) VALUES (?,?,?,?,?,?,?,?)");
    put.run(thread, 1, "message", "person", "someone", "other", 1, null);
    put.run(thread, 2, "message", "person", "me", "mine", 2, null);
    put.run(thread, 3, "message", "person", "someone", "letter", 3, "{}");
    assert.equal(r.store.unreadForArchive("me", thread), true);
    r.store.setRead("me", thread, 1);
    assert.equal(r.store.unreadForArchive("me", thread), false);
    put.run(thread, 4, "message", "agent", "a", "answer", 4, null);
    assert.equal(r.store.unreadForArchive("me", thread), true);
    r.store.setRead("me", thread, 4);
    assert.equal(r.store.unreadForArchive("me", thread), false);
  } finally { await r.close(); }
});

test("the archive's unread decision reads one snapshot while another station writes", () => {
  const dir = mkdtempSync(join(tmpdir(), "archive-unread-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path);
  const other = new DatabaseSync(path);
  try {
    const thread = store.openThread("ember", "EMBER", "chat", null, "me").id;
    const put = "INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,?,'message',?,?,?,?)";
    store.db.prepare(put).run(thread, 1, "person", "me", "mine", 1);
    const read = store.readPosition.bind(store);
    let wrote = false;
    store.readPosition = (...args) => {
      const position = read(...args);
      if (!wrote) {
        wrote = true;
        other.prepare(put).run(thread, 2, "agent", "a", "new", 2);
      }
      return position;
    };
    assert.equal(store.unreadForArchive("me", thread), false);
    assert.equal(store.unreadForArchive("me", thread), true);
    store.readPosition = () => { throw new Error("read failed"); };
    assert.throws(() => store.unreadForArchive("me", thread), /read failed/);
    assert.doesNotThrow(() => store.db.exec("BEGIN; ROLLBACK"));
  } finally { other.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an old unknown boundary is prepared before archiving", async () => {
  const r = new Rig();
  try {
    const thread = chat(r, "old", "person", true);
    r.store.db.prepare("UPDATE thread_state SET said_other_known=0 WHERE thread=?").run(thread);
    const need: number[] = [];
    const trace = track(r);
    try {
      autoArchive(r.hub, later(), (id: number) => need.push(id));
      assert.equal(r.store.getThread(thread)?.hiddenAt, null, "unknown is not treated as read");
      assert.deepEqual(need, [thread]);
      assert.ok(trace.visited() <= 65, `the foreground visited ${trace.visited()} messages`);
    } finally { trace.restore(); }
    let scan: SaidScan | null = null;
    for (;;) {
      const next = saidScanStep(r.store.db, thread, scan);
      if (next.done) break;
      scan = next.scan;
    }
    autoArchive(r.hub, later());
    assert.equal(r.store.getThread(thread)?.hiddenAt, null, "the older unread message still keeps it open");
    r.store.setRead("me", thread, 1);
    autoArchive(r.hub, later());
    assert.notEqual(r.store.getThread(thread)?.hiddenAt, null, "once known, the read chat can be archived");
  } finally { await r.close(); }
});

test("the archive timer retries when the old boundary is ready", async () => {
  const r = new Rig();
  const time = timers();
  const ready = Promise.withResolvers<void>();
  const calls: number[][] = [];
  let stop = () => {};
  try {
    const thread = chat(r, "timer", "person", true);
    r.store.setRead("me", thread, 1);
    r.store.db.prepare("UPDATE threads SET created_at=0 WHERE id=?").run(thread);
    r.store.db.prepare("UPDATE thread_state SET said_other_known=0 WHERE thread=?").run(thread);
    stop = startAutoArchiveTimer(r.hub, time, { prepareSaid: (ids) => { calls.push([...ids]); return ready.promise; }, prepareSessionBindings: async () => {} });
    time.fire(60_000);
    assert.equal(r.store.getThread(thread)?.hiddenAt, null);
    assert.deepEqual(calls, [[thread]]);
    time.fire(600_000);
    assert.deepEqual(calls, [[thread]], "a slow worker is not started twice");
    let scan: SaidScan | null = null;
    for (;;) {
      const step = saidScanStep(r.store.db, thread, scan);
      if (step.done) break;
      scan = step.scan;
    }
    ready.resolve();
    await ready.promise;
    await Promise.resolve();
    time.fire(0);
    assert.notEqual(r.store.getThread(thread)?.hiddenAt, null);
  } finally { stop(); ready.resolve(); await r.close(); }
});

test("stopping the archive timer cancels its pending old-chat work", async () => {
  const r = new Rig();
  const time = timers();
  const ready = Promise.withResolvers<void>();
  let signal: AbortSignal | undefined;
  let stop = () => {};
  try {
    const thread = chat(r, "handover", "person", true);
    r.store.setRead("me", thread, 1);
    r.store.db.prepare("UPDATE threads SET created_at=0 WHERE id=?").run(thread);
    r.store.db.prepare("UPDATE thread_state SET said_other_known=0 WHERE thread=?").run(thread);
    stop = startAutoArchiveTimer(r.hub, time, { prepareSaid: (_ids, s) => { signal = s; return ready.promise; }, prepareSessionBindings: async () => {} });
    time.fire(60_000);
    stop();
    assert.equal(signal?.aborted, true);
    ready.resolve();
    await ready.promise;
    await Promise.resolve();
    assert.equal(time.pending(), null);
    assert.equal(r.store.getThread(thread)?.hiddenAt, null);
  } finally { stop(); ready.resolve(); await r.close(); }
});
