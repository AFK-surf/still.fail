import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { makeStore } from "../src/read/store.ts";
import { sharedChatRows } from "../src/read/views.ts";

const viewer = { sub: "me", email: "me", name: "Me", role: "owner", workspace: "w", device: "d" } as const;

test("a shared chat row finds the last different author without visiting a long run of the same person", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/s", token: "s", createdAt: 1, lastActiveAt: 1 });
    const thread = store.openThread("ember", "CHAT", "chat", null, null).id;
    store.joinThread(thread, "s", "ember");
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,?,'message',?,?,'hello',?)");
    db.exec("BEGIN");
    put.run(thread, 1, "agent", "s", 1);
    for (let n = 2; n <= 5_001; n++) put.run(thread, n, "person", "me", n);
    db.exec("COMMIT");
    let visited = 0;
    db.function("visit_different_author", (_n) => { visited++; return 1; });
    const read = makeStore(db, "/no-station-config");
    read.db = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(
          sql.includes("FROM entries INDEXED BY entries_said") && sql.includes("n < ?2")
            ? sql.replace("WHERE thread = ?1", "WHERE visit_different_author(n) AND thread = ?1")
            : sql,
        );
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    const row = sharedChatRows(read, viewer, null, null).find((item: any) => item.thread === thread);
    assert.deepEqual(row?.said, { n: 5_001, authorKind: "person", author: "me", other: 1 });
    assert.equal(visited, 0, "a maintained boundary needs no old messages");
    db.prepare("UPDATE thread_state SET said_other_known=0 WHERE thread=?").run(thread);
    assert.throws(() => sharedChatRows(read, viewer, null, null), /sidebar said state pending/);
    assert.ok(visited <= 64, `an old row should leave after one bounded slice (visited ${visited})`);
  } finally { store.close(); }
});
