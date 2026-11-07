import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import * as readStore from "../src/read/store.ts";
import { threadHistory } from "../src/sessions/conversations.ts";
import type { Hub } from "../src/sessions/hub.ts";
import { CARD_POST_LATEST } from "../src/store/card-post-index.ts";
import { installLegacyEdits } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

const card = JSON.stringify({ type: "options", options: [{ label: "Pick" }] });

test("history's card status comes from a reader, and a cardless page needs no status", async () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "1.1", null, null);
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,card,at)
      VALUES(?,?,'message',?,'agent','worker',?,?,?)`);
    put.run(thread.id, 1, "1.1", "older", card, 1);
    put.run(thread.id, 2, "2.1", "current", card, 2);
    put.run(thread.id, 3, "3.1", "without card", null, 3);
    const base = { store, chatOf: () => null } as unknown as Hub;
    const expected = await threadHistory(base, "worker", thread, "internal", "CHAT/1.1", { limit: 3 });
    assert.match(expected, /older[\s\S]*Answer card: no longer pending/);
    assert.match(expected, /current[\s\S]*Answer card: pending/);
    const hub = { store, chatOf: () => null, historyPendingCard: async (id: number) => {
      assert.equal(id, thread.id); return 2;
    } } as unknown as Hub;
    store.pendingCard = () => { throw new Error("station card lookup used"); };
    assert.equal(await threadHistory(hub, "worker", thread, "internal", "CHAT/1.1", { limit: 3 }), expected);
    hub.historyPendingCard = async () => { throw new Error("cardless page looked up status"); };
    assert.match(await threadHistory(hub, "worker", thread, "internal", "CHAT/1.1", { limit: 1 }), /without card/);
  } finally { store.close(); }
});

test("the pending card number preserves options, malformed cards, closing and answers", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "1.1", null, null).id;
    const read = readStore.makeStore(db, "");
    const pending = readStore.pendingCardNumber;
    const same = () => assert.equal(pending(read, thread), store.pendingCard(thread)?.[0].n ?? null);
    same();
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,card,options,at)
      VALUES(?,?,'message',?,'agent','worker',?,?,?,?)`);
    put.run(thread, 1, "1.1", "old options", "{", JSON.stringify([{ label: "Old" }]), 1);
    same();
    put.run(thread, 2, "2.1", "new card", card, null, 2);
    same();
    db.prepare("INSERT INTO closed_cards(thread,n,viewer,at) VALUES(?,2,'person',3)").run(thread);
    same();
    db.prepare("DELETE FROM closed_cards WHERE thread=? AND n=2").run(thread);
    db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,3,'message','3.1','person','p','yes',3)").run(thread);
    same();
    const bad = store.openThread("ember", "CHAT", "2.1", null, null).id;
    put.run(bad, 1, "bad.1", "invalid", "{", null, 1);
    assert.equal(pending(read, bad), store.pendingCard(bad)?.[0].n ?? null);
  } finally { store.close(); }
});

test("the pending number and its answer use one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "history-card-snapshot-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db, writer = new DatabaseSync(path);
  try {
    const thread = store.openThread("ember", "CHAT", "1.1", null, null).id;
    db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,card,at) VALUES(?,1,'message','1.1','agent','worker','ask',?,1)").run(thread, card);
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === CARD_POST_LATEST && !changed) {
          changed = true;
          writer.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,2,'message','2.1','person','p','yes',2)").run(thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = readStore.makeStore(observed, dir), pending = readStore.pendingCardNumber;
    assert.equal(pending(read, thread), 1);
    assert.ok(changed);
    assert.equal(pending(read, thread), null);
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a pending number does not read an unprepared old message's edits", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "old-edits", null, null).id;
    db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,card,at) VALUES(?,1,'message','1.1','agent','worker','ask',?,1)").run(thread, card);
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',1,'agent','worker','edit',2)");
    for (let n = 2; n <= 151; n++) edit.run(thread, n);
    edit.run(thread, 9007199254740993n);
    installLegacyEdits(db);
    addClientColumn(db);
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        assert.doesNotMatch(sql, /\bmerged\b/i, "the pending number does not need merged message data");
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.equal(readStore.pendingCardNumber(readStore.makeStore(observed, ""), thread), 1);
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
  } finally { store.close(); }
});

test("history readers share old card preparation after handover when one cancels", async () => {
  const dir = mkdtempSync(join(tmpdir(), "history-card-reader-"));
  const store = Store.open(join(dir, "stillfail.db")), db = store.db;
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const thread = store.openThread("ember", "CHAT", "1.1", null, null);
    const short = store.openThread("ember", "CHAT", "2.1", null, null);
    db.prepare("DELETE FROM card_post_scopes WHERE thread=?").run(thread.id);
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,ts,author_kind,author,text,card,at)
      VALUES(?,?,?,?,?,'agent','worker','ask',?,?)`);
    db.exec("BEGIN");
    put.run(thread.id, 1, "message", null, "1.1", card, 1);
    for (let n = 2; n <= 151; n++) put.run(thread.id, n, "edit", 1, null, card, n);
    db.exec("COMMIT");
    const controller = new AbortController();
    const abandoned = readers.read("historyPendingCard", { thread: thread.id }, "en", { signal: controller.signal });
    const kept = readers.read("historyPendingCard", { thread: thread.id }, "en");
    void abandoned.catch(() => {}); void kept.catch(() => {});
    assert.equal(JSON.parse(await readers.read("historyPendingCard", { thread: short.id }, "en")), null);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    assert.equal(JSON.parse(await kept), 1);
    const hub = { store, chatOf: () => null,
      historyPendingCard: async (id: number) => JSON.parse(await readers.read("historyPendingCard", { thread: id }, "en")) } as unknown as Hub;
    store.pendingCard = () => { throw new Error("station card lookup used"); };
    assert.match(await threadHistory(hub, "worker", thread, "internal", "CHAT/1.1", { limit: 1 }), /Answer card: pending/);
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
