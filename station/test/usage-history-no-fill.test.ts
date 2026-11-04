import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { makeStore } from "../src/read/store.ts";
import { usageHistory } from "../src/read/usage.ts";
import { installCompactUsage } from "../src/store/usage-compact.ts";
import { convertUsageHistoryStep, historyTransferPending, installUsageHistory, usageHistorySince } from "../src/store/usage-history.ts";
import { Store } from "../src/store/store.ts";
import { retireAfterPrevious } from "../src/usage/module.ts";

function beforeHistory(store: Store): void {
  store.db.exec(`DROP TRIGGER usage_history_add; DROP TRIGGER usage_history_grow; DROP TRIGGER usage_history_move; DROP TRIGGER usage_history_drop;
    DROP TABLE usage_history; DROP TABLE usage_history_total; DROP TABLE usage_history_since;`);
}

test("handover preserves the old quarterly and compact summaries in the usage history", async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    beforeHistory(store);
    const put = db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES (?, ?, 'old', 'claude', ?, 0, 0, 0, 1, 1)`);
    put.run("old-quarter", 1, 2);
    installCompactUsage(db, () => 900_000);
    put.run("old-compact", 86_400_000, 4);
    await Effect.runPromise(retireAfterPrevious(store, Promise.resolve()));
    const read = () => usageHistory(makeStore(db, "."), 0n, null)!.days.map((day: { day: string; calls: number; tokens: number }) =>
      [day.day, day.calls, day.tokens]);
    assert.deepEqual(read(), [["1970-01-01", 1, 3], ["1970-01-02", 1, 5]]);
    put.run("after-handover", 86_400_001, 6);
    assert.deepEqual(read(), [["1970-01-01", 1, 3], ["1970-01-02", 2, 12]]);
  } finally { store.close(); }
});

test("installing usage history does not read old calls or summaries under its installation lock", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    // An older store has no history or marker column yet.
    beforeHistory(store);
    const insert = db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES (?, ?, 'old', 'claude', 2, 0, 0, 0, 3, 1)`);
    db.exec("BEGIN");
    for (let n = 0; n < 5000; n++) insert.run(`old-${n}`, n * 900_000);
    db.exec("COMMIT");
    installCompactUsage(db, () => 0);
    const oldReads: string[] = [];
    const traced = new Proxy(db, {
      get(target, property) {
        if (property === "prepare" || property === "exec") return (source: string) => {
          if (property === "prepare" && (/\b(?:from|join)\s+usage_day_quarters\b/i.test(source)
            || (/\b(?:from|join)\s+usage\b/i.test(source) && !/^\s*select 1 from usage limit 1\s*$/i.test(source)))) oldReads.push(source);
          return property === "prepare" ? target.prepare(source) : target.exec(source);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    const now = 5_000 * 900_000;
    installUsageHistory(traced, now);
    assert.deepEqual(oldReads, [], "installation does not read old calls or summaries");
    assert.equal(usageHistorySince(db), null, "the old summary was complete");
    assert.equal(historyTransferPending(db), true);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_history").get() as { n: number }).n, 0);
    while (!convertUsageHistoryStep(db)) { /* Old summaries only, in bounded batches. */ }
    insert.run("new", now + 1000);
    const total = () => db.prepare("SELECT calls, tokens FROM usage_history_total WHERE scope = ''").get() as { calls: number; tokens: number };
    assert.deepEqual({ ...total() }, { calls: 5_001, tokens: 25_005 });
    db.prepare("UPDATE usage SET output=100 WHERE id='old-0'").run();
    assert.deepEqual({ ...total() }, { calls: 5_001, tokens: 25_102 });
    db.prepare("UPDATE usage SET output=10 WHERE id='new'").run();
    assert.deepEqual({ ...total() }, { calls: 5_001, tokens: 25_109 });
    db.prepare("DELETE FROM usage WHERE id='old-1'").run();
    assert.deepEqual({ ...total() }, { calls: 5_000, tokens: 25_104 });
    db.prepare("DELETE FROM usage WHERE id='new'").run();
    assert.deepEqual({ ...total() }, { calls: 4_999, tokens: 25_092 });
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`old and new calls in the same quarter are each counted once (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    beforeHistory(store);
    db.exec(`PRAGMA recursive_triggers = ${recursive ? 1 : 0}`);
    const write = db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES (?, ?, 's', 'claude', 2, 0, 0, 0, ?, 1)
      ON CONFLICT(id) DO UPDATE SET output = MAX(output, excluded.output)`);
    write.run("old", 900_010, 3);
    installCompactUsage(db, () => 900_100);
    installUsageHistory(db, 900_100);
    write.run("new", 900_200, 3); // An older writer omits the marker.
    while (!convertUsageHistoryStep(db)) { /* Old summaries only. */ }
    const rows = () => db.prepare("SELECT quarter, calls, tokens FROM usage_history ORDER BY quarter").all().map((row) => ({ ...row }));
    assert.deepEqual(rows(), [{ quarter: 1, calls: 2, tokens: 10 }]);
    write.run("old", 900_010, 30);
    db.prepare("UPDATE usage SET at = 10 WHERE id = 'old'").run();
    assert.deepEqual(rows(), [{ quarter: 0, calls: 1, tokens: 32 }, { quarter: 1, calls: 1, tokens: 5 }]);
    write.run("new", 900_200, 10);
    assert.deepEqual(rows(), [{ quarter: 0, calls: 1, tokens: 32 }, { quarter: 1, calls: 1, tokens: 12 }]);
    db.prepare("UPDATE usage SET at = 1_800_000 WHERE id = 'new'").run();
    assert.deepEqual(rows(), [{ quarter: 0, calls: 1, tokens: 32 }, { quarter: 1, calls: 0, tokens: 0 }, { quarter: 2, calls: 1, tokens: 12 }]);
    db.prepare("DELETE FROM usage WHERE id IN ('old', 'new')").run();
    assert.deepEqual(rows(), [{ quarter: 0, calls: 0, tokens: 0 }, { quarter: 1, calls: 0, tokens: 0 }, { quarter: 2, calls: 0, tokens: 0 }]);
  } finally { store.close(); }
});

test("an already installed history is left intact even if it predates the marker", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    beforeHistory(store);
    db.exec(`CREATE TABLE usage_history (scope TEXT, quarter INTEGER, calls INTEGER, tokens INTEGER);
      CREATE TABLE usage_history_since (id INTEGER PRIMARY KEY, since INTEGER);
      INSERT INTO usage_history VALUES ('', 1, 2, 7); INSERT INTO usage_history_since VALUES (1, NULL);`);
    const schema = () => db.prepare("SELECT type, name, sql FROM sqlite_master ORDER BY type, name").all();
    const before = schema();
    installUsageHistory(db, 999);
    assert.deepEqual(schema(), before);
    assert.deepEqual({ ...db.prepare("SELECT calls, tokens FROM usage_history").get() }, { calls: 2, tokens: 7 });
    assert.equal(usageHistorySince(db), null);
  } finally { store.close(); }
});
