import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants, DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { makeStore, sessionUsages } from "../src/read/store.ts";
import { addUsageColumns, addUsageCompactions, addUsageQuarters, addUsageTotals } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";
import { installIncrementalUsageTotals } from "../src/store/usage-detail.ts";

function oldUsage(withColumns = true): DatabaseSync {
  const db = new DatabaseSync(":memory:");
  db.exec(`CREATE TABLE usage (id TEXT PRIMARY KEY, at INTEGER NOT NULL, session TEXT NOT NULL, thread INTEGER,
    person TEXT, profile TEXT, runtime TEXT NOT NULL, model TEXT, subagent INTEGER NOT NULL DEFAULT 0,
    fast INTEGER NOT NULL DEFAULT 0, input INTEGER NOT NULL, cache_read INTEGER NOT NULL, cache_write INTEGER NOT NULL,
    cache_write_long INTEGER NOT NULL, output INTEGER NOT NULL${withColumns ? ", calls INTEGER NOT NULL DEFAULT 1, context INTEGER, context_window INTEGER" : ""});
    CREATE INDEX usage_session ON usage (session, at);
    INSERT INTO usage (id, at, session, runtime, model, input, cache_read, cache_write, cache_write_long, output)
      VALUES ('old', 1, 's', 'claude', 'm', 5, 0, 0, 0, 1);`);
  return db;
}

test("the incremental source for missing totals installs without reading old calls", () => {
  const db = oldUsage();
  try {
    db.exec("CREATE TABLE sessions (key TEXT PRIMARY KEY, ws TEXT, token TEXT UNIQUE)");
    addUsageTotals(db);
    db.setAuthorizer((action, table, column) => table === "usage" &&
      (action === constants.SQLITE_UPDATE || (action === constants.SQLITE_READ && column !== "" && column !== null))
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { installIncrementalUsageTotals(db); }
    finally { db.setAuthorizer(null); }
    assert.deepEqual(db.prepare("SELECT * FROM usage_totals_source").all(), []);
  } finally { db.close(); }
});

for (const [name, upgrade, withColumns] of [
  ["columns", addUsageColumns, false],
  ["session totals", addUsageTotals, true],
  ["quarter totals", addUsageQuarters, true],
  ["compactions", addUsageCompactions, true],
] as const) {
  test(`an old database installs ${name} without reading or rewriting old calls`, () => {
    const db = oldUsage(withColumns);
    try {
      db.setAuthorizer((action, table, column) => table === "usage" &&
        (action === constants.SQLITE_UPDATE || (action === constants.SQLITE_READ && column !== "" && column !== null))
        ? constants.SQLITE_DENY : constants.SQLITE_OK);
      try { upgrade(db); }
      finally { db.setAuthorizer(null); }
      assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage").get() as { n: number }).n, 1);
    } finally { db.close(); }
  });
}

test("a missing old session total keeps only new writes and never presents them as a complete old total", () => {
  for (const detail of ["complete", "missing"] as const) for (const recursive of ["OFF", "ON"] as const) {
    const dir = mkdtempSync(join(tmpdir(), "usage-old-totals-"));
    const path = join(dir, "stillfail.db");
    let store = Store.open(path);
    const owner = { turn: null, person: null, thread: null, profile: "cc" };
    const call = (id: string, at: number, input: number, output: number) => [{ id, at, model: "m", subagent: false,
      fast: false, input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output, calls: 1, context: null, window: null }, owner] as const;
    try {
      store.insertSession({ key: "old", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "old", ws: "A", createdAt: 1, lastActiveAt: 1 });
      store.recordUsage("/old", { session: "old", offset: 1, model: null }, "claude", [call("before", 100, 10, 2)] as never);
      store.setSessionUsage("old", { modelCalls: 1, inputTokens: 10 });
      store.db.exec("DROP TRIGGER usage_totals_add; DROP TRIGGER usage_totals_drop; DROP TRIGGER usage_totals_grow; DROP TABLE usage_totals");
      if (detail === "missing") {
        const objects = store.db.prepare("SELECT type, name FROM sqlite_master WHERE (name LIKE 'usage_detail_%' OR name = 'usage_detail') AND type IN ('trigger', 'table') ORDER BY type DESC").all() as { type: string; name: string }[];
        for (const object of objects) store.db.exec(`DROP ${object.type.toUpperCase()} "${object.name}"`);
      }
      store.close();
      store = Store.open(path);
      store.db.exec(`PRAGMA recursive_triggers = ${recursive}`);
      assert.deepEqual(store.db.prepare("SELECT * FROM usage_totals").all(), [], "the old call was not aggregated");
      assert.equal(store.sessionUsage("old"), null);
      assert.equal(sessionUsages(makeStore(store.db, dir), "old").size, 0);
      store.recordUsage("/old", { session: "old", offset: 2, model: null }, "claude", [call("after", 200, 3, 4)] as never);
      store.db.exec("UPDATE usage SET output = 9 WHERE id = 'before'; INSERT OR REPLACE INTO usage SELECT * FROM usage WHERE id = 'before'; DELETE FROM usage WHERE id = 'before'; INSERT OR REPLACE INTO usage SELECT * FROM usage WHERE id = 'after'");
      assert.deepEqual(store.db.prepare("SELECT calls, input, output FROM usage_totals WHERE session = 'old'").all().map((r) => [r.calls, r.input, r.output]), [[1, 3, 4]], `${detail}, recursive ${recursive}`);
      assert.deepEqual(store.usageOfSession("old"), [], "an incomplete old session total is not presented as complete");
      store.insertSession({ key: "new", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "new", ws: "A", createdAt: 2, lastActiveAt: 2 });
      store.recordUsage("/new", { session: "new", offset: 1, model: null }, "claude", [call("new", 300, 7, 5)] as never);
      assert.deepEqual(store.usageOfSession("new").map((g) => [g.calls, g.input, g.output]), [[1, 7, 5]]);
      store.setSessionUsage("new", { modelCalls: 1, inputTokens: 7 });
      assert.equal(sessionUsages(makeStore(store.db, dir), "new").size, 1);
      store.close();
      store = Store.open(path);
      assert.deepEqual(store.usageOfSession("new").map((g) => [g.calls, g.input, g.output]), [[1, 7, 5]]);
      assert.equal(store.sessionUsage("old"), null);
    } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
  }
});
