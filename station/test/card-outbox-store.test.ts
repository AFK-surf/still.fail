import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { cardOutcomeHeads, installCardOutbox, saveWithCardOutcome } from "../src/store/card-outbox.ts";
import { Store } from "../src/store/store.ts";

test("a card outcome cannot announce a close before an outer transaction commits", () => {
  const store = Store.open(":memory:");
  try {
    const db = store.db, thread = store.openThread("ember", "CHAT", "card", null, null).id;
    db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','a','question',1,?)`).run(thread, JSON.stringify({ type: "text", adb: {} }));
    let closes = 0, saved = false;
    store.subscribe((change) => { if (change.type === "thread" && change.closed !== undefined) closes++; });
    db.exec("BEGIN");
    try {
      assert.throws(() => store.saveCardOutcome({ thread, ts: "card", agent: "a", field: "adb", close: true, outcome: {} },
        () => { saved = true; }), /outside.*transaction/);
      assert.equal(saved, false);
    } finally { db.exec("ROLLBACK"); }
    assert.equal(closes, 0);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(thread)?.n, 0);
  } finally { store.close(); }
});

test("a request save takes the writer before checking its outbox schema", () => {
  const dir = mkdtempSync(join(tmpdir(), "card-outbox-writer-")), path = join(dir, "station.sqlite");
  const store = Store.open(path), raw = store.db, other = new DatabaseSync(path, { timeout: 0 });
  try {
    const thread = store.openThread("ember", "CHAT", "card", null, null).id;
    raw.exec("CREATE TABLE card_test_request(id INTEGER PRIMARY KEY,status TEXT); INSERT INTO card_test_request VALUES(1,'pending')");
    raw.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','a','question',1,?)`).run(thread, JSON.stringify({ type: "text", adb: {} }));
    installCardOutbox(raw);
    let attempted = false, blocked = false;
    (store as any).db = new Proxy(raw, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (sql !== "SELECT version FROM card_outbox_meta WHERE id=1") return statement;
        return new Proxy(statement, { get(stmt, key) {
          if (key === "get") return (...args: any[]) => {
            const value = stmt.get(...args);
            if (!attempted) {
              attempted = true;
              try { other.exec("UPDATE card_test_request SET status='other' WHERE id=1"); }
              catch (error) {
                const code = (error as { errcode?: number }).errcode;
                if (code === undefined || ![5, 6].includes(code & 255)) throw error;
                blocked = true;
              }
            }
            return value;
          };
          const value = Reflect.get(stmt, key, stmt);
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    store.saveCardOutcome({ thread, ts: "card", agent: "a", field: "adb", close: true, outcome: { status: "granted" } },
      () => raw.exec("UPDATE card_test_request SET status='granted' WHERE id=1"));
    assert.equal(attempted, true);
    assert.equal(blocked, true, "the competing writer is serialized after the request and queue commit");
    assert.equal(raw.prepare("SELECT status FROM card_test_request WHERE id=1").get()?.status, "granted");
    assert.equal(cardOutcomeHeads(raw, "0").length, 1);
    other.exec("UPDATE card_test_request SET status='other' WHERE id=1");
  } finally {
    (store as any).db = raw;
    other.close(); store.close(); rmSync(dir, { recursive: true, force: true });
  }
});

for (const close of [false, true]) test(`a queued outcome writes its card and removes itself (close ${close})`, () => {
  const store = Store.open(":memory:");
  try {
    const thread = store.openThread("ember", "CHAT", "card", null, null).id;
    store.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','a','question',1,?)`)
      .run(thread, JSON.stringify({ type: "text", adb: { reason: "debug" } }));
    installCardOutbox(store.db);
    const id = saveWithCardOutcome(store.db, { thread, ts: "card", agent: "a", field: "adb", close, outcome: { status: "granted" } }, () => {});
    const item = cardOutcomeHeads(store.db, "0")[0]!;
    const events: string[] = [];
    store.subscribe((change) => {
      if (change.type !== "thread" || change.id !== thread) return;
      if (change.closed !== undefined) events.push("closed");
      if (change.entries.some((entry) => entry.kind === "edit")) events.push("edit");
    });
    assert.equal(item.id, id);
    assert.equal((store as any).restateQueuedCard(item), true);
    const latest = store.db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)!;
    assert.equal(latest.text, "question");
    assert.deepEqual(JSON.parse(String(latest.card)), { type: "text", adb: { reason: "debug", outcome: { status: "granted" } } });
    assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=? AND n=1").get(thread)?.n, close ? 1 : 0);
    assert.deepEqual(cardOutcomeHeads(store.db, "0"), []);
    assert.deepEqual(events, close ? ["closed", "edit"] : ["edit"]);
  } finally { store.close(); }
});

test("a post that appears before discarding its queued outcome receives it", () => {
  const dir = mkdtempSync(join(tmpdir(), "card-outbox-appear-")), path = join(dir, "station.sqlite");
  const store = Store.open(path), raw = store.db, other = new DatabaseSync(path, { timeout: 5000 });
  try {
    const thread = store.openThread("ember", "CHAT", "card", null, null).id;
    installCardOutbox(raw);
    saveWithCardOutcome(raw, { thread, ts: "card", agent: "a", field: "signin", close: false, outcome: { status: "done" } }, () => {});
    const item = cardOutcomeHeads(raw, "0")[0]!;
    let inserted = false;
    (store as any).db = new Proxy(raw, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        if (sql === "BEGIN IMMEDIATE" && !inserted) {
          inserted = true;
          other.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
            VALUES(?,1,'message','card','agent','a','question',1,?)`).run(thread, JSON.stringify({ type: "text", signin: {} }));
        }
        target.exec(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.equal((store as any).restateQueuedCard(item), true);
    assert.equal(inserted, true);
    const last = raw.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)!;
    assert.deepEqual(JSON.parse(String(last.card)).signin.outcome, { status: "done" });
    assert.deepEqual(cardOutcomeHeads(raw, "0"), []);
  } finally {
    (store as any).db = raw;
    other.close(); store.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("two connections consuming one outcome only write it once", () => {
  const dir = mkdtempSync(join(tmpdir(), "card-outbox-consume-")), path = join(dir, "station.sqlite");
  const store = Store.open(path), raw = store.db, other = Store.open(path);
  try {
    const thread = store.openThread("ember", "CHAT", "card", null, null).id;
    raw.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','a','question',1,?)`).run(thread, JSON.stringify({ type: "text", adb: {} }));
    installCardOutbox(raw);
    saveWithCardOutcome(raw, { thread, ts: "card", agent: "a", field: "adb", close: true, outcome: { status: "granted" } }, () => {});
    const item = cardOutcomeHeads(raw, "0")[0]!;
    let consumed = false;
    (store as any).db = new Proxy(raw, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        target.exec(sql);
        if (sql === "RELEASE restate_card_read" && !consumed) {
          consumed = true;
          assert.equal((other as any).restateQueuedCard(item), true);
        }
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.equal((store as any).restateQueuedCard(item), false);
    assert.equal(consumed, true);
    assert.equal(raw.prepare("SELECT COUNT(*) AS n FROM entries WHERE thread=?").get(thread)?.n, 2);
    assert.equal(raw.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(thread)?.n, 1);
    assert.deepEqual(cardOutcomeHeads(raw, "0"), []);
  } finally {
    (store as any).db = raw;
    other.close(); store.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("a failed card edit rolls back the close and keeps its queued result", () => {
  const store = Store.open(":memory:");
  try {
    const thread = store.openThread("ember", "CHAT", "card", null, null).id;
    store.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','a','question',1,?)`).run(thread, JSON.stringify({ type: "text", adb: {} }));
    installCardOutbox(store.db);
    saveWithCardOutcome(store.db, { thread, ts: "card", agent: "a", field: "adb", close: true, outcome: { status: "granted" } }, () => {});
    const item = cardOutcomeHeads(store.db, "0")[0]!;
    store.db.exec("CREATE TRIGGER fail_card_outbox BEFORE INSERT ON entries WHEN NEW.kind='edit' BEGIN SELECT RAISE(ABORT,'cannot write edit'); END");
    assert.throws(() => (store as any).restateQueuedCard(item), /cannot write edit/);
    assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM entries WHERE thread=?").get(thread)?.n, 1);
    assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(thread)?.n, 0);
    assert.deepEqual(cardOutcomeHeads(store.db, "0"), [item]);
    store.db.exec("DROP TRIGGER fail_card_outbox");
    assert.equal((store as any).restateQueuedCard(item), true);
    assert.deepEqual(cardOutcomeHeads(store.db, "0"), []);
  } finally { store.close(); }
});

test("an already consumed outcome cannot overwrite its successor", () => {
  const store = Store.open(":memory:");
  try {
    const thread = store.openThread("ember", "CHAT", "card", null, null).id;
    store.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,1,'message','card','agent','a','question',1,?)`).run(thread, JSON.stringify({ type: "text", adb: {} }));
    installCardOutbox(store.db);
    const add = (status: string) => saveWithCardOutcome(store.db, { thread, ts: "card", agent: "a", field: "adb", close: false, outcome: { status } }, () => {});
    add("granted"); add("ended");
    const first = cardOutcomeHeads(store.db, "0")[0]!;
    assert.equal((store as any).restateQueuedCard(first), true);
    assert.equal((store as any).restateQueuedCard(first), false);
    const next = cardOutcomeHeads(store.db, "0")[0]!;
    assert.equal((store as any).restateQueuedCard(next), true);
    assert.equal((store as any).restateQueuedCard(first), false);
    const latest = store.db.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)!;
    assert.deepEqual(JSON.parse(String(latest.card)).adb.outcome, { status: "ended" });
    assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM entries WHERE thread=?").get(thread)?.n, 3);
  } finally { store.close(); }
});

test("an outcome for a deleted post is discarded without creating an edit", () => {
  const store = Store.open(":memory:");
  try {
    const thread = store.openThread("ember", "CHAT", "card", null, null).id;
    installCardOutbox(store.db);
    saveWithCardOutcome(store.db, { thread, ts: "gone", agent: "a", field: "signin", close: false, outcome: { status: "done" } }, () => {});
    const item = cardOutcomeHeads(store.db, "0")[0]!;
    assert.equal((store as any).restateQueuedCard(item), true);
    assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM entries WHERE thread=?").get(thread)?.n, 0);
    assert.deepEqual(cardOutcomeHeads(store.db, "0"), []);
  } finally { store.close(); }
});
