import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { Effect, Fiber } from "effect";
import { error, json, type Request } from "../src/api/request.ts";
import { usageRoutes } from "../src/api/routes/usage.ts";
import { Readers } from "../src/read/pool.ts";
import * as reads from "../src/read/store.ts";
import { usage } from "../src/read/usage.ts";
import { Store } from "../src/store/store.ts";
import { installCompactUsage } from "../src/store/usage-compact.ts";
import { installUsageSummaryBlocks, usageSummaryBlocksStep, USAGE_SUMMARY_PENDING, type UsageSummaryRange } from "../src/store/usage-summary-blocks.ts";
import { retireUntilComplete, watchCompactMoves } from "../src/usage/module.ts";

test("showing available history during preparation does not read old calls or compact minutes", () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-history-without-details-"));
  const store = Store.open(join(dir, "stillfail.db"));
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(store.db, () => 0);
    store.db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    store.db.exec(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES ('a', 0, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, 'WA', 0)`);
    store.db.exec("INSERT INTO usage_history VALUES ('A', 0, 2, 19)");
    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && (table === "usage" || table === "usage_compact")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    const result = usage(reads.makeStore(store.db, dir), "en", 0n, 60_000n, 0n, false, { workspace: "A", home: false }, true,
      { detailsPreparing: true, historyRange: { from: 0n, to: 86_400_000n } });
    assert.equal(result.detailsPreparing, true);
    assert.deepEqual((result.history as { days: { calls: number; tokens: number }[] }).days.map(({ calls, tokens }) => [calls, tokens]), [[2, 19]]);
  } finally {
    store.db.setAuthorizer(null);
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a page can see its history while recent usage is being prepared", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-partial-history-"));
  const store = Store.open(join(dir, "stillfail.db"));
  const readers = new Readers(dir, 1);
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(store.db, () => 0);
    store.db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    store.db.exec(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES ('a', 0, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, 'WA', 0)`);
    store.db.exec("INSERT INTO usage_history VALUES ('A', 0, 2, 19), ('B', 0, 90, 900)");
    installUsageSummaryBlocks(store.db);
    let waits = 0;
    const tools = { read: async (request: Request, op: string, args: unknown) => {
      try { return json(200, await readers.read(op, args, request.lang, { signal: request.signal })); }
      catch (cause) {
        const e = cause as Error & { status?: number };
        return error(e.status ?? 500, e.message);
      }
    } };
    // The old client must wait. If a new one waits here too, fail immediately rather than measuring a duration.
    const waitSummary = async () => { waits++; throw new Error("waiting for grouped usage"); };
    const route = usageRoutes(tools as never, () => false, () => {}, waitSummary).find((r) => r.pattern.test("/usage"))!;
    const query: [string, string][] = [["from", "0"], ["to", "60000"], ["tz", "0"], ["history", "1"],
      ["historyFrom", "0"], ["historyTo", "86400000"]];
    const request = { method: "GET", path: "/usage", query, headers: {}, body: Buffer.alloc(0),
      viewer: { workspace: "A", home: false }, lang: "en" } as unknown as Request;
    const partial = await route.handle({ ...request, query: [...query, ["allowPartial", "1"]] }, []);
    assert.equal(partial.status, 200, "the already available history does not wait for the recent summary");
    const answer = JSON.parse((partial.body as Buffer).toString());
    assert.equal(answer.detailsPreparing, true);
    assert.deepEqual(answer.rows, []);
    assert.deepEqual(answer.history.days.map((day: { calls: number; tokens: number }) => [day.calls, day.tokens]), [[2, 19]],
      "the partial result is scoped to the viewer's workspace");
    assert.equal(waits, 0);
    const old = await route.handle(request, []);
    assert.equal(old.status, 503, "an older client is never given incomplete rows as a finished answer");
    assert.equal(waits, 1);
  } finally {
    readers.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a usage stream sends available history and then the prepared details on the same request", async () => {
  let release!: () => void;
  let sawWait!: () => void;
  const waiting = new Promise<void>((resolve) => { sawWait = resolve; });
  const calls: Record<string, unknown>[] = [];
  const tools = { read: async (_: Request, op: string, args: Record<string, unknown>) => {
    assert.equal(op, "usage");
    calls.push(args);
    if (args.detailsPreparing) return json(200, JSON.stringify({ detailsPreparing: true, rows: [], history: { days: [1] } }));
    if (args.summaryPrepared) return json(200, JSON.stringify({ rows: [{ calls: 3 }], history: { days: [2] } }));
    return error(503, USAGE_SUMMARY_PENDING);
  } };
  const route = usageRoutes(tools as never, () => false, () => {}, async (_viewer, _range, signal) => {
    await new Promise<void>((resolve, reject) => {
      release = resolve;
      signal?.addEventListener("abort", () => reject(new Error("read cancelled")), { once: true });
      sawWait();
    });
  }).find((r) => r.pattern.test("/usage"))!;
  const request = { method: "GET", path: "/usage", query: [["from", "0"], ["to", "60000"], ["tz", "0"],
    ["history", "1"], ["allowPartial", "1"]], headers: { accept: "text/event-stream" }, body: Buffer.alloc(0),
    viewer: { workspace: "A", home: false }, lang: "en" } as unknown as Request;
  const response = await route.handle(request, []);
  assert.equal(response.headers["content-type"], "text/event-stream");
  const body = (response.body as AsyncIterable<Buffer>)[Symbol.asyncIterator]();
  try {
    const first = await body.next();
    assert.match(first.value!.toString(), /event: usage\ndata: .*"detailsPreparing":true/);
    await waiting;
    release();
    const final = await body.next();
    assert.match(final.value!.toString(), /event: usage\ndata: .*"calls":3/);
    assert.equal((await body.next()).done, true);
    assert.equal(calls.filter((args) => args.summaryPrepared === true).length, 1);
  } finally {
    await body.return?.();
  }
});

test("leaving a preparing usage stream cancels its background request", async () => {
  let started!: () => void;
  let cancelled!: () => void;
  const waiting = new Promise<void>((resolve) => { started = resolve; });
  const aborted = new Promise<void>((resolve) => { cancelled = resolve; });
  const tools = { read: async (_: Request, _op: string, args: Record<string, unknown>) => args.detailsPreparing
    ? json(200, JSON.stringify({ detailsPreparing: true, rows: [], history: { days: [] } })) : error(503, USAGE_SUMMARY_PENDING) };
  const route = usageRoutes(tools as never, () => false, () => {}, async (_viewer, _range, signal) => {
    await new Promise<void>((_resolve, reject) => {
      signal?.addEventListener("abort", () => { cancelled(); reject(new Error("read cancelled")); }, { once: true });
      started();
    });
  }).find((r) => r.pattern.test("/usage"))!;
  const request = { method: "GET", path: "/usage", query: [["history", "1"], ["allowPartial", "1"]],
    headers: { accept: "text/event-stream" }, body: Buffer.alloc(0), viewer: { workspace: "A", home: false }, lang: "en" } as unknown as Request;
  const response = await route.handle(request, []);
  assert.equal(response.headers["content-type"], "text/event-stream");
  const body = (response.body as AsyncIterable<Buffer>)[Symbol.asyncIterator]();
  await body.next();
  await waiting;
  const blocked = body.next();
  await body.return?.();
  await aborted;
  assert.equal((await blocked).done, true);
});

test("a preparing usage stream stays alive until it is closed", async (t) => {
  t.mock.timers.enable({ apis: ["setInterval"] });
  let started!: () => void;
  const waiting = new Promise<void>((resolve) => { started = resolve; });
  const tools = { read: async (_: Request, _op: string, args: Record<string, unknown>) => args.detailsPreparing
    ? json(200, JSON.stringify({ detailsPreparing: true, rows: [], history: { days: [] } })) : error(503, USAGE_SUMMARY_PENDING) };
  const route = usageRoutes(tools as never, () => false, () => {}, async (_viewer, _range, signal) => {
    await new Promise<void>((_resolve, reject) => {
      signal?.addEventListener("abort", () => reject(new Error("read cancelled")), { once: true });
      started();
    });
  }).find((r) => r.pattern.test("/usage"))!;
  const request = { method: "GET", path: "/usage", query: [["history", "1"], ["allowPartial", "1"]],
    headers: { accept: "text/event-stream" }, body: Buffer.alloc(0), viewer: { workspace: "A", home: false }, lang: "en" } as unknown as Request;
  const response = await route.handle(request, []);
  const body = (response.body as AsyncIterable<Buffer>)[Symbol.asyncIterator]();
  try {
    await body.next();
    await waiting;
    const next = body.next();
    t.mock.timers.tick(15_000);
    assert.equal((await next).value!.toString(), ": ping\n\n");
  } finally {
    await body.return?.();
  }
  t.mock.timers.tick(15_000);
  assert.equal((await body.next()).done, true);
});

test("a streamed usage page receives history and the prepared summary from real readers", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-stream-preparing-"));
  const store = Store.open(join(dir, "stillfail.db"));
  const readers = new Readers(dir, 1);
  let handover!: () => void;
  const mover = watchCompactMoves(store, new Promise<void>((resolve) => { handover = resolve; }));
  let body: AsyncIterator<Buffer> | null = null;
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(store.db, () => 0);
    store.db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    store.db.exec(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES ('a', 0, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, 'WA', 0)`);
    store.db.exec("INSERT INTO usage_history VALUES ('A', 0, 2, 19)");
    installUsageSummaryBlocks(store.db);
    const tools = { read: async (request: Request, op: string, args: unknown) => {
      try { return json(200, await readers.read(op, args, request.lang, { signal: request.signal })); }
      catch (cause) {
        const e = cause as Error & { status?: number };
        return error(e.status ?? 500, e.message);
      }
    } };
    const route = usageRoutes(tools as never, () => false, mover.read, mover.waitSummary).find((r) => r.pattern.test("/usage"))!;
    const request = { method: "GET", path: "/usage", query: [["from", "0"], ["to", "60000"], ["tz", "0"],
      ["history", "1"], ["allowPartial", "1"], ["historyFrom", "0"], ["historyTo", "86400000"]],
      headers: { accept: "text/event-stream" }, body: Buffer.alloc(0), viewer: { workspace: "A", home: false }, lang: "en" } as unknown as Request;
    const response = await route.handle(request, []);
    body = (response.body as AsyncIterable<Buffer>)[Symbol.asyncIterator]();
    const nextUsage = async () => {
      for (;;) {
        const next = await body!.next();
        assert.equal(next.done, false, "the stream must answer before it closes");
        const chunk = next.value!.toString("utf8");
        if (chunk.startsWith(": ")) continue;
        assert.ok(chunk.startsWith("event: usage\ndata: "), chunk);
        return JSON.parse(chunk.slice("event: usage\ndata: ".length));
      }
    };
    const first = await nextUsage();
    assert.equal(first.detailsPreparing, true);
    assert.deepEqual(first.history.days.map((day: { calls: number; tokens: number }) => [day.calls, day.tokens]), [[2, 19]]);
    assert.ok(JSON.parse(await readers.read("summary", { key: "a" }, "en")), "another request can use the only reader");
    handover();
    const complete = await nextUsage();
    assert.notEqual(complete.detailsPreparing, true);
    assert.equal(complete.rows.reduce((n: number, row: { calls: number }) => n + row.calls, 0), 1);
    assert.equal((await body.next()).done, true);
  } finally {
    await body?.return?.();
    handover();
    await mover.close();
    readers.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a usage page waits for its summary without holding the reader, and can leave while waiting", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-summary-preparing-"));
  const store = Store.open(join(dir, "stillfail.db"));
  const readers = new Readers(dir, 1);
  let handover!: () => void;
  const mover = watchCompactMoves(store, new Promise<void>((resolve) => { handover = resolve; }));
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(store.db, () => 0);
    store.db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    const put = store.db.prepare(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES ('a', ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, 'WA', 0)`);
    for (let minute = -1_000; minute < 200; minute++) put.run(minute);
    installUsageSummaryBlocks(store.db);
    const pending: (() => void)[] = [];
    const tools = { read: async (request: Request, op: string, args: unknown) => {
      try { return json(200, await readers.read(op, args, request.lang, { signal: request.signal })); }
      catch (cause) {
        const e = cause as Error & { status?: number };
        if (e.message === USAGE_SUMMARY_PENDING) pending.shift()?.();
        return error(e.status ?? 500, e.message);
      }
    } };
    const route = usageRoutes(tools as never, () => false, mover.read, mover.waitSummary).find((r) => r.pattern.test("/usage"))!;
    const viewer = { workspace: "A", home: false };
    const request = { method: "GET", path: "/usage", query: [["from", "0"], ["to", String(200 * 60_000)], ["tz", "0"]],
      headers: {}, body: Buffer.alloc(0), viewer, lang: "en" } as unknown as Request;
    const noticed = () => new Promise<void>((resolve) => pending.push(resolve));
    const seenFirst = noticed();
    const first = route.handle(request, []);
    await seenFirst;
    const seenSecond = noticed();
    const controller = new AbortController();
    const second = route.handle({ ...request, signal: controller.signal }, []);
    await seenSecond;
    controller.abort();
    const cancelled = await second;
    assert.equal(cancelled.status, 503);
    assert.deepEqual(JSON.parse((cancelled.body as Buffer).toString()), { error: "read cancelled" });
    const other = JSON.parse(await readers.read("summary", { key: "a" }, "en"));
    assert.ok(other, "another request can use the only reader while usage is being prepared");
    handover();
    const answer = await first;
    assert.equal(answer.status, 200);
    const result = JSON.parse((answer.body as Buffer).toString());
    assert.equal(result.rows.reduce((n: number, row: { calls: number }) => n + row.calls, 0), 200);
    assert.equal((store.db.prepare("SELECT done FROM usage_summary_blocks_progress WHERE id = 1").get() as { done: number }).done, 0,
      "the requested range was answered without waiting for older minutes in the same workspace");
    const partialFrom = -60_001n, partialTo = 200n * 60_000n - 1n;
    const expected = reads.usageGroups(reads.makeStore(store.db, dir), partialFrom, partialTo, 0n, viewer);
    const partial = await route.handle({ ...request, query: [["from", String(partialFrom)], ["to", String(partialTo)], ["tz", "0"]] }, []);
    assert.equal(partial.status, 200);
    const totals = (rows: { day: string; session: string; calls: number; input: number; output: number }[]) =>
      rows.map(({ day, session, calls, input, output }) => [day, session, calls, input, output]);
    assert.deepEqual(totals(JSON.parse((partial.body as Buffer).toString()).rows), totals(expected),
      "a negative partial boundary is prepared and read using the same scope and exact endpoints");
  } finally {
    handover();
    await mover.close();
    readers.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a waiting usage page resumes when a temporarily failed installation is retried", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-summary-install-"));
  const store = Store.open(join(dir, "stillfail.db"));
  const readers = new Readers(dir, 1);
  let handover!: () => void;
  const exited = new Promise<void>((resolve) => { handover = resolve; });
  const mover = watchCompactMoves(store, exited);
  let attempted!: () => void;
  const failed = new Promise<void>((resolve) => { attempted = resolve; });
  let fiber: ReturnType<typeof Effect.runFork> | null = null;
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(store.db, () => 0);
    store.db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    store.db.exec(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES ('a', 0, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, 'WA', 0)`);
    store.db.setAuthorizer((action, table) => {
      if (action === constants.SQLITE_CREATE_TABLE && table === "usage_summary_blocks_progress") {
        attempted();
        return constants.SQLITE_DENY;
      }
      return constants.SQLITE_OK;
    });
    fiber = Effect.runFork(retireUntilComplete(store, exited, undefined, mover.wake));
    let sawPending!: () => void;
    const pending = new Promise<void>((resolve) => { sawPending = resolve; });
    const tools = { read: async (request: Request, op: string, args: unknown) => {
      try { return json(200, await readers.read(op, args, request.lang, { signal: request.signal })); }
      catch (cause) {
        const e = cause as Error & { status?: number };
        if (e.message === USAGE_SUMMARY_PENDING) sawPending();
        return error(e.status ?? 500, e.message);
      }
    } };
    const route = usageRoutes(tools as never, () => false, mover.read, mover.waitSummary).find((r) => r.pattern.test("/usage"))!;
    const request = { method: "GET", path: "/usage", query: [["from", "0"], ["to", "60000"], ["tz", "0"]], headers: {},
      body: Buffer.alloc(0), viewer: { workspace: "A", home: false }, lang: "en" } as unknown as Request;
    const answer = route.handle(request, []);
    await pending;
    assert.ok(JSON.parse(await readers.read("summary", { key: "a" }, "en")), "the waiting page leaves the reader free");
    handover();
    await failed;
    store.db.setAuthorizer(null);
    const result = await answer;
    assert.equal(result.status, 200);
    assert.equal(JSON.parse((result.body as Buffer).toString()).rows[0].calls, 1);
    assert.ok(store.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_summary_blocks_progress'").get());
  } finally {
    handover();
    store.db.setAuthorizer(null);
    if (fiber !== null) await Effect.runPromise(Fiber.interrupt(fiber));
    await mover.close();
    readers.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a usage request waits through handover until compact statistics exist", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-summary-handover-"));
  const store = Store.open(join(dir, "stillfail.db"));
  const readers = new Readers(dir, 1);
  let handover!: () => void;
  const exited = new Promise<void>((resolve) => { handover = resolve; });
  const mover = watchCompactMoves(store, exited);
  const fiber = Effect.runFork(retireUntilComplete(store, exited, undefined, mover.wake));
  try {
    let sawPending!: () => void;
    const pending = new Promise<void>((resolve) => { sawPending = resolve; });
    const tools = { read: async (request: Request, op: string, args: unknown) => {
      try { return json(200, await readers.read(op, args, request.lang, { signal: request.signal })); }
      catch (cause) {
        const e = cause as Error & { status?: number };
        if (e.message === USAGE_SUMMARY_PENDING) sawPending();
        return error(e.status ?? 500, e.message);
      }
    } };
    const route = usageRoutes(tools as never, () => false, mover.read, mover.waitSummary).find((r) => r.pattern.test("/usage"))!;
    const request = { method: "GET", path: "/usage", query: [["from", "0"], ["to", "60000"], ["tz", "0"]], headers: {},
      body: Buffer.alloc(0), viewer: { workspace: "A", home: false }, lang: "en" } as unknown as Request;
    const answer = route.handle(request, []);
    await pending;
    handover();
    const result = await answer;
    assert.equal(result.status, 200);
    assert.deepEqual(JSON.parse((result.body as Buffer).toString()).rows, []);
    assert.ok(store.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_summary_blocks_progress'").get());
  } finally {
    handover();
    await Effect.runPromise(Fiber.interrupt(fiber));
    await mover.close();
    readers.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("simultaneous ranges and the home workspace are prepared independently", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-summary-ranges-"));
  const store = Store.open(join(dir, "stillfail.db"));
  const readers = new Readers(dir, 1);
  let handover!: () => void;
  const mover = watchCompactMoves(store, new Promise<void>((resolve) => { handover = resolve; }));
  try {
    for (const [key, ws] of [["a", "A"], ["h", null]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key,
        ws, createdAt: 0, lastActiveAt: 0 });
    }
    installCompactUsage(store.db, () => 0);
    store.db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1), ('h', NULL, 1)");
    const put = store.db.prepare(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES (?, ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, ?, 0)`);
    for (let minute = -1_000; minute < 20; minute++) put.run("a", minute, "WA");
    for (let minute = 0; minute < 3; minute++) put.run("h", minute, "H");
    installUsageSummaryBlocks(store.db);
    const waiting: (() => void)[] = [];
    const tools = { read: async (request: Request, op: string, args: unknown) => {
      try { return json(200, await readers.read(op, args, request.lang, { signal: request.signal })); }
      catch (cause) {
        const e = cause as Error & { status?: number };
        if (e.message === USAGE_SUMMARY_PENDING) waiting.shift()?.();
        return error(e.status ?? 500, e.message);
      }
    } };
    const route = usageRoutes(tools as never, () => false, mover.read, mover.waitSummary).find((r) => r.pattern.test("/usage"))!;
    const request = (from: number, to: number, home: boolean) => ({ method: "GET", path: "/usage",
      query: [["from", String(from * 60_000)], ["to", String(to * 60_000)], ["tz", "0"]], headers: {}, body: Buffer.alloc(0),
      viewer: { workspace: "A", home }, lang: "en" } as unknown as Request);
    const noticed = () => new Promise<void>((resolve) => waiting.push(resolve));
    const seenFirst = noticed();
    const first = route.handle(request(0, 10, true), []);
    await seenFirst;
    const seenSecond = noticed();
    const second = route.handle(request(10, 20, false), []);
    await seenSecond;
    handover();
    const [a, b] = await Promise.all([first, second]);
    assert.equal(a.status, 200);
    assert.equal(b.status, 200);
    const calls = (body: unknown) => JSON.parse((body as Buffer).toString()).rows.reduce((n: number, r: { calls: number }) => n + r.calls, 0);
    assert.equal(calls(a.body), 13);
    assert.equal(calls(b.body), 10);
    assert.equal((store.db.prepare("SELECT done FROM usage_summary_blocks_progress WHERE id = 1").get() as { done: number }).done, 0);
  } finally {
    handover();
    await mover.close();
    readers.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a prepared usage range is reused while other history is still being converted", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-summary-reuse-"));
  const store = Store.open(join(dir, "stillfail.db"));
  const readers = new Readers(dir, 1);
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(store.db, () => 0);
    store.db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    const put = store.db.prepare(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES ('a', ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, 'WA', 0)`);
    for (let minute = -1_000; minute < 10; minute++) put.run(minute);
    installUsageSummaryBlocks(store.db);
    const tools = { read: async (request: Request, op: string, args: unknown) => {
      try { return json(200, await readers.read(op, args, request.lang, { signal: request.signal })); }
      catch (cause) { const e = cause as Error & { status?: number }; return error(e.status ?? 500, e.message); }
    } };
    let preparations = 0;
    const wait = async (viewer: { workspace: string } | null, requested: UsageSummaryRange) => {
      preparations++;
      const range = { ...requested };
      for (;;) {
        const result = usageSummaryBlocksStep(store.db, 32, viewer === null ? undefined : `W${viewer.workspace}`, range);
        if (result.done) break;
        if (result.after) range.after = result.after;
        if (result.converted) range.converted = true;
      }
    };
    const route = usageRoutes(tools as never, () => false, () => {}, wait).find((r) => r.pattern.test("/usage"))!;
    const request = { method: "GET", path: "/usage", query: [["from", "0"], ["to", String(10 * 60_000)], ["tz", "0"]], headers: {},
      body: Buffer.alloc(0), viewer: { workspace: "A", home: false }, lang: "en" } as unknown as Request;
    const calls = (body: unknown) => JSON.parse((body as Buffer).toString()).rows.reduce((n: number, r: { calls: number }) => n + r.calls, 0);
    const first = await route.handle(request, []);
    assert.equal(first.status, 200);
    assert.equal(calls(first.body), 10);
    assert.equal(preparations, 1);
    assert.equal((store.db.prepare("SELECT done FROM usage_summary_blocks_progress WHERE id = 1").get() as { done: number }).done, 0);
    store.db.exec("UPDATE usage_compact SET calls = 3 WHERE session = 'a' AND minute = 2");
    const again = await route.handle(request, []);
    assert.equal(again.status, 200);
    assert.equal(calls(again.body), 12, "a new write is reflected even when the prepared range is reused");
    assert.equal(preparations, 1, "the same range does not scan its old minutes again");
    const other = await route.handle({ ...request, viewer: { ...request.viewer, workspace: "B", home: false } }, []);
    assert.equal(other.status, 200);
    assert.equal(calls(other.body), 0);
    assert.equal(preparations, 2, "a different workspace cannot borrow the first one's preparation");
    store.db.exec("CREATE TABLE summary_schema_change (id INTEGER)");
    const afterSchemaChange = await route.handle(request, []);
    assert.equal(afterSchemaChange.status, 200);
    assert.equal(calls(afterSchemaChange.body), 12);
    assert.equal(preparations, 3, "a schema change discards a reader's preparation proofs");
    const more = store.db.prepare(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES ('a', 2, 0, 'p', ?, 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, 'WA', 0)`);
    for (let i = 0; i < 70; i++) more.run(`profile-${i}`);
    const dirty = await route.handle(request, []);
    assert.equal(dirty.status, 200);
    assert.equal(calls(dirty.body), 82);
    assert.equal(preparations, 4, "a large set of changes is still prepared in batches before reading");
  } finally {
    readers.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
