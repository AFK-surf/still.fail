import assert from "node:assert/strict";
import { test } from "node:test";
import { recentChatIds } from "../src/store/chat-list.ts";
import { scanRecentWorkspaceStep, settleRecentWorkspaceMemberStep } from "../src/store/chat-list-scope-build.ts";
import { installRecentScopeJournal, trackRecentScope } from "../src/store/chat-list-scope-journal.ts";
import { dispatchRecentScopeOrderStep, settleRecentWorkspaceOrderStep } from "../src/store/chat-list-scope-order.ts";
import { putRecentScopeSource, readPreparedRecentWorkspace, RECENT_SCOPE_ORDER_PENDING } from "../src/store/chat-list-scope-rows.ts";
import { settleRecentScopeVisibilityStep } from "../src/store/chat-list-scope-visibility.ts";
import { Store } from "../src/store/store.ts";

for (const recursive of [false, true]) test(`a changed message updates only its own workspace order (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["one", "here"], ["other", "elsewhere"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','p','hello',?)");
    const make = (name: string, home: string, at: number) => {
      const id = store.openThread("ember", "EMBER", name, name, null).id;
      db.prepare("UPDATE threads SET home = ? WHERE id = ?").run(home, id);
      put.run(id, at);
      return id;
    };
    const first = make("first", "one", 1);
    make("second", "one", 2);
    make("other", "other", 3);
    installRecentScopeJournal(db);
    for (const ws of ["here", "elsewhere"]) {
      trackRecentScope(db, { kind: "workspace", workspace: ws });
      while (!scanRecentWorkspaceStep(db, ws, 2).sourceDone) { /* Read the existing sources. */ }
    }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1").run();
    const other = readPreparedRecentWorkspace(db, "elsewhere", 5);
    db.prepare("UPDATE entries SET at = 30 WHERE thread = ? AND n = 1").run(first);
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null);
    assert.deepEqual(readPreparedRecentWorkspace(db, "elsewhere", 5), other);
    assert.deepEqual(settleRecentWorkspaceOrderStep(db, "here", 2), { ordersDone: true, visited: 1 });
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), recentChatIds(db, "here", "home", 5));
    assert.equal(readPreparedRecentWorkspace(db, "here", 5)?.ids[0], first);
  } finally { store.close(); }
});

test("too many undistributed chats conservatively wait without scanning all of them", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "one", createdAt: 1, lastActiveAt: 1, ws: "here" });
    const thread = store.openThread("ember", "EMBER", "chat", "Chat", null).id;
    db.prepare("UPDATE threads SET home = 'one' WHERE id = ?").run(thread);
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    putRecentScopeSource(db, "here", BigInt(thread), "one");
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    const original = readPreparedRecentWorkspace(db, "here", 5);
    const insert = db.prepare("INSERT INTO recent_scope_order_dispatch(thread) VALUES (?)");
    for (let i = 0; i < 64; i++) insert.run(10_000 + i);
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), original);
    insert.run(10_064);
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "a larger pending set takes the bounded wait path");
    const pending = db.prepare(RECENT_SCOPE_ORDER_PENDING).get("here") as { n: number };
    for (let i = 0; i < 500; i++) insert.run(20_000 + i);
    assert.equal(db.prepare(RECENT_SCOPE_ORDER_PENDING).get("here")!.n, pending.n, "only the first 65 jobs are considered");
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${RECENT_SCOPE_ORDER_PENDING}`).all("here") as { detail: string }[];
    assert.ok(plan.some((row) => row.detail.includes("SEARCH r USING PRIMARY KEY")), JSON.stringify(plan));
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`a shared chat's changing order is distributed without restarting (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const thread = store.openThread("ember", "EMBER", "shared", "Shared", null).id;
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','p','hello',1)").run(thread);
    const workspaces = Array.from({ length: 70 }, (_, i) => `w${String(i).padStart(3, "0")}`);
    for (const ws of [...workspaces, "000-new"]) {
      store.insertSession({ key: ws, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: ws, createdAt: 1, lastActiveAt: 1, ws });
      store.joinThread(thread, ws, "ember");
    }
    store.insertSession({ key: "unrelated", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "unrelated", createdAt: 1, lastActiveAt: 1, ws: "unrelated" });
    const unrelated = store.openThread("ember", "EMBER", "unrelated", "Unrelated", null).id;
    db.prepare("UPDATE threads SET home = 'unrelated' WHERE id = ?").run(unrelated);
    installRecentScopeJournal(db);
    for (const ws of workspaces) {
      trackRecentScope(db, { kind: "workspace", workspace: ws });
      putRecentScopeSource(db, ws, BigInt(thread), ws);
    }
    trackRecentScope(db, { kind: "workspace", workspace: "unrelated" });
    putRecentScopeSource(db, "unrelated", BigInt(unrelated), "unrelated");
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1").run();
    const before = readPreparedRecentWorkspace(db, "unrelated", 5);
    const change = db.prepare("UPDATE entries SET at = ? WHERE thread = ? AND n = 1");
    change.run(10, thread);
    assert.deepEqual(readPreparedRecentWorkspace(db, "unrelated", 5), before,
      "an unrelated workspace remains readable while a shared chat is being distributed");
    assert.equal(readPreparedRecentWorkspace(db, "w069", 5), null,
      "an affected workspace cannot use the old order even before its marker is distributed");
    let done = false, steps = 0;
    while (!done && steps < 12) {
      const batch = dispatchRecentScopeOrderStep(db, 8);
      assert.ok(batch.visited <= 8);
      steps++;
      if (steps === 1) {
        trackRecentScope(db, { kind: "workspace", workspace: "000-new" });
        putRecentScopeSource(db, "000-new", BigInt(thread), "000-new");
        db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = '000-new'").run();
      }
      if (!batch.dispatchDone) {
        assert.equal(settleRecentWorkspaceOrderStep(db, "w000", 2).ordersDone, false,
          "a workspace already visited cannot clear its marker while distribution is running");
        change.run(10 + steps, thread);
      }
      done = batch.dispatchDone;
    }
    assert.ok(done, "repeated changes do not keep moving the distributor back to the beginning");
    assert.deepEqual(readPreparedRecentWorkspace(db, "unrelated", 5), before);
    const latest = db.prepare("SELECT at FROM entries WHERE thread = ? AND n = 1").get(thread)!.at;
    for (const ws of [...workspaces, "000-new"]) {
      assert.equal(readPreparedRecentWorkspace(db, ws, 5), null);
      assert.deepEqual(settleRecentWorkspaceOrderStep(db, ws, 2), { ordersDone: true, visited: 1 });
      assert.deepEqual(readPreparedRecentWorkspace(db, ws, 5), recentChatIds(db, ws, "home", 5));
      assert.equal(db.prepare("SELECT at FROM recent_scope_rows WHERE ws = ? AND thread = ?").get(ws, thread)!.at, latest);
    }
  } finally { store.close(); }
});

test("a deleted shared chat removes its workspace sources in bounded steps", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "shared", "Shared", null).id;
    for (let i = 0; i < 7; i++) {
      const key = `session-${i}`;
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws: "here" });
      store.joinThread(thread, key, "ember");
    }
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 2).sourceDone) { /* Build the shared sources. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [thread], total: 1 });
    db.prepare("DELETE FROM threads WHERE id = ?").run(thread);
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null);
    let done = false, steps = 0;
    while (!done && steps++ < 10) {
      const batch = settleRecentWorkspaceOrderStep(db, "here", 2);
      assert.ok(batch.visited <= 2);
      done = batch.ordersDone;
    }
    assert.ok(done);
    assert.ok(steps >= 4);
    while (!settleRecentScopeVisibilityStep(db, 2).visibilityDone) { /* Settle the deleted chat's visibility. */ }
    while (!settleRecentWorkspaceMemberStep(db, "here", 2).membersDone) { /* Settle cascaded changes, if any. */ }
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), recentChatIds(db, "here", "home", 5));
    assert.equal(readPreparedRecentWorkspace(db, "here", 5)?.total, 0);
  } finally { store.close(); }
});
