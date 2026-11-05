import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { ccSessionReady } from "../src/store/cc-thread-index.ts";
import { indexedSessionChat, installSessionChatIndex, SESSION_CHAT_EMBER, SESSION_CHAT_OTHER,
  SessionChatPreparation, sessionChatReady } from "../src/store/session-chat-index.ts";

function prepare(store: Store, session: string, limit = 8): number {
  const work = new SessionChatPreparation();
  let visited = 0;
  for (let steps = 0; steps < 2_000; steps++) {
    const result = work.step(store.db, session, limit);
    assert.ok(result.visited <= limit, "each preparation slice is bounded");
    visited += result.visited;
    if (result.done) return visited;
  }
  throw new Error("session chat preparation did not finish");
}

test("a prepared session chooses its latest chat across surfaces and follows changes", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installSessionChatIndex(db);
    const own = store.openThread("ember", "EMBER", "own", null, null).id;
    const slack = store.openThread("slack", "C", "slack", null, null).id;
    const empty = store.openThread("ember", "EMBER", "empty", null, null).id;
    for (const [id, connect] of [[own, "ember"], [slack, "slack"], [empty, "ember"]] as const) store.joinThread(id, "s", connect);
    db.prepare("UPDATE threads SET created_at=1 WHERE id IN (?,?,?)").run(own, slack, empty);
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','p',?)");
    put.run(own, 1, 10); put.run(slack, 1, 20);
    const same = () => assert.equal(indexedSessionChat(db, "s")?.id ?? null, store.sessionChat("s")?.thread.id ?? null);
    assert.equal(sessionChatReady(db, "s"), false);
    prepare(store, "s"); same();
    assert.equal(indexedSessionChat(db, "s")?.id, slack);
    put.run(own, 2, 30);
    assert.equal(ccSessionReady(db, "s"), false);
    prepare(store, "s"); same();
    assert.equal(indexedSessionChat(db, "s")?.id, own);
    db.prepare("UPDATE entries SET at=5 WHERE thread=? AND n=2").run(own);
    prepare(store, "s"); same();
    assert.equal(indexedSessionChat(db, "s")?.id, slack);
    db.prepare("DELETE FROM thread_sessions WHERE thread=? AND session='s'").run(slack);
    prepare(store, "s"); same();
    assert.equal(indexedSessionChat(db, "s")?.id, own);
    store.leaveThread(own, "s");
    prepare(store, "s"); same();
    assert.equal(indexedSessionChat(db, "s")?.id, own, "a left membership still counts");
    db.prepare("DELETE FROM thread_sessions WHERE session='s'").run();
    prepare(store, "s"); same();
    assert.equal(indexedSessionChat(db, "s"), null);
  } finally { store.close(); }
});

test("old sessions are prepared in bounded batches, including members added behind the cursor", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installSessionChatIndex(db);
    const late = store.openThread("ember", "EMBER", "late", null, null).id;
    db.exec("BEGIN");
    for (let n = 0; n < 70; n++) {
      const id = store.openThread(n % 2 ? "ember" : "slack", "C", `old-${n}`, null, null).id;
      store.joinThread(id, "s", "c");
    }
    db.exec("COMMIT");
    const cc = new SessionChatPreparation();
    while (!ccSessionReady(db, "s")) cc.step(db, "s", 8);
    assert.equal(cc.step(db, "s", 8).done, false);
    store.joinThread(late, "s", "ember");
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,1,'message','person','p',1000)").run(late);
    prepare(store, "s", 8);
    assert.equal(indexedSessionChat(db, "s")?.id, late);
    assert.equal(store.sessionChat("s")?.thread.id, late);
  } finally { store.close(); }
});

test("both chat candidates seek their own ordered index", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installSessionChatIndex(db);
    for (const [sql, index] of [[SESSION_CHAT_EMBER, "session_chat_ember_order"], [SESSION_CHAT_OTHER, "cc_session_order"]] as const) {
      const plan = db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all("s").map((row) => String(row.detail)).join("\n");
      assert.match(plan, new RegExp(`SEARCH .*${index} \\(session=\\?\\)`));
      assert.doesNotMatch(plan, /SCAN |TEMP B-TREE/);
    }
  } finally { store.close(); }
});
