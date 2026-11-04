import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { constants, DatabaseSync } from "node:sqlite";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { Effect } from "effect";
import { makeStore } from "../src/read/store.ts";
import { usage, usageHistory } from "../src/read/usage.ts";
import { Store } from "../src/store/store.ts";
import { installCompactUsage } from "../src/store/usage-compact.ts";
import { convertUsageHistoryStep, hasUsageHistory, historyTransferPending, installUsageHistory } from "../src/store/usage-history.ts";
import { moveHistoryOrphanScope } from "../src/store/usage-history-transfer.ts";
import { retireAfterPrevious, retireUntilComplete } from "../src/usage/module.ts";

function oldStore(path = ":memory:") {
  const store = Store.open(path);
  store.db.exec(`DROP TRIGGER usage_history_add; DROP TRIGGER usage_history_grow; DROP TRIGGER usage_history_move; DROP TRIGGER usage_history_drop;
    DROP TABLE usage_history; DROP TABLE usage_history_total; DROP TABLE usage_history_since;`);
  for (const [key, ws] of [["a", "A"], ["b", "B"]] as const)
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, ws, createdAt: 0, lastActiveAt: 0 });
  return store;
}

function sourceTotals(store: Store) {
  const db = store.db;
  const rows = db.prepare(`SELECT session, quarter, calls, tokens FROM usage_day_quarters
    UNION ALL SELECT session, CASE WHEN minute >= 0 THEN minute / 15 ELSE -1 - ((-1 - minute) / 15) END,
      calls, input + cache_read + cache_write + cache_write_long + output FROM usage_compact`).all() as
    { session: string; quarter: number; calls: number; tokens: number }[];
  const session = db.prepare("SELECT ws FROM sessions WHERE key = ?");
  const orphan = db.prepare("SELECT group_id FROM usage_history_orphans WHERE session = ?");
  const group = db.prepare("SELECT parent, scope FROM usage_history_owner_groups WHERE id = ?");
  const totals = new Map<string, { scope: string; quarter: number; calls: number; tokens: number }>();
  for (const row of rows) {
    const live = session.get(row.session) as { ws: string | null } | undefined;
    let scope = live?.ws ?? "";
    if (live === undefined) {
      let id = (orphan.get(row.session) as { group_id: number } | undefined)?.group_id;
      while (id !== undefined) {
        const owner = group.get(id) as { parent: number | null; scope: string };
        scope = owner.scope;
        id = owner.parent ?? undefined;
      }
    }
    const key = JSON.stringify([scope, row.quarter]);
    const total = totals.get(key) ?? { scope, quarter: row.quarter, calls: 0, tokens: 0 };
    total.calls += row.calls; total.tokens += row.tokens;
    totals.set(key, total);
  }
  return [...totals.values()].filter((row) => row.calls !== 0 || row.tokens !== 0)
    .sort((a, b) => a.scope.localeCompare(b.scope) || a.quarter - b.quarter);
}

test("the usage page can tell a pending history from one that is unavailable", () => {
  const store = oldStore();
  const db = store.db;
  try {
    db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES ('old', 0, 'a', 'claude', 2, 0, 0, 0, 1, 1)`).run();
    const read = () => usage(makeStore(db, "."), "en", 0n, 900_000n, 0n, false, null, true);
    assert.equal(read().historyPreparing, true, "history is also being prepared before its tables are installed");
    installCompactUsage(db, () => 900_000);
    installUsageHistory(db, 900_000);
    assert.equal(read().historyPreparing, true);
    while (!convertUsageHistoryStep(db)) { /* Transfer the old summaries. */ }
    const ready = read();
    assert.equal(ready.historyPreparing, undefined);
    assert.ok(ready.history);
  } finally { store.close(); }
});

test("a session deleted before history installation keeps its old usage in its workspace", () => {
  const store = oldStore();
  const db = store.db;
  try {
    db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES ('old', 0, 'a', 'claude', 2, 0, 0, 0, 1, 1)`).run();
    store.deleteSession("a");
    installCompactUsage(db, () => 900_000);
    installUsageHistory(db, 900_000);
    while (!convertUsageHistoryStep(db, 1)) { /* Take over the old summaries. */ }
    const mine = usageHistory(makeStore(db, "."), 0n, { workspace: "A", home: false });
    const home = usageHistory(makeStore(db, "."), 0n, { workspace: "home", home: true });
    assert.ok(mine);
    assert.ok(home);
    assert.deepEqual((mine.days as { calls: number; tokens: number }[]).map(({ calls, tokens }) => [calls, tokens]), [[1, 3]]);
    assert.deepEqual(home.days, []);
  } finally { store.close(); }
});

test("an older station can delete a session while the new station waits to install history", () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-history-previous-"));
  const path = join(dir, "station.db");
  const before = oldStore(path);
  before.db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
    VALUES ('old', 0, 'a', 'claude', 2, 0, 0, 0, 1, 1)`).run();
  before.close();
  const store = Store.open(path);
  const previous = new DatabaseSync(path);
  try {
    assert.equal(hasUsageHistory(store.db), false);
    // The older process does not know the new Store.deleteSession implementation.
    previous.prepare("DELETE FROM sessions WHERE key = 'a'").run();
    installCompactUsage(store.db, () => 900_000);
    installUsageHistory(store.db, 900_000);
    while (!convertUsageHistoryStep(store.db, 1)) { /* Take over the old summaries. */ }
    const result = usageHistory(makeStore(store.db, dir), 0n, { workspace: "A", home: false });
    const home = usageHistory(makeStore(store.db, dir), 0n, { workspace: "home", home: true });
    assert.ok(result);
    assert.ok(home);
    assert.deepEqual((result.days as { calls: number; tokens: number }[]).map(({ calls, tokens }) => [calls, tokens]), [[1, 3]]);
    assert.deepEqual(home.days, []);
  } finally { previous.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a deleted session follows its workspace move before history installation", () => {
  const store = oldStore();
  const db = store.db;
  try {
    db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES ('old', 0, 'a', 'claude', 2, 0, 0, 0, 1, 1)`).run();
    store.deleteSession("a");
    store.setSessionsWs("A", "C");
    store.insertSession({ key: "new-a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/new-a",
      token: "new-a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES ('new-a', 0, 'new-a', 'claude', 4, 0, 0, 0, 1, 1)`).run();
    installCompactUsage(db, () => 900_000);
    installUsageHistory(db, 900_000);
    while (!convertUsageHistoryStep(db, 1)) { /* Take over the old summaries. */ }
    const days = (workspace: string) => {
      const result = usageHistory(makeStore(db, "."), 0n, { workspace, home: false });
      assert.ok(result);
      return (result.days as { calls: number; tokens: number }[]).map(({ calls, tokens }) => [calls, tokens]);
    };
    assert.deepEqual(days("C"), [[1, 3]]);
    assert.deepEqual(days("A"), [[1, 5]], "the reused workspace name has only its own calls");
  } finally { store.close(); }
});

test("ownership also covers summaries installed after an earlier session was deleted", () => {
  const store = oldStore();
  const db = store.db;
  try {
    store.deleteSession("a"); // Owners are installed before compact statistics exist.
    installCompactUsage(db, () => 900_000);
    db.prepare(`INSERT INTO usage_compact (session, minute, thread, person, profile, runtime, model, fast, records,
      calls, input, cache_read, cache_write, cache_write_long, output, scope)
      VALUES ('b', 0, 0, '', '', 'claude', '', 0, 1, 1, 2, 0, 0, 0, 1, 'WB')`).run();
    store.deleteSession("b");
    installUsageHistory(db, 900_000);
    while (!convertUsageHistoryStep(db, 1)) { /* Take over the surviving summary. */ }
    const result = usageHistory(makeStore(db, "."), 0n, { workspace: "B", home: false });
    assert.ok(result);
    assert.deepEqual((result.days as { calls: number; tokens: number }[]).map(({ calls, tokens }) => [calls, tokens]), [[1, 3]]);
  } finally { store.close(); }
});

test("a failed owner move before installation rolls the live sessions back too", () => {
  const store = oldStore();
  const db = store.db;
  try {
    store.insertSession({ key: "live", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/live",
      token: "live", ws: "A", createdAt: 0, lastActiveAt: 0 });
    const put = db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES (?, 0, ?, 'claude', 2, 0, 0, 0, 1, 1)`);
    put.run("a", "a");
    put.run("b", "b");
    store.deleteSession("a");
    store.deleteSession("b");
    const groups = db.prepare("SELECT * FROM usage_history_owner_groups ORDER BY id").all();
    const scopes = db.prepare("SELECT * FROM usage_history_owner_scopes ORDER BY scope").all();
    db.setAuthorizer((action, table, column) => action === constants.SQLITE_UPDATE && table === "usage_history_owner_groups" && column === "parent"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    assert.throws(() => store.setSessionsWs("A", "B"));
    db.setAuthorizer(null);
    assert.equal(store.getSession("live")?.ws, "A");
    assert.deepEqual(db.prepare("SELECT * FROM usage_history_owner_groups ORDER BY id").all(), groups);
    assert.deepEqual(db.prepare("SELECT * FROM usage_history_owner_scopes ORDER BY scope").all(), scopes);
  } finally { db.setAuthorizer(null); store.close(); }
});

for (const moved of [false, true]) test(`a fresh station keeps later changes to a deleted session's usage (moved ${moved})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/a",
      token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES ('old', 0, 'a', 'claude', 2, 0, 0, 0, 1, 1)`).run();
    store.deleteSession("a");
    if (moved) store.setSessionsWs("A", "B");
    db.prepare("UPDATE usage SET output = 8 WHERE id = 'old'").run();
    const result = usageHistory(makeStore(db, "."), 0n, { workspace: moved ? "B" : "A", home: false });
    const home = usageHistory(makeStore(db, "."), 0n, { workspace: "home", home: true });
    assert.ok(result);
    assert.ok(home);
    assert.deepEqual((result.days as { calls: number; tokens: number }[]).map(({ calls, tokens }) => [calls, tokens]), [[1, 10]]);
    assert.deepEqual(home.days, []);
  } finally { store.close(); }
});

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

test("each conversion transaction reads and writes at most 256 old summary rows", () => {
  const store = oldStore();
  const db = store.db;
  try {
    const put = db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES (?, ?, 'a', 'claude', 2, 0, 0, 0, 1, 1)`);
    db.exec("BEGIN");
    for (let n = 0; n < 600; n++) put.run(`old-${n}`, n * 900_000);
    db.exec("COMMIT");
    installCompactUsage(db, () => 600 * 900_000);
    installUsageHistory(db, 600 * 900_000);
    const plan = db.prepare(`EXPLAIN QUERY PLAN SELECT * FROM usage_day_quarters
      WHERE (session, quarter, runtime, model) > (?, ?, ?, ?) ORDER BY session, quarter, runtime, model LIMIT ?`)
      .all("a", 0, "claude", "", 256) as { detail: string }[];
    assert.ok(plan.some((row) => /SEARCH usage_day_quarters USING PRIMARY KEY/.test(row.detail)), JSON.stringify(plan));
    assert.equal(convertUsageHistoryStep(db, 10_000), false);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_history").get() as { n: number }).n, 256);
    assert.deepEqual({ ...db.prepare("SELECT phase, q_session, q_quarter FROM usage_history_transfer").get() },
      { phase: 0, q_session: "a", q_quarter: 255 });
    assert.equal(convertUsageHistoryStep(db, 10_000), false);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_history").get() as { n: number }).n, 512);
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
    const told: boolean[] = [];
    const stop = store.subscribe((change) => { if (change.type === "usage") told.push(!historyTransferPending(store.db)); });
    try { await Effect.runPromise(retireAfterPrevious(store, Promise.resolve())); }
    finally { stop(); }
    assert.equal(historyTransferPending(store.db), false);
    assert.ok(told.includes(true), "the page is notified after the history becomes available");
    assert.deepEqual(store.db.prepare("SELECT scope, quarter, calls, tokens FROM usage_history ORDER BY scope, quarter")
      .all().map((r) => ({ ...r })), sourceTotals(store));
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a stopped conversion worker is retried without restarting the station", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-history-retry-worker-"));
  const store = oldStore(join(dir, "station.db"));
  try {
    store.db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES ('old', 0, 'a', 'claude', 2, 0, 0, 0, 1, 1)`).run();
    installCompactUsage(store.db, () => 900_000);
    installUsageHistory(store.db, 900_000);
    const worker = join(dir, "fail-once.mjs");
    const actual = new URL("../src/usage/retire-worker.ts", import.meta.url).href;
    writeFileSync(worker, `import { existsSync, writeFileSync } from "node:fs";\nimport { workerData } from "node:worker_threads";\n` +
      `const marker = workerData.path + ".failed-once";\nif (!existsSync(marker)) { writeFileSync(marker, ""); process.exit(1); }\n` +
      `await import(${JSON.stringify(actual)});\n`);
    await Effect.runPromise(retireUntilComplete(store, Promise.resolve(), pathToFileURL(worker)));
    assert.equal(historyTransferPending(store.db), false, "the pending conversion resumed after the worker failed");
    assert.deepEqual(store.db.prepare("SELECT scope, quarter, calls, tokens FROM usage_history ORDER BY scope, quarter")
      .all().map((r) => ({ ...r })), sourceTotals(store));
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a temporarily failed statistics installation is retried without restarting the station", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-history-retry-install-"));
  const store = oldStore(join(dir, "station.db"));
  try {
    store.db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES ('old', 0, 'a', 'claude', 2, 0, 0, 0, 1, 1)`).run();
    let denied = false;
    store.db.setAuthorizer((action, name) => {
      if (!denied && action === constants.SQLITE_CREATE_TABLE && name === "usage_compact") {
        denied = true;
        return constants.SQLITE_DENY;
      }
      return constants.SQLITE_OK;
    });
    await Effect.runPromise(retireUntilComplete(store, Promise.resolve()));
    assert.equal(denied, true);
    assert.equal(hasUsageHistory(store.db), true, "statistics became available after the transient failure");
    assert.equal(historyTransferPending(store.db), false);
    assert.deepEqual(store.db.prepare("SELECT scope, quarter, calls, tokens FROM usage_history ORDER BY scope, quarter")
      .all().map((r) => ({ ...r })), sourceTotals(store));
  } finally { store.db.setAuthorizer(null); store.close(); rmSync(dir, { recursive: true, force: true }); }
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

test("a deleted session's usage change during a workspace move stays with the moved history", () => {
  const store = oldStore();
  const db = store.db;
  try {
    db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES ('old', 0, 'a', 'claude', 2, 0, 0, 0, 1, 1)`).run();
    installCompactUsage(db, () => 900_000);
    installUsageHistory(db, 900_000);
    while (!convertUsageHistoryStep(db, 1)) { /* Convert old summaries. */ }
    store.deleteSession("a");
    // The callback stands for a later write arriving between copying and removing the old workspace's history.
    db.exec(`CREATE TEMP TRIGGER move_usage_during_history_copy AFTER INSERT ON main.usage_history
      WHEN NEW.scope = 'C' BEGIN UPDATE usage SET output = 8 WHERE id = 'old'; END`);
    store.setSessionsWs("A", "C");
    db.exec("DROP TRIGGER move_usage_during_history_copy");
    assert.deepEqual(db.prepare("SELECT scope, calls, tokens FROM usage_history WHERE calls != 0 OR tokens != 0").all().map((r) => ({ ...r })),
      [{ scope: "C", calls: 1, tokens: 10 }]);
  } finally { store.close(); }
});

test("a deleted session keeps its workspace while its old summaries are still converting", () => {
  const store = oldStore();
  const db = store.db;
  try {
    const put = db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES (?, ?, 'a', 'claude', 2, 0, 0, 0, 1, 1)`);
    put.run("old", 0); put.run("later", 900_000);
    installCompactUsage(db, () => 1_800_000);
    put.run("compact", 1_800_000);
    installUsageHistory(db, 2_700_000);
    assert.equal(convertUsageHistoryStep(db, 1), false);
    store.deleteSession("a");
    db.exec(`CREATE TEMP TRIGGER move_usage_during_history_copy AFTER INSERT ON main.usage_history
      WHEN NEW.scope = 'C' BEGIN UPDATE usage SET output = 8 WHERE id = 'old'; END`);
    store.setSessionsWs("A", "C");
    db.exec("DROP TRIGGER move_usage_during_history_copy");
    while (!convertUsageHistoryStep(db, 1)) { /* Complete the remaining summaries. */ }
    assert.deepEqual(db.prepare("SELECT scope, quarter, calls, tokens FROM usage_history WHERE calls != 0 OR tokens != 0 ORDER BY scope, quarter")
      .all().map((r) => ({ ...r })), [
      { scope: "C", quarter: 0, calls: 1, tokens: 10 },
      { scope: "C", quarter: 1, calls: 1, tokens: 3 },
      { scope: "C", quarter: 2, calls: 1, tokens: 3 },
    ]);
  } finally { store.close(); }
});

test("moving a workspace does not rewrite each deleted session's owner", () => {
  const store = oldStore();
  const db = store.db;
  try {
    const put = db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES (?, 0, ?, 'claude', 2, 0, 0, 0, 1, 1)`);
    for (let n = 0; n < 300; n++) {
      const key = `deleted-${n}`;
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, ws: "A", createdAt: 0, lastActiveAt: 0 });
      put.run(key, key);
    }
    installCompactUsage(db, () => 900_000);
    installUsageHistory(db, 900_000);
    while (!convertUsageHistoryStep(db)) { /* Convert old summaries. */ }
    for (let n = 0; n < 300; n++) store.deleteSession(`deleted-${n}`);
    db.exec(`CREATE TEMP TABLE moved_owners (n INTEGER);
      CREATE TEMP TRIGGER count_moved_owner AFTER UPDATE ON main.usage_history_orphans BEGIN INSERT INTO moved_owners VALUES (1); END`);
    store.setSessionsWs("A", "C");
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM moved_owners").get() as { n: number }).n, 0);
    assert.deepEqual({ ...db.prepare("SELECT calls, tokens FROM usage_history WHERE scope = 'C'").get() }, { calls: 300, tokens: 900 });
  } finally { store.close(); }
});

test("deleted sessions follow repeated workspace merges, including reused workspace names", () => {
  const store = oldStore();
  const db = store.db;
  try {
    const put = db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES (?, 0, ?, 'claude', 2, 0, 0, 0, 1, 1)`);
    for (let n = 0; n < 16; n++) {
      const key = `owner-${n}`;
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, ws: `S${n}`, createdAt: 0, lastActiveAt: 0 });
      put.run(key, key);
    }
    installCompactUsage(db, () => 900_000);
    installUsageHistory(db, 900_000);
    while (!convertUsageHistoryStep(db)) { /* Convert old summaries. */ }
    for (let n = 0; n < 16; n++) store.deleteSession(`owner-${n}`);
    for (let size = 1; size < 16; size *= 2)
      for (let n = 0; n < 16; n += 2 * size) store.setSessionsWs(`S${n + size - 1}`, `S${n + 2 * size - 1}`);

    store.insertSession({ key: "reused", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "reused", ws: "S0", createdAt: 0, lastActiveAt: 0 });
    put.run("reused", "reused");
    store.deleteSession("reused");
    store.setSessionsWs("S15", "S0");
    store.insertSession({ key: "later", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "later", ws: "S16", createdAt: 0, lastActiveAt: 0 });
    put.run("later", "later");
    store.deleteSession("later");
    store.setSessionsWs("S16", "S0");
    db.prepare("UPDATE usage SET output = 8 WHERE id = 'owner-0'").run();
    assert.deepEqual(db.prepare("SELECT scope, quarter, calls, tokens FROM usage_history WHERE calls != 0 OR tokens != 0 ORDER BY scope, quarter")
      .all().map((r) => ({ ...r })), [{ scope: "S0", quarter: 0, calls: 18, tokens: 61 }]);
    const depth = db.prepare(`WITH RECURSIVE chain(id, parent, depth) AS (
      SELECT id, parent, 0 FROM usage_history_owner_groups
      UNION ALL SELECT chain.id, g.parent, chain.depth + 1 FROM chain JOIN usage_history_owner_groups g ON g.id = chain.parent
    ) SELECT MAX(depth) AS n FROM chain`).get() as { n: number };
    assert.ok(depth.n <= 5, "repeated moves keep owner lookup shallow");
  } finally { store.close(); }
});

test("a failed deleted-owner merge rolls its group changes back", () => {
  const store = oldStore();
  const db = store.db;
  try {
    const put = db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES (?, 0, ?, 'claude', 2, 0, 0, 0, 1, 1)`);
    put.run("one", "a"); put.run("two", "b");
    installCompactUsage(db, () => 900_000);
    installUsageHistory(db, 900_000);
    while (!convertUsageHistoryStep(db)) { /* Convert old summaries. */ }
    store.deleteSession("a"); store.deleteSession("b");
    const groups = db.prepare("SELECT * FROM usage_history_owner_groups ORDER BY id").all();
    const scopes = db.prepare("SELECT * FROM usage_history_owner_scopes ORDER BY scope").all();
    db.setAuthorizer((action, table, column) => action === constants.SQLITE_UPDATE && table === "usage_history_owner_groups" && column === "parent"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.throws(() => moveHistoryOrphanScope(db, "A", "B")); }
    finally { db.setAuthorizer(null); }
    assert.deepEqual(db.prepare("SELECT * FROM usage_history_owner_groups ORDER BY id").all(), groups);
    assert.deepEqual(db.prepare("SELECT * FROM usage_history_owner_scopes ORDER BY scope").all(), scopes);
    moveHistoryOrphanScope(db, "A", "B");
  } finally { db.setAuthorizer(null); store.close(); }
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
