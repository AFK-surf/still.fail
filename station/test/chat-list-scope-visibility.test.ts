import assert from "node:assert/strict";
import { test } from "node:test";
import { recentChatIds } from "../src/store/chat-list.ts";
import { scanRecentWorkspaceStep, settleRecentWorkspaceMemberStep } from "../src/store/chat-list-scope-build.ts";
import { installRecentScopeJournal, trackRecentScope } from "../src/store/chat-list-scope-journal.ts";
import { readPreparedRecentWorkspace } from "../src/store/chat-list-scope-rows.ts";
import { settleRecentScopeVisibilityStep } from "../src/store/chat-list-scope-visibility.ts";
import { Store } from "../src/store/store.ts";

for (const recursive of [false, true]) for (const home of ["two", null]) {
  test(`a changed chat home cannot leave a workspace page stale (home ${home}, recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:");
    const db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
      for (const [key, ws] of [["one", "here"], ["two", "elsewhere"]] as const)
        store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
          token: key, createdAt: 1, lastActiveAt: 1, ws });
      const thread = store.openThread("ember", "EMBER", "shared", "Shared", null).id;
      db.prepare("UPDATE threads SET home = 'one' WHERE id = ?").run(thread);
      store.joinThread(thread, "two", "ember");
      installRecentScopeJournal(db);
      for (const ws of ["here", "elsewhere"]) {
        trackRecentScope(db, { kind: "workspace", workspace: ws });
        while (!scanRecentWorkspaceStep(db, ws, 2).sourceDone) { /* Prepare both scopes. */ }
      }
      db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1").run();
      assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [thread], total: 1 });
      assert.deepEqual(readPreparedRecentWorkspace(db, "elsewhere", 5), { ids: [], total: 0 });
      db.prepare("UPDATE threads SET home = ? WHERE id = ?").run(home, thread);
      assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "the old home has not yet been removed");
      assert.equal(readPreparedRecentWorkspace(db, "elsewhere", 5), null, "the new scope has not yet been added");
      let done = false;
      for (let i = 0; i < 10 && !done; i++) {
        const batch = settleRecentScopeVisibilityStep(db, 1);
        assert.ok(batch.visited <= 1);
        done = batch.visibilityDone;
      }
      assert.ok(done);
      for (const ws of ["here", "elsewhere"])
        assert.deepEqual(readPreparedRecentWorkspace(db, ws, 5), recentChatIds(db, ws, "home", 5));
    } finally { store.close(); }
  });
}

for (const recursive of [false, true]) test(`a home and its members can change during visibility preparation (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const keys = Array.from({ length: 7 }, (_, i) => `m0${i}`);
    for (const key of keys) store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/work", token: key, createdAt: 1, lastActiveAt: 1, ws: key });
    const thread = store.openThread("ember", "EMBER", "shared", "Shared", null).id;
    db.prepare("UPDATE threads SET home = 'm01' WHERE id = ?").run(thread);
    for (const key of keys.slice(1)) store.joinThread(thread, key, "ember");
    installRecentScopeJournal(db);
    for (const ws of keys) {
      trackRecentScope(db, { kind: "workspace", workspace: ws });
      while (!scanRecentWorkspaceStep(db, ws, 2).sourceDone) { /* Prepare the original scope. */ }
    }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1").run();
    db.prepare("UPDATE threads SET home = NULL WHERE id = ?").run(thread);
    assert.equal(settleRecentScopeVisibilityStep(db, 2).visited, 1, "remove the old home's source");
    assert.equal(settleRecentScopeVisibilityStep(db, 2).visited, 2, "start adding member sources");
    db.prepare("UPDATE threads SET home = 'm06' WHERE id = ?").run(thread);
    db.prepare("UPDATE threads SET home = NULL WHERE id = ?").run(thread);
    assert.equal(settleRecentScopeVisibilityStep(db, 2).visited, 2, "the newer home starts another bounded pass");
    settleRecentScopeVisibilityStep(db, 2);
    settleRecentScopeVisibilityStep(db, 2);
    store.joinThread(thread, "m00", "ember");
    db.prepare("DELETE FROM thread_sessions WHERE thread = ? AND session = 'm01'").run(thread);
    let done = false;
    for (let i = 0; i < 20 && !done; i++) {
      const batch = settleRecentScopeVisibilityStep(db, 2);
      assert.ok(batch.visited <= 2);
      done = batch.visibilityDone;
    }
    assert.ok(done);
    for (const ws of keys) {
      while (!settleRecentWorkspaceMemberStep(db, ws, 2).membersDone) { /* Reconcile changed members. */ }
      assert.deepEqual(readPreparedRecentWorkspace(db, ws, 5), recentChatIds(db, ws, "home", 5), ws);
    }
  } finally { store.close(); }
});
