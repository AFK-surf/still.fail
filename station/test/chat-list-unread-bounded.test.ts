import assert from "node:assert/strict";
import { test } from "node:test";
import { sessionOps } from "../src/read/ops-sessions.ts";
import { listThreads, makeStore } from "../src/read/store.ts";
import { chatList } from "../src/sessions/others.ts";
import type { Hub } from "../src/sessions/hub.ts";
import { Store } from "../src/store/store.ts";

function fixture() {
  const store = Store.open(":memory:");
  store.insertSession({ key: "agent", connect: "ember", runtime: "claude", profile: "cc",
    workspace: "/work", token: "token", createdAt: 1, lastActiveAt: 1 });
  const thread = store.openThread("ember", "EMBER", "the-chat", "The chat", null).id;
  store.joinThread(thread, "agent", "ember");
  const db = store.db;
  const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,?,'message','agent','agent','findable',?)");
  db.exec("BEGIN");
  for (let n = 1; n <= 5_000; n++) put.run(thread, n, n);
  db.exec("COMMIT");
  let visited = 0;
  db.function("visit_unused_unread", (_n) => { visited++; return 1; });
  const instrumented = new Proxy(db, {
    get(target, property) {
      if (property === "prepare") return (source: string) => target.prepare(
        source.includes("COUNT(*) AS c FROM entries") && source.includes("json_each(")
          ? source.replace("AND NOT (author_kind", "AND visit_unused_unread(n) IS NOT NULL AND NOT (author_kind")
          : source,
      );
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  return { store, db, thread, instrumented, visited: () => visited };
}

test("the reader for chat_list does not count messages it will not show", () => {
  const f = fixture();
  try {
    const read = makeStore(f.db, "/no-station-config");
    assert.equal(listThreads(read, "", null, f.thread)[0]?.unread, 5_000, "thread views retain the exact count");
    read.db = f.instrumented;
    const rows = sessionOps.threadList!(read, {}) as ReturnType<typeof listThreads>;
    assert.equal(rows[0]?.thread.id, f.thread);
    assert.equal(rows[0]?.lastMessage?.text, "findable");
    assert.equal(f.visited(), 0, `chat_list visited ${f.visited()} unread messages`);
  } finally { f.store.close(); }
});

test("chat_list without a reader does not count messages it will not show", async () => {
  const f = fixture();
  try {
    Object.defineProperty(f.store, "db", { configurable: true, value: f.instrumented });
    const hub = { store: f.store, threadList: null, workspaces: () => [], wsOf: () => null,
      outsideChats: () => [], link: () => undefined } as unknown as Hub;
    const listed = await chatList(hub, "agent", { query: "findable" });
    assert.match(listed, /The chat/);
    assert.match(listed, /findable/);
    assert.equal(f.visited(), 0, `chat_list visited ${f.visited()} unread messages`);
  } finally {
    Object.defineProperty(f.store, "db", { configurable: true, value: f.db });
    f.store.close();
  }
});

test("a list that asks for no unread counts can still provide people and conversation order", () => {
  const f = fixture();
  try {
    Object.defineProperty(f.store, "db", { configurable: true, value: f.instrumented });
    const rows = f.store.listThreads("", null, null, "none");
    assert.equal(rows[0]?.thread.id, f.thread);
    assert.equal(rows[0]?.lastMessage?.text, "findable");
    assert.equal(f.visited(), 0, `the list visited ${f.visited()} unread messages`);
  } finally {
    Object.defineProperty(f.store, "db", { configurable: true, value: f.db });
    f.store.close();
  }
});
