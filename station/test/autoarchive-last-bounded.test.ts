import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { autoArchive, startAutoArchiveTimer } from "../src/sessions/lifecycle.ts";
import { archiveLastRead, archiveLastStep, installArchiveLast } from "../src/store/archive-last.ts";
import { Store } from "../src/store/store.ts";
import { Rig } from "./hub-fakes.ts";

function finish(db: DatabaseSync, thread: number) {
  let done = false;
  for (let i = 0; i < 100 && !done; i++) {
    const step = archiveLastStep(db, thread);
    assert.ok(step.visited <= 64, `one slice examined ${step.visited} entries`);
    done = step.done;
  }
  assert.ok(done, "the requested chat becomes readable");
}

test("the archive time follows message order, including letters and out-of-order times", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "archive-last-order", null, "me").id;
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: null });
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at,letter)
      VALUES(?,?,?,'person','me','text',?,?)`);
    put.run(thread, 1, "message", 999, null);
    put.run(thread, 2, "message", 10, "{}");
    put.run(thread, 3, "edit", 1000, "{}");
    assert.equal(store.lastMessage(thread)?.createdAt, 10);
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 10 });
    put.run(thread, 4, "message", 0, null);
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 0 });
  } finally { store.close(); }
});

for (const scenario of ["non-message-letters", "missing-letter-index"] as const) {
  test(`archive last message stays bounded with ${scenario}`, () => {
    const visits: number[] = [];
    for (const size of [80, 800]) {
      const store = Store.open(":memory:"), db = store.db;
      try {
        const thread = store.openThread("ember", "CHAT", `${scenario}-${size}`, null, "me").id;
        const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,ts,at,letter)
          VALUES(?,?,?,?,?,?,?,?,?)`);
        put.run(thread, 1, "message", "person", "me", "message", "t1", 1, null);
        for (let n = 2; n <= size + 1; n++) put.run(thread, n, "edit", "person", "me", "edit", `t${n}`, n,
          scenario === "non-message-letters" ? "{}" : null);
        if (scenario === "missing-letter-index") db.exec("DROP INDEX entries_letters");
        installArchiveLast(db);
        let visited = 0, observed = false;
        db.function("visited_archive_entry", (n) => { visited++; return n; });
        const counted = new Proxy(db, { get(target, property) {
          if (property === "prepare") return (sql: string) => {
            const changed = sql.replace(/e\.thread=(\?1|\?)(?!\d)/g,
              (_match, parameter: string) => `e.thread=${parameter} AND visited_archive_entry(e.n)=e.n`);
            if (changed !== sql && sql.includes("FROM entries e")) observed = true;
            return target.prepare(changed);
          };
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        } });
        const before = archiveLastRead(counted, thread);
        assert.ok(observed && visited > 0, "the entry lookup was observed");
        visits.push(visited);
        if (!before.known) finish(counted, thread);
        assert.deepEqual(archiveLastRead(counted, thread), { known: true, at: 1 });
      } finally { store.close(); }
    }
    assert.ok(visits[1]! <= visits[0]! + 2 && visits[1]! <= 70,
      `archive candidates for 80 / 800 entries: ${visits.join(" / ")}`);
  });
}

for (const recursive of [false, true]) for (const operation of ["insert", "rowid", "_rowid_", "oid"] as const)
  test(`a rowid ${operation} replacement invalidates another chat's answer (recursive ${recursive})`, () => {
  const dir = mkdtempSync(join(tmpdir(), "archive-last-replace-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db, old = new DatabaseSync(path);
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    old.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    installArchiveLast(db);
    const a = store.openThread("ember", "CHAT", "replace-a", null, "me").id;
    const b = store.openThread("ember", "CHAT", "replace-b", null, "me").id;
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,ts,at)
      VALUES(?,?,'message','person','me','message',?,?)`);
    put.run(b, 1, "older", 1); put.run(b, 2, "newer", 2);
    const victim = db.prepare("SELECT rowid FROM entries WHERE thread=? AND n=2").get(b)!.rowid;
    const edit = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,ts,at)
      VALUES(?,?,'edit','person','me','edit',?,?)`);
    for (let n = 3; n < 90; n++) edit.run(b, n, `edit${n}`, n);
    if (operation !== "insert") edit.run(a, 1, "replacement", 100);
    finish(db, b);
    assert.deepEqual(archiveLastRead(db, b), { known: true, at: 2 });
    if (operation === "insert") old.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,kind,author_kind,author,text,ts,at)
      VALUES(?,?,1,'edit','person','me','replacement','replacement',100)`).run(victim as number, a);
    else old.prepare(`UPDATE OR REPLACE entries SET ${operation}=? WHERE thread=? AND n=1`).run(victim as number, a);
    const after = archiveLastRead(db, b);
    if (!after.known) finish(db, b);
    assert.deepEqual(archiveLastRead(db, b), { known: true, at: 1 });
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const timing of ["BEFORE", "AFTER"] as const) for (const recursive of [false, true])
  for (const installFirst of [false, true]) for (const operation of ["append", "delete", "replace"] as const)
    test(`a nested ${timing} ${operation} preserves the archive time (recursive ${recursive}, installed first ${installFirst})`, () => {
      const store = Store.open(":memory:"), db = store.db;
      try {
        db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
        const thread = store.openThread("ember", "CHAT", "nested-last", null, "me").id;
        const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at)
          VALUES(?,?,?,'person','me',?)`);
        db.exec("BEGIN");
        put.run(thread, 1, "message", 1); put.run(thread, 2, "message", 2);
        for (let n = 3; n < 90; n++) put.run(thread, n, "edit", n);
        db.exec("COMMIT");

        if (installFirst) db.exec("DROP TRIGGER archive_last_insert");
        const change = operation === "append"
          ? `INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(${thread},180,'message','person','me',99);`
          : operation === "delete"
            ? `DELETE FROM entries WHERE thread=${thread} AND n=2;`
            : `INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,at) VALUES(${thread},2,'edit','person','me',2);`;
        db.exec(`CREATE TRIGGER nested_archive_last ${timing} INSERT ON entries
          WHEN NEW.thread=${thread} AND NEW.n=200 BEGIN ${change} END`);
        assert.ok(installArchiveLast(db));
        finish(db, thread);
        assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 2 });

        db.exec("BEGIN");
        put.run(thread, 200, "edit", 200);
        for (let n = 201; n < 270; n++) put.run(thread, n, "edit", n);
        db.exec("COMMIT");
        if (!archiveLastRead(db, thread).known) finish(db, thread);
        assert.deepEqual(archiveLastRead(db, thread), { known: true, at: operation === "append" ? 99 : 1 });
      } finally { store.close(); }
    });

for (const conflict of ["number", "timestamp"] as const) for (const action of ["REPLACE", "IGNORE"] as const)
  for (const method of ["insert", "update"] as const)
  test(`an ${action} ${method} by ${conflict} preserves the archive time`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("ember", "CHAT", "last-conflict", null, "me").id;
      const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,ts,at)
        VALUES(?,?,?,'person','me',?,?)`);
      db.exec("BEGIN");
      put.run(thread, 1, "message", "t1", 1); put.run(thread, 2, "message", "t2", 2);
      for (let n = 3; n < 90; n++) put.run(thread, n, "edit", `t${n}`, n);
      if (method === "update") put.run(thread, 90, "edit", "old", 90);
      db.exec("COMMIT");
      finish(db, thread);
      assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 2 });
      if (method === "insert") db.prepare(`INSERT OR ${action} INTO entries(thread,n,kind,author_kind,author,ts,at)
        VALUES(?,?,'edit','person','me',?,200)`).run(thread, conflict === "number" ? 2 : 200, conflict === "number" ? "new" : "t2");
      else db.prepare(`UPDATE OR ${action} entries SET ${conflict === "number" ? "n=2,ts='new'" : "ts='t2'"}
        WHERE thread=? AND n=90`).run(thread);
      if (!archiveLastRead(db, thread).known) finish(db, thread);
      assert.deepEqual(archiveLastRead(db, thread), { known: true, at: action === "REPLACE" ? 1 : 2 });
    } finally { store.close(); }
  });

test("two openers can share a long scan and an old write invalidates its previous answer", () => {
  const dir = mkdtempSync(join(tmpdir(), "archive-last-openers-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db, other = new DatabaseSync(path);
  try {
    installArchiveLast(db);
    const thread = store.openThread("ember", "CHAT", "two-openers", null, "me").id;
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,1,'message','person','me','message',1)`).run(thread);
    const edit = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'edit','person','me','edit',?)`);
    for (let n = 2; n <= 250; n++) edit.run(thread, n, n);
    let done = false;
    for (let i = 0; i < 20 && !done; i++) {
      const step = archiveLastStep(i % 2 === 0 ? db : other, thread);
      assert.ok(step.visited <= 64);
      done = step.done;
    }
    assert.ok(done);
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 1 });
    other.prepare("UPDATE entries SET at=99 WHERE thread=? AND n=1").run(thread);
    if (!archiveLastRead(db, thread).known) finish(db, thread);
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 99 });
  } finally { other.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an old writer changing an already-scanned range prevents a stale archive time", () => {
  const dir = mkdtempSync(join(tmpdir(), "archive-last-interleave-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db, other = new DatabaseSync(path);
  try {
    installArchiveLast(db);
    const thread = store.openThread("ember", "CHAT", "last-interleave", null, "me").id;
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,1,'message','person','me','message',1)`).run(thread);
    const edit = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'edit','person','me','edit',?)`);
    for (let n = 2; n <= 200; n++) edit.run(thread, n, n);
    assert.deepEqual(archiveLastStep(db, thread), { done: false, visited: 64 });
    other.prepare("UPDATE entries SET kind='message',at=99 WHERE thread=? AND n=180").run(thread);
    finish(db, thread);
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 99 });
  } finally { other.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an old prepared write invalidates an answer after the guard is installed", () => {
  const dir = mkdtempSync(join(tmpdir(), "archive-last-prepared-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db, old = new DatabaseSync(path);
  try {
    db.exec("DROP TRIGGER archive_last_insert");
    const put = old.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'message','person','me','message',?)`);
    installArchiveLast(db);
    const thread = store.openThread("ember", "CHAT", "last-prepared-write", null, "me").id;
    put.run(thread, 1, 1);
    const edit = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'edit','person','me','edit',?)`);
    for (let n = 2; n < 90; n++) edit.run(thread, n, n);
    finish(db, thread);
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 1 });
    put.run(thread, 90, 99);
    for (let n = 91; n < 160; n++) edit.run(thread, n, n);
    if (!archiveLastRead(db, thread).known) finish(db, thread);
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 99 });
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a missing guard trigger is restored without trusting an answer recorded while it was absent", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installArchiveLast(db);
    const thread = store.openThread("ember", "CHAT", "last-trigger-removed", null, "me").id;
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,1,'message','person','me','message',1)`).run(thread);
    const edit = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'edit','person','me','edit',?)`);
    for (let n = 2; n < 90; n++) edit.run(thread, n, n);
    finish(db, thread);
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 1 });
    db.exec("DROP TRIGGER archive_last_update");
    db.prepare("UPDATE entries SET at=99 WHERE thread=? AND n=1").run(thread);
    assert.equal(archiveLastRead(db, thread).known, false);
    finish(db, thread);
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 99 });
  } finally { store.close(); }
});

test("a failed slice rolls back and can resume", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installArchiveLast(db);
    const thread = store.openThread("ember", "CHAT", "last-rollback", null, "me").id;
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,1,'message','person','me','message',1)`).run(thread);
    const edit = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'edit','person','me','edit',?)`);
    for (let n = 2; n < 90; n++) edit.run(thread, n, n);
    db.exec(`CREATE TRIGGER fail_archive_last BEFORE UPDATE ON archive_last_guard
      BEGIN SELECT RAISE(ABORT,'stop archive scan'); END`);
    assert.throws(() => archiveLastStep(db, thread), /stop archive scan/);
    db.exec("DROP TRIGGER fail_archive_last");
    finish(db, thread);
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 1 });
  } finally { store.close(); }
});

test("rolling back an old write restores the previous archive answer", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "last-write-rollback", null, "me").id;
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,1,'message','person','me','message',1)`).run(thread);
    const edit = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'edit','person','me','edit',?)`);
    for (let n = 2; n < 90; n++) edit.run(thread, n, n);
    finish(db, thread);
    db.exec("BEGIN");
    db.prepare("UPDATE entries SET at=99 WHERE thread=? AND n=1").run(thread);
    assert.equal(archiveLastRead(db, thread).known, false);
    db.exec("ROLLBACK");
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 1 });
  } finally { store.close(); }
});

test("a scan preserves entry keys beyond JavaScript's exact integer range", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installArchiveLast(db);
    const thread = store.openThread("ember", "CHAT", "last-large-key", null, "me").id;
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,1,'message','person','me','message',1)`).run(thread);
    const edit = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'edit','person','me','edit',1)`);
    for (let n = 0n; n < 90n; n++) edit.run(thread, 9007199254741000n + n);
    assert.equal(archiveLastRead(db, thread).known, false);
    finish(db, thread);
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 1 });
  } finally { store.close(); }
});

test("an archive scan keeps its snapshot while another connection changes the last message", () => {
  const dir = mkdtempSync(join(tmpdir(), "archive-last-snapshot-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db, other = new DatabaseSync(path);
  try {
    installArchiveLast(db);
    const thread = store.openThread("ember", "CHAT", "last-snapshot", null, "me").id;
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,1,'message','person','me','message',1)`).run(thread);
    const edit = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'edit','person','me','edit',?)`);
    for (let n = 2; n < 90; n++) edit.run(thread, n, n);
    finish(db, thread);
    db.exec("BEGIN");
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 1 });
    other.prepare("UPDATE entries SET at=99 WHERE thread=? AND n=1").run(thread);
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 1 });
    db.exec("COMMIT");
    if (!archiveLastRead(db, thread).known) finish(db, thread);
    assert.deepEqual(archiveLastRead(db, thread), { known: true, at: 99 });
  } finally { other.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an interrupted scan can resume after reopening", () => {
  const dir = mkdtempSync(join(tmpdir(), "archive-last-reopen-")), path = join(dir, "stillfail.db");
  let store = Store.open(path);
  try {
    installArchiveLast(store.db);
    const thread = store.openThread("ember", "CHAT", "last-reopen", null, "me").id;
    store.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,1,'message','person','me','message',1)`).run(thread);
    const edit = store.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'edit','person','me','edit',?)`);
    for (let n = 2; n <= 150; n++) edit.run(thread, n, n);
    assert.deepEqual(archiveLastStep(store.db, thread), { done: false, visited: 64 });
    store.close();
    store = Store.open(path);
    assert.equal(archiveLastStep(store.db, thread).visited, 64);
    finish(store.db, thread);
    assert.deepEqual(archiveLastRead(store.db, thread), { known: true, at: 1 });
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("auto-archive waits for a long last-message scan and then checks the real time", async () => {
  const r = new Rig();
  try {
    const thread = r.store.openThread("ember", "CHAT", "last-auto-archive", null, "me").id;
    const db = r.store.db;
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,1,'message','person','me','message',1)`).run(thread);
    const edit = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'edit','person','me','edit',?)`);
    for (let n = 2; n < 150; n++) edit.run(thread, n, n);
    const now = Date.now() + 3 * 86_400_000;
    const requested: number[] = [];
    autoArchive(r.hub, now, undefined, undefined, undefined, undefined, (id) => requested.push(id));
    assert.equal(r.store.getThread(thread)?.hiddenAt, null);
    assert.deepEqual(requested, [thread]);
    finish(db, thread);
    autoArchive(r.hub, now);
    assert.notEqual(r.store.getThread(thread)?.hiddenAt, null);
  } finally { await r.close(); }
});

test("the requested worker waits for handover and prepares the last-message time", async () => {
  const dir = mkdtempSync(join(tmpdir(), "archive-last-worker-")), path = join(dir, "stillfail.db");
  const store = Store.open(path);
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const thread = store.openThread("ember", "CHAT", "last-worker", null, "me").id;
    store.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,1,'message','person','me','message',1)`).run(thread);
    const edit = store.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'edit','person','me','edit',?)`);
    for (let n = 2; n < 150; n++) edit.run(thread, n, n);
    assert.equal(store.lastMessageAtForArchive(thread).known, false);
    const first = readers.prepareArchiveLast([thread]);
    const second = readers.prepareArchiveLast([thread]);
    assert.equal(store.lastMessageAtForArchive(thread).known, false);
    previous.resolve();
    await Promise.all([first, second]);
    assert.deepEqual(store.lastMessageAtForArchive(thread), { known: true, at: 1 });
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("the archive timer retries after its last-message preparation finishes", async () => {
  const r = new Rig();
  const ready = Promise.withResolvers<void>();
  let next: { ms: number; run: () => void } | null = null;
  const time = { after(ms: number, run: () => void) {
    const task = { ms, run }; next = task;
    return () => { if (next === task) next = null; };
  } };
  const fire = (ms: number) => { const task = next; assert.ok(task); assert.equal(task.ms, ms); next = null; task.run(); };
  const calls: number[][] = [];
  let stop = () => {};
  try {
    const thread = r.store.openThread("ember", "CHAT", "last-timer", null, "me").id;
    const db = r.store.db;
    db.prepare("UPDATE threads SET created_at=0 WHERE id=?").run(thread);
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,1,'message','person','me','message',1)`).run(thread);
    const edit = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'edit','person','me','edit',?)`);
    for (let n = 2; n < 150; n++) edit.run(thread, n, n);
    stop = startAutoArchiveTimer(r.hub, time, {
      prepareSaid: async () => {}, prepareSessionBindings: async () => {}, prepareSessionUpJobs: async () => {},
      prepareArchiveLast: (threads) => { calls.push([...threads]); return ready.promise; },
    });
    fire(60_000);
    assert.equal(r.store.getThread(thread)?.hiddenAt, null);
    assert.deepEqual(calls, [[thread]]);
    finish(db, thread);
    ready.resolve();
    await Promise.resolve();
    fire(0);
    assert.notEqual(r.store.getThread(thread)?.hiddenAt, null);
  } finally { stop(); await r.close(); }
});
