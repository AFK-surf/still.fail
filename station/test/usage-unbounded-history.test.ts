import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import * as reads from "../src/read/store.ts";
import { usage } from "../src/read/usage.ts";
import * as compact from "../src/store/usage-compact.ts";
import { retireUsageIndexes } from "../src/store/usage-retire.ts";
import { Store } from "../src/store/store.ts";

test("an unbounded read with a cached summary says the same as one without", async () => {
  const writer = Store.open(":memory:");
  try {
    for (const [key, ws] of [["a", "A"], ["h", null], ["other", "B"]] as const) {
      writer.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, ws, createdAt: 0, lastActiveAt: 0 });
    }
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number, model = "m") => ({ id, at, model, subagent: true, fast: false,
      input: 1, cacheRead: 2, cacheWrite: 3, cacheWriteLong: 4, output: 5, calls: 1, context: null, window: null });
    writer.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call("old", -120_000), owner]]);
    writer.db.exec("CREATE TABLE usage_retired_detail (id INTEGER PRIMARY KEY); INSERT INTO usage_retired_detail VALUES (1)");
    compact.installCompactUsage(writer.db, () => 0);
    retireUsageIndexes(writer.db);
    compact.installUsageSummaryChanges(writer.db);
    for (const key of ["a", "h", "other"]) writer.recordUsage(`/${key}`, { session: key, offset: 2, model: "m" }, "claude",
      [[call(`${key}-1`, 0), owner], [call(`${key}-2`, 60_000, "second"), { ...owner, person: "q" }]]);
    while (!compact.compactTotalsStep(writer.db, 64).done) { /* Settle the visible statistics. */ }
    const store = reads.makeStore(writer.db, "."), from = 0n, to = 9223372036854775807n;
    for (const viewer of [null, { workspace: "A", home: false }, { workspace: "A", home: true }]) for (const tz of [0n, 330n, -61n]) {
      const expected = usage(store, "en", from, to, tz, false, viewer, true);
      assert.ok(expected.history);
      const summary = await reads.usageGroupsBatched(store, from, to, tz, viewer, async () => {});
      assert.ok(summary);
      const values = new Set(["records", "calls", "input", "cache_read", "cache_write", "cache_write_long", "output"]);
      writer.db.setAuthorizer((action, table, column) => action === constants.SQLITE_READ && table === "usage_compact" && values.has(column ?? "")
        ? constants.SQLITE_DENY : constants.SQLITE_OK);
      try {
        const actual = usage(store, "en", from, to, tz, false, viewer, true, { batched: summary });
        assert.deepEqual(JSON.parse(JSON.stringify(actual)), JSON.parse(JSON.stringify(expected)));
      } finally { writer.db.setAuthorizer(null); }
    }
    // A newly counted call before the summary's start must remain in the unbounded history.
    writer.recordUsage("/a", { session: "a", offset: 3, model: "m" }, "claude", [[call("earlier", -60_000), owner]]);
    const viewer = { workspace: "A", home: false };
    const expected = usage(store, "en", from, to, 0n, false, viewer, true);
    const summary = await reads.usageGroupsBatched(store, from, to, 0n, viewer, async () => {});
    assert.ok(summary);
    assert.deepEqual(JSON.parse(JSON.stringify(usage(store, "en", from, to, 0n, false, viewer, true, { batched: summary }))),
      JSON.parse(JSON.stringify(expected)), "an earlier minute is included through the ordinary history query");
  } finally { writer.close(); }
});

test("a reader preserves an unbounded history as earlier usage arrives", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-unbounded-history-"));
  const writer = Store.open(join(dir, "stillfail.db"));
  let workers: Readers | null = null;
  try {
    writer.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number) => ({ id, at, model: "m", subagent: true, fast: false,
      input: 1, cacheRead: 2, cacheWrite: 3, cacheWriteLong: 4, output: 5, calls: 1, context: null, window: null });
    writer.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call("old", -120_000), owner]]);
    writer.db.exec("CREATE TABLE usage_retired_detail (id INTEGER PRIMARY KEY); INSERT INTO usage_retired_detail VALUES (1)");
    compact.installCompactUsage(writer.db, () => 0);
    retireUsageIndexes(writer.db);
    compact.installUsageSummaryChanges(writer.db);
    writer.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[call("new", 0), owner]]);
    const viewer = { workspace: "A", home: false }, from = 0n, to = 9223372036854775807n;
    const store = reads.makeStore(writer.db, dir);
    const args = { from: String(from), to: String(to), tz: "0", lang: "en", reading: false, viewer, history: true };
    workers = new Readers(dir, 1);
    const expected = () => JSON.parse(JSON.stringify(usage(store, "en", from, to, 0n, false, viewer, true)));
    assert.deepEqual(JSON.parse(await workers.read("usage", args, "en")), expected());
    assert.deepEqual(JSON.parse(await workers.read("usage", args, "en")), expected());
    writer.recordUsage("/a", { session: "a", offset: 3, model: "m" }, "claude", [[call("earlier", -60_000), owner]]);
    assert.deepEqual(JSON.parse(await workers.read("usage", args, "en")), expected());
  } finally { workers?.close(); writer.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a reader returns available usage when only old decisions are missing", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-missing-decisions-"));
  const writer = Store.open(join(dir, "stillfail.db"));
  let workers: Readers | null = null;
  try {
    writer.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    const thread = writer.openThread("ember", "EMBER", "chat", null, null).id;
    writer.joinThread(thread, "a", "ember");
    const owner = { turn: null, thread, person: "p", profile: "cc" };
    const call = { id: "one", at: 60_000, model: "m", subagent: false, fast: false,
      input: 2, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    writer.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    writer.db.exec("CREATE TABLE card_outcomes_incomplete (id INTEGER PRIMARY KEY)");
    const before = writer.db.prepare("SELECT * FROM usage_chat_progress").get();
    workers = new Readers(dir, 1);
    const args = { from: "0", to: "180000", tz: "0", reading: false, viewer: { workspace: "A", home: false }, history: true };
    const answer = JSON.parse(await workers.read("usage", args, "en"));
    assert.equal(answer.history.cardsIncomplete, true);
    assert.deepEqual(answer.history.places, { ember: 1 });
    assert.deepEqual(answer.history.days.map((day: { tokens: number }) => day.tokens), [3]);
    assert.deepEqual(writer.db.prepare("SELECT * FROM usage_chat_progress").get(), before);
  } finally { workers?.close(); writer.close(); rmSync(dir, { recursive: true, force: true }); }
});
