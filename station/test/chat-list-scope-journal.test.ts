import assert from "node:assert/strict";
import { test } from "node:test";
import { installRecentScopeJournal, trackRecentScope } from "../src/store/chat-list-scope-journal.ts";
import { recentScopeSessionsStep, type RecentScopeSessionCursor } from "../src/store/chat-list-scope-source.ts";
import { Store } from "../src/store/store.ts";

for (const recursive of [false, true]) test(`a session moving behind a workspace scan is recorded for another pass (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["earlier", "elsewhere"], ["first", "here"], ["last", "here"]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    }
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    let cursor: RecentScopeSessionCursor = { connect: null, after: null, done: false };
    const first = recentScopeSessionsStep(db, "here", cursor, 1);
    assert.deepEqual(first.sessions.map((session) => session.key), ["first"]);
    cursor = first.cursor;
    db.prepare("UPDATE sessions SET ws = 'here' WHERE key = 'earlier'").run();
    const rest: string[] = [];
    while (!cursor.done) {
      const step = recentScopeSessionsStep(db, "here", cursor, 1);
      rest.push(...step.sessions.map((session) => session.key));
      cursor = step.cursor;
    }
    assert.deepEqual(rest, ["last"], "the index cursor cannot revisit the earlier row by itself");
    const pending = db.prepare("SELECT session FROM recent_scope_session_dirty WHERE kind = 1 AND ws = 'here'").all() as { session: string }[];
    assert.deepEqual(pending.map((row) => row.session), ["earlier"], "the missed move is kept for the builder");
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`workspace session moves record only affected workspaces (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    store.insertSession({ key: "moving", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "moving", createdAt: 1, lastActiveAt: 1, ws: "A" });
    installRecentScopeJournal(db);
    for (const workspace of ["A", "B", "unrelated"]) trackRecentScope(db, { kind: "workspace", workspace });
    db.prepare("UPDATE sessions SET ws = 'B' WHERE key = 'moving'").run();
    const pending = () => db.prepare("SELECT ws, session, revision FROM recent_scope_session_dirty WHERE kind = 1 ORDER BY ws").all() as
      { ws: string; session: string; revision: number }[];
    const first = pending();
    assert.deepEqual(first.map(({ ws, session }) => ({ ws, session })), [{ ws: "A", session: "moving" }, { ws: "B", session: "moving" }]);
    db.prepare("UPDATE sessions SET ws = 'A' WHERE key = 'moving'").run();
    const again = pending();
    assert.ok(again.every((row, index) => row.revision > first[index]!.revision), "a builder can notice changes during a pass");
    db.prepare("DELETE FROM recent_scope_session_dirty").run();
    db.prepare("UPDATE sessions SET title = 'renamed' WHERE key = 'moving'").run();
    assert.deepEqual(pending(), [], "unrelated session edits do not postpone the ordering");
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`a move between named workspaces does not delay the home scope (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    store.insertSession({ key: "moving", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "moving", createdAt: 1, lastActiveAt: 1, ws: "A" });
    const thread = store.openThread("ember", "EMBER", "chat", "Chat", null).id;
    db.prepare("UPDATE threads SET home = 'moving' WHERE id = ?").run(thread);
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "home" });
    trackRecentScope(db, { kind: "workspace", workspace: "A" });
    trackRecentScope(db, { kind: "workspace", workspace: "B" });
    db.prepare("UPDATE sessions SET ws = 'B' WHERE key = 'moving'").run();
    assert.equal(db.prepare("SELECT 1 FROM recent_scope_session_dirty WHERE kind = 0").get(), undefined,
      "its home visibility is unchanged");
    db.prepare("UPDATE sessions SET ws = NULL WHERE key = 'moving'").run();
    assert.ok(db.prepare("SELECT 1 FROM recent_scope_session_dirty WHERE kind = 0 AND session = 'moving'").get(),
      "moving into home does need a home update");
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`replacing a session also records the workspace and home it leaves (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    store.insertSession({ key: "old", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "shared-token", createdAt: 1, lastActiveAt: 1, ws: "A" });
    const thread = store.openThread("ember", "EMBER", "chat", "Chat", null).id;
    db.prepare("UPDATE threads SET home = 'old' WHERE id = ?").run(thread);
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "home" });
    for (const workspace of ["A", "B", "unrelated"]) trackRecentScope(db, { kind: "workspace", workspace });
    db.prepare(`INSERT OR REPLACE INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws)
      VALUES ('new','ember','thread','claude','cc','/work','shared-token',1,1,'B')`).run();
    const pending = db.prepare("SELECT kind, ws, session FROM recent_scope_session_dirty ORDER BY kind, ws, session").all();
    assert.deepEqual(pending.map((row) => ({ ...row })), [
      { kind: 0, ws: "", session: "old" },
      { kind: 1, ws: "A", session: "old" },
      { kind: 1, ws: "B", session: "new" },
    ]);
  } finally { store.close(); }
});
