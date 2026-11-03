import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { makeStore } from "../src/read/store.ts";
import { usage } from "../src/read/usage.ts";
import * as compact from "../src/store/usage-compact.ts";
import { Store } from "../src/store/store.ts";
import { retireUsageIndexes } from "../src/store/usage-retire.ts";

const a = { workspace: "A", home: false };
const b = { workspace: "B", home: false };
const home = { workspace: "A", home: true };

function account(store: Store): void {
  for (let i = 0; i < 100; i++) if (compact.compactTotalsStep(store.db, 2).done) return;
  assert.fail("compact totals did not finish in bounded batches");
}

test("a year's usage view reads only its requested days but keeps the all-time total", () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws] of [["a", "A"], ["b", "B"]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, ws,
        createdAt: 0, lastActiveAt: 0 });
    }
    compact.installCompactUsage(store.db, () => store.now());
    retireUsageIndexes(store.db);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number, input: number) => ({ id, at, model: "m", subagent: true, fast: false,
      input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null });
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [
      [call("old", -86_400_000, 10), owner], [call("new", 60_000, 19), owner], [call("future", 86_400_000, 6), owner],
    ]);
    store.recordUsage("/b", { session: "b", offset: 1, model: "m" }, "claude", [[call("other", 60_000, 999), owner]]);
    const pending = usage(makeStore(store.db, "."), "en", 0n, 86_400_000n, 0n, false, a, true,
      { historyRange: { from: 0n, to: 86_400_000n } });
    assert.equal(pending.historyPending, true, "a page missing an unprocessed total knows to retry it");
    account(store);
    const limited = compact.compactHistory(store.db, 0n, a, false, { from: 0n, to: 1_440n });
    assert.deepEqual(limited?.map((d) => [d.day, d.tokens]), [["1970-01-01", 20]]);
    assert.deepEqual(compact.compactTotal(store.db, a, 1_440n), { calls: 2, tokens: 31 });
    assert.deepEqual(compact.compactTotal(store.db, b, 1_440n), { calls: 1, tokens: 1_000 });
    assert.deepEqual(compact.compactTotal(store.db, a, 0n), { calls: 1, tokens: 11 });
    assert.deepEqual(compact.compactTotal(store.db, a, -1_440n), { calls: 0, tokens: 0 });
    const answer = usage(makeStore(store.db, "."), "en", 0n, 86_400_000n, 0n, false, a, true,
      { historyRange: { from: 0n, to: 86_400_000n } });
    assert.deepEqual(answer.history.days.map((d: { day: string; tokens: number }) => [d.day, d.tokens]), [["1970-01-01", 20]]);
    assert.equal(answer.history.tokens, 31, "the older day remains in the total, while tomorrow's call is not yet included");
    assert.equal(answer.history.beforeDay, "1970-01-02");
    assert.equal(answer.historyPending, undefined);
    const oldClient = usage(makeStore(store.db, "."), "en", 0n, 86_400_000n, 0n, false, a, true);
    assert.deepEqual(oldClient.history.days.map((d: { day: string }) => d.day), ["1969-12-31", "1970-01-01", "1970-01-02"]);
    assert.equal(oldClient.history.tokens, undefined, "older clients keep the full history contract");
  } finally { store.close(); }
});

test("bounded requests preserve complete older daily summaries without rebuilding them", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A",
      createdAt: 0, lastActiveAt: 0 });
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "old", at: 0, model: "m", subagent: true, fast: false, input: 9, cacheRead: 0,
      cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    compact.installCompactUsage(store.db, () => store.now());
    retireUsageIndexes(store.db);
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[{ ...call, id: "new", at: 86_400_000 }, owner]]);
    account(store);
    const answer = usage(makeStore(store.db, "."), "en", 0n, 172_800_000n, 0n, false, a, true,
      { historyRange: { from: 86_400_000n, to: 172_800_000n } });
    assert.deepEqual(answer.history.days.map((d: { day: string; tokens: number }) => [d.day, d.tokens]),
      [["1970-01-01", 10], ["1970-01-02", 10]]);
    assert.equal(answer.history.tokens, undefined, "the old complete summary remains in the legacy full-history form");
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`compact totals follow changes and workspace moves (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws] of [["a", "A"], ["b", "B"], ["h", null]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, ws,
        createdAt: 0, lastActiveAt: 0 });
    }
    compact.installCompactUsage(store.db, () => store.now());
    retireUsageIndexes(store.db);
    store.db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number, input: number) => ({ id, at, model: "m", subagent: true, fast: false,
      input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null });
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call("old", -60_000, 10), owner], [call("new", 60_000, 19), owner]]);
    store.recordUsage("/b", { session: "b", offset: 1, model: "m" }, "claude", [[call("other", 60_000, 29), owner]]);
    store.recordUsage("/h", { session: "h", offset: 1, model: "m" }, "claude", [[call("home", 60_000, 39), owner]]);
    account(store);
    // The total is a maintained statistic, so older minutes, calls and other workspaces are not enumerated.
    store.db.setAuthorizer((action, name) => action === constants.SQLITE_READ && name === "usage"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      assert.deepEqual(compact.compactTotal(store.db, a), { calls: 2, tokens: 31 });
      assert.deepEqual(compact.compactTotal(store.db, b), { calls: 1, tokens: 30 });
      assert.deepEqual(compact.compactTotal(store.db, home), { calls: 3, tokens: 71 });
      assert.deepEqual(compact.compactTotal(store.db, null), { calls: 4, tokens: 101 });
    } finally { store.db.setAuthorizer(null); }

    store.db.prepare("UPDATE usage SET output = 5 WHERE id = ?").run("new");
    store.db.prepare("DELETE FROM usage WHERE id = ?").run("old");
    assert.equal(compact.compactTotal(store.db, a), null);
    account(store);
    assert.deepEqual(compact.compactTotal(store.db, a), { calls: 1, tokens: 24 });

    store.db.exec("UPDATE sessions SET ws = 'B' WHERE key = 'a'");
    assert.equal(compact.compactTotal(store.db, a), null, "a moving scope is never shown with stale ownership");
    assert.equal(compact.compactTotal(store.db, b), null);
    let done = false;
    for (let i = 0; i < 32 && !done; i++) done = compact.moveCompactStep(store.db, 1).done;
    assert.ok(done, "moving one session finishes in bounded steps");
    assert.deepEqual(compact.compactTotal(store.db, a), { calls: 0, tokens: 0 });
    assert.deepEqual(compact.compactTotal(store.db, b), { calls: 2, tokens: 54 });
    assert.deepEqual(compact.compactTotal(store.db, home), { calls: 1, tokens: 40 });

    // A previous station omits the compact marker but can still insert and grow its response.
    const oldWriter = store.db.prepare(`INSERT INTO usage (id, at, session, person, profile, runtime, model, subagent,
      input, cache_read, cache_write, cache_write_long, output) VALUES ('legacy', 120000, 'b', 'p', 'cc', 'claude', 'm', 1, 2, 0, 0, 0, ?)
      ON CONFLICT (id) DO UPDATE SET output = MAX(output, excluded.output)`);
    oldWriter.run(1);
    oldWriter.run(4);
    account(store);
    assert.deepEqual(compact.compactTotal(store.db, b), { calls: 3, tokens: 60 });
  } finally { store.close(); }
});

test("a zeroed compact bucket can later contribute to both its workspace and the overall total", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A",
      createdAt: 0, lastActiveAt: 0 });
    compact.installCompactUsage(store.db, () => store.now());
    retireUsageIndexes(store.db);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "call", at: 0, model: "m", subagent: true, fast: false, input: 1, cacheRead: 0,
      cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    store.db.exec("UPDATE usage SET calls = 0, input = 0, output = 0 WHERE id = 'call'");
    account(store);
    assert.deepEqual(compact.compactTotal(store.db, null), { calls: 0, tokens: 0 });
    store.db.exec("UPDATE usage SET calls = 1, output = 4 WHERE id = 'call'");
    account(store);
    assert.deepEqual(compact.compactTotal(store.db, a), { calls: 1, tokens: 4 });
    assert.deepEqual(compact.compactTotal(store.db, null), { calls: 1, tokens: 4 });
  } finally { store.close(); }
});

test("compact totals begin empty on an older database and do not absorb old calls", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A",
      createdAt: 0, lastActiveAt: 0 });
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "old", at: 0, model: "m", subagent: true, fast: false, input: 100, cacheRead: 0,
      cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    store.db.exec("CREATE TABLE usage_retired_detail (id INTEGER PRIMARY KEY); INSERT INTO usage_retired_detail VALUES (1)");
    compact.installCompactUsage(store.db, () => store.now());
    retireUsageIndexes(store.db);
    assert.deepEqual(compact.compactTotal(store.db, a), { calls: 0, tokens: 0 });
    store.db.exec("UPDATE usage SET output = 9 WHERE id = 'old'");
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[{ ...call, id: "new", input: 2 }, owner]]);
    account(store);
    assert.deepEqual(compact.compactTotal(store.db, a), { calls: 1, tokens: 3 });
  } finally { store.close(); }
});
