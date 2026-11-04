import assert from "node:assert/strict";
import { test } from "node:test";
import { installCompactUsage } from "../src/store/usage-compact.ts";
import { installUsageHistory, usageHistorySince } from "../src/store/usage-history.ts";
import { Store } from "../src/store/store.ts";

test("installing usage history does not read or reconstruct old calls or quarters", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    // An older store has no history or marker column yet.
    db.exec(`DROP TRIGGER usage_history_add; DROP TRIGGER usage_history_grow; DROP TRIGGER usage_history_move; DROP TRIGGER usage_history_drop;
      DROP TABLE usage_history; DROP TABLE usage_history_total; DROP TABLE usage_history_since;
      ALTER TABLE usage DROP COLUMN history_counted;`);
    const insert = db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES (?, ?, 'old', 'claude', 2, 0, 0, 0, 3, 1)`);
    db.exec("BEGIN");
    for (let n = 0; n < 5000; n++) insert.run(`old-${n}`, n * 900_000);
    db.exec("COMMIT");
    installCompactUsage(db, () => 0);
    let calls = 0, quarters = 0;
    db.function("visit_old_call", () => { calls++; return 1; });
    db.function("visit_old_quarter", () => { quarters++; return 1; });
    const traced = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (source: string) => target.prepare(source
          .replace("WHERE u.at >= ?1 GROUP BY", "WHERE u.at >= ?1 AND visit_old_call() GROUP BY")
          .replace("WHERE ?1 IS NULL OR q.quarter < ?1 GROUP BY", "WHERE (?1 IS NULL OR q.quarter < ?1) AND visit_old_quarter() GROUP BY"));
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    const now = 5_000 * 900_000;
    installUsageHistory(traced, now);
    assert.deepEqual({ calls, quarters }, { calls: 0, quarters: 0 }, "old history is never read to initialize new statistics");
    assert.equal(usageHistorySince(db), now, "earlier usage is marked incomplete");
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_history").get() as { n: number }).n, 0);

    insert.run("new", now + 1000);
    const total = () => db.prepare("SELECT calls, tokens FROM usage_history_total WHERE scope = ''").get() as { calls: number; tokens: number };
    assert.deepEqual({ ...total() }, { calls: 1, tokens: 5 });
    db.prepare("UPDATE usage SET output=100 WHERE id='old-0'").run();
    assert.deepEqual({ ...total() }, { calls: 1, tokens: 5 }, "changes to an uncounted old row do not affect the new total");
    db.prepare("UPDATE usage SET output=10 WHERE id='new'").run();
    assert.deepEqual({ ...total() }, { calls: 1, tokens: 12 });
    db.prepare("DELETE FROM usage WHERE id='old-1'").run();
    assert.deepEqual({ ...total() }, { calls: 1, tokens: 12 });
    db.prepare("DELETE FROM usage WHERE id='new'").run();
    assert.deepEqual({ ...total() }, { calls: 0, tokens: 0 });
  } finally { store.close(); }
});
