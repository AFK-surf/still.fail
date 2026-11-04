import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { makeStore } from "../src/read/store.ts";
import { usageHistory } from "../src/read/usage.ts";
import { Store } from "../src/store/store.ts";
import { installCompactUsage } from "../src/store/usage-compact.ts";
import { convertUsageHistoryStep, historyTransferPending, installUsageHistory } from "../src/store/usage-history.ts";

function oldStore() {
  const store = Store.open(":memory:");
  store.db.exec(`DROP TRIGGER usage_history_add; DROP TRIGGER usage_history_grow; DROP TRIGGER usage_history_move; DROP TRIGGER usage_history_drop;
    DROP TABLE usage_history; DROP TABLE usage_history_total; DROP TABLE usage_history_since;`);
  for (const [key, ws] of [["a", "A"], ["b", "B"]] as const)
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, ws, createdAt: 0, lastActiveAt: 0 });
  return store;
}

function sourceTotals(store: Store) {
  const scope = (name: string) => `COALESCE((SELECT COALESCE(ws, '') FROM sessions WHERE key = ${name}.session),
    (SELECT scope FROM usage_history_orphans WHERE session = ${name}.session), '')`;
  return store.db.prepare(`SELECT scope, quarter, SUM(calls) AS calls, SUM(tokens) AS tokens FROM (
    SELECT ${scope("q")} AS scope, q.quarter, q.calls, q.tokens FROM usage_day_quarters q
    UNION ALL SELECT ${scope("c")}, CASE WHEN c.minute >= 0 THEN c.minute / 15 ELSE -1 - ((-1 - c.minute) / 15) END,
      c.calls, c.input + c.cache_read + c.cache_write + c.cache_write_long + c.output FROM usage_compact c
  ) GROUP BY scope, quarter HAVING calls != 0 OR tokens != 0 ORDER BY scope, quarter`).all().map((r) => ({ ...r }));
}

for (const recursive of [false, true]) test(`old summaries transfer in batches while calls change (recursive triggers ${recursive})`, () => {
  const store = oldStore();
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? 1 : 0}`);
    const put = db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES (?, ?, ?, 'claude', ?, 0, 0, 0, 1, 1)`);
    for (const [id, at, session] of [["q1", 0, "a"], ["q2", 900_000, "a"], ["q3", 0, "b"]] as const) put.run(id, at, session, 2);
    installCompactUsage(db, () => 1_800_000);
    for (const [id, at, session] of [["c1", 1_800_000, "a"], ["c2", 2_700_000, "a"], ["c3", 1_800_000, "b"]] as const) put.run(id, at, session, 4);
    installUsageHistory(db, 3_600_000);
    assert.equal(historyTransferPending(db), true);
    assert.equal(usageHistory(makeStore(db, "."), 0n, null), null, "a partially converted history is not presented as complete");
    assert.equal(convertUsageHistoryStep(db, 1), false); // First old-quarter row is now accounted for.
    db.prepare("UPDATE usage SET output = 7 WHERE id = 'q1'").run();
    db.prepare("UPDATE usage SET output = 8 WHERE id = 'q2'").run();
    while ((db.prepare("SELECT phase FROM usage_history_transfer").get() as { phase: number }).phase === 0) convertUsageHistoryStep(db, 1);
    assert.equal(convertUsageHistoryStep(db, 1), false); // First compact bucket is now accounted for.
    db.prepare("UPDATE usage SET output = 9 WHERE id = 'c1'").run();
    db.prepare("UPDATE usage SET output = 10 WHERE id = 'c2'").run();
    db.prepare("DELETE FROM usage WHERE id = 'c3'").run();
    put.run("new-before-cursor", 60_000, "a", 5);
    put.run("new-after-cursor", 3_600_000, "b", 6);
    // Foreground changes remain allowed between batches, including a workspace move and a deleted session.
    store.setSessionsWs("A", "C");
    store.deleteSession("b");
    let steps = 0;
    while (historyTransferPending(db)) {
      db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage" ? constants.SQLITE_DENY : constants.SQLITE_OK);
      try { convertUsageHistoryStep(db, 1); }
      finally { db.setAuthorizer(null); }
      assert.ok(++steps < 30);
    }
    const actual = db.prepare("SELECT scope, quarter, calls, tokens FROM usage_history WHERE calls != 0 OR tokens != 0 ORDER BY scope, quarter")
      .all().map((r) => ({ ...r }));
    assert.deepEqual(actual, sourceTotals(store));
    db.prepare("UPDATE usage SET output = 20 WHERE id = 'q1'").run();
    put.run("new-after-transfer", 4_500_000, "a", 7);
    assert.deepEqual(db.prepare("SELECT scope, quarter, calls, tokens FROM usage_history WHERE calls != 0 OR tokens != 0 ORDER BY scope, quarter")
      .all().map((r) => ({ ...r })), sourceTotals(store));
  } finally { db.setAuthorizer(null); store.close(); }
});
