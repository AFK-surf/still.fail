import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import * as compact from "../src/store/usage-compact.ts";
import { Store } from "../src/store/store.ts";
import { retireUsageIndexes } from "../src/store/usage-retire.ts";

test("recording calls does not rewrite the workspace total in every transaction", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A",
      createdAt: 0, lastActiveAt: 0 });
    compact.installCompactUsage(store.db, () => store.now());
    retireUsageIndexes(store.db);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number) => ({ id, at, model: "m", subagent: true, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null });
    store.db.setAuthorizer((action, name) => name === "usage_compact_total" &&
      [constants.SQLITE_INSERT, constants.SQLITE_UPDATE, constants.SQLITE_DELETE].includes(action) ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      for (let i = 0; i < 8; i++) store.recordUsage("/a", { session: "a", offset: i + 1, model: "m" }, "claude", [[call(`call-${i}`, Math.floor(i / 3) * 60_000), owner]]);
    } finally { store.db.setAuthorizer(null); }
    assert.equal(compact.compactTotal(store.db, { workspace: "A", home: false }), null, "an unprocessed total is never served as complete");
    let accounted = 0;
    store.db.function("accounted_bucket", () => { accounted++; return 0; });
    store.db.exec("CREATE TEMP TRIGGER count_accounted AFTER UPDATE OF accounted_calls ON usage_compact BEGIN SELECT accounted_bucket(); END");
    for (let n = 0; n < 10; n++) {
      const before = accounted;
      const step = compact.compactTotalsStep(store.db, 2);
      assert.ok(accounted - before <= 2, "one transaction accounts for at most two buckets");
      if (step.done) break;
    }
    assert.equal(accounted, 3, "eight calls in three minutes need three bucket updates");
    assert.deepEqual(compact.compactTotal(store.db, { workspace: "A", home: false }), { calls: 8, tokens: 16 });
  } finally { store.close(); }
});
