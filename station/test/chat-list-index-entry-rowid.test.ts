import assert from "node:assert/strict";
import { test } from "node:test";
import { recentChatPage, RECENT_CHAT_PENDING } from "../src/read/recent-chat.ts";
import { recentChatIds } from "../src/store/chat-list.ts";
import { RecentChatPreparation, type RecentChatScope } from "../src/store/chat-list-prepare.ts";
import { Store } from "../src/store/store.ts";

const scopes: { name: string; scope: RecentChatScope }[] = [
  { name: "global", scope: { ws: null, home: "elsewhere" } },
  { name: "workspace", scope: { ws: "here", home: "elsewhere" } },
  { name: "home", scope: { ws: "here", home: "here" } },
];

for (const recursive of [false, true]) for (const how of ["insert", "insert negative", "update", "update _rowid_", "update oid"] as const) for (const { name, scope } of scopes)
  test(`an entry ${how} replacing another chat's rowid keeps the ${name} order exact (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
      store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: "one", createdAt: 1, lastActiveAt: 1, ws: "here" });
      const victim = store.openThread("ember", "CHAT", "victim", "Victim", null).id;
      store.joinThread(victim, "one", "ember");
      store.joinThread(victim, "missing", "ember");
      const other = store.openThreadOf("ember", "CHAT", "other", "Other", null, "one").id;
      db.prepare("UPDATE threads SET created_at = 0 WHERE id IN (?, ?)").run(victim, other);
      const message = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','p','hello',?)");
      message.run(victim, 100); message.run(other, 50);
      if (how.startsWith("update")) db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,2,'edit','person','p','edit',1)").run(other);
      if (how === "insert negative") db.prepare("UPDATE entries SET rowid = -1 WHERE thread = ? AND n = 1").run(victim);
      const preparation = new RecentChatPreparation(db, 16);
      const prepare = () => {
        let done = false;
        for (let i = 0; i < 1000 && !done; i++) done = preparation.step(scope).done;
        assert.ok(done);
      };
      prepare();
      assert.deepEqual(recentChatPage(db, scope.ws, scope.home, 5).ids, [victim, other]);
      const rowid = (db.prepare("SELECT rowid FROM entries WHERE thread = ? AND n = 1").get(victim) as { rowid: number }).rowid;
      if (how.startsWith("insert")) db.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,kind,author_kind,author,text,at)
        VALUES (?,?,2,'edit','person','p','edit',1)`).run(rowid, other);
      else {
        const column = how === "update _rowid_" ? "_rowid_" : how === "update oid" ? "oid" : "rowid";
        db.prepare(`UPDATE OR REPLACE entries SET ${column} = ? WHERE thread = ? AND n = 2`).run(rowid, other);
      }
      const expected = recentChatIds(db, scope.ws, scope.home, 5);
      assert.deepEqual(expected.ids, [other, victim], "the displaced latest message changes the original ordering");
      try {
        assert.deepEqual(recentChatPage(db, scope.ws, scope.home, 5), expected, "a ready page must reflect the displaced message");
      } catch (error) {
        if (!(error instanceof Error) || error.message !== RECENT_CHAT_PENDING) throw error;
      }
      prepare();
      assert.deepEqual(recentChatPage(db, scope.ws, scope.home, 5), expected);
    } finally { store.close(); }
  });
