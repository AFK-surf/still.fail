import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { makeStore } from "../src/read/store.ts";
import { usageHistory } from "../src/read/usage.ts";
import { Store } from "../src/store/store.ts";
import { ensureHistoryOwners, installUsageHistory } from "../src/store/usage-history.ts";
import { HISTORY_MOVE_ROWS, hasHistoryMoves, historyMovesPending, moveHistoryStep } from "../src/store/usage-history-moves.ts";
import { watchCompactMoves } from "../src/usage/module.ts";

function session(store: Store, key: string, ws: string) {
  store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`,
    token: key, ws, createdAt: 0, lastActiveAt: 0 });
}

function record(store: Store, id: string, session: string, input: number) {
  store.db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
    VALUES (?, 0, ?, 'claude', ?, 0, 0, 0, 1, 1)`).run(id, session, input);
}

test("a fresh history installed after an early deletion can move its later calls", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`DROP TRIGGER usage_history_add; DROP TRIGGER usage_history_grow; DROP TRIGGER usage_history_move; DROP TRIGGER usage_history_drop;
      DROP TABLE usage_history; DROP TABLE usage_history_total; DROP TABLE usage_history_since;`);
    session(store, "empty", "A");
    store.deleteSession("empty"); // Owners exist before history, but there are no calls or old summaries.
    installUsageHistory(db, 0);
    session(store, "a", "A");
    record(store, "a", "a", 2);
    store.setSessionsWs("A", "B");
    const result = usageHistory(makeStore(db, "."), 0n, { workspace: "B", home: false });
    assert.ok(result);
    assert.deepEqual((result.days as { calls: number; tokens: number }[]).map(({ calls, tokens }) => [calls, tokens]), [[1, 3]]);
  } finally { store.close(); }
});

test("moving a workspace with no history does not install routing on every future call", () => {
  const store = Store.open(":memory:");
  try {
    session(store, "a", "A");
    store.setSessionsWs("A", "B");
    assert.equal(hasHistoryMoves(store.db), false);
    record(store, "new", "a", 2);
    const destination = usageHistory(makeStore(store.db, "."), 0n, { workspace: "B", home: false });
    const former = usageHistory(makeStore(store.db, "."), 0n, { workspace: "A", home: false });
    assert.ok(destination);
    assert.ok(former);
    assert.deepEqual((destination.days as { calls: number; tokens: number }[]).map(({ calls, tokens }) => [calls, tokens]), [[1, 3]]);
    assert.deepEqual(former.days, []);
  } finally { store.close(); }
});

test("a failed workspace move does not leave sessions and usage in different workspaces", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    session(store, "a", "A");
    session(store, "b", "B");
    record(store, "a", "a", 2);
    record(store, "b", "b", 4);
    const before = db.prepare("SELECT scope, quarter, calls, tokens FROM usage_history ORDER BY scope, quarter").all();
    db.setAuthorizer((action, table) => action === constants.SQLITE_DELETE && table === "usage_history"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    let failed = false;
    try { store.setSessionsWs("A", "B"); } catch { failed = true; }
    finally { db.setAuthorizer(null); }

    if (failed) {
      assert.equal(store.getSession("a")?.ws, "A");
      assert.deepEqual(db.prepare("SELECT scope, quarter, calls, tokens FROM usage_history ORDER BY scope, quarter").all(), before);
    } else {
      assert.equal(store.getSession("a")?.ws, "B");
      const history = usageHistory(makeStore(db, "."), 0n, { workspace: "B", home: false });
      if (history !== null) {
        assert.deepEqual((history.days as { calls: number; tokens: number }[]).map(({ calls, tokens }) => [calls, tokens]), [[2, 8]]);
      }
    }
  } finally { db.setAuthorizer(null); store.close(); }
});

test("moving a workspace does bounded history work before returning", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    session(store, "a", "A");
    db.exec(`WITH RECURSIVE quarters(n) AS (VALUES (0) UNION ALL SELECT n + 1 FROM quarters WHERE n < 1023)
      INSERT INTO usage_history (scope, quarter, calls, tokens) SELECT 'A', n, 1, 2 FROM quarters;
      CREATE TEMP TABLE history_move_writes (n INTEGER);
      CREATE TEMP TRIGGER history_move_insert AFTER INSERT ON main.usage_history BEGIN INSERT INTO history_move_writes VALUES (1); END;
      CREATE TEMP TRIGGER history_move_update AFTER UPDATE ON main.usage_history BEGIN INSERT INTO history_move_writes VALUES (1); END;
      CREATE TEMP TRIGGER history_move_delete AFTER DELETE ON main.usage_history BEGIN INSERT INTO history_move_writes VALUES (1); END;`);
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${HISTORY_MOVE_ROWS}`)
      .all("A", 256) as { detail: string }[];
    assert.ok(plan.some((row) => /SEARCH usage_history USING PRIMARY KEY \(scope=\?\)/.test(row.detail)), JSON.stringify(plan));
    store.setSessionsWs("A", "B");
    const writes = (db.prepare("SELECT count(*) AS n FROM history_move_writes").get() as { n: number }).n;
    assert.ok(writes <= 256, `moving the workspace wrote ${writes} history rows before returning`);
    const history = usageHistory(makeStore(db, "."), 0n, { workspace: "B", home: false });
    if (history !== null) {
      assert.equal((history.days as { calls: number }[]).reduce((sum, day) => sum + day.calls, 0), 1_024);
    }
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`pending history follows repeated moves while the old workspace name is reused (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? 1 : 0}`);
    session(store, "a", "A");
    session(store, "b", "B");
    record(store, "a", "a", 2);
    record(store, "b", "b", 4);
    db.exec(`WITH RECURSIVE quarters(n) AS (VALUES (1) UNION ALL SELECT n + 1 FROM quarters WHERE n < 300)
      INSERT INTO usage_history (scope, quarter, calls, tokens) SELECT 'A', n, 1, 2 FROM quarters`);
    db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES ('late', ?, 'a', 'claude', 9, 0, 0, 0, 1, 1)`).run(250 * 900_000);
    store.setSessionsWs("A", "B");
    assert.equal(historyMovesPending(db, ["B"]), true);
    assert.equal(usageHistory(makeStore(db, "."), 0n, { workspace: "B", home: false }), null);

    session(store, "new-a", "A");
    record(store, "new-a", "new-a", 6);
    store.setSessionsWs("B", "C");
    db.prepare("UPDATE usage SET output = 8 WHERE id = 'a'").run();
    db.prepare("UPDATE usage SET output = 8 WHERE id = 'late'").run();
    assert.equal(historyMovesPending(db, ["C"]), true);
    const sum = (scope: string | null) => {
      const h = usageHistory(makeStore(db, "."), 0n, scope === null ? null : { workspace: scope, home: false });
      assert.ok(h);
      return (h.days as { calls: number; tokens: number }[]).reduce(([calls, tokens], day) => [calls + day.calls, tokens + day.tokens], [0, 0]);
    };
    assert.deepEqual(sum("A"), [1, 7], "the reused source sees only its new call");
    let steps = 0;
    while (historyMovesPending(db)) {
      moveHistoryStep(db, 17);
      assert.ok(++steps < 100, "the remaining partitions make progress");
    }
    assert.deepEqual(sum("C"), [303, 632]);
    assert.deepEqual(sum("B"), [0, 0]);
    assert.deepEqual(sum("A"), [1, 7]);
    assert.deepEqual(sum(null), [304, 639]);
  } finally { store.close(); }
});

test("failure to redirect history rolls the session move back", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    session(store, "a", "A");
    record(store, "a", "a", 2);
    db.setAuthorizer((action, table) => action === constants.SQLITE_CREATE_TABLE && table === "usage_history_move_groups"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    assert.throws(() => store.setSessionsWs("A", "B"));
    db.setAuthorizer(null);
    assert.equal(store.getSession("a")?.ws, "A");
    const h = usageHistory(makeStore(db, "."), 0n, { workspace: "A", home: false });
    assert.ok(h);
    assert.deepEqual((h.days as { calls: number; tokens: number }[]).map(({ calls, tokens }) => [calls, tokens]), [[1, 3]]);
  } finally { db.setAuthorizer(null); store.close(); }
});

test("a history read does not return a workspace's data after it moves during the read", () => {
  const store = Store.open(":memory:");
  try {
    session(store, "a", "A");
    record(store, "a", "a", 2);
    let moved = false;
    const result = usageHistory(makeStore(store.db, "."), 0n, { workspace: "A", home: false }, (stage) => {
      if (stage === "historyDays" && !moved) { moved = true; store.setSessionsWs("A", "B"); }
    });
    assert.equal(moved, true);
    assert.equal(result, null, "the old workspace's result is discarded after its history moves");
  } finally { store.close(); }
});

test("an empty history move also invalidates a read in progress", () => {
  const store = Store.open(":memory:");
  try {
    session(store, "a", "A");
    let moved = false;
    const result = usageHistory(makeStore(store.db, "."), 0n, { workspace: "A", home: false }, (stage) => {
      if (stage === "historyDays" && !moved) { moved = true; store.setSessionsWs("A", "B"); }
    });
    assert.equal(moved, true);
    assert.equal(hasHistoryMoves(store.db), false);
    assert.equal(result, null);
  } finally { store.close(); }
});

test("a failed history move batch rolls back all its changes and can be retried", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    session(store, "a", "A");
    db.exec(`WITH RECURSIVE quarters(n) AS (VALUES (0) UNION ALL SELECT n + 1 FROM quarters WHERE n < 399)
      INSERT INTO usage_history (scope, quarter, calls, tokens) SELECT 'A', n, 1, 2 FROM quarters`);
    store.setSessionsWs("A", "B");
    const contents = () => ({
      rows: db.prepare("SELECT scope, quarter, calls, tokens FROM usage_history ORDER BY scope, quarter").all(),
      totals: db.prepare("SELECT scope, calls, tokens FROM usage_history_total ORDER BY scope").all(),
      pending: db.prepare("SELECT source, group_id FROM usage_history_moving ORDER BY source").all(),
    });
    const before = contents();
    db.exec(`CREATE TEMP TRIGGER fail_history_move BEFORE DELETE ON main.usage_history
      WHEN OLD.quarter = 136 BEGIN SELECT RAISE(ABORT, 'injected failure'); END`);
    assert.throws(() => moveHistoryStep(db, 16), /injected failure/);
    assert.deepEqual(contents(), before, "even the rows moved before the failed deletion were rolled back");
    db.exec("DROP TRIGGER fail_history_move");
    while (historyMovesPending(db)) moveHistoryStep(db, 16);
    const result = usageHistory(makeStore(db, "."), 0n, { workspace: "B", home: false });
    assert.ok(result);
    assert.equal((result.days as { calls: number }[]).reduce((sum, day) => sum + day.calls, 0), 400);
  } finally { store.close(); }
});

test("a restarted station finishes a pending history move and tells the usage page", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "usage-history-move-"));
  const path = join(dir, "station.db");
  let store = Store.open(path);
  let mover: ReturnType<typeof watchCompactMoves> | null = null;
  try {
    session(store, "a", "A");
    store.db.exec(`WITH RECURSIVE quarters(n) AS (VALUES (0) UNION ALL SELECT n + 1 FROM quarters WHERE n < 399)
      INSERT INTO usage_history (scope, quarter, calls, tokens) SELECT 'A', n, 1, 2 FROM quarters`);
    store.setSessionsWs("A", "B");
    assert.equal(historyMovesPending(store.db, ["B"]), true);
    store.close();
    store = Store.open(path);
    assert.equal(historyMovesPending(store.db, ["B"]), true);
    const told = new Promise<void>((resolve, reject) => {
      const abort = () => { unsubscribe(); reject(t.signal.reason); };
      const unsubscribe = store.subscribe((change) => {
        if (change.type !== "usage" || !change.statisticsOnly || historyMovesPending(store.db, ["B"])) return;
        unsubscribe();
        t.signal.removeEventListener("abort", abort);
        resolve();
      });
      t.signal.addEventListener("abort", abort, { once: true });
    });
    mover = watchCompactMoves(store, Promise.resolve());
    await told;
    const result = usageHistory(makeStore(store.db, dir), 0n, { workspace: "B", home: false });
    assert.ok(result);
    assert.equal((result.days as { calls: number }[]).reduce((sum, day) => sum + day.calls, 0), 400);
  } finally {
    if (mover !== null) await mover.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

for (const moved of [false, true]) test(`a fresh station keeps a deleted session's later usage in its workspace (moved ${moved})`, () => {
  const store = Store.open(":memory:");
  try {
    session(store, "a", "A");
    record(store, "a", "a", 2);
    store.deleteSession("a");
    if (moved) store.setSessionsWs("A", "B");
    store.db.prepare("UPDATE usage SET output = 8 WHERE id = 'a'").run();
    const scope = moved ? "B" : "A";
    const result = usageHistory(makeStore(store.db, "."), 0n, { workspace: scope, home: false });
    const home = usageHistory(makeStore(store.db, "."), 0n, { workspace: "home", home: true });
    assert.ok(result);
    assert.ok(home);
    assert.deepEqual((result.days as { calls: number; tokens: number }[]).map(({ calls, tokens }) => [calls, tokens]), [[1, 10]]);
    assert.deepEqual(home.days, [], "a deleted session does not put later changes in the home workspace");
  } finally { store.close(); }
});

test("a session deleted during a fresh history move keeps later updates with its destination", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    session(store, "a", "A");
    db.exec(`WITH RECURSIVE quarters(n) AS (VALUES (0) UNION ALL SELECT n + 1 FROM quarters WHERE n < 299)
      INSERT INTO usage_history (scope, quarter, calls, tokens) SELECT 'A', n, 1, 2 FROM quarters`);
    db.prepare(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output, calls)
      VALUES ('late', ?, 'a', 'claude', 2, 0, 0, 0, 1, 1)`).run(250 * 900_000);
    store.setSessionsWs("A", "B");
    assert.equal(historyMovesPending(db, ["B"]), true);
    store.deleteSession("a");
    db.prepare("UPDATE usage SET output = 8 WHERE id = 'late'").run();
    while (historyMovesPending(db)) moveHistoryStep(db, 17);
    const result = usageHistory(makeStore(db, "."), 0n, { workspace: "B", home: false });
    const home = usageHistory(makeStore(db, "."), 0n, { workspace: "home", home: true });
    assert.ok(result);
    assert.ok(home);
    assert.deepEqual((result.days as { calls: number; tokens: number }[]).reduce(
      ([calls, tokens], day) => [calls + day.calls, tokens + day.tokens], [0, 0]), [301, 610]);
    assert.deepEqual(home.days, []);
  } finally { store.close(); }
});

test("establishing owners for an existing history does not read its calls", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    session(store, "a", "A");
    db.exec("BEGIN");
    for (let n = 0; n < 250; n++) record(store, `call-${n}`, "a", 2);
    db.exec("COMMIT");
    const plan = db.prepare("EXPLAIN QUERY PLAN SELECT 1 FROM usage INDEXED BY usage_session WHERE session = ? LIMIT 1")
      .all("a") as { detail: string }[];
    assert.ok(plan.some((row) => /SEARCH usage USING COVERING INDEX usage_session/.test(row.detail)), JSON.stringify(plan));
    db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      db.exec("BEGIN IMMEDIATE");
      ensureHistoryOwners(db);
      db.exec("COMMIT");
    } finally { db.setAuthorizer(null); }
    store.deleteSession("a");
    db.prepare("UPDATE usage SET output = 8 WHERE id = 'call-0'").run();
    const result = usageHistory(makeStore(db, "."), 0n, { workspace: "A", home: false });
    assert.ok(result);
    assert.deepEqual((result.days as { calls: number; tokens: number }[]).map(({ calls, tokens }) => [calls, tokens]), [[250, 757]]);
  } finally { db.setAuthorizer(null); store.close(); }
});
