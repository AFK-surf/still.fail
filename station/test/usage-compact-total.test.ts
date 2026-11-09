import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants } from "node:sqlite";
import { test } from "node:test";
import * as compact from "../src/store/usage-compact.ts";
import { Store } from "../src/store/store.ts";
import type { UsageCall, UsageFor } from "../src/store/usage.ts";
import { retireUsageIndexes } from "../src/store/usage-retire.ts";

const a = { workspace: "A", home: false };
const b = { workspace: "B", home: false };
const home = { workspace: "A", home: true };

function account(store: Store): void {
  for (let i = 0; i < 100; i++) if (compact.compactTotalsStep(store.db, 2).done) return;
  assert.fail("compact totals did not finish in bounded batches");
}

test("a bounded lifetime total does not read future or unrelated minute buckets", () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws] of [["a", "A"], ["b", "B"], ["h", null]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, ws,
        createdAt: 0, lastActiveAt: 0 });
    }
    compact.installCompactUsage(store.db, () => store.now());
    retireUsageIndexes(store.db);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const rows = [
      ...[-65_537, -257, -256, -1, 0, 1, 255, 256, 65_536].map((minute, i) => ({ session: "a", minute, input: i + 1 })),
      ...Array.from({ length: 40 }, (_, i) => ({ session: "a", minute: 100_000 + i * 257, input: 1 })),
      { session: "b", minute: 0, input: 100 },
      { session: "h", minute: -1, input: 10 },
    ];
    for (const [i, row] of rows.entries()) {
      const call = { id: `c-${i}`, at: row.minute * 60_000, model: "m", subagent: true, fast: false,
        input: row.input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
      store.recordUsage(`/${row.session}`, { session: row.session, offset: i + 1, model: "m" }, "claude", [[call, owner]]);
    }
    account(store);
    for (const viewer of [a, home, null]) {
      const query = compact.compactTotalQuery(viewer, 100_100n);
      const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${query.sql}`).all(...query.args) as { detail: string }[])
        .map((row) => row.detail).join(" | ");
      assert.match(plan, /SEARCH t USING PRIMARY KEY \(scope=\? AND level=\? AND bucket>\? AND bucket<\?\)/, plan);
    }
    // Readiness may check scope and pending, but the answer must not enumerate minute buckets on either side of the cutoff.
    const denied = new Set(["minute", "records", "calls", "input", "cache_read", "cache_write", "cache_write_long", "output"]);
    store.db.setAuthorizer((action, table, column) => action === constants.SQLITE_READ && table === "usage_compact" && denied.has(column ?? "")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      for (const end of [-65_538, -65_537, -256, 0, 1, 256, 65_537, 100_100, 1_000_000]) {
        for (const [viewer, sessions] of [[a, ["a"]], [b, ["b"]], [home, ["a", "h"]], [null, ["a", "b", "h"]]] as const) {
          const visible = rows.filter((row) => (sessions as readonly string[]).includes(row.session) && row.minute < end);
          assert.deepEqual(compact.compactTotal(store.db, viewer, BigInt(end)), {
            calls: visible.length, tokens: visible.reduce((sum, row) => sum + row.input + 1, 0),
          }, `cutoff ${end} for ${viewer?.workspace ?? "all"}`);
        }
      }
    } finally { store.db.setAuthorizer(null); }
  } finally { store.close(); }
});

test("bounded totals follow edits and an interrupted workspace move", () => {
  const dir = mkdtempSync(join(tmpdir(), "compact-prefix-"));
  const path = join(dir, "station.db");
  let store = Store.open(path);
  try {
    for (const [key, ws] of [["a", "A"], ["b", "B"], ["h", null]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, ws,
        createdAt: 0, lastActiveAt: 0 });
    }
    compact.installCompactUsage(store.db, () => store.now());
    retireUsageIndexes(store.db);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    for (const session of ["a", "b", "h"]) {
      const calls = Array.from({ length: 12 }, (_, i): [UsageCall, UsageFor] => [{ id: `${session}-${i}`, at: (i - 6) * 257 * 60_000,
        model: "m", subagent: true, fast: false, input: i + 1, cacheRead: 2, cacheWrite: 0, cacheWriteLong: 0,
        output: 1, calls: 1, context: null, window: null }, owner]);
      store.recordUsage(`/${session}`, { session, offset: 1, model: "m" }, "claude", calls);
    }
    account(store);
    store.db.exec("UPDATE usage SET at = 15420000, output = 9 WHERE id = 'a-0'; DELETE FROM usage WHERE id = 'a-5'");
    store.db.exec("UPDATE sessions SET ws = 'B' WHERE key = 'a'");
    assert.equal(compact.moveCompactStep(store.db, 2).done, false);
    assert.equal(compact.compactTotal(store.db, b, 1n), null, "a partially moved total stays unavailable");
    store.close();
    store = Store.open(path);
    let moved = false;
    for (let i = 0; i < 100 && !moved; i++) moved = compact.moveCompactStep(store.db, 2).done;
    assert.ok(moved, "the move resumes after reopening");
    account(store);
    const truth = (end: number, viewer: typeof a | typeof b | typeof home | null) => {
      const visible = viewer === null ? "" : viewer.home ? "AND (s.ws = ? OR s.ws IS NULL)" : "AND s.ws = ?";
      const row = store.db.prepare(`SELECT COALESCE(SUM(u.calls), 0) AS calls,
        COALESCE(SUM(u.input + u.cache_read + u.cache_write + u.cache_write_long + u.output), 0) AS tokens
        FROM usage u JOIN sessions s ON s.key = u.session WHERE u.compact_counted = 1 AND u.at < ? ${visible}`)
        .get(end * 60_000, ...(viewer === null ? [] : [viewer.workspace])) as { calls: number; tokens: number };
      return { calls: row.calls, tokens: row.tokens };
    };
    for (const end of [-2_000, -1_542, -257, 0, 1, 257, 1_543, 2_000]) {
      for (const viewer of [a, b, home, null]) assert.deepEqual(compact.compactTotal(store.db, viewer, BigInt(end)), truth(end, viewer));
    }
  } finally {
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
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
      assert.deepEqual(compact.compactTotal(store.db, { workspace: "A" }), { calls: 3, tokens: 71 }, "an omitted home flag means the home workspace");
      assert.deepEqual(compact.compactTotal(store.db, null), { calls: 4, tokens: 101 });
    } finally { store.db.setAuthorizer(null); }

    store.db.prepare("UPDATE usage SET output = 5 WHERE id = ?").run("new");
    store.db.prepare("DELETE FROM usage WHERE id = ?").run("old");
    assert.equal(compact.compactTotal(store.db, a), null);
    account(store);
    assert.deepEqual(compact.compactTotal(store.db, a), { calls: 1, tokens: 24 });
    assert.deepEqual(compact.compactTotal(store.db, a, 1n), { calls: 0, tokens: 0 });
    assert.deepEqual(compact.compactTotal(store.db, a, 2n), { calls: 1, tokens: 24 });

    store.db.exec("UPDATE sessions SET ws = 'B' WHERE key = 'a'");
    assert.equal(compact.compactTotal(store.db, a), null, "a moving scope is never shown with stale ownership");
    assert.equal(compact.compactTotal(store.db, b), null);
    let done = false;
    for (let i = 0; i < 32 && !done; i++) done = compact.moveCompactStep(store.db, 1).done;
    assert.ok(done, "moving one session finishes in bounded steps");
    assert.deepEqual(compact.compactTotal(store.db, a), { calls: 0, tokens: 0 });
    assert.deepEqual(compact.compactTotal(store.db, b), { calls: 2, tokens: 54 });
    assert.deepEqual(compact.compactTotal(store.db, home), { calls: 1, tokens: 40 });
    assert.deepEqual(compact.compactTotal(store.db, a, 2n), { calls: 0, tokens: 0 });
    assert.deepEqual(compact.compactTotal(store.db, b, 2n), { calls: 2, tokens: 54 });

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
