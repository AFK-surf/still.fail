import assert from "node:assert/strict";
import { test } from "node:test";
import { DISK_LOW_BYTES } from "../src/ops/disk.ts";
import { ColdRooms } from "../src/sessions/cold.ts";
import { expireArchived, relieveArchived } from "../src/sessions/lifecycle.ts";
import { Rig } from "./hub-fakes.ts";

const DAY = 86_400_000;

function rig() {
  const emptied: string[] = [];
  const cold = {
    isCold: async () => false,
    restore: () => {},
    pack: () => {},
    holdsMore: async () => true,
    expire: async (key: string) => { emptied.push(key); },
  };
  const r = new Rig({ cold });
  const fetched: number[] = [];
  const read = r.store.archivedSessions.bind(r.store) as (...args: any[]) => ReturnType<typeof r.store.archivedSessions>;
  r.store.archivedSessions = ((...args: any[]) => {
    const rows = read(...args);
    fetched.push(rows.length);
    return rows;
  }) as typeof r.store.archivedSessions;
  const add = (key: string, at: number) => {
    r.store.insertSession({ key, connect: "cl", runtime: "claude", profile: "cc", workspace: r.dir, token: key, createdAt: at, lastActiveAt: at });
    r.store.db.prepare("UPDATE sessions SET archived_at = ? WHERE key = ?").run(at, key);
  };
  return { r, add, cold, emptied, fetched };
}

test("emptying workspaces reads only due archives, a bounded page at a time", async () => {
  const { r, add, emptied, fetched } = rig();
  try {
    for (let i = 0; i < 130; i++) add(`old-${String(i).padStart(3, "0")}`, DAY);
    for (let i = 0; i < 200; i++) add(`future-${String(i).padStart(3, "0")}`, 20 * DAY);
    let yielded = false;
    const done = expireArchived(r.hub, 8 * DAY);
    setImmediate(() => { yielded = true; });
    assert.equal(await done, 27 * DAY);
    assert.equal(yielded, true, "other station work can run between pages");
    assert.deepEqual(emptied, Array.from({ length: 130 }, (_, i) => `old-${String(i).padStart(3, "0")}`));
    assert.ok(fetched.length > 1 && fetched.every((n) => n <= 64), `archive rows per read: ${fetched}`);
    assert.equal(fetched.reduce((a, b) => a + b, 0), 130, "future archives are not read as cleanup candidates");
    const plans = [
      ["SELECT key, archived_at FROM sessions INDEXED BY sessions_put_away WHERE archived_at IS NOT NULL AND archived_at <= ? AND (archived_at, key) > (?, ?) ORDER BY archived_at, key LIMIT 64", [DAY, DAY, "old-050"]],
      ["SELECT archived_at FROM sessions INDEXED BY sessions_put_away WHERE archived_at > ? ORDER BY archived_at, key LIMIT 1", [DAY]],
    ] as const;
    for (const [sql, args] of plans) {
      const plan = (r.store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((p) => p.detail).join(" | ");
      assert.match(plan, /SEARCH sessions USING (?:COVERING )?INDEX sessions_put_away/, plan);
      assert.doesNotMatch(plan, /TEMP B-TREE/, plan);
    }
  } finally { await r.close(); }
});

test("a low-disk sweep finishes at the last archive it saw when it began", async () => {
  const { r, add, cold, emptied } = rig();
  try {
    for (let i = 0; i < 130; i++) add(`old-${String(i).padStart(3, "0")}`, DAY);
    let added = false;
    cold.holdsMore = async () => {
      if (!added) { added = true; add("zz-new", DAY); }
      return true;
    };
    await relieveArchived(r.hub, () => DISK_LOW_BYTES - 1);
    assert.deepEqual(emptied, Array.from({ length: 130 }, (_, i) => `old-${String(i).padStart(3, "0")}`));
  } finally { await r.close(); }
});

test("cleanup rechecks free space before emptying a workspace", async () => {
  const { r, add, emptied } = rig();
  try {
    add("old", DAY);
    let checks = 0;
    await relieveArchived(r.hub, () => ++checks <= 2 ? DISK_LOW_BYTES - 1 : DISK_LOW_BYTES);
    assert.deepEqual(emptied, [], "room recovered after the sweep began");
  } finally { await r.close(); }
});

test("cleanup leaves a workspace when room recovers while its contents are checked", async () => {
  const { r, add, cold, emptied } = rig();
  try {
    add("old", DAY);
    let room = false;
    cold.holdsMore = async () => { room = true; return true; };
    await relieveArchived(r.hub, () => room ? DISK_LOW_BYTES : DISK_LOW_BYTES - 1);
    assert.deepEqual(emptied, [], "room recovered while checking the workspace");
  } finally { await r.close(); }
});

test("low-disk cleanup stops reading archives once it has freed enough room", async () => {
  const { r, add, emptied, fetched } = rig();
  try {
    for (let i = 0; i < 200; i++) add(`old-${String(i).padStart(3, "0")}`, DAY);
    await relieveArchived(r.hub, () => DISK_LOW_BYTES);
    assert.deepEqual(fetched, [], "nothing is read while there is enough room");
    await relieveArchived(r.hub, () => emptied.length ? DISK_LOW_BYTES : DISK_LOW_BYTES - 1);
    assert.deepEqual(emptied, ["old-000"]);
    assert.ok(fetched.reduce((a, b) => a + b, 0) <= 64, `archive rows read: ${fetched}`);
  } finally { await r.close(); }
});

test("segmenting old transcripts reads archived sessions in bounded pages", async () => {
  const { r, add, fetched } = rig();
  const cold = new ColdRooms(() => r.hub);
  const list = r.store.listSessions;
  try {
    for (let i = 0; i < 130; i++) add(`old-${String(i).padStart(3, "0")}`, DAY);
    for (let i = 0; i < 200; i++) r.store.insertSession({ key: `live-${i}`, connect: "cl", runtime: "claude", profile: "cc", workspace: r.dir, token: `live-${i}`, createdAt: DAY, lastActiveAt: DAY });
    const visited: string[] = [];
    cold.historyFiles = (key) => {
      visited.push(key);
      if (visited.length === 1) add("late", 2 * DAY);
      return [];
    };
    r.store.listSessions = () => { throw new Error("all session history was read"); };
    let yielded = false;
    const done = cold.segmentHistories();
    setImmediate(() => { yielded = true; });
    await done;
    assert.equal(yielded, true, "other station work can run while archives are processed");
    assert.deepEqual(visited, Array.from({ length: 130 }, (_, i) => `old-${String(i).padStart(3, "0")}`));
    assert.ok(fetched.length > 1 && fetched.every((n) => n <= 64), `archive rows per read: ${fetched}`);
    assert.equal(fetched.reduce((a, b) => a + b, 0), 130, "live and later-archived sessions are not read");
    const reads = fetched.length;
    await cold.segmentHistories();
    assert.equal(fetched.length, reads, "a completed sweep is not repeated");
  } finally {
    r.store.listSessions = list;
    await r.close();
  }
});
