// Exercise the client and station together, including the station's real streaming compression and reader worker.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect } from "effect";
import { HostError, CoreError } from "../../client/core-ts/src/error.ts";
import { HostWire } from "../../client/core-ts/src/station/wire.ts";
import { subscribe } from "../../client/core-ts/test/helpers.ts";
import { base, started } from "../../client/core-ts/test/station-fixture.ts";
import { error, json, type Request } from "../src/api/request.ts";
import { usageRoutes } from "../src/api/routes/usage.ts";
import { compressed } from "../src/mesh/compress.ts";
import { Readers } from "../src/read/pool.ts";
import { Store } from "../src/store/store.ts";
import { installCompactUsage } from "../src/store/usage-compact.ts";
import { installUsageSummaryBlocks } from "../src/store/usage-summary-blocks.ts";
import { watchCompactMoves } from "../src/usage/module.ts";

for (const cancel of [false, true]) test(`a client receives compressed usage from the station${cancel ? " and can leave" : " through preparation"}`, async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "usage-client-stream-"));
  const store = Store.open(join(dir, "stillfail.db"));
  const readers = new Readers(dir, 1);
  let handover!: () => void, noteWait!: () => void, noteAbort!: () => void;
  const waitStarted = new Promise<void>((resolve) => { noteWait = resolve; });
  const waitAborted = new Promise<void>((resolve) => { noteAbort = resolve; });
  const mover = watchCompactMoves(store, new Promise<void>((resolve) => { handover = resolve; }));
  let opened = 0;
  const tools = { read: async (request: Request, op: string, args: unknown) => {
    try { return json(200, await readers.read(op, args, request.lang, { signal: request.signal })); }
    catch (cause) {
      const e = cause as Error & { status?: number };
      return error(e.status ?? 500, e.message);
    }
  } };
  const route = usageRoutes(tools as never, () => false, mover.read, (viewer, range, signal) => {
    noteWait();
    signal?.addEventListener("abort", noteAbort, { once: true });
    return mover.waitSummary(viewer, range, signal);
  }).find((r) => r.pattern.test("/usage"))!;
  class StationUsageWire extends HostWire {
    override request(...args: Parameters<HostWire["request"]>) {
      const head = args[1];
      if (!head.path.startsWith("/admin/api/usage?")) return super.request(...args);
      opened++;
      return Effect.gen(function* () {
        const url = new URL(head.path, "https://station.test");
        const headers = Object.fromEntries(head.headers.map(([key, value]) => [key.toLowerCase(), value]));
        const request = { method: head.method, path: "/usage", query: [...url.searchParams], headers, body: Buffer.alloc(0),
          viewer: { workspace: "ws", home: false }, lang: "en" } as unknown as Request;
        const answer = yield* Effect.tryPromise({
          try: async () => compressed(await route.handle(request, []), headers, "/usage"),
          catch: (cause) => CoreError.host(String(cause)),
        });
        assert.equal(answer.headers["content-encoding"], "zstd");
        assert.ok(!Buffer.isBuffer(answer.body));
        const body = (answer.body as AsyncIterable<Buffer>)[Symbol.asyncIterator]();
        yield* Effect.addFinalizer(() => Effect.promise(async () => { await body.return?.(); }));
        return { status: answer.status, headers: Object.entries(answer.headers), via: null,
          body: { take: Effect.tryPromise({ try: async () => {
            const part = await body.next();
            return part.done ? null : part.value;
          }, catch: (cause) => new HostError(String(cause)) }) } };
      });
    }
  }
  const { host, core } = await started(base(), 0, (h) => new StationUsageWire(h));
  const stop = new Promise<never>((_, reject) => t.signal.addEventListener("abort", () => reject(t.signal.reason), { once: true }));
  let partial!: (value: any) => void, complete!: (value: any) => void;
  const sawPartial = new Promise<any>((resolve) => { partial = resolve; });
  const sawComplete = new Promise<any>((resolve) => { complete = resolve; });
  const data = core.inner.data;
  const set = data.set.bind(data);
  data.set = (topic, value, confirmed) => {
    set(topic, value, confirmed);
    if (topic.topic !== "stationUsage") return;
    if ((value as any)?.detailsPreparing === true) partial(value);
    else complete(value);
  };
  try {
    const now = host.nowMs();
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "ws", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(store.db, () => 0);
    store.db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'ws', 1)");
    store.db.prepare(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES ('a', ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, 'Wws', 0)`)
      .run(Math.floor(now / 60_000));
    store.db.prepare("INSERT INTO usage_history VALUES ('ws', ?, 2, 19)").run(Math.floor(now / 900_000));
    installUsageSummaryBlocks(store.db);
    const ui = core.connect();
    subscribe(core, ui, 1, { topic: "stationUsage", station: "ws/st" });
    await host.settle();
    const first = await Promise.race([sawPartial, stop]);
    await Promise.race([waitStarted, stop]);
    assert.equal(opened, 1);
    assert.equal(first.detailsPreparing, true);
    assert.deepEqual(first.history.days.map((day: { calls: number; tokens: number }) => [day.calls, day.tokens]), [[2, 19]]);
    assert.ok(JSON.parse(await readers.read("summary", { key: "a" }, "en")), "the waiting client leaves the reader free");
    if (cancel) {
      await core.close();
      await Promise.race([waitAborted, stop]);
    } else {
      handover();
      const ready = await Promise.race([sawComplete, stop]);
      assert.notEqual(ready.detailsPreparing, true);
      assert.equal(ready.rows.reduce((n: number, row: { calls: number }) => n + row.calls, 0), 1);
      assert.equal(opened, 1);
    }
  } finally {
    data.set = set;
    handover();
    await core.close();
    await mover.close();
    readers.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
