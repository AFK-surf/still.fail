import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { makeStore, usageGroups, usageSince } from "../src/read/store.ts";
import { usage } from "../src/read/usage.ts";
import { Store } from "../src/store/store.ts";
import { backfillUsageDetail } from "../src/store/usage-detail.ts";

function forgetDetail(store: Store) {
  const objects = store.db.prepare("SELECT type, name FROM sqlite_master WHERE (name LIKE 'usage_detail_%' OR name = 'usage_detail') AND type IN ('trigger', 'table') ORDER BY type DESC").all() as { type: string; name: string }[];
  for (const object of objects) store.db.exec(`DROP ${object.type.toUpperCase()} "${object.name}"`);
}

test("an old partial detail index is left aside and only later calls enter new statistics", () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-new-only-"));
  const path = join(dir, "stillfail.db");
  let store = Store.open(path);
  const owner = { turn: null, person: null, thread: null, profile: "cc" };
  const call = (id: string, at: number, input: number, output = 1) => [{ id, at, model: "m", subagent: false,
    fast: false, input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output, calls: 1, context: null, window: null }, owner] as const;
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", ws: "A", createdAt: 1, lastActiveAt: 1 });
    store.recordUsage("/s", { session: "s", offset: 1, model: null }, "claude", [call("old1", 100, 10), call("old2", 200, 20)] as never);
    forgetDetail(store);
    store.close();
    store = Store.open(path); // An old station had begun building an index but stopped halfway.
    assert.equal(backfillUsageDetail(store.db, "s", 1).done, false);
    const before = store.db.prepare("SELECT * FROM usage_detail_all").get();
    store.close();
    store = Store.open(path);

    const groups = (workspace = "A") => usageGroups(makeStore(store.db, dir), 0n, 500n, 0n, { workspace, home: false });
    assert.deepEqual(groups(), [], "part of old history is not presented as complete");
    store.db.exec("UPDATE sessions SET ws = 'B' WHERE key = 's'");
    assert.deepEqual(store.db.prepare("SELECT * FROM usage_detail_live_scope").all(), [],
      "moving an old session with no new statistics does not add it to the live lookup");
    store.db.exec("UPDATE sessions SET ws = 'A' WHERE key = 's'");
    store.recordUsage("/s", { session: "s", offset: 2, model: null }, "claude", [call("new1", 50, 3), call("new2", 300, 4)] as never);
    store.recordUsage("/s", { session: "s", offset: 3, model: null }, "claude", [call("old2", 200, 20, 9), call("new1", 50, 3, 5)] as never);
    store.db.exec("UPDATE sessions SET ws = 'B' WHERE key = 's'");
    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      assert.deepEqual(groups(), []);
      const result = groups("B");
      assert.deepEqual(result.map((g) => [g.calls, g.input, g.output]), [[2, 7, 6]],
        "new calls, including one earlier than the old cursor, follow the moved session and are counted once");
      const answer = usage(makeStore(store.db, dir), "en", 0n, 500n, 0n, false, { workspace: "B", home: false }, true);
      assert.equal(answer.detailSince, usageSince(makeStore(store.db, dir)));
    } finally { store.db.setAuthorizer(null); }
    store.db.exec("UPDATE sessions SET ws = 'A' WHERE key = 's'");
    assert.deepEqual(store.db.prepare("SELECT * FROM usage_detail_all").get(), before, "the old cursor is not advanced");
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM usage").get() as { n: number }).n, 4, "original calls remain intact");
    assert.equal(usageSince(makeStore(store.db, dir)), (store.db.prepare("SELECT since FROM usage_detail_live_since").get() as { since: number }).since);
    // A previous station may finish its obsolete index after the new station starts. It must not switch the reader
    // back to that incomplete index or lose the data recorded since cutover, including after a restart.
    store.db.exec("UPDATE usage_detail_all SET done = 1");
    store.close();
    store = Store.open(path);
    assert.deepEqual(groups().map((g) => [g.calls, g.input, g.output]), [[2, 7, 6]]);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("replacing old and new calls only changes the new statistics, with either SQLite trigger mode", () => {
  for (const recursive of ["OFF", "ON"]) {
    const dir = mkdtempSync(join(tmpdir(), "usage-new-replace-"));
    const path = join(dir, "stillfail.db");
    let store = Store.open(path);
    const owner = { turn: null, person: null, thread: null, profile: "cc" };
    const call = (id: string, at: number, input: number, output: number) => [{ id, at, model: "m", subagent: false,
      fast: false, input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output, calls: 1, context: null, window: null }, owner] as const;
    try {
      store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", ws: "A", createdAt: 1, lastActiveAt: 1 });
      store.recordUsage("/s", { session: "s", offset: 1, model: null }, "claude", [call("old", 100, 10, 1)] as never);
      forgetDetail(store);
      store.close();
      store = Store.open(path);
      store.db.exec(`PRAGMA recursive_triggers = ${recursive}`);
      store.recordUsage("/s", { session: "s", offset: 2, model: null }, "claude", [call("new", 50, 3, 1)] as never);
      store.db.exec("INSERT OR REPLACE INTO usage SELECT * FROM usage WHERE id = 'old'");
      store.db.exec("INSERT OR REPLACE INTO usage SELECT * FROM usage WHERE id = 'new'");
      store.recordUsage("/s", { session: "s", offset: 3, model: null }, "claude", [call("old", 100, 10, 9), call("new", 50, 3, 7)] as never);
      const groups = () => usageGroups(makeStore(store.db, dir), -100n, 1000n, 0n, { workspace: "A", home: false });
      assert.deepEqual(groups().map((g) => [g.calls, g.input, g.output]), [[1, 3, 7]], `recursive triggers ${recursive}`);

      // Moving an uncounted call past the old end must not make it look like a newly inserted call. A counted call
      // can move across that boundary and must remain counted exactly once.
      store.db.exec("UPDATE usage SET at = 500 WHERE id = 'old'; UPDATE usage SET at = -10 WHERE id = 'new'");
      assert.deepEqual(groups().map((g) => [g.calls, g.input, g.output]), [[1, 3, 7]]);
      store.db.exec("INSERT OR IGNORE INTO usage SELECT * FROM usage WHERE id = 'old'; DELETE FROM usage WHERE id = 'old'");
      store.recordUsage("/s", { session: "s", offset: 4, model: null }, "claude", [call("old", 500, 10, 2)] as never);
      const byDay = groups().map((g) => [g.day, g.calls, g.input, g.output]).sort();
      assert.deepEqual(byDay, [["1969-12-31", 1, 3, 7], ["1970-01-01", 1, 10, 2]],
        "deleting an old call and recording it anew counts the new insertion");
    } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
  }
});

test("incremental detail agrees with new calls through changes to old and new rows", () => {
  for (const recursive of ["OFF", "ON"]) {
    const dir = mkdtempSync(join(tmpdir(), "usage-new-changes-"));
    const path = join(dir, "stillfail.db");
    let store = Store.open(path);
    const owner = { turn: null, person: null, thread: null, profile: "cc" };
    const call = (id: string, at: number, input: number, output: number) => [{ id, at, model: "m", subagent: false,
      fast: false, input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output, calls: 1, context: null, window: null }, owner] as const;
    type Row = { at: number; input: number; output: number; counted: boolean };
    const rows = new Map<string, Row>();
    let seed = 7;
    const random = (n: number) => { seed = (seed * 1_664_525 + 1_013_904_223) >>> 0; return (seed >>> 8) % n; };
    try {
      store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", ws: "A", createdAt: 1, lastActiveAt: 1 });
      for (let i = 0; i < 25; i++) {
        const id = `c${i}`, at = i * 10;
        rows.set(id, { at, input: i + 1, output: 1, counted: false });
        store.recordUsage("/s", { session: "s", offset: i, model: null }, "claude", [call(id, at, i + 1, 1)] as never);
      }
      forgetDetail(store);
      store.close();
      store = Store.open(path);
      store.db.exec(`PRAGMA recursive_triggers = ${recursive}`);
      for (let i = 0; i < 200; i++) {
        const id = `c${random(40)}`, op = random(4), row = rows.get(id);
        if (op === 0 && row) {
          row.at = random(400) - 100;
          store.db.prepare("UPDATE usage SET at = ? WHERE id = ?").run(row.at, id);
        } else if (op === 1 && row) {
          row.output = random(20);
          store.db.prepare("UPDATE usage SET output = ? WHERE id = ?").run(row.output, id);
        } else if (op === 2 && row) {
          store.db.prepare("INSERT OR REPLACE INTO usage SELECT * FROM usage WHERE id = ?").run(id);
        } else if (op === 3 && row) {
          store.db.prepare("DELETE FROM usage WHERE id = ?").run(id);
          rows.delete(id);
        } else if (!row) {
          const at = random(400) - 100, input = random(30) + 1, output = random(20);
          store.recordUsage("/s", { session: "s", offset: 100 + i, model: null }, "claude", [call(id, at, input, output)] as never);
          rows.set(id, { at, input, output, counted: true });
        }
        const expected = new Map<string, [number, number, number]>();
        for (const item of rows.values()) if (item.counted) {
          const day = new Date(item.at).toISOString().slice(0, 10);
          const sum: [number, number, number] = expected.get(day) ?? [0, 0, 0];
          sum[0]++; sum[1] += item.input; sum[2] += item.output;
          expected.set(day, sum);
        }
        const actual = usageGroups(makeStore(store.db, dir), -1000n, 1000n, 0n, { workspace: "A", home: false })
          .map((g) => [g.day, [g.calls, g.input, g.output]]).sort();
        assert.deepEqual(actual, [...expected].sort(), `trigger mode ${recursive}, change ${i}`);
      }
    } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
  }
});
