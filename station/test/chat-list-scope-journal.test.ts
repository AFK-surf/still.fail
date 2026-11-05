import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { acknowledgeRecentScopeSession, installRecentScopeJournal, trackRecentScope } from "../src/store/chat-list-scope-journal.ts";
import { recentScopeSessionsStep, type RecentScopeSessionCursor } from "../src/store/chat-list-scope-source.ts";
import { Store } from "../src/store/store.ts";

test("workspace journaling installs without reading old sessions and rolls back on failure", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "old", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "old", createdAt: 1, lastActiveAt: 1, ws: "A" });
    db.setAuthorizer((action, name) => action === constants.SQLITE_CREATE_TRIGGER && name === "recent_scope_session_change"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.throws(() => installRecentScopeJournal(db)); }
    finally { db.setAuthorizer(null); }
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'recent_scope_tracked'").get(), undefined);
    db.setAuthorizer((action, name) => action === constants.SQLITE_READ && ["sessions", "threads", "thread_sessions"].includes(name ?? "")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { installRecentScopeJournal(db); }
    finally { db.setAuthorizer(null); }
    trackRecentScope(db, { kind: "workspace", workspace: "A" });
    trackRecentScope(db, { kind: "workspace", workspace: "A" });
    assert.equal(db.prepare("SELECT count(*) AS n FROM recent_scope_tracked").get()?.n, 1);
  } finally { db.setAuthorizer(null); store.close(); }
});

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
    const scope = { kind: "workspace", workspace: "A" } as const;
    assert.equal(acknowledgeRecentScopeSession(db, scope, "moving", first[0]!.revision), false, "an old batch cannot clear a newer change");
    assert.equal(acknowledgeRecentScopeSession(db, scope, "moving", again[0]!.revision), true);
    assert.equal(pending().length, 1, "acknowledging A leaves B's work pending");
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
    const thread = store.openThread("ember", "CHAT", "chat", "Chat", null).id;
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
    const thread = store.openThread("ember", "CHAT", "chat", "Chat", null).id;
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

for (const recursive of [false, true]) test(`a missing home session becoming known is recorded, including after deletion (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const thread = store.openThread("ember", "CHAT", "chat", "Chat", null).id;
    db.prepare("UPDATE threads SET home = 'appears' WHERE id = ?").run(thread);
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "home" });
    trackRecentScope(db, { kind: "workspace", workspace: "A" });
    const pending = () => (db.prepare("SELECT kind, ws, session FROM recent_scope_session_dirty ORDER BY kind, ws").all())
      .map((row) => ({ ...row }));
    const expected = [{ kind: 0, ws: "", session: "appears" }, { kind: 1, ws: "A", session: "appears" }];
    store.insertSession({ key: "appears", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "appears", createdAt: 1, lastActiveAt: 1, ws: "A" });
    assert.deepEqual(pending(), expected);
    db.prepare("DELETE FROM recent_scope_session_dirty").run();
    db.prepare("DELETE FROM sessions WHERE key = 'appears'").run();
    assert.deepEqual(pending(), expected);
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`an update replacing another session records both sides (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["one", "A"], ["two", "B"]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    }
    const thread = store.openThread("ember", "CHAT", "chat", "Chat", null).id;
    db.prepare("UPDATE threads SET home = 'two' WHERE id = ?").run(thread);
    installRecentScopeJournal(db);
    trackRecentScope(db, { kind: "home" });
    for (const workspace of ["A", "B", "unrelated"]) trackRecentScope(db, { kind: "workspace", workspace });
    db.prepare("UPDATE OR REPLACE sessions SET token = 'two' WHERE key = 'one'").run();
    const pending = db.prepare("SELECT kind, ws, session FROM recent_scope_session_dirty ORDER BY kind, ws, session").all();
    assert.deepEqual(pending.map((row) => ({ ...row })), [
      { kind: 0, ws: "", session: "two" },
      { kind: 1, ws: "A", session: "one" },
      { kind: 1, ws: "B", session: "two" },
    ]);
  } finally { store.close(); }
});

for (const recursive of [false, true]) for (const operation of ["insert", "update"] as const)
  test(`a session ${operation} replacing a rowid records the displaced session (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
      for (const [key, ws] of [["one", "A"], ["two", "B"]] as const)
        store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
          token: key, createdAt: 1, lastActiveAt: 1, ws });
      store.openThreadOf("ember", "CHAT", "chat-two", "Chat", null, "two");
      installRecentScopeJournal(db);
      trackRecentScope(db, { kind: "home" });
      for (const workspace of ["A", "B"]) trackRecentScope(db, { kind: "workspace", workspace });
      const target = (db.prepare("SELECT rowid FROM sessions WHERE key = 'two'").get() as { rowid: number }).rowid;
      if (operation === "insert") db.prepare(`INSERT OR REPLACE INTO sessions(rowid,key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws)
        VALUES (?,'new','ember','thread','claude','cc','/work','new',1,1,'A')`).run(target);
      else db.prepare("UPDATE OR REPLACE sessions SET oid = ? WHERE key = 'one'").run(target);
      const pending = db.prepare("SELECT kind, ws, session FROM recent_scope_session_dirty ORDER BY kind, ws, session").all()
        .map((row) => ({ ...row }));
      assert.ok(pending.some((row) => row.kind === 0 && row.session === "two"));
      assert.ok(pending.some((row) => row.kind === 1 && row.ws === "B" && row.session === "two"));
      assert.ok(pending.some((row) => row.kind === 1 && row.ws === "A" && row.session === (operation === "insert" ? "new" : "one")));
    } finally { store.close(); }
  });
