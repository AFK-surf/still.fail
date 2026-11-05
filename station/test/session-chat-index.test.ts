import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
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

test("the two orders keep SQLite's tie breaking and old non-integer times", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installSessionChatIndex(db);
    const ids = Array.from({ length: 4 }, (_, n) => {
      const id = store.openThread(n % 2 ? "ember" : "slack", "C", `tie-${n}`, null, null).id;
      store.joinThread(id, "s", "c");
      db.prepare("UPDATE threads SET created_at=10 WHERE id=?").run(id);
      db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,1,'message','person','p',?)")
        .run(id, n < 2 ? 4.25 : 4.5);
      return id;
    });
    prepare(store, "s");
    assert.equal(indexedSessionChat(db, "s")?.id, ids[3]);
    assert.equal(indexedSessionChat(db, "s")?.id, store.sessionChat("s")?.thread.id);
    db.prepare("UPDATE entries SET at=? WHERE thread=? AND n=1").run("old-text-time", ids[0]!);
    prepare(store, "s");
    assert.equal(indexedSessionChat(db, "s")?.id, ids[0]);
    assert.equal(indexedSessionChat(db, "s")?.id, store.sessionChat("s")?.thread.id);
  } finally { store.close(); }
});

test("readiness and the chosen chat share a snapshot with another writer", () => {
  const dir = mkdtempSync(join(tmpdir(), "session-chat-snapshot-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db, writer = new DatabaseSync(path);
  try {
    installSessionChatIndex(db);
    const first = store.openThread("ember", "C", "first", null, null).id;
    const later = store.openThread("slack", "C", "later", null, null).id;
    store.joinThread(first, "s", "c"); store.joinThread(later, "s", "c");
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,1,'message','person','p',10)").run(first);
    prepare(store, "s");
    let changed = false;
    const proxy = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const statement = target.prepare(sql);
          if (sql.includes("WITH own AS MATERIALIZED")) return new Proxy(statement, {
            get(query, key) {
              if (key === "get") return (...args: unknown[]) => {
                writer.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,1,'message','person','p',20)").run(later);
                changed = true;
                return query.get(...(args as never[]));
              };
              const value = Reflect.get(query, key, query);
              return typeof value === "function" ? value.bind(query) : value;
            },
          });
          return statement;
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    assert.equal(indexedSessionChat(proxy, "s")?.id, first);
    assert.ok(changed);
    assert.equal(sessionChatReady(db, "s"), false);
    prepare(store, "s");
    assert.equal(indexedSessionChat(db, "s")?.id, later);
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
