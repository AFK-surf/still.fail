// The readers' one line (read/pool.ts): what the event streams tell goes before the pages asked, so a message just said
// is not held up behind them.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
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
  const asked = [readers.read(bulk, args, "en"), readers.read(bulk, args, "en"), readers.read("thread", args, "en"), readers.read("told", args, "en", { told: true })];
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
    assert.equal(Atomics.load(state, 1), 3, "both the chat and stream can be read before bulk reads finish");
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
  const asked = [readers.read("usage", args, "en"), readers.read(background, args, "en"), readers.read("sessionFile", args, "en"), readers.read("told", args, "en", { told: true })];
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
    assert.equal(Atomics.load(state, 1) & 6, 6, "the message starts too");
  } finally {
    Atomics.store(state, 2, 1);
    Atomics.notify(state, 2);
    await Promise.allSettled(asked);
    readers.close();
    rmSync(data, { recursive: true, force: true });
  }
});
