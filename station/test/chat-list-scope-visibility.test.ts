import assert from "node:assert/strict";
import { test } from "node:test";
import { recentChatIds } from "../src/store/chat-list.ts";
import { scanRecentWorkspaceStep, settleRecentWorkspaceMemberStep, settleRecentWorkspaceSessionStep } from "../src/store/chat-list-scope-build.ts";
import { installRecentScopeJournal, trackRecentScope } from "../src/store/chat-list-scope-journal.ts";
import { settleRecentWorkspaceOrderStep } from "../src/store/chat-list-scope-order.ts";
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

for (const recursive of [false, true]) for (const how of ["insert", "update"] as const) {
  test(`a chat ${how} replacing another keeps workspace visibility exact (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:");
    const db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
      for (const [key, ws] of [["one", "here"], ["two", "elsewhere"]] as const)
        store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
          token: key, createdAt: 1, lastActiveAt: 1, ws });
      const first = store.openThread("ember", "EMBER", "first", "First", null).id;
      const second = store.openThread("ember", "EMBER", "second", "Second", null).id;
      db.prepare("UPDATE threads SET home = ? WHERE id = ?").run("one", first);
      db.prepare("UPDATE threads SET home = ? WHERE id = ?").run("two", second);
      installRecentScopeJournal(db);
      for (const ws of ["here", "elsewhere"]) {
        trackRecentScope(db, { kind: "workspace", workspace: ws });
        while (!scanRecentWorkspaceStep(db, ws, 2).sourceDone) { /* Prepare the original scopes. */ }
      }
      db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1").run();
      if (how === "insert")
        db.prepare("INSERT OR REPLACE INTO threads(id,surface,channel,thread_ts,created_at,home) VALUES (999,'ember','EMBER','first',10,'two')").run();
      else db.prepare("UPDATE OR REPLACE threads SET thread_ts = 'first' WHERE id = ?").run(second);
      assert.equal(readPreparedRecentWorkspace(db, "here", 5), null);
      let done = false;
      for (let i = 0; i < 20 && !done; i++) done = settleRecentScopeVisibilityStep(db, 1).visibilityDone;
      assert.ok(done);
      for (const ws of ["here", "elsewhere"]) {
        while (!settleRecentWorkspaceOrderStep(db, ws, 1).ordersDone) { /* Account for removed rows. */ }
        assert.deepEqual(readPreparedRecentWorkspace(db, ws, 5), recentChatIds(db, ws, "home", 5), ws);
      }
    } finally { store.close(); }
  });
}

for (const recursive of [false, true]) test(`an unrelated new chat does not delay a ready workspace (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["one", "here"], ["two", "elsewhere"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    installRecentScopeJournal(db);
    for (const ws of ["here", "elsewhere"]) {
      trackRecentScope(db, { kind: "workspace", workspace: ws });
      while (!scanRecentWorkspaceStep(db, ws, 2).sourceDone) { /* Prepare empty scopes. */ }
    }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1").run();
    const empty = { ids: [], total: 0 };
    const thread = store.openThread("ember", "EMBER", "new-chat", "New", null).id;
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), empty, "an orphan affects the default home only");
    db.prepare("UPDATE threads SET home = 'two' WHERE id = ?").run(thread);
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), empty, "the named home is in another workspace");
    assert.equal(readPreparedRecentWorkspace(db, "elsewhere", 5), null, "the new home has not yet been added");
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`a new member keeps its workspace pending while an orphan is rebuilt (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "one", createdAt: 1, lastActiveAt: 1, ws: "here" });
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 2).sourceDone) { /* Prepare the empty scope. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1").run();
    const thread = store.openThread("ember", "EMBER", "new-member", "New", null).id;
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [], total: 0 });
    store.joinThread(thread, "one", "ember");
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null);
    assert.equal(settleRecentWorkspaceMemberStep(db, "here", 1).membersDone, true);
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null);
    assert.equal(settleRecentScopeVisibilityStep(db, 1).visited, 1, "the visibility pass temporarily removes the source");
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "the temporary gap cannot become an empty page");
    while (!settleRecentScopeVisibilityStep(db, 1).visibilityDone) { /* Restore current sources. */ }
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), recentChatIds(db, "here", "fallback", 5));
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`a moving home stays pending while its new workspace is rebuilt (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "one", createdAt: 1, lastActiveAt: 1, ws: "here" });
    const thread = store.openThread("ember", "EMBER", "moving-home", "Moving", null).id;
    db.prepare("UPDATE threads SET home = 'one' WHERE id = ?").run(thread);
    installRecentScopeJournal(db);
    for (const ws of ["here", "elsewhere"]) {
      trackRecentScope(db, { kind: "workspace", workspace: ws });
      while (!scanRecentWorkspaceStep(db, ws, 2).sourceDone) { /* Prepare the original scopes. */ }
    }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1").run();
    db.prepare("UPDATE threads SET home = NULL WHERE id = ?").run(thread);
    db.prepare("UPDATE threads SET home = 'one' WHERE id = ?").run(thread);
    db.prepare("UPDATE sessions SET ws = 'elsewhere' WHERE key = 'one'").run();
    for (const ws of ["here", "elsewhere"]) {
      let done = false;
      for (let i = 0; i < 20 && !done; i++) done = settleRecentWorkspaceSessionStep(db, ws, 1).sessionsDone;
      assert.ok(done);
    }
    assert.equal(readPreparedRecentWorkspace(db, "elsewhere", 5), null);
    assert.equal(settleRecentScopeVisibilityStep(db, 1).visited, 1, "the new workspace source is removed for the pass");
    assert.equal(readPreparedRecentWorkspace(db, "elsewhere", 5), null, "the refreshed home hint covers the temporary gap");
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [], total: 0 });
    while (!settleRecentScopeVisibilityStep(db, 1).visibilityDone) { /* Restore the new home source. */ }
    assert.deepEqual(readPreparedRecentWorkspace(db, "elsewhere", 5), recentChatIds(db, "elsewhere", "fallback", 5));
  } finally { store.close(); }
});
