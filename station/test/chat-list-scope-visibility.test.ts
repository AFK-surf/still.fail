import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { recentChatIds } from "../src/store/chat-list.ts";
import { scanRecentWorkspaceStep, settleRecentWorkspaceMemberStep, settleRecentWorkspaceSessionStep } from "../src/store/chat-list-scope-build.ts";
import { installRecentScopeJournal, trackRecentScope } from "../src/store/chat-list-scope-journal.ts";
import { settleRecentWorkspaceOrderStep } from "../src/store/chat-list-scope-order.ts";
import { readPreparedRecentWorkspace } from "../src/store/chat-list-scope-rows.ts";
import { settleRecentScopeVisibilityStep } from "../src/store/chat-list-scope-visibility.ts";
import { Store } from "../src/store/store.ts";

for (const recursive of [false, true]) test(`many unrelated shared home changes do not block a small workspace (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["owner", "away"], ["here", "here"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const target = store.openThreadOf("ember", "CHAT", "backlog-target", "Target", null, "here").id;
    const changing: number[] = [];
    for (let i = 0; i < 66; i++) {
      const thread = store.openThreadOf("ember", "CHAT", `backlog-shared-${i}`, "Shared", null, "owner").id;
      for (let j = 0; j < 65; j++) store.joinThread(thread, `unknown-${j}`, "ember");
      changing.push(thread);
    }
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 16).sourceDone) { /* Prepare this workspace. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    const move = db.prepare("UPDATE threads SET home = ? WHERE id = ?");
    for (const thread of changing) move.run(null, thread);
    const check = () => {
      db.setAuthorizer((action, name) => action === constants.SQLITE_READ && name === "thread_sessions"
        ? constants.SQLITE_DENY : constants.SQLITE_OK);
      try { assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 }); }
      finally { db.setAuthorizer(null); }
    };
    check();
    const last = changing.at(-1)!;
    store.joinThread(last, "here", "ember");
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null);
    while (!settleRecentWorkspaceMemberStep(db, "here", 16).membersDone) { /* Settle the new member. */ }
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "a member of a job beyond the first 65 must wait");
    db.prepare("DELETE FROM thread_sessions WHERE thread = ? AND session = 'here'").run(last);
    while (!settleRecentWorkspaceMemberStep(db, "here", 16).membersDone) { /* Settle the departure. */ }
    check();
    move.run("owner", last);
    store.joinThread(last, "here", "ember");
    while (!settleRecentWorkspaceMemberStep(db, "here", 16).membersDone) { /* The named home still hides this member. */ }
    assert.equal(db.prepare("SELECT 1 FROM recent_scope_rows WHERE ws = 'here' AND thread = ?").get(last), undefined);
    move.run(null, last);
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "a hidden member of a later job must also wait");
    db.prepare("DELETE FROM thread_sessions WHERE thread = ? AND session = 'here'").run(last);
    while (!settleRecentWorkspaceMemberStep(db, "here", 16).membersDone) { /* Settle the departure. */ }
    check();
    move.run("here", last);
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "a new named home must wait even before it has a row");
    move.run("owner", last);
    while (!settleRecentWorkspaceMemberStep(db, "here", 16).membersDone) { /* Settle the earlier named home. */ }
    db.prepare("UPDATE sessions SET ws = 'here' WHERE key = 'owner'").run();
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "the home session's move must be recorded");
    while (!settleRecentWorkspaceSessionStep(db, "here", 16).sessionsDone) { /* Account for the moved session. */ }
    const source = db.prepare("SELECT 1 FROM recent_scope_rows WHERE ws = 'here' AND thread = ?");
    assert.ok(source.get(last));
    for (let i = 0; i < 100 && source.get(last); i++) settleRecentScopeVisibilityStep(db, 16);
    assert.equal(source.get(last), undefined, "the pending visibility pass removed its old source");
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "the moved named home remains pending during the pass");
  } finally { db.setAuthorizer(null); store.close(); }
});

test("many pending changes do not make a workspace scan unlimited hidden members", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    for (const [key, ws] of [["owner", "away"], ["here", "here"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const target = store.openThreadOf("ember", "CHAT", "many-hidden-target", "Target", null, "here").id;
    for (let i = 0; i < 65; i++) {
      const thread = store.openThreadOf("ember", "CHAT", `many-hidden-${i}`, "Hidden", null, "owner").id;
      store.joinThread(thread, "here", "ember");
    }
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 16).sourceDone) { /* Prepare the hidden members. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    const insert = db.prepare("INSERT INTO recent_scope_visibility_dirty(thread, revision, home_ws, ambiguous) VALUES (?, 1, NULL, 1)");
    for (let i = 0; i < 65; i++) insert.run(-1 - i);
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "both sides are too large for the bounded check");
    db.prepare("DELETE FROM recent_scope_visibility_dirty WHERE thread = -65").run();
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 });
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`many named home moves do not block an unrelated workspace (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["a", "a"], ["b", "b"], ["here", "here"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const target = store.openThreadOf("ember", "CHAT", "target-named-moves", "Target", null, "here").id;
    const moving: number[] = [];
    for (let i = 0; i < 70; i++) moving.push(store.openThreadOf("ember", "CHAT", `moving-${i}`, "Moving", null, "a").id);
    installRecentScopeJournal(db);
    for (const ws of ["a", "b", "here"]) {
      trackRecentScope(db, { kind: "workspace", workspace: ws });
      while (!scanRecentWorkspaceStep(db, ws, 8).sourceDone) { /* Prepare the existing scopes. */ }
    }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1").run();
    const move = db.prepare("UPDATE threads SET home = 'b' WHERE id = ?");
    for (const id of moving) move.run(id);
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 },
      "unrelated named home changes need no global wait");
    for (const ws of ["a", "b"]) {
      assert.equal(readPreparedRecentWorkspace(db, ws, 5), null, "a changed workspace must wait for its own updates");
      while (!settleRecentWorkspaceMemberStep(db, ws, 8).membersDone) { /* Account for its changed homes. */ }
      assert.deepEqual(readPreparedRecentWorkspace(db, ws, 5), recentChatIds(db, ws, "home", 5));
    }
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`a home becoming shared does not block a workspace without its members (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["a", "a"], ["b", "b"], ["here", "here"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const target = store.openThreadOf("ember", "CHAT", "target-shared", "Target", null, "here").id;
    const changing = store.openThreadOf("ember", "CHAT", "changing-shared", "Changing", null, "a").id;
    store.joinThread(changing, "b", "ember");
    installRecentScopeJournal(db);
    for (const ws of ["a", "b", "here"]) {
      trackRecentScope(db, { kind: "workspace", workspace: ws });
      while (!scanRecentWorkspaceStep(db, ws, 2).sourceDone) { /* Prepare the existing scopes. */ }
    }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1").run();
    db.prepare("UPDATE threads SET home = NULL WHERE id = ?").run(changing);
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 },
      "its known members cannot make an unrelated workspace wait");
    for (const ws of ["a", "b"]) {
      assert.equal(readPreparedRecentWorkspace(db, ws, 5), null);
      while (!settleRecentWorkspaceMemberStep(db, ws, 2).membersDone) { /* Account for its changed home. */ }
      assert.deepEqual(readPreparedRecentWorkspace(db, ws, 5), recentChatIds(db, ws, "home", 5));
    }
    db.prepare("UPDATE threads SET home = 'a' WHERE id = ?").run(changing);
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 });
    for (const ws of ["a", "b"]) {
      assert.equal(readPreparedRecentWorkspace(db, ws, 5), null);
      while (!settleRecentWorkspaceMemberStep(db, ws, 2).membersDone) { /* Account for the named home. */ }
      assert.deepEqual(readPreparedRecentWorkspace(db, ws, 5), recentChatIds(db, ws, "home", 5));
    }
    db.prepare("UPDATE threads SET home = NULL WHERE id = ?").run(changing);
    db.prepare("UPDATE threads SET home = 'a' WHERE id = ?").run(changing);
    db.prepare("UPDATE threads SET home = NULL WHERE id = ?").run(changing);
    for (const ws of ["a", "b"]) {
      assert.equal(readPreparedRecentWorkspace(db, ws, 5), null);
      while (!settleRecentWorkspaceMemberStep(db, ws, 1).membersDone) { /* Use the latest home and members. */ }
      assert.deepEqual(readPreparedRecentWorkspace(db, ws, 5), recentChatIds(db, ws, "home", 5));
    }
  } finally { store.close(); }
});

for (const count of [64, 65]) test(`a home with ${count} members remains exact at the direct-work boundary`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    for (const [key, ws] of [["owner", "owner"], ["here", "here"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const changing = store.openThreadOf("ember", "CHAT", `boundary-${count}`, "Changing", null, "owner").id;
    const target = store.openThreadOf("ember", "CHAT", `here-${count}`, "Here", null, "here").id;
    for (let i = 0; i < count; i++) {
      const key = `member-${String(i).padStart(2, "0")}`;
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws: key });
      store.joinThread(changing, key, "ember");
    }
    installRecentScopeJournal(db);
    const scopes = ["owner", "member-00", "member-63", "here"];
    for (const ws of scopes) {
      trackRecentScope(db, { kind: "workspace", workspace: ws });
      while (!scanRecentWorkspaceStep(db, ws, 8).sourceDone) { /* Prepare the existing scopes. */ }
    }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1").run();
    db.prepare("UPDATE threads SET home = NULL WHERE id = ?").run(changing);
    if (count === 64) {
      assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 });
      for (const ws of scopes) while (!settleRecentWorkspaceMemberStep(db, ws, 8).membersDone) { /* Reconcile small changes. */ }
    } else {
      assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 },
        "a large shared change cannot block a workspace without any of its members");
      assert.equal(readPreparedRecentWorkspace(db, "member-00", 5), null,
        "a workspace gaining the shared chat must wait for bounded distribution");
      let done = false;
      for (let i = 0; i < 30 && !done; i++) {
        const result = settleRecentScopeVisibilityStep(db, 8);
        assert.ok(result.visited <= 8);
        done = result.visibilityDone;
      }
      assert.ok(done);
    }
    for (const ws of scopes) assert.deepEqual(readPreparedRecentWorkspace(db, ws, 5), recentChatIds(db, ws, "home", 5));
  } finally { store.close(); }
});

for (const count of [64, 65]) test(`a workspace with ${count} sessions checks a large shared change within its read budget`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    store.insertSession({ key: "owner", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "owner", createdAt: 1, lastActiveAt: 1, ws: "away" });
    for (let i = 0; i < count; i++) {
      const key = `here-${String(i).padStart(2, "0")}`;
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws: "here" });
    }
    const target = store.openThreadOf("ember", "CHAT", `here-${count}`, "Here", null, "here-00").id;
    const shared = store.openThreadOf("ember", "CHAT", `large-${count}`, "Large", null, "owner").id;
    for (let i = 0; i < 65; i++) store.joinThread(shared, `unknown-${i}`, "ember");
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 32).sourceDone) { /* Prepare the old sessions. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    db.prepare("UPDATE threads SET home = NULL WHERE id = ?").run(shared);
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 });
    store.joinThread(shared, "here-00", "ember");
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "a new member must keep the workspace pending");
    while (!settleRecentWorkspaceMemberStep(db, "here", 8).membersDone) { /* Reconcile the new member. */ }
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "the global visibility pass is still in progress");
    while (!settleRecentScopeVisibilityStep(db, 8).visibilityDone) { /* Finish the bounded pass. */ }
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), recentChatIds(db, "here", "home", 5));
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`a session moving while a shared change waits updates its workspace membership (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["owner", "away"], ["moving", "here"], ["survivor", "here"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const target = store.openThreadOf("ember", "CHAT", "target-moving-session", "Target", null, "survivor").id;
    const shared = store.openThreadOf("ember", "CHAT", "shared-moving-session", "Shared", null, "owner").id;
    store.joinThread(shared, "moving", "ember");
    for (let i = 0; i < 64; i++) store.joinThread(shared, `unknown-${i}`, "ember");
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 8).sourceDone) { /* Prepare the old sessions. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    const move = db.prepare("UPDATE sessions SET ws = ? WHERE key = 'moving'");
    const settle = () => {
      let done = false;
      for (let i = 0; i < 100 && !done; i++) done = settleRecentWorkspaceSessionStep(db, "here", 2).sessionsDone;
      assert.ok(done);
    };
    move.run("away");
    settle();
    db.prepare("UPDATE threads SET home = NULL WHERE id = ?").run(shared);
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 });
    move.run("here");
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null);
    settle();
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "the returned member is affected by the pending change");
    move.run("away");
    settle();
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 },
      "the departed member no longer makes this workspace wait");
    while (!settleRecentScopeVisibilityStep(db, 8).visibilityDone) { /* Finish the shared pass. */ }
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), recentChatIds(db, "here", "home", 5));
  } finally { store.close(); }
});

test("checking an unrelated large shared chat does not read historical memberships", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    store.insertSession({ key: "owner", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "owner", createdAt: 1, lastActiveAt: 1, ws: "away" });
    for (let i = 0; i < 64; i++) {
      const key = `here-${String(i).padStart(2, "0")}`;
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws: "here" });
    }
    const target = store.openThreadOf("ember", "CHAT", "bounded-target", "Target", null, "here-00").id;
    const shared = store.openThreadOf("ember", "CHAT", "bounded-shared", "Shared", null, "owner").id;
    for (let i = 0; i < 65; i++) store.joinThread(shared, `unknown-${i}`, "ember");
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 64).sourceDone) { /* Prepare the workspace. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    db.prepare("UPDATE threads SET home = NULL WHERE id = ?").run(shared);
    const check = () => {
      db.setAuthorizer((action, name) => action === constants.SQLITE_READ && name === "thread_sessions"
        ? constants.SQLITE_DENY : constants.SQLITE_OK);
      try { assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 }); }
      finally { db.setAuthorizer(null); }
    };
    check();
    for (let i = 65; i < 1000; i++) store.joinThread(shared, `unknown-${i}`, "ember");
    check();
  } finally { db.setAuthorizer(null); store.close(); }
});

for (const recursive of [false, true]) test(`a named chat's members are tracked before it becomes shared (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["owner", "away"], ["here", "here"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const target = store.openThreadOf("ember", "CHAT", "candidate-target", "Target", null, "here").id;
    const shared = store.openThreadOf("ember", "CHAT", "candidate-shared", "Shared", null, "owner").id;
    for (let i = 0; i < 65; i++) store.joinThread(shared, `unknown-${i}`, "ember");
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 8).sourceDone) { /* Prepare the workspace. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    store.joinThread(shared, "here", "ember");
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 },
      "joining another named home does not change this workspace's visible chats");
    db.prepare("UPDATE threads SET home = NULL WHERE id = ?").run(shared);
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "the newly shared membership must not be missed");
    db.prepare("DELETE FROM thread_sessions WHERE thread = ? AND session = 'here'").run(shared);
    while (!settleRecentWorkspaceMemberStep(db, "here", 8).membersDone) { /* Reconcile the departure. */ }
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 },
      "the departed member no longer affects the pending visibility change");
  } finally { store.close(); }
});

for (const recursive of [false, true]) for (const operation of ["insert", "update"]) test(`a ${operation} replacing a hidden member is accounted before a later shared change (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["owner", "away"], ["here", "here"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const target = store.openThreadOf("ember", "CHAT", "replace-candidate-target", "Target", null, "here").id;
    const shared = store.openThreadOf("ember", "CHAT", "replace-candidate-shared", "Shared", null, "owner").id;
    const other = store.openThreadOf("ember", "CHAT", "replace-candidate-other", "Other", null, "owner").id;
    store.joinThread(shared, "here", "ember");
    if (operation === "update") store.joinThread(other, "owner", "ember");
    for (let i = 0; i < 65; i++) store.joinThread(shared, `unknown-${i}`, "ember");
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 8).sourceDone) { /* Prepare the old member. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    const rowid = (db.prepare("SELECT rowid FROM thread_sessions WHERE thread = ? AND session = 'here'").get(shared) as { rowid: number }).rowid;
    if (operation === "insert") db.prepare("INSERT OR REPLACE INTO thread_sessions(rowid,thread,session,connect,joined_at) VALUES (?,?, 'owner','ember',1)")
      .run(rowid, other);
    else db.prepare("UPDATE OR REPLACE thread_sessions SET rowid = ? WHERE thread = ? AND session = 'owner'").run(rowid, other);
    while (!settleRecentWorkspaceMemberStep(db, "here", 8).membersDone) { /* Reconcile a displaced row. */ }
    db.prepare("UPDATE threads SET home = NULL WHERE id = ?").run(shared);
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 },
      "a replaced member must not make the unrelated workspace wait");
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`a frequently moving chat does not prevent another workspace from settling (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["a", "a"], ["b", "b"], ["here", "here"], ["away", "away"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const hot = store.openThread("ember", "CHAT", "hot", "Hot", null).id;
    const target = store.openThread("ember", "CHAT", "target", "Target", null).id;
    const move = db.prepare("UPDATE threads SET home = ? WHERE id = ?");
    move.run("a", hot);
    move.run("here", target);
    for (const id of [hot, target]) for (let i = 0; i < 65; i++) store.joinThread(id, `unknown-${i}`, "ember");
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 1).sourceDone) { /* Prepare the target workspace. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 });
    move.run(null, target);
    move.run("away", target);
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null);
    let page = null;
    for (let i = 0; i < 16 && page === null; i++) {
      move.run(null, hot);
      move.run(i % 2 === 0 ? "b" : "a", hot);
      assert.ok(settleRecentScopeVisibilityStep(db, 1).visited <= 1);
      page = readPreparedRecentWorkspace(db, "here", 5);
    }
    assert.deepEqual(page, recentChatIds(db, "here", "home", 5),
      "work on the unrelated changing chat must not indefinitely postpone this workspace");
  } finally { store.close(); }
});

test("visibility work keeps its turn across rollback and reopening", () => {
  const dir = mkdtempSync(join(tmpdir(), "recent-visibility-turn-"));
  const path = join(dir, "station.db");
  let store = Store.open(path);
  try {
    let db = store.db;
    for (const [key, ws] of [["a", "a"], ["b", "b"], ["here", "here"], ["away", "away"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const hot = store.openThread("ember", "CHAT", "hot", "Hot", null).id;
    const target = store.openThread("ember", "CHAT", "target", "Target", null).id;
    const move = db.prepare("UPDATE threads SET home = ? WHERE id = ?");
    move.run("a", hot);
    move.run("here", target);
    for (const id of [hot, target]) for (let i = 0; i < 65; i++) store.joinThread(id, `unknown-${i}`, "ember");
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 1).sourceDone) { /* Prepare the workspace. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    move.run(null, hot);
    move.run("b", hot);
    move.run(null, target);
    move.run("away", target);
    db.setAuthorizer((action, name) => action === constants.SQLITE_UPDATE && name === "recent_scope_visibility_dirty"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.throws(() => settleRecentScopeVisibilityStep(db, 1)); }
    finally { db.setAuthorizer(null); }
    settleRecentScopeVisibilityStep(db, 1);
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "the failed turn was rolled back");
    store.close();
    store = Store.open(path);
    db = store.db;
    settleRecentScopeVisibilityStep(db, 1);
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), recentChatIds(db, "here", "home", 5),
      "the next chat gets a turn after the worker reopens its database");
  } finally {
    store.db.setAuthorizer(null);
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

for (const recursive of [false, true]) test(`newer chats cannot continually pass an older pending workspace (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["a", "a"], ["b", "b"], ["here", "here"], ["away", "away"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const target = store.openThread("ember", "CHAT", "target", "Target", null).id;
    const first = store.openThread("ember", "CHAT", "first", "First", null).id;
    const move = db.prepare("UPDATE threads SET home = ? WHERE id = ?");
    move.run("here", target);
    move.run("a", first);
    for (const id of [target, first]) for (let i = 0; i < 65; i++) store.joinThread(id, `unknown-${i}`, "ember");
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 1).sourceDone) { /* Prepare the workspace. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    move.run(null, first);
    move.run("b", first);
    settleRecentScopeVisibilityStep(db, 1);
    move.run(null, target);
    move.run("away", target);
    let page = null;
    for (let i = 0; i < 16 && page === null; i++) {
      const added = store.openThread("ember", "CHAT", `new-${i}`, "New", null).id;
      for (let j = 0; j < 65; j++) store.joinThread(added, `unknown-${j}`, "ember");
      move.run("a", added);
      assert.ok(settleRecentScopeVisibilityStep(db, 1).visited <= 1);
      page = readPreparedRecentWorkspace(db, "here", 5);
    }
    assert.deepEqual(page, recentChatIds(db, "here", "home", 5),
      "an older change must get a turn even while unrelated newer chats arrive");
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`many unrelated new orphan chats do not make a workspace wait (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    store.insertSession({ key: "here", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "here", createdAt: 1, lastActiveAt: 1, ws: "here" });
    const target = store.openThreadOf("ember", "CHAT", "target", "Target", null, "here").id;
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 2).sourceDone) { /* Prepare the workspace. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    for (let i = 0; i < 100; i++) store.openThread("ember", "CHAT", `orphan-${i}`, "Orphan", null);
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 },
      "unrelated new orphans must not accumulate work that blocks this workspace");
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`many new chats in an untracked workspace do not make another workspace wait (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["here", "here"], ["away", "away"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const target = store.openThreadOf("ember", "CHAT", "target", "Target", null, "here").id;
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 2).sourceDone) { /* Prepare the workspace. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    for (let i = 0; i < 100; i++) store.openThreadOf("ember", "CHAT", `away-${i}`, "Away", null, "away");
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [target], total: 1 },
      "a scope that has never been requested must not accumulate work for this workspace");
    trackRecentScope(db, { kind: "workspace", workspace: "away" });
    while (!scanRecentWorkspaceStep(db, "away", 20).sourceDone) { /* Its own first read scans its sessions. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'away'").run();
    assert.deepEqual(readPreparedRecentWorkspace(db, "away", 5), recentChatIds(db, "away", "home", 5));
    store.openThreadOf("ember", "CHAT", "new-here", "New here", null, "here");
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "a new chat in a prepared scope must be accounted");
    while (!settleRecentScopeVisibilityStep(db, 2).visibilityDone) { /* Account the new named home. */ }
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), recentChatIds(db, "here", "home", 5));
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`a previously unknown home becoming known is added to its workspace (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 2).sourceDone) { /* Prepare the empty scope. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    const chat = store.openThreadOf("ember", "CHAT", "unknown", "Unknown", null, "later").id;
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [], total: 0 });
    store.insertSession({ key: "later", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "later", createdAt: 1, lastActiveAt: 1, ws: "here" });
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null);
    while (!settleRecentWorkspaceSessionStep(db, "here", 2).sessionsDone) { /* Find the newly known home. */ }
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [chat], total: 1 });
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`a new chat with an existing member is accounted for its workspace (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    store.insertSession({ key: "here", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "here", createdAt: 1, lastActiveAt: 1, ws: "here" });
    db.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES (999,'here','ember',1)").run();
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 2).sourceDone) { /* The referenced chat is not there yet. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    db.prepare("INSERT INTO threads(id,surface,channel,thread_ts,created_at) VALUES (999,'ember','CHAT','late',1)").run();
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "existing members still require a visibility pass");
    while (!settleRecentScopeVisibilityStep(db, 2).visibilityDone) { /* Account the existing membership. */ }
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), recentChatIds(db, "here", "home", 5));
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [999], total: 1 });
  } finally { store.close(); }
});

for (const recursive of [false, true]) for (const home of ["two", null]) {
  test(`a changed chat home cannot leave a workspace page stale (home ${home}, recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:");
    const db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
      for (const [key, ws] of [["one", "here"], ["two", "elsewhere"]] as const)
        store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
          token: key, createdAt: 1, lastActiveAt: 1, ws });
      const thread = store.openThread("ember", "CHAT", "shared", "Shared", null).id;
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
      for (const ws of ["here", "elsewhere"]) {
        while (!settleRecentWorkspaceMemberStep(db, ws, 2).membersDone) { /* Account for changed named homes. */ }
        assert.deepEqual(readPreparedRecentWorkspace(db, ws, 5), recentChatIds(db, ws, "home", 5));
      }
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
    const thread = store.openThread("ember", "CHAT", "shared", "Shared", null).id;
    db.prepare("UPDATE threads SET home = 'm01' WHERE id = ?").run(thread);
    for (const key of keys.slice(1)) store.joinThread(thread, key, "ember");
    for (let i = 0; i < 65; i++) store.joinThread(thread, `unknown-${i}`, "ember");
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
    for (let i = 0; i < 80 && !done; i++) {
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
      const first = store.openThread("ember", "CHAT", "first", "First", null).id;
      const second = store.openThread("ember", "CHAT", "second", "Second", null).id;
      db.prepare("UPDATE threads SET home = ? WHERE id = ?").run("one", first);
      db.prepare("UPDATE threads SET home = ? WHERE id = ?").run("two", second);
      installRecentScopeJournal(db);
      for (const ws of ["here", "elsewhere"]) {
        trackRecentScope(db, { kind: "workspace", workspace: ws });
        while (!scanRecentWorkspaceStep(db, ws, 2).sourceDone) { /* Prepare the original scopes. */ }
      }
      db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1").run();
      if (how === "insert")
        db.prepare("INSERT OR REPLACE INTO threads(id,surface,channel,thread_ts,created_at,home) VALUES (999,'ember','CHAT','first',10,'two')").run();
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
    const thread = store.openThread("ember", "CHAT", "new-chat", "New", null).id;
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
    const thread = store.openThread("ember", "CHAT", "new-member", "New", null).id;
    db.prepare("UPDATE threads SET home = 'missing' WHERE id = ?").run(thread);
    db.prepare("UPDATE threads SET home = NULL WHERE id = ?").run(thread);
    db.prepare("INSERT OR REPLACE INTO threads(id,surface,channel,thread_ts,created_at,home) VALUES (?,'ember','CHAT','new-member',1,NULL)").run(thread);
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
    const thread = store.openThread("ember", "CHAT", "moving-home", "Moving", null).id;
    db.prepare("UPDATE threads SET home = 'one' WHERE id = ?").run(thread);
    for (let i = 0; i < 65; i++) store.joinThread(thread, `unknown-${i}`, "ember");
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
