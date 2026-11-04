import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect, Layer } from "effect";
import { makeStore } from "../src/read/store.ts";
import { usageHistory } from "../src/read/usage.ts";
import { Paths, Previous, Readers, ReadersAndStore, Store as StoreService } from "../src/services.ts";
import { Store } from "../src/store/store.ts";
import { MinuteReader } from "../src/usage/minute-reader.ts";

test("the station starts its store before the background minute reader", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-minute-service-"));
  try {
    const paths = Layer.succeed(Paths)({ data: dir, app: dir });
    await Effect.runPromise(Effect.gen(function* () {
      const store = yield* StoreService;
      const readers = yield* Readers;
      assert.equal(readers.data, dir);
      assert.equal((store.db.prepare("SELECT done FROM usage_minute_all WHERE id = 1").get() as { done: number }).done, 1);
    }).pipe(Effect.provide(ReadersAndStore.pipe(Layer.provide(Layer.succeed(Previous)({ pid: null, gone: Promise.resolve(), exited: Promise.resolve() })), Layer.provide(paths)))));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("an incomplete old minute history stays unavailable after a workspace move", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-minute-reader-"));
  const path = join(dir, "stillfail.db");
  let store = Store.open(path);
  let reader: MinuteReader | null = null;
  try {
    for (const [key, ws] of [["a", "workspace-a"], ["b", "workspace-b"]]) {
      store.insertSession({ key: key!, ws: ws!, connect: key!, runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key!, createdAt: 1, lastActiveAt: 1 });
    }
    // As on a station before minute summaries existed.
    store.db.exec(`DROP TRIGGER usage_minute_add; DROP TRIGGER usage_minute_drop; DROP TRIGGER usage_minute_grow;
      DROP TRIGGER usage_minute_session_add; DROP TRIGGER usage_minute_session_move; DROP TRIGGER usage_minute_session_drop;
      DROP TABLE usage_minute; DROP TABLE usage_day_quarters; DROP TABLE usage_minute_scope; DROP TABLE usage_minute_sessions; DROP TABLE usage_minute_seen; DROP TABLE usage_minute_all;`);
    const midnight = Date.UTC(2026, 0, 2);
    const call = (id: string, at: number) => ({ id, at, model: "m", subagent: true, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 0, calls: 1, context: null, window: null });
    const of = { turn: null, person: null, thread: null, profile: null };
    store.recordUsage("/a.jsonl", { session: "a", offset: 1, model: "m" }, "claude", [[call("a1", midnight - 30_000), of]]);
    const other = Array.from({ length: 2_000 }, (_, n) => [call(`b${n}`, midnight - 1_000_000), of] as const);
    store.recordUsage("/b.jsonl", { session: "b", offset: 1, model: "m" }, "claude", other as never);
    store.close();
    store = Store.open(path);
    reader = new MinuteReader(path);
    const before = store.db.prepare("SELECT * FROM usage_minute_all WHERE id = 1").get();
    await assert.rejects(reader.ready({ workspace: "workspace-a", home: false }), /minute.*unavailable/);
    // The page's history does not wait for them: it was counted from the first call.
    const page = usageHistory(makeStore(store.db, dir), 0n, { workspace: "workspace-a", home: false });
    assert.deepEqual(page!.days.map((d: { calls: number }) => d.calls), [1]);
    store.db.prepare("UPDATE sessions SET ws = 'workspace-b' WHERE key = 'a'").run();
    await assert.rejects(reader.ready({ workspace: "workspace-b", home: false }), /minute.*unavailable/);
    assert.deepEqual(store.db.prepare("SELECT * FROM usage_minute_all WHERE id = 1").get(), before);
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM usage").get() as { n: number }).n, 2_001);
  } finally {
    if (reader !== null) await reader.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
