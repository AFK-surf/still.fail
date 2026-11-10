import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { cardEditPage, cardMessagePage, cardOutcomeHeads, installCardOutbox, saveWithCardOutcome } from "../src/store/card-outbox.ts";
import { CardOutcomeWorker } from "../src/store/card-outbox-worker.ts";
import { installLegacyEdits, legacyMergedReadReady } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { MessageWriteBusy, Store } from "../src/store/store.ts";
import { installWidgetSources } from "../src/store/widget-sources.ts";
import { testClock } from "./hub-fakes.ts";

async function until(check: () => boolean, timeout = 5000): Promise<void> {
  const end = Date.now() + timeout;
  while (!check()) {
    if (Date.now() >= end) throw new Error("timed out waiting for card outcome");
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

function queue(store: Store, thread: number) {
  saveWithCardOutcome(store.db, { thread, ts: "card", agent: "a", field: "adb", close: true, outcome: { status: "granted" } }, () => {});
}

function longCard(store: Store, name: string): number {
  const db = store.db, thread = store.openThread("ember", "CHAT", name, null, null).id;
  db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
    VALUES(?,1,'message','card','agent','a','question',1,?)`).run(thread, JSON.stringify({ type: "text", adb: { reason: "original" } }));
  const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card) VALUES(?,?,'edit',?,'agent','a',?,?,?)");
  edit.run(thread, 2, 1, "old card", 2, JSON.stringify({ type: "text", adb: { reason: "old card" } }));
  for (let n = 3; n <= 82; n++) edit.run(thread, n, 1, `text ${n}`, n, null);
  for (let n = 83; n <= 162; n++) edit.run(thread, n, n + 1000, "other", n, JSON.stringify({ type: "text" }));
  return thread;
}

function shortCard(store: Store, name: string): number {
  const thread = store.openThread("ember", "CHAT", name, null, null).id;
  store.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
    VALUES(?,1,'message','card','agent','a','short',1,?)`).run(thread, JSON.stringify({ type: "text", adb: {} }));
  return thread;
}

test("a busy queued card retries on the store's clock", async () => {
  const time = testClock(), store = Store.open(":memory:", null, time.clock), db = store.db;
  let worker: CardOutcomeWorker | undefined;
  try {
    const thread = shortCard(store, "retry"); installCardOutbox(db); queue(store, thread);
    const restate = store.restateQueuedCard.bind(store);
    let attempts = 0;
    store.restateQueuedCard = (...args) => {
      if (++attempts === 1) throw new MessageWriteBusy();
      return restate(...args);
    };
    worker = new CardOutcomeWorker(store, Promise.resolve(), async (t, target, before) => cardEditPage(db, t, target, before),
      async (t, target, before) => cardMessagePage(db, t, target, before));
    await until(() => attempts === 1);
    await time.adjust(249);
    assert.equal(attempts, 1);
    assert.equal(cardOutcomeHeads(db, "0").length, 1);
    await time.adjust(1);
    await until(() => cardOutcomeHeads(db, "0").length === 0);
    assert.equal(attempts, 2);
  } finally { await worker?.close(); store.close(); }
});

test("a queued old card waits for handover and pages without delaying a short card", async () => {
  const store = Store.open(":memory:"), db = store.db;
  const previous = Promise.withResolvers<void>(), preparation = Promise.withResolvers<void>();
  let worker: CardOutcomeWorker | undefined;
  try {
    const old = longCard(store, "old"), short = shortCard(store, "short");
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    installLegacyEdits(db); addClientColumn(db); installWidgetSources(db); installCardOutbox(db);
    queue(store, old); queue(store, short);
    let reading = false;
    worker = new CardOutcomeWorker(store, previous.promise,
      async (thread, target, before) => cardEditPage(db, thread, target, before),
      async (thread, target, before) => {
        if (thread === old) { reading = true; await preparation.promise; }
        return cardMessagePage(db, thread, target, before);
      });
    worker.wake();
    await new Promise((resolve) => setTimeout(resolve, 30));
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM closed_cards").get()?.n, 0);
    previous.resolve();
    await until(() => reading && db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(short)?.n === 1);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(old)?.n, 0);
    preparation.resolve();
    await until(() => cardOutcomeHeads(db, "0").length === 0);
    assert.equal(legacyMergedReadReady(db), false, "the card does not wait for the whole old edit index");
    const last = db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(old)!;
    assert.equal(last.text, "text 82");
    assert.deepEqual(JSON.parse(String(last.card)).adb, { reason: "old card", outcome: { status: "granted" } });
  } finally { previous.resolve(); preparation.resolve(); await worker?.close(); store.close(); }
});

test("a changed card is reread after a paged result becomes stale", async () => {
  const store = Store.open(":memory:"), db = store.db;
  let worker: CardOutcomeWorker | undefined;
  try {
    const thread = longCard(store, "race"); installCardOutbox(db); queue(store, thread);
    let changed = false;
    worker = new CardOutcomeWorker(store, Promise.resolve(), async (t, target, before) => {
      const page = cardEditPage(db, t, target, before);
      if (!changed) {
        changed = true;
        db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card)
          VALUES(?,163,'edit',1,'agent','a','concurrent',163,?)`)
          .run(thread, JSON.stringify({ type: "text", adb: { reason: "concurrent" } }));
      }
      return page;
    }, async (t, target, before) => cardMessagePage(db, t, target, before));
    await until(() => cardOutcomeHeads(db, "0").length === 0);
    assert.equal(changed, true);
    const last = db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)!;
    assert.equal(last.text, "concurrent");
    assert.deepEqual(JSON.parse(String(last.card)).adb, { reason: "concurrent", outcome: { status: "granted" } });
  } finally { await worker?.close(); store.close(); }
});

test("an old message changed during its paged lookup is reread before recording an outcome", async () => {
  const store = Store.open(":memory:"), db = store.db;
  let worker: CardOutcomeWorker | undefined;
  try {
    const thread = longCard(store, "old-race");
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    installLegacyEdits(db); addClientColumn(db); installWidgetSources(db); installCardOutbox(db); queue(store, thread);
    let changed = false;
    worker = new CardOutcomeWorker(store, Promise.resolve(), async (t, target, before) => cardEditPage(db, t, target, before),
      async (t, target, before) => {
        const page = cardMessagePage(db, t, target, before);
        if (!changed) {
          changed = true;
          db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card)
            VALUES(?,163,'edit',1,'agent','a','new text',163,?)`)
            .run(thread, JSON.stringify({ type: "text", adb: { reason: "new card" } }));
        }
        return page;
      });
    await until(() => cardOutcomeHeads(db, "0").length === 0);
    assert.equal(changed, true);
    const last = db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)!;
    assert.equal(last.text, "new text");
    assert.deepEqual(JSON.parse(String(last.card)).adb, { reason: "new card", outcome: { status: "granted" } });
    assert.equal(legacyMergedReadReady(db), false);
  } finally { await worker?.close(); store.close(); }
});

test("stopping during a card scan leaves its result for the next worker", async () => {
  const store = Store.open(":memory:"), db = store.db;
  let worker: CardOutcomeWorker | undefined, restarted: CardOutcomeWorker | undefined;
  try {
    const thread = longCard(store, "stop"); installCardOutbox(db); queue(store, thread);
    let reading = false;
    worker = new CardOutcomeWorker(store, Promise.resolve(), async (_thread, _target, _before, signal) => {
      reading = true;
      return await new Promise<never>((_resolve, reject) => signal.addEventListener("abort", () => reject(new Error("stopped")), { once: true }));
    }, async (t, target, before) => cardMessagePage(db, t, target, before));
    await until(() => reading);
    await worker.close(); worker = undefined;
    assert.equal(cardOutcomeHeads(db, "0").length, 1);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(thread)?.n, 0);
    restarted = new CardOutcomeWorker(store, Promise.resolve(),
      async (t, target, before) => cardEditPage(db, t, target, before),
      async (t, target, before) => cardMessagePage(db, t, target, before));
    await until(() => cardOutcomeHeads(db, "0").length === 0);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(thread)?.n, 1);
  } finally { await worker?.close(); await restarted?.close(); store.close(); }
});

test("ready cards still finish while all card scan slots are busy", async () => {
  const store = Store.open(":memory:"), db = store.db;
  let worker: CardOutcomeWorker | undefined;
  try {
    installCardOutbox(db);
    for (let n = 0; n < 4; n++) queue(store, longCard(store, `busy-${n}`));
    const short = shortCard(store, "ready"); queue(store, short);
    let reading = 0;
    worker = new CardOutcomeWorker(store, Promise.resolve(), async (_thread, _target, _before, signal) => {
      reading++;
      return await new Promise<never>((_resolve, reject) => signal.addEventListener("abort", () => reject(new Error("stopped")), { once: true }));
    }, async (t, target, before) => cardMessagePage(db, t, target, before));
    await until(() => reading === 4 && db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(short)?.n === 1);
    assert.equal(cardOutcomeHeads(db, "0").length, 4);
  } finally { await worker?.close(); store.close(); }
});

test("a queued old card is paged by real readers without preparing the whole edit index", async () => {
  const dir = mkdtempSync(join(tmpdir(), "card-outbox-readers-"));
  const store = Store.open(join(dir, "stillfail.db")), db = store.db, previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  let worker: CardOutcomeWorker | undefined;
  try {
    const thread = longCard(store, "real-readers");
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    installLegacyEdits(db); addClientColumn(db); installWidgetSources(db); installCardOutbox(db); queue(store, thread);
    worker = new CardOutcomeWorker(store, previous.promise,
      (t, target, before, signal) => readers.cardEditPage(t, target, before, signal),
      (t, target, before, signal) => readers.cardMessagePage(t, target, before, signal));
    previous.resolve();
    await until(() => cardOutcomeHeads(db, "0").length === 0, 30_000);
    assert.equal(legacyMergedReadReady(db), false);
    const last = db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)!;
    assert.equal(last.text, "text 82");
    assert.deepEqual(JSON.parse(String(last.card)).adb, { reason: "old card", outcome: { status: "granted" } });
  } finally { previous.resolve(); await worker?.close(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
