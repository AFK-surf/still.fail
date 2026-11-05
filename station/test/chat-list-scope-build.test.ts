import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { RECENT_CHAT_LIST } from "../src/store/chat-list.ts";
import { scanRecentWorkspaceStep } from "../src/store/chat-list-scope-build.ts";
import { installRecentScopeJournal, trackRecentScope } from "../src/store/chat-list-scope-journal.ts";
import { readPreparedRecentWorkspace } from "../src/store/chat-list-scope-rows.ts";
import { Store } from "../src/store/store.ts";

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
    scanRecentWorkspaceStep(db, "here", 2);
    const progress = () => db.prepare("SELECT * FROM recent_scope_tracked WHERE kind = 1 AND ws = 'here'").get();
    const before = progress();
    db.setAuthorizer((action, name) => action === constants.SQLITE_INSERT && name === "recent_scope_rows" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.throws(() => scanRecentWorkspaceStep(db, "here", 2)); }
    finally { db.setAuthorizer(null); }
    assert.deepEqual(progress(), before);
    assert.equal(db.prepare("SELECT count(*) AS n FROM recent_scope_sources").get()?.n, 0);
    assert.equal(db.prepare("SELECT total FROM recent_scope_tracked WHERE kind = 1 AND ws = 'here'").get()?.total, 0);
    assert.equal(scanRecentWorkspaceStep(db, "here", 2).visited, 1, "the same source can be retried");
  } finally { db.setAuthorizer(null); store.close(); }
});
