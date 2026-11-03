import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants } from "node:sqlite";
import { mock, test } from "node:test";
import { Worker } from "node:worker_threads";
import { Effect, Fiber } from "effect";
import { usageRoutes } from "../src/api/routes/usage.ts";
import { makeStore, USAGE_CALLS_EARLIER, USAGE_CALLS_SAME, usageByDay, usageCallsPage, usageGroups, usageSince } from "../src/read/store.ts";
import { usage, usageNow } from "../src/read/usage.ts";
import { Store } from "../src/store/store.ts";
import { compactHistory, compactQuery, compactScopeReady, compactTotal, installCompactUsage, moveCompactStep } from "../src/store/usage-compact.ts";
import { retireUsageIndexes } from "../src/store/usage-retire.ts";
import { keepUsage, retireAfterPrevious, watchCompactMoves } from "../src/usage/module.ts";
import { testClock } from "./hub-fakes.ts";

const compactUsage = (store: Store) => { installCompactUsage(store.db, () => store.now()); retireUsageIndexes(store.db); };

test("workspace-change listeners only wake for changes of session ownership", () => {
  const store = Store.open(":memory:");
  try {
    const seen: (string | null)[] = [];
    const unsubscribe = store.onSessionWorkspaceChange(() => seen.push(store.getSession("a")?.ws ?? null));
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    store.setSessionProfile("a", "other", false);
    store.setSessionsWs("A", "A");
    store.setSessionsWs("A", "B");
    store.deleteSession("a");
    assert.deepEqual(seen, ["A", "B", null]);
    unsubscribe();
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    assert.deepEqual(seen, ["A", "B", null]);
  } finally { store.close(); }
});

test("recording another call leaves an unchanged workspace scope alone", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "one", at: 60_000, model: "m", subagent: false, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    store.db.exec(`CREATE TABLE scope_changes (session TEXT);
      CREATE TRIGGER count_scope_changes AFTER UPDATE ON usage_minute_scope BEGIN
        INSERT INTO scope_changes VALUES (NEW.session);
      END;`);
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[{ ...call, id: "two", at: 120_000 }, owner]]);
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM scope_changes").get() as { n: number }).n, 0);
    store.db.prepare("UPDATE sessions SET ws = ? WHERE key = ?").run("B", "a");
    store.recordUsage("/a", { session: "a", offset: 3, model: "m" }, "claude", [[{ ...call, id: "three", at: 180_000 }, owner]]);
    const reader = makeStore(store.db, ".");
    assert.throws(() => usageGroups(reader, 0n, 240_000n, 0n, { workspace: "B", home: false }), /moving between workspaces/);
    while (!moveCompactStep(store.db, 2).done) { /* One bounded batch at a time. */ }
    assert.deepEqual(usageGroups(reader, 0n, 240_000n, 0n, { workspace: "A", home: false }), []);
    assert.equal(usageGroups(reader, 0n, 240_000n, 0n, { workspace: "B", home: false })[0]!.calls, 3);
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM scope_changes").get() as { n: number }).n, 1);
  } finally { store.close(); }
});

test("reading the same call and transcript position again writes nothing", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "one", at: 60_000, model: "m", subagent: false, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    const file = { session: "a", offset: 1, model: "m" };
    store.recordUsage("/a", file, "claude", [[call, owner]]);
    const changes = () => (store.db.prepare("SELECT total_changes() AS n").get() as { n: number }).n;
    const before = changes();
    store.recordUsage("/a", file, "claude", [[call, owner]]);
    assert.equal(changes(), before, "unchanged calls and positions do not cause a database write");
    store.recordUsage("/a", { ...file, offset: 2 }, "claude", [[{ ...call, output: 4 }, owner]]);
    assert.deepEqual(store.usageOfSession("a").map((row) => [row.calls, row.output]), [[1, 4]]);
    assert.equal(store.usageFiles().get("/a")?.offset, 2);
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`an older station can still record and grow a call after compact statistics are installed (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    store.db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    // The previous station does not know compact_counted and uses an upsert to grow the output.
    const write = store.db.prepare(`INSERT INTO usage (id, at, session, turn, thread, person, profile, runtime, model, subagent, fast,
      input, cache_read, cache_write, cache_write_long, output, calls, context, context_window)
      VALUES ('legacy', 60000, 'a', NULL, NULL, 'p', 'cc', 'claude', 'm', 0, 0, 10, 0, 0, 0, ?, 1, NULL, NULL)
      ON CONFLICT (id) DO UPDATE SET output = MAX(output, excluded.output)`);
    write.run(1);
    const read = () => usageGroups(makeStore(store.db, "."), 0n, 120_000n, 0n, { workspace: "A", home: false });
    assert.deepEqual(read().map((row) => [row.calls, row.input, row.output]), [[1, 10, 1]], "a new call from an older writer enters the compact statistics");
    assert.doesNotThrow(() => write.run(4), "an older writer can grow a recorded response");
    assert.deepEqual(read().map((row) => [row.calls, row.input, row.output]), [[1, 10, 4]], "the response contributes its growth exactly once");
    write.run(2);
    assert.deepEqual(read().map((row) => [row.calls, row.input, row.output]), [[1, 10, 4]], "an older response cannot reduce the output");
  } finally { store.close(); }
});

test("a first call written by an older station is not skipped when reconstructing recent context", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    store.db.exec(`INSERT INTO usage (id, at, session, person, profile, runtime, model, input, cache_read, cache_write, cache_write_long, output, context)
      VALUES ('legacy', 60000, 'a', 'p', 'cc', 'claude', 'm', 10, 0, 10, 0, 1, 10)`);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "new", at: 120_000, model: "m", subagent: false, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 20, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    assert.deepEqual(store.lastContexts("a", 5), [], "one later call cannot reconstruct the missing legacy cache write");
    for (let n = 1; n <= 4; n++) store.recordUsage("/a", { session: "a", offset: n + 1, model: "m" }, "claude",
      [[{ ...call, id: `new-${n}`, at: call.at + n }, owner]]);
    assert.equal(store.lastContexts("a", 5).length, 5, "five newer calls restore the complete recent tail");
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`an older writer grows calls recorded on either side of compact installation (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "before", at: 60_000, model: "m", subagent: true, fast: false, input: 10,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    compactUsage(store);
    store.db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const write = store.db.prepare(`INSERT INTO usage (id, at, session, person, profile, runtime, model, subagent,
      input, cache_read, cache_write, cache_write_long, output) VALUES (?, ?, 'a', 'p', 'cc', 'claude', 'm', 1, 10, 0, 0, 0, ?)
      ON CONFLICT (id) DO UPDATE SET output = MAX(output, excluded.output)`);
    write.run("before", 60_000, 4);
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[{ ...call, id: "after", at: 120_000 }, owner]]);
    write.run("after", 120_000, 4);
    const reader = makeStore(store.db, ".");
    assert.deepEqual(usageGroups(reader, 120_000n, 180_000n, 0n, { workspace: "A", home: false })
      .map((row) => [row.calls, row.input, row.output]), [[1, 10, 4]], "the later call's compact bucket includes its growth once");
    assert.deepEqual(usageByDay(reader, 0n, { workspace: "A", home: false })
      .map((row) => [row.calls, row.tokens]), [[2, 28]], "the preserved historical total and the compact total both stay accurate");
  } finally { store.close(); }
});

test("a time range does not visit sessions with only older statistics", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "one", at: 60_000, model: "m", subagent: false, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    let visits = 0;
    store.db.function("inspected_session", (session) => { visits++; return session; });
    const q = compactQuery(60_000n, 120_000n, 0n, { workspace: "A", home: false });
    const sql = q.sql.replace("GROUP BY day", "AND inspected_session(c.session) IS NOT NULL GROUP BY day");
    assert.notEqual(sql, q.sql, "the test counts each candidate statistics row");
    const read = () => {
      visits = 0;
      const rows = store.db.prepare(sql).all(...q.args) as { session: string; calls: number }[];
      assert.deepEqual(rows.map((row) => [row.session, row.calls]), [["a", 1]]);
      return visits;
    };
    const before = read();
    const history = () => compactHistory(store.db, 0n, { workspace: "A", home: false }, false, { from: 1n, to: 2n })
      ?.map((row) => [row.session, row.calls, row.tokens]);
    assert.deepEqual(history(), [["a", 1, 2]]);
    const scope = store.db.prepare("INSERT INTO usage_minute_scope (session, ws, done) VALUES (?, 'A', 1)");
    const old = store.db.prepare("INSERT INTO usage_compact (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write, cache_write_long, output, scope) VALUES (?, -1, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 1, 0, 0, 0, 1, 'WA')");
    for (let n = 0; n < 200; n++) { scope.run(`old-${n}`); old.run(`old-${n}`); }
    const other = store.db.prepare("INSERT INTO usage_compact (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write, cache_write_long, output, scope) VALUES (?, 1, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 1, 0, 0, 0, 1, 'WB')");
    for (let n = 0; n < 200; n++) other.run(`other-${n}`);
    assert.equal(read(), before, "older sessions outside the requested range do not increase lookup work");
    assert.deepEqual(history(), [["a", 1, 2]], "history excludes older days and other workspaces too");
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${q.sql}`).all(...q.args) as { detail: string }[]).map((row) => row.detail).join(" | ");
    assert.match(plan, /usage_compact_scope_time \(scope=\? AND minute>\? AND minute<\?\)/);
  } finally { store.close(); }
});

test("compact usage keeps exact millisecond boundaries and workspace visibility", () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws] of [["a", "A"], ["b", "B"], ["home", null]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, ws, createdAt: 0, lastActiveAt: 0 });
    }
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number, input: number) => ({ id, at, model: "m", subagent: false, fast: false,
      input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 0, calls: 1, context: null, window: null });
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [
      [call("a0", -60_001, 1), owner], [call("a1", -60_000, 2), owner], [call("a2", -1, 4), owner],
      [call("a3", 0, 8), owner], [call("a4", 10, 16), owner], [call("a5", 59_999, 32), owner], [call("a6", 60_000, 64), owner],
      [call("a7", 120_010, 128), owner],
    ]);
    store.recordUsage("/b", { session: "b", offset: 1, model: "m" }, "claude", [[call("b", 10, 4096), owner]]);
    store.recordUsage("/home", { session: "home", offset: 1, model: "m" }, "claude", [[call("home", 10, 8192), owner]]);
    const reader = makeStore(store.db, ".");
    const rows = (from: bigint, to: bigint, home: boolean) => usageGroups(reader, from, to, 1n, { workspace: "A", home })
      .map((r) => [r.day, r.session, r.input]).sort((a, b) => String(a).localeCompare(String(b)));
    assert.deepEqual(rows(10n, 11n, false), [["1970-01-01", "a", 16]]);
    assert.deepEqual(rows(-60_001n, 60_001n, false), [["1969-12-31", "a", 1], ["1970-01-01", "a", 126]]);
    assert.deepEqual(rows(-60_001n, 60_001n, true), [["1969-12-31", "a", 1], ["1970-01-01", "a", 126], ["1970-01-01", "home", 8192]]);
    assert.deepEqual(rows(-60_000n, 60_000n, false), [["1970-01-01", "a", 62]]);
    assert.deepEqual(rows(10n, 10n, false), []);
  } finally { store.close(); }
});

test("compact usage agrees with calls across dates and arbitrary bounds", () => {
  const store = Store.open(":memory:");
  try {
    const sessions = [["a", "A"], ["b", "B"], ["home", null]] as const;
    for (const [key, ws] of sessions) store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/w", token: key, ws, createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const times = [-86_400_002, -60_001, -60_000, -1, 0, 1, 59_999, 60_000, 86_399_999, 86_400_000];
    const originals: { session: string; ws: string | null; at: number; input: number; output: number }[] = [];
    for (const [key, ws] of sessions) {
      const calls = Array.from({ length: 50 }, (_, n) => {
        const at = times[n % times.length]! + Math.floor(n / times.length);
        const input = n + 1;
        const output = n % 7;
        originals.push({ session: key, ws, at, input, output });
        return [{ id: `${key}-${n}`, at, model: "m", subagent: false, fast: false, input,
          cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output, calls: 1, context: null, window: null }, owner] as const;
      });
      store.recordUsage(`/${key}`, { session: key, offset: 1, model: "m" }, "claude", calls.map(([call, of]) => [call, of]));
    }
    const reader = makeStore(store.db, ".");
    const ranges: [bigint, bigint][] = [[-86_400_003n, -86_400_001n], [-60_001n, 60_001n], [-1n, 1n],
      [0n, 59_999n], [1n, 60_000n], [0n, 9_223_372_036_854_775_807n], [-60_000n, 120_000n],
      [1n, 1n], [-86_399_999n, 86_400_001n]];
    for (const [from, to] of ranges) for (const offset of [-31, 0, 1, 345]) for (const home of [false, true]) {
      const expected = new Map<string, { day: string; session: string; calls: number; input: number; output: number }>();
      for (const call of originals) {
        if (BigInt(call.at) < from || BigInt(call.at) >= to || (call.ws !== "A" && !(home && call.ws === null))) continue;
        const day = new Date(call.at + offset * 60_000).toISOString().slice(0, 10);
        const id = `${day}\0${call.session}`;
        const row = expected.get(id) ?? { day, session: call.session, calls: 0, input: 0, output: 0 };
        row.calls++;
        row.input += call.input;
        row.output += call.output;
        expected.set(id, row);
      }
      const order = (a: { day: string; session: string }, b: { day: string; session: string }) =>
        a.day.localeCompare(b.day) || a.session.localeCompare(b.session);
      const actual = usageGroups(reader, from, to, BigInt(offset), { workspace: "A", home })
        .map(({ day, session, calls, input, output }) => ({ day, session, calls, input, output })).sort(order);
      assert.deepEqual(actual, [...expected.values()].sort(order), `${from}..${to}, offset ${offset}, home ${home}`);
    }
  } finally { store.close(); }
});

test("compact usage does not read sessions again after selecting its workspace", () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws] of [["a", "A"], ["b", "B"], ["home", null]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, ws, createdAt: 0, lastActiveAt: 0 });
    }
    compactUsage(store);
    const owner = { turn: null, thread: null, person: null, profile: "cc" };
    for (const key of ["a", "b", "home"]) {
      const call = { id: key, at: 60_000, model: "m", subagent: false, fast: false, input: 1,
        cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
      store.recordUsage(`/${key}`, { session: key, offset: 1, model: "m" }, "claude", [[call, owner]]);
    }
    const reader = makeStore(store.db, ".");
    const read = (workspace: string, home: boolean) => {
      store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "sessions"
        ? constants.SQLITE_DENY : constants.SQLITE_OK);
      try {
        const answer = usage(reader, "en", 0n, 120_000n, 0n, false, { workspace, home }, false, { remoteRuns: false });
        return answer.rows.map((r: { session: string }) => r.session).sort();
      } finally { store.db.setAuthorizer(null); }
    };
    assert.deepEqual(read("A", false), ["a"]);
    assert.deepEqual(read("A", true), ["a", "home"]);
    assert.deepEqual(read("B", false), ["b"]);

    store.db.prepare("UPDATE sessions SET ws = 'B' WHERE key = 'a'").run();
    assert.throws(() => read("A", false), /moving between workspaces/);
    while (!moveCompactStep(store.db, 2).done) { /* One bounded batch at a time. */ }
    assert.deepEqual(read("A", false), []);
    assert.deepEqual(read("B", false), ["a", "b"]);

    store.deleteSession("b");
    while (!moveCompactStep(store.db, 2).done) { /* Its usage becomes home usage. */ }
    assert.deepEqual(read("B", false), ["a"]);
    assert.deepEqual(read("A", true), ["b", "home"]);
  } finally { store.close(); }
});

test("a usage summary checks a session's workspace once for its minutes", () => {
  const store = Store.open(":memory:");
  try {
    const sessions = [["a", "A"], ["b", "A"], ["other", "B"], ["old", "A"]] as const;
    for (const [key, ws] of sessions) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, ws, createdAt: 0, lastActiveAt: 0 });
    }
    compactUsage(store);
    const scope = store.db.prepare("INSERT INTO usage_minute_scope (session, ws, done) VALUES (?, ?, 1)");
    const bucket = store.db.prepare("INSERT INTO usage_compact (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write, cache_write_long, output, scope) VALUES (?, ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 1, 0, 0, 0, 0, ?)");
    for (const [key, ws] of sessions) {
      scope.run(key, ws);
      for (let minute = 0; minute < 60; minute++) bucket.run(key, key === "old" ? minute - 120 : minute, `W${ws}`);
    }
    let visits = 0;
    store.db.function("inspected_scope_session", (session) => { visits++; return session; });
    const query = compactQuery(0n, 3_600_000n, 0n, { workspace: "A", home: false });
    const counted = query.sql.replace(/sc\.session = ([a-z]+)\.session/, "sc.session = inspected_scope_session($1.session)");
    assert.notEqual(counted, query.sql, "the test counts lookups of a session's workspace");
    const before = (store.db.prepare("SELECT total_changes() AS n").get() as { n: number }).n;
    const rows = store.db.prepare(counted).all(...query.args) as { session: string; calls: number; input: number }[];
    assert.deepEqual(rows.map((r) => [r.session, r.calls, r.input]).sort(), [["a", 60, 60], ["b", 60, 60]]);
    assert.equal(visits, 2, "each relevant session's scope is looked up once, not once per minute");
    assert.equal((store.db.prepare("SELECT total_changes() AS n").get() as { n: number }).n, before, "reading writes nothing");
  } finally { store.close(); }
});

test("a partial minute does not visit other workspaces or calls outside its bounds", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number) => ({ id, at, model: "m", subagent: false, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 0, calls: 1, context: null, window: null });
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call("wanted", 1_001), owner]]);
    let buckets = 0;
    let calls = 0;
    store.db.function("edge_bucket", () => { buckets++; return 1; });
    store.db.function("edge_call", () => { calls++; return 1; });
    const q = compactQuery(1_001n, 1_002n, 0n, { workspace: "A", home: false });
    const sql = q.sql.replace("c.minute = ", "edge_bucket() AND c.minute = ")
      .replace("WHERE u.compact_counted = 1", "WHERE edge_call() AND u.compact_counted = 1");
    assert.notEqual(sql, q.sql);
    const read = () => {
      buckets = 0;
      calls = 0;
      const rows = store.db.prepare(sql).all(...q.args) as { session: string; calls: number; input: number }[];
      assert.deepEqual(rows.map((r) => [r.session, r.calls, r.input]), [["a", 1, 1]]);
      return [buckets, calls];
    };
    const before = read();
    const scope = store.db.prepare("INSERT INTO usage_minute_scope (session, ws, done) VALUES (?, ?, 1)");
    const bucket = store.db.prepare("INSERT INTO usage_compact (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write, cache_write_long, output, scope) VALUES (?, ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 1, 0, 0, 0, 0, ?)");
    for (let n = 0; n < 200; n++) {
      scope.run(`old-${n}`, "A");
      bucket.run(`old-${n}`, -1, "WA");
      scope.run(`other-${n}`, "B");
      bucket.run(`other-${n}`, 0, "WB");
    }
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude",
      Array.from({ length: 300 }, (_, n) => [call(`earlier-${n}`, 500), owner]));
    assert.deepEqual(read(), before, "unrelated statistics and calls do not increase edge work");
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${q.sql}`).all(...q.args) as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /usage_compact_scope_time \(scope=\? AND minute=\?\)/);
    assert.match(plan, /usage_session \(session=\? AND at>\? AND at<\?\)/);
  } finally { store.close(); }
});

test("a moved session's statistics are re-scoped in bounded batches and follow another move", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (n: number) => ({ id: `call-${n}`, at: n * 60_000, model: "m", subagent: true, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null });
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", Array.from({ length: 7 }, (_, i) => [call(i + 1), owner]));
    let updates = 0;
    store.db.function("bucket_was_moved", () => { updates++; return 0; });
    store.db.exec("CREATE TEMP TRIGGER count_bucket_moves AFTER UPDATE OF scope ON usage_compact BEGIN SELECT bucket_was_moved(); END");
    store.db.prepare("UPDATE sessions SET ws = ? WHERE key = ?").run("B", "a");
    assert.equal(compactScopeReady(store.db, { workspace: "A", home: false }), false);
    assert.equal(compactScopeReady(store.db, { workspace: "B", home: false }), false);
    assert.equal(compactScopeReady(store.db, { workspace: "C", home: false }), true);
    moveCompactStep(store.db, 2);
    assert.equal(updates, 2);
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[call(0), owner]]);
    store.db.prepare("UPDATE sessions SET ws = ? WHERE key = ?").run("C", "a");
    const addScope = store.db.prepare("INSERT INTO usage_compact_moving_scope VALUES (?, 'a')");
    for (let n = 0; n < 5; n++) addScope.run(`Wprevious-${n}`);
    const scopes = () => (store.db.prepare("SELECT COUNT(*) AS n FROM usage_compact_moving_scope WHERE session = 'a'").get() as { n: number }).n;
    for (;;) {
      const before = updates;
      const beforeScopes = scopes();
      const step = moveCompactStep(store.db, 2);
      assert.ok(updates - before <= 2, "one transaction moves at most one batch");
      assert.ok(beforeScopes - scopes() <= 2, "one transaction removes at most one batch of affected workspaces");
      if (step.done) break;
    }
    const reader = makeStore(store.db, ".");
    assert.deepEqual(usageGroups(reader, 0n, 600_000n, 0n, { workspace: "A", home: false }), []);
    assert.deepEqual(usageGroups(reader, 0n, 600_000n, 0n, { workspace: "B", home: false }), []);
    assert.equal(usageGroups(reader, 0n, 600_000n, 0n, { workspace: "C", home: false })[0]!.calls, 8);
    assert.deepEqual(compactTotal(store.db, { workspace: "A", home: false }), { calls: 0, tokens: 0 });
    assert.deepEqual(compactTotal(store.db, { workspace: "B", home: false }), { calls: 0, tokens: 0 });
    assert.deepEqual(compactTotal(store.db, { workspace: "C", home: false }), { calls: 8, tokens: 16 });
    assert.deepEqual(compactTotal(store.db, null), { calls: 8, tokens: 16 });
  } finally { store.close(); }
});

test("an omitted home flag includes home usage in compact histories, time edges and moving checks", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "h", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "h", ws: null,
      createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "home", at: 1_000, model: "m", subagent: true, fast: false, input: 1, cacheRead: 0,
      cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    store.recordUsage("/h", { session: "h", offset: 1, model: "m" }, "claude", [[call, owner]]);
    const viewer = { workspace: "A" };
    assert.deepEqual(compactHistory(store.db, 0n, viewer)?.map((row) => row.tokens), [2]);
    assert.deepEqual(usageGroups(makeStore(store.db, "."), 500n, 2_000n, 0n, viewer).map((row) => row.input), [1]);
    store.db.exec("UPDATE sessions SET ws = 'B' WHERE key = 'h'");
    assert.equal(compactScopeReady(store.db, viewer), false);
    assert.equal(compactScopeReady(store.db, { workspace: "A", home: false }), true);
  } finally { store.close(); }
});

test("a worker resumes an interrupted workspace move and wakes for the next one", async () => {
  const dir = mkdtempSync(join(tmpdir(), "compact-scope-worker-"));
  const path = join(dir, "station.db");
  let store = Store.open(path);
  let mover: ReturnType<typeof watchCompactMoves> | null = null;
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const calls = Array.from({ length: 270 }, (_, i) => [{ id: `call-${i}`, at: i * 60_000, model: "m", subagent: true,
      fast: false, input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null }, owner] as const);
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", calls as never);
    store.setSessionsWs("A", "B");
    moveCompactStep(store.db, 2);
    store.close();
    store = Store.open(path);
    const waitForMove = () => new Promise<void>((resolve) => {
      const unsubscribe = store.subscribe((change) => {
        if (change.type === "usage" && change.sessions.includes("a")) { unsubscribe(); resolve(); }
      });
    });
    const resumed = waitForMove();
    mover = watchCompactMoves(store, Promise.resolve());
    await resumed;
    assert.equal(compactScopeReady(store.db, { workspace: "B", home: false }), true);
    assert.equal(usageGroups(makeStore(store.db, dir), 0n, 18_000_000n, 0n, { workspace: "B", home: false })[0]!.calls, 270);
    const moved = waitForMove();
    store.setSessionsWs("B", "C");
    await moved;
    assert.equal(compactScopeReady(store.db, { workspace: "C", home: false }), true);
    assert.equal(usageGroups(makeStore(store.db, dir), 0n, 18_000_000n, 0n, { workspace: "C", home: false })[0]!.calls, 270);
  } finally { if (mover !== null) await mover.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a stopped workspace worker retries a pending move without another change", async () => {
  const dir = mkdtempSync(join(tmpdir(), "compact-scope-retry-"));
  const time = testClock();
  const store = Store.open(join(dir, "station.db"), null, time.clock);
  let mover: ReturnType<typeof watchCompactMoves> | null = null;
  const post = Worker.prototype.postMessage;
  let wakes = 0;
  let stopped!: () => void;
  const firstExit = new Promise<void>((resolve) => { stopped = resolve; });
  const interception = mock.method(Worker.prototype, "postMessage", function (this: Worker, message: unknown) {
    if (message !== null && typeof message === "object" && "wake" in message) {
      wakes++;
      if (wakes === 1) { this.once("exit", stopped); void this.terminate(); return; }
    }
    return post.call(this, message);
  });
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "one", at: 60_000, model: "m", subagent: true, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    store.setSessionsWs("A", "B");
    const finished = new Promise<void>((resolve) => {
      const unsubscribe = store.subscribe((change) => {
        if (change.type === "usage" && change.sessions.includes("a")) { unsubscribe(); resolve(); }
      });
    });
    mover = watchCompactMoves(store, Promise.resolve());
    await firstExit;
    await time.adjust(250);
    assert.equal(wakes, 2, "the worker is restarted without waiting for another session change");
    await finished;
    assert.equal(compactScopeReady(store.db, { workspace: "B", home: false }), true);
    assert.equal(usageGroups(makeStore(store.db, dir), 0n, 120_000n, 0n, { workspace: "B", home: false })[0]!.calls, 1);
  } finally {
    interception.mock.restore();
    if (mover !== null) await mover.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a call moved to a session without earlier calls follows its workspace", () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws] of [["a", "A"], ["b", "B"]]) store.insertSession({ key: key!, connect: "ember", runtime: "claude", profile: "cc",
      workspace: `/w/${key}`, token: key!, ws: ws!, createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "one", at: 60_000, model: "m", subagent: false, fast: false, input: 2,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    store.db.prepare("UPDATE usage SET session = ? WHERE id = ?").run("b", "one");
    const reader = makeStore(store.db, ".");
    assert.deepEqual(usageGroups(reader, 0n, 120_000n, 0n, { workspace: "A", home: false }), []);
    assert.deepEqual(usageGroups(reader, 0n, 120_000n, 0n, { workspace: "B", home: false })
      .map((row) => [row.session, row.calls, row.input]), [["b", 1, 2]]);
  } finally { store.close(); }
});

test("a growing response adjusts its existing bucket without replacing it", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "one", at: 60_000, model: "m", subagent: false, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    store.db.exec(`CREATE TABLE bucket_changes (kind TEXT);
      CREATE TRIGGER bucket_added AFTER INSERT ON usage_compact BEGIN INSERT INTO bucket_changes VALUES ('add'); END;
      CREATE TRIGGER bucket_updated AFTER UPDATE ON usage_compact BEGIN INSERT INTO bucket_changes VALUES ('update'); END;
      CREATE TRIGGER bucket_deleted AFTER DELETE ON usage_compact BEGIN INSERT INTO bucket_changes VALUES ('delete'); END;`);
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[{ ...call, output: 9 }, owner]]);
    assert.deepEqual(store.db.prepare("SELECT kind FROM bucket_changes").all().map((row) => row.kind), ["update"]);
    assert.deepEqual(usageGroups(makeStore(store.db, "."), 0n, 120_000n, 0n, { workspace: "A", home: false })
      .map((row) => [row.calls, row.input, row.output]), [[1, 1, 9]]);
  } finally { store.close(); }
});

test("a later reading of the same call keeps its original time and coverage", () => {
  const time = testClock();
  const store = Store.open(":memory:", null, time.clock);
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "one", at: 60_000, model: "m", subagent: true, fast: false, input: 3,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[{ ...call, at: 120_000, output: 9 }, owner]]);
    const reader = makeStore(store.db, ".");
    assert.equal(usageSince(reader), 60_000);
    assert.deepEqual(usageGroups(reader, 0n, 120_000n, 0n, { workspace: "A", home: false })
      .map((row) => [row.calls, row.input, row.output]), [[1, 3, 9]]);
  } finally { store.close(); }
});

test("a duplicate insert cannot silently corrupt statistics with either SQLite trigger mode", () => {
  for (const recursive of ["OFF", "ON"]) {
    const store = Store.open(":memory:");
    try {
      store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
      compactUsage(store);
      const owner = { turn: null, thread: null, person: "p", profile: "cc" };
      const call = { id: "one", at: 60_000, model: "m", subagent: true, fast: false, input: 3,
        cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
      store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
      store.db.exec(`PRAGMA recursive_triggers = ${recursive}`);
      const groups = () => usageGroups(makeStore(store.db, "."), 0n, 120_000n, 0n, { workspace: "A", home: false })
        .map((row) => [row.calls, row.input, row.output]);
      assert.throws(() => store.db.exec("INSERT OR IGNORE INTO usage SELECT * FROM usage WHERE id = 'one'"), /updated in place/);
      assert.throws(() => store.db.exec("INSERT OR REPLACE INTO usage SELECT * FROM usage WHERE id = 'one'"), /updated in place/);
      assert.deepEqual(groups(), [[1, 3, 1]], `rejected inserts leave the call intact with recursive triggers ${recursive}`);
      store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[{ ...call, output: 9 }, owner]]);
      assert.deepEqual(groups(), [[1, 3, 9]], `growing the call with recursive triggers ${recursive}`);
    } finally { store.close(); }
  }
});

test("a recent context compaction does not add a discarded legacy event", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "one", at: 60_000, model: "m", subagent: false, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 100_000, window: 200_000 };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    store.db.setAuthorizer((action, name) => action === constants.SQLITE_INSERT && name === "usage_compaction_events"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[{ ...call, id: "two", at: 120_000, context: 10_000 }, owner]]);
      assert.equal(store.recentlyCompacted("a"), true);
    } finally { store.db.setAuthorizer(null); }
  } finally { store.close(); }
});

test("after handover old per-call indexes are removed and new statistics remain readable", async () => {
  const time = testClock();
  const store = Store.open(":memory:", null, time.clock);
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: -100_000, lastActiveAt: 0 });
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number, input: number) => [{ id, at, model: "m", subagent: false, fast: false,
      input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 100_000, window: null }, owner] as const;
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [call("old", -60_000, 2)] as never);
    let handedOver!: () => void;
    const fiber = Effect.runFork(retireAfterPrevious(store, new Promise<void>((resolve) => { handedOver = resolve; })));
    const table = (name: string) => !!store.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").get(name);
    assert.ok(table("usage_detail") && table("usage_main_calls"), "the previous process can still read until it exits");
    handedOver();
    await Effect.runPromise(Fiber.join(fiber));
    for (const name of ["usage_detail", "usage_detail_lookup", "usage_main_calls"]) {
      assert.equal(table(name), false, `${name} no longer duplicates historical calls`);
    }
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [call("new", 60_000, 4)] as never);
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM usage").get() as { n: number }).n, 2, "the original records remain");
    assert.deepEqual(store.usageOfSession("a").map((row) => [row.calls, row.input]), [[2, 6]], "the existing session total continues");
    store.db.setAuthorizer((action, name) => action === constants.SQLITE_READ && name === "usage" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      const reader = makeStore(store.db, ".");
      assert.deepEqual(usageGroups(reader, 0n, 86_400_000n, 0n, { workspace: "A", home: false }).map((row) => [row.calls, row.input]), [[1, 4]],
        "the new period is computed from statistics without rereading calls");
      assert.deepEqual(usageByDay(reader, 0n, { workspace: "A", home: false }).map((row) => [row.day, row.calls, row.tokens]), [
        ["1969-12-31", 1, 3], ["1970-01-01", 1, 5],
      ], "the old complete daily summary is retained");
    } finally { store.db.setAuthorizer(null); }
  } finally { store.close(); }
});

test("an old response growing after handover updates the preserved daily total", () => {
  const time = testClock();
  const store = Store.open(":memory:", null, time.clock);
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: -100_000, lastActiveAt: 0 });
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const old = { id: "old", at: -60_000, model: "m", subagent: false, fast: false, input: 2, cacheRead: 0,
      cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 100_000, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[old, owner]]);
    compactUsage(store);
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[{ ...old, output: 9 }, owner]]);
    assert.deepEqual(usageByDay(makeStore(store.db, "."), 0n, { workspace: "A", home: false }).map((row) => [row.calls, row.tokens]), [[1, 11]]);
    assert.deepEqual(store.usageOfSession("a").map((row) => [row.calls, row.input, row.output]), [[1, 2, 9]]);
  } finally { store.close(); }
});

test("old daily totals are not claimed complete after summary writers were stopped", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "old", at: 60_000, model: "m", subagent: false, fast: false, input: 2, cacheRead: 0,
      cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    store.db.exec("CREATE TABLE usage_retired_detail (id INTEGER PRIMARY KEY); INSERT INTO usage_retired_detail VALUES (1)");
    compactUsage(store);
    assert.throws(() => usageByDay(makeStore(store.db, "."), 0n, { workspace: "A", home: false }), /being indexed|unavailable/);
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[{ ...call, id: "new", at: 120_000 }, owner]]);
    assert.deepEqual(usageGroups(makeStore(store.db, "."), 0n, 180_000n, 0n, { workspace: "A", home: false }).map((row) => [row.calls, row.input]), [[1, 2]]);
  } finally { store.close(); }
});

test("a station with incomplete old totals can report its new history without claiming completeness", () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws] of [["a", "A"], ["b", "B"]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, ws, createdAt: 0, lastActiveAt: 0 });
    }
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "old", at: 60_000, model: "m", subagent: false, fast: false, input: 100, cacheRead: 0,
      cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    store.db.exec("CREATE TABLE usage_retired_detail (id INTEGER PRIMARY KEY); INSERT INTO usage_retired_detail VALUES (1)");
    compactUsage(store);
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[{ ...call, id: "new", at: 120_000, input: 2 }, owner]]);
    store.recordUsage("/b", { session: "b", offset: 1, model: "m" }, "claude", [[{ ...call, id: "other", at: 120_000, input: 50 }, owner]]);
    store.db.setAuthorizer((action, name) => action === constants.SQLITE_READ && name === "usage" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      for (const offset of [0n, 1n]) {
        const answer = usage(makeStore(store.db, "."), "en", 0n, 180_000n, offset, false, { workspace: "A", home: false }, true);
        assert.equal(answer.history, undefined, "older clients must not mistake the new records for complete history");
        assert.equal(answer.historyUnavailable, true);
        assert.deepEqual(answer.partialHistory.days.map((d: { calls: number; tokens: number }) => [d.calls, d.tokens]), [[1, 3]]);
      }
    } finally { store.db.setAuthorizer(null); }
  } finally { store.close(); }
});

test("compact coverage keeps its own first call without reading or maintaining the old span", async () => {
  const time = testClock();
  await time.adjust(60_000);
  const store = Store.open(":memory:", null, time.clock);
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "first", at: 120_123, model: "m", subagent: false, fast: false, input: 1, cacheRead: 0,
      cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    store.db.setAuthorizer((action, name) => name === "usage_span" && [constants.SQLITE_READ, constants.SQLITE_UPDATE].includes(action)
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
      assert.equal(store.usageSince(), 120_123);
      assert.equal(usageSince(makeStore(store.db, ".")), 120_123);
      store.db.prepare("DELETE FROM usage WHERE id = ?").run("first");
      store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[{ ...call, id: "later", at: 180_000 }, owner]]);
      assert.equal(store.usageSince(), 60_000, "after deleting the earliest call the coverage start remains a safe bound");
    } finally { store.db.setAuthorizer(null); }
  } finally { store.close(); }
});

test("an unchanged old call does not seed or write context on replay", async () => {
  const time = testClock();
  await time.adjust(10_000);
  const store = Store.open(":memory:", null, time.clock);
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A",
      createdAt: 0, lastActiveAt: 0, runtimeSessionId: "r" });
    store.ranIn("a", "r", "cc");
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "old", at: 11_000, model: "claude-opus-5-5", subagent: false, fast: false, input: 2, cacheRead: 0,
      cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 100_000, window: 200_000 };
    const file = { session: "a", offset: 1, model: "m" };
    store.recordUsage("/a", file, "claude", [[call, owner]]);
    keepUsage(store, "a", true);
    compactUsage(store);
    const changes = () => (store.db.prepare("SELECT total_changes() AS n").get() as { n: number }).n;
    const before = changes();
    store.recordUsage("/a", file, "claude", [[call, owner]]);
    assert.equal(changes(), before, "replaying a call and unchanged file position writes nothing");
    store.recordUsage("/a", { ...file, offset: 2 }, "claude", [[{ ...call, id: "sub", at: 20_000, subagent: true }, owner]]);
    keepUsage(store, "a", true);
    assert.equal(store.sessionUsage("a").contextTokens, 100_000, "the first actual change can still preserve the saved context");
  } finally { store.close(); }
});

test("a saved session context survives the first later subagent call", async () => {
  const time = testClock();
  await time.adjust(10_000);
  const store = Store.open(":memory:", null, time.clock);
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A",
      createdAt: 0, lastActiveAt: 0, runtimeSessionId: "r" });
    store.ranIn("a", "r", "cc");
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "old", at: 11_000, model: "claude-opus-5-5", subagent: false, fast: false, input: 2, cacheRead: 0,
      cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 100_000, window: 200_000 };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    keepUsage(store, "a", true);
    compactUsage(store);
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[{ ...call, id: "sub", at: 20_000, subagent: true, context: null }, owner]]);
    keepUsage(store, "a", true);
    const saved = store.sessionUsage("a");
    assert.deepEqual([saved.modelCalls, saved.model, saved.contextTokens, saved.contextWindow, saved.lastCallAt],
      [2, "claude-opus-5-5", 100_000, 200_000, 11_000]);
    assert.equal(usageNow(store, "a")?.contextTokens, 100_000, "account decisions see the same saved context as the session summary");
    store.recordUsage("/a", { session: "a", offset: 3, model: "m" }, "claude",
      [[{ ...call, id: "main", at: 30_000, context: 120_000 }, owner]]);
    keepUsage(store, "a", true);
    assert.equal(store.sessionUsage("a").contextTokens, 120_000, "a newer main call replaces the saved context");
    store.setRuntimeSessionId("a", null);
    keepUsage(store, "a", true);
    assert.equal(store.sessionUsage("a").contextTokens, undefined, "clearing the conversation clears its context");
  } finally { store.close(); }
});

test("a saved context with calls missing from its summary is not reused", () => {
  const store = Store.open(":memory:");
  try {
    const now = store.now();
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A",
      createdAt: now, lastActiveAt: now, runtimeSessionId: "r" });
    store.ranIn("a", "r", "cc");
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "old", at: now + 1, model: "m", subagent: false, fast: false, input: 2, cacheRead: 0,
      cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 100_000, window: 200_000 };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    keepUsage(store, "a", true);
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[{ ...call, id: "unreported", at: now + 2 }, owner]]);
    compactUsage(store);
    store.recordUsage("/a", { session: "a", offset: 3, model: "m" }, "claude", [[{ ...call, id: "sub", at: now + 3, subagent: true }, owner]]);
    keepUsage(store, "a", true);
    assert.equal(store.sessionUsage("a").contextTokens, undefined, "the earlier saved call is not claimed as the last one");
  } finally { store.close(); }
});

test("reopening does not rebuild the removed usage indexes", () => {
  const dir = mkdtempSync(join(tmpdir(), "compact-usage-"));
  const path = join(dir, "station.db");
  const time = testClock();
  let store = Store.open(path, null, time.clock);
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    store.close();
    store = Store.open(path, null, time.clock);
    const tables = store.db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('usage_detail', 'usage_detail_lookup', 'usage_main_calls')").all();
    assert.deepEqual(tables, []);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "new", at: 60_000, model: "m", subagent: false, fast: false, input: 4, cacheRead: 0,
      cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 100_000, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    assert.deepEqual(usageGroups(makeStore(store.db, dir), 0n, 86_400_000n, 0n, { workspace: "A", home: false }).map((row) => [row.calls, row.input]), [[1, 4]]);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a file-backed station retires the old indexes on a worker after handover", async () => {
  const dir = mkdtempSync(join(tmpdir(), "compact-usage-worker-"));
  const store = Store.open(join(dir, "station.db"));
  try {
    let handedOver!: () => void;
    const fiber = Effect.runFork(retireAfterPrevious(store, new Promise<void>((resolve) => { handedOver = resolve; })));
    assert.ok(store.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_detail'").get());
    handedOver();
    await Effect.runPromise(Fiber.join(fiber));
    assert.deepEqual(store.db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('usage_detail', 'usage_detail_lookup', 'usage_main_calls')").all(), []);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a deep call page does not revisit newer calls with the same or a later timestamp", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number) => ({ id, at, model: "m", subagent: false, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null });
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [0, 1, 2].map((i) => [call(`a${i}`, 1_000), owner]));
    const seq = (store.db.prepare("SELECT rowid AS n FROM usage WHERE id = 'a2'").get() as { n: number }).n;
    let visited = 0;
    store.db.function("page_visit", (_rowid) => { visited++; return 1; });
    const db = new Proxy(store.db, { get(target, key) {
      if (key === "prepare") return (sql: string) => target.prepare(
        sql === USAGE_CALLS_SAME || sql === USAGE_CALLS_EARLIER ? sql.replace("WHERE session = ?1", "WHERE page_visit(rowid) AND session = ?1") : sql);
      const value = Reflect.get(target, key, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = () => usageCallsPage(makeStore(db, "."), "a", 0n, 2_000n, [1_000n, BigInt(seq)], 2, { workspace: "A", home: false }).rows.map((row) => row.id);
    assert.deepEqual(read(), ["a1", "a0"]);
    const before = visited;
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude",
      Array.from({ length: 1_000 }, (_, i) => [call(`later-${i}`, i % 2 ? 1_000 : 1_500), owner]));
    visited = 0;
    assert.deepEqual(read(), ["a1", "a0"]);
    assert.equal(visited, before, "newer calls do not add work to the same page");
  } finally { store.close(); }
});

test("original usage is paged by session with exact bounds and workspace isolation", () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws] of [["a", "A"], ["b", "B"]]) store.insertSession({ key: key!, connect: "ember", runtime: "claude", profile: "cc",
      workspace: `/w/${key}`, token: key!, ws: ws!, createdAt: 0, lastActiveAt: 0 });
    compactUsage(store);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number) => ({ id, at, model: "m", subagent: false, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 100_000, window: null });
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude",
      Array.from({ length: 7 }, (_, i) => [call(`a${i}`, 1_000 + Math.floor(i / 3)), owner]));
    store.recordUsage("/b", { session: "b", offset: 1, model: "m" }, "claude",
      Array.from({ length: 30 }, (_, i) => [call(`b${i}`, 1_000), owner]));
    const reader = makeStore(store.db, ".");
    const viewer = { workspace: "A", home: false };
    const max = 9_223_372_036_854_775_807n;
    assert.deepEqual(usageGroups(reader, 1_001n, 1_002n, 0n, viewer).map((row) => [row.session, row.calls, row.input]), [["a", 3, 3]]);
    assert.deepEqual(usageGroups(reader, 1_001n, 1_001n, 0n, viewer), [], "an empty range stays empty");
    let before: [bigint, bigint] = [max, max];
    const ids: string[] = [];
    for (;;) {
      const page = usageCallsPage(reader, "a", 1_000n, 1_002n, before, 2, viewer);
      ids.push(...page.rows.map((row) => row.id));
      if (page.next === null) break;
      before = [BigInt(page.next.at), BigInt(page.next.seq)];
    }
    assert.deepEqual(ids, ["a5", "a4", "a3", "a2", "a1", "a0"]);
    assert.deepEqual(usageCallsPage(reader, "b", 0n, max, [max, max], 2, viewer), { rows: [], next: null });
    store.db.prepare("DELETE FROM sessions WHERE key = ?").run("b");
    assert.deepEqual(usageCallsPage(reader, "b", 0n, max, [max, max], 2, { workspace: "A", home: true }), { rows: [], next: null },
      "a deleted session's orphaned calls do not become home-workspace data");
    const same = store.db.prepare(`EXPLAIN QUERY PLAN ${USAGE_CALLS_SAME}`).all("a", 1_000n, max, 2) as { detail: string }[];
    const earlier = store.db.prepare(`EXPLAIN QUERY PLAN ${USAGE_CALLS_EARLIER}`).all("a", 1_000n, 1_002n, 2) as { detail: string }[];
    assert.match(same.map((row) => row.detail).join(" | "), /SEARCH usage USING INDEX usage_session \(session=\? AND at=\? AND rowid<\?\)/);
    assert.match(earlier.map((row) => row.detail).join(" | "), /SEARCH usage USING INDEX usage_session \(session=\? AND at>\? AND at<\?\)/);
    assert.ok(![...same, ...earlier].some((row) => row.detail.includes("TEMP B-TREE")));
  } finally { store.close(); }
});

test("the call-page cursor preserves SQLite rowids beyond JavaScript's integer precision", async () => {
  let captured: unknown;
  const route = usageRoutes({ read: (_request: unknown, _operation: string, args: unknown) => {
    captured = args;
    return Promise.resolve({ status: 200, headers: {}, body: Buffer.alloc(0) });
  } } as never, () => false)[0]!;
  const request = { query: [["beforeAt", "9007199254740995"], ["beforeSeq", "9007199254740993"]], viewer: { workspace: "A", home: false } };
  await route.handle(request as never, ["a"]);
  assert.equal((captured as { beforeAt: string }).beforeAt, "9007199254740995");
  assert.equal((captured as { beforeSeq: string }).beforeSeq, "9007199254740993");
});

test("the optional usage chart range reaches the reader and wakes pending totals", async () => {
  let captured: unknown, woken: unknown, wakes = 0;
  const route = usageRoutes({ read: (_request: unknown, _operation: string, args: unknown) => {
    captured = args;
    return Promise.resolve({ status: 200, headers: {}, body: Buffer.alloc(0) });
  } } as never, () => false, (viewer) => { wakes++; woken = viewer; })[1]!;
  const request = { lang: "en", query: [["history", "1"], ["historyFrom", "0"], ["historyTo", "86400000"]], viewer: { workspace: "A", home: false } };
  await route.handle(request as never, []);
  assert.deepEqual((captured as { historyRange: unknown }).historyRange, { from: "0", to: "86400000" });
  assert.equal(wakes, 1);
  assert.deepEqual(woken, request.viewer);
  assert.throws(() => route.handle({ ...request, query: [["historyFrom", "0"]] } as never, []), /both bounds/);
  assert.throws(() => route.handle({ ...request, query: [["historyFrom", "0"], ["historyTo", "60000"]] } as never, []), /invalid history range/);
  assert.equal(wakes, 1);
});

test("pages calls at the same time past SQLite rowids above JavaScript's integer precision", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "a", at: 1_000, model: "m", subagent: false, fast: false, input: 1, cacheRead: 0,
      cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner], [{ ...call, id: "b" }, owner]]);
    store.db.prepare("UPDATE usage SET rowid = ? WHERE id = ?").run(9_007_199_254_740_993n, "a");
    store.db.prepare("UPDATE usage SET rowid = ? WHERE id = ?").run(9_007_199_254_740_995n, "b");
    const reader = makeStore(store.db, ".");
    const max = 9_223_372_036_854_775_807n;
    const viewer = { workspace: "A", home: false };
    const first = usageCallsPage(reader, "a", 0n, max, [max, max], 1, viewer);
    assert.equal(first.rows[0].id, "b");
    assert.deepEqual(first.next, { at: "1000", seq: "9007199254740995" });
    const second = usageCallsPage(reader, "a", 0n, max, [BigInt(first.next!.at), BigInt(first.next!.seq)], 1, viewer);
    assert.equal(second.rows[0].id, "a");
    assert.deepEqual(second.next, { at: "1000", seq: "9007199254740993" });
  } finally { store.close(); }
});
