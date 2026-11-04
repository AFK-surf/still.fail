import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { listThreads, makeStore } from "../src/read/store.ts";
import { chats } from "../src/read/views.ts";

const viewer = { sub: "me", email: "me", name: "Me", role: "owner", workspace: "w", device: "d" } as const;

function fixture() {
  const store = Store.open(":memory:");
  store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/s", token: "s", createdAt: 1, lastActiveAt: 1 });
  const thread = store.openThread("ember", "EMBER", "chat", null, null).id;
  store.joinThread(thread, "s", "ember");
  const read = makeStore(store.db, "/no-station-config");
  return { store, thread, read };
}

test("the sidebar only seeks the first unread message, while a thread still has its exact count", () => {
  const { store, thread, read } = fixture();
  const db = store.db;
  try {
    const put = db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, text, at) VALUES (?, ?, 'message', 'agent', 's', 'hello', ?)");
    db.exec("BEGIN");
    for (let n = 1; n <= 5_000; n++) put.run(thread, n, n);
    db.exec("COMMIT");
    assert.equal(listThreads(read, viewer.email, null, thread)[0]?.unread, 5_000);

    let visited = 0;
    db.function("visit_unread", (_n) => { visited++; return 1; });
    read.db = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(
          sql.includes("FROM entries WHERE") && sql.includes("json_each(?3)")
            ? sql.replace("AND NOT (author_kind", "AND visit_unread(n) IS NOT NULL AND NOT (author_kind")
            : sql,
        );
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    const row = chats(read, viewer, false).find((item) => item.thread === thread);
    assert.equal(row?.unread, true);
    assert.ok(visited > 0 && visited <= 2, `only the first unread message is needed (visited ${visited})`);
  } finally { store.close(); }
});

test("the sidebar unread flag follows read position and excludes the viewer's own messages and letters", () => {
  const { store, thread, read } = fixture();
  try {
    const put = store.db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, text, at, letter) VALUES (?, ?, 'message', ?, ?, 'hello', ?, ?)");
    put.run(thread, 1, "person", "me", 1, null);
    put.run(thread, 2, "person", "someone", 2, "{}");
    assert.equal(chats(read, viewer, false)[0]?.unread, false);
    put.run(thread, 3, "person", "someone", 3, null);
    put.run(thread, 4, "agent", "s", 4, null);
    assert.equal(chats(read, viewer, false)[0]?.unread, true);
    assert.equal(listThreads(read, viewer.email, null, thread)[0]?.unread, 2);
    store.setRead(viewer.email, thread, 4);
    put.run(thread, 5, "person", "me", 5, null);
    assert.equal(chats(read, viewer, false)[0]?.unread, false);
    assert.equal(listThreads(read, viewer.email, null, thread)[0]?.unread, 0);
  } finally { store.close(); }
});

test("an unread existence check recognizes the viewer's Slack identity", () => {
  const { store, read } = fixture();
  try {
    const thread = store.openThread("slack:T", "C", "1.0", null, null).id;
    store.joinThread(thread, "s", "slack");
    store.setSlackIdentity(viewer.email, "U1", true);
    const put = store.db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, text, at) VALUES (?, ?, 'message', 'person', ?, 'hello', ?)");
    put.run(thread, 1, "U1", 1);
    assert.equal(listThreads(read, viewer.email, null, thread, "exists")[0]?.unread, 0);
    put.run(thread, 2, "U2", 2);
    put.run(thread, 3, "U2", 3);
    assert.equal(listThreads(read, viewer.email, null, thread, "exists")[0]?.unread, 1);
    assert.equal(listThreads(read, viewer.email, null, thread)[0]?.unread, 2);
    store.setSlackIdentity(viewer.email, "U2", true);
    assert.equal(listThreads(read, viewer.email, null, thread, "exists")[0]?.unread, 0);
  } finally { store.close(); }
});
