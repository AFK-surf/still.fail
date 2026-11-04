import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { makeStore } from "../src/read/store.ts";
import { usage, usageHistory } from "../src/read/usage.ts";
import { Store } from "../src/store/store.ts";
import type { InWorkspace } from "../src/store/rows.ts";
import { installCompactUsage } from "../src/store/usage-compact.ts";
import { HISTORY_DAYS, installUsageHistory } from "../src/store/usage-history.ts";
import type { UsageCall, UsageFor } from "../src/store/usage.ts";

const of: UsageFor = { turn: null, person: "p", thread: null, profile: "cc" };
const call = (id: string, at: number, input: number, output = 1): UsageCall => ({ id, at, model: "m", subagent: true, fast: false,
  input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output, calls: 1, context: null, window: null });

function session(store: Store, key: string, ws: string | null) {
  store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, ws, createdAt: 0, lastActiveAt: 0 });
}

function record(store: Store, key: string, calls: UsageCall[]) {
  store.recordUsage(`/${key}`, { session: key, offset: calls.length, model: "m" }, "claude", calls.map((c) => [c, of]));
}

/// What the page should say, added up from the calls themselves: by local day, of the sessions `viewer` sees.
function truth(store: Store, offset: number, viewer: InWorkspace | null, ws: Map<string, string | null>): [string, number, number][] {
  const days = new Map<string, [number, number]>();
  const rows = store.db.prepare("SELECT session, at, calls, input + cache_read + cache_write + cache_write_long + output AS tokens FROM usage").all() as
    { session: string; at: number; calls: number; tokens: number }[];
  for (const r of rows) {
    const w = ws.get(r.session) ?? null;
    if (viewer !== null && !(w === viewer.workspace || (w === null && viewer.home !== false))) continue;
    const day = new Date(r.at + offset * 60_000).toISOString().slice(0, 10);
    const d = days.get(day) ?? [0, 0];
    days.set(day, [d[0] + r.calls, d[1] + r.tokens]);
  }
  return [...days].sort(([a], [b]) => (a < b ? -1 : 1)).map(([day, [calls, tokens]]) => [day, calls, tokens]);
}

/// The history as the page reads it, with the calls themselves never read.
function history(store: Store, offset: number, viewer: InWorkspace | null, range?: { from: bigint; to: bigint }) {
  store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage" ? constants.SQLITE_DENY : constants.SQLITE_OK);
  try {
    return usageHistory(makeStore(store.db, "."), BigInt(offset), viewer, undefined, range);
  } finally { store.db.setAuthorizer(null); }
}

const days = (h: { days: { day: string; calls: number; tokens: number }[] }) => h.days.map((d) => [d.day, d.calls, d.tokens]);

test("the history adds each call to its local day as calls are recorded, grow, move and go, reading only its quarters", () => {
  const store = Store.open(":memory:");
  try {
    const ws = new Map<string, string | null>([["a", "A"], ["b", "B"], ["h", null]]);
    for (const [key, w] of ws) session(store, key, w);
    const midnight = Date.UTC(2026, 0, 2);
    const times = [-15, 0, 15, 345, -345, 480, 1_440, -1_440].flatMap((offset) => {
      const local = midnight - offset * 60_000;
      return [local - 900_001, local - 1, local, local + 899_999, local + 900_000];
    });
    record(store, "a", times.map((at, i) => call(`a${i}`, at, i + 1)));
    record(store, "b", times.slice(0, 9).map((at, i) => call(`b${i}`, at, 100 + i)));
    record(store, "h", times.slice(5, 20).map((at, i) => call(`h${i}`, at, 1_000 + i)));
    // A response grows; a call is read again later at another time; one is removed; one moves to another session.
    record(store, "a", [call("a3", times[3]!, 4, 50)]);
    store.db.prepare("UPDATE usage SET at = at + 86400000 WHERE id = 'a7'").run();
    store.db.prepare("DELETE FROM usage WHERE id = 'b2'").run();
    store.db.prepare("UPDATE usage SET session = 'h' WHERE id = 'a9'").run();
    for (const offset of [0, 15, -15, 345, -345, 480, 1_440, -1_440]) {
      for (const viewer of [null, { workspace: "A", home: false }, { workspace: "A", home: true }, { workspace: "B", home: false }]) {
        assert.deepEqual(days(history(store, offset, viewer)), truth(store, offset, viewer, ws), `offset ${offset}, ${JSON.stringify(viewer)}`);
      }
    }
  } finally { store.close(); }
});

test("a year's read takes its own quarters by key: an older history or another workspace adds nothing to it", () => {
  const store = Store.open(":memory:");
  try {
    session(store, "a", "A");
    session(store, "b", "B");
    const day = 86_400_000;
    const to = Date.UTC(2026, 0, 1);
    const range = { from: BigInt(to - 364 * day), to: BigInt(to) };
    record(store, "a", Array.from({ length: 50 }, (_, i) => call(`year${i}`, to - (i + 1) * day, 1)));
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${HISTORY_DAYS}`).all("A", 0n, 1n, 0n) as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /SEARCH usage_history USING PRIMARY KEY \(scope=\? AND quarter>\? AND quarter<\?\)/);
    let visited = 0;
    store.db.function("visited", (q) => { visited++; return q; });
    const tracked = store.db.prepare(HISTORY_DAYS.replace("WHERE scope = ?1", "WHERE visited(quarter) IS NOT NULL AND scope = ?1"));
    const read = () => { visited = 0; tracked.all("A", range.from / 900_000n, range.to / 900_000n, 0n); return visited; };
    const before = read();
    assert.equal(before, 50);
    // Years before, and another workspace in the same days: as much again, many times over.
    record(store, "a", Array.from({ length: 5_000 }, (_, i) => call(`old${i}`, to - 400 * day - i * 900_000, 1)));
    record(store, "b", Array.from({ length: 5_000 }, (_, i) => call(`other${i}`, to - 1 - i * 900_000, 1)));
    assert.equal(read(), before);
    const year = history(store, 0, { workspace: "A", home: false }, range);
    assert.equal(year.days.length, 50);
    assert.equal(year.tokens, 5_050 * 2, "the year's total is the workspace's in all, its older calls too");
    assert.equal(year.beforeDay, "2026-01-01");
    assert.equal(year.since, undefined, "a new station counts from its first call");
  } finally { store.close(); }
});

test("the total stops at the year's end and an older client still gets every day", () => {
  const store = Store.open(":memory:");
  try {
    session(store, "a", "A");
    record(store, "a", [call("old", -86_400_000, 10), call("new", 60_000, 19), call("future", 86_400_000, 6)]);
    const a = { workspace: "A", home: false };
    const answer = usage(makeStore(store.db, "."), "en", 0n, 86_400_000n, 0n, false, a, true, { historyRange: { from: 0n, to: 86_400_000n } });
    assert.deepEqual(answer.history.days.map((d: { day: string; tokens: number }) => [d.day, d.tokens]), [["1970-01-01", 20]]);
    assert.equal(answer.history.tokens, 31, "the older day stays in the total; tomorrow's call is not in it yet");
    assert.equal(answer.history.beforeDay, "1970-01-02");
    const old = usage(makeStore(store.db, "."), "en", 0n, 86_400_000n, 0n, false, a, true);
    assert.deepEqual(old.history.days.map((d: { day: string }) => d.day), ["1969-12-31", "1970-01-01", "1970-01-02"]);
    assert.equal(old.history.tokens, undefined);
  } finally { store.close(); }
});

test("when the home workspace changes, its whole history goes with it, its sessions gone too", () => {
  const store = Store.open(":memory:");
  try {
    session(store, "h", null);
    session(store, "gone", null);
    session(store, "b", "B");
    record(store, "h", [call("h", 0, 1)]);
    record(store, "gone", [call("gone", 0, 10)]);
    record(store, "b", [call("b", 0, 100)]);
    store.deleteSession("gone");
    store.setSessionsWs(null, "B");
    assert.deepEqual(days(history(store, 0, { workspace: "B", home: false })), [["1970-01-01", 3, 114]]);
    assert.deepEqual(days(history(store, 0, null)), [["1970-01-01", 3, 114]]);
    record(store, "h", [call("h2", 0, 1_000)]);
    assert.deepEqual(days(history(store, 0, { workspace: "B", home: false })), [["1970-01-01", 4, 1_115]]);
  } finally { store.close(); }
});

/// A station from before: its database without the history, as it was then.
function before(store: Store) {
  store.db.exec(`DROP TRIGGER usage_history_add; DROP TRIGGER usage_history_grow; DROP TRIGGER usage_history_move; DROP TRIGGER usage_history_drop;
    DROP TABLE usage_history; DROP TABLE usage_history_total; DROP TABLE usage_history_since;
    ALTER TABLE usage DROP COLUMN history_counted;`);
}

test("installed on an older station, the history counts new calls without reconstructing older statistics", () => {
  for (const state of ["kept", "compact", "stopped"] as const) {
    const store = Store.open(":memory:");
    try {
      before(store);
      for (const [key, w] of [["a", "A"], ["h", null]] as const) session(store, key, w);
      // Calls while the old quarters were kept with them.
      record(store, "a", Array.from({ length: 40 }, (_, i) => call(`old${i}`, i * 3_600_000, 1 + i)));
      record(store, "h", [call("home", 600_000, 7)]);
      const last = 39 * 3_600_000;
      if (state === "stopped") {
        // The emergency stop: the old quarters stopped being kept at a time not written down, a while before the
        // compact statistics began. A call in their last quarter and later ones went to neither.
        store.db.exec("DROP TRIGGER usage_minute_add; DROP TRIGGER usage_minute_drop; DROP TRIGGER usage_minute_grow");
        store.db.exec("CREATE TABLE usage_retired_detail (id INTEGER PRIMARY KEY CHECK (id = 1)); INSERT INTO usage_retired_detail VALUES (1)");
        record(store, "a", [call("gap-last-quarter", last + 60_000, 500), call("gap", last + 7_200_000, 600)]);
      }
      if (state !== "kept") {
        installCompactUsage(store.db, () => last + 10_800_000);
        record(store, "a", [call("compact", last + 14_400_000, 700)]);
        // An old call's response grows: the compact statistics keep the old quarters with it (not after a stop).
        if (state === "compact") record(store, "a", [call("old0", 0, 1, 9)]);
      }
      installUsageHistory(store.db, last + 20_000_000);
      for (const viewer of [null, { workspace: "A", home: false }, { workspace: "A", home: true }]) {
        assert.deepEqual(days(history(store, 480, viewer)), [], `${state} ${JSON.stringify(viewer)}`);
      }
      assert.equal(history(store, 0, null).since, last + 20_000_000, `${state}: the older history is incomplete`);
      record(store, "a", [call("after", last + 30_000_000, 3)]);
      assert.deepEqual(days(history(store, 0, null)), [["1970-01-02", 1, 4]]);
    } finally { store.close(); }
  }
});

test("a station whose old quarters were incomplete does not reconstruct them", () => {
  const store = Store.open(":memory:");
  try {
    before(store);
    session(store, "a", "A");
    record(store, "a", [call("old", 0, 1)]);
    store.db.exec("UPDATE usage_minute_all SET done = 0");
    installCompactUsage(store.db, () => 3_600_000);
    record(store, "a", [call("new", 7_200_000, 2)]);
    installUsageHistory(store.db, 10_000_000);
    const h = history(store, 0, null);
    assert.equal(h.since, 10_000_000);
    assert.deepEqual(days(h), []);
  } finally { store.close(); }
});
