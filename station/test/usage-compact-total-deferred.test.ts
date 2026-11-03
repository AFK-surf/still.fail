import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import * as compact from "../src/store/usage-compact.ts";
import { Store } from "../src/store/store.ts";
import { retireUsageIndexes } from "../src/store/usage-retire.ts";
import { watchCompactMoves } from "../src/usage/module.ts";

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

test("pending deletions stay invisible and only the affected scope waits", () => {
  const store = Store.open(":memory:");
  try {
    for (const ws of ["A", "B"]) store.insertSession({ key: ws, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w",
      token: ws, ws, createdAt: 0, lastActiveAt: 0 });
    compact.installCompactUsage(store.db, () => store.now());
    retireUsageIndexes(store.db);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string) => ({ id, at: 0, model: "m", subagent: true, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null });
    for (const ws of ["A", "B"]) store.recordUsage(`/${ws}`, { session: ws, offset: 1, model: "m" }, "claude", [[call(ws), owner]]);
    assert.equal(compact.compactTotalsStep(store.db, 8).done, true);
    store.db.prepare("DELETE FROM usage WHERE id = ?").run("A");
    assert.equal(compact.compactTotal(store.db, { workspace: "A", home: false }), null);
    assert.equal(compact.compactTotal(store.db, null), null);
    assert.deepEqual(compact.compactTotal(store.db, { workspace: "B", home: false }), { calls: 1, tokens: 2 });
    assert.deepEqual(compact.compactHistory(store.db, 0n, { workspace: "A", home: false }), []);
    const query = compact.compactQuery(0n, 60_000n, 0n, { workspace: "A", home: false });
    assert.deepEqual(store.db.prepare(query.sql).all(...query.args), []);
    // A replacement in the same minute keeps the old contribution until the bucket can be accounted once.
    store.recordUsage("/A", { session: "A", offset: 2, model: "m" }, "claude", [[call("replacement"), owner]]);
    assert.equal(compact.compactTotalsStep(store.db, 8).done, true);
    assert.deepEqual(compact.compactTotal(store.db, null), { calls: 2, tokens: 4 });
    store.db.prepare("DELETE FROM usage WHERE id = ?").run("replacement");
    assert.equal(compact.compactTotalsStep(store.db, 8).done, true);
    assert.deepEqual(compact.compactTotal(store.db, null), { calls: 1, tokens: 2 });
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM usage_compact WHERE session = 'A'").get() as { n: number }).n, 0);
  } finally { store.close(); }
});

test("a worker completes pending totals after new calls and tells the page", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "compact-total-worker-"));
  const store = Store.open(join(dir, "station.db"));
  let mover: ReturnType<typeof watchCompactMoves> | null = null;
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A",
      createdAt: 0, lastActiveAt: 0 });
    compact.installCompactUsage(store.db, () => store.now());
    retireUsageIndexes(store.db);
    mover = watchCompactMoves(store, Promise.resolve());
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string) => ({ id, at: 0, model: "m", subagent: true, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null });
    const ready = (calls: number) => new Promise<void>((resolve, reject) => {
      const abort = () => { unsubscribe(); reject(t.signal.reason); };
      const unsubscribe = store.subscribe((change) => {
        if (change.type !== "usage" || !change.sessions.includes("a") || change.from !== 0) return;
        if (compact.compactTotal(store.db, { workspace: "A", home: false })?.calls !== calls) return;
        unsubscribe();
        t.signal.removeEventListener("abort", abort);
        resolve();
      });
      t.signal.addEventListener("abort", abort, { once: true });
    });
    for (let n = 1; n <= 2; n++) {
      const told = ready(n);
      store.recordUsage("/a", { session: "a", offset: n, model: "m" }, "claude", [[call(`call-${n}`), owner]]);
      store.usageChanged(["a"]);
      await told;
      assert.deepEqual(compact.compactTotal(store.db, { workspace: "A", home: false }), { calls: n, tokens: n * 2 });
    }
  } finally {
    if (mover !== null) await mover.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
