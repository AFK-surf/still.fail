import assert from "node:assert/strict";
import { mkdtempSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { installCompactUsage } from "../src/store/usage-compact.ts";
import { retireUsageIndexes } from "../src/store/usage-retire.ts";
import { keepUsage } from "../src/usage/module.ts";

test("keeping a main call's recent context does not add a page write to each transaction", () => {
  const write = (subagent: boolean) => {
    const dir = mkdtempSync(join(tmpdir(), "compact-context-write-"));
    const path = join(dir, "station.db");
    const store = Store.open(path);
    try {
      store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", ws: "A", createdAt: 0, lastActiveAt: 0 });
      installCompactUsage(store.db, () => 0);
      retireUsageIndexes(store.db);
      const owner = { turn: null, thread: null, person: "p", profile: "cc" };
      const record = (n: number) => store.recordUsage("/s", { session: "s", offset: n + 1, model: "m" }, "claude", [[{
        id: `call-${String(n).padStart(4, "0")}`, at: 60_000 + n, model: "m", subagent, fast: false, input: 10,
        cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 10, window: null,
      }, owner]]);
      for (let n = 0; n < 5; n++) record(n);
      store.db.exec("PRAGMA wal_checkpoint(TRUNCATE); PRAGMA wal_autocheckpoint = 0");
      for (let n = 5; n < 105; n++) record(n);
      return statSync(`${path}-wal`).size;
    } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
  };
  const subagent = write(true);
  const main = write(false);
  assert.equal(main, subagent, "the same calls should dirty the same number of pages when context is kept");
});

test("recent context follows model changes and is not kept after its calls are edited", () => {
  const dir = mkdtempSync(join(tmpdir(), "compact-context-owner-"));
  const path = join(dir, "station.db");
  let store = Store.open(path);
  const owner = { turn: "turn", thread: null, person: "p", profile: "cc" };
  const call = (id: string, at: number, model: string, fast = false, subagent = false) => ({
    id, at, model, fast, subagent, input: 10, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1,
    calls: 1, context: at, window: null,
  });
  const record = (n: number, c: ReturnType<typeof call>) => store.recordUsage("/s", { session: "s", offset: n, model: c.model }, "claude", [[c, owner]]);
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", ws: "A", createdAt: 0, lastActiveAt: 0 });
    // A database made by an earlier station has the positional form of this trigger.
    store.db.exec(`DROP TRIGGER usage_totals_add;
      CREATE TRIGGER usage_totals_add AFTER INSERT ON usage BEGIN
        INSERT INTO usage_totals VALUES (NEW.session, NEW.runtime, COALESCE(NEW.model, ''), NEW.fast, NEW.calls,
          NEW.input, NEW.cache_read, NEW.cache_write, NEW.cache_write_long, NEW.output)
        ON CONFLICT (session, runtime, model, fast) DO UPDATE SET calls = calls + excluded.calls,
          input = input + excluded.input, output = output + excluded.output;
      END;`);
    installCompactUsage(store.db, () => 0);
    retireUsageIndexes(store.db);
    record(1, call("one", 1, "a"));
    record(2, call("two", 2, "b", true));
    record(3, call("sub", 3, "c", false, true));
    assert.deepEqual(store.lastContexts("s", 5).map((c) => [c.model, c.at, c.fast]), [["a", 1, false], ["b", 2, true]]);
    assert.deepEqual(store.usageOfSession("s").map((g) => [g.model, g.calls]), [["a", 1], ["b", 1], ["c", 1]]);
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM usage_totals WHERE session = 's' AND compact_context IS NOT NULL").get() as { n: number }).n, 1);
    store.close();
    store = Store.open(path);
    assert.deepEqual(store.lastContexts("s", 5).map((c) => c.model), ["a", "b"]);
    store.db.prepare("UPDATE usage SET context = ? WHERE id = ?").run(9, "one");
    assert.deepEqual(store.lastContexts("s", 5), [], "an edited tail is not presented as current");
    record(4, call("three", 4, "a"));
    assert.deepEqual(store.lastContexts("s", 5), [], "a new call alone cannot recover the earlier tail");
    store.db.prepare("DELETE FROM usage WHERE id = ?").run("three");
    assert.deepEqual(store.lastContexts("s", 5), [], "a deleted last call is not presented as current");
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an incremental old total retains its context when its last source row is removed", () => {
  const dir = mkdtempSync(join(tmpdir(), "compact-context-incremental-"));
  const path = join(dir, "station.db");
  let store = Store.open(path);
  const owner = { turn: null, thread: null, person: "p", profile: "cc" };
  const call = (id: string, at: number) => ({ id, at, model: "m", fast: false, subagent: false, input: 10,
    cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: at, window: null });
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", ws: "A", createdAt: 0, lastActiveAt: 0 });
    store.recordUsage("/s", { session: "s", offset: 1, model: "m" }, "claude", [[call("old", 1), owner]]);
    store.db.exec("DROP TRIGGER usage_totals_add; DROP TRIGGER usage_totals_drop; DROP TRIGGER usage_totals_grow; DROP TABLE usage_totals");
    store.close();
    store = Store.open(path);
    const previous = (store.db.prepare("SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = 'usage_totals_source_aggregate_add'").get() as { sql: string }).sql;
    const positional = previous.replace(/INSERT INTO usage_totals\s*\([^)]*\)/, "INSERT INTO usage_totals");
    assert.notEqual(positional, previous);
    store.db.exec(`DROP TRIGGER usage_totals_source_aggregate_add; ${positional}`);
    installCompactUsage(store.db, () => 0);
    retireUsageIndexes(store.db);
    store.recordUsage("/s", { session: "s", offset: 2, model: "m" }, "claude", [[call("new", 2), owner]]);
    assert.deepEqual(store.lastContexts("s", 5).map((c) => c.at), [2]);
    store.recordUsage("/s", { session: "s", offset: 2, model: "m" }, "claude", [[{ ...call("new", 2), output: 5 }, owner]]);
    assert.deepEqual(store.lastContexts("s", 5).map((c) => c.at), [2], "growing a call keeps its context through the temporary zero total");
    store.db.prepare("DELETE FROM usage WHERE id = ?").run("new");
    assert.deepEqual(store.lastContexts("s", 5), []);
    store.recordUsage("/s", { session: "s", offset: 3, model: "m" }, "claude", [[call("later", 3), owner]]);
    assert.deepEqual(store.lastContexts("s", 5), [], "the old tail is not claimed complete after deleting a call");
    store.close();
    store = Store.open(path);
    assert.deepEqual(store.lastContexts("s", 5), []);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an edited context is not replaced by a delayed call", () => {
  const store = Store.open(":memory:");
  const owner = { turn: null, thread: null, person: "p", profile: "cc" };
  const call = (id: string, at: number) => ({ id, at, model: "m", fast: false, subagent: false, input: 10,
    cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: at, window: null });
  const record = (id: string, at: number) => store.recordUsage("/s", { session: "s", offset: at, model: "m" }, "claude", [[call(id, at), owner]]);
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(store.db, () => 0);
    retireUsageIndexes(store.db);
    record("first", 100);
    record("last", 200);
    store.db.prepare("UPDATE usage SET context = ? WHERE id = ?").run(90, "first");
    record("late", 50);
    assert.deepEqual(store.lastContexts("s", 5), [], "the older late call is not reported as the newest context");
    for (let n = 0; n < 5; n++) record(`later-${n}`, 300 + n);
    assert.deepEqual(store.lastContexts("s", 5).map((c) => c.at), [300, 301, 302, 303, 304], "five later calls establish a complete tail again");
  } finally { store.close(); }
});

test("a saved newer context is not treated as compacted by older late calls", () => {
  const store = Store.open(":memory:");
  const now = store.now();
  const owner = (turn: string) => ({ turn, thread: null, person: "p", profile: "cc" });
  const call = (id: string, at: number, context: number) => ({ id, at, model: "m", fast: false, subagent: false,
    input: 10, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context, window: null });
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", ws: "A",
      createdAt: now, lastActiveAt: now, runtimeSessionId: "r" });
    store.ranIn("s", "r", "cc");
    store.recordUsage("/s", { session: "s", offset: 1, model: "m" }, "claude", [[{ ...call("saved", now + 1_000, 150_000), cacheWrite: 5 }, owner("saved")]]);
    keepUsage(store, "s", true);
    installCompactUsage(store.db, () => now + 2_000);
    retireUsageIndexes(store.db);
    store.recordUsage("/s", { session: "s", offset: 2, model: "m" }, "claude", [
      [call("late-before", now + 100, 180_000), owner("late")], [call("late-after", now + 200, 20_000), owner("late")],
    ]);
    assert.equal(store.recentlyCompacted("s"), false, "an older compaction does not describe the saved newer context");
    assert.deepEqual(store.lastContexts("s", 5), [], "the older calls do not replace the saved latest context");
    assert.equal(store.savedCompactContext("s")?.contextTokens, 150_000);
    assert.equal(store.savedCompactContext("s")?.cacheMs, undefined, "an earlier late call can change the last five cache writes");
    store.recordUsage("/s", { session: "s", offset: 3, model: "m" }, "claude", [
      [call("new-before", now + 3_000, 180_000), owner("new")], [call("new-after", now + 4_000, 20_000), owner("new")],
    ]);
    assert.equal(store.recentlyCompacted("s"), true, "a compaction after the saved context is still recognized");
  } finally { store.close(); }
});

test("a call tied with a saved context is not ordered without its old id", () => {
  const store = Store.open(":memory:");
  const now = store.now();
  const owner = { turn: "turn", thread: null, person: "p", profile: "cc" };
  const call = (id: string, at: number) => ({ id, at, model: "m", fast: false, subagent: false, input: 10,
    cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: at, window: null });
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", ws: "A",
      createdAt: now, lastActiveAt: now, runtimeSessionId: "r" });
    store.ranIn("s", "r", "cc");
    store.recordUsage("/s", { session: "s", offset: 1, model: "m" }, "claude", [[call("saved", now + 1_000), owner]]);
    keepUsage(store, "s", true);
    installCompactUsage(store.db, () => now + 2_000);
    retireUsageIndexes(store.db);
    store.recordUsage("/s", { session: "s", offset: 2, model: "m" }, "claude", [[call("tied", now + 1_000), owner]]);
    assert.equal(store.savedCompactContext("s"), null);
    assert.deepEqual(store.lastContexts("s", 5), []);
    for (let n = 0; n < 5; n++) {
      store.recordUsage("/s", { session: "s", offset: 3 + n, model: "m" }, "claude", [[call(`later-${n}`, now + 3_000 + n), owner]]);
    }
    assert.deepEqual(store.lastContexts("s", 5).map((c) => c.at), Array.from({ length: 5 }, (_, n) => now + 3_000 + n));
  } finally { store.close(); }
});
