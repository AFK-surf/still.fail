import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { RECENT_CHAT_LIST } from "../src/store/chat-list.ts";
import { installRecentChatIndex, readGlobalRecentChatIndex, stepRecentChatIndex } from "../src/store/chat-list-index.ts";
import { Store } from "../src/store/store.ts";

test("installing recent chat writers avoids old message and membership history, and a failed install can retry", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const id = store.openThread("ember", "EMBER", "old", "Old", null).id;
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','p','hello',1)").run(id);
    db.setAuthorizer((action, name) => action === constants.SQLITE_CREATE_TRIGGER && name === "recent_chat_entry_add"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.throws(() => installRecentChatIndex(db)); }
    finally { db.setAuthorizer(null); }
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'recent_chat_meta'").get(), undefined);
    db.setAuthorizer((action, name) => action === constants.SQLITE_READ &&
      ["entries", "thread_state", "sessions", "thread_sessions"].includes(name ?? "") ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { installRecentChatIndex(db); }
    finally { db.setAuthorizer(null); }
    db.setAuthorizer((action) => action === constants.SQLITE_TRANSACTION ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { installRecentChatIndex(db); }
    finally { db.setAuthorizer(null); }
    assert.equal(readGlobalRecentChatIndex(db, 5), null);
  } finally { db.setAuthorizer(null); store.close(); }
});

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

for (const recursive of [false, true]) test(`an edit or a letter does not make the recent ordering wait (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const id = store.openThread("ember", "EMBER", "chat", "Chat", null).id;
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','p','hello',1)").run(id);
    installRecentChatIndex(db);
    while (!stepRecentChatIndex(db, 3).done) { /* Prepare the old chat. */ }
    const page = readGlobalRecentChatIndex(db, 5);
    assert.ok(page);
    db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES (?,2,'edit',1,'person','p','changed',2)").run(id);
    assert.deepEqual(readGlobalRecentChatIndex(db, 5), page, "an edit leaves the message's ordering untouched");
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at,letter) VALUES (?,3,'message','agent','a','letter',3,'peer')").run(id);
    assert.deepEqual(readGlobalRecentChatIndex(db, 5), page, "a letter does not become the latest visible message");
  } finally { store.close(); }
});

for (const recursive of [false, true]) for (const how of ["append", "replace"] as const) {
  test(`a message ${how} updates the ready recent ordering (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:");
    const db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
      const chat = store.openThread("ember", "EMBER", "chat", "Chat", null).id;
      const other = store.openThread("ember", "EMBER", "other", "Other", null).id;
      db.prepare("UPDATE threads SET created_at = 1 WHERE id IN (?, ?)").run(chat, other);
      const message = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,?,'message','person','p','hello',?)");
      message.run(chat, 1, 10);
      message.run(other, 1, 20);
      installRecentChatIndex(db);
      while (!stepRecentChatIndex(db, 3).done) { /* Prepare before the message changes. */ }
      assert.deepEqual(readGlobalRecentChatIndex(db, 5), { ids: [other, chat], total: 2 });
      if (how === "append") message.run(chat, 2, 30);
      else db.prepare("INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','p','changed',30)").run(chat);
      assert.equal(readGlobalRecentChatIndex(db, 5), null, "the old ordering is not returned after a message changes it");
      while (!stepRecentChatIndex(db, 3).done) { /* Account the message. */ }
      const rows = db.prepare(RECENT_CHAT_LIST).all(null, null, 5) as { id: number; total: number }[];
      assert.deepEqual(readGlobalRecentChatIndex(db, 5), { ids: rows.map((row) => row.id), total: rows[0]?.total ?? 0 });
    } finally { store.close(); }
  });
}

for (const recursive of [false, true]) for (const how of ["number", "timestamp", "timestamp update"] as const) {
  test(`replacing the latest message by ${how} invalidates its ordering (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:");
    const db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
      const id = store.openThread("ember", "EMBER", "chat", "Chat", null).id;
      db.prepare("UPDATE threads SET created_at = 100 WHERE id = ?").run(id);
      const other = store.openThread("ember", "EMBER", "other", "Other", null).id;
      db.prepare("UPDATE threads SET created_at = 50 WHERE id = ?").run(other);
      db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES (?,1,'message','same','person','p','hello',1)").run(id);
      if (how === "timestamp update")
        db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES (?,2,'edit','different','person','p','edit',2)").run(id);
      installRecentChatIndex(db);
      while (!stepRecentChatIndex(db, 3).done) { /* Prepare the chat before an older writer changes it. */ }
      assert.ok(readGlobalRecentChatIndex(db, 5));
      if (how === "number")
        db.prepare("INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'edit','person','p','edit',2)").run(id);
      else if (how === "timestamp")
        db.prepare("INSERT OR REPLACE INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES (?,2,'edit','same','person','p','edit',2)").run(id);
      else db.prepare("UPDATE OR REPLACE entries SET ts = 'same' WHERE thread = ? AND n = 2").run(id);
      assert.equal(readGlobalRecentChatIndex(db, 5), null, "a replaced latest message must not leave a stale page");
      while (!stepRecentChatIndex(db, 3).done) { /* Account the changed ordering. */ }
      const rows = db.prepare(RECENT_CHAT_LIST).all(null, null, 5) as { id: number; total: number }[];
      assert.deepEqual(readGlobalRecentChatIndex(db, 5), { ids: rows.map((row) => row.id), total: rows[0]?.total ?? 0 });
    } finally { store.close(); }
  });
}

for (const recursive of [false, true]) for (const what of ["thread", "thread update", "state"] as const) {
  test(`replacing a chat ${what} keeps the recent index exact (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:");
    const db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
      const id = store.openThread("ember", "EMBER", "chat", "Chat", null).id;
      db.prepare("UPDATE threads SET created_at = 100 WHERE id = ?").run(id);
      const other = store.openThread("ember", "EMBER", "other", "Other", null).id;
      db.prepare("UPDATE threads SET created_at = 50 WHERE id = ?").run(other);
      db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','p','hello',1)").run(id);
      installRecentChatIndex(db);
      while (!stepRecentChatIndex(db, 3).done) { /* Prepare before an older writer replaces a row. */ }
      if (what === "thread")
        db.prepare("INSERT OR REPLACE INTO threads (id,surface,channel,thread_ts,created_at) VALUES (999,'ember','EMBER','chat',200)").run();
      else if (what === "thread update") db.prepare("UPDATE OR REPLACE threads SET thread_ts = 'chat' WHERE id = ?").run(other);
      else db.prepare("INSERT OR REPLACE INTO thread_state(thread,last_n,said_n,person_n,letters) VALUES (?,1,NULL,NULL,0)").run(id);
      assert.equal(readGlobalRecentChatIndex(db, 5), null, "a replaced row must not leave a stale page");
      while (!stepRecentChatIndex(db, 3).done) { /* Account both the removed and new rows. */ }
      const rows = db.prepare(RECENT_CHAT_LIST).all(null, null, 5) as { id: number; total: number }[];
      assert.deepEqual(readGlobalRecentChatIndex(db, 5), { ids: rows.map((row) => row.id), total: rows[0]?.total ?? 0 });
    } finally { store.close(); }
  });
}
