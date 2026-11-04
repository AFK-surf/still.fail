import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import * as reads from "../src/read/store.ts";
import { usage } from "../src/read/usage.ts";
import { installCompactUsage } from "../src/store/usage-compact.ts";
import { retireUsageIndexes } from "../src/store/usage-retire.ts";
import { Store } from "../src/store/store.ts";

test("a large usage summary gives other work a turn without mixing database snapshots", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-batched-read-"));
  const path = join(dir, "stillfail.db");
  const writer = Store.open(path);
  let reader: DatabaseSync | null = null;
  let workers: Readers | null = null;
  try {
    for (const [key, ws] of [["a", "A"], ["b", "A"], ["other", "B"]]) {
      writer.insertSession({ key: key!, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key!, ws: ws!, createdAt: 0, lastActiveAt: 0 });
    }
    installCompactUsage(writer.db, () => 0);
    retireUsageIndexes(writer.db);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number, output = 1) => ({ id, at, model: "m", subagent: false, fast: false,
      input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output, calls: 1, context: null, window: null });
    for (const key of ["a", "b", "other"]) {
      const calls = Array.from({ length: 150 }, (_, n) => [
        { ...call(`${key}-${n}`, n * 60_000), model: n > 0 && n % 2 ? "z" : "m", fast: n > 0 && n % 3 === 0 },
        { ...owner, person: n > 0 && n % 5 === 0 ? "あ" : "p", profile: n > 0 && n % 7 === 0 ? "other" : "cc" },
      ] as [ReturnType<typeof call>, typeof owner]);
      writer.recordUsage(`/${key}`, { session: key, offset: 1, model: "m" }, "claude", calls);
    }
    const later = Array.from({ length: 200 }, (_, n) => [call(`later-${n}`, (1_000 + n) * 60_000), owner] as [ReturnType<typeof call>, typeof owner]);
    writer.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", later);
    writer.db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
    reader = new DatabaseSync(path, { readOnly: true });
    const store = reads.makeStore(reader, dir);
    const viewer = { workspace: "A", home: false };
    const expected = reads.usageGroups(store, 0n, 150n * 60_000n, 0n, viewer);
    const batched = reads.usageGroupsBatched;
    assert.equal(await batched(store, 1n, 150n * 60_000n, 0n, viewer, async () => {}), null,
      "a partial-minute edge is left to the exact original query");
    let pauses = 0;
    let pinned: { log: number; checkpointed: number } | undefined;
    reader.exec("BEGIN");
    try {
      const result = await batched(store, 0n, 150n * 60_000n, 0n, viewer, async () => {
        if (++pauses === 1) {
          writer.recordUsage("/a", { session: "a", offset: 3, model: "m" }, "claude", [[call("a-0", 0, 9), owner]]);
          pinned = writer.db.prepare("PRAGMA wal_checkpoint(PASSIVE)").get() as typeof pinned;
        }
      });
      assert.ok(result);
      assert.ok(pauses > 1, "a large read yields more than once");
      assert.deepEqual(result.groups, expected, "every batch sees the same snapshot, including across a concurrent update");
      assert.equal(result.diagnostics.parts, 300, "only the visible workspace contributes");
      assert.equal(result.diagnostics.candidates, 300, "another workspace and later buckets are not visited");
    } finally { reader.exec("COMMIT"); }
    assert.ok(pinned && pinned.log > pinned.checkpointed, "the open snapshot retains the writer's newer log frames");
    const released = writer.db.prepare("PRAGMA wal_checkpoint(PASSIVE)").get() as { log: number; checkpointed: number };
    assert.equal(released.checkpointed, released.log, "finishing the read releases those frames to the checkpoint");
    assert.notDeepEqual(reads.usageGroups(store, 0n, 150n * 60_000n, 0n, viewer), expected, "the concurrent update was committed");
    for (const who of [null, viewer, { workspace: "B", home: true }]) for (const tz of [-720n, -60n, 0n, 330n, 1380n]) {
      for (const [from, to] of [[0n, 150n * 60_000n], [60_000n, 9223372036854775807n], [60_000n, 0n]] as const) {
        const result = await batched(store, from, to, tz, who, async () => {});
        assert.ok(result);
        assert.deepEqual(result.groups, reads.usageGroups(store, from, to, tz, who), "the two reads agree for each workspace, range and time zone");
      }
    }
    writer.db.prepare("UPDATE usage_minute_scope SET ws = ? WHERE session = ?").run("B", "a");
    const stale = await batched(store, 0n, 150n * 60_000n, 0n, viewer, async () => {});
    assert.ok(stale);
    assert.deepEqual(stale.groups, reads.usageGroups(store, 0n, 150n * 60_000n, 0n, viewer), "stale scope buckets do not expose a moved session");
    writer.db.prepare("UPDATE usage_minute_scope SET ws = ? WHERE session = ?").run("A", "a");
    assert.equal((reader.prepare("SELECT total_changes() AS n").get() as { n: number }).n, 0, "the reader writes no statistics");
    const current = usage(store, "en", 0n, 150n * 60_000n, 0n, false, viewer);
    workers = new Readers(dir, 1);
    const answer = await workers.read("usage", { from: "0", to: String(150 * 60_000), tz: "0", lang: "en", reading: false, viewer }, "en");
    assert.deepEqual(JSON.parse(answer), JSON.parse(JSON.stringify(current)), "the reader returns the same complete usage after batching");
  } finally {
    workers?.close();
    reader?.close();
    writer.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
