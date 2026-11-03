import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { installOutflowChatIndex, outflowChatIndexReady, outflowChatIndexStep, outflowChatScopes } from "../src/store/outflow-index.ts";
import type { InWorkspace } from "../src/store/rows.ts";

const viewers: InWorkspace[] = [
  { workspace: "A", home: false }, { workspace: "B", home: false }, { workspace: "home", home: true },
];

function fixture() {
  const store = Store.open(":memory:");
  const db = store.db;
  const addSession = (key: string, ws: string | null, token = key) => store.insertSession({
    key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token, createdAt: 1, lastActiveAt: 1, ws,
  });
  const addThread = (name: string, members: string[]) => {
    const thread = store.openThreadOf("ember", "EMBER", name, name, "ann@x", members[0]!);
    for (const member of members) store.joinThread(thread.id, member, "ember");
    db.prepare("UPDATE threads SET created_at=10 WHERE id=?").run(thread.id);
    return thread.id;
  };
  const insertMessage = db.prepare("INSERT INTO entries (thread,n,kind,author_kind,author,text,at) VALUES (?,?,'message','person','ann@x','body',?)");
  const actual = () => (db.prepare("SELECT scope, thread, at FROM outflow_chat_order ORDER BY scope,thread").all() as {scope:string; thread:number; at:number}[])
    .map((r) => [r.scope, r.thread, r.at]);
  // Read the fixture's membership and activity directly, independently of the maintained index.
  const expected = () => (db.prepare(`SELECT DISTINCT CASE WHEN s.ws IS NULL THEN 'H' ELSE 'W' || s.ws END AS scope,
      t.id AS thread, MAX(t.created_at, COALESCE(e.at, 0)) AS at
    FROM threads t JOIN thread_sessions m ON m.thread=t.id JOIN sessions s ON s.key=m.session
      LEFT JOIN thread_state st ON st.thread=t.id LEFT JOIN entries e ON e.thread=t.id AND e.n=st.said_n AND e.kind='message'
    ORDER BY scope,thread`).all() as {scope:string; thread:number; at:number}[]).map((r) => [r.scope, r.thread, r.at]);
  const settle = () => {
    for (const viewer of viewers) for (const scope of outflowChatScopes(viewer)) {
      let steps = 0;
      while (!outflowChatIndexStep(db, scope, 1).done) assert.ok(++steps < 30, "bounded work converges");
    }
    assert.deepEqual(actual(), expected());
  };
  return { store, db, addSession, addThread, insertMessage, actual, expected, settle };
}

for (const recursive of [false, true]) test(`outflow chat order follows writes and old writers (recursive triggers ${recursive})`, () => {
  const { store, db, addSession, addThread, insertMessage, actual, expected, settle } = fixture();
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    addSession("a", "A"); addSession("b", "B"); addSession("home", null);
    const shared = addThread("shared", ["a", "b", "home"]);
    const other = addThread("other", ["a"]);
    insertMessage.run(shared, 1, 20); insertMessage.run(shared, 2, 30);
    db.setAuthorizer((action, table) => action === constants.SQLITE_READ && ["usage", "usage_compact", "entries"].includes(table ?? "")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { installOutflowChatIndex(db); } finally { db.setAuthorizer(null); }
    assert.deepEqual(actual(), [], "installation does not read or rewrite old chat or usage rows");
    assert.equal(outflowChatIndexReady(db, viewers[0]!), false);
    assert.deepEqual(outflowChatIndexStep(db, "WA", 1), { done: false, visited: 1 });
    // A write before the saved cursor, and another after it, must both survive a stopped/resumed build.
    insertMessage.run(shared, 3, 40);
    db.prepare("UPDATE threads SET created_at=15 WHERE id=?").run(other);
    settle();
    assert.deepEqual(actual(), expected());

    insertMessage.run(shared, 4, 50);
    assert.equal(outflowChatIndexReady(db, viewers[0]!), false);
    assert.equal(outflowChatIndexReady(db, { workspace: "C", home: false }), true);
    assert.deepEqual(outflowChatIndexStep(db, "WA", 1), { done: true, visited: 1 });
    assert.equal(outflowChatIndexReady(db, viewers[1]!), true, "one refresh settles all scopes of a shared chat");
    assert.equal(outflowChatIndexReady(db, viewers[2]!), true);
    assert.deepEqual(actual(), expected());

    db.prepare("UPDATE entries SET at=75 WHERE thread=? AND n=4").run(shared); settle();
    db.prepare("UPDATE sessions SET ws='B' WHERE key='a'").run(); settle();
    db.prepare("DELETE FROM thread_sessions WHERE thread=? AND session='b'").run(shared); settle();
    db.prepare("INSERT OR IGNORE INTO sessions (key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws) VALUES ('ignored','ember','thread','claude','cc','/w','home',1,1,'A')").run(); settle();
    db.prepare("INSERT OR REPLACE INTO sessions (key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws) VALUES ('replacement','ember','thread','claude','cc','/w','home',1,1,'A')").run(); settle();
    db.prepare("INSERT OR REPLACE INTO sessions (key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws) VALUES ('a','ember','thread','claude','cc','/w','a',1,1,'A')").run(); settle();
    db.prepare("DELETE FROM entries WHERE thread=? AND n=4").run(shared); settle();
    db.prepare("DELETE FROM threads WHERE id=?").run(other); settle();
  } finally { store.close(); }
});

test("building the chat order reads no usage and resumes bounded old-thread batches", () => {
  const { store, db, addSession, addThread, insertMessage, actual, expected, settle } = fixture();
  try {
    addSession("a", "A");
    for (let i=0; i<12; i++) { const thread = addThread(`old-${i}`, ["a"]); insertMessage.run(thread, 1, i + 20); }
    installOutflowChatIndex(db);
    db.setAuthorizer((action, table) => action === constants.SQLITE_READ && ["usage", "usage_compact"].includes(table ?? "")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      for (let i=0; i<3; i++) assert.deepEqual(outflowChatIndexStep(db, "WA", 2), { done: false, visited: 2 });
      const extra = addThread("new", ["a"]); insertMessage.run(extra, 1, 99);
      settle();
    } finally { db.setAuthorizer(null); }
    assert.deepEqual(actual(), expected());
  } finally { store.close(); }
});
