import { Effect } from "effect";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { outflowUsage } from "../src/read/outflow.ts";
import { makeStore } from "../src/read/store.ts";
import { usageHistory } from "../src/read/usage.ts";
import { Store } from "../src/store/store.ts";
import { installCompactUsage } from "../src/store/usage-compact.ts";
import { fillUsageStep } from "../src/store/usage-fill.ts";
import { installUsageHistory } from "../src/store/usage-history.ts";
import type { UsageCall, UsageFor } from "../src/store/usage.ts";
import { retireAfterPrevious } from "../src/usage/module.ts";

const HOUR = 3_600_000;
const of: UsageFor = { turn: null, person: "p", thread: null, profile: "cc" };
const call = (id: string, at: number, input: number, output = 1): UsageCall => ({ id, at, model: "m", subagent: false, fast: false,
  input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output, calls: 1, context: 100, window: 1000 });

function session(store: Store, key: string, ws: string | null) {
  store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, ws, createdAt: 0, lastActiveAt: 0 });
}
function record(store: Store, key: string, calls: UsageCall[]) {
  store.recordUsage(`/${key}`, { session: key, offset: calls.length, model: "m" }, "claude", calls.map((c) => [c, of]));
}

/// A station from before the compact statistics, `hours` of calls in two workspaces. `complete`: its old quarters held
/// every call, so the year took them over and only the detail lacks them.
function oldStation(complete: boolean, hours = 200) {
  const store = Store.open(":memory:");
  store.db.exec(`DROP TRIGGER usage_history_add; DROP TRIGGER usage_history_grow; DROP TRIGGER usage_history_move; DROP TRIGGER usage_history_drop;
    DROP TABLE usage_history; DROP TABLE usage_history_total; DROP TABLE usage_history_since;`);
  session(store, "a", "A");
  session(store, "h", null);
  record(store, "a", Array.from({ length: hours }, (_, i) => call(`a${i}`, i * HOUR, i + 1)));
  record(store, "h", Array.from({ length: hours / 2 }, (_, i) => call(`h${i}`, i * 2 * HOUR + 60_000, 1_000 + i)));
  if (!complete) store.db.exec("UPDATE usage_minute_all SET done = 0");
  const now = hours * HOUR;
  installCompactUsage(store.db, () => now);
  installUsageHistory(store.db, now);
  record(store, "a", [call("after", now + HOUR, 5)]);
  return store;
}

const fill = (store: Store) => { let steps = 0; while (!fillUsageStep(store.db, 16)) steps++; return steps; };

/// By UTC day, from the calls themselves.
function truth(store: Store, ws?: string | null) {
  const rows = store.db.prepare(`SELECT strftime('%Y-%m-%d', u.at / 1000, 'unixepoch') AS day, SUM(u.calls) AS calls,
    SUM(u.input + u.output) AS tokens FROM usage u JOIN sessions s ON s.key = u.session ${ws === undefined ? "" : ws === null ? "WHERE s.ws IS NULL" : "WHERE s.ws = ?"}
    GROUP BY 1 ORDER BY 1`).all(...(typeof ws === "string" ? [ws] : [])) as { day: string; calls: number; tokens: number }[];
  return rows.map((r) => [r.day, r.calls, r.tokens]);
}
const year = (store: Store) => usageHistory(makeStore(store.db, "."), 0n, null) as { since?: number; tokens: number; days: { day: string; calls: number; tokens: number }[] };
const yearDays = (store: Store) => year(store).days.map((d) => [d.day, d.calls, d.tokens]);
/// What GET /v1/usage answers for workspace A, by day.
function detail(store: Store, from: number, to: number) {
  const days = new Map<string, [number, number]>();
  const read = outflowUsage(makeStore(store.db, "."), "en", from, to, 0, { workspace: "A", home: false }) as { rows: { day: string; calls: number; input: number; output: number }[] };
  for (const r of read.rows) {
    const d = days.get(r.day) ?? [0, 0];
    days.set(r.day, [d[0] + Number(r.calls), d[1] + Number(r.input) + Number(r.output)]);
  }
  return [...days].sort(([a], [b]) => (a < b ? -1 : 1)).map(([day, [calls, tokens]]) => [day, calls, tokens]);
}

test("a station whose old statistics were never complete gets its old days back, on the page and through outflow", () => {
  const store = oldStation(false);
  try {
    assert.equal(year(store).since, 200 * HOUR);
    assert.deepEqual(detail(store, 0, 201 * HOUR + 1), [["1970-01-09", 1, 6]], "only the call after the statistics began");
    assert.ok(fill(store) > 3, "in batches");
    assert.equal(year(store).since, undefined, "every call is known now");
    assert.deepEqual(yearDays(store), truth(store));
    assert.equal((store.db.prepare("SELECT SUM(tokens) AS n FROM usage_history_total").get() as { n: number }).n, (truth(store) as [string, number, number][]).reduce((n, d) => n + d[2], 0));
    assert.deepEqual(detail(store, 0, 201 * HOUR + 1), truth(store, "A"));
    assert.equal(fillUsageStep(store.db), true, "nothing left, and nothing done");
  } finally { store.close(); }
});

test("each batch leaves the days it reached complete, and a station already complete keeps its year and gets the detail", () => {
  const store = oldStation(false);
  try {
    const since = () => year(store).since!;
    let before = since();
    assert.equal(fillUsageStep(store.db, 16), false);
    assert.ok(since() < before && since() % 900_000 === 0, "the cursor is on a whole quarter");
    before = since();
    const known = truth(store).filter(([day]) => `${day}` > new Date(before).toISOString().slice(0, 10));
    assert.deepEqual(yearDays(store).filter(([day]) => `${day}` > new Date(before).toISOString().slice(0, 10)), known);
    // A stopped fill goes on from where it was: a fresh step, no state but `since`.
    fill(store);
    assert.deepEqual(yearDays(store), truth(store));
  } finally { store.close(); }
  const complete = oldStation(true);
  try {
    const was = yearDays(complete);
    assert.equal(year(complete).since, undefined);
    assert.deepEqual(detail(complete, 0, HOUR), []);
    fill(complete);
    assert.deepEqual(yearDays(complete), was, "the year did not change");
    assert.deepEqual(yearDays(complete), truth(complete));
    assert.deepEqual(detail(complete, 0, 201 * HOUR + 1), truth(complete, "A"));
  } finally { complete.close(); }
});

test("calls written while the fill goes on are counted once, wherever it has reached", () => {
  const store = oldStation(false);
  try {
    assert.equal(fillUsageStep(store.db, 16), false);
    const reached = year(store).since!;
    // Not yet reached: a late call, a response grown, a call removed. Already reached: the same.
    record(store, "a", [call("late-old", 3 * HOUR + 5, 7), call("a10", 10 * HOUR, 11, 50)]);
    store.db.prepare("DELETE FROM usage WHERE id = 'a20'").run();
    record(store, "a", [call("late-new", reached + 5, 9), call("a199", 199 * HOUR, 200, 60)]);
    store.db.prepare("DELETE FROM usage WHERE id = 'a198'").run();
    fill(store);
    assert.deepEqual(yearDays(store), truth(store));
    assert.deepEqual(detail(store, 0, 201 * HOUR + 1), truth(store, "A"));
    record(store, "a", [call("after-all", 2 * HOUR, 3)]);
    store.db.prepare("DELETE FROM usage WHERE id = 'h4'").run();
    assert.deepEqual(yearDays(store), truth(store));
    assert.deepEqual(detail(store, 0, 201 * HOUR + 1), truth(store, "A"));
  } finally { store.close(); }
});

test("a viewer sees only their workspace's old calls", () => {
  const store = oldStation(false);
  try {
    fill(store);
    const days = (workspace: string, home: boolean) => (usageHistory(makeStore(store.db, "."), 0n, { workspace, home }) as ReturnType<typeof year>).days.map((d) => [d.day, d.calls, d.tokens]);
    assert.deepEqual(days("A", false), truth(store, "A"));
    const read = outflowUsage(makeStore(store.db, "."), "en", 0, 201 * HOUR + 1, 0, { workspace: "A", home: false }) as { rows: { session: string }[] };
    assert.deepEqual([...new Set(read.rows.map((r) => r.session))], ["a"]);
  } finally { store.close(); }
});

test("a failed batch leaves everything as it was", () => {
  const store = oldStation(false);
  try {
    const was = [year(store).since, yearDays(store), store.db.prepare("SELECT COUNT(*) AS n FROM usage WHERE compact_counted = 1").get()];
    store.db.exec("CREATE TRIGGER fail_fill BEFORE INSERT ON usage_history BEGIN SELECT RAISE(ABORT, 'no room'); END");
    assert.throws(() => fillUsageStep(store.db, 16), /no room/);
    store.db.exec("DROP TRIGGER fail_fill");
    assert.deepEqual([year(store).since, yearDays(store), store.db.prepare("SELECT COUNT(*) AS n FROM usage WHERE compact_counted = 1").get()], was);
    fill(store);
    assert.deepEqual(yearDays(store), truth(store));
  } finally { store.close(); }
});

test("a session keeps its context as its old calls are taken in, also where the trigger was made before", () => {
  const store = oldStation(false);
  try {
    // The trigger as a station that took the compact statistics before this has it.
    const trigger = store.db.prepare("SELECT sql FROM sqlite_master WHERE name = 'usage_compact_context_change'").get() as { sql: string };
    store.db.exec(`DROP TRIGGER usage_compact_context_change; ${trigger.sql.replace("cache_write_long ON usage", "cache_write_long, compact_counted ON usage")
      .replace("OLD.cache_write_long IS NOT NEW.cache_write_long", "OLD.cache_write_long IS NOT NEW.cache_write_long OR OLD.compact_counted IS NOT NEW.compact_counted")}`);
    assert.match((store.db.prepare("SELECT sql FROM sqlite_master WHERE name = 'usage_compact_context_change'").get() as { sql: string }).sql, /compact_counted/);
    const context = () => store.db.prepare("SELECT context_uncertain, context_runtime, context_model FROM usage_minute_scope WHERE session = 'a'").get();
    const was = context();
    fill(store);
    assert.deepEqual(context(), was);
    assert.doesNotMatch((store.db.prepare("SELECT sql FROM sqlite_master WHERE name = 'usage_compact_context_change'").get() as { sql: string }).sql, /compact_counted/);
  } finally { store.close(); }
});

test("the station's worker fills a file's old calls after handover and tells open pages", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-fill-worker-"));
  const store = Store.open(join(dir, "stillfail.db"));
  try {
    store.db.exec(`DROP TRIGGER usage_history_add; DROP TRIGGER usage_history_grow; DROP TRIGGER usage_history_move; DROP TRIGGER usage_history_drop;
      DROP TABLE usage_history; DROP TABLE usage_history_total; DROP TABLE usage_history_since;`);
    session(store, "a", "A");
    record(store, "a", Array.from({ length: 600 }, (_, i) => call(`a${i}`, i * HOUR, i + 1)));
    store.db.exec("UPDATE usage_minute_all SET done = 0");
    let told = 0;
    const off = store.subscribe((change) => { if (change.type === "usage" && change.statisticsOnly) told++; });
    await Effect.runPromise(retireAfterPrevious(store, Promise.resolve()));
    off();
    assert.ok(told >= 2, "told as the statistics were installed and as the fill ended");
    assert.equal(year(store).since, undefined);
    assert.deepEqual(yearDays(store), truth(store));
    assert.deepEqual(detail(store, 0, 600 * HOUR), truth(store, "A"));
    // On a later start there is nothing to do.
    await Effect.runPromise(retireAfterPrevious(store, Promise.resolve()));
    assert.deepEqual(yearDays(store), truth(store));
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});
