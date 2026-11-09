import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { installSearchScopeIndex } from "../src/search/scope-index.ts";
import { SearchScopePreparation } from "../src/search/scope-prepare.ts";
import { Store } from "../src/store/store.ts";

test("a failed search-scope installation leaves no partial state and can be retried", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    store.openThread("ember", "CHAT", "old", "Old", null);
    db.setAuthorizer((action, name) => action === constants.SQLITE_CREATE_TRIGGER && name === "search_scope_thread_add"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.throws(() => installSearchScopeIndex(db)); }
    finally { db.setAuthorizer(null); }
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'search_scope_meta'").get(), undefined);
    installSearchScopeIndex(db);
    installSearchScopeIndex(db);
  } finally { db.setAuthorizer(null); store.close(); }
});

for (const recursive of [false, true]) test(`search candidate scopes follow old rows and changes (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["a", "here"], ["b", "here"], ["c", "away"], ["old", null]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const shared = store.openThread("ember", "CHAT", "shared", "Shared", null).id;
    const orphan = store.openThread("ember", "CHAT", "orphan", "Orphan", null).id;
    const later = store.openThread("ember", "CHAT", "later", "Later", null).id;
    store.joinThread(shared, "a", "ember");
    store.joinThread(shared, "b", "ember");
    store.joinThread(later, "c", "ember");
    const prepare = new SearchScopePreparation(db, 1);
    assert.equal(prepare.step().done, false);
    // Move old sources on both sides of the backfill cursor, and add a formerly unknown session.
    db.prepare("UPDATE sessions SET ws = 'here' WHERE key = 'c'").run();
    store.joinThread(orphan, "old", "ember");
    store.joinThread(later, "unknown", "ember");
    const drain = () => {
      let done = false;
      for (let i = 0; i < 200 && !done; i++) {
        const step = prepare.step();
        assert.ok(step.visited <= 1);
        done = step.done;
      }
      assert.ok(done, "the old scan and all marked changes complete");
    };
    const refs = (kind: number, ws: string, thread: number) =>
      (db.prepare("SELECT refs FROM search_scope_threads WHERE kind = ? AND ws = ? AND thread = ?").get(kind, ws, thread) as { refs: number } | undefined)?.refs;
    drain();
    assert.equal(refs(1, "here", shared), 2);
    assert.equal(refs(1, "here", later), 1);
    assert.equal(refs(0, "", later), 1, "an unknown session remains a default candidate");
    assert.equal(refs(0, "", orphan), 1);
    assert.equal(db.prepare("SELECT 1 FROM search_scope_orphans WHERE thread = ?").get(orphan), undefined);

    db.prepare("DELETE FROM thread_sessions WHERE thread = ? AND session = 'a'").run(shared);
    assert.equal(refs(1, "here", shared), 1);
    const displaced = db.prepare("SELECT rowid AS n FROM thread_sessions WHERE thread = ? AND session = 'b'").get(shared) as { n: number };
    db.prepare("INSERT OR REPLACE INTO thread_sessions(rowid, thread, session, connect, joined_at) VALUES (?, ?, 'a', 'ember', 1)")
      .run(displaced.n, later);
    drain();
    assert.equal(refs(1, "here", shared), undefined, "a rowid replacement removes the displaced membership");
    assert.ok(db.prepare("SELECT 1 FROM search_scope_orphans WHERE thread = ?").get(shared));
    assert.equal(refs(1, "here", later), 2);

    db.prepare("UPDATE sessions SET ws = '非ASCII' WHERE key = 'a'").run();
    drain();
    assert.equal(refs(1, "here", later), 1);
    assert.equal(refs(2, "", later), 1, "non-ASCII identities are conservatively reconsidered");
    db.prepare("DELETE FROM sessions WHERE key = 'c'").run();
    drain();
    assert.equal(refs(1, "here", later), undefined);
    assert.equal(refs(0, "", later), 2, "a missing session keeps its chat in the default candidate range");
  } finally { store.close(); }
});
