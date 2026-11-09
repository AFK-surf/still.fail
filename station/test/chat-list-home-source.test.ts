import assert from "node:assert/strict";
import { test } from "node:test";
import { recentChatIds } from "../src/store/chat-list.ts";
import { FIRST_HOME_CHAT_MEMBERS, NEXT_HOME_CHAT_MEMBERS, recentHomeChatStep, type HomeChatCursor } from "../src/store/chat-list-home-source.ts";
import { Store } from "../src/store/store.ts";

test("the default home source agrees with the original home visibility rules", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    for (const [key, ws] of [["named", "work"], ["no-workspace", null], ["", "work"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: `token-${key}`, createdAt: 1, lastActiveAt: 1, ws });
    const make = (name: string, home: string | null, members: string[]) => {
      const thread = store.openThread("ember", "CHAT", name, name, null).id;
      db.prepare("UPDATE threads SET home = ? WHERE id = ?").run(home, thread);
      for (const member of members) store.joinThread(thread, member, "ember");
      return thread;
    };
    const cases = [make("named-home", "named", ["no-workspace"]), make("missing-home", "missing", ["named"]),
      make("default-home", "no-workspace", []), make("empty-home-key", "", []), make("orphan", null, []),
      make("named-members", null, ["named"]), make("unknown-member", null, ["named", "missing"]),
      make("default-member", null, ["named", "no-workspace"])];
    const expected = new Set(recentChatIds(db, "fallback", "fallback", 100).ids);
    for (const thread of cases) {
      let cursor: HomeChatCursor = { after: null, seen: false };
      for (;;) {
        const batch = recentHomeChatStep(db, BigInt(thread), cursor, 1);
        assert.ok(batch.visited <= 1);
        if (batch.done) { assert.equal(batch.included, expected.has(thread), `chat ${thread}`); break; }
        cursor = batch.cursor;
      }
    }
    assert.deepEqual(recentHomeChatStep(db, 999_999n, { after: null, seen: false }, 1),
      { done: true, included: false, visited: 0 });
  } finally { store.close(); }
});

test("home membership sources are read in bounded steps using the chat index", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "many", "Many", null).id;
    for (let i = 0; i < 130; i++) {
      const key = `agent-${String(i).padStart(3, "0")}`;
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws: "work" });
      store.joinThread(thread, key, "ember");
    }
    store.joinThread(thread, "zzz-unknown", "ember");
    let cursor: HomeChatCursor = { after: null, seen: false }, visits = 0, steps = 0;
    for (;;) {
      const batch = recentHomeChatStep(db, BigInt(thread), cursor, 3);
      assert.ok(batch.visited <= 3);
      visits += batch.visited;
      steps++;
      if (batch.done) { assert.equal(batch.included, true); break; }
      cursor = batch.cursor;
    }
    assert.equal(visits, 131);
    assert.ok(steps > 40);
    for (const [sql, args] of [[FIRST_HOME_CHAT_MEMBERS, [thread, 3]], [NEXT_HOME_CHAT_MEMBERS, [thread, "agent-010", 3]]] as const) {
      const plan = db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[];
      assert.ok(plan.some((row) => row.detail.includes("SEARCH thread_sessions USING COVERING INDEX sqlite_autoindex_thread_sessions_1")), JSON.stringify(plan));
      assert.ok(plan.every((row) => !row.detail.includes("TEMP B-TREE")), JSON.stringify(plan));
    }
  } finally { store.close(); }
});
