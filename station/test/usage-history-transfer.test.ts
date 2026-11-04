import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { constants } from "node:sqlite";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect } from "effect";
import { makeStore } from "../src/read/store.ts";
import { usageHistory } from "../src/read/usage.ts";
import { Store } from "../src/store/store.ts";
import { installCompactUsage } from "../src/store/usage-compact.ts";
import { convertUsageHistoryStep, historyTransferPending, installUsageHistory } from "../src/store/usage-history.ts";
import { retireAfterPrevious } from "../src/usage/module.ts";

function oldStore(path = ":memory:") {
  const store = Store.open(path);
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
    db.prepare("UPDATE usage SET output = 12 WHERE id = 'q1'").run();
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

test("a failed summary batch rolls back its cursor and can be retried", () => {
  const store = oldStore();
  const db = store.db;
  try {
    const put = db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES (?, ?, 'a', 'claude', 2, 0, 0, 0, 1, 1)`);
    put.run("one", 0);
    put.run("two", 900_000);
    installCompactUsage(db, () => 1_800_000);
    installUsageHistory(db, 1_800_000);
    const progress = db.prepare("SELECT * FROM usage_history_transfer").get();
    db.setAuthorizer((action, table) => action === constants.SQLITE_INSERT && table === "usage_history" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.throws(() => convertUsageHistoryStep(db, 1)); }
    finally { db.setAuthorizer(null); }
    assert.deepEqual(db.prepare("SELECT * FROM usage_history_transfer").get(), progress);
    assert.deepEqual(db.prepare("SELECT * FROM usage_history").all(), []);
    while (!convertUsageHistoryStep(db, 1)) { /* Resume from the committed cursor. */ }
    assert.deepEqual(db.prepare("SELECT scope, quarter, calls, tokens FROM usage_history ORDER BY scope, quarter").all().map((r) => ({ ...r })),
      sourceTotals(store));
  } finally { db.setAuthorizer(null); store.close(); }
});

test("each conversion transaction reads and writes at most 64 old summary rows", () => {
  const store = oldStore();
  const db = store.db;
  try {
    const put = db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES (?, ?, 'a', 'claude', 2, 0, 0, 0, 1, 1)`);
    db.exec("BEGIN");
    for (let n = 0; n < 200; n++) put.run(`old-${n}`, n * 900_000);
    db.exec("COMMIT");
    installCompactUsage(db, () => 200 * 900_000);
    installUsageHistory(db, 200 * 900_000);
    const plan = db.prepare(`EXPLAIN QUERY PLAN SELECT * FROM usage_day_quarters
      WHERE (session, quarter, runtime, model) > (?, ?, ?, ?) ORDER BY session, quarter, runtime, model LIMIT ?`)
      .all("a", 0, "claude", "", 64) as { detail: string }[];
    assert.ok(plan.some((row) => /SEARCH usage_day_quarters USING PRIMARY KEY/.test(row.detail)), JSON.stringify(plan));
    assert.equal(convertUsageHistoryStep(db, 10_000), false);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_history").get() as { n: number }).n, 64);
    assert.deepEqual({ ...db.prepare("SELECT phase, q_session, q_quarter FROM usage_history_transfer").get() },
      { phase: 0, q_session: "a", q_quarter: 63 });
    assert.equal(convertUsageHistoryStep(db, 10_000), false);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_history").get() as { n: number }).n, 128);
  } finally { store.close(); }
});

test("a stopped station resumes conversion and tells a waiting usage page", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-history-transfer-"));
  const path = join(dir, "station.db");
  let store = oldStore(path);
  try {
    const put = store.db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES (?, ?, 'a', 'claude', 2, 0, 0, 0, 1, 1)`);
    put.run("one", 0);
    put.run("two", 900_000);
    installCompactUsage(store.db, () => 1_800_000);
    put.run("compact", 1_800_000);
    installUsageHistory(store.db, 2_700_000);
    assert.equal(convertUsageHistoryStep(store.db, 1), false);
    store.close();
    store = Store.open(path);
    assert.equal(historyTransferPending(store.db), true);
    store.db.prepare("UPDATE usage SET output = 5 WHERE id = 'one'").run();
    const told: unknown[] = [];
    const stop = store.subscribe((change) => { if (change.type === "usage") told.push(change); });
    try { await Effect.runPromise(retireAfterPrevious(store, Promise.resolve())); }
    finally { stop(); }
    assert.equal(historyTransferPending(store.db), false);
    assert.ok(told.length >= 1, "the page is notified when the history becomes available");
    assert.deepEqual(store.db.prepare("SELECT scope, quarter, calls, tokens FROM usage_history ORDER BY scope, quarter")
      .all().map((r) => ({ ...r })), sourceTotals(store));
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a session deleted after conversion keeps its later usage changes in its workspace", () => {
  const store = oldStore();
  const db = store.db;
  try {
    db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES ('old', 0, 'a', 'claude', 2, 0, 0, 0, 1, 1)`).run();
    installCompactUsage(db, () => 900_000);
    installUsageHistory(db, 900_000);
    while (!convertUsageHistoryStep(db, 1)) { /* Convert old summaries. */ }
    store.deleteSession("a");
    db.prepare("UPDATE usage SET output = 8 WHERE id = 'old'").run();
    assert.deepEqual(db.prepare("SELECT scope, calls, tokens FROM usage_history WHERE calls != 0").all().map((r) => ({ ...r })),
      [{ scope: "A", calls: 1, tokens: 10 }]);
  } finally { store.close(); }
});

test("an incomplete old summary stays unchanged when an old raw call changes", () => {
  const store = oldStore();
  const db = store.db;
  try {
    db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES ('old', 0, 'a', 'claude', 2, 0, 0, 0, 1, 1)`).run();
    db.exec("UPDATE usage_minute_all SET done = 0");
    installCompactUsage(db, () => 900_000);
    installUsageHistory(db, 900_000);
    while (!convertUsageHistoryStep(db, 1)) { /* Convert old summaries. */ }
    const before = db.prepare("SELECT scope, quarter, calls, tokens FROM usage_history ORDER BY scope, quarter").all();
    db.prepare("UPDATE usage SET output = 8 WHERE id = 'old'").run();
    db.prepare("DELETE FROM usage WHERE id = 'old'").run();
    assert.deepEqual(db.prepare("SELECT scope, quarter, calls, tokens FROM usage_history ORDER BY scope, quarter").all(), before);
    const history = usageHistory(makeStore(db, "."), 0n, null)!;
    assert.equal(history.since, 900_000, "the older, partly known period is not called complete");
  } finally { store.close(); }
});
