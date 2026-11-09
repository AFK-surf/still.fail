import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { setTimeout as pause } from "node:timers/promises";
import { pathToFileURL } from "node:url";
import { lastMessage, makeStore, messagesBefore, saidOf } from "../src/read/store.ts";
import { stationDocSteps, threadDocs } from "../src/search/sources.ts";
import { installLegacySaid, legacySaidDrain, legacySaidStep, publishLegacySaid } from "../src/store/legacy-said-build.ts";
import { buildLegacySaid } from "../src/store/legacy-said-builder.ts";
import { installSaidState } from "../src/store/said-state.ts";
import { toMessage } from "../src/store/rows.ts";
import { Store } from "../src/store/store.ts";
import { withoutSaidState } from "./legacy-message-fixture.ts";

for (const recursive of [false, true]) test(`old and native message writers keep the same sidebar boundary (recursive triggers ${recursive})`, () => {
  const stores = [Store.open(":memory:"), Store.open(":memory:")];
  try {
    const threads = stores.map((store) => {
      const db = store.db;
      db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      const thread = store.openThread("ember", "CHAT", "compare-said", null, null).id;
      const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,ts)
        VALUES(?,?,'message','person',?,?,?)`);
      for (let n=1;n<=20;n++) put.run(thread,n,n%2 ? "a" : "b",n,`seed-${n}`);
      return thread;
    });
    assert.equal(threads[0],threads[1]);
    const thread = threads[0], candidate = stores[1].db;
    installLegacySaid(candidate);
    candidate.exec("DROP INDEX entries_said");
    installSaidState(candidate);
    const readers = stores.map((s) => makeStore(s.db,"/none"));
    const check = (step: number) => {
      const snapshot = (db: DatabaseSync) => ({
        state: db.prepare(`SELECT last_n,said_n,person_n,letters,said_other_n,said_other_known
          FROM thread_state WHERE thread=?`).get(thread),
        guard: db.prepare("SELECT token,author,other_n,ready FROM said_state_guard WHERE thread=?").get(thread),
      });
      assert.deepEqual(snapshot(candidate),snapshot(stores[0].db),`state after write ${step}`);
      assert.deepEqual(saidOf(readers[1],thread),saidOf(readers[0],thread),`sidebar after write ${step}`);
    };
    let seed = 0x20261106;
    const next = (range: number) => { seed = (Math.imul(seed,1664525)+1013904223) >>> 0; return seed % range; };
    check(0);
    for (let i=1;i<=180;i++) {
      const n=1+next(45), author=next(3) === 0 ? "a" : "b", ts=`stamp-${next(12)}`;
      for (const store of stores) {
        const db = store.db;
        switch (i%7) {
          case 0: db.prepare("DELETE FROM entries WHERE thread=? AND n=?").run(thread,n); break;
          case 1: db.prepare("UPDATE entries SET author=? WHERE thread=? AND n=?").run(author,thread,n); break;
          case 2: db.prepare("UPDATE entries SET letter='letter' WHERE thread=? AND n=?").run(thread,n); break;
          case 3: db.prepare(`INSERT OR IGNORE INTO entries(thread,n,kind,author_kind,author,at,ts)
            VALUES(?,?,'message','person',?,?,?)`).run(thread,n,author,i,ts); break;
          default: db.prepare(`INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,letter,at,ts)
            VALUES(?,?,?,?,?,?,?,?)`).run(thread,n,i%7 === 4 ? "edit" : "message",i%5 === 0 ? "agent" : "person",
              author,i%11 === 0 ? "letter" : null,i,ts); break;
        }
      }
      if (i===60) while (!legacySaidStep(candidate,8).ready) { /* prepare */ }
      if (i>60 && i%19===0) legacySaidDrain(candidate,8);
      check(i);
    }
    while (legacySaidDrain(candidate,8)) check(181);
    check(182);
  } finally { for (const store of stores) store.close(); }
});

test("a prepared old message lookup serves the station, readers and search while old writers continue", () => {
  const dir = mkdtempSync(join(tmpdir(), "legacy-said-store-")), path = join(dir, "station.db");
  const initial = Store.open(path);
  const thread = initial.openThread("ember", "CHAT", "legacy-said", null, null).id;
  const putInitial = initial.db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,letter,ts)
    VALUES(?,?,?,?,?,?,?,?,?,?)`);
  putInitial.run(thread, 1, "message", null, "person", "viewer", "first", 1, null, "1");
  putInitial.run(thread, 2, "message", null, "person", "other", "second", 2, null, "2");
  putInitial.run(thread, 3, "message", null, "agent", "s", "letter", 3, '{"way":"in"}', "3");
  putInitial.run(thread, 4, "edit", 2, "person", "other", "second edited", 4, null, "4");
  initial.setRead("viewer", thread, 1);
  initial.close();

  const old = new DatabaseSync(path, { timeout: 5000 });
  let station: Store | null = null;
  try {
    withoutSaidState(old);
    const put = old.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at,ts)
      VALUES(?,?,'message',?,?,?,?,?)`);
    assert.equal(legacySaidStep(old, 2).ready, false);
    put.run(thread, 5, "agent", "s", "during preparation", 5, "5");
    while (!legacySaidStep(old, 2).ready) { /* bounded preparation */ }
    assert.equal(publishLegacySaid(old), true);
    station = Store.open(path);
    assert.equal(station.db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_said'").get(), undefined);
    const read = makeStore(station.db, dir);
    assert.equal(read.legacySaid, true);

    const check = () => {
      const expected = station!.db.prepare("SELECT * FROM merged WHERE thread=? ORDER BY n").all(thread).map(toMessage);
      assert.deepEqual(station!.messagesBefore(thread, null, 20), expected);
      assert.deepEqual(messagesBefore(read, thread, null, 20), expected);
      assert.deepEqual(station!.lastMessage(thread), expected.at(-1) ?? null);
      assert.deepEqual(lastMessage(read, thread), expected.at(-1) ?? null);
      const unread = station!.db.prepare(`SELECT COUNT(*) c FROM entries WHERE thread=? AND n>1 AND kind='message'
        AND letter IS NULL AND NOT (author_kind='person' AND author='viewer')`).get(thread)!.c;
      assert.equal(station!.unreadCount("viewer", thread), unread);
      const said = station!.db.prepare(`SELECT n,author_kind,author FROM entries WHERE thread=? AND kind='message'
        AND letter IS NULL ORDER BY n DESC LIMIT 1`).get(thread) as { n: number; author_kind: string; author: string } | undefined;
      const other = said?.author_kind !== "person" ? said?.n : station!.db.prepare(`SELECT n FROM entries WHERE thread=?
        AND kind='message' AND letter IS NULL AND NOT (author_kind='person' AND author=?) ORDER BY n DESC LIMIT 1`)
        .get(thread, said.author)?.n ?? null;
      assert.deepEqual(saidOf(read, thread), said ? { n: said.n, authorKind: said.author_kind, author: said.author, other } : null);
      assert.deepEqual(threadDocs(read, thread).filter((doc) => doc.kind === "message").map((doc) => doc.body), expected.map((m) => m.text));
      const chat = threadDocs(read, thread).find((doc) => doc.kind === "chat");
      assert.deepEqual([...stationDocSteps(read, dir, {}, new Set(["chat"]))].find((doc) => doc?.key === `c:${thread}`), chat);
    };
    check();
    put.run(thread, 6, "person", "viewer", "mine", 6, "6");
    put.run(thread, 7, "agent", "s", "new", 7, "7");
    old.prepare("UPDATE entries SET author='changed' WHERE thread=? AND n=2").run(thread);
    check();
    assert.deepEqual(saidOf(read, thread), { n: 7, authorKind: "agent", author: "s", other: 7 });
    while (legacySaidDrain(old, 2)) check();
    check();
  } finally {
    station?.close();
    old.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a large old store answers while its message lookup is prepared in batches", () => {
  const dir = mkdtempSync(join(tmpdir(), "legacy-said-live-")), path = join(dir, "station.db");
  const initial = Store.open(path);
  const thread = initial.openThread("ember", "CHAT", "legacy-live", null, null).id;
  const insert = initial.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at,ts)
    VALUES(?,?,'message','person',?,?,?,?)`);
  for (let n = 1; n <= 100; n++) insert.run(thread, n, n % 2 ? "viewer" : "other", `message-${n}`, n, `${n}`);
  initial.setRead("viewer", thread, 90);
  initial.close();

  const old = new DatabaseSync(path, { timeout: 5000 });
  let station: Store | null = null;
  try {
    withoutSaidState(old);
    station = Store.open(path);
    assert.equal(station.db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_said'").get(), undefined);
    assert.equal(station.db.prepare("SELECT scanned FROM legacy_said_meta WHERE id=1").get()?.scanned, 0);
    const read = makeStore(station.db, dir);
    const check = () => {
      const expected = station!.db.prepare("SELECT * FROM merged WHERE thread=? ORDER BY n").all(thread).map(toMessage);
      assert.deepEqual(station!.messagesBefore(thread, null, 3), expected.slice(-3));
      assert.deepEqual(messagesBefore(read, thread, null, 3), expected.slice(-3));
      assert.deepEqual(lastMessage(read, thread), expected.at(-1));
      const unread = station!.db.prepare(`SELECT COUNT(*) c FROM entries WHERE thread=? AND n>90 AND kind='message'
        AND letter IS NULL AND NOT (author_kind='person' AND author='viewer')`).get(thread)!.c;
      assert.equal(station!.unreadCount("viewer", thread), unread);
      assert.equal(threadDocs(read, thread).filter((doc) => doc.kind === "message").length, expected.length);
      const chat = threadDocs(read, thread).find((doc) => doc.kind === "chat");
      assert.deepEqual([...stationDocSteps(read, dir, {}, new Set(["chat"]))].find((doc) => doc?.key === `c:${thread}`), chat);
    };
    check();
    old.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at,ts)
      VALUES(?,101,'message','person','other','during',101,'101')`).run(thread);
    let step;
    do { step = legacySaidStep(old, 8); assert.ok(step.visited <= 8); check(); } while (!step.ready);
    assert.equal(publishLegacySaid(old), true);
    check();
    old.prepare("UPDATE entries SET author='viewer' WHERE thread=? AND n=100").run(thread);
    check();
    while (legacySaidDrain(old, 8)) check();
  } finally {
    station?.close(); old.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("the old message worker waits for handover, resumes its scan and reconciles later writes", async () => {
  const dir = mkdtempSync(join(tmpdir(), "legacy-said-builder-")), path = join(dir, "station.db");
  let station = Store.open(path);
  const thread = station.openThread("ember", "CHAT", "legacy-worker", null, null).id;
  const put = station.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at,ts)
    VALUES(?,?,'message','person','other',?,?,?)`);
  for (let n = 1; n <= 130; n++) put.run(thread, n, `message-${n}`, n, `${n}`);
  station.close();
  const old = new DatabaseSync(path, { timeout: 5000 });
  let builder: ReturnType<typeof buildLegacySaid> | null = null;
  try {
    withoutSaidState(old);
    station = Store.open(path);
    assert.deepEqual(legacySaidStep(old, 1), { ready: false, visited: 1 });
    const previous = Promise.withResolvers<void>();
    builder = buildLegacySaid(station, previous.promise);
    let settled = false;
    void builder.ready.then(() => { settled = true; });
    await Promise.resolve();
    assert.equal(settled, false);
    assert.equal(station.db.prepare("SELECT scanned FROM legacy_said_meta WHERE id=1").get()?.scanned, 0);
    assert.equal(station.lastMessage(thread)?.n, 130);
    previous.resolve();
    assert.equal(await builder.ready, true);
    assert.equal(station.db.prepare("SELECT scanned FROM legacy_said_meta WHERE id=1").get()?.scanned, 1);
    assert.equal(station.db.prepare("SELECT COUNT(*) c FROM legacy_said_dirty").get()?.c, 0);
    old.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at,ts)
      VALUES(?,131,'message','person','other','old writer',131,'131')`).run(thread);
    assert.equal(station.lastMessage(thread)?.n, 131, "the pending write is already readable");
    builder.wake();
    while (station.db.prepare("SELECT 1 FROM legacy_said_dirty LIMIT 1").get() !== undefined) await pause(10);
    assert.equal(station.lastMessage(thread)?.n, 131);
  } finally {
    await builder?.close(); station.close(); old.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("closing an old message worker while the previous station is still up settles its wait", async () => {
  const dir = mkdtempSync(join(tmpdir(), "legacy-said-close-")), path = join(dir, "station.db");
  let station = Store.open(path);
  const thread = station.openThread("ember", "CHAT", "legacy-close", null, null).id;
  const put = station.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','p',?)`);
  for (let n = 1; n <= 64; n++) put.run(thread, n, n);
  station.close();
  const old = new DatabaseSync(path);
  try {
    withoutSaidState(old);
    station = Store.open(path);
    const previous = Promise.withResolvers<void>();
    const builder = buildLegacySaid(station, previous.promise);
    await builder.close();
    assert.equal(await builder.ready, false);
    previous.resolve();
  } finally { station.close(); old.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a failed old message worker is retried from its saved scan", async () => {
  const dir = mkdtempSync(join(tmpdir(), "legacy-said-retry-")), path = join(dir, "station.db");
  const station = Store.open(path);
  let builder: ReturnType<typeof buildLegacySaid> | null = null;
  try {
    const thread = station.openThread("ember", "CHAT", "legacy-retry", null, null).id;
    const put = station.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','p',?)`);
    for (let n = 1; n <= 130; n++) put.run(thread, n, n);
    installLegacySaid(station.db);
    assert.deepEqual(legacySaidStep(station.db, 1), { ready: false, visited: 1 });
    const flag = join(dir, "worker-failed"), script = join(dir, "flaky-worker.mjs");
    const worker = new URL("../src/sessions/workspace-activity-worker.ts", import.meta.url).href;
    writeFileSync(script, `import { existsSync, writeFileSync } from 'node:fs';\n` +
      `if (!existsSync(${JSON.stringify(flag)})) { writeFileSync(${JSON.stringify(flag)}, 'failed'); process.exit(1); }\n` +
      `await import(${JSON.stringify(worker)});\n`);
    builder = buildLegacySaid(station, Promise.resolve(), pathToFileURL(script));
    assert.equal(await builder.ready, true);
    assert.equal(existsSync(flag), true);
    assert.equal(station.db.prepare("SELECT scanned FROM legacy_said_meta WHERE id=1").get()?.scanned, 1);
    assert.equal(station.db.prepare("SELECT COUNT(*) c FROM legacy_said WHERE thread=?").get(thread)?.c, 130);
  } finally { await builder?.close(); station.close(); rmSync(dir, { recursive: true, force: true }); }
});
