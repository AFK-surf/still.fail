// The readers' two lines (read/pool.ts): what the station tells is read by its own reader, whatever devices ask; among
// what devices ask, bulk reads leave room for a chat's.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { Store } from "../src/store/store.ts";

/// Readers answering by reader-line-worker.mjs, and its state: how many reads started, which kinds, and the gate.
function gated(size: number) {
  const data = mkdtempSync(join(tmpdir(), "reader-line-"));
  const readers = new Readers(data, size, new URL("./reader-line-worker.mjs", import.meta.url));
  const state = new Int32Array(new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT * 3));
  const args = (hold: boolean) => ({ state: state.buffer, hold });
  const started = async (wanted: number) => {
    for (let count = Atomics.load(state, 0); count < wanted; count = Atomics.load(state, 0)) await Atomics.waitAsync(state, 0, count).value;
  };
  const open = async (asked: Promise<string>[]) => {
    Atomics.store(state, 2, 1);
    Atomics.notify(state, 2);
    const settled = await Promise.allSettled(asked);
    readers.close();
    rmSync(data, { recursive: true, force: true });
    return settled;
  };
  return { readers, state, args, started, open };
}

// On ccvm (2026-11-02 15:41 UTC) a usage read held one reader for 97 s and sidebar updates the other: what was told of
// two messages just said waited 50 s and 31 s, a push notice 55 s.
test("what the station tells is read while every reader of what devices ask is held", { timeout: 30_000 }, async () => {
  const { readers, state, args, started, open } = gated(2);
  const asked = [readers.read("thread", args(true), "en"), readers.read("thread", args(true), "en"), readers.read("usage", args(true), "en")];
  try {
    await started(2);
    const told = await readers.read("told", args(false), "en", { told: true });
    assert.equal(told, "{}");
    assert.equal(Atomics.load(state, 0), 3, "the device reads still held, the third still waiting");
  } finally {
    const settled = await open(asked);
    assert.ok(settled.every((s) => s.status === "fulfilled"));
  }
});

test("what devices ask is read while the station's own reader is held", { timeout: 30_000 }, async () => {
  const { readers, args, started, open } = gated(2);
  const asked = [readers.read("chatRows", args(true), "en", { told: true })];
  try {
    await started(1);
    assert.equal(await readers.read("thread", args(false), "en"), "{}");
  } finally {
    await open(asked);
  }
});

for (const bulk of ["usage", "openJobs", "changed", "timeline", "aNewRead"]) test(`a chat can be read while ${bulk} reads are held`, { timeout: 30_000 }, async () => {
  const { readers, state, args, started, open } = gated(2);
  // Two bulk reads: one takes a reader, the other waits, leaving the second reader to the chat.
  const asked = [readers.read(bulk, args(true), "en"), readers.read(bulk, args(true), "en")];
  try {
    await started(1);
    assert.equal(await readers.read("thread", args(false), "en"), "{}");
    assert.equal(Atomics.load(state, 1) & 1, 1);
  } finally {
    const settled = await open(asked);
    assert.ok(settled.every((s) => s.status === "fulfilled"), "the waiting bulk read is taken once a reader is free");
  }
  assert.equal(Atomics.load(state, 0), 3);
});

// On ccvm (2026-11-03) a device's history sweep (POST /batch, four pages at once, 1 to 4 s each) held the sidebar, a
// session opened and the rest 10 s and more behind it.
test("a history brought on in the background is read after every other read, one page at a time, a reader left beside it", { timeout: 30_000 }, async () => {
  const { readers, state, args, started, open } = gated(2);
  const background = { background: true };
  const pages = [readers.read("timeline", args(true), "en", background), readers.read("timeline", args(true), "en", background)];
  const asked = [...pages];
  try {
    await started(1);
    // One page at a time: the other waits, and the sidebar is read beside it.
    assert.equal(await readers.read("chats", args(false), "en"), "{}");
    assert.equal(Atomics.load(state, 0), 2, "the second page still waits");
    // What a device asks meanwhile goes before the page waiting.
    asked.push(readers.read("session", args(true), "en"));
    await started(3);
    assert.equal(Atomics.load(state, 0), 3, "the session read, the page still waiting");
  } finally {
    const settled = await open(asked);
    assert.ok(settled.every((s) => s.status === "fulfilled"), "the page waiting is read once nothing else is");
  }
  assert.equal(Atomics.load(state, 0), 4);
});

test("a stretch of a history filled in brief is read behind the rest; one read whole is not", { timeout: 30_000 }, async () => {
  const { readers, state, args, started, open } = gated(2);
  const stretch = (whole: boolean) => ({ ...args(true), from: "0", to: "999", ...(whole ? {} : { brief: "1" }) });
  const asked = [readers.read("timeline", stretch(false), "en"), readers.read("timeline", stretch(false), "en")];
  try {
    await started(1);
    assert.equal(await readers.read("chats", args(false), "en"), "{}", "the sidebar beside the stretch, the other stretch waiting");
    assert.equal(Atomics.load(state, 0), 2);
    // A step opened: read whole, someone waits on it; it goes before the stretch waiting.
    asked.push(readers.read("timeline", stretch(true), "en"));
    await started(3);
  } finally {
    const settled = await open(asked);
    assert.ok(settled.every((s) => s.status === "fulfilled"));
  }
  assert.equal(Atomics.load(state, 0), 4);
});

test("the sidebar and a session's detail are read beside a slow bulk read, before another waiting", { timeout: 30_000 }, async () => {
  const { readers, state, args, started, open } = gated(2);
  // A slow usage read holds one reader, another waits for the one left.
  const asked = [readers.read("usage", args(true), "en"), readers.read("usage", args(true), "en")];
  try {
    await started(1);
    assert.equal(await readers.read("chats", args(false), "en"), "{}");
    assert.equal(await readers.read("session", args(false), "en"), "{}");
    assert.equal(Atomics.load(state, 0), 3, "the usage read waiting still waits");
  } finally {
    const settled = await open(asked);
    assert.ok(settled.every((s) => s.status === "fulfilled"));
  }
});

// On ccvm (2026-11-02) the log waited up to 98 s behind bulk reads, growing until the main connection wrote it itself.
test("the database's log is written into it before the reads waiting, by the reader left for a chat", { timeout: 30_000 }, async () => {
  const { readers, state, args, started, open } = gated(2);
  // Two bulk reads: one takes a reader, the other waits, and the one left is a chat's.
  const asked = [readers.read("usage", args(true), "en"), readers.read("usage", args(true), "en")];
  try {
    await started(1);
    assert.equal(await readers.read("checkpoint", args(false), "en"), "{}");
    assert.equal(Atomics.load(state, 0), 2, "the bulk read waiting still waits");
  } finally {
    const settled = await open(asked);
    assert.ok(settled.every((s) => s.status === "fulfilled"));
  }
});

test("a history waiting for old usage to be summarized does not hold a device reader", { timeout: 30_000 }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "reader-minute-"));
  const store = Store.open(join(dir, "stillfail.db"));
  const readers = new Readers(dir, 1, new URL("./reader-line-worker.mjs", import.meta.url));
  const state = new Int32Array(new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT * 3));
  store.db.exec("UPDATE usage_minute_all SET done = 0; BEGIN IMMEDIATE");
  // The write lock keeps the minute worker from finishing while the device reader stays available.
  const history = readers.read("usage", { state: state.buffer, hold: true, history: true, viewer: null }, "en");
  try {
    assert.equal(await readers.read("thread", { state: state.buffer, hold: false }, "en"), "{}");
    assert.equal(Atomics.load(state, 0), 1, "only the chat read entered a device reader");
  } finally {
    store.db.exec("COMMIT");
    Atomics.store(state, 2, 1);
    Atomics.notify(state, 2);
    await history;
    readers.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
