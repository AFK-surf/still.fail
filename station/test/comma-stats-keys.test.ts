import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { CommaStats, nextPage, statsRowsOf, type StationRows } from "../src/comma/stats.ts";

const from = Date.UTC(2026, 10, 1);
const usage = (session: string) => ({ day: "2026-11-02", session, thread: 7, person: "ann@x", account: "cc", runtime: "claude", model: null, calls: 1, input: 10, output: 5 });
const given = (sessions: string[]): StationRows => ({ usage: { rows: sessions.map(usage), people: {} }, chats: [] });
const quiet = () => () => {};
const nothing = async () => ({ stations: [], unread: [] });

test("an existing statistics index resets Comma with distinct safe keys and later removes the right row", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-stats-keys-"));
  const path = join(dir, "comma-stats.db");
  let stats: CommaStats | undefined;
  try {
    // An earlier station has stored full NUL-delimited keys and Comma has already held its old epoch.
    stats = CommaStats.at(dir, nothing, quiet);
    stats.close();
    stats = undefined;
    const db = new DatabaseSync(path);
    try {
      const put = db.prepare("INSERT INTO stats_index (key, source, kind, rev, json, removed) VALUES (?, 'stillfail', ?, ?, ?, 0)");
      let rev = 0;
      for (const [key, row] of statsRowsOf(given(["a", "b"]), "2026-11-01")) put.run(key, row.kind, ++rev, row.json);
      const meta = db.prepare("INSERT INTO meta (key, value) VALUES (?, ?)");
      meta.run("stats_index.rev", String(rev));
      meta.run("stats_index.epoch", "legacy-epoch");
      meta.run("task_index.epoch", "task-epoch");
    } finally { db.close(); }

    stats = CommaStats.at(dir, nothing, quiet);
    const reset = nextPage(stats.stats, { epoch: "legacy-epoch", through: 2 });
    assert.ok(reset?.reset, "a receiver that held the old keys must clear and rebuild its copy");
    assert.equal(stats.tasks.epoch(), "task-epoch.gc1", "the task index also resets for earlier pruned tombstones");
    assert.equal(nextPage(stats.tasks, { epoch: "task-epoch", through: 0 })?.reset, true);
    const sent = reset.rows as { key: string; row: { session: string } }[];
    assert.equal(sent.length, 2);
    assert.equal(new Set(sent.map((row) => row.key)).size, 2);
    assert.ok(sent.every((row) => !row.key.includes("\0") && Buffer.byteLength(row.key) <= 512));
    const b = sent.find((row) => row.row.session === "b")!.key;
    const remote = new Map(sent.map((row) => [row.key, row.row.session]));

    assert.deepEqual(stats.apply([given(["a"])], [], from), { stats: 1, tasks: 0 });
    const changed = nextPage(stats.stats, { epoch: reset.epoch, through: reset.through });
    assert.ok(changed && !changed.reset);
    assert.deepEqual(changed.rows.map((row) => [row.key, row.removed]), [[b, true]]);
    for (const row of changed.rows) if (row.removed) remote.delete(row.key);
    assert.deepEqual([...remote.values()], ["a"]);
    const epoch = reset.epoch;
    stats.close();
    stats = CommaStats.at(dir, nothing, quiet);
    assert.equal(stats.stats.epoch(), epoch, "restart does not reset the repaired index again");
    const legacy = new DatabaseSync(path, { readOnly: true });
    try {
      assert.equal((legacy.prepare("SELECT value FROM meta WHERE key = 'stats_index.epoch'").get() as { value: string }).value, "legacy-epoch");
    } finally { legacy.close(); }
  } finally { stats?.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a reset spanning pages gives each statistic a stable key Comma can store", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-stats-keys-"));
  const stats = CommaStats.at(dir, nothing, quiet);
  try {
    const sessions = [...Array.from({ length: 205 }, (_, i) => `session-${i}`), "long-" + "x".repeat(800)];
    stats.apply([given(sessions)], [], from);
    let held: { epoch: string | null; through: number } = { epoch: "old", through: 0 };
    const remote = new Map<string, string>();
    let pages = 0;
    for (let page = nextPage(stats.stats, held); page !== null; page = nextPage(stats.stats, held)) {
      if (page.reset) remote.clear();
      assert.equal(page.reset, pages === 0);
      for (const row of page.rows) {
        assert.ok(typeof row.key === "string" && !row.key.includes("\0") && Buffer.byteLength(row.key) <= 512);
        assert.equal(remote.has(row.key), false);
        remote.set(row.key, row.row.session);
      }
      held = { epoch: page.epoch, through: page.through };
      pages++;
    }
    assert.ok(pages > 1);
    assert.deepEqual(new Set(remote.values()), new Set(sessions));
    const removed = [...remote].find(([, session]) => session === sessions[1])![0];
    stats.apply([given(sessions.filter((session) => session !== sessions[1]))], [], from);
    const page = nextPage(stats.stats, held);
    assert.deepEqual(page?.rows.map((row) => [row.key, row.removed]), [[removed, true]]);
  } finally { stats.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a row written by an earlier station is sent and retained after handover", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-stats-keys-"));
  const stats = CommaStats.at(dir, nothing, quiet);
  try {
    stats.apply([given(["a"])], [], from);
    const first = nextPage(stats.stats, { epoch: null, through: 0 })!;
    const older = new DatabaseSync(join(dir, "comma-stats.db"));
    try {
      const [key, row] = [...statsRowsOf(given(["b"]), "2026-11-01")][0]!;
      const rev = stats.stats.rev() + 1;
      older.prepare("INSERT INTO stats_index (key, source, kind, rev, json, removed) VALUES (?, 'stillfail', ?, ?, ?, 0)").run(key, row.kind, rev, row.json);
      older.prepare("UPDATE meta SET value = ? WHERE key = 'stats_index.rev'").run(String(rev));
    } finally { older.close(); }
    const next = nextPage(stats.stats, { epoch: first.epoch, through: first.through });
    assert.equal(next?.rows[0]?.row.session, "b");
    assert.notEqual(next?.rows[0]?.key, first.rows[0]?.key);
    assert.deepEqual(stats.apply([given(["a", "b"])], [], from), { stats: 0, tasks: 0 });
  } finally { stats.close(); rmSync(dir, { recursive: true, force: true }); }
});
