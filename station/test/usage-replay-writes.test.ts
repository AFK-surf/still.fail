import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { retireUsageIndexes } from "../src/store/usage-retire.ts";

for (const retired of [false, true]) test(`replaying unchanged usage writes nothing ${retired ? "after" : "before"} index retirement`, () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    if (retired) retireUsageIndexes(store.db);
    const call = { id: "one", at: 60_000, model: "m", subagent: false, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const file = { session: "a", offset: 1, model: "m" };
    store.recordUsage("/a", file, "claude", [[call, owner]]);
    const changes = () => (store.db.prepare("SELECT total_changes() AS n").get() as { n: number }).n;
    const before = changes();
    assert.equal(store.recordUsage("/a", file, "claude", [[call, owner]]), 0);
    assert.equal(changes(), before, "an unchanged call and offset do not update rows or their triggers");
    assert.equal(store.recordUsage("/a", { ...file, offset: 2 }, "claude", [[{ ...call, output: 4 }, owner]]), 0);
    assert.deepEqual(store.usageOfSession("a").map((row) => [row.calls, row.input, row.output]), [[1, 1, 4]]);
    assert.equal(store.usageFiles().get("/a")?.offset, 2);
  } finally { store.close(); }
});
