import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mock, test } from "node:test";
import { Host } from "../src/api/host.ts";
import { wall } from "../src/ops/fibers.ts";
import { platform } from "../src/platform/index.ts";
import { hostInfo } from "../src/read/host.ts";
import { Readers } from "../src/read/pool.ts";
import { Store } from "../src/store/store.ts";

test("an isolated recording uses a fictional host sample", () => {
  const before = process.env.STILLFAIL_TEST_HOST;
  process.env.STILLFAIL_TEST_HOST = "1";
  try {
    const result = hostInfo("/Users/example/private/data", null);
    const info = result.info as { hostname: string; cpuModel: string; disk: { path: string }; cpuBusy: number | null };
    assert.equal(info.hostname, "test-station");
    assert.equal(info.cpuModel, "Test CPU");
    assert.equal(info.disk.path, "/test-station/data");
    assert.equal(info.cpuBusy, 0.25);
    assert.equal(result.needsTicks, false);
  } finally {
    if (before === undefined) delete process.env.STILLFAIL_TEST_HOST;
    else process.env.STILLFAIL_TEST_HOST = before;
  }
});

test("a host read takes the first CPU ticks without sleeping in the reader", () => {
  const waits = mock.method(Atomics, "wait", () => { throw new Error("the reader slept"); });
  let current: [number, number] | null = [10, 20];
  const ticks = mock.method(platform.host, "cpuTicks", () => current);
  try {
    const answer = hostInfo(tmpdir(), null);
    assert.equal((answer.info as { cpuBusy: number | null }).cpuBusy, null);
    assert.deepEqual(answer.seen?.ticks, [10, 20]);
    assert.equal(answer.needsTicks, true);
    const previous = { at: wall.now(), ticks: [4, 10] as [number, number] };
    const measured = hostInfo(tmpdir(), previous);
    assert.equal((measured.info as { cpuBusy: number | null }).cpuBusy, 0.6);
    assert.equal(measured.needsTicks, false);
    current = null;
    const unavailable = hostInfo(tmpdir(), previous);
    assert.equal((unavailable.info as { cpuBusy: number | null }).cpuBusy, null);
    assert.equal(unavailable.needsTicks, false, "an unavailable counter is not retried");
    assert.deepEqual(unavailable.seen, previous);
    assert.equal(waits.mock.calls.length, 0);
  } finally {
    ticks.mock.restore();
    waits.mock.restore();
  }
});

test("a host sample leaves its reader free while waiting for CPU ticks to move", async () => {
  const dir = mkdtempSync(join(tmpdir(), "host-reader-"));
  const readers = new Readers(dir, 1, new URL("./host-reader-worker.mjs", import.meta.url));
  const delays: number[] = [];
  const releases: (() => void)[] = [];
  let clock = 1_000;
  let open = false;
  const now = mock.method(wall, "now", () => clock);
  const sleep = mock.method(wall, "sleep", (ms: number) => new Promise<void>((resolve) => {
    delays.push(ms);
    const release = () => { clock += ms; resolve(); };
    if (open) release();
    else releases.push(release);
  }));
  const host = new Host(readers);
  const sample = host.sample("en");
  try {
    assert.equal(host.sample("en"), sample, "simultaneous requests share the sample");
    // The chat is queued after the first host read. Its answer proves that read released the only device reader.
    assert.equal(await readers.read("thread", {}, "en"), "{}");
    assert.deepEqual(delays, [500]);
    releases.shift()!();
    await Promise.resolve();
    assert.equal(await readers.read("thread", {}, "en"), "{}");
    assert.deepEqual(delays, [500, 100], "unchanged ticks are checked again without holding a reader");
    releases.shift()!();
    const info = await sample;
    assert.equal(info.cpuBusy, 0.5);
  } finally {
    open = true;
    for (const release of releases.splice(0)) release();
    await sample.catch(() => {});
    sleep.mock.restore();
    now.mock.restore();
    readers.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a host sample uses the actual reader's CPU operation", async () => {
  const dir = mkdtempSync(join(tmpdir(), "host-real-reader-"));
  const store = Store.open(join(dir, "stillfail.db"));
  const readers = new Readers(dir, 1);
  try {
    const first = JSON.parse(await readers.read("host", { seen: null }, "en"));
    assert.equal(typeof first.needsTicks, "boolean");
    const ticks = JSON.parse(await readers.read("hostTicks", {}, "en"));
    assert.ok(ticks === null || (Array.isArray(ticks) && ticks.length === 2));
    const info = await new Host(readers).sample("en");
    assert.equal(typeof info.hostname, "string");
    assert.ok(info.cpuBusy === null || (info.cpuBusy >= 0 && info.cpuBusy <= 1));
  } finally {
    readers.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
