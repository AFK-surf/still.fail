import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import * as compact from "../src/store/usage-compact.ts";
import { Store } from "../src/store/store.ts";
import { retireUsageIndexes } from "../src/store/usage-retire.ts";

const a = { workspace: "A", home: false };
const b = { workspace: "B", home: false };
const home = { workspace: "A", home: true };

for (const recursive of [false, true]) test(`compact totals follow changes and workspace moves (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws] of [["a", "A"], ["b", "B"], ["h", null]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, ws,
        createdAt: 0, lastActiveAt: 0 });
    }
    compact.installCompactUsage(store.db, () => store.now());
    retireUsageIndexes(store.db);
    store.db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number, input: number) => ({ id, at, model: "m", subagent: true, fast: false,
      input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null });
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call("old", -60_000, 10), owner], [call("new", 60_000, 19), owner]]);
    store.recordUsage("/b", { session: "b", offset: 1, model: "m" }, "claude", [[call("other", 60_000, 29), owner]]);
    store.recordUsage("/h", { session: "h", offset: 1, model: "m" }, "claude", [[call("home", 60_000, 39), owner]]);
    // The total is a maintained statistic, so older minutes, calls and other workspaces are not enumerated.
    store.db.setAuthorizer((action, name) => action === constants.SQLITE_READ && (name === "usage" || name === "usage_compact")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      assert.deepEqual(compact.compactTotal(store.db, a), { calls: 2, tokens: 31 });
      assert.deepEqual(compact.compactTotal(store.db, b), { calls: 1, tokens: 30 });
      assert.deepEqual(compact.compactTotal(store.db, home), { calls: 3, tokens: 71 });
      assert.deepEqual(compact.compactTotal(store.db, null), { calls: 4, tokens: 101 });
    } finally { store.db.setAuthorizer(null); }

    store.db.prepare("UPDATE usage SET output = 5 WHERE id = ?").run("new");
    store.db.prepare("DELETE FROM usage WHERE id = ?").run("old");
    assert.deepEqual(compact.compactTotal(store.db, a), { calls: 1, tokens: 24 });

    store.db.exec("UPDATE sessions SET ws = 'B' WHERE key = 'a'");
    assert.equal(compact.compactTotal(store.db, a), null, "a moving scope is never shown with stale ownership");
    assert.equal(compact.compactTotal(store.db, b), null);
    let done = false;
    for (let i = 0; i < 32 && !done; i++) done = compact.moveCompactStep(store.db, 1).done;
    assert.ok(done, "moving one session finishes in bounded steps");
    assert.deepEqual(compact.compactTotal(store.db, a), { calls: 0, tokens: 0 });
    assert.deepEqual(compact.compactTotal(store.db, b), { calls: 2, tokens: 54 });
    assert.deepEqual(compact.compactTotal(store.db, home), { calls: 1, tokens: 40 });

    // A previous station omits the compact marker but can still insert and grow its response.
    const oldWriter = store.db.prepare(`INSERT INTO usage (id, at, session, person, profile, runtime, model, subagent,
      input, cache_read, cache_write, cache_write_long, output) VALUES ('legacy', 120000, 'b', 'p', 'cc', 'claude', 'm', 1, 2, 0, 0, 0, ?)
      ON CONFLICT (id) DO UPDATE SET output = MAX(output, excluded.output)`);
    oldWriter.run(1);
    oldWriter.run(4);
    assert.deepEqual(compact.compactTotal(store.db, b), { calls: 3, tokens: 60 });
  } finally { store.close(); }
});
