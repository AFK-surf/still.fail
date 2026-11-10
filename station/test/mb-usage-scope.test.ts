// The MoonBit builder of the usage statistics' workspace upkeep (station/mb, src/usagefill scope.mbt) answers each
// wake as usage/scope-worker.ts does: the same answers and the same rows of the compact statistics, their totals and
// tree, and the summary blocks, batch by batch, for moves, totals, the blocks' conversion and requested spans, with
// calls recorded and sessions moved meanwhile.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Worker } from "node:worker_threads";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { Store } from "../src/store/store.ts";
import { installCompactUsage } from "../src/store/usage-compact.ts";
import { installUsageSummaryBlocks } from "../src/store/usage-summary-blocks.ts";
import { retireUsageIndexes } from "../src/store/usage-retire.ts";
import type { UsageCall, UsageFor } from "../src/store/usage.ts";

const binary = mbReaderBinary();
const MINUTE = 60_000;
const of = (person: string): UsageFor => ({ turn: null, person, thread: null, profile: "cc" });
const call = (id: string, at: number, input: number): UsageCall => ({ id, at, model: "m", subagent: false, fast: false,
  input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 100, window: 1000 });

/// A station with the compact statistics and their summary blocks, three sessions' calls over many minutes, none of the
/// totals or blocks prepared yet.
function station() {
  const dir = mkdtempSync(join(tmpdir(), "mb-usage-scope-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive"));
  installCompactUsage(store.db, () => 2_000 * MINUTE);
  retireUsageIndexes(store.db);
  installUsageSummaryBlocks(store.db);
  for (const [key, ws] of [["a", "A"], ["b", "B"], ["h", null]] as const) store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, ws, createdAt: 0, lastActiveAt: 0 });
  const record = (key: string, calls: [UsageCall, string][]) => store.recordUsage(`/${key}`, { session: key, offset: calls.length, model: "m" }, "claude", calls.map(([c, p]) => [c, of(p)]));
  for (const key of ["a", "b", "h"]) record(key, Array.from({ length: 150 }, (_, i) => [call(`${key}${i}`, i * 7 * MINUTE + 1000, i + 1), `p${i % 3}`]));
  return { dir, path, store, record, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function tables(store: Store): string[] {
  const db = store.db;
  const names = (db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND (name LIKE 'usage_compact%' OR name LIKE 'usage_summary_blocks%') ORDER BY name").all() as { name: string }[]).map((r) => r.name);
  return names.flatMap((name) => (db.prepare(`SELECT * FROM "${name}"`).all() as object[]).map((r) => `${name} ${JSON.stringify(r)}`)).sort();
}

function same(ours: string[], theirs: string[], what: string) {
  const a = new Set(ours), b = new Set(theirs);
  assert.deepEqual({ ours: ours.filter((r) => !b.has(r)).slice(0, 4), theirs: theirs.filter((r) => !a.has(r)).slice(0, 4) }, { ours: [], theirs: [] }, what);
}

/// An answer with its span cursor's numbers as text on both sides (the worker's are bigints).
const plain = (answer: object) => JSON.parse(JSON.stringify(answer, (_, v) => typeof v === "bigint" ? v.toString() : v));

test("the MoonBit builder answers the usage workspace wakes as the scope worker does", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = station(), mb = station();
  const worker = new Worker(new URL("../src/usage/scope-worker.ts", import.meta.url), { workerData: { path: ts.path, priority: new SharedArrayBuffer(8) } });
  const builder = new MbProcess(binary!, ["--builder", "usage-scope", "--db", mb.path]);
  const asked = <T>(target: { once(event: "message", f: (answer: T) => void): unknown; postMessage(message: unknown): void }, message: object) =>
    new Promise<T>((resolve) => { target.once("message", resolve); target.postMessage(message); });
  try {
    const run = async (work: { scope?: string; range?: { from: bigint; to: bigint; after?: object; converted?: boolean } }, change?: (n: number) => void) => {
      let n = 0, done = false;
      const range = work.range === undefined ? undefined : { ...work.range };
      for (; n < 60 && !done; n++) {
        change?.(n);
        const message = { wake: true, ...work, ...(range === undefined ? {} : { range: { ...range } }) };
        const theirs = await asked<{ done: boolean; after?: object; converted?: boolean; error?: string }>(worker, message);
        const ours = await asked<{ done: boolean; after?: object; converted?: boolean; error?: string }>(builder, message);
        assert.equal(theirs.error, undefined);
        assert.deepEqual(plain(ours), plain(theirs), `${JSON.stringify(plain(work))} batch ${n}`);
        same(tables(mb.store), tables(ts.store), `${JSON.stringify(plain(work))} batch ${n}`);
        done = theirs.done;
        if (range !== undefined && theirs.after !== undefined) range.after = theirs.after;
        if (range !== undefined && theirs.converted) range.converted = true;
      }
      assert.ok(done, `${JSON.stringify(plain(work))}: ${n} batches`);
      return n;
    };
    // a requested span first (before the blocks are converted), then the moves, a workspace's and the station's totals
    assert.ok(await run({ scope: "WA", range: { from: 100n, to: 400n } }) >= 2);
    for (const f of [ts, mb]) f.store.setSessionsWs("A", "C");
    await run({});
    // (a workspace's blocks converted on their own, before the station's)
    assert.ok(await run({ scope: "WB" }) >= 2);
    assert.ok(await run({ scope: "G" }, (n) => {
      if (n === 1) for (const f of [ts, mb]) f.record("b", [[call("late", 3 * MINUTE, 9), "p9"], [call("later", 900 * MINUTE, 4), "p1"]]);
    }) >= 2);
    await run({ scope: "WB" });
    await run({ scope: "H" });
  } finally {
    await worker.terminate();
    await builder.terminate();
    ts.close(); mb.close();
  }
});
