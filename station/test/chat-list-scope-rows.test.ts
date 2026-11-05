import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { RECENT_CHAT_LIST } from "../src/store/chat-list.ts";
import { installRecentScopeJournal, trackRecentScope } from "../src/store/chat-list-scope-journal.ts";
import { putRecentScopeSource, readPreparedRecentWorkspace, removeRecentScopeSource } from "../src/store/chat-list-scope-rows.ts";
import { Store } from "../src/store/store.ts";

test("workspace contributions keep the original ordering and count once per shared chat", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    for (const [key, ws] of [["one", "here"], ["two", "here"], ["other", "elsewhere"]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    }
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','p','hello',?)");
    const make = (name: string, home: string | null, members: string[], created: number, at: number | null) => {
      const id = store.openThread("ember", "EMBER", name, name, null).id;
      db.prepare("UPDATE threads SET home = ?, created_at = ? WHERE id = ?").run(home, created, id);
      for (const member of members) store.joinThread(id, member, "ember");
      if (at !== null) put.run(id, at);
      return BigInt(id);
    };
    const own = make("own", "one", ["other"], 1, 30);
    const shared = make("shared", null, ["one", "two", "other"], 2, 20);
    const empty = make("empty", null, ["two"], 5, null);
    const foreign = make("foreign", "other", ["one"], 3, 40);
    installRecentScopeJournal(db);
    for (const workspace of ["here", "elsewhere"]) trackRecentScope(db, { kind: "workspace", workspace });
    assert.equal(readPreparedRecentWorkspace(db, "here", 5), null, "a partly built scope is not a page");
    for (const [ws, thread, session] of [["here", own, "one"], ["here", shared, "one"], ["here", shared, "two"],
      ["here", empty, "two"], ["elsewhere", shared, "other"], ["elsewhere", foreign, "other"]] as const) {
      assert.equal(putRecentScopeSource(db, ws, thread, session), true);
    }
    assert.equal(putRecentScopeSource(db, "here", shared, "one"), true, "replaying a source is harmless");
    assert.equal(putRecentScopeSource(db, "here", 99_999n, "one"), false, "a deleted thread adds no count");
    assert.throws(() => putRecentScopeSource(db, "untracked", own, "one"), /not tracked/);
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1").run();
    const original = (ws: string, limit: number) => {
      const rows = db.prepare(RECENT_CHAT_LIST).all(ws, "home", limit) as { id: number; total: number }[];
      return { ids: rows.map((row) => row.id), total: rows[0]?.total ?? 0 };
    };
    const cases = ["here", "elsewhere"].flatMap((ws) => [1, 3, 50].map((limit) => ({ ws, limit, expected: original(ws, limit) })));
    db.setAuthorizer((action, name) => action === constants.SQLITE_READ &&
      ["threads", "thread_state", "entries", "sessions", "thread_sessions"].includes(name ?? "") ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { for (const { ws, limit, expected } of cases) assert.deepEqual(readPreparedRecentWorkspace(db, ws, limit), expected); }
    finally { db.setAuthorizer(null); }

    const before = readPreparedRecentWorkspace(db, "here", 50)!;
    removeRecentScopeSource(db, "here", shared, "one");
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 50), before, "another session still contributes the chat");
    removeRecentScopeSource(db, "here", shared, "two");
    assert.deepEqual(readPreparedRecentWorkspace(db, "here", 50),
      { ids: before.ids.filter((id) => BigInt(id) !== shared), total: before.total - 1 });
    removeRecentScopeSource(db, "here", shared, "two");
    assert.equal(readPreparedRecentWorkspace(db, "here", 50)?.total, before.total - 1, "a replayed removal does not subtract twice");
    const otherBefore = readPreparedRecentWorkspace(db, "elsewhere", 50);
    db.prepare("UPDATE sessions SET ws = 'new' WHERE key = 'one'").run();
    assert.equal(readPreparedRecentWorkspace(db, "here", 50), null, "a changed source needs another pass");
    assert.deepEqual(readPreparedRecentWorkspace(db, "elsewhere", 50), otherBefore, "a different scope remains ready");
  } finally { db.setAuthorizer(null); store.close(); }
});
