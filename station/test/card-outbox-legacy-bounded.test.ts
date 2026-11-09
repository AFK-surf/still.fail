import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { cardOutcomeHeads, installCardOutbox, saveWithCardOutcome } from "../src/store/card-outbox.ts";
import { installLegacyEdits, legacyEditsMaintenanceStep, legacyMergedReadReady } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";
import { installWidgetSources } from "../src/store/widget-sources.ts";

for (const shape of ["long", "short", "recent"] as const) test(`a queued result on an old ${shape} chat avoids an unprepared merged lookup`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "old", null, null).id;
    const size = shape === "short" ? 10 : 400;
    const message = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,?,'message',?,'person','p','other',?)");
    const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'person','p','other edit',?)");
    for (let n = 1; n <= size; n++) message.run(thread, n, `other-${n}`, n);
    for (let n = size + 1; n <= 2 * size; n++) edit.run(thread, n, n - size, n);
    const number = 2 * size + 1;
    db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,?,'message','card','agent','a','question',?,?)`)
      .run(thread, number, number, JSON.stringify({ type: "text", adb: { reason: "original" } }));
    if (shape === "recent") db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card)
      VALUES(?,?,'edit',?,'agent','a','changed question',?,?)`)
      .run(thread, number + 1, number, number + 1, JSON.stringify({ type: "text", adb: { reason: "updated" } }));
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    installLegacyEdits(db); addClientColumn(db); installWidgetSources(db);
    installCardOutbox(db);
    saveWithCardOutcome(db, { thread, ts: "card", agent: "a", field: "adb", close: true, outcome: { status: "granted" } }, () => {});
    const item = cardOutcomeHeads(db, "0")[0]!;
    let unpreparedMerged = 0, prepared = false;
    (store as any).db = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (!prepared && sql === "SELECT * FROM merged WHERE thread = ? AND ts = ?") {
          unpreparedMerged++;
          throw new Error("unprepared merged lookup on the station");
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const first = (store as any).restateQueuedCard(item);
    assert.equal(unpreparedMerged, 0);
    if (shape === "long") {
      assert.equal(first, undefined, "the result stays queued while old edits are prepared");
      assert.equal(cardOutcomeHeads(db, "0").length, 1);
      assert.equal(db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(thread)?.n, 0);
      while (!legacyMergedReadReady(db)) legacyEditsMaintenanceStep(db);
      prepared = true;
      assert.equal((store as any).restateQueuedCard(item), true);
    } else assert.equal(first, true, "short chats and recent card edits need no old scan");
    const last = db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)!;
    assert.equal(last.text, shape === "recent" ? "changed question" : "question");
    assert.deepEqual(JSON.parse(String(last.card)).adb, { reason: shape === "recent" ? "updated" : "original", outcome: { status: "granted" } });
    assert.deepEqual(cardOutcomeHeads(db, "0"), []);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=? AND n=?").get(thread, number)?.n, 1);
  } finally { (store as any).db = db; store.close(); }
});

for (const legacy of [false, true]) test(`a queued result keeps a card edited before its post (legacy ${legacy})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "old", null, null).id;
    db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card)
      VALUES(?,1,'edit',2,'agent','a','earlier edit',1,?)`)
      .run(thread, JSON.stringify({ type: "text", adb: { reason: "earlier" } }));
    db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,2,'message','card','agent','a','question',2,?)`)
      .run(thread, JSON.stringify({ type: "text", adb: { reason: "original" } }));
    if (legacy) { db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target"); installLegacyEdits(db); addClientColumn(db); installWidgetSources(db); }
    installCardOutbox(db);
    saveWithCardOutcome(db, { thread, ts: "card", agent: "a", field: "adb", close: false, outcome: { status: "granted" } }, () => {});
    assert.equal(store.restateQueuedCard(cardOutcomeHeads(db, "0")[0]!), true);
    const last = db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)!;
    assert.equal(last.text, "earlier edit");
    assert.deepEqual(JSON.parse(String(last.card)).adb, { reason: "earlier", outcome: { status: "granted" } });
  } finally { store.close(); }
});

for (const legacy of [false, true]) test(`a queued result waits when neither limited card probe can decide (legacy ${legacy})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "old", null, null).id;
    db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','a','question',1,?)`)
      .run(thread, JSON.stringify({ type: "text", adb: { reason: "original" } }));
    const edit = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card)
      VALUES(?,?,'edit',?,'agent','a',?,?,?)`);
    edit.run(thread, 2, 1, "card edit", 2, JSON.stringify({ type: "text", adb: { reason: "latest card" } }));
    for (let n = 3; n <= 82; n++) edit.run(thread, n, 1, `text ${n}`, n, null);
    for (let n = 83; n <= 162; n++) edit.run(thread, n, n + 1000, "other", n, JSON.stringify({ type: "text" }));
    if (legacy) {
      db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
      installLegacyEdits(db); addClientColumn(db); installWidgetSources(db);
      while (!legacyMergedReadReady(db)) legacyEditsMaintenanceStep(db);
    }
    installCardOutbox(db);
    saveWithCardOutcome(db, { thread, ts: "card", agent: "a", field: "adb", close: true, outcome: { status: "granted" } }, () => {});
    const item = cardOutcomeHeads(db, "0")[0]!;
    assert.equal(store.restateQueuedCard(item), undefined);
    assert.deepEqual(cardOutcomeHeads(db, "0"), [item]);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(thread)?.n, 0);
    db.prepare("DELETE FROM entries WHERE thread=? AND n>=83").run(thread);
    assert.equal(store.restateQueuedCard(item), true);
    const last = db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)!;
    assert.equal(last.text, "text 82");
    assert.deepEqual(JSON.parse(String(last.card)).adb, { reason: "latest card", outcome: { status: "granted" } });
    assert.deepEqual(cardOutcomeHeads(db, "0"), []);
  } finally { store.close(); }
});

test("a queued result stays pending when its snapshot becomes inconclusive before the write", () => {
  const dir = mkdtempSync(join(tmpdir(), "card-outbox-read-")), path = join(dir, "station.sqlite");
  const store = Store.open(path), db = store.db, other = new DatabaseSync(path, { timeout: 5000 });
  try {
    const thread = store.openThread("ember", "CHAT", "old", null, null).id;
    const message = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,?,'message',?,'person','p','other',?)");
    for (let n = 1; n <= 100; n++) message.run(thread, n, `other-${n}`, n);
    db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,101,'message','card','agent','a','question',101,?)`)
      .run(thread, JSON.stringify({ type: "text", adb: { reason: "original" } }));
    db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card)
      VALUES(?,102,'edit',101,'agent','a','changed',102,?)`)
      .run(thread, JSON.stringify({ type: "text", adb: { reason: "updated" } }));
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    installLegacyEdits(db); addClientColumn(db); installWidgetSources(db); installCardOutbox(db);
    saveWithCardOutcome(db, { thread, ts: "card", agent: "a", field: "adb", close: true, outcome: { status: "granted" } }, () => {});
    const item = cardOutcomeHeads(db, "0")[0]!;
    let changed = false;
    (store as any).db = new Proxy(db, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        target.exec(sql);
        if (sql === "RELEASE restate_card_read" && !changed) {
          changed = true;
          const insert = other.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'person','p','other edit',?)");
          for (let n = 103; n < 173; n++) insert.run(thread, n, n - 102, n);
        }
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.equal(store.restateQueuedCard(item), undefined);
    assert.equal(changed, true);
    assert.deepEqual(cardOutcomeHeads(db, "0"), [item]);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(thread)?.n, 0);
    while (!legacyMergedReadReady(db)) legacyEditsMaintenanceStep(db);
    assert.equal(store.restateQueuedCard(item), true);
    const last = db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)!;
    assert.equal(last.text, "changed");
    assert.deepEqual(JSON.parse(String(last.card)).adb, { reason: "updated", outcome: { status: "granted" } });
  } finally { (store as any).db = db; other.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
