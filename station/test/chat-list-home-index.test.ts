import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { recentChatIds } from "../src/store/chat-list.ts";
import { installRecentHomeIndex, scanRecentHomeChatsStep, settleRecentHomeChatStep } from "../src/store/chat-list-home-index.ts";
import { Store } from "../src/store/store.ts";

test("old default-home chats are built in bounded steps while new chats arrive behind the cursor", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    for (const [key, ws] of [["named", "work"], ["default", null]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    for (let i = 0; i < 12; i++) {
      const id = store.openThread("ember", "EMBER", `chat-${i}`, `Chat ${i}`, null).id;
      if (i % 3 === 0) db.prepare("UPDATE threads SET home = 'named' WHERE id = ?").run(id);
      else if (i % 3 === 1) store.joinThread(id, "default", "ember");
      db.prepare("UPDATE threads SET created_at = ? WHERE id = ?").run(i, id);
    }
    installRecentHomeIndex(db);
    assert.equal(scanRecentHomeChatsStep(db, 2).visited, 2);
    db.prepare("INSERT INTO threads(id,surface,channel,thread_ts,created_at,home) VALUES (0,'ember','EMBER','behind',99,'missing')").run();
    let scanned = false;
    for (let i = 0; i < 20 && !scanned; i++) {
      const batch = scanRecentHomeChatsStep(db, 2);
      assert.ok(batch.visited <= 2);
      scanned = batch.scanDone;
    }
    assert.ok(scanned);
    let settled = false;
    for (let i = 0; i < 50 && !settled; i++) {
      const batch = settleRecentHomeChatStep(db, 2);
      assert.ok(batch.visited <= 2);
      settled = batch.chatsDone;
    }
    assert.ok(settled);
    const ids = (db.prepare("SELECT thread FROM recent_home_rows ORDER BY at DESC, said_at DESC, created_at DESC, thread DESC").all() as { thread: number }[])
      .map((row) => row.thread);
    const expected = recentChatIds(db, "fallback", "fallback", 100);
    assert.deepEqual(ids, expected.ids);
    assert.equal(db.prepare("SELECT total FROM recent_home_meta").get()?.total, expected.total);
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`a membership change behind a home scan cursor is not lost (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const thread = store.openThread("ember", "EMBER", "many", "Many", null).id;
    for (let i = 0; i < 8; i++) {
      const key = `agent-${i}`;
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws: "work" });
      store.joinThread(thread, key, "ember");
    }
    installRecentHomeIndex(db);
    while (!scanRecentHomeChatsStep(db, 2).scanDone) { /* Enqueue the old chat. */ }
    assert.equal(settleRecentHomeChatStep(db, 2).visited, 2);
    store.joinThread(thread, "000-missing", "ember");
    let done = false;
    for (let i = 0; i < 20 && !done; i++) done = settleRecentHomeChatStep(db, 2).chatsDone;
    assert.ok(done);
    assert.ok(db.prepare("SELECT 1 FROM recent_home_rows WHERE thread = ?").get(thread));
    assert.equal(db.prepare("SELECT total FROM recent_home_meta").get()?.total, 1);
    db.prepare("DELETE FROM thread_sessions WHERE thread = ? AND session = '000-missing'").run(thread);
    done = false;
    for (let i = 0; i < 20 && !done; i++) done = settleRecentHomeChatStep(db, 2).chatsDone;
    assert.ok(done);
    assert.equal(db.prepare("SELECT 1 FROM recent_home_rows WHERE thread = ?").get(thread), undefined);
    assert.equal(db.prepare("SELECT total FROM recent_home_meta").get()?.total, 0);
  } finally { store.close(); }
});

test("a failed default-home batch rolls back its row, count and pending work", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "orphan", "Orphan", null).id;
    installRecentHomeIndex(db);
    while (!scanRecentHomeChatsStep(db, 2).scanDone) { /* Enqueue the old chat. */ }
    db.setAuthorizer((action, name) => action === constants.SQLITE_INSERT && name === "recent_home_rows" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.throws(() => settleRecentHomeChatStep(db, 2)); }
    finally { db.setAuthorizer(null); }
    assert.equal(db.prepare("SELECT total FROM recent_home_meta").get()?.total, 0);
    assert.ok(db.prepare("SELECT 1 FROM recent_home_dirty WHERE thread = ?").get(thread));
    assert.equal(db.prepare("SELECT 1 FROM recent_home_work WHERE thread = ?").get(thread), undefined);
    assert.equal(settleRecentHomeChatStep(db, 2).chatsDone, true);
    assert.equal(db.prepare("SELECT total FROM recent_home_meta").get()?.total, 1);
  } finally { db.setAuthorizer(null); store.close(); }
});
