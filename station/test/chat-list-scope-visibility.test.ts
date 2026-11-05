import assert from "node:assert/strict";
import { test } from "node:test";
import { scanRecentWorkspaceStep } from "../src/store/chat-list-scope-build.ts";
import { installRecentScopeJournal, trackRecentScope } from "../src/store/chat-list-scope-journal.ts";
import { readPreparedRecentWorkspace } from "../src/store/chat-list-scope-rows.ts";
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
    } finally { store.close(); }
  });
}
