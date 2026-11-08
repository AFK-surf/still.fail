// The MoonBit builder of the usage retirement (station/mb, src/usagefill) frees the retired per-call indexes as
// `dropUsageIndexStep` does and takes the calls from before the compact statistics in as `fillUsageStep` does: the same
// answers and tables, step by step, with calls recorded meanwhile, and an old context trigger replaced as it is.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { Store } from "../src/store/store.ts";
import { installCompactUsage } from "../src/store/usage-compact.ts";
import { fillUsageStep } from "../src/store/usage-fill.ts";
import { installUsageHistory } from "../src/store/usage-history.ts";
import { dropUsageIndexStep, stopUsageIndexes } from "../src/store/usage-retire.ts";
import type { UsageCall, UsageFor } from "../src/store/usage.ts";

const binary = mbReaderBinary();
const HOUR = 3_600_000;
const of: UsageFor = { turn: null, person: "p", thread: null, profile: "cc" };
const call = (id: string, at: number, input: number): UsageCall => ({ id, at, model: "m", subagent: false, fast: false,
  input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 100, window: 1000 });

/// A station from before the compact statistics (`complete`: its old quarters held every call), its calls in two
/// workspaces, the retired per-call indexes still there and full.
function old(complete: boolean) {
  const dir = mkdtempSync(join(tmpdir(), "mb-usage-retire-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive"));
  store.db.exec(`DROP TRIGGER usage_history_add; DROP TRIGGER usage_history_grow; DROP TRIGGER usage_history_move; DROP TRIGGER usage_history_drop;
    DROP TABLE usage_history; DROP TABLE usage_history_total; DROP TABLE usage_history_since;`);
  for (const [key, ws] of [["a", "A"], ["h", null]] as const) store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, ws, createdAt: 0, lastActiveAt: 0 });
  const record = (key: string, calls: UsageCall[]) => store.recordUsage(`/${key}`, { session: key, offset: calls.length, model: "m" }, "claude", calls.map((c) => [c, of]));
  record("a", Array.from({ length: 300 }, (_, i) => call(`a${i}`, i * HOUR / 3, i + 1)));
  record("h", Array.from({ length: 200 }, (_, i) => call(`h${i}`, i * HOUR / 2 + 60_000, 1_000 + i)));
  if (!complete) store.db.exec("UPDATE usage_minute_all SET done = 0");
  const now = 120 * HOUR;
  installCompactUsage(store.db, () => now);
  installUsageHistory(store.db, now);
  // the retired indexes (the station's own, and one keyed by two columns), full
  store.db.exec("CREATE TABLE IF NOT EXISTS usage_detail_x (k TEXT, n INTEGER, PRIMARY KEY (k, n)) WITHOUT ROWID");
  for (let i = 0; i < 600; i++) store.db.prepare("INSERT INTO usage_detail_x VALUES (?, ?)").run(`k${i % 7}`, i);
  stopUsageIndexes(store.db);
  return { dir, path, store, record, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

/// Every usage table's rows (the counter's wall-clock times aside) and the compact statistics' triggers, a line each, sorted.
function tables(store: Store): string[] {
  const db = store.db;
  const names = (db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'usage%' AND name <> 'usage_counter' ORDER BY name").all() as { name: string }[]).map((r) => r.name);
  const triggers = (db.prepare("SELECT name, replace(replace(sql, ' ', ''), char(10), '') AS sql FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'usage_compact%' ORDER BY name").all() as object[]).map((r) => `trigger ${JSON.stringify(r)}`);
  return [...names.map((n) => `table ${n}`), ...triggers, ...names.flatMap((name) => (db.prepare(`SELECT * FROM "${name}"`).all() as object[]).map((r) => `${name} ${JSON.stringify(r)}`))].sort();
}

/// The lines only one side has, none when the same.
function same(ours: string[], theirs: string[], what: string) {
  const a = new Set(ours), b = new Set(theirs);
  assert.deepEqual({ ours: ours.filter((r) => !b.has(r)).slice(0, 5), theirs: theirs.filter((r) => !a.has(r)).slice(0, 5) }, { ours: [], theirs: [] }, what);
}

for (const complete of [false, true]) {
  test(`the MoonBit builder frees the retired usage indexes and fills the old calls as the TypeScript does${complete ? " (old quarters complete)" : ""}`, async () => {
    assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
    const ts = old(complete), mb = old(complete);
    const builder = new MbProcess(binary!, ["--builder", "usage-retire", "--db", mb.path]);
    const ask = (message: object) => {
      const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
      builder.postMessage(message);
      return answered;
    };
    try {
      let n = 0;
      for (let done = false; !done && n < 40; n++) {
        const ours = await ask({ drop: true });
        assert.equal(ours.error, undefined);
        done = dropUsageIndexStep(ts.store.db);
        assert.equal(ours.done, done, `drop ${n}`);
        same(tables(mb.store), tables(ts.store), `drop ${n}`);
      }
      assert.ok(n >= 4, `${n} drops`);
      // (an old context trigger, from before the fill: replaced on the first fill step)
      for (const f of [ts, mb]) {
        const sql = (f.store.db.prepare("SELECT sql FROM sqlite_master WHERE name = 'usage_compact_context_change'").get() as { sql: string } | undefined)?.sql;
        if (sql !== undefined) f.store.db.exec(`DROP TRIGGER usage_compact_context_change; ${sql.replace("WHEN", "WHEN NEW.compact_counted = NEW.compact_counted AND")}`);
      }
      n = 0;
      for (let done = false; !done && n < 60; n++) {
        if (n === 2) for (const f of [ts, mb]) f.record("a", [call("during", 130 * HOUR, 7), call("old-late", HOUR / 7, 9)]);
        const ours = await ask({});
        assert.equal(ours.error, undefined);
        done = fillUsageStep(ts.store.db);
        assert.equal(ours.done, done, `fill ${n}`);
        same(tables(mb.store), tables(ts.store), `fill ${n}`);
      }
      assert.ok(n >= 2, `${n} fills`);
    } finally {
      await builder.terminate();
      ts.close(); mb.close();
    }
  });
}
