import assert from "node:assert/strict";
import { test } from "node:test";
import { sessionOps } from "../src/read/ops-sessions.ts";
import { makeStore } from "../src/read/store.ts";
import type { Hub } from "../src/sessions/hub.ts";
import { chatList } from "../src/sessions/others.ts";
import { Store } from "../src/store/store.ts";

for (const reader of [false, true]) test(`a recent chat list reads details only for its displayed chats (reader ${reader})`, async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "agent", connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/work", token: "token", createdAt: 1, lastActiveAt: 1 });
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person',?,'hello',?)");
    for (let i = 0; i < 250; i++) {
      const thread = store.openThread("ember", "EMBER", `chat-${i}`, `Title ${i}`, null).id;
      store.joinThread(thread, "agent", "ember");
      put.run(thread, `person-${i}`, i);
    }
    const plain = makeStore(db, "/no-station-config");
    const common = { store, workspaces: () => [], wsOf: () => null, outsideChats: () => [], link: () => undefined };
    const old = { ...common, threadList: async () => sessionOps.threadList!(plain, {}) } as unknown as Hub;
    const expected = await chatList(old, "agent", { limit: 5 });
    assert.match(expected, /\(245 more; raise limit or narrow query\)/);

    let visited = 0;
    db.function("visit_chat_list_person", (_author) => { visited++; return 1; });
    const instrumented = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(sql.replace(
          "SELECT author FROM thread_people WHERE thread = ?",
          "SELECT author FROM thread_people WHERE thread = ? AND visit_chat_list_person(author)",
        ));
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    Object.defineProperty(store, "db", { value: instrumented, configurable: true });
    const read = makeStore(instrumented, "/no-station-config");
    const hub = { ...common,
      threadList: reader ? async () => sessionOps.threadList!(read, {}) : null,
      recentChatList: reader ? async (ws: string | null, home: string | null, limit: number) => sessionOps.recentChatList!(read, { ws, home, limit }) : null,
    } as unknown as Hub;
    assert.equal(await chatList(hub, "agent", { limit: 5 }), expected);
    assert.ok(visited <= 5, `the list read people from ${visited} chats to show only five`);
  } finally {
    Object.defineProperty(store, "db", { value: db, configurable: true });
    store.close();
  }
});
