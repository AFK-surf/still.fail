import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { routerReads } from "../src/comma/chats.ts";
import { CommaStats, type StationRows } from "../src/comma/stats.ts";

const from = Date.UTC(2026, 10, 1);
const station = (chats: unknown[], id?: string): StationRows => ({ ...(id === undefined ? {} : { station: id }), usage: { rows: [] }, chats });
const chat = (thread: number, title: string) => ({ thread, title, createdAt: from, lastActiveAt: from, agents: [] });

test("the Router reads the current title of the requested workspace chat", async () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-task-read-"));
  const stats = CommaStats.at(dir, async () => ({ stations: [], unread: [] }), () => () => {});
  const asked: unknown[][] = [];
  const reply = JSON.stringify({ messages: [
    { kind: "message", n: 4, authorKind: "person", person: { name: "Ada" }, text: "hello", at: 42 },
    { kind: "edit", n: 5, text: "later" },
  ], last: 5 });
  const reads = {
    home: () => "home",
    here: async (op: string, args: unknown) => (asked.push(["here", op, args]), reply),
    there: async (id: string, op: string, args: unknown) => (asked.push([id, op, args]), reply),
  };
  try {
    stats.apply([station([chat(7, "Local")]), station([chat(7, "Peer")], "other")], [], from);
    assert.deepEqual(await routerReads(stats, reads, "7", 3, 20), {
      title: "Local", messages: [{ seq: 4, author_kind: "person", author: "Ada", text: "hello", at: 42 }], through: 5,
    });
    assert.equal((await routerReads(stats, reads, "7@other", 0, 20)).title, "Peer");
    assert.deepEqual(asked, [
      ["here", "outflowMessages", { thread: 7, after: 3, limit: 20, ws: { workspace: "home", home: true } }],
      ["other", "outflowMessages", { thread: 7, after: 0, limit: 20 }],
    ]);
    assert.equal((await routerReads(stats, reads, "8", 0, 20)).title, "", "a chat not in the index has no title");
    stats.apply([station([])], ["other"], from);
    assert.equal((await routerReads(stats, reads, "7", 0, 20)).title, "", "a removed row has no title");
    assert.equal((await routerReads(stats, reads, "7@other", 0, 20)).title, "Peer", "an unread station's row stays");
    await assert.rejects(routerReads(stats, { ...reads, here: async () => "null" }, "7", 0, 20), /no such chat of the workspace/);
    await assert.rejects(routerReads(stats, reads, "not-a-chat", 0, 20), /no such chat/);
  } finally { stats.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a Task title lookup respects old row revisions and the whole key", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-task-key-"));
  const stats = CommaStats.at(dir, async () => ({ stations: [], unread: [] }), () => () => {});
  const db = new DatabaseSync(join(dir, "comma-stats.db"));
  try {
    const insert = db.prepare("INSERT INTO task_index (key, source, kind, rev, json, removed) VALUES (?, 'stillfail', 'task', ?, ?, ?)");
    insert.run("7@peer\0one", 1, JSON.stringify({ title: "One" }), 0);
    insert.run("7@peer\0two", 2, JSON.stringify({ title: "Two" }), 0);
    insert.run("8", 0, JSON.stringify({ title: "Not yet indexed" }), 0);
    insert.run("9", 3, JSON.stringify({ title: null }), 0);
    insert.run("10", 4, "not json", 0);
    insert.run("7@peer\ufffd", 5, JSON.stringify({ title: "Replacement" }), 0);
    assert.equal(stats.taskTitle("7@peer\0one"), "One");
    assert.equal(stats.taskTitle("7@peer\0two"), "Two");
    assert.equal(stats.taskTitle("7@peer"), "");
    assert.equal(stats.taskTitle("8"), "", "the old reader starts after revision zero");
    assert.equal(stats.taskTitle("9"), null, "the old reader returned the stored title as it was");
    assert.equal(stats.taskTitle("7@peer\ud800"), "", "a malformed key is not its replacement-character neighbor");
    assert.equal(stats.taskTitle("7@peer\ufffd"), "Replacement");
    assert.throws(() => stats.taskTitle("10"), SyntaxError);
  } finally { db.close(); stats.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("the title is read after the workspace's message read completes", async () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-task-after-"));
  const stats = CommaStats.at(dir, async () => ({ stations: [], unread: [] }), () => () => {});
  let finish!: (value: string) => void;
  const pending = new Promise<string>((resolve) => { finish = resolve; });
  const reads = { home: () => null, here: () => pending, there: () => pending };
  try {
    stats.apply([station([chat(7, "Before")])], [], from);
    const result = routerReads(stats, reads, "7", 0, 20);
    stats.apply([station([chat(7, "After")])], [], from);
    finish(JSON.stringify({ messages: [], last: 0 }));
    assert.equal((await result).title, "After");
  } finally { stats.close(); rmSync(dir, { recursive: true, force: true }); }
});
