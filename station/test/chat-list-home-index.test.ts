import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { recentChatIds } from "../src/store/chat-list.ts";
import { installRecentHomeIndex, readPreparedDefaultHome, scanRecentHomeChatsStep, settleRecentHomeChatStep, settleRecentHomeOrderStep, settleRecentHomeSessionStep } from "../src/store/chat-list-home-index.ts";
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

for (const recursive of [false, true]) test(`a session moving again while home chats are being marked is reconciled (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "one", createdAt: 1, lastActiveAt: 1, ws: "work" });
    for (let i = 0; i < 8; i++) {
      const thread = store.openThread("ember", "EMBER", `chat-${i}`, `Chat ${i}`, null).id;
      if (i < 4) db.prepare("UPDATE threads SET home = 'one' WHERE id = ?").run(thread);
      else store.joinThread(thread, "one", "ember");
    }
    installRecentHomeIndex(db);
    while (!scanRecentHomeChatsStep(db, 2).scanDone) { /* Enqueue the original chats. */ }
    while (!settleRecentHomeChatStep(db, 2).chatsDone) { /* Account the original chats. */ }
    assert.equal(db.prepare("SELECT total FROM recent_home_meta").get()?.total, 0);
    db.prepare("UPDATE sessions SET ws = NULL WHERE key = 'one'").run();
    assert.equal(settleRecentHomeSessionStep(db, 2).visited, 2);
    db.prepare("UPDATE sessions SET ws = 'work' WHERE key = 'one'").run();
    db.prepare("UPDATE sessions SET ws = NULL WHERE key = 'one'").run();
    let done = false;
    for (let i = 0; i < 30 && !done; i++) {
      const batch = settleRecentHomeSessionStep(db, 2);
      assert.ok(batch.visited <= 2);
      done = batch.sessionsDone;
    }
    assert.ok(done);
    for (let i = 0; i < 30 && !settleRecentHomeChatStep(db, 2).chatsDone; i++) { /* Apply the marked chats. */ }
    const rows = db.prepare("SELECT thread FROM recent_home_rows ORDER BY at DESC, said_at DESC, created_at DESC, thread DESC")
      .all() as { thread: number }[];
    const expected = recentChatIds(db, "fallback", "fallback", 100);
    assert.deepEqual(rows.map((row) => row.thread), expected.ids);
    assert.equal(db.prepare("SELECT total FROM recent_home_meta").get()?.total, expected.total);
    assert.equal(expected.total, 8);
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`a message time change cannot leave the default home order stale (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const first = store.openThread("ember", "EMBER", "first", "First", null).id;
    const second = store.openThread("ember", "EMBER", "second", "Second", null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','p','hello',?)");
    put.run(first, 1);
    put.run(second, 2);
    installRecentHomeIndex(db);
    while (!scanRecentHomeChatsStep(db, 2).scanDone) { /* Enqueue the old chats. */ }
    while (!settleRecentHomeChatStep(db, 2).chatsDone) { /* Account for the old chats. */ }
    assert.deepEqual(readPreparedDefaultHome(db, 5), { ids: [second, first], total: 2 });
    db.prepare("UPDATE entries SET at = 30 WHERE thread = ? AND n = 1").run(first);
    assert.equal(readPreparedDefaultHome(db, 5), null, "the changed order has not yet been accounted");
    assert.deepEqual(settleRecentHomeOrderStep(db, 1), { ordersDone: true, visited: 1 });
    assert.deepEqual(readPreparedDefaultHome(db, 5), recentChatIds(db, "fallback", "fallback", 5));
    assert.equal(readPreparedDefaultHome(db, 5)?.ids[0], first);
  } finally { store.close(); }
});

for (const recursive of [false, true]) for (const how of ["number", "timestamp", "timestamp update", "state"] as const) {
  test(`replacing ${how} keeps the default home order exact (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
      const chat = store.openThread("ember", "EMBER", "chat", "Chat", null).id;
      const other = store.openThread("ember", "EMBER", "other", "Other", null).id;
      db.prepare("UPDATE threads SET created_at = 100 WHERE id = ?").run(chat);
      db.prepare("UPDATE threads SET created_at = 50 WHERE id = ?").run(other);
      db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES (?,1,'message','same','person','p','hello',1)").run(chat);
      if (how === "timestamp update")
        db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES (?,2,'edit','different','person','p','edit',2)").run(chat);
      installRecentHomeIndex(db);
      while (!scanRecentHomeChatsStep(db, 2).scanDone) { /* Enqueue the chats. */ }
      while (!settleRecentHomeChatStep(db, 2).chatsDone) { /* Prepare their ordering. */ }
      assert.deepEqual(readPreparedDefaultHome(db, 5), recentChatIds(db, "home", "home", 5));
      if (how === "number")
        db.prepare("INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'edit','person','p','edit',2)").run(chat);
      else if (how === "timestamp")
        db.prepare("INSERT OR REPLACE INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES (?,2,'edit','same','person','p','edit',2)").run(chat);
      else if (how === "timestamp update") db.prepare("UPDATE OR REPLACE entries SET ts = 'same' WHERE thread = ? AND n = 2").run(chat);
      else db.prepare("INSERT OR REPLACE INTO thread_state(thread,last_n,said_n,person_n,letters) VALUES (?,1,NULL,NULL,0)").run(chat);
      assert.equal(readPreparedDefaultHome(db, 5), null, "the displaced message cannot leave a stale page");
      while (!settleRecentHomeOrderStep(db, 2).ordersDone) { /* Account the changed ordering. */ }
      assert.deepEqual(readPreparedDefaultHome(db, 5), recentChatIds(db, "home", "home", 5));
    } finally { store.close(); }
  });
}
