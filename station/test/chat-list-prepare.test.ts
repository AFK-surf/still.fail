import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
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
      const thread = store.openThread("ember", "CHAT", `old-${i}`, "Old", null).id;
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
        const thread = store.openThread("ember", "CHAT", "new", "New", null).id;
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

test("requested workspace preparation resumes after the database is reopened", () => {
  const dir = mkdtempSync(join(tmpdir(), "recent-preparation-restart-"));
  const path = join(dir, "station.db");
  let store = Store.open(path);
  try {
    store.insertSession({ key: "here", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "here", createdAt: 1, lastActiveAt: 1, ws: "here" });
    for (let i = 0; i < 30; i++) {
      const id = store.openThread("ember", "CHAT", `chat-${i}`, "Chat", null).id;
      store.joinThread(id, "here", "ember");
    }
    const scope = { ws: "here", home: "home" };
    let prep = new RecentChatPreparation(store.db, 2);
    for (let i = 0; i < 5; i++) assert.equal(prep.step(scope).done, false);
    store.close();
    store = Store.open(path);
    prep = new RecentChatPreparation(store.db, 2);
    let done = false;
    for (let i = 0; i < 100 && !done; i++) {
      const result = prep.step(scope);
      assert.ok(result.visited <= 2);
      done = result.done;
    }
    assert.ok(done);
    assert.deepEqual(readPreparedRecentWorkspace(store.db, "here", 5), recentChatIds(store.db, "here", "home", 5));
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a busy workspace cannot starve another requested home's preparation", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    for (const [key, ws] of [["a", "a"], ["b", "b"], ["busy", "busy"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const changing = store.openThreadOf("ember", "CHAT", "changing", "Changing", null, "a").id;
    const orphan = store.openThread("ember", "CHAT", "orphan", "Orphan", null).id;
    for (let i = 0; i < 400; i++) {
      const key = `busy-${i}`;
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws: "busy" });
    }
    const prep = new RecentChatPreparation(db, 2), home = { ws: "home", home: "home" }, busy = { ws: "busy", home: "home" };
    let ready = false;
    for (let round = 0; round < 100 && !ready; round++) {
      db.prepare("UPDATE threads SET home = ? WHERE id = ?").run(round % 2 === 0 ? "b" : "a", changing);
      assert.ok(prep.step(busy).visited <= 2);
      const result = prep.step(home);
      assert.ok(result.visited <= 2);
      ready = result.done;
    }
    assert.ok(ready, "the home gets turns while the other scope still has old chats to scan");
    assert.deepEqual(readPreparedRecentHome(db, "home", 5), { ids: [orphan], total: 1 });
  } finally { store.close(); }
});
