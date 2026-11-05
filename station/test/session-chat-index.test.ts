import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { ccSessionReady, CcIndexPreparation } from "../src/store/cc-thread-index.ts";
import { indexedSessionChat, installSessionChatIndex, SESSION_CHAT_INDEXED, SESSION_CHAT_MANY, SESSION_CHAT_SMALL,
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

// The order the store used before the prepared index, retained as an independent reference for old data.
function original(store: Store, session: string): unknown {
  return store.db.prepare(`SELECT t.id FROM thread_sessions m JOIN threads t ON t.id=m.thread WHERE m.session=?
    ORDER BY (SELECT e.at FROM entries e WHERE e.thread=t.id ORDER BY e.n DESC LIMIT 1) DESC,
      t.created_at DESC,t.id DESC LIMIT 1`).get(session)?.id ?? null;
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
    const same = () => {
      assert.equal(indexedSessionChat(db, "s")?.id ?? null, original(store, "s"));
      assert.equal(store.sessionChat("s")?.thread.id ?? null, original(store, "s"));
    };
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
    assert.equal(original(store, "s"), late);
  } finally { store.close(); }
});

test("a prepared name follows remaining entries when their old state row is absent", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const first = store.openThread("ember", "C", "first", null, null).id;
    const second = store.openThread("slack", "C", "second", null, null).id;
    store.joinThread(first, "s", "c"); store.joinThread(second, "s", "c");
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','p',?)");
    put.run(first, 1, 60); put.run(first, 2, 100); put.run(second, 1, 50);
    prepare(store, "s");
    assert.equal(indexedSessionChat(db, "s")?.id, first);
    // Old writers can remove one entry, which also removes thread_state while earlier entries remain.
    db.prepare("DELETE FROM entries WHERE thread=? AND n=2").run(first);
    assert.equal(db.prepare("SELECT 1 FROM thread_state WHERE thread=?").get(first), undefined);
    prepare(store, "s");
    assert.equal(original(store, "s"), first);
    assert.equal(indexedSessionChat(db, "s")?.id, first);
    // With no state row, the copy-destination projection stays NULL even though the remaining entry changes.
    db.prepare("UPDATE entries SET at=40 WHERE thread=? AND n=1").run(first);
    prepare(store, "s");
    assert.equal(original(store, "s"), second);
    assert.equal(indexedSessionChat(db, "s")?.id, second);
  } finally { store.close(); }
});

test("old missing state is handled during preparation on either chat surface", () => {
  for (const surface of ["ember", "slack"]) {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const first = store.openThread(surface, "C", "first", null, null).id;
      const second = store.openThread("ember", "C", "second", null, null).id;
      store.joinThread(first, "s", "c"); store.joinThread(second, "s", "c");
      const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','p',?)");
      put.run(first, 1, 10); put.run(first, 2, 100); put.run(second, 1, 50);
      db.prepare("DELETE FROM entries WHERE thread=? AND n=1").run(first);
      assert.equal(db.prepare("SELECT 1 FROM thread_state WHERE thread=?").get(first), undefined);
      prepare(store, "s");
      assert.equal(original(store, "s"), first);
      assert.equal(indexedSessionChat(db, "s")?.id, first);
    } finally { store.close(); }
  }
});

test("copy destination tracking alone does not prepare chat names", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("slack", "C", "only-copy", null, null).id;
    store.joinThread(thread, "s", "c");
    const work = new CcIndexPreparation();
    while (!ccSessionReady(db, "s")) work.step(db, "s");
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,1,'message','person','p',10)").run(thread);
    while (!ccSessionReady(db, "s")) work.step(db, "s");
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM session_chat_scopes").get()?.n, 0);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM session_chat_rows").get()?.n, 0);
  } finally { store.close(); }
});

test("the chat candidate seeks its ordered index", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installSessionChatIndex(db);
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${SESSION_CHAT_INDEXED}`).all("s").map((row) => String(row.detail)).join("\n");
    assert.match(plan, /SEARCH r USING COVERING INDEX session_chat_order \(session=\?\)/);
    assert.doesNotMatch(plan, /SCAN |TEMP B-TREE/);
  } finally { store.close(); }
});

test("the small-session check reads at most two memberships through their index", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const plan = (sql: string) => db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all("s").map((row) => String(row.detail)).join(" | ");
    assert.match(plan(SESSION_CHAT_SMALL), /SEARCH thread_sessions USING INDEX thread_sessions_session \(session=\?\)/);
    assert.match(plan(SESSION_CHAT_MANY), /SEARCH thread_sessions USING COVERING INDEX thread_sessions_session \(session=\?\)/);
    assert.match(SESSION_CHAT_SMALL, /LIMIT 2/);
    assert.match(SESSION_CHAT_MANY, /LIMIT 1 OFFSET 1/);
  } finally { store.close(); }
});

test("a single-chat answer keeps its snapshot while a second chat joins", () => {
  const dir = mkdtempSync(join(tmpdir(), "session-chat-single-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db, writer = new DatabaseSync(path);
  try {
    const first = store.openThread("ember", "CHAT", "first", null, null).id;
    const second = store.openThread("ember", "CHAT", "second", null, null).id;
    store.joinThread(first, "s", "ember");
    let joined = false;
    const proxy = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const query = target.prepare(sql);
          if (sql !== SESSION_CHAT_SMALL) return query;
          return new Proxy(query, {
            get(statement, key) {
              if (key === "get") return (...args: never[]) => {
                const row = statement.get(...args);
                if (!joined) {
                  writer.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES(?,'s','ember',1)").run(second);
                  joined = true;
                }
                return row;
              };
              const value = Reflect.get(statement, key, statement);
              return typeof value === "function" ? value.bind(statement) : value;
            },
          });
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    (store as any).db = proxy;
    const requests: string[] = [];
    store.requestSessionChat = (session) => requests.push(session);
    assert.equal(store.sessionChat("s")?.thread.id, first);
    assert.equal(joined, true);
    assert.deepEqual(requests, []);
    assert.equal(store.sessionChat("s")?.thread.id, second);
    assert.deepEqual(requests, ["s"]);
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
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
    assert.equal(indexedSessionChat(db, "s")?.id, original(store, "s"));
    db.prepare("UPDATE entries SET at=? WHERE thread=? AND n=1").run("old-text-time", ids[0]!);
    prepare(store, "s");
    assert.equal(indexedSessionChat(db, "s")?.id, ids[0]);
    assert.equal(indexedSessionChat(db, "s")?.id, original(store, "s"));
    db.prepare("UPDATE entries SET at=? WHERE thread=? AND n=1").run("z-old-text-time", ids[1]!);
    prepare(store, "s");
    assert.equal(indexedSessionChat(db, "s")?.id, ids[1]);
    assert.equal(indexedSessionChat(db, "s")?.id, original(store, "s"));
  } finally { store.close(); }
});

test("empty chats sort by creation and thread id across both surfaces", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installSessionChatIndex(db);
    const ids = Array.from({ length: 4 }, (_, n) => {
      const id = store.openThread(n % 2 ? "ember" : "slack", "C", `empty-${n}`, null, null).id;
      store.joinThread(id, "s", "c");
      db.prepare("UPDATE threads SET created_at=? WHERE id=?").run(n < 2 ? 1 : 2, id);
      return id;
    });
    prepare(store, "s");
    assert.equal(indexedSessionChat(db, "s")?.id, ids[3]);
    assert.equal(indexedSessionChat(db, "s")?.id, original(store, "s"));
    db.prepare("DELETE FROM thread_sessions WHERE thread=? AND session='s'").run(ids[3]!);
    prepare(store, "s");
    assert.equal(indexedSessionChat(db, "s")?.id, ids[2]);
    assert.equal(indexedSessionChat(db, "s")?.id, original(store, "s"));
  } finally { store.close(); }
});

for (const recursive of [false, true]) {
  test(`replacing and rolling back source rows keeps the chosen chat (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      installSessionChatIndex(db);
      const own = store.openThread("ember", "C", "own", null, null).id;
      const other = store.openThread("slack", "C", "other", null, null).id;
      store.joinThread(own, "s", "c"); store.joinThread(other, "s", "c");
      const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,1,'message','person','p',?)");
      put.run(own, 30); put.run(other, 20);
      prepare(store, "s");
      const rowid = db.prepare("SELECT rowid FROM entries WHERE thread=? AND n=1").get(own)!.rowid as number;
      db.exec("BEGIN");
      db.prepare("INSERT OR REPLACE INTO entries(rowid,thread,n,kind,author_kind,author,at) VALUES(?,?,2,'message','person','p',40)")
        .run(rowid, other);
      db.exec("ROLLBACK");
      assert.equal(indexedSessionChat(db, "s")?.id, own);
      db.prepare("INSERT OR REPLACE INTO entries(rowid,thread,n,kind,author_kind,author,at) VALUES(?,?,2,'message','person','p',40)")
        .run(rowid, other);
      prepare(store, "s");
      assert.equal(indexedSessionChat(db, "s")?.id, other);
      assert.equal(indexedSessionChat(db, "s")?.id, original(store, "s"));
    } finally { store.close(); }
  });
}

for (const recursive of [false, true]) test(`interleaved old entry and membership changes keep the original name order (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    const threads = Array.from({ length: 5 }, (_, n) => store.openThread(n % 2 ? "slack" : "ember", "C", `t-${n}`, null, null).id);
    for (const session of ["a", "b"]) for (const thread of threads.slice(0, 3)) store.joinThread(thread, session, "c");
    for (const session of ["a", "b"]) prepare(store, session);
    let random = 0x3a92bc17;
    const pick = (n: number) => { random = (Math.imul(random, 1664525) + 1013904223) >>> 0; return (random >>> 8) % n; };
    for (let step = 0; step < 120; step++) {
      const thread = threads[pick(threads.length)]!, session = pick(2) === 0 ? "a" : "b", n = 1 + pick(4);
      switch (pick(6)) {
        case 0: db.prepare("INSERT OR IGNORE INTO thread_sessions(thread,session,connect,joined_at) VALUES(?,?,'c',?)").run(thread, session, step); break;
        case 1: db.prepare("DELETE FROM thread_sessions WHERE thread=? AND session=?").run(thread, session); break;
        case 2: db.prepare("INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','p',?)").run(thread, n, pick(100)); break;
        case 3: db.prepare("DELETE FROM entries WHERE thread=? AND n=?").run(thread, n); break;
        case 4: db.prepare("UPDATE entries SET at=? WHERE thread=? AND n=?").run(pick(100), thread, n); break;
        case 5: db.prepare("UPDATE threads SET created_at=? WHERE id=?").run(pick(100), thread); break;
      }
      for (const key of ["a", "b"]) {
        prepare(store, key);
        assert.equal(indexedSessionChat(db, key)?.id ?? null, original(store, key), `step ${step}, session ${key}`);
      }
    }
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
          if (sql === SESSION_CHAT_INDEXED) return new Proxy(statement, {
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

test("an incompatible session chat index is neither read nor prepared", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installSessionChatIndex(db);
    db.prepare("UPDATE session_chat_meta SET version=2 WHERE id=1").run();
    assert.throws(() => installSessionChatIndex(db), /incompatible/);
    assert.throws(() => sessionChatReady(db, "s"), /incompatible/);
    assert.throws(() => new SessionChatPreparation().step(db, "s"), /incompatible/);
    assert.equal(db.prepare("SELECT count(*) AS n FROM session_chat_scopes").get()?.n, 0);
  } finally { store.close(); }
});

test("a writer between readiness and a preparation transaction is not missed", () => {
  const dir = mkdtempSync(join(tmpdir(), "session-chat-handover-")), path = join(dir, "stillfail.db");
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
        if (property === "exec") return (sql: string) => {
          if (sql === "BEGIN IMMEDIATE" && !changed) {
            writer.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,1,'message','person','p',20)").run(later);
            changed = true;
          }
          return target.exec(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    assert.equal(new SessionChatPreparation().step(proxy, "s").done, false);
    assert.ok(changed);
    prepare(store, "s");
    assert.equal(indexedSessionChat(db, "s")?.id, later);
    assert.equal(indexedSessionChat(db, "s")?.id, original(store, "s"));
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const tracked of [false, true]) test(`a session removed before ${tracked ? "name" : "copy"} tracking is not recreated`, () => {
  const dir = mkdtempSync(join(tmpdir(), "session-chat-removed-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db, writer = new DatabaseSync(path);
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "s", createdAt: 1, lastActiveAt: 1 });
    const thread = store.openThread("ember", "CHAT", "s", null, null).id;
    store.joinThread(thread, "s", "ember");
    if (tracked) {
      const copy = new CcIndexPreparation();
      while (!ccSessionReady(db, "s")) copy.step(db, "s");
    }
    let removed = false;
    const proxy = new Proxy(db, {
      get(target, property) {
        if (property === "exec") return (sql: string) => {
          if (sql === "BEGIN IMMEDIATE" && !removed) {
            writer.prepare("DELETE FROM sessions WHERE key='s'").run();
            removed = true;
          }
          return target.exec(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    const work = new SessionChatPreparation();
    work.step(proxy, "s", 64, { existingSession: true });
    assert.equal(work.step(proxy, "s", 64, { existingSession: true }).done, true);
    assert.equal(removed, true);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM session_chat_scopes WHERE session='s'").get()?.n, 0);
    if (!tracked) assert.equal(db.prepare("SELECT COUNT(*) AS n FROM cc_sessions WHERE session='s'").get()?.n, 0);
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a synchronous title keeps its immediate answer while requesting preparation", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const older = store.openThread("slack", "C", "older", null, null).id;
    const thread = store.openThread("ember", "C", "first", null, null).id;
    store.joinThread(older, "s", "c");
    store.joinThread(thread, "s", "c");
    const requests: string[] = [];
    store.requestSessionChat = (session) => requests.push(session);
    assert.equal(store.sessionChat("s")?.thread.id, thread);
    assert.deepEqual(requests, ["s"]);
    prepare(store, "s");
    assert.equal(store.sessionChat("s")?.thread.id, thread);
    assert.deepEqual(requests, ["s"]);
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,1,'message','person','p',10)").run(thread);
    assert.equal(store.sessionChat("s")?.thread.id, thread);
    assert.deepEqual(requests, ["s", "s"]);
  } finally { store.close(); }
});

test("deleting a session releases its prepared chat-name scope", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "s", createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const own = store.openThread("ember", "EMBER", "own", null, null);
    store.joinThread(own.id, "s", "ember");
    prepare(store, "s");
    assert.equal(db.prepare("SELECT count(*) AS n FROM session_chat_scopes WHERE session='s'").get()?.n, 1);
    assert.equal(db.prepare("SELECT count(*) AS n FROM session_chat_rows WHERE session='s'").get()?.n, 1);
    db.exec("SAVEPOINT gone; DELETE FROM sessions WHERE key='s'; ROLLBACK TO gone; RELEASE gone");
    assert.equal(db.prepare("SELECT count(*) AS n FROM session_chat_scopes WHERE session='s'").get()?.n, 1, "a rolled back deletion keeps its scope");
    store.deleteSession("s");
    assert.equal(db.prepare("SELECT count(*) AS n FROM session_chat_scopes WHERE session='s'").get()?.n, 0);
    assert.equal(db.prepare("SELECT count(*) AS n FROM session_chat_rows WHERE session='s'").get()?.n, 0);
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "new-s", createdAt: 2, lastActiveAt: 2, ws: "mine" });
    const replacement = store.openThread("ember", "EMBER", "new-own", null, null);
    store.joinThread(replacement.id, "s", "ember");
    prepare(store, "s");
    assert.equal(indexedSessionChat(db, "s")?.id, replacement.id);
  } finally { store.close(); }
});
