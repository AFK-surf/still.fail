import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { RECENT_CHAT_LIST } from "../src/store/chat-list.ts";
import { scanRecentWorkspaceStep, settleRecentWorkspaceSessionStep } from "../src/store/chat-list-scope-build.ts";
import { installRecentScopeJournal, trackRecentScope } from "../src/store/chat-list-scope-journal.ts";
import { readPreparedRecentWorkspace } from "../src/store/chat-list-scope-rows.ts";
import { Store } from "../src/store/store.ts";

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
      const id = store.openThread("ember", "EMBER", `chat-${i}`, "Chat", null).id;
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
    const id = store.openThread("ember", "EMBER", "chat", "Chat", null).id;
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
      store.openThreadOf("ember", "EMBER", `chat-${key}`, "Chat", null, key);
    }
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
    db.exec("DROP TRIGGER fail_second_source");
    assert.equal(scanRecentWorkspaceStep(db, "here", 64).sourceDone, true);
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
    const thread = store.openThread("ember", "EMBER", "moved", "Moved", null).id;
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
      const id = store.openThread("ember", "EMBER", `chat-${i}`, "Chat", null).id;
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
