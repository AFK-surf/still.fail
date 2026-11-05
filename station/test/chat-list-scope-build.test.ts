import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { RECENT_CHAT_LIST } from "../src/store/chat-list.ts";
import { RecentChatPreparation } from "../src/store/chat-list-prepare.ts";
import { scanRecentWorkspaceStep, settleRecentWorkspaceMemberStep, settleRecentWorkspaceSessionStep } from "../src/store/chat-list-scope-build.ts";
import { installRecentScopeJournal, trackRecentScope } from "../src/store/chat-list-scope-journal.ts";
import { readPreparedRecentWorkspace } from "../src/store/chat-list-scope-rows.ts";
import { Store } from "../src/store/store.ts";

test("new unrelated connections cannot keep an old workspace scan open", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    for (const [key, connect, ws] of [["ours", "a", "here"], ["foreign", "z", "away"]] as const) {
      store.insertSession({ key, connect, runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    }
    const chat = store.openThreadOf("ember", "CHAT", "old-chat", "Old", null, "ours").id;
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    let done = false;
    for (let i = 0; i < 200 && !done; i++) {
      const key = `new-${String(i).padStart(3, "0")}`;
      store.insertSession({ key, connect: `zz-${String(i).padStart(3, "0")}`, runtime: "claude", profile: "cc",
        workspace: "/work", token: key, createdAt: 1, lastActiveAt: 1, ws: "away" });
      const result = scanRecentWorkspaceStep(db, "here", 1);
      assert.ok(result.visited <= 1);
      done = result.sourceDone;
    }
    assert.ok(done, "new connections outside this workspace cannot indefinitely extend the old scan");
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [chat], total: 1 });
  } finally { store.close(); }
});

test("new sessions on an old connection are journaled instead of extending the old scan", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    store.insertSession({ key: "old", connect: "a", runtime: "claude", profile: "cc", workspace: "/work",
      token: "old", createdAt: 1, lastActiveAt: 1, ws: "here" });
    const old = store.openThreadOf("ember", "CHAT", "old-chat", "Old", null, "old").id;
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    let done = false, newest = 0;
    for (let i = 0; i < 20 && !done; i++) {
      const key = `new-${i}`;
      store.insertSession({ key, connect: "a", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws: "here" });
      newest = store.openThreadOf("ember", "CHAT", `new-chat-${i}`, "New", null, key).id;
      const result = scanRecentWorkspaceStep(db, "here", 1);
      assert.ok(result.visited <= 1);
      done = result.sourceDone;
    }
    assert.ok(done, "new sessions do not move the endpoint of the old-session scan");
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    assert.equal(readPreparedRecentWorkspace(db, "here", 50), null, "the new sessions still need reconciliation");
    let sessionsDone = false, membersDone = false;
    for (let i = 0; i < 200 && !sessionsDone; i++) sessionsDone = settleRecentWorkspaceSessionStep(db, "here", 2).sessionsDone;
    for (let i = 0; i < 200 && !membersDone; i++) membersDone = settleRecentWorkspaceMemberStep(db, "here", 2).membersDone;
    assert.ok(sessionsDone && membersDone);
    const preparation = new RecentChatPreparation(db, 2);
    let ready = false;
    for (let i = 0; i < 200 && !ready; i++) ready = preparation.step({ ws: "here", home: "home" }).done;
    assert.ok(ready, "other changes caused by the new chats are also settled");
    const expected = db.prepare(RECENT_CHAT_LIST).all("here", "home", 50) as { id: number; total: number }[];
    const page = readPreparedRecentWorkspace(db, "here", 50);
    assert.deepEqual(page, { ids: expected.map((row) => row.id), total: expected[0]?.total ?? 0 });
    assert.ok(page?.ids.includes(old) && page.ids.includes(newest));
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`a session moved past the old scan boundary is still accounted (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    store.insertSession({ key: "old", connect: "a", runtime: "claude", profile: "cc", workspace: "/work",
      token: "old", createdAt: 1, lastActiveAt: 1, ws: "here" });
    const chat = store.openThreadOf("ember", "CHAT", "old-chat", "Old", null, "old").id;
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    db.prepare("UPDATE sessions SET _rowid_ = 900 WHERE key = 'old'").run();
    let scanned = false;
    for (let i = 0; i < 20 && !scanned; i++) scanned = scanRecentWorkspaceStep(db, "here", 2).sourceDone;
    assert.ok(scanned);
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "the moved row must remain pending");
    const preparation = new RecentChatPreparation(db, 2);
    let ready = false;
    for (let i = 0; i < 100 && !ready; i++) ready = preparation.step({ ws: "here", home: "home" }).done;
    assert.ok(ready);
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [chat], total: 1 });
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`a session whose connection moves behind the scan is still accounted (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, connect] of [["first", "a"], ["moving", "z"]] as const)
      store.insertSession({ key, connect, runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws: "here" });
    const chat = store.openThreadOf("ember", "CHAT", "moving-chat", "Moving", null, "moving").id;
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    scanRecentWorkspaceStep(db, "here", 1);
    db.prepare("UPDATE sessions SET connect = '0' WHERE key = 'moving'").run();
    let scanned = false;
    for (let i = 0; i < 30 && !scanned; i++) scanned = scanRecentWorkspaceStep(db, "here", 2).sourceDone;
    assert.ok(scanned);
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "the moved connection must remain pending");
    const preparation = new RecentChatPreparation(db, 2);
    let ready = false;
    for (let i = 0; i < 100 && !ready; i++) ready = preparation.step({ ws: "here", home: "home" }).done;
    assert.ok(ready);
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [chat], total: 1 });
  } finally { store.close(); }
});

test("the finite old-session walk resumes after reopening and rolls back as one batch", () => {
  const dir = mkdtempSync(join(tmpdir(), "recent-workspace-boundary-"));
  const path = join(dir, "station.db");
  let store = Store.open(path);
  try {
    let db = store.db;
    for (let i = 0; i < 70; i++) {
      const key = `old-${String(i).padStart(3, "0")}`;
      store.insertSession({ key, connect: `c-${String(i).padStart(3, "0")}`, runtime: "claude", profile: "cc",
        workspace: "/work", token: key, createdAt: 1, lastActiveAt: 1, ws: i === 69 ? "here" : "away" });
    }
    store.openThreadOf("ember", "CHAT", "later", "Later", null, "old-069");
    store.openThreadOf("ember", "CHAT", "moves", "Moves", null, "old-000");
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    const progress = () => db.prepare("SELECT * FROM recent_scope_tracked WHERE kind = 1 AND ws = 'here'").get()!;
    for (let i = 0; i < 200 && progress().scan_rowids !== 1; i++) scanRecentWorkspaceStep(db, "here", 1);
    assert.equal(progress().scan_rowids, 1, "many connections switch to the finite old-session walk");
    for (let i = 0; i < 5; i++) scanRecentWorkspaceStep(db, "here", 1);
    db.prepare("UPDATE sessions SET ws = 'here' WHERE key = 'old-000'").run();
    store.insertSession({ key: "new", connect: "new", runtime: "claude", profile: "cc", workspace: "/work",
      token: "new", createdAt: 1, lastActiveAt: 1, ws: "here" });
    store.openThreadOf("ember", "CHAT", "new", "New", null, "new");
    const beforeClose = progress();
    store.close();
    store = Store.open(path);
    db = store.db;
    assert.deepEqual(progress(), beforeClose);
    const beforeSources = db.prepare("SELECT COUNT(*) AS n FROM recent_scope_sources").get()?.n;
    db.exec(`CREATE TRIGGER fail_later_source BEFORE INSERT ON recent_scope_sources WHEN NEW.session = 'old-069'
      BEGIN SELECT RAISE(ABORT, 'test failure'); END`);
    assert.throws(() => scanRecentWorkspaceStep(db, "here", 128), /test failure/);
    assert.deepEqual(progress(), beforeClose);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM recent_scope_sources").get()?.n, beforeSources);
    db.exec("DROP TRIGGER fail_later_source");
    let scanned = false;
    for (let i = 0; i < 100 && !scanned; i++) scanned = scanRecentWorkspaceStep(db, "here", 8).sourceDone;
    assert.ok(scanned);
    const preparation = new RecentChatPreparation(db, 8);
    let ready = false;
    for (let i = 0; i < 200 && !ready; i++) ready = preparation.step({ ws: "here", home: "home" }).done;
    assert.ok(ready);
    const expected = db.prepare(RECENT_CHAT_LIST).all("here", "home", 5) as { id: number; total: number }[];
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: expected.map((row) => row.id), total: expected[0]?.total ?? 0 });
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("one bounded workspace batch advances through multiple empty old sessions", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    for (let i = 0; i < 20; i++) {
      const key = `empty-${i}`;
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws: "here" });
    }
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    const result = scanRecentWorkspaceStep(db, "here", 64);
    assert.ok(result.visited <= 64);
    assert.equal(result.sourceDone, true, "twenty empty sessions fit in one bounded batch");
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: [], total: 0 });
  } finally { store.close(); }
});

test("an explicit workspace's old chat sources resume in bounded batches", () => {
  const dir = mkdtempSync(join(tmpdir(), "recent-workspace-scan-"));
  const path = join(dir, "station.db");
  let store = Store.open(path);
  try {
    let db = store.db;
    for (const [key, ws, connect] of [["one", "here", "ember"], ["two", "here", "slack"], ["other", "elsewhere", "ember"]] as const) {
      store.insertSession({ key, connect, runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    }
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','p','hello',?)");
    for (let i = 0; i < 80; i++) {
      const id = store.openThread("ember", "CHAT", `chat-${i}`, "Chat", null).id;
      if (i < 10) db.prepare("UPDATE threads SET home = 'one' WHERE id = ?").run(id);
      else if (i < 20) { store.joinThread(id, "one", "ember"); store.joinThread(id, "two", "slack"); }
      else { db.prepare("UPDATE threads SET home = 'other' WHERE id = ?").run(id); store.joinThread(id, "one", "ember"); }
      put.run(id, i);
    }
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    for (let i = 0; i < 10; i++) assert.ok(scanRecentWorkspaceStep(db, "here", 3).visited <= 3);
    store.close();
    store = Store.open(path);
    db = store.db;
    let done = false, steps = 0;
    while (!done && steps++ < 200) {
      const batch = scanRecentWorkspaceStep(db, "here", 3);
      assert.ok(batch.visited <= 3);
      done = batch.sourceDone;
    }
    assert.ok(done, "the source scan resumes and finishes");
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "a source scan alone cannot certify a complete scope");
    const expected = db.prepare(RECENT_CHAT_LIST).all("here", "home", 5) as { id: number; total: number }[];
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: expected.map((row) => row.id), total: expected[0]?.total ?? 0 });
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a failed workspace source batch rolls back both the cursor and its contributions", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "one", createdAt: 1, lastActiveAt: 1, ws: "here" });
    const id = store.openThread("ember", "CHAT", "chat", "Chat", null).id;
    db.prepare("UPDATE threads SET home = 'one' WHERE id = ?").run(id);
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    scanRecentWorkspaceStep(db, "here", 1);
    const progress = () => db.prepare("SELECT * FROM recent_scope_tracked WHERE kind = 1 AND ws = 'here'").get();
    const before = progress();
    db.setAuthorizer((action, name) => action === constants.SQLITE_INSERT && name === "recent_scope_rows" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.throws(() => scanRecentWorkspaceStep(db, "here", 2)); }
    finally { db.setAuthorizer(null); }
    assert.deepEqual(progress(), before);
    assert.equal(db.prepare("SELECT count(*) AS n FROM recent_scope_sources").get()?.n, 0);
    assert.equal(db.prepare("SELECT total FROM recent_scope_tracked WHERE kind = 1 AND ws = 'here'").get()?.total, 0);
    assert.equal(scanRecentWorkspaceStep(db, "here", 1).visited, 1, "the same source can be retried");
    assert.equal(db.prepare("SELECT total FROM recent_scope_tracked WHERE kind = 1 AND ws = 'here'").get()?.total, 1);
  } finally { db.setAuthorizer(null); store.close(); }
});

test("a later session's failed source rolls back the earlier sessions in its batch", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    for (const key of ["first", "second"]) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws: "here" });
      store.openThreadOf("ember", "CHAT", `chat-${key}`, "Chat", null, key);
    }
    const hidden = store.openThreadOf("ember", "CHAT", "hidden-membership", "Hidden", null, "outside").id;
    store.joinThread(hidden, "first", "ember");
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    const progress = () => db.prepare("SELECT * FROM recent_scope_tracked WHERE kind = 1 AND ws = 'here'").get();
    const before = progress();
    db.exec(`CREATE TRIGGER fail_second_source BEFORE INSERT ON recent_scope_sources WHEN NEW.session = 'second'
      BEGIN SELECT RAISE(ABORT, 'test failure'); END`);
    assert.throws(() => scanRecentWorkspaceStep(db, "here", 64), /test failure/);
    assert.deepEqual(progress(), before);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM recent_scope_sources").get()?.n, 0);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM recent_scope_rows").get()?.n, 0);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM recent_scope_candidates").get()?.n, 0);
    db.exec("DROP TRIGGER fail_second_source");
    assert.equal(scanRecentWorkspaceStep(db, "here", 64).sourceDone, true);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM recent_scope_candidates").get()?.n, 1);
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    assert.equal(readPreparedRecentWorkspace(db, "here", 5)?.total, 2);
  } finally { store.close(); }
});

test("a session that moves behind the initial scan keeps the workspace unready", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    for (const [key, ws] of [["earlier", "elsewhere"], ["first", "here"], ["last", "here"]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    }
    const thread = store.openThread("ember", "CHAT", "moved", "Moved", null).id;
    db.prepare("UPDATE threads SET home = 'earlier' WHERE id = ?").run(thread);
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    scanRecentWorkspaceStep(db, "here", 1);
    db.prepare("UPDATE sessions SET ws = 'here' WHERE key = 'earlier'").run();
    let done = false;
    for (let i = 0; i < 50 && !done; i++) done = scanRecentWorkspaceStep(db, "here", 2).sourceDone;
    assert.ok(done);
    assert.equal(db.prepare("SELECT 1 FROM recent_scope_rows WHERE ws = 'here' AND thread = ?").get(thread), undefined,
      "the earlier row really was behind the source cursor");
    assert.ok(db.prepare("SELECT 1 FROM recent_scope_session_dirty WHERE kind = 1 AND ws = 'here' AND session = 'earlier'").get());
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "pending work cannot be mistaken for a complete page");
    let settled = false;
    for (let i = 0; i < 50 && !settled; i++) {
      const batch = settleRecentWorkspaceSessionStep(db, "here", 2);
      assert.ok(batch.visited <= 2);
      settled = batch.sessionsDone;
    }
    assert.ok(settled, "the missed session is revisited in bounded batches");
    const expected = db.prepare(RECENT_CHAT_LIST).all("here", "home", 5) as { id: number; total: number }[];
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 5), { ids: expected.map((row) => row.id), total: expected[0]?.total ?? 0 });
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`a session can move again while its workspace sources are being reconciled (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const key of ["one", "two"]) store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/work", token: key, createdAt: 1, lastActiveAt: 1, ws: "here" });
    for (let i = 0; i < 8; i++) {
      const id = store.openThread("ember", "CHAT", `chat-${i}`, "Chat", null).id;
      store.joinThread(id, "one", "ember");
      if (i === 0) store.joinThread(id, "two", "ember");
    }
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    let sourceDone = false;
    while (!sourceDone) sourceDone = scanRecentWorkspaceStep(db, "here", 2).sourceDone;
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    const before = readPreparedRecentWorkspace(db, "here", 50);
    db.prepare("UPDATE sessions SET ws = 'elsewhere' WHERE key = 'one'").run();
    const first = settleRecentWorkspaceSessionStep(db, "here", 2);
    assert.equal(first.visited, 2);
    assert.equal(readPreparedRecentWorkspace(db, "here", 50), null);
    db.prepare("UPDATE sessions SET ws = 'here' WHERE key = 'one'").run();
    let settled = false;
    for (let i = 0; i < 100 && !settled; i++) {
      const batch = settleRecentWorkspaceSessionStep(db, "here", 2);
      assert.ok(batch.visited <= 2);
      settled = batch.sessionsDone;
    }
    assert.ok(settled);
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 50), before, "the interrupted removal is rebuilt without a lost chat");
    assert.equal(db.prepare("SELECT count(*) AS n FROM recent_scope_session_work WHERE ws = 'here'").get()?.n, 0);
  } finally { store.close(); }
});
