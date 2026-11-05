import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants, DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { recentChatIds } from "../src/store/chat-list.ts";
import { installRecentHomeIndex, scanRecentHomeChatsStep, settleRecentHomeChatStep } from "../src/store/chat-list-home-index.ts";
import { installRecentHomeOverlap, readPreparedRecentHome, scanRecentHomeOverlapStep, settleRecentHomeOverlapStep } from "../src/store/chat-list-home-overlap.ts";
import { scanRecentWorkspaceStep, settleRecentWorkspaceMemberStep } from "../src/store/chat-list-scope-build.ts";
import { trackRecentScope } from "../src/store/chat-list-scope-journal.ts";
import { settleRecentWorkspaceOrderStep } from "../src/store/chat-list-scope-order.ts";
import { putRecentScopeSource, removeRecentScopeSource } from "../src/store/chat-list-scope-rows.ts";
import { settleRecentScopeVisibilityStep } from "../src/store/chat-list-scope-visibility.ts";
import { Store } from "../src/store/store.ts";

for (const recursive of [false, true]) test(`home and workspace overlap is counted once as both change (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["one", "home"], ["two", "elsewhere"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const shared = store.openThread("ember", "CHAT", "shared", "Shared", null).id;
    for (const member of ["one", "two", "missing"]) store.joinThread(shared, member, "ember");
    const named = store.openThread("ember", "CHAT", "named", "Named", null).id;
    db.prepare("UPDATE threads SET home = 'one' WHERE id = ?").run(named);
    store.openThread("ember", "CHAT", "orphan", "Orphan", null);
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

test("a home union reads its rows and overlap count on one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "recent-home-snapshot-"));
  const path = join(dir, "station.db"), store = Store.open(path), db = store.db;
  let reader: DatabaseSync | undefined;
  try {
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "one", createdAt: 1, lastActiveAt: 1, ws: "home" });
    const old = store.openThread("ember", "CHAT", "old", "Old", null).id;
    store.joinThread(old, "one", "ember");
    store.joinThread(old, "missing", "ember");
    installRecentHomeIndex(db);
    trackRecentScope(db, { kind: "workspace", workspace: "home" });
    while (!scanRecentWorkspaceStep(db, "home", 2).sourceDone) { /* Prepare the workspace. */ }
    while (!scanRecentHomeChatsStep(db, 2).scanDone) { /* Prepare the default range. */ }
    while (!settleRecentHomeChatStep(db, 2).chatsDone) { /* Add the default rows. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'home'").run();
    installRecentHomeOverlap(db);
    while (!scanRecentHomeOverlapStep(db, 2).scanDone) { /* Schedule old overlaps. */ }
    while (!settleRecentHomeOverlapStep(db, 2).overlapsDone) { /* Count the intersection. */ }
    assert.deepEqual(readPreparedRecentHome(db, "home", 5), { ids: [old], total: 1 });
    reader = new DatabaseSync(path, { readOnly: true });
    let added: number | null = null;
    const observed = new Proxy(reader, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const statement = target.prepare(sql);
          if (sql !== "SELECT scan_done FROM recent_home_overlap_meta WHERE id = 1") return statement;
          return new Proxy(statement, {
            get(row, member) {
              if (member === "get") return (...args: Parameters<typeof row.get>) => {
                const result = row.get(...args);
                if (added === null) {
                  added = store.openThread("ember", "CHAT", "added", "Added", null).id;
                  store.joinThread(added, "one", "ember");
                  store.joinThread(added, "missing", "ember");
                  db.prepare("UPDATE threads SET created_at = ? WHERE id = ?").run(9_999_999_999_999, added);
                  for (let i = 0; i < 50; i++) {
                    settleRecentScopeVisibilityStep(db, 2);
                    settleRecentWorkspaceMemberStep(db, "home", 2);
                    settleRecentWorkspaceOrderStep(db, "home", 2);
                    settleRecentHomeChatStep(db, 2);
                    settleRecentHomeOverlapStep(db, 2);
                    if (readPreparedRecentHome(db, "home", 5) !== null) break;
                  }
                  assert.deepEqual(readPreparedRecentHome(db, "home", 5), { ids: [added, old], total: 2 });
                }
                return result;
              };
              const value = Reflect.get(row, member, row);
              return typeof value === "function" ? value.bind(row) : value;
            },
          });
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    assert.deepEqual(readPreparedRecentHome(observed, "home", 5), { ids: [old], total: 1 });
    assert.ok(added !== null);
    assert.deepEqual(readPreparedRecentHome(reader, "home", 5), { ids: [added, old], total: 2 });
  } finally {
    reader?.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

for (const recursive of [false, true]) test(`home overlap survives new scopes and repeated home changes between batches (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const shared = store.openThread("ember", "CHAT", "shared-many", "Shared", null).id;
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
