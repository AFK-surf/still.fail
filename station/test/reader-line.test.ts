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

test("a read abandoned while waiting never reaches a reader", { timeout: 30_000 }, async () => {
  const { readers, state, args, started, open } = gated(1);
  const asked = [readers.read("thread", args(true), "en")];
  let settled: PromiseSettledResult<string>[];
  try {
    await started(1);
    const waiting = new AbortController();
    asked.push(readers.read("thread", args(false), "en", { signal: waiting.signal }));
    waiting.abort();
    const already = new AbortController();
    already.abort();
    asked.push(readers.read("thread", args(false), "en", { signal: already.signal }));
  } finally {
    settled = await open(asked);
  }
  assert.deepEqual(settled.map((s) => s.status), ["fulfilled", "rejected", "rejected"]);
  assert.equal(Atomics.load(state, 0), 1, "neither abandoned read started");
});

test("a read abandoned while running cannot return a late answer or hold the next read", { timeout: 30_000 }, async () => {
  const { readers, state, args, started, open } = gated(1);
  const controller = new AbortController();
  const asked = [readers.read("thread", args(true), "en", { signal: controller.signal })];
  let settled: PromiseSettledResult<string>[];
  try {
    await started(1);
    controller.abort();
    asked.push(readers.read("thread", args(false), "en"));
  } finally {
    settled = await open(asked);
  }
  assert.deepEqual(settled.map((s) => s.status), ["rejected", "fulfilled"]);
  assert.equal(Atomics.load(state, 0), 2, "the next read was answered");
});

// On a station (2026-11-02 15:41 UTC) a usage read held one reader for 97 s and sidebar updates the other: what was told of
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

// On a station (2026-11-03) a device's history sweep (POST /batch, four pages at once, 1 to 4 s each) held the sidebar, a
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

test("a history's pages are read by readers of their own: what devices ask is read beside them", { timeout: 30_000 }, async () => {
  // In line with what devices ask, the sidebar and a chat opened waited 20 s and more behind them on a station (2026-11-03).
  const { readers, state, args, started, open } = gated(2);
  const asked = [readers.read("timeline", args(true), "en"), readers.read("timeline", args(true), "en")];
  try {
    await started(2);
    // Both of the pages' readers held: a bulk read and a chat's are read all the same.
    asked.push(readers.read("usage", args(true), "en"));
    await started(3);
    assert.equal(await readers.read("thread", args(false), "en"), "{}");
  } finally {
    const settled = await open(asked);
    assert.ok(settled.every((s) => s.status === "fulfilled"));
  }
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

test("the sidebar, a session's detail and the jobs up are read beside a slow bulk read, before another waiting", { timeout: 30_000 }, async () => {
  const { readers, state, args, started, open } = gated(2);
  // A slow usage read holds one reader, another waits for the one left.
  const asked = [readers.read("usage", args(true), "en"), readers.read("usage", args(true), "en")];
  try {
    await started(1);
    assert.equal(await readers.read("chats", args(false), "en"), "{}");
    assert.equal(await readers.read("session", args(false), "en"), "{}");
    // So are the jobs up without their chats; with their chats, they are a bulk read (below).
    assert.equal(await readers.read("openJobs", { ...args(false), chats: false }, "en"), "{}");
    assert.equal(Atomics.load(state, 0), 4, "the usage read waiting still waits");
  } finally {
    const settled = await open(asked);
    assert.ok(settled.every((s) => s.status === "fulfilled"));
  }
});

// On a station (2026-11-02) the log waited up to 98 s behind bulk reads, growing until the main connection wrote it itself;
// then, going before them in their readers, it held the one left for a chat 53 s (2026-11-03).
test("the database's log is written into it by a reader of its own, while every device reader is held", { timeout: 30_000 }, async () => {
  const { readers, state, args, started, open } = gated(2);
  const asked = [readers.read("thread", args(true), "en"), readers.read("thread", args(true), "en"), readers.read("usage", args(true), "en")];
  try {
    await started(2);
    assert.equal(await readers.read("checkpoint", args(false), "en"), "{}");
    assert.equal(Atomics.load(state, 0), 3, "the device reads still held, the usage read still waiting");
  } finally {
    const settled = await open(asked);
    assert.ok(settled.every((s) => s.status === "fulfilled"));
  }
});

test("the year's history does not wait for old minute statistics nor hold a device reader", { timeout: 30_000 }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "reader-minute-"));
  const store = Store.open(join(dir, "stillfail.db"));
  const readers = new Readers(dir, 1);
  store.db.exec("UPDATE usage_minute_all SET done = 0");
  const history = readers.read("usage", { from: 0, to: 100, tz: 0, reading: false, history: true, viewer: null }, "en");
  try {
    await readers.read("checkpoint", {}, "en");
    const result = JSON.parse(await history);
    assert.deepEqual(result.history.days, []);
    assert.deepEqual(result.rows, []);
    assert.equal((store.db.prepare("SELECT done FROM usage_minute_all WHERE id = 1").get() as { done: number }).done, 0);
  } finally {
    readers.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("the readers of what devices ask and of what streams tell are kept idle, started before either is asked", { timeout: 30_000 }, async () => {
  const { wall } = await import("../src/ops/fibers.ts");
  const after = wall.after;
  const due: (() => void)[] = [];
  wall.after = (_ms, f) => (due.push(f), () => {});
  const { readers, state, args, open } = gated(2);
  try {
    readers.warm();
    const lines = readers as any;
    const [asked, told] = [lines.asked.slots[0], lines.told.slots[0]];
    assert.ok(asked !== undefined && told !== undefined, "started before anything is asked");
    await readers.read("thread", args(false), "en");
    assert.deepEqual([lines.asked.slots.length, lines.told.slots.length], [2, 1], "as many as each line has");
    // A minute idle, every timer due: every one of them is kept.
    for (const f of due.splice(0)) f();
    assert.deepEqual([lines.asked.slots.length, lines.told.slots.length], [2, 1]);
    await readers.read("thread", args(false), "en");
    assert.equal(lines.asked.slots[0], asked, "the same reader answers");
    assert.equal(Atomics.load(state, 0), 2);
  } finally {
    wall.after = after;
    await open([]);
  }
});

test("a background read waiting while its line rests is read once it has rested, a timer firing early or not", { timeout: 30_000 }, async () => {
  const { wall } = await import("../src/ops/fibers.ts");
  const [now, after] = [wall.now, wall.after];
  let clock = 1_000;
  // The line's wakes (a reader idle a minute going is not this test's).
  const due: (() => void)[] = [];
  wall.now = () => clock;
  wall.after = (ms, f) => (ms < 60_000 && due.push(f), () => {});
  const { readers, state, args, open } = gated(2);
  try {
    const background = { background: true };
    // The first page takes 50 ms (as the clock says): the line rests 50 ms before the second.
    const first = readers.read("timeline", args(false), "en", background);
    const second = readers.read("timeline", args(false), "en", background);
    clock += 50;
    await first;
    assert.equal(Atomics.load(state, 0), 1, "the second waits while the line rests");
    // A timer firing a moment before the rest is over: the line is looked at again later.
    clock += 49;
    for (const f of due.splice(0)) f();
    assert.equal(Atomics.load(state, 0), 1);
    assert.ok(due.length > 0, "looked at again once it has rested");
    clock += 1;
    for (const f of due.splice(0)) f();
    assert.equal(await second, "{}");
  } finally {
    [wall.now, wall.after] = [now, after];
    await open([]);
  }
});

test("a batch's chat reads, in the background, are read one at a time beside what a device asks, not as it is", { timeout: 30_000 }, async () => {
  const { readers, state, args, started, open } = gated(2);
  const background = { background: true };
  const asked = [readers.read("thread", args(true), "en", background), readers.read("thread", args(true), "en", background)];
  try {
    await started(1);
    // The second waits: one at a time, a reader left for a chat someone opens.
    assert.equal(await readers.read("thread", args(false), "en"), "{}");
    assert.equal(Atomics.load(state, 0), 2, "the second background read still waits");
  } finally {
    const settled = await open(asked);
    assert.ok(settled.every((s) => s.status === "fulfilled"));
  }
  assert.equal(Atomics.load(state, 0), 3);
});

test("a background session list keeps a reader free for an interactive read", { timeout: 30_000 }, async () => {
  const { readers, state, args, started, open } = gated(2);
  const asked = [readers.read("thread", args(true), "en")];
  try {
    await started(1);
    asked.push(readers.read("sessions", args(false), "en", { background: true }));
    assert.equal(await readers.read("thread", args(false), "en"), "{}");
    assert.equal(Atomics.load(state, 0), 2, "the background session list is still waiting");
  } finally { await open(asked); }
});
