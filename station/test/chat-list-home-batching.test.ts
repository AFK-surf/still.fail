import assert from "node:assert/strict";
import { test } from "node:test";
import { recentChatIds } from "../src/store/chat-list.ts";
import { installRecentHomeIndex, scanRecentHomeChatsStep, settleRecentHomeChatStep } from "../src/store/chat-list-home-index.ts";
import { installRecentHomeOverlap, readPreparedRecentHome, scanRecentHomeOverlapStep, settleRecentHomeOverlapStep } from "../src/store/chat-list-home-overlap.ts";
import { scanRecentWorkspaceStep } from "../src/store/chat-list-scope-build.ts";
import { trackRecentScope } from "../src/store/chat-list-scope-journal.ts";
import { Store } from "../src/store/store.ts";

test("one bounded home batch accounts for multiple ordinary old chats", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    store.insertSession({ key: "away", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "away", createdAt: 1, lastActiveAt: 1, ws: "away" });
    for (let i = 0; i < 20; i++) {
      store.openThreadOf("ember", "CHAT", `away-${i}`, "Away", null, "away");
      store.openThread("ember", "CHAT", `orphan-${i}`, "Orphan", null);
    }
    installRecentHomeIndex(db);
    while (!scanRecentHomeChatsStep(db, 64).scanDone) { /* Enqueue the old chats. */ }
    const batch = settleRecentHomeChatStep(db, 64);
    assert.ok(batch.visited <= 64);
    assert.equal(batch.chatsDone, true, "forty simple chats fit in one batch");
    assert.equal(db.prepare("SELECT total FROM recent_home_meta").get()?.total, 20);
  } finally { store.close(); }
});

test("one bounded overlap batch accounts for multiple ordinary shared chats", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    store.insertSession({ key: "here", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "here", createdAt: 1, lastActiveAt: 1, ws: "here" });
    for (let i = 0; i < 20; i++) {
      const id = store.openThread("ember", "CHAT", `shared-${i}`, "Shared", null).id;
      store.joinThread(id, "here", "ember");
      store.joinThread(id, "missing", "ember");
    }
    installRecentHomeIndex(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 64).sourceDone) { /* Prepare the workspace rows. */ }
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    while (!scanRecentHomeChatsStep(db, 64).scanDone) { /* Enqueue the default chats. */ }
    while (!settleRecentHomeChatStep(db, 64).chatsDone) { /* Prepare the default rows. */ }
    installRecentHomeOverlap(db);
    while (!scanRecentHomeOverlapStep(db, 64).scanDone) { /* Enqueue existing overlaps. */ }
    const batch = settleRecentHomeOverlapStep(db, 64);
    assert.ok(batch.visited <= 64);
    assert.equal(batch.overlapsDone, true, "twenty single-workspace overlaps fit in one batch");
    assert.equal(db.prepare("SELECT total FROM recent_home_overlap_totals WHERE ws = 'here'").get()?.total, 20);
    assert.deepEqual(readPreparedRecentHome(db, "here", 5), recentChatIds(db, "here", "here", 5));
  } finally { store.close(); }
});

test("a failure on a later home chat rolls back the entire batch", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    store.openThread("ember", "CHAT", "first", "First", null);
    const second = store.openThread("ember", "CHAT", "second", "Second", null).id;
    installRecentHomeIndex(db);
    while (!scanRecentHomeChatsStep(db, 64).scanDone) { /* Enqueue both chats. */ }
    db.exec(`CREATE TRIGGER fail_later_home BEFORE INSERT ON recent_home_rows WHEN NEW.thread = ${second}
      BEGIN SELECT RAISE(ABORT, 'test failure'); END`);
    assert.throws(() => settleRecentHomeChatStep(db, 64), /test failure/);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM recent_home_rows").get()?.n, 0);
    assert.equal(db.prepare("SELECT total FROM recent_home_meta").get()?.total, 0);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM recent_home_dirty").get()?.n, 2);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM recent_home_work").get()?.n, 0);
    db.exec("DROP TRIGGER fail_later_home");
    assert.equal(settleRecentHomeChatStep(db, 64).chatsDone, true);
    assert.equal(db.prepare("SELECT total FROM recent_home_meta").get()?.total, 2);
  } finally { store.close(); }
});

test("a failure on a later overlap rolls back the entire batch", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    store.insertSession({ key: "here", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "here", createdAt: 1, lastActiveAt: 1, ws: "here" });
    const ids = ["first", "second"].map((name) => {
      const id = store.openThread("ember", "CHAT", name, name, null).id;
      store.joinThread(id, "here", "ember");
      store.joinThread(id, "missing", "ember");
      return id;
    });
    installRecentHomeIndex(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    while (!scanRecentWorkspaceStep(db, "here", 64).sourceDone) { /* Prepare the workspace rows. */ }
    while (!scanRecentHomeChatsStep(db, 64).scanDone) { /* Enqueue the default chats. */ }
    while (!settleRecentHomeChatStep(db, 64).chatsDone) { /* Prepare the default rows. */ }
    installRecentHomeOverlap(db);
    while (!scanRecentHomeOverlapStep(db, 64).scanDone) { /* Enqueue both overlaps. */ }
    db.exec(`CREATE TRIGGER fail_later_overlap BEFORE INSERT ON recent_home_overlap_rows WHEN NEW.thread = ${ids[1]}
      BEGIN SELECT RAISE(ABORT, 'test failure'); END`);
    assert.throws(() => settleRecentHomeOverlapStep(db, 64), /test failure/);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM recent_home_overlap_rows").get()?.n, 0);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM recent_home_overlap_totals").get()?.n, 0);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM recent_home_overlap_dirty").get()?.n, 2);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM recent_home_overlap_work").get()?.n, 0);
    db.exec("DROP TRIGGER fail_later_overlap");
    assert.equal(settleRecentHomeOverlapStep(db, 64).overlapsDone, true);
    assert.equal(db.prepare("SELECT total FROM recent_home_overlap_totals WHERE ws = 'here'").get()?.total, 2);
  } finally { store.close(); }
});
