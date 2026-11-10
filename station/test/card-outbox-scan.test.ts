import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { cardEditPage, cardOutcomeHeads, installCardOutbox, saveWithCardOutcome, type CardEditScan } from "../src/store/card-outbox.ts";
import { MessageWriteBusy, Store } from "../src/store/store.ts";

function rig() {
  const dir = mkdtempSync(join(tmpdir(), "card-outbox-scan-")), path = join(dir, "station.sqlite");
  const store = Store.open(path), db = store.db, other = new DatabaseSync(path, { timeout: 5000 });
  const thread = store.openThread("ember", "CHAT", "old", null, null).id;
  db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
    VALUES(?,1,'message','card','agent','a','question',1,?)`).run(thread, JSON.stringify({ type: "text", adb: { reason: "original" } }));
  const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card) VALUES(?,?,'edit',?,'agent','a',?,?,?)");
  edit.run(thread, 2, 1, "old card", 2, JSON.stringify({ type: "text", adb: { reason: "old card" } }));
  for (let n = 3; n <= 82; n++) edit.run(thread, n, 1, `text ${n}`, n, null);
  for (let n = 83; n <= 162; n++) edit.run(thread, n, n + 1000, "other", n, JSON.stringify({ type: "text" }));
  installCardOutbox(db);
  saveWithCardOutcome(db, { thread, ts: "card", agent: "a", field: "adb", close: true, outcome: { status: "granted" } }, () => {});
  const item = cardOutcomeHeads(db, "0")[0]!;
  const close = () => { other.close(); store.close(); rmSync(dir, { recursive: true, force: true }); };
  return { store, db, other, thread, item, close };
}

function readCard(db: DatabaseSync, scan: CardEditScan): string | null {
  let before: string | null = null;
  for (;;) {
    db.exec("SAVEPOINT card_page");
    let page: ReturnType<typeof cardEditPage>;
    try { page = cardEditPage(db, scan.thread, scan.target, before); }
    finally { db.exec("RELEASE card_page"); }
    if (page.kind === "found") return page.card;
    if (page.kind === "end") return null;
    before = page.before;
  }
}

test("a guarded multi-page card lookup applies its outcome once", () => {
  const r = rig();
  try {
    assert.equal(r.store.restateQueuedCard(r.item), undefined);
    const scan = r.store.beginCardEditScan(r.item)!;
    const card = readCard(r.db, scan);
    assert.equal(r.store.restateQueuedCard(r.item, { scan, card }), true);
    const last = r.db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
    assert.equal(last.text, "text 82");
    assert.deepEqual(JSON.parse(String(last.card)).adb, { reason: "old card", outcome: { status: "granted" } });
    assert.deepEqual(cardOutcomeHeads(r.db, "0"), []);
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM restate_guard").get()?.n, 0);
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM card_scan_guard").get()?.n, 0);
  } finally { r.close(); }
});

test("a card edited while its old cards are paged is checked again", () => {
  const r = rig();
  try {
    const scan = r.store.beginCardEditScan(r.item)!;
    const page = cardEditPage(r.db, r.thread, scan.target, null);
    assert.equal(page.kind, "next");
    r.other.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card)
      VALUES(?,163,'edit',1,'agent','a','concurrent text',163,?)`)
      .run(r.thread, JSON.stringify({ type: "text", adb: { reason: "concurrent card" } }));
    const oldCard = readCard(r.db, scan);
    assert.equal(r.store.restateQueuedCard(r.item, { scan, card: oldCard }), undefined);
    assert.deepEqual(cardOutcomeHeads(r.db, "0"), [r.item]);
    assert.equal(r.store.restateQueuedCard(r.item), true);
    const last = r.db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
    assert.equal(last.text, "concurrent text");
    assert.deepEqual(JSON.parse(String(last.card)).adb, { reason: "concurrent card", outcome: { status: "granted" } });
  } finally { r.close(); }
});

test("another message in the same conversation does not invalidate a card scan", () => {
  const r = rig();
  try {
    const scan = r.store.beginCardEditScan(r.item)!;
    const card = readCard(r.db, scan);
    r.other.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at)
      VALUES(?,163,'message','other','person','p','another message',163)`).run(r.thread);
    assert.equal(r.store.restateQueuedCard(r.item, { scan, card }), true);
    const last = r.db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
    assert.equal(last.text, "text 82");
    assert.deepEqual(JSON.parse(String(last.card)).adb, { reason: "old card", outcome: { status: "granted" } });
  } finally { r.close(); }
});

test("another consumer's scan cannot finish using an older guard", () => {
  const r = rig();
  try {
    const first = r.store.beginCardEditScan(r.item)!;
    const card = readCard(r.db, first);
    const second = r.store.beginCardEditScan(r.item)!;
    assert.equal(r.store.restateQueuedCard(r.item, { scan: first, card }), undefined);
    assert.equal(r.store.restateQueuedCard(r.item, { scan: second, card: readCard(r.db, second) }), true);
    assert.deepEqual(cardOutcomeHeads(r.db, "0"), []);
  } finally { r.close(); }
});

test("two different cards in one conversation can be scanned at once", () => {
  const r = rig();
  try {
    r.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,163,'message','second','agent','a','second question',163,?)`)
      .run(r.thread, JSON.stringify({ type: "text", adb: { reason: "second" } }));
    saveWithCardOutcome(r.db, { thread: r.thread, ts: "second", agent: "a", field: "adb", close: true, outcome: { status: "denied" } }, () => {});
    const secondItem = cardOutcomeHeads(r.db, r.item.id)[0]!;
    const first = r.store.beginCardEditScan(r.item)!, second = r.store.beginCardEditScan(secondItem)!;
    const firstCard = readCard(r.db, first), secondCard = readCard(r.db, second);
    assert.equal(r.store.restateQueuedCard(r.item, { scan: first, card: firstCard }), true);
    assert.equal(r.store.restateQueuedCard(secondItem, { scan: second, card: secondCard }), true);
    assert.deepEqual(cardOutcomeHeads(r.db, "0"), []);
  } finally { r.close(); }
});

for (const recursive of [false, true]) for (const operation of ["insert", "update"] as const) {
  test(`a rowid ${operation} replacement invalidates the displaced card edit (recursive ${recursive})`, () => {
    const r = rig();
    try {
      const other = r.store.openThread("ember", "CHAT", "other", null, null).id;
      if (operation === "update") r.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at)
        VALUES(?,1,'message','other','person','p','other',1)`).run(other);
      r.other.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      const scan = r.store.beginCardEditScan(r.item)!, card = readCard(r.db, scan);
      const rowid = r.db.prepare("SELECT rowid FROM entries WHERE thread=? AND n=2").get(r.thread)!.rowid;
      if (operation === "insert") r.other.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,kind,ts,author_kind,author,text,at)
        VALUES(?,?,1,'message','other','person','p','other',1)`).run(rowid as number, other);
      else r.other.prepare("UPDATE OR REPLACE entries SET rowid=? WHERE thread=? AND n=1").run(rowid as number, other);
      assert.equal(r.store.restateQueuedCard(r.item, { scan, card }), undefined);
      assert.deepEqual(cardOutcomeHeads(r.db, "0"), [r.item]);
    } finally { r.close(); }
  });

  test(`a timestamp ${operation} replacement invalidates the displaced card edit (recursive ${recursive})`, () => {
    const r = rig();
    try {
      r.db.prepare(`INSERT INTO entries(thread,n,kind,target,ts,author_kind,author,text,at,card)
        VALUES(?,163,'edit',1,'edit-ts','agent','a','new card',163,?)`)
        .run(r.thread, JSON.stringify({ type: "text", adb: { reason: "new card" } }));
      if (operation === "update") r.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at)
        VALUES(?,164,'message','other','person','p','other',164)`).run(r.thread);
      r.other.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      const scan = r.store.beginCardEditScan(r.item)!, card = readCard(r.db, scan);
      if (operation === "insert") r.other.prepare(`INSERT OR REPLACE INTO entries(thread,n,kind,ts,author_kind,author,text,at)
        VALUES(?,164,'message','edit-ts','person','p','other',164)`).run(r.thread);
      else r.other.prepare("UPDATE OR REPLACE entries SET ts='edit-ts' WHERE thread=? AND n=164").run(r.thread);
      assert.equal(r.store.restateQueuedCard(r.item, { scan, card }), undefined);
      assert.deepEqual(cardOutcomeHeads(r.db, "0"), [r.item]);
    } finally { r.close(); }
  });
}

test("a schema change during a card scan invalidates its result", () => {
  const r = rig();
  try {
    const scan = r.store.beginCardEditScan(r.item)!;
    const card = readCard(r.db, scan);
    r.other.exec("DROP INDEX entries_cards");
    assert.equal(r.store.restateQueuedCard(r.item, { scan, card }), undefined);
    assert.deepEqual(cardOutcomeHeads(r.db, "0"), [r.item]);
  } finally { r.close(); }
});

test("a removed guard trigger invalidates an active scan and is restored for the next one", () => {
  const r = rig();
  try {
    const first = r.store.beginCardEditScan(r.item)!, card = readCard(r.db, first);
    r.other.exec("DROP TRIGGER card_scan_add");
    r.other.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card)
      VALUES(?,163,'edit',1,'agent','a','changed',163,?)`)
      .run(r.thread, JSON.stringify({ type: "text", adb: { reason: "changed" } }));
    assert.equal(r.store.restateQueuedCard(r.item, { scan: first, card }), undefined);
    const second = r.store.beginCardEditScan(r.item)!;
    assert.equal(r.store.restateQueuedCard(r.item, { scan: second, card: readCard(r.db, second) }), true);
    const last = r.db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
    assert.equal(last.text, "changed");
    assert.deepEqual(JSON.parse(String(last.card)).adb, { reason: "changed", outcome: { status: "granted" } });
  } finally { r.close(); }
});

test("a guard trigger replaced under the same name is restored before a scan", () => {
  const r = rig();
  try {
    const first = r.store.beginCardEditScan(r.item)!;
    r.store.endCardEditScan(first);
    r.other.exec(`DROP TRIGGER card_scan_add;
      CREATE TRIGGER card_scan_add BEFORE INSERT ON entries BEGIN SELECT 1; END`);
    const scan = r.store.beginCardEditScan(r.item)!, card = readCard(r.db, scan);
    r.other.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card)
      VALUES(?,163,'edit',1,'agent','a','changed',163,?)`)
      .run(r.thread, JSON.stringify({ type: "text", adb: { reason: "changed" } }));
    assert.equal(r.store.restateQueuedCard(r.item, { scan, card }), undefined);
    assert.match(String(r.db.prepare("SELECT sql FROM sqlite_master WHERE type='trigger' AND name='card_scan_add'").get()?.sql), /card_scan_guard_v1/);
  } finally { r.close(); }
});

test("a scan remains valid without the timestamp index and detects row replacements", () => {
  const r = rig();
  try {
    r.other.exec("DROP INDEX entries_ts");
    const scan = r.store.beginCardEditScan(r.item)!, card = readCard(r.db, scan);
    const rowid = r.db.prepare("SELECT rowid FROM entries WHERE thread=? AND n=2").get(r.thread)!.rowid;
    r.other.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,163,'message','person','p','replacement',163)`).run(rowid as number, r.thread);
    assert.equal(r.store.restateQueuedCard(r.item, { scan, card }), undefined);
  } finally { r.close(); }
});

test("queue guard registration yields to another writer", () => {
  const r = rig();
  try {
    r.db.exec("PRAGMA busy_timeout=5000");
    r.other.exec("BEGIN IMMEDIATE");
    const started = performance.now();
    assert.throws(() => r.store.beginCardEditScan(r.item), MessageWriteBusy);
    assert.ok(performance.now() - started < 1000, "guard registration does not wait for the other writer");
    assert.equal(r.db.prepare("PRAGMA busy_timeout").get()?.timeout, 5000);
    r.other.exec("ROLLBACK");
    assert.notEqual(r.store.beginCardEditScan(r.item), null);
  } finally { try { r.other.exec("ROLLBACK"); } catch {} r.close(); }
});
