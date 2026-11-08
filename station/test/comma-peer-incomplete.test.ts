import assert from "node:assert/strict";
import { test } from "node:test";
import { workspaceRead } from "../src/comma/peer.ts";
import { CommaStats } from "../src/comma/stats.ts";

const from = Date.UTC(2026, 10, 1), to = Date.UTC(2026, 10, 9);
const usage = { rows: [{ day: "2026-11-08", session: "s", person: "p", account: "a", runtime: "claude", model: "m", calls: 1 }], people: {} };
const chat = { thread: 7, title: "kept", createdAt: from, lastActiveAt: from };
const quiet = () => () => {};
const empty = async () => ({ stations: [], unread: [] });
const local = (op: string) => JSON.stringify(op === "outflowUsage" ? { rows: [], people: {} } : { chats: [], more: false });

for (const [name, remote] of [
  ["usage without rows", (op: string) => op === "outflowUsage" ? { rows: null } : { chats: [], more: false }],
  ["a usage row without its key", (op: string) => op === "outflowUsage" ? { rows: [{ day: "2026-11-08" }] } : { chats: [], more: false }],
  ...(["person", "account", "runtime", "model"] as const).map((key) => [`a usage row without ${key}`, (op: string) => {
    const row: Record<string, unknown> = { ...usage.rows[0] };
    delete row[key];
    return op === "outflowUsage" ? { rows: [row] } : { chats: [], more: false };
  }] as const),
  ["chats without an array", (op: string) => op === "outflowUsage" ? usage : { chats: null, more: false }],
  ["a chat without its thread", (op: string) => op === "outflowUsage" ? usage : { chats: [{ title: "partial" }], more: false }],
  ["a page promising more without a cursor", (op: string) => op === "outflowUsage" ? usage : { chats: [], more: true, next: null }],
  ["a page with an invalid continuation flag", (op: string) => op === "outflowUsage" ? usage : { chats: [], more: "true" }],
] as const) {
  test(`an incomplete peer answer (${name}) keeps that station's previous rows`, async () => {
    const stats = new CommaStats(":memory:", empty, quiet);
    try {
      stats.apply([{ station: "away", usage, chats: [chat] }], [], from);
      const read = workspaceRead({ home: () => "home", here: async (op) => local(op), others: async () => ["away"],
        there: async (_station, op) => JSON.stringify(remote(op)) });
      const got = await read(from, to);
      const changed = stats.apply(got.stations, got.unread, from);
      assert.deepEqual(changed, { stats: 0, tasks: 0 }, "an incomplete answer must not tombstone previously held rows");
      assert.equal(stats.taskTitle("7@away"), "kept");
      assert.deepEqual(got.unread, ["away"]);
    } finally { stats.close(); }
  });
}

test("a repeating peer cursor is refused before requesting it again", async () => {
  let pages = 0;
  const read = workspaceRead({ home: () => "home", here: async (op) => local(op), others: async () => ["away"],
    there: async (_station, op) => {
      if (op === "outflowUsage") return JSON.stringify(usage);
      pages++;
      if (pages > 3) throw new Error("test safety stop");
      return JSON.stringify({ chats: [], more: true, next: pages === 2 ? "two" : "one" });
    },
  });
  const got = await read(from, to);
  assert.deepEqual(got.unread, ["away"]);
  assert.equal(pages, 3, "the cycle one → two → one must stop without another request");
});

test("an incomplete local answer fails the build instead of reading it as empty", async () => {
  const read = workspaceRead({ home: () => "home", here: async (op) => op === "outflowUsage" ? JSON.stringify(usage) : JSON.stringify({ chats: null }),
    others: async () => [], there: async () => { throw new Error("unused"); } });
  await assert.rejects(() => read(from, to));
});

test("an older unpaged answer without more and next remains readable", async () => {
  const read = workspaceRead({ home: () => "home", here: async (op) => local(op), others: async () => ["away"],
    there: async (_station, op) => JSON.stringify(op === "outflowUsage" ? usage : { chats: [chat] }) });
  const got = await read(from, to);
  assert.deepEqual(got.unread, []);
  assert.deepEqual(got.stations[1]?.chats, [chat]);
});

test("a usage row can have null person, account and model", async () => {
  const row = { ...usage.rows[0], person: null, account: null, model: null };
  const read = workspaceRead({ home: () => "home", here: async (op) => local(op), others: async () => ["away"],
    there: async (_station, op) => JSON.stringify(op === "outflowUsage" ? { rows: [row] } : { chats: [] }) });
  const got = await read(from, to);
  assert.deepEqual(got.unread, []);
  assert.deepEqual(got.stations[1]?.usage.rows, [row]);
});

test("a later complete answer can remove a peer's rows after its partial answer was refused", async () => {
  let complete = false;
  const stats = new CommaStats(":memory:", empty, quiet);
  try {
    stats.apply([{ station: "away", usage, chats: [chat] }], [], from);
    const read = workspaceRead({ home: () => "home", here: async (op) => local(op), others: async () => ["away"],
      there: async (_station, op) => JSON.stringify(op === "outflowUsage" ? { rows: [], people: {} }
        : complete ? { chats: [], more: false } : { chats: [], more: true, next: null }) });
    const partial = await read(from, to);
    assert.deepEqual(stats.apply(partial.stations, partial.unread, from), { stats: 0, tasks: 0 });
    assert.equal(stats.taskTitle("7@away"), "kept");
    complete = true;
    const done = await read(from, to);
    assert.deepEqual(stats.apply(done.stations, done.unread, from), { stats: 1, tasks: 1 });
    assert.equal(stats.taskTitle("7@away"), "");
  } finally { stats.close(); }
});
