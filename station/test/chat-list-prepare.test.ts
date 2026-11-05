import assert from "node:assert/strict";
import { test } from "node:test";
import { recentChatIds } from "../src/store/chat-list.ts";
import { readPreparedRecentHome } from "../src/store/chat-list-home-overlap.ts";
import { readGlobalRecentChatIndex } from "../src/store/chat-list-index.ts";
import { RecentChatPreparation, type RecentChatScope } from "../src/store/chat-list-prepare.ts";
import { readPreparedRecentWorkspace } from "../src/store/chat-list-scope-rows.ts";
import { Store } from "../src/store/store.ts";

for (const recursive of [false, true]) test(`requested recent pages prepare in bounded interleaved steps (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["here", "here"], ["away", "away"], ["default", null]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    for (let i = 0; i < 12; i++) {
      const thread = store.openThread("ember", "EMBER", `old-${i}`, "Old", null).id;
      if (i % 3 === 0) db.prepare("UPDATE threads SET home = ? WHERE id = ?").run(i % 2 ? "away" : "here", thread);
      else if (i % 3 === 1) { store.joinThread(thread, "here", "ember"); store.joinThread(thread, "missing", "ember"); }
      db.prepare("UPDATE threads SET created_at = ? WHERE id = ?").run(i, thread);
    }
    const scopes: RecentChatScope[] = [
      { ws: null, home: "here" }, { ws: "away", home: "here" }, { ws: "here", home: "here" },
    ];
    const page = ({ ws, home }: RecentChatScope) => ws === null ? readGlobalRecentChatIndex(db, 5)
      : ws === home ? readPreparedRecentHome(db, ws, 5) : readPreparedRecentWorkspace(db, ws, 5);
    const prep = new RecentChatPreparation(db, 2);
    let allDone = false;
    for (let round = 0; round < 1_000 && !allDone; round++) {
      if (round === 3) {
        const thread = store.openThread("ember", "EMBER", "new", "New", null).id;
        store.joinThread(thread, "here", "ember");
        store.joinThread(thread, "missing", "ember");
        db.prepare("UPDATE sessions SET ws = NULL WHERE key = 'away'").run();
      }
      allDone = true;
      for (const scope of scopes) {
        const result = prep.step(scope);
        assert.ok(result.visited <= 2, "one step has a fixed amount of source work");
        if (!result.done) allDone = false;
        else assert.deepEqual(page(scope), recentChatIds(db, scope.ws, scope.home, 5));
      }
    }
    assert.ok(allDone, "each requested scope becomes ready");
    for (const scope of scopes) assert.deepEqual(page(scope), recentChatIds(db, scope.ws, scope.home, 5));
  } finally { store.close(); }
});
