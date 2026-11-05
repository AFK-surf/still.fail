import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants, DatabaseSync } from "node:sqlite";
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
    db.setAuthorizer((action, name) => action === constants.SQLITE_CREATE_TRIGGER && name === "recent_chat_entry_before_change"
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

for (const value of ["created time", "message time"] as const) test(`an undisplayed chat's 64-bit ${value} does not prevent a recent page`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const visible = store.openThread("ember", "EMBER", "visible", "Visible", null).id;
    const hidden = store.openThread("ember", "EMBER", "hidden", "Hidden", null).id;
    db.prepare("UPDATE threads SET created_at = 100 WHERE id = ?").run(visible);
    if (value === "created time") db.prepare("UPDATE threads SET created_at = ? WHERE id = ?").run(-9_007_199_254_740_993n, hidden);
    else {
      db.prepare("UPDATE threads SET created_at = 0 WHERE id = ?").run(hidden);
      db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','p','hello',?)")
        .run(hidden, -9_007_199_254_740_993n);
    }
    const expected = db.prepare(RECENT_CHAT_LIST).all(null, null, 1) as { id: number; total: number }[];
    assert.deepEqual(expected.map((row) => row.id), [visible]);
    installRecentChatIndex(db);
    while (!stepRecentChatIndex(db, 2).done) { /* Prepare even the chats outside the requested page. */ }
    assert.deepEqual(readGlobalRecentChatIndex(db, 1), { ids: [visible], total: 2 });
  } finally { store.close(); }
});

for (const arrival of ["old", "new"] as const) test(`an undisplayed ${arrival} chat's 64-bit id does not prevent a recent page`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const visible = store.openThread("ember", "EMBER", "visible", "Visible", null).id;
    db.prepare("UPDATE threads SET created_at = 100 WHERE id = ?").run(visible);
    const insert = () => db.prepare(`INSERT INTO threads(id,surface,channel,thread_ts,title,created_at)
      VALUES (?,'ember','EMBER','hidden','Hidden',0)`).run(9_007_199_254_740_993n);
    if (arrival === "old") insert();
    installRecentChatIndex(db);
    if (arrival === "new") insert();
    const expected = db.prepare(RECENT_CHAT_LIST).all(null, null, 1) as { id: number; total: number }[];
    assert.deepEqual(expected.map((row) => row.id), [visible]);
    while (!stepRecentChatIndex(db, 2).done) { /* Prepare even the chats outside the requested page. */ }
    assert.deepEqual(readGlobalRecentChatIndex(db, 1), { ids: [visible], total: 2 });
  } finally { store.close(); }
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

for (const recursive of [false, true]) test(`old message inserts keep or restore the selected ordering (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const chat = store.openThread("ember", "EMBER", "chat", "Chat", null).id;
    const other = store.openThread("ember", "EMBER", "other", "Other", null).id;
    db.prepare("UPDATE threads SET created_at = 1 WHERE id IN (?, ?)").run(chat, other);
    const message = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,?,'message','person','p','hello',?)");
    message.run(chat, 5, 30);
    message.run(other, 1, 20);
    installRecentChatIndex(db);
    while (!stepRecentChatIndex(db, 3).done) { /* Prepare before old messages arrive. */ }
    const page = readGlobalRecentChatIndex(db, 5);
    message.run(chat, 1, 10);
    assert.deepEqual(readGlobalRecentChatIndex(db, 5), page, "an older message does not change the selected one");
    db.prepare("DELETE FROM entries WHERE thread = ? AND n = 5").run(chat);
    db.prepare("INSERT OR REPLACE INTO thread_state(thread,last_n,said_n,person_n,letters) VALUES (?,5,5,NULL,0)").run(chat);
    while (!stepRecentChatIndex(db, 3).done) { /* Prepare the unresolved pointer left by an old writer. */ }
    assert.deepEqual(readGlobalRecentChatIndex(db, 5), { ids: [other, chat], total: 2 });
    message.run(chat, 5, 30);
    assert.equal(readGlobalRecentChatIndex(db, 5), null, "filling the selected number changes the ordering");
    while (!stepRecentChatIndex(db, 3).done) { /* Account the resolved pointer. */ }
    assert.deepEqual(readGlobalRecentChatIndex(db, 5), { ids: [chat, other], total: 2 });
  } finally { store.close(); }
});

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

for (const recursive of [false, true]) test(`recent ordering matches the original through interleaved old writes (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    let seed = 0x49c2a718;
    const pick = (n: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
    let nextName = 0;
    const addThread = () => {
      const id = store.openThread("ember", "EMBER", `chat-${nextName++}`, "Chat", null).id;
      db.prepare("UPDATE threads SET created_at = ? WHERE id = ?").run(pick(100), id);
    };
    for (let i = 0; i < 20; i++) addThread();
    installRecentChatIndex(db);
    const insert = db.prepare("INSERT OR REPLACE INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES (?,?,?,?, 'person','p','hello',?)");
    const check = (step: number) => {
      const actual = readGlobalRecentChatIndex(db, 5);
      if (actual === null) return;
      const rows = db.prepare(RECENT_CHAT_LIST).all(null, null, 5) as { id: number; total: number }[];
      assert.deepEqual(actual, { ids: rows.map((row) => row.id), total: rows[0]?.total ?? 0 }, `after write ${step}`);
    };
    for (let i = 0; i < 300; i++) {
      const threads = db.prepare("SELECT id, thread_ts FROM threads ORDER BY id").all() as { id: number; thread_ts: string }[];
      if (threads.length === 0) addThread();
      else {
        const { id, thread_ts } = threads[pick(threads.length)]!;
        const entries = db.prepare("SELECT n FROM entries WHERE thread = ? ORDER BY n").all(id) as { n: number }[];
        const next = (entries.at(-1)?.n ?? 0) + 1;
        const action = pick(9);
        if (action === 0) addThread();
        else if (action === 1) insert.run(id, next, "message", null, pick(100));
        else if (action === 2) insert.run(id, next, "edit", null, pick(100));
        else if (action === 3 && entries.length) {
          const n = entries[pick(entries.length)]!.n;
          db.prepare("UPDATE entries SET at = ? WHERE thread = ? AND n = ?").run(pick(100), id, n);
        } else if (action === 4 && entries.length) {
          const n = entries[pick(entries.length)]!.n;
          db.prepare("DELETE FROM entries WHERE thread = ? AND n = ?").run(id, n);
        } else if (action === 5 && entries.length) {
          const n = entries[pick(entries.length)]!.n;
          insert.run(id, n, pick(2) ? "message" : "edit", null, pick(100));
        } else if (action === 6) db.prepare("UPDATE threads SET created_at = ? WHERE id = ?").run(pick(100), id);
        else if (action === 7) db.prepare("DELETE FROM threads WHERE id = ?").run(id);
        else if (action === 8) db.prepare("INSERT OR REPLACE INTO threads(id,surface,channel,thread_ts,created_at) VALUES (?,'ember','EMBER',?,?)")
          .run(100_000 + i, thread_ts, pick(100));
      }
      check(i);
      if (pick(3) !== 0) stepRecentChatIndex(db, 2);
      check(i);
    }
    while (!stepRecentChatIndex(db, 3).done) { /* Finish the interleaved batches. */ }
    check(300);
  } finally { store.close(); }
});

test("a recent page keeps its count and ordering on one snapshot while another connection updates them", () => {
  const dir = mkdtempSync(join(tmpdir(), "recent-chat-snapshot-"));
  const path = join(dir, "station.db");
  const store = Store.open(path);
  const db = store.db;
  let reader: DatabaseSync | undefined;
  try {
    const first = store.openThread("ember", "EMBER", "first", "First", null).id;
    const second = store.openThread("ember", "EMBER", "second", "Second", null).id;
    db.prepare("UPDATE threads SET created_at = 1 WHERE id IN (?, ?)").run(first, second);
    const message = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','p','hello',?)");
    message.run(first, 10);
    message.run(second, 20);
    installRecentChatIndex(db);
    while (!stepRecentChatIndex(db, 3).done) { /* Prepare before a second connection reads. */ }
    reader = new DatabaseSync(path, { readOnly: true });
    let added: number | null = null;
    const observed = new Proxy(reader, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const statement = target.prepare(sql);
          if (sql !== "SELECT total, complete FROM recent_chat_meta WHERE id = 1") return statement;
          return new Proxy(statement, {
            get(row, member) {
              if (member === "get") return (...args: Parameters<typeof row.get>) => {
                const result = row.get(...args);
                if (added === null) {
                  added = store.openThread("ember", "EMBER", "added", "Added", null).id;
                  message.run(added, 30);
                  while (!stepRecentChatIndex(db, 3).done) { /* The writer finishes between the two reads. */ }
                }
                return result;
              };
              const value = Reflect.get(row, member, row);
              return typeof value === "function" ? value.bind(row) : value;
            },
          });
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    assert.deepEqual(readGlobalRecentChatIndex(observed, 5), { ids: [second, first], total: 2 });
    assert.ok(added !== null);
    assert.deepEqual(readGlobalRecentChatIndex(reader, 5), { ids: [added, second, first], total: 3 });
  } finally {
    reader?.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
