import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { RECENT_CHAT_LIST } from "../src/store/chat-list.ts";
import { installRecentChatIndex, readGlobalRecentChatIndex, stepRecentChatIndex } from "../src/store/chat-list-index.ts";
import { Store } from "../src/store/store.ts";

for (const recursive of [false, true]) test(`a global recent page uses a maintained count and ordering (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const thread = (name: string, created: number) => {
      const id = store.openThread("ember", "EMBER", name, name, null).id;
      db.prepare("UPDATE threads SET created_at = ? WHERE id = ?").run(created, id);
      return id;
    };
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','p','hello',?)");
    const ids = Array.from({ length: 30 }, (_, i) => {
      const id = thread(`old-${i}`, i - 15);
      if (i % 3 !== 0) put.run(id, i - 20);
      return id;
    });
    const original = (limit: number) => {
      const rows = db.prepare(RECENT_CHAT_LIST).all(null, null, limit) as { id: number; total: number }[];
      return { ids: rows.map((row) => row.id), total: rows[0]?.total ?? 0 };
    };
    installRecentChatIndex(db);
    assert.equal(readGlobalRecentChatIndex(db, 5), null, "an unprepared old index is not a complete page");
    const first = stepRecentChatIndex(db, 3);
    assert.ok(first.processed <= 3);
    assert.equal(first.done, false);

    // The first batch and later batches must see changes made while the old chats are being prepared.
    db.prepare("UPDATE entries SET at = 999 WHERE thread = ? AND n = 1").run(ids[1]);
    db.prepare("DELETE FROM threads WHERE id = ?").run(ids[2]);
    const added = thread("added", 1000);
    put.run(added, -200);
    let done = false;
    for (let i = 0; i < 100 && !done; i++) {
      const step = stepRecentChatIndex(db, 3);
      assert.ok(step.processed <= 3, "each transaction has a fixed number of old or changed chats");
      done = step.done;
    }
    assert.ok(done, "preparation reaches a complete state");
    const expected = original(5);
    db.setAuthorizer((action, table) => action === constants.SQLITE_READ &&
      ["threads", "thread_state", "entries", "sessions", "thread_sessions"].includes(table ?? "")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.deepEqual(readGlobalRecentChatIndex(db, 5), expected); }
    finally { db.setAuthorizer(null); }

    // A change invalidates the index until it is accounted, rather than returning an old count or ordering.
    db.prepare("UPDATE entries SET at = 2000 WHERE thread = ? AND n = 1").run(ids[4]);
    assert.equal(readGlobalRecentChatIndex(db, 5), null);
    while (!stepRecentChatIndex(db, 3).done) { /* Account changed chats in bounded transactions. */ }
    assert.deepEqual(readGlobalRecentChatIndex(db, 5), original(5));
  } finally { db.setAuthorizer(null); store.close(); }
});
