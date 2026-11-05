import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { recentChatIds } from "../src/store/chat-list.ts";
import { installRecentHomeIndex, scanRecentHomeChatsStep, settleRecentHomeChatStep } from "../src/store/chat-list-home-index.ts";
import { installRecentHomeOverlap, readPreparedRecentHome, scanRecentHomeOverlapStep, settleRecentHomeOverlapStep } from "../src/store/chat-list-home-overlap.ts";
import { scanRecentWorkspaceStep } from "../src/store/chat-list-scope-build.ts";
import { trackRecentScope } from "../src/store/chat-list-scope-journal.ts";
import { putRecentScopeSource, removeRecentScopeSource } from "../src/store/chat-list-scope-rows.ts";
import { Store } from "../src/store/store.ts";

for (const recursive of [false, true]) test(`home and workspace overlap is counted once as both change (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["one", "home"], ["two", "elsewhere"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const shared = store.openThread("ember", "EMBER", "shared", "Shared", null).id;
    for (const member of ["one", "two", "missing"]) store.joinThread(shared, member, "ember");
    const named = store.openThread("ember", "EMBER", "named", "Named", null).id;
    db.prepare("UPDATE threads SET home = 'one' WHERE id = ?").run(named);
    store.openThread("ember", "EMBER", "orphan", "Orphan", null);
    installRecentHomeIndex(db);
    for (const ws of ["home", "elsewhere"]) {
      trackRecentScope(db, { kind: "workspace", workspace: ws });
      while (!scanRecentWorkspaceStep(db, ws, 2).sourceDone) { /* Prepare each explicit scope. */ }
    }
    while (!scanRecentHomeChatsStep(db, 2).scanDone) { /* Enqueue default-home chats. */ }
    while (!settleRecentHomeChatStep(db, 2).chatsDone) { /* Prepare the default scope. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1").run();
    installRecentHomeOverlap(db);
    while (!scanRecentHomeOverlapStep(db, 1).scanDone) { /* Schedule old default rows. */ }
    const settle = () => {
      let done = false;
      for (let i = 0; i < 20 && !done; i++) {
        const batch = settleRecentHomeOverlapStep(db, 1);
        assert.ok(batch.visited <= 1);
        done = batch.overlapsDone;
      }
      assert.ok(done);
    };
    const count = (ws: string) => db.prepare("SELECT COALESCE((SELECT total FROM recent_home_overlap_totals WHERE ws = ?), 0) AS n").get(ws)!.n;
    settle();
    assert.equal(count("home"), 1);
    assert.equal(count("elsewhere"), 1);
    const cases = ["home", "elsewhere"].flatMap((home) => [1, 2, 10].map((limit) =>
      ({ home, limit, expected: recentChatIds(db, home, home, limit) })));
    db.setAuthorizer((action, name) => action === constants.SQLITE_READ &&
      ["threads", "thread_state", "entries", "sessions", "thread_sessions"].includes(name ?? "") ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { for (const { home, limit, expected } of cases) assert.deepEqual(readPreparedRecentHome(db, home, limit), expected); }
    finally { db.setAuthorizer(null); }
    removeRecentScopeSource(db, "home", BigInt(shared), "one");
    assert.equal(count("home"), 0);
    putRecentScopeSource(db, "home", BigInt(shared), "one");
    assert.equal(count("home"), 1);
    db.prepare("DELETE FROM thread_sessions WHERE thread = ? AND session = 'missing'").run(shared);
    while (!settleRecentHomeChatStep(db, 2).chatsDone) { /* All remaining members have named workspaces. */ }
    assert.equal(readPreparedRecentHome(db, "home", 5), null, "a pending overlap cannot supply a complete count");
    settle();
    assert.equal(count("home"), 0);
    assert.equal(count("elsewhere"), 0);
    store.joinThread(shared, "missing", "ember");
    while (!settleRecentHomeChatStep(db, 2).chatsDone) { /* The unknown member makes it default again. */ }
    settle();
    for (const ws of ["home", "elsewhere"]) {
      const expected = db.prepare(`SELECT count(*) AS n FROM recent_scope_rows s
        JOIN recent_home_rows h ON h.thread = s.thread WHERE s.ws = ?`).get(ws)!.n;
      assert.equal(count(ws), expected);
      assert.deepEqual(readPreparedRecentHome(db, ws, 5), recentChatIds(db, ws, ws, 5));
    }
  } finally { db.setAuthorizer(null); store.close(); }
});

for (const recursive of [false, true]) test(`home overlap survives new scopes and repeated home changes between batches (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const shared = store.openThread("ember", "EMBER", "shared-many", "Shared", null).id;
    const workspaces = Array.from({ length: 8 }, (_, i) => `w0${i}`);
    for (const ws of [...workspaces, "000-new"]) {
      store.insertSession({ key: ws, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: ws, createdAt: 1, lastActiveAt: 1, ws });
      store.joinThread(shared, ws, "ember");
    }
    store.joinThread(shared, "zzz-missing", "ember");
    installRecentHomeIndex(db);
    while (!scanRecentHomeChatsStep(db, 2).scanDone) { /* Prepare the default chat. */ }
    while (!settleRecentHomeChatStep(db, 2).chatsDone) { /* Its unknown member belongs to home. */ }
    for (const ws of workspaces) {
      trackRecentScope(db, { kind: "workspace", workspace: ws });
      putRecentScopeSource(db, ws, BigInt(shared), ws);
    }
    installRecentHomeOverlap(db);
    while (!scanRecentHomeOverlapStep(db, 2).scanDone) { /* Schedule the existing row. */ }
    assert.equal(settleRecentHomeOverlapStep(db, 2).visited, 2);
    trackRecentScope(db, { kind: "workspace", workspace: "000-new" });
    putRecentScopeSource(db, "000-new", BigInt(shared), "000-new");
    assert.equal(db.prepare("SELECT total FROM recent_home_overlap_totals WHERE ws = '000-new'").get()?.total, 1,
      "a scope added behind the cursor is counted immediately");
    db.prepare("DELETE FROM thread_sessions WHERE thread = ? AND session = 'zzz-missing'").run(shared);
    while (!settleRecentHomeChatStep(db, 2).chatsDone) { /* The chat leaves default home. */ }
    assert.equal(settleRecentHomeOverlapStep(db, 2).visited, 2);
    store.joinThread(shared, "zzz-missing", "ember");
    while (!settleRecentHomeChatStep(db, 2).chatsDone) { /* The chat enters default home again. */ }
    let done = false;
    for (let i = 0; i < 30 && !done; i++) {
      const batch = settleRecentHomeOverlapStep(db, 2);
      assert.ok(batch.visited <= 2);
      done = batch.overlapsDone;
    }
    assert.ok(done);
    for (const ws of [...workspaces, "000-new"]) {
      assert.equal(db.prepare("SELECT total FROM recent_home_overlap_totals WHERE ws = ?").get(ws)?.total, 1, ws);
      assert.ok(db.prepare("SELECT 1 FROM recent_home_overlap_rows WHERE ws = ? AND thread = ?").get(ws, shared));
    }
    assert.equal(db.prepare("SELECT count(*) AS n FROM recent_home_overlap_rows WHERE thread = ?").get(shared)?.n, 9);
  } finally { store.close(); }
});
