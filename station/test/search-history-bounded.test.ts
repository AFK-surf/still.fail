import assert from "node:assert/strict";
import fs from "node:fs";
import { open } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { openStore } from "../src/read/store.ts";
import { historyGroup, historyHits } from "../src/search/sources.ts";
import { Store } from "../src/store/store.ts";

const asker = { workspace: "W1", home: true, scopes: ["write"] };

function fixture() {
  const data = fs.mkdtempSync(join(tmpdir(), "history-search-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/s", token: "s", createdAt: 1, lastActiveAt: 1 });
  const thread = store.openThreadOf("ember", "ember", "s", null, "a@x", "s");
  store.joinThread(thread.id, "s", "ember");
  store.setRuntimeSessionId("s", "rs1");
  const home = join(data, "p");
  fs.mkdirSync(join(home, "projects", "w"), { recursive: true });
  const file = join(home, "projects", "w", "rs1.jsonl");
  const profiles = [{ id: "cc", home, runtime: "claude" }];
  const read = openStore(data);
  return { file, profiles, read, close: () => { read.db.close(); store.close(); fs.rmSync(data, { recursive: true, force: true }); } };
}

async function countReads(path: string, size: number) {
  const inode = fs.statSync(path).ino;
  const handle = await open(path, "r");
  const fileType = Object.getPrototypeOf(handle);
  const read = fileType.read;
  await handle.close();
  let count = 0;
  fileType.read = async function (...args: any[]) {
    const result = await read.apply(this, args);
    if (args[2] === size && fs.fstatSync(this.fd).ino === inode) count++;
    return result;
  };
  return { count: () => count, restore: () => { fileType.read = read; } };
}

test("a history search stops within one growing file when its budget runs out", async () => {
  const f = fixture();
  let reads: Awaited<ReturnType<typeof countReads>> | null = null;
  try {
    fs.writeFileSync(f.file, Buffer.alloc(16 << 20, "a"));
    reads = await countReads(f.file, 8 << 20);
    const found = await historyHits(f.read, f.profiles, ["needle"], asker, { limit: 5, offset: 0, ms: 1, now: () => reads!.count() ? 2 : 0 });
    assert.deepEqual(found.hits, []);
    assert.equal(found.left, 1, "the unfinished session is reported as unsearched");
    assert.equal(found.more, true);
    assert.deepEqual(historyGroup(found), { kind: "history", hits: [], more: true, left: 1 }, "the caller is told even when no hit was found");
    assert.equal(reads.count(), 1, "the rest of the file is not read after the budget expires");
  } finally {
    reads?.restore();
    f.close();
  }
});

test("a matching history with a very long line can stop before it is parsed", async () => {
  const f = fixture();
  let reads: Awaited<ReturnType<typeof countReads>> | null = null;
  try {
    const record = { type: "assistant", timestamp: "2026-10-18T08:00:00Z", message: { content: [{ type: "text", text: `needle ${"a".repeat(3 << 20)}` }] } };
    fs.writeFileSync(f.file, `${JSON.stringify(record)}\n`);
    reads = await countReads(f.file, 1 << 20);
    const found = await historyHits(f.read, f.profiles, ["needle"], asker, { limit: 5, offset: 0, ms: 1, now: () => reads!.count() ? 2 : 0 });
    assert.deepEqual(found.hits, []);
    assert.equal(found.left, 1, "an interrupted file is not reported as fully searched");
    assert.equal(found.more, true);
    assert.equal(reads.count(), 1, "the unfinished line is not read or copied after the budget expires");
  } finally {
    reads?.restore();
    f.close();
  }
});

test("a cancelled history search stops in the current file", async () => {
  const f = fixture();
  let reads: Awaited<ReturnType<typeof countReads>> | null = null;
  try {
    fs.writeFileSync(f.file, Buffer.alloc(16 << 20, "a"));
    reads = await countReads(f.file, 8 << 20);
    await assert.rejects(historyHits(f.read, f.profiles, ["needle"], asker, { limit: 5, offset: 0, ms: 10_000, now: () => 0, cancelled: () => reads!.count() > 0 }), /the search took too long/);
    assert.equal(reads.count(), 1);
  } finally {
    reads?.restore();
    f.close();
  }
});

test("a page of many matching history steps keeps the newest steps and their original numbers", async () => {
  const f = fixture();
  try {
    const lines = Array.from({ length: 12 }, (_, n) => JSON.stringify({
      type: "assistant", timestamp: "2026-10-18T08:00:00Z", message: { content: [{ type: "text", text: `needle ${n}` }] },
    }));
    fs.writeFileSync(f.file, `${lines.join("\n")}\n`);
    const found = await historyHits(f.read, f.profiles, ["needle"], asker, { limit: 2, offset: 3, ms: 10_000, now: () => 0 });
    assert.deepEqual(found.hits.map((h) => [h.index, h.text]), [[8, "needle 8"], [7, "needle 7"]]);
    assert.equal(found.more, true);
    assert.equal(found.left, 0);
  } finally { f.close(); }
});
