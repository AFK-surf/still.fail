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
    let details = 0;
    db.function("visit_chat_list_person", (_author) => { visited++; return 1; });
    db.function("visit_chat_list_detail", (_n) => { details++; return 1; });
    const instrumented = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(sql
          .replace("SELECT author FROM thread_people WHERE thread = ?",
            "SELECT author FROM thread_people WHERE thread = ? AND visit_chat_list_person(author)")
          .replace("SELECT m.* FROM thread_state t JOIN merged m ON m.thread = t.thread AND m.n = t.said_n WHERE t.thread = ?",
            "SELECT m.* FROM thread_state t JOIN merged m ON m.thread = t.thread AND m.n = t.said_n WHERE t.thread = ? AND visit_chat_list_detail(m.n)"));
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
    assert.equal(visited, 0, `the list read people from ${visited} chats although it does not show them`);
    assert.equal(details, 5, `the list read message details from ${details} chats to show five`);
  } finally {
    Object.defineProperty(store, "db", { value: db, configurable: true });
    store.close();
  }
});

test("recent chat selection keeps workspace rules, ordering and the number left out", async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    for (const [key, ws] of [["agent", "here"], ["other", "elsewhere"], ["legacy", null]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: `token-${key}`, createdAt: 1, lastActiveAt: 1, ws });
    }
    const put = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES (?,?,?,?,?,?,?,?)");
    const make = (name: string, home: string | null, members: string[], created: number, said: number | null) => {
      const thread = store.openThread("ember", "EMBER", name, name, null).id;
      db.prepare("UPDATE threads SET home = ?, created_at = ? WHERE id = ?").run(home, created, thread);
      for (const member of members) store.joinThread(thread, member, "ember");
      if (said !== null) put.run(thread, 1, "message", null, "person", "person", `words ${name}`, said);
      return thread;
    };
    make("own", "agent", ["other"], 100, 20);
    make("foreign-home", "other", ["agent"], 101, 99);
    make("shared-membership", null, ["other", "agent"], 102, 30);
    make("empty", null, ["agent"], 30, null);
    make("legacy-home", "missing", ["agent"], 103, 50);
    make("legacy-member", null, ["legacy"], 104, 60);
    make("no-members", null, [], 105, 70);
    const edited = make("edited", null, ["agent"], 99, 30);
    put.run(edited, 2, "edit", 1, "person", "person", "edited words", 500);
    const untitled = make("untitled", null, ["agent"], 98, 30);
    db.prepare("UPDATE threads SET title = NULL, auto_title = NULL WHERE id = ?").run(untitled);
    make("İSTANBUL", null, ["agent"], 97, 30);
    make("negative", null, ["agent"], 200, -1);
    const unreadable = make("missing-state", null, ["agent"], 30, 4);
    db.prepare("DELETE FROM thread_state WHERE thread = ?").run(unreadable);

    const read = makeStore(db, "/no-station-config");
    const common = { store, workspaces: () => ["workspace"], wsOf: (key: string | null) => key === null ? "home" : "here",
      outsideChats: () => [], link: (key: string) => `https://example.test/${key}` };
    const old = { ...common, threadList: async () => sessionOps.threadList!(read, {}) } as unknown as Hub;
    const recent = { ...common, threadList: async () => sessionOps.threadList!(read, {}),
      recentChatList: async (ws: string | null, home: string | null, limit: number) => sessionOps.recentChatList!(read, { ws, home, limit }),
      searchChatList: async (ws: string | null, home: string | null, limit: number, query: string) => sessionOps.searchChatList!(read, { ws, home, limit, query }),
    } as unknown as Hub;
    for (const limit of [1, 2, 5, 100, "not-a-number"]) {
      assert.equal(await chatList(recent, "agent", { limit }), await chatList(old, "agent", { limit }), `limit ${limit}`);
    }
    for (const query of ["edited", "WORDS", "agent", "i\u0307stanbul", "missing"]) {
      for (const limit of [1, 5, 100, "not-a-number"]) {
        assert.equal(await chatList(recent, "agent", { query, limit }), await chatList(old, "agent", { query, limit }), `${query}, limit ${limit}`);
      }
    }
  } finally { store.close(); }
});
