import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { makeStore } from "../src/read/store.ts";
import { usageHistory } from "../src/read/usage.ts";
import { Store } from "../src/store/store.ts";

test("a local midnight does not make usage history read its growing call history", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "a", runtime: "claude", profile: "cc", workspace: "/w/a", token: "a", createdAt: 1, lastActiveAt: 1 });
    const midnight = Date.UTC(2026, 0, 2);
    const calls = Array.from({ length: 2_000 }, (_, n) => [{ id: `c${n}`, at: midnight - 30_000, model: "m", subagent: true, fast: false,
      input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 0, calls: 1, context: null, window: null },
      { turn: null, person: null, thread: null, profile: null }] as const);
    store.recordUsage("/a.jsonl", { session: "a", offset: 1, model: "m" }, "claude", calls as never);

    // The minute is across midnight at UTC+00:01. Even an indexed range over usage would visit all 2,000 calls.
    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      const days = usageHistory(makeStore(store.db, "."), 1n, null).days;
      assert.deepEqual(days.map((d: { day: string; calls: number }) => [d.day, d.calls]), [["2026-01-02", 2_000]]);
    } finally {
      store.db.setAuthorizer(null);
    }
  } finally {
    store.close();
  }
});
