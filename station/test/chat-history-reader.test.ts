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
import { Store } from "../src/store/store.ts";

test("chat history reads its requested page without holding the station's store", async () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "1.1", null, null);
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at)
      VALUES(?,?,'message',?,'agent','worker',?,?)`);
    for (let n = 1; n <= 3; n++) put.run(thread.id, n, `${n}.1`, `message-${n}`, n);
    const base = { store, chatOf: () => null } as unknown as Hub;
    const expected = await threadHistory(base, "worker", thread, "internal", "CHAT/1.1", { before: "3.1", limit: 2 });
    const page = store.messagesBefore(thread.id, 3, 2);
    const hub = { store, chatOf: () => null,
      historyMessages: async (id: number, before: string | null, limit: number) => {
        assert.equal(id, thread.id);
        assert.equal(limit, 2);
        return before === "3.1" ? page : null;
      } } as unknown as Hub;
    store.messageAt = () => { throw new Error("station message lookup used"); };
    store.messagesBefore = () => { throw new Error("station page lookup used"); };
    assert.equal(await threadHistory(hub, "worker", thread, "internal", "CHAT/1.1", { before: "3.1", limit: 2 }), expected);
    await assert.rejects(threadHistory(hub, "worker", thread, "internal", "CHAT/1.1", { before: "unknown", limit: 2 }),
      /no message unknown in CHAT\/1\.1/);
  } finally { store.close(); }
});

test("the history boundary and its page share one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "history-reader-snapshot-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db, writer = new DatabaseSync(path);
  try {
    const thread = store.openThread("ember", "CHAT", "1.1", null, null).id;
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at)
      VALUES(?,?,'message',?,'agent','worker',?,?)`);
    for (let n = 1; n <= 3; n++) put.run(thread, n, `${n}.1`, `message-${n}`, n);
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === readStore.PAGE_ORDINARY_KEYS && !changed) {
          changed = true;
          writer.prepare("UPDATE entries SET kind='edit' WHERE thread=? AND n=2").run(thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = readStore.makeStore(observed, dir);
    assert.deepEqual(readStore.chatHistoryMessages(read, thread, "3.1", 2)?.map((m) => m.text), ["message-1", "message-2"]);
    assert.ok(changed);
    assert.deepEqual(readStore.chatHistoryMessages(read, thread, "3.1", 2)?.map((m) => m.text), ["message-1"]);
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a history boundary uses the timestamp index and keeps a 64-bit key", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "1.1", null, null).id;
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at)
      VALUES(?,?,'message',?,'agent','worker',?,?)`);
    put.run(thread, 1, "1.1", "earlier", 1);
    put.run(thread, 9007199254740993n, "large.1", "boundary", 2);
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${readStore.CHAT_HISTORY_BOUNDARY}`).all(thread, "large.1");
    assert.ok(plan.some((row) => String(row.detail).includes("entries_ts")));
    assert.deepEqual(readStore.chatHistoryMessages(readStore.makeStore(db, ""), thread, "large.1", 1)?.map((m) => m.text), ["earlier"]);
  } finally { store.close(); }
});

test("history pages share bounded old-letter preparation after handover", async () => {
  const dir = mkdtempSync(join(tmpdir(), "history-reader-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db;
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const threadRow = store.openThread("ember", "CHAT", "1.1", null, null);
    const thread = threadRow.id;
    const short = store.openThread("ember", "CHAT", "2.1", null, null).id;
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,ts,letter,author_kind,author,text,at)
      VALUES(?,?,?,?,?,'agent','worker',?,?)`);
    db.exec("BEGIN");
    put.run(thread, 1, "message", "1.1", null, "kept", 1);
    for (let n = 2; n <= 151; n++) put.run(thread, n, "edit", n === 2 ? "edit.1" : null, "letter", `other-${n}`, n);
    put.run(short, 1, "message", "short.1", null, "short", 1);
    db.exec("COMMIT");

    const args = { thread, before: null, limit: 1 };
    const controller = new AbortController();
    const abandoned = readers.read("chatHistoryMessages", args, "en", { signal: controller.signal });
    const kept = readers.read("chatHistoryMessages", args, "en");
    // Attach rejection handlers immediately, including when another assertion fails before these reads settle.
    void abandoned.catch(() => {});
    void kept.catch(() => {});
    assert.deepEqual(JSON.parse(await readers.read("chatHistoryMessages", { thread: short, before: null, limit: 1 }, "en"))
      .map((m: { text: string }) => m.text), ["short"]);
    assert.equal(JSON.parse(await readers.read("chatHistoryMessages", { thread, before: "edit.1", limit: 1 }, "en")), null);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    assert.deepEqual(JSON.parse(await kept).map((m: { text: string }) => m.text), ["kept"]);
    const hub = { store, chatOf: () => null,
      historyMessages: async (id: number, before: string | null, limit: number) =>
        JSON.parse(await readers.read("chatHistoryMessages", { thread: id, before, limit }, "en")) } as unknown as Hub;
    store.messageAt = () => { throw new Error("station message lookup used"); };
    store.messagesBefore = () => { throw new Error("station page lookup used"); };
    assert.match(await threadHistory(hub, "worker", threadRow, "internal", "CHAT/1.1", { limit: 1 }), /kept/);
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
