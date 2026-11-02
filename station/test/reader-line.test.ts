// The readers' one line (read/pool.ts): what the event streams tell goes before the pages asked, so a message just said
// is not held up behind them.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Readers, chat } from "../src/read/pool.ts";
import { Store } from "../src/store/store.ts";

test("a read the streams tell is answered before the pages asked before it", async () => {
  const data = mkdtempSync(join(tmpdir(), "reader-line-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const readers = new Readers(data, 1);
  try {
    const answered: string[] = [];
    // Reads no reader knows: each is answered (refused) in turn, in the order the one reader took them.
    const ask = (name: string, told = false) => readers.read(name, {}, "en", { told }).catch(() => void answered.push(name));
    await Promise.all([ask("taken"), ask("page 1"), ask("page 2"), ask("told", true), ask("page 3")]);
    assert.deepEqual(answered, ["taken", "told", "page 1", "page 2", "page 3"]);
  } finally {
    readers.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

for (const bulk of ["usage", "chats", "openJobs", "changed"]) test(`messages and chats can be read while ${bulk} reads are held`, async () => {
  const data = mkdtempSync(join(tmpdir(), "reader-line-"));
  const readers = new Readers(data, 2, new URL("./reader-line-worker.mjs", import.meta.url));
  // The worker counts the reads it starts, says which interactive reads started, and holds bulk reads at the gate.
  const state = new Int32Array(new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT * 3));
  const args = { state: state.buffer };
  const asked = [readers.read(bulk, args, "en"), readers.read(bulk, args, "en"), readers.read("thread", args, "en"), readers.read("entries", { ...args, params: [["from", "10"], ["to", "12"]] }, "en", { told: true })];
  let finished: PromiseSettledResult<string>[] = [];
  try {
    const started = async (wanted: number) => {
      while (Atomics.load(state, 0) < wanted) {
        const count = Atomics.load(state, 0);
        if (count < wanted) await Atomics.waitAsync(state, 0, count).value;
      }
    };
    await Promise.race([started(2), Promise.all(asked)]);
    assert.notEqual(Atomics.load(state, 1), 0, "interactive reads are not held behind two bulk reads");
    await Promise.race([started(3), Promise.all(asked)]);
    assert.equal(Atomics.load(state, 1), 9, "both the chat and stream can be read before bulk reads finish");
  } finally {
    Atomics.store(state, 2, 1);
    Atomics.notify(state, 2);
    finished = await Promise.allSettled(asked);
    readers.close();
    rmSync(data, { recursive: true, force: true });
  }
  assert.equal(Atomics.load(state, 0), 4, "the waiting bulk read is also taken");
  assert.ok(finished.every((result) => result.status === "fulfilled"));
});

for (const background of ["timeline", "resourceChats", "aNewRead"]) test(`a stalled ${background} and usage cannot occupy both readers ahead of a file and a message`, async () => {
  const data = mkdtempSync(join(tmpdir(), "reader-line-"));
  const readers = new Readers(data, 2, new URL("./reader-line-worker.mjs", import.meta.url));
  const state = new Int32Array(new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT * 3));
  const args = { state: state.buffer };
  const asked = [readers.read("usage", args, "en"), readers.read(background, args, "en"), readers.read("sessionFile", args, "en"), readers.read("entries", { ...args, params: [["from", "10"], ["to", "12"]] }, "en", { told: true })];
  try {
    const started = async (wanted: number) => {
      while (Atomics.load(state, 0) < wanted) {
        const count = Atomics.load(state, 0);
        if (count < wanted) await Atomics.waitAsync(state, 0, count).value;
      }
    };
    await started(2);
    assert.notEqual(Atomics.load(state, 1) & 4, 0, "the file starts without waiting for both background reads");
    await started(3);
    assert.equal(Atomics.load(state, 1) & 12, 12, "the message starts too");
  } finally {
    Atomics.store(state, 2, 1);
    Atomics.notify(state, 2);
    await Promise.allSettled(asked);
    readers.close();
    rmSync(data, { recursive: true, force: true });
  }
});

/// Waits until the worker has started `wanted` reads in all (or every read asked has ended).
async function started(state: Int32Array, wanted: number, asked: Promise<unknown>[]) {
  const all = Promise.allSettled(asked);
  while (Atomics.load(state, 0) < wanted) {
    const count = Atomics.load(state, 0);
    if (count >= wanted) break;
    const more = Atomics.waitAsync(state, 0, count).value;
    if ((await Promise.race([more, all.then(() => "ended")])) === "ended") break;
  }
}

// What happened on ccvm (2026-11-02 15:41): a usage read held one reader 97 s and a sidebar update (told by the streams)
// the other; the message just said waited 50 s for a read of 11 ms. Bulk reads of any kind, told or not, known or not,
// never take the chat reader.
for (const told of [false, true]) test(`bulk reads${told ? " the streams tell" : ""}, however many and however long, leave the chat reader to a message, a chat and a file`, async () => {
  const data = mkdtempSync(join(tmpdir(), "reader-line-"));
  const readers = new Readers(data, 2, new URL("./reader-line-worker.mjs", import.meta.url));
  const state = new Int32Array(new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT * 3));
  const args = { state: state.buffer };
  const bulk = ["usage", "chatRows", "summary", "turnNotices", "aNewRead", "timeline", "checkpoint"].map((op) => readers.read(op, args, "en", { told }));
  const asked = [
    ...bulk,
    readers.read("entries", { ...args, params: [["from", "41"], ["to", "41"]] }, "en", { told: true }),
    readers.read("thread", args, "en", { told: true }),
    readers.read("sessionFile", args, "en"),
  ];
  try {
    // Two reads have started: a bulk one, and the message just said (not a second bulk one).
    await started(state, 2, asked);
    assert.equal(Atomics.load(state, 1) & 8, 8, "the message is read while the bulk reads wait");
    await started(state, 4, asked);
    assert.equal(Atomics.load(state, 1) & 13, 13, "the chat and the file too");
  } finally {
    Atomics.store(state, 2, 1);
    Atomics.notify(state, 2);
    await Promise.allSettled(asked);
    readers.close();
    rmSync(data, { recursive: true, force: true });
  }
});

test("only bounded pages of a chat are chat reads: an open catch-up or a wide range is bulk", () => {
  const page = (params: [string, string][]) => chat("entries", { params });
  assert.equal(page([]), true);
  assert.equal(page([["before", "900"]]), true);
  assert.equal(page([["from", "10"], ["to", "509"]]), true);
  assert.equal(page([["from", "10"], ["to", "510"]]), false);
  assert.equal(page([["from", "10"]]), false);
  assert.equal(page([["after", "10"], ["limit", "100"]]), true);
  assert.equal(page([["after", "10"]]), false);
  assert.equal(chat("letters", { params: [["after", "3"]] }), false);
  for (const op of ["thread", "sessionFile"]) assert.equal(chat(op, {}), true);
  for (const op of ["chatRows", "summary", "usage", "timeline", "aNewRead"]) assert.equal(chat(op, {}), false);
});
