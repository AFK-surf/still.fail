import assert from "node:assert/strict";
import { test } from "node:test";
import { sessionOps } from "../src/read/ops-sessions.ts";
import { makeStore } from "../src/read/store.ts";
import type { Hub } from "../src/sessions/hub.ts";
import { chatList } from "../src/sessions/others.ts";
import { RECENT_CHAT_LIST, SEARCH_CHAT_LIST } from "../src/store/chat-list.ts";
import { Store } from "../src/store/store.ts";

for (const reader of [false, true]) test(`searching chats does not read people or other unused details (reader ${reader})`, async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "agent", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "token", createdAt: 1, lastActiveAt: 1 });
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person',?,?,?)");
    for (let n = 0; n < 250; n++) {
      const thread = store.openThread("ember", "CHAT", `chat-${n}`, n % 10 === 0 ? `Matching title ${n}` : `Title ${n}`, null).id;
      store.joinThread(thread, "agent", "ember");
      put.run(thread, `person-${n}`, `words ${n}`, n);
    }
    const plain = makeStore(db, "/no-station-config");
    const common = { store, workspaces: () => [], wsOf: () => null, outsideChats: () => [], link: () => undefined };
    const old = { ...common, threadList: async () => sessionOps.threadList!(plain, {}) } as unknown as Hub;
    const expected = await chatList(old, "agent", { query: "MATCHING", limit: 5 });
    assert.match(expected, /\(20 more; raise limit or narrow query\)/);

    let visited = 0;
    db.function("visit_search_person", (_author) => { visited++; return 1; });
    const instrumented = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(sql.replace(
          "SELECT author FROM thread_people WHERE thread = ?",
          "SELECT author FROM thread_people WHERE thread = ? AND visit_search_person(author)",
        ));
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    Object.defineProperty(store, "db", { value: instrumented, configurable: true });
    const read = makeStore(instrumented, "/no-station-config");
    const hub = { ...common,
      threadList: reader ? async () => sessionOps.threadList!(read, {}) : null,
      searchChatList: reader ? async (ws: string | null, home: string | null, limit: number, query: string) => sessionOps.searchChatList!(read, { ws, home, limit, query }) : null,
    } as unknown as Hub;
    assert.equal(await chatList(hub, "agent", { query: "MATCHING", limit: 5 }), expected);
    assert.equal(visited, 0, `the search read people from ${visited} chats although it does not show them`);
  } finally {
    Object.defineProperty(store, "db", { value: db, configurable: true });
    store.close();
  }
});

test("chat selection seeks each chat's messages and edits by their existing indexes", () => {
  const store = Store.open(":memory:");
  try {
    for (const [sql, args] of [[RECENT_CHAT_LIST, [null, null, 5]], [SEARCH_CHAT_LIST, [null, null]]] as const) {
      const plan = store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args).map((r) => String(r.detail));
      assert.ok(plan.some((p) => /SEARCH e USING INDEX .*entries.*thread=\? AND n=\?/.test(p)), plan.join("\n"));
      assert.ok(!plan.some((p) => /^SCAN [me](?:\s|$)/.test(p)), plan.join("\n"));
      if (sql === SEARCH_CHAT_LIST) assert.ok(plan.some((p) => /SEARCH x USING COVERING INDEX entries_edits \(thread=\? AND target=\?\)/.test(p)), plan.join("\n"));
    }
  } finally { store.close(); }
});
