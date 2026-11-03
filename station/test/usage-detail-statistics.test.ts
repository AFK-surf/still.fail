import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { makeStore, usageGroups } from "../src/read/store.ts";
import { usage } from "../src/read/usage.ts";
import { Store } from "../src/store/store.ts";
import { MinuteReader } from "../src/usage/minute-reader.ts";

function forgetDetailIndex(store: Store) {
  const objects = store.db.prepare("SELECT type, name FROM sqlite_master WHERE (name LIKE 'usage_detail_%' OR name = 'usage_detail') AND type IN ('trigger', 'table') ORDER BY type DESC").all() as { type: string; name: string }[];
  for (const object of objects) store.db.exec(`DROP ${object.type.toUpperCase()} "${object.name}"`);
}

test("usage detail reads statistics for the viewer and exact boundaries, including a non-quarter-hour zone", () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws] of [["a", "workspace-a"], ["b", "workspace-b"]]) {
      store.insertSession({ key: key!, connect: key!, runtime: "claude", profile: "cc", workspace: `/w/${key}`,
        token: key!, ws: ws!, createdAt: 1, lastActiveAt: 1 });
    }
    const from = Date.UTC(2026, 0, 1, 23, 58, 10);
    const midnight = Date.UTC(2026, 0, 1, 23, 59);
    const to = Date.UTC(2026, 0, 2, 0, 0, 10);
    const call = (id: string, at: number) => ({ id, at, model: "m", subagent: false, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 0, calls: 1, context: null, window: null });
    const of = { turn: null, person: null, thread: null, profile: null };
    const mine = [from - 1, from, midnight - 1, midnight, to - 1, to].map((at, i) => [call(`a${i}`, at), of] as const);
    const other = Array.from({ length: 2_000 }, (_, i) => [call(`b${i}`, from + i), of] as const);
    store.recordUsage("/a.jsonl", { session: "a", offset: 1, model: "m" }, "claude", mine as never);
    store.recordUsage("/b.jsonl", { session: "b", offset: 1, model: "m" }, "claude", other as never);

    // A non-paged usage request must not consult its per-call facts, including for a minute-offset time zone or the
    // two partial minutes. Those boundaries must still exclude the calls just outside and keep each local day exact.
    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      const result = usage(makeStore(store.db, "."), "en", BigInt(from), BigInt(to), 1n, false,
        { workspace: "workspace-a", home: false });
      assert.deepEqual(result.rows.map((r: { day: string; session: string; calls: number; input: number }) =>
        [r.day, r.session, r.calls, r.input]), [["2026-01-01", "a", 2, 2], ["2026-01-02", "a", 2, 2]]);
    } finally {
      store.db.setAuthorizer(null);
    }
  } finally {
    store.close();
  }
});

test("a usage request waits for old details outside the reader and resumes after handover", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-detail-wait-"));
  const path = join(dir, "stillfail.db");
  let store = Store.open(path);
  store.insertSession({ key: "a", connect: "a", runtime: "claude", profile: "cc", workspace: "/a",
    token: "a", ws: "A", createdAt: 1, lastActiveAt: 1 });
  const of = { turn: null, person: null, thread: null, profile: null };
  store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[{
    id: "one", at: 10, model: "m", subagent: false, fast: false, input: 3, cacheRead: 0,
    cacheWrite: 0, cacheWriteLong: 0, output: 0, calls: 1, context: null, window: null,
  }, of]]);
  forgetDetailIndex(store);
  store.close();
  store = Store.open(path);
  store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage" ? constants.SQLITE_DENY : constants.SQLITE_OK);
  try {
    assert.throws(() => usage(makeStore(store.db, dir), "en", 0n, 100n, 0n, false, { workspace: "A", home: false }),
      /usage detail statistics.*being filled/);
  } finally { store.db.setAuthorizer(null); }
  let handover!: () => void;
  const previousGone = new Promise<void>((resolve) => { handover = resolve; });
  const readers = new Readers(dir, 1, undefined, 1, { previousGone });
  const args = { from: 0, to: 100, tz: 0, reading: false, viewer: { workspace: "A", home: false } };
  const pending = readers.read("usage", args, "en");
  let state = "pending";
  void pending.then(() => { state = "resolved"; }, () => { state = "rejected"; });
  try {
    await readers.read("checkpoint", {}, "en");
    assert.equal(state, "pending");
    handover();
    const result = JSON.parse(await pending);
    assert.equal(result.rows[0].input, 3);
    const exported = JSON.parse(await readers.read("outflowUsage", { ...args, ws: args.viewer }, "en"));
    assert.equal(exported.rows[0].input, 3);
  } finally { handover(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a failed detail backfill reports an error rather than leaving readers waiting", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-detail-error-"));
  const path = join(dir, "stillfail.db");
  let store = Store.open(path);
  store.insertSession({ key: "a", connect: "a", runtime: "claude", profile: "cc", workspace: "/a",
    token: "a", ws: "A", createdAt: 1, lastActiveAt: 1 });
  store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[{
    id: "one", at: 10, model: "m", subagent: false, fast: false, input: 3, cacheRead: 0,
    cacheWrite: 0, cacheWriteLong: 0, output: 0, calls: 1, context: null, window: null,
  }, { turn: null, person: null, thread: null, profile: null }]]);
  forgetDetailIndex(store);
  store.close();
  store = Store.open(path);
  store.db.exec("DROP TABLE usage_detail_lookup");
  const reader = new MinuteReader(path);
  try {
    await assert.rejects(reader.readyDetail({ workspace: "A", home: false }), /no such table: (?:main\.)?usage_detail_lookup/);
    await assert.rejects(reader.readyDetail({ workspace: "A", home: false }), /no such table: (?:main\.)?usage_detail_lookup/);
    await reader.readyRemote();
  } finally { await reader.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("closing while detail statistics wait for handover rejects the request", async () => {
  const reader = new MinuteReader("unused", { previousGone: new Promise<void>(() => {}) });
  const pending = reader.readyDetail({ workspace: "A", home: false });
  await reader.close();
  await assert.rejects(pending, /station stopping/);
});

test("a moved session restarts its detail worker without holding unrelated workspace reads", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-detail-move-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path);
  store.insertSession({ key: "a", connect: "a", runtime: "claude", profile: "cc", workspace: "/a",
    token: "a", ws: "A", createdAt: 1, lastActiveAt: 1 });
  const of = { turn: null, person: null, thread: null, profile: null };
  store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[{
    id: "one", at: 10, model: "m", subagent: false, fast: false, input: 3, cacheRead: 0,
    cacheWrite: 0, cacheWriteLong: 0, output: 0, calls: 1, context: null, window: null,
  }, of]]);
  const reader = new MinuteReader(path);
  try {
    await reader.readyDetail({ workspace: "A", home: false });
    store.db.prepare("UPDATE sessions SET ws = 'B' WHERE key = 'a'").run();
    assert.deepEqual(usageGroups(makeStore(store.db, dir), 0n, 100n, 0n, { workspace: "C", home: false }), []);
    await reader.readyDetail({ workspace: "B", home: false });
    assert.equal(usageGroups(makeStore(store.db, dir), 0n, 100n, 0n, { workspace: "B", home: false })[0]?.input, 3);
    assert.deepEqual(usageGroups(makeStore(store.db, dir), 0n, 100n, 0n, { workspace: "A", home: false }), []);
  } finally { await reader.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("bucketed statistics agree with calls at arbitrary boundaries and time zones", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "a", runtime: "claude", profile: "cc", workspace: "/a",
      token: "a", ws: "A", createdAt: 1, lastActiveAt: 1 });
    const of = { turn: null, person: null, thread: null, profile: null };
    const times = [-90_000_001, -1001, -1000, -999, -1, 0, 1, 999, 1000, 1001, 59_999, 60_000,
      899_999, 900_000, 86_399_999, 86_400_000, 86_400_001];
    const calls = times.map((at, i) => [{ id: `c${i}`, at, model: "m", subagent: false, fast: false, input: i + 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 0, calls: 1, context: null, window: null }, of] as const);
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", calls as never);
    const ranges = [[-90_000_002, 86_400_002], [-1001, 1001], [-1, 1], [1, 1000], [999, 60_001],
      [59_999, 900_001], [86_399_999, 86_400_001], [3, 3]];
    for (const offset of [-90, -1, 0, 1, 345]) for (const [from, to] of ranges) {
      const expected = new Map<string, { calls: number; input: number }>();
      for (const [i, at] of times.entries()) if (at >= from! && at < to!) {
        const day = new Date(at + offset * 60_000).toISOString().slice(0, 10);
        const row = expected.get(day) ?? { calls: 0, input: 0 };
        row.calls++;
        row.input += i + 1;
        expected.set(day, row);
      }
      const got = usageGroups(makeStore(store.db, "."), BigInt(from!), BigInt(to!), BigInt(offset), { workspace: "A", home: false });
      assert.deepEqual(got.map((r) => [r.day, r.calls, r.input]).sort(),
        [...expected].map(([day, row]) => [day, row.calls, row.input]).sort(), `range ${from}..${to}, offset ${offset}`);
    }
  } finally { store.close(); }
});
