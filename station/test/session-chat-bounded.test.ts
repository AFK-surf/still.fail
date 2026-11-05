import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { SESSION_CHAT_EMBER, SESSION_CHAT_INDEXED, SESSION_CHAT_OTHER, SessionChatPreparation } from "../src/store/session-chat-index.ts";

test("naming a session with at most one chat needs no background preparation", () => {
  const store = Store.open(":memory:");
  try {
    const requests: string[] = [];
    store.requestSessionChat = (session) => requests.push(session);
    assert.equal(store.sessionChat("s"), null);
    const thread = store.openThread("ember", "CHAT", "only", "Only chat", null);
    store.joinThread(thread.id, "s", "ember");
    assert.equal(store.sessionChat("s")?.thread.id, thread.id);
    assert.deepEqual(requests, []);
    assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM session_chat_scopes").get()?.n, 0);
    assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM cc_sessions").get()?.n, 0);
  } finally { store.close(); }
});

test("naming a session's most recent chat does not traverse its older chats", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const latest = store.openThread("ember", "EMBER", "latest", null, null).id;
    store.joinThread(latest, "s", "ember");
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,1,'message','person','p',100)").run(latest);
    const add = (from: number, to: number) => {
      db.exec("BEGIN");
      for (let n = from; n <= to; n++) {
        const old = store.openThread("slack", "C", `old-${n}`, null, null).id;
        store.joinThread(old, "s", "slack");
      }
      db.exec("COMMIT");
    };
    let visits = 0, traced = false;
    db.function("visited_session_chat", (thread) => { visits++; return thread; });
    const prepare = () => {
      const work = new SessionChatPreparation();
      while (!work.step(db, "s").done) {}
    };
    const proxy = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          if (sql === SESSION_CHAT_INDEXED) {
            const own = SESSION_CHAT_EMBER.replace("WHERE session=?1", "WHERE session=?1 AND visited_session_chat(thread)=thread");
            const other = SESSION_CHAT_OTHER.replace("WHERE session=?1", "WHERE session=?1 AND visited_session_chat(thread)=thread");
            const observed = sql.replace(SESSION_CHAT_EMBER, own).replace(SESSION_CHAT_OTHER, other);
            assert.notEqual(observed, sql);
            const plan = (s: string) => target.prepare(`EXPLAIN QUERY PLAN ${s}`).all("s").map((r) => r.detail);
            assert.deepEqual(plan(observed), plan(sql), "counting keeps the actual query plan");
            traced = true;
            return target.prepare(observed);
          }
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    (store as any).db = proxy;
    const read = () => {
      visits = 0;
      assert.equal(store.sessionChat("s")?.thread.id, latest);
      return visits;
    };
    add(1, 40);
    prepare();
    const before = read();
    assert.ok(traced && before > 0, "the chat lookup's candidates are counted");
    add(41, 400);
    prepare();
    const after = read();
    assert.equal(after, before, `naming the chat visited ${before}, then ${after}, linked chats`);
  } finally { store.close(); }
});
