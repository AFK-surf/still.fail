import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { cardEditPage, cardMessagePage, cardOutcomeHeads, completeCardOutcome, enqueueCardOutcome, hasCardOutbox, installCardOutbox, saveWithCardOutcome } from "../src/store/card-outbox.ts";

function transaction<T>(db: DatabaseSync, body: () => T): T {
  db.exec("BEGIN IMMEDIATE");
  try { const result = body(); db.exec("COMMIT"); return result; }
  catch (error) { db.exec("ROLLBACK"); throw error; }
}

test("a saved request and its card outcome commit or roll back together", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec("CREATE TABLE requests(id TEXT PRIMARY KEY,status TEXT); INSERT INTO requests VALUES('r','pending')");
    installCardOutbox(db);
    const item = { thread: 1, ts: "card", agent: "a", field: "adb" as const, close: true, outcome: { status: "granted" } };
    assert.throws(() => enqueueCardOutcome(db, item), /transaction/);
    assert.throws(() => transaction(db, () => {
      db.exec("UPDATE requests SET status='granted' WHERE id='r'");
      enqueueCardOutcome(db, item);
      throw new Error("save failed");
    }), /save failed/);
    assert.equal(db.prepare("SELECT status FROM requests WHERE id='r'").get()?.status, "pending");
    assert.deepEqual(cardOutcomeHeads(db, "0"), []);
    transaction(db, () => {
      db.exec("UPDATE requests SET status='granted' WHERE id='r'");
      enqueueCardOutcome(db, item);
    });
    assert.equal(db.prepare("SELECT status FROM requests WHERE id='r'").get()?.status, "granted");
    assert.deepEqual(cardOutcomeHeads(db, "0").map(({ id: _id, ...rest }) => rest), [item]);
  } finally { db.close(); }
});

test("a request and its queued result roll back together if queuing fails", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec("CREATE TABLE requests(id TEXT PRIMARY KEY,status TEXT); INSERT INTO requests VALUES('r','pending')");
    installCardOutbox(db);
    const cyclic: Record<string, unknown> = {};
    cyclic.self = cyclic;
    const item = { thread: 1, ts: "card", agent: "a", field: "adb" as const, close: true, outcome: cyclic };
    assert.throws(() => saveWithCardOutcome(db, item, () => db.exec("UPDATE requests SET status='granted' WHERE id='r'")), /circular/i);
    assert.equal(db.prepare("SELECT status FROM requests WHERE id='r'").get()?.status, "pending");
    assert.deepEqual(cardOutcomeHeads(db, "0"), []);
    const id = saveWithCardOutcome(db, { ...item, outcome: { status: "granted" } },
      () => db.exec("UPDATE requests SET status='granted' WHERE id='r'"));
    assert.equal(db.prepare("SELECT status FROM requests WHERE id='r'").get()?.status, "granted");
    assert.deepEqual(cardOutcomeHeads(db, "0").map((x) => x.id), [id]);
  } finally { db.close(); }
});

test("a rolled-back outbox installation is not mistaken for a later schema with the same version", () => {
  const db = new DatabaseSync(":memory:");
  try {
    const item = { thread: 1, ts: "card", agent: "a", field: "adb" as const, close: true, outcome: { status: "granted" } };
    let during = 0;
    assert.throws(() => saveWithCardOutcome(db, item, () => {
      during = Number(db.prepare("PRAGMA schema_version").get()!.schema_version);
      throw new Error("request save failed");
    }), /request save failed/);
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name='card_outbox_meta'").get(), undefined);
    for (let n = Number(db.prepare("PRAGMA schema_version").get()!.schema_version); n < during; n++)
      db.exec(`CREATE TABLE unrelated_${n}(id INTEGER)`);
    assert.equal(Number(db.prepare("PRAGMA schema_version").get()!.schema_version), during);
    assert.equal(hasCardOutbox(db), false);
    const id = saveWithCardOutcome(db, item, () => {});
    assert.deepEqual(cardOutcomeHeads(db, "0").map((head) => head.id), [id]);
  } finally { db.close(); }
});

test("missing outbox tables are not silently recreated", () => {
  const db = new DatabaseSync(":memory:");
  try {
    installCardOutbox(db);
    db.exec("DROP TABLE card_outbox_head");
    assert.throws(() => installCardOutbox(db), /tables are missing/);
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name='card_outbox_head'").get(), undefined);
  } finally { db.close(); }
});

test("each card's outcomes remain ordered without blocking another card", () => {
  const db = new DatabaseSync(":memory:");
  try {
    installCardOutbox(db);
    const item = (thread: number, status: string) => ({ thread, ts: "card", agent: "a", field: "adb" as const, close: true, outcome: { status } });
    const [first, other, next] = transaction(db, () => [
      enqueueCardOutcome(db, item(1, "granted")), enqueueCardOutcome(db, item(2, "granted")), enqueueCardOutcome(db, item(1, "ended")),
    ]);
    assert.deepEqual(cardOutcomeHeads(db, "0").map((x) => x.id), [first, other]);
    const [head, otherHead] = cardOutcomeHeads(db, "0");
    assert.equal(transaction(db, () => completeCardOutcome(db, otherHead!)), true);
    assert.deepEqual(cardOutcomeHeads(db, "0").map((x) => x.id), [first]);
    assert.equal(transaction(db, () => completeCardOutcome(db, head!)), true);
    assert.deepEqual(cardOutcomeHeads(db, "0").map((x) => x.id), [next]);
    assert.equal(transaction(db, () => completeCardOutcome(db, head!)), false, "an old consumer cannot remove the next outcome");
    const final = cardOutcomeHeads(db, "0")[0]!;
    assert.deepEqual(final.outcome, { status: "ended" });
    assert.throws(() => transaction(db, () => { completeCardOutcome(db, final); throw new Error("edit failed"); }), /edit failed/);
    assert.deepEqual(cardOutcomeHeads(db, "0").map((x) => x.id), [next]);
    assert.equal(transaction(db, () => completeCardOutcome(db, final)), true);
    assert.deepEqual(cardOutcomeHeads(db, "0"), []);
    const later = transaction(db, () => enqueueCardOutcome(db, item(1, "pending")));
    assert.ok(BigInt(later) > BigInt(next!), "a cursor remains valid after the queue becomes empty");
    assert.deepEqual(cardOutcomeHeads(db, next!).map((x) => x.id), [later]);
  } finally { db.close(); }
});

test("pending card outcomes survive closing and reopening the database", () => {
  const dir = mkdtempSync(join(tmpdir(), "card-outbox-")), path = join(dir, "store.sqlite");
  let db = new DatabaseSync(path);
  try {
    installCardOutbox(db);
    const id = transaction(db, () => enqueueCardOutcome(db, { thread: 3, ts: "card", agent: "a", field: "vault", close: true, outcome: { status: "denied" } }));
    db.close();
    db = new DatabaseSync(path);
    installCardOutbox(db);
    assert.deepEqual(cardOutcomeHeads(db, "0"), [{ id, thread: 3, ts: "card", agent: "a", field: "vault", close: true, outcome: { status: "denied" } }]);
  } finally { db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("card outcome sequence numbers keep their full precision", () => {
  const db = new DatabaseSync(":memory:");
  try {
    installCardOutbox(db);
    transaction(db, () => enqueueCardOutcome(db, { thread: 1, ts: "a", agent: "a", field: "signin", close: false, outcome: {} }));
    db.exec("UPDATE card_outbox_meta SET next_id=9007199254740992 WHERE id=1");
    const id = transaction(db, () => enqueueCardOutcome(db, { thread: 2, ts: "b", agent: "a", field: "signin", close: false, outcome: {} }));
    assert.equal(id, "9007199254740993");
    assert.deepEqual(cardOutcomeHeads(db, "9007199254740992").map((x) => x.id), [id]);
  } finally { db.close(); }
});

test("a backlog for one card does not hide another card's head", () => {
  const db = new DatabaseSync(":memory:");
  try {
    installCardOutbox(db);
    transaction(db, () => {
      for (let n = 0; n < 200; n++)
        enqueueCardOutcome(db, { thread: 1, ts: "slow", agent: "a", field: "adb", close: true, outcome: { n } });
      enqueueCardOutcome(db, { thread: 2, ts: "ready", agent: "b", field: "vault", close: true, outcome: { status: "denied" } });
    });
    const heads = cardOutcomeHeads(db, "0", 2);
    assert.deepEqual(heads.map(({ ts }) => ts), ["slow", "ready"]);
    assert.deepEqual(heads.map(({ outcome }) => outcome), [{ n: 0 }, { status: "denied" }]);
    assert.deepEqual(cardOutcomeHeads(db, heads[0]!.id, 2).map(({ ts }) => ts), ["ready"]);
    assert.throws(() => cardOutcomeHeads(db, "0", 65), /1 to 64/);
  } finally { db.close(); }
});

test("a second connection cannot finish the outcome after another has advanced the card", () => {
  const dir = mkdtempSync(join(tmpdir(), "card-outbox-two-")), path = join(dir, "store.sqlite");
  const first = new DatabaseSync(path), second = new DatabaseSync(path);
  try {
    first.exec("PRAGMA journal_mode=WAL");
    installCardOutbox(first);
    transaction(first, () => {
      for (const status of ["granted", "ended"])
        enqueueCardOutcome(first, { thread: 1, ts: "card", agent: "a", field: "adb", close: true, outcome: { status } });
    });
    const fromFirst = cardOutcomeHeads(first, "0")[0]!, fromSecond = cardOutcomeHeads(second, "0")[0]!;
    assert.equal(transaction(first, () => completeCardOutcome(first, fromFirst)), true);
    assert.equal(transaction(second, () => completeCardOutcome(second, fromSecond)), false);
    assert.deepEqual(cardOutcomeHeads(second, "0").map((x) => x.outcome), [{ status: "ended" }]);
  } finally { second.close(); first.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an incompatible outbox version is not replaced", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec("CREATE TABLE card_outbox_meta(id INTEGER PRIMARY KEY,version INTEGER NOT NULL,next_id INTEGER NOT NULL); INSERT INTO card_outbox_meta VALUES(1,9,5)");
    assert.throws(() => installCardOutbox(db), /unsupported version/);
    assert.deepEqual({ ...db.prepare("SELECT version,next_id FROM card_outbox_meta WHERE id=1").get() }, { version: 9, next_id: 5 });
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='card_outbox'").get(), undefined);
  } finally { db.close(); }
});

test("a version changed without schema DDL is not read through the installed cache", () => {
  const db = new DatabaseSync(":memory:");
  try {
    installCardOutbox(db);
    db.exec("UPDATE card_outbox_meta SET version=9 WHERE id=1");
    assert.throws(() => hasCardOutbox(db), /unsupported version/);
    assert.throws(() => installCardOutbox(db), /unsupported version/);
  } finally { db.close(); }
});

for (const indexed of [true, false]) test(`card edit pages keep numeric order and find the newest matching edit (index ${indexed})`, () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`CREATE TABLE entries(thread INTEGER NOT NULL,n INTEGER NOT NULL,kind TEXT NOT NULL,target INTEGER,card TEXT,
      PRIMARY KEY(thread,n)) WITHOUT ROWID`);
    if (indexed) db.exec("CREATE INDEX entries_cards ON entries(thread,n) WHERE card IS NOT NULL");
    const add = db.prepare("INSERT INTO entries(thread,n,kind,target,card) VALUES(1,CAST(? AS INTEGER),?,?,?)");
    const base = 9007199254741000n;
    add.run(String(base - 1n), "edit", 1, '{"version":"wanted"}');
    for (let i = 0n; i < 130n; i++) add.run(String(base + i), i % 2n === 0n ? "edit" : "message", 999, '{"other":true}');
    db.exec("BEGIN");
    let result = cardEditPage(db, 1, "1", null);
    assert.deepEqual(result, { kind: "next", before: String(base + 66n) });
    assert.equal(result.kind, "next");
    result = cardEditPage(db, 1, "1", result.before);
    assert.deepEqual(result, { kind: "next", before: String(base + 2n) });
    assert.equal(result.kind, "next");
    assert.deepEqual(cardEditPage(db, 1, "1", result.before), { kind: "found", card: '{"version":"wanted"}' });
    result = cardEditPage(db, 1, "8", null);
    assert.equal(result.kind, "next");
    result = cardEditPage(db, 1, "8", result.before);
    assert.equal(result.kind, "next");
    assert.deepEqual(cardEditPage(db, 1, "8", result.before), { kind: "end" });
    db.exec("COMMIT");
  } finally { db.close(); }
});

test("old message pages find an early target entry with a 64-bit cursor", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec("CREATE TABLE entries(thread INTEGER NOT NULL,n INTEGER NOT NULL,target INTEGER,PRIMARY KEY(thread,n)) WITHOUT ROWID");
    const insert = db.prepare("INSERT INTO entries(thread,n,target) VALUES(1,CAST(? AS INTEGER),?)"), base = 9007199254741000n;
    insert.run(String(base), 7);
    for (let n = 1n; n <= 1100n; n++) insert.run(String(base + n), 8);
    let page = cardMessagePage(db, 1, "7", null), pages = 1;
    while (page.kind === "next") { page = cardMessagePage(db, 1, "7", page.before); pages++; }
    assert.equal(pages, 3);
    assert.deepEqual(page, { kind: "found", n: String(base) });
    page = cardMessagePage(db, 1, "9", null);
    while (page.kind === "next") page = cardMessagePage(db, 1, "9", page.before);
    assert.deepEqual(page, { kind: "end" });
  } finally { db.close(); }
});

test("a queue made before a rig's card had an outcome takes one, the outcomes waiting in it kept", () => {
  const db = new DatabaseSync(":memory:");
  try {
    // The queue as it was made before (2026-11-10): three fields named in its CHECK.
    db.exec(`CREATE TABLE card_outbox_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL,next_id INTEGER NOT NULL) WITHOUT ROWID;
      INSERT INTO card_outbox_meta VALUES(1,1,0);
      CREATE TABLE card_outbox(thread INTEGER NOT NULL,ts TEXT NOT NULL,id INTEGER NOT NULL,
        agent TEXT NOT NULL,field TEXT NOT NULL CHECK(field IN ('adb','signin','vault')),
        close_card INTEGER NOT NULL CHECK(close_card IN (0,1)),outcome TEXT NOT NULL,
        PRIMARY KEY(thread,ts,id)) WITHOUT ROWID;
      CREATE TABLE card_outbox_head(id INTEGER PRIMARY KEY,thread INTEGER NOT NULL,ts TEXT NOT NULL);`);
    const phone = { thread: 1, ts: "phone", agent: "a", field: "adb" as const, close: true, outcome: { status: "granted" } };
    const rig = { thread: 2, ts: "rig", agent: "a", field: "rig" as const, close: true, outcome: { status: "granted", delivered: true } };
    saveWithCardOutcome(db, phone, () => {});
    assert.throws(() => transaction(db, () => enqueueCardOutcome(db, rig)), /CHECK constraint failed/);
    let saved = 0;
    saveWithCardOutcome(db, rig, () => void saved++);
    assert.equal(saved, 1);
    assert.deepEqual(cardOutcomeHeads(db, "0").map(({ id: _id, ...rest }) => rest), [phone, rig]);
    assert.equal(hasCardOutbox(db), true);
    // Made again once: the next finds it wide enough.
    const made = db.prepare("SELECT sql FROM sqlite_master WHERE name='card_outbox'").get()?.sql;
    saveWithCardOutcome(db, { ...rig, ts: "rig2" }, () => {});
    assert.equal(db.prepare("SELECT sql FROM sqlite_master WHERE name='card_outbox'").get()?.sql, made);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE name='card_outbox_wider'").get()?.n, 0);
  } finally { db.close(); }
});
