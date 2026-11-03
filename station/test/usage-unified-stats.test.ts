import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { Effect, Fiber } from "effect";
import { makeStore, usageByDay, USAGE_DETAIL_DAY_SCOPED } from "../src/read/store.ts";
import { Store } from "../src/store/store.ts";
import { retireAfterPrevious } from "../src/usage/module.ts";

test("daily history keeps its compact quarter totals as later calls arrive", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 1, lastActiveAt: 1 });
    const of = { turn: null, person: null, thread: null, profile: "cc" };
    const call = (id: string, input: number) => [{ id, at: 1_700_000_000_000, model: "m", subagent: false, fast: false,
      input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null }, of] as const;
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [call("old", 2)] as never);
    assert.equal(store.retireDuplicateUsage(), true);
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [call("new", 4)] as never);
    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && (table === "usage" || table === "usage_detail")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      const rows = usageByDay(makeStore(store.db, "."), 0n, { workspace: "A", home: false });
      assert.deepEqual(rows.map((row) => [row.calls, row.tokens]), [[2, 8]]);
    } finally { store.db.setAuthorizer(null); }
  } finally { store.close(); }
});

test("daily history keeps compact quarters and uses detail minutes after handover", async () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws] of [["a", "A"], ["b", "B"]]) store.insertSession({ key: key!, connect: "ember", runtime: "claude",
      profile: "cc", workspace: `/w/${key}`, token: key!, ws: ws!, createdAt: 1, lastActiveAt: 1 });
    const owner = { turn: null, person: null, thread: null, profile: "cc" };
    const call = (id: string, at: number, input: number) => [{ id, at, model: "m", subagent: false, fast: false,
      input, cacheRead: 2, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null }, owner] as const;
    const midnight = Date.UTC(2026, 0, 2) - 60_000;
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [call("old", midnight - 1, 10)] as never);
    store.recordUsage("/b", { session: "b", offset: 1, model: "m" }, "claude", [call("other", midnight, 100)] as never);
    let handover!: () => void;
    const previous = new Promise<void>((resolve) => { handover = resolve; });
    const fiber = Effect.runFork(retireAfterPrevious(store, previous));
    assert.ok(store.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = 'usage_minute_add'").get(),
      "the previous process can still read its summaries while handing over");
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [call("during", midnight - 2, 4)] as never);
    assert.deepEqual(usageByDay(makeStore(store.db, "."), 1n, { workspace: "A", home: false }).map((r) => [r.calls, r.tokens]), [[2, 20]],
      "the previous process's daily summary still follows writes during handover");
    handover();
    await Effect.runPromise(Fiber.join(fiber));
    const obsolete = new Set(["usage_quarters", "usage_minute"]);
    store.db.setAuthorizer((action, table) => obsolete.has(table ?? "") &&
      [constants.SQLITE_INSERT, constants.SQLITE_UPDATE, constants.SQLITE_DELETE].includes(action)
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      store.recordUsage("/a", { session: "a", offset: 3, model: "m" }, "claude", [call("new", midnight + 1, 20)] as never);
    } finally { store.db.setAuthorizer(null); }

    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && (table === "usage" || obsolete.has(table ?? ""))
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      const rows = usageByDay(makeStore(store.db, "."), 1n, { workspace: "A", home: false });
      assert.deepEqual(rows.map((r) => [r.day, r.session, r.calls, r.tokens]), [
        ["2026-01-01", "a", 2, 20], ["2026-01-02", "a", 1, 23],
      ]);
    } finally { store.db.setAuthorizer(null); }
    store.db.exec("UPDATE sessions SET ws = 'B' WHERE key = 'a'");
    assert.deepEqual(usageByDay(makeStore(store.db, "."), 1n, { workspace: "A", home: false }), []);
    assert.deepEqual(usageByDay(makeStore(store.db, "."), 1n, { workspace: "B", home: false }).map((r) => [r.day, r.session, r.calls, r.tokens]), [
      ["2026-01-01", "a", 2, 20], ["2026-01-02", "a", 1, 23], ["2026-01-02", "b", 1, 103],
    ]);
  } finally { store.close(); }
});

test("daily detail reads minutes only for quarters that cross local midnight", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 1, lastActiveAt: 1 });
    const owner = { turn: null, person: null, thread: null, profile: "cc" };
    const call = (id: string, at: number) => [{ id, at, model: "m", subagent: false, fast: false,
      input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 0, calls: 1, context: null, window: null }, owner] as const;
    const noon = Date.UTC(2026, 0, 1, 12);
    const midnight = Date.UTC(2026, 0, 2) - 60_000;
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude",
      [...Array.from({ length: 15 }, (_, i) => call(`noon-${i}`, noon + i * 60_000)), call("before", midnight - 1), call("after", midnight + 1)] as never);
    let visited = 0;
    store.db.function("visited_minute", (minute) => { visited++; return minute; });
    const sql = USAGE_DETAIL_DAY_SCOPED.replace("d.bucket < (e.quarter + 1) * 15", "d.bucket < (e.quarter + 1) * 15 AND visited_minute(d.bucket) IS NOT NULL");
    const rows = store.db.prepare(sql).all(1n, "A") as { day: string; calls: number }[];
    assert.deepEqual(rows.map((r) => [r.day, r.calls]), [["2026-01-01", 16], ["2026-01-02", 1]]);
    assert.equal(visited, 2, "the fifteen ordinary minutes are read through their quarter");
  } finally { store.close(); }
});

test("daily detail keeps the same local days and workspace totals through later changes", () => {
  const store = Store.open(":memory:");
  try {
    const workspaces = new Map<string, string | null>([["a", "A"], ["b", "B"], ["home", null]]);
    for (const [key, ws] of workspaces) store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc",
      workspace: `/w/${key}`, token: key, ws, createdAt: 1, lastActiveAt: 1 });
    const offsets = [1, -1, 0, 15, -15, 345, -345, 1_439, -1_439, 1_440, -1_440];
    const times = offsets.flatMap((offset) => {
      const midnight = Date.UTC(2026, 0, 2) - offset * 60_000;
      return [midnight - 900_001, midnight - 30_000, midnight + 30_000, midnight + 900_001];
    }).concat([-900_001, -900_000, -1, 0, 1, 899_999, 900_000]);
    const owner = { turn: null, person: null, thread: null, profile: "cc" };
    const rows = times.map((at, i) => ({ id: `call-${i}`, session: ["a", "b", "home"][i % 3]!, at,
      model: i % 2 ? "m" : null, subagent: false, fast: i % 2 === 0, input: i + 1,
      cacheRead: 2, cacheWrite: 3, cacheWriteLong: 4, output: 5, calls: i % 3 + 1, context: null, window: null }));
    for (const key of workspaces.keys()) {
      store.recordUsage(`/${key}`, { session: key, offset: 1, model: null }, "claude",
        rows.filter((row) => row.session === key).map((row) => [row, owner]));
    }
    assert.equal(store.retireDuplicateUsage(), true);
    rows[0]!.output = 17;
    store.recordUsage(`/${rows[0]!.session}`, { session: rows[0]!.session, offset: 2, model: null }, "claude", [[rows[0]!, owner]]);
    const removed = rows.splice(1, 1)[0]!;
    store.db.prepare("DELETE FROM usage WHERE id = ?").run(removed.id);
    rows[1]!.at = -30_001;
    store.db.prepare("UPDATE usage SET at = ? WHERE id = ?").run(rows[1]!.at, rows[1]!.id);
    store.db.exec("UPDATE sessions SET ws = 'A' WHERE key = 'b'");
    workspaces.set("b", "A");

    for (const offset of offsets) for (const viewer of [null, { workspace: "A", home: false }, { workspace: "B", home: false }, { workspace: "A", home: true }]) {
      const expected = new Map<string, [number, number]>();
      for (const row of rows) {
        const ws = workspaces.get(row.session);
        if (viewer !== null && ws !== viewer.workspace && !(viewer.home && ws === null)) continue;
        const day = new Date(row.at + offset * 60_000).toISOString().slice(0, 10);
        const key = JSON.stringify([day, row.session, "claude", row.model]);
        const total = expected.get(key) ?? [0, 0];
        total[0] += row.calls;
        total[1] += row.input + row.cacheRead + row.cacheWrite + row.cacheWriteLong + row.output;
        expected.set(key, total);
      }
      const actual = usageByDay(makeStore(store.db, "."), BigInt(offset), viewer).map((row) =>
        [JSON.stringify([row.day, row.session, row.runtime, row.model]), [row.calls, row.tokens]] as const);
      assert.deepEqual(actual.sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0), [...expected].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0),
        `offset ${offset}, viewer ${JSON.stringify(viewer)}`);
    }
  } finally { store.close(); }
});

test("an incomplete detail index keeps the existing summary writers", () => {
  const store = Store.open(":memory:");
  try {
    store.db.exec("UPDATE usage_detail_all SET done = 0 WHERE id = 1");
    assert.equal(store.retireDuplicateUsage(), false);
    assert.ok(store.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = 'usage_minute_add'").get());
  } finally { store.close(); }
});

test("incomplete daily quarters keep the existing summary writers", () => {
  const store = Store.open(":memory:");
  try {
    store.db.exec("UPDATE usage_minute_all SET done = 0 WHERE id = 1");
    assert.equal(store.retireDuplicateUsage(), false);
    assert.ok(store.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = 'usage_minute_add'").get());
  } finally { store.close(); }
});

test("reopening does not restore retired summary writers", () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-unified-"));
  const path = join(dir, "stillfail.db");
  let store = Store.open(path);
  try {
    assert.equal(store.retireDuplicateUsage(), true);
    store.close();
    store = Store.open(path);
    const triggers = store.db.prepare("SELECT name FROM sqlite_master WHERE type = 'trigger' AND name IN ('usage_quarters_add','usage_quarters_drop','usage_minute_add','usage_minute_drop')").all();
    assert.deepEqual(triggers, []);
    assert.equal(store.retireDuplicateUsage(), true);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});
