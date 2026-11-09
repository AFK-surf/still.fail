import assert from "node:assert/strict";
import { test } from "node:test";
import { workspaceRead } from "../src/comma/peer.ts";

const answer = (op: string) => JSON.stringify(op === "outflowUsage" ? { rows: [], people: {} } : { chats: [], more: false });
const until = async (f: () => boolean) => {
  for (let i = 0; i < 100 && !f(); i++) await new Promise<void>((resolve) => setImmediate(resolve));
  assert.ok(f());
};

test("an unavailable station does not keep an available station from being read", async () => {
  const started: string[] = [];
  let failSlow!: () => void;
  const slow = new Promise<never>((_, reject) => { failSlow = () => reject(new Error("unavailable")); });
  const read = workspaceRead({
    of: () => ({ workspace: "home", home: true }),
    here: async (op) => answer(op),
    others: async () => ["slow", "fast"],
    there: async (station, op) => {
      started.push(`${station}:${op}`);
      if (station === "slow") return slow;
      return answer(op);
    },
  });
  const pending = read(0, 1);
  await new Promise<void>((resolve) => setImmediate(resolve));
  const beforeSlowFails = [...started];
  failSlow();
  const result = await pending;
  assert.deepEqual(result.unread, ["slow"]);
  assert.deepEqual(result.stations.map((row) => row.station ?? ""), ["", "fast"]);
  assert.ok(beforeSlowFails.includes("fast:outflowUsage"), `only these requests started before the failure: ${beforeSlowFails.join(", ")}`);
});

test("peer reads stay bounded and their results retain roster order", async () => {
  const ids = ["a", "b", "c", "d", "e"], started: string[] = [];
  const waits = new Map<string, { promise: Promise<void>; release: () => void }>();
  for (const id of ids) {
    let release!: () => void;
    const promise = new Promise<void>((resolve) => { release = resolve; });
    waits.set(id, { promise, release });
  }
  let active = 0, most = 0;
  const read = workspaceRead({
    of: () => ({ workspace: "home", home: true }),
    here: async (op) => answer(op),
    others: async () => ids,
    there: async (station, op) => {
      if (op === "outflowUsage") {
        started.push(station);
        most = Math.max(most, ++active);
        await waits.get(station)!.promise;
        active--;
        if (station === "c") throw new Error("unavailable");
      }
      return answer(op);
    },
  });
  const pending = read(0, 1);
  try {
    await until(() => started.length === 2);
    assert.deepEqual(started, ["a", "b"]);
    waits.get("b")!.release(); await until(() => started.length === 3);
    waits.get("c")!.release(); await until(() => started.length === 4);
    waits.get("d")!.release(); await until(() => started.length === 5);
    waits.get("e")!.release(); waits.get("a")!.release();
    const result = await pending;
    assert.equal(most, 2);
    assert.deepEqual(result.stations.map((row) => row.station ?? ""), ["", "a", "b", "d", "e"]);
    assert.deepEqual(result.unread, ["c"]);
  } finally { for (const wait of waits.values()) wait.release(); }
});
