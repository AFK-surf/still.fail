import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { autoArchive, startAutoArchiveTimer } from "../src/sessions/lifecycle.ts";
import { installSaidState, SAID_LATEST, SAID_SCAN, saidScanStep, type SaidScan } from "../src/store/said-state.ts";
import { installLegacySaid, legacySaidStep } from "../src/store/legacy-said-build.ts";
import { Store } from "../src/store/store.ts";
import { Rig } from "./hub-fakes.ts";

const later = () => Date.now() + 3 * 86_400_000;

function chat(r: Rig, name: string, who: "agent" | "person", firstOther = false) {
  const thread = r.store.openThread("ember", "CHAT", name, null, "me").id;
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
          : sql === SAID_LATEST || sql === SAID_SCAN
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
      assert.ok(trace.visited() > 0, "the unread lookup was observed");
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
      assert.ok(trace.visited() > 0, "the unread lookup was observed");
      assert.ok(trace.visited() <= 64, `the decision visited ${trace.visited()} messages`);
    } finally { trace.restore(); }
  } finally { await r.close(); }
});

test("the archive check ignores letters and the starter's messages", async () => {
  const r = new Rig();
  try {
    const thread = r.store.openThread("ember", "CHAT", "mixed", null, "me").id;
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
    const thread = store.openThread("ember", "CHAT", "chat", null, "me").id;
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

for (const scenario of ["changed-away","ignored"] as const) test(`archive unread reads bounded ${scenario} legacy keys`, () => {
  const counts: number[] = [];
  for (const size of [80,800]) {
    const dir = mkdtempSync(join(tmpdir(),"archive-unread-legacy-")), path = join(dir,"stillfail.db");
    let store = Store.open(path);
    const thread = store.openThread("ember","CHAT",`archive-${scenario}-${size}`,null,"me").id;
    const put = store.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,ts,at)
      VALUES(?,?,'message','person','me','text',?,?)`);
    put.run(thread,1,"occupied",1);
    if (scenario === "changed-away") for (let n=2;n<=size+1;n++) put.run(thread,n,`t${n}`,n);
    installLegacySaid(store.db);
    store.db.exec("DROP INDEX entries_said");
    installSaidState(store.db);
    while (!legacySaidStep(store.db,64).ready) { /* prepare */ }
    store.close();
    store = Store.open(path);
    const db = store.db;
    try {
      if (scenario === "changed-away") db.prepare("UPDATE entries SET letter='{}' WHERE thread=? AND n>1").run(thread);
      else {
        const ignored = db.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,author_kind,author,text,ts,at)
          VALUES(?,?,'message','person','me','text','occupied',?)`);
        for (let n=2;n<=size+1;n++) ignored.run(thread,n,n);
      }
      let visited = 0;
      db.function("visit_archive_legacy", (n) => { visited++; return n; });
      Object.defineProperty(store,"db",{ configurable:true,value:new Proxy(db,{ get(target,property) {
        if (property === "prepare") return (sql: string) => target.prepare(sql.replaceAll(
          "CROSS JOIN entries e ON e.thread=d.thread AND e.n=d.n",
          "CROSS JOIN entries e ON e.thread=d.thread AND e.n=visit_archive_legacy(d.n)")
          .replace("FROM entries e WHERE e.thread=?", "FROM entries e WHERE e.thread=? AND visit_archive_legacy(e.n)=e.n")
          .replace("FROM entries WHERE thread=? ORDER BY n DESC LIMIT 65",
            "FROM entries WHERE thread=? AND visit_archive_legacy(n)=n ORDER BY n DESC LIMIT 65")
          .replace("FROM entries WHERE thread=?1 AND n<?2 ORDER BY n DESC LIMIT 65",
            "FROM entries WHERE thread=?1 AND n<?2 AND visit_archive_legacy(n)=n ORDER BY n DESC LIMIT 65"));
        const value = Reflect.get(target,property,target);
        return typeof value === "function" ? value.bind(target) : value;
      } }) });
      let answer = store.unreadForArchive("me",thread);
      assert.ok(visited > 0, "the unread lookup was observed");
      counts.push(visited);
      if (answer === null) {
        let scan: SaidScan | null = null, done = false;
        for (let i=0;i<100 && !done;i++) {
          const step = saidScanStep(db,thread,scan);
          assert.ok(step.visited <= 64);
          scan = step.scan; done = step.done;
        }
        assert.ok(done,"the requested chat becomes readable");
        answer = store.unreadForArchive("me",thread);
      }
      assert.equal(answer,false);
    } finally {
      Object.defineProperty(store,"db",{ configurable:true,value:db });
      store.close(); rmSync(dir,{ recursive:true,force:true });
    }
  }
  assert.ok(counts[1]! <= counts[0]!+4 && counts[1]! <= 70,
    `archive unread candidates for 80 / 800 keys: ${counts.join(" / ")}`);
});

test("legacy archive unread keeps its snapshot while an old connection appends", () => {
  const dir = mkdtempSync(join(tmpdir(),"archive-unread-legacy-snapshot-")), path = join(dir,"stillfail.db");
  let store = Store.open(path);
  const thread = store.openThread("ember","CHAT","archive-legacy-snapshot",null,"me").id;
  store.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,ts,at)
    VALUES(? ,1,'message','person','me','mine','occupied',1)`).run(thread);
  installLegacySaid(store.db);
  store.db.exec("DROP INDEX entries_said");
  installSaidState(store.db);
  while (!legacySaidStep(store.db,64).ready) { /* prepare */ }
  store.close();
  store = Store.open(path);
  const other = new DatabaseSync(path);
  try {
    const ignored = store.db.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,author_kind,author,text,ts,at)
      VALUES(?,?,'message','person','me','mine','occupied',?)`);
    for (let n=3;n<=75;n++) ignored.run(thread,n,n);
    const read = store.readPosition.bind(store);
    let wrote = false;
    store.readPosition = (...args) => {
      const position = read(...args);
      if (!wrote) {
        other.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,ts,at)
          VALUES(?,2,'message','agent','worker','answer','new',2)`).run(thread);
        wrote = true;
      }
      return position;
    };
    assert.equal(store.unreadForArchive("me",thread),false);
    assert.equal(store.unreadForArchive("me",thread),true);
    assert.equal(wrote,true);
  } finally { other.close(); store.close(); rmSync(dir,{ recursive:true,force:true }); }
});

test("legacy archive waits for the older unread boundary when changed keys are pending", () => {
  const dir = mkdtempSync(join(tmpdir(),"archive-unread-legacy-boundary-")), path = join(dir,"stillfail.db");
  let store = Store.open(path);
  const thread = store.openThread("ember","CHAT","archive-legacy-boundary",null,"me").id;
  const put = store.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,ts,at)
    VALUES(?,?,'message',?,?,'text',?,?)`);
  put.run(thread,1,"agent","worker","occupied",1);
  for (let n=2;n<=150;n++) put.run(thread,n,"person","me",`t${n}`,n);
  installLegacySaid(store.db);
  store.db.exec("DROP INDEX entries_said");
  installSaidState(store.db);
  while (!legacySaidStep(store.db,64).ready) { /* prepare */ }
  store.close();
  store = Store.open(path);
  try {
    const ignored = store.db.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,author_kind,author,text,ts,at)
      VALUES(?,?,'message','person','me','mine','occupied',?)`);
    for (let n=200;n<300;n++) ignored.run(thread,n,n);
    assert.equal(store.unreadForArchive("me",thread),null);
    let scan: SaidScan | null = null, done = false;
    for (let i=0;i<20 && !done;i++) {
      const step = saidScanStep(store.db,thread,scan);
      assert.ok(step.visited <= 64);
      scan = step.scan; done = step.done;
    }
    assert.ok(done);
    assert.equal(store.unreadForArchive("me",thread),true);
    store.setRead("me",thread,1);
    assert.equal(store.unreadForArchive("me",thread),false);
  } finally { store.close(); rmSync(dir,{ recursive:true,force:true }); }
});

test("legacy archive can use a nearby unread boundary while changed keys are pending", () => {
  const dir = mkdtempSync(join(tmpdir(),"archive-unread-legacy-near-")), path = join(dir,"stillfail.db");
  let store = Store.open(path);
  const thread = store.openThread("ember","CHAT","archive-legacy-near",null,"me").id;
  const put = store.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,ts,at)
    VALUES(?,?,'message',?,?,'text',?,?)`);
  put.run(thread,1,"agent","worker","occupied",1);
  for (let n=2;n<=150;n++) put.run(thread,n,n===140 ? "agent" : "person",n===140 ? "worker" : "me",`t${n}`,n);
  installLegacySaid(store.db);
  store.db.exec("DROP INDEX entries_said");
  installSaidState(store.db);
  while (!legacySaidStep(store.db,64).ready) { /* prepare */ }
  store.close();
  store = Store.open(path);
  try {
    const ignored = store.db.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,author_kind,author,text,ts,at)
      VALUES(?,?,'message','person','me','mine','occupied',?)`);
    for (let n=200;n<300;n++) ignored.run(thread,n,n);
    assert.equal(store.unreadForArchive("me",thread),true);
    store.setRead("me",thread,140);
    assert.equal(store.unreadForArchive("me",thread),false);
  } finally { store.close(); rmSync(dir,{ recursive:true,force:true }); }
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
      assert.ok(trace.visited() > 0, "the unread lookup was observed");
      assert.ok(trace.visited() <= 65, `the unread decision visited ${trace.visited()} messages`);
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
    stop = startAutoArchiveTimer(r.hub, time, { prepareSaid: (ids) => { calls.push([...ids]); return ready.promise; }, prepareSessionBindings: async () => {}, prepareSessionUpJobs: async () => {} });
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
    stop = startAutoArchiveTimer(r.hub, time, { prepareSaid: (_ids, s) => { signal = s; return ready.promise; }, prepareSessionBindings: async () => {}, prepareSessionUpJobs: async () => {} });
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
