import assert from "node:assert/strict";
import { worded } from "../../client/core-ts/src/chat-row.ts";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { listThreads, makeStore } from "../src/read/store.ts";
import { chats, sharedChatRows } from "../src/read/views.ts";

const viewer = { sub: "me", email: "me", name: "Me", role: "owner", workspace: "w", device: "d" } as const;

function fixture() {
  const store = Store.open(":memory:");
  store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/s", token: "s", createdAt: 1, lastActiveAt: 1 });
  const thread = store.openThread("ember", "CHAT", "chat", null, null).id;
  store.joinThread(thread, "s", "ember");
  const read = makeStore(store.db, "/no-station-config");
  return { store, thread, read };
}

test("the sidebar counts no unread message, while a thread still has its exact count", () => {
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
    // The chat list is made once for everyone: unread is where the viewer read against its latest message and the
    // latest before that its author did not write (read/store.ts saidOf), none of what came after counted.
    assert.equal(visited, 0, `no unread message is visited (visited ${visited})`);
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

test("the chat list is made once for everyone: a viewer's row is it with what is theirs", () => {
  const { store, thread, read } = fixture();
  try {
    store.setAutoTitle(thread, "部署", false);
    const put = store.db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, text, at) VALUES (?, ?, 'message', ?, ?, 'hello', ?)");
    put.run(thread, 1, "person", "me", 1);
    put.run(thread, 2, "agent", "s", 2);
    store.setRead("me", thread, 2);
    store.setChatHidden("me", thread, true);
    const other = { ...viewer, sub: "you", email: "you" };
    // One list, the same for both: named by the chat itself, nothing of either viewer in it.
    const shared = sharedChatRows(read, viewer, null, null);
    assert.deepEqual(sharedChatRows(read, other, null, null), shared);
    assert.deepEqual(shared.map((r: any) => [r.thread, r.named.thread.autoTitle, r.said]), [[thread, "部署", { n: 2, authorKind: "agent", author: "s", other: 2 }]]);
    // Each viewer's: the same chat and name, their own unread and whether it is theirs.
    // (in the client's words: chat-row.ts `worded`)
    const words = { untitled: "新对话", directMessage: "私信", quotedOnly: "引用了一条消息" };
    const mine = worded(chats(read, viewer, false)[0]!, words);
    const yours = worded(chats(read, other, false)[0]!, words);
    assert.deepEqual([mine.title, mine.unread, mine.mine], ["部署", false, true]);
    assert.deepEqual([yours.title, yours.unread, yours.mine], ["部署", true, false]);
    assert.equal(mine.hidden, true);
    assert.equal(yours.hidden, false);
    assert.equal(store.getThread(thread)!.hiddenAt, null, "personal hiding does not archive the chat");
  } finally { store.close(); }
});
