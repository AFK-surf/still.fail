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
