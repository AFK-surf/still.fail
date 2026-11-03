import assert from "node:assert/strict";
import { test } from "node:test";
import type { LiveHub } from "../src/sessions/live.ts";
import { Store, USAGE_SUMMARY_AFTER } from "../src/store/store.ts";
import type { UsageCounter } from "../src/usage/counter.ts";
import { keepCounted, keepUsage } from "../src/usage/module.ts";

test("starting usage does not walk every session, and an interrupted summary upgrade resumes once", async () => {
  const store = Store.open(":memory:");
  const live = { countWith() {}, usageCounted() {} } as unknown as LiveHub;
  const counter = {} as UsageCounter;
  const keys = ["a", "b", "c"];
  let stop = () => {};
  try {
    for (const key of keys) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1 });
      store.ranIn(key, `r-${key}`, "cc");
      store.setRuntimeSessionId(key, `r-${key}`);
      store.recordUsage(`/${key}`, { session: key, offset: 1, model: null }, "claude", [[{
        id: `call-${key}`, at: store.now() + 1000, model: "claude-opus-5-5", subagent: false, fast: false,
        input: 1, cacheRead: 0, cacheWrite: 10, cacheWriteLong: 0, output: 1, calls: 1, context: 11, window: 100,
      }, { turn: null, thread: null, person: null, profile: "cc" }]]);
      keepUsage(store, key, true);
      const { lastCallAt: _at, cacheMs: _cache, rereadCost: _cost, ...old } = store.sessionUsage(key);
      store.setSessionUsage(key, old, true);
    }
    const previousKeys = store.sessionKeys.bind(store);
    store.sessionKeys = () => { throw new Error("startup enumerated all sessions"); };
    let first: (() => void) | undefined;
    const one = new Promise<void>((resolve) => { first = resolve; });
    const unsubscribe = store.subscribe((change) => {
      if (change.type === "session" && store.sessionUsage(change.key)?.cacheMs !== undefined) {
        stop();
        first?.();
      }
    });
    stop = keepCounted(store, live, counter);
    assert.ok(keys.every((key) => store.sessionUsage(key)?.cacheMs === undefined), "startup returns before historical summaries are refreshed");
    await one;
    unsubscribe();
    assert.ok(keys.some((key) => store.sessionUsage(key)?.cacheMs === undefined), "a stop leaves the rest for later");

    let complete: (() => void) | undefined;
    const rest = new Promise<void>((resolve) => { complete = resolve; });
    const changed = store.subscribe(() => {
      if (keys.every((key) => store.sessionUsage(key)?.cacheMs === 300_000)) complete?.();
    });
    stop = keepCounted(store, live, counter);
    await rest;
    changed();
    // Let the worker persist that it reached the end before stopping and starting it again.
    await new Promise<void>((resolve) => setImmediate(resolve));
    await new Promise<void>((resolve) => setImmediate(resolve));
    stop();
    let recalculated = 0;
    const usageOf = store.usageOfSession.bind(store);
    store.usageOfSession = (key) => { recalculated++; return usageOf(key); };
    stop = keepCounted(store, live, counter);
    await new Promise<void>((resolve) => setImmediate(resolve));
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(recalculated, 0, "the completed upgrade is not repeated on the next start");
    store.sessionKeys = previousKeys;
  } finally {
    stop();
    store.close();
  }
});

test("a first count of many sessions does not synchronously recount all their summaries", async () => {
  const store = Store.open(":memory:");
  const live = { countWith() {}, usageCounted() {} } as unknown as LiveHub;
  const stop = keepCounted(store, live, {} as UsageCounter);
  try {
    const keys = Array.from({ length: 40 }, (_, i) => `s-${String(i).padStart(2, "0")}`);
    for (const key of keys) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1 });
      store.recordUsage(`/${key}`, { session: key, offset: 1, model: null }, "claude", [[{
        id: `call-${key}`, at: 1000, model: "claude-opus-5-5", subagent: false, fast: false,
        input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 1, window: 100,
      }, { turn: null, thread: null, person: null, profile: "cc" }]]);
    }
    let calculations = 0;
    const usageOf = store.usageOfSession.bind(store);
    store.usageOfSession = (key) => { calculations++; return usageOf(key); };
    let complete: (() => void) | undefined;
    const done = new Promise<void>((resolve) => { complete = resolve; });
    const unsubscribe = store.subscribe(() => {
      if (keys.every((key) => store.sessionUsage(key)?.modelCalls === 1)) complete?.();
    });
    store.usageChanged(keys);
    assert.ok(calculations <= 1, "the notice does not count the whole history before returning");
    await done;
    unsubscribe();
  } finally {
    stop();
    store.close();
  }
});

test("the upgrade seeks one session and gives both old and changed sessions a turn", () => {
  const store = Store.open(":memory:");
  try {
    for (let i = 0; i < 500; i++) {
      const key = `s-${String(i).padStart(4, "0")}`;
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1 });
    }
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${USAGE_SUMMARY_AFTER}`).all("s-0100") as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /SEARCH sessions USING .*\(key>\?\)/);
    let visited = 0;
    store.db.function("inspected", (_key) => { visited++; return 1; });
    const query = USAGE_SUMMARY_AFTER.replace(" ORDER BY", " AND inspected(key) ORDER BY");
    assert.equal((store.db.prepare(query).get("s-0100") as { key: string }).key, "s-0101");
    assert.equal(visited, 1, "only the next key is visited despite hundreds of other sessions");

    store.startUsageSummaryRefresh(1);
    const dirty = store.db.prepare("INSERT INTO usage_summary_dirty (session) VALUES (?)");
    dirty.run("z");
    dirty.run("s-0200");
    const first = store.nextUsageSummaryRefresh(true)!;
    assert.deepEqual(first, { key: "z", upgrade: false });
    store.refreshSessionUsage(first.key, () => null);
    dirty.run("z");
    assert.equal(store.nextUsageSummaryRefresh(true)?.key, "s-0200", "a repeatedly changed session joins the back of the queue");
    assert.deepEqual(store.nextUsageSummaryRefresh(false), { key: "s-0000", upgrade: true }, "the old summaries also keep advancing");
  } finally {
    store.close();
  }
});

test("an older writer's changes are reflected during and after handover", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const store = Store.open(":memory:");
  const live = { countWith() {}, usageCounted() {} } as unknown as LiveHub;
  let release: (() => void) | undefined;
  const previous = new Promise<void>((resolve) => { release = resolve; });
  let stop = () => {};
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", createdAt: 1, lastActiveAt: 1 });
    store.recordUsage("/a", { session: "a", offset: 1, model: null }, "claude", [[{
      id: "call", at: 1000, model: "claude-opus-5-5", subagent: false, fast: false,
      input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 1, window: 100,
    }, { turn: null, thread: null, person: null, profile: "cc" }]]);
    keepUsage(store, "a", true);
    stop = keepCounted(store, live, {} as UsageCounter, previous);
    store.db.prepare("UPDATE usage SET output = 9 WHERE id = 'call'").run();
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(store.sessionUsage("a")?.outputTokens, 1, "the old writer still has the database");
    let refreshed: (() => void) | undefined;
    const done = new Promise<void>((resolve) => { refreshed = resolve; });
    const unsubscribe = store.subscribe(() => {
      if (store.sessionUsage("a")?.outputTokens === 9) refreshed?.();
    });
    release?.();
    await done;
    unsubscribe();
    assert.equal(store.sessionUsage("a")?.outputTokens, 9);
    // Once the initial upgrade is finished, another connection has no in-process event with which to wake this one.
    await new Promise<void>((resolve) => setImmediate(resolve));
    await new Promise<void>((resolve) => setImmediate(resolve));
    let followed: (() => void) | undefined;
    const followedWrite = new Promise<void>((resolve) => { followed = resolve; });
    const again = store.subscribe(() => {
      if (store.sessionUsage("a")?.outputTokens === 11) followed?.();
    });
    store.db.prepare("UPDATE usage SET output = 11 WHERE id = 'call'").run();
    t.mock.timers.tick(1_000);
    await followedWrite;
    again();
    assert.equal(store.sessionUsage("a")?.outputTokens, 11);
  } finally {
    stop();
    store.close();
  }
});

test("a temporary failure starting the upgrade is retried", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const store = Store.open(":memory:");
  const live = { countWith() {}, usageCounted() {} } as unknown as LiveHub;
  let stop = () => {};
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", createdAt: 1, lastActiveAt: 1 });
    store.recordUsage("/a", { session: "a", offset: 1, model: null }, "claude", [[{
      id: "call", at: 1000, model: "claude-opus-5-5", subagent: false, fast: false,
      input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 1, window: 100,
    }, { turn: null, thread: null, person: null, profile: "cc" }]]);
    const start = store.startUsageSummaryRefresh.bind(store);
    let attempts = 0;
    let attempted: (() => void) | undefined;
    const firstAttempt = new Promise<void>((resolve) => { attempted = resolve; });
    store.startUsageSummaryRefresh = (version) => {
      if (++attempts === 1) { attempted?.(); throw new Error("temporary failure"); }
      start(version);
    };
    let refreshed: (() => void) | undefined;
    const done = new Promise<void>((resolve) => { refreshed = resolve; });
    const unsubscribe = store.subscribe(() => {
      if (store.sessionUsage("a")?.modelCalls === 1) refreshed?.();
    });
    stop = keepCounted(store, live, {} as UsageCounter);
    await firstAttempt;
    assert.equal(attempts, 1);
    t.mock.timers.tick(5_000);
    await done;
    unsubscribe();
    assert.equal(attempts, 2);
  } finally {
    stop();
    store.close();
  }
});
