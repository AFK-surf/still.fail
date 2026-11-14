// The machine as GET /host says it (api/host.ts `hostInfo`, `Host`), read on the main thread: a fictional sample for an
// isolated recording, the station's own memory under both names, the CPUs' ticks waited for without a reader.
import assert from "node:assert/strict";
import { tmpdir } from "node:os";
import { mock, test } from "node:test";
import { Host, hostInfo } from "../src/api/host.ts";
import { wall } from "../src/ops/fibers.ts";
import { platform } from "../src/platform/index.ts";

test("an isolated recording uses a fictional host sample", async () => {
  const before = process.env.STILLFAIL_TEST_HOST;
  process.env.STILLFAIL_TEST_HOST = "1";
  try {
    const result = await hostInfo("/Users/example/private/data", null);
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

test("a host read says this process's memory under both names, as clients from before the new one require the old", async () => {
  const info = (await hostInfo(tmpdir(), null)).info as { stationRssBytes: number; emberRssBytes: number; hostname: string; disk: { totalBytes: number } };
  assert.equal(typeof info.stationRssBytes, "number");
  assert.ok(info.stationRssBytes > 0, "the station's own memory is read");
  assert.equal(info.emberRssBytes, info.stationRssBytes);
  assert.equal(typeof info.hostname, "string");
  assert.ok(info.disk.totalBytes > 0);
});

test("an isolated recording does not read the machine's GPUs", async () => {
  const before = process.env.STILLFAIL_TEST_HOST;
  process.env.STILLFAIL_TEST_HOST = "1";
  let gpuReads = 0;
  const host = new Host("/private/data", { read: async () => { gpuReads++; return [{ name: "Private GPU", cores: 30, busy: 0.9 }]; } });
  try {
    const sample = await host.sample("en");
    assert.deepEqual(sample.gpus, [{ name: "Test GPU", cores: 4, busy: 0.25 }]);
    assert.equal(gpuReads, 0);
  } finally {
    if (before === undefined) delete process.env.STILLFAIL_TEST_HOST;
    else process.env.STILLFAIL_TEST_HOST = before;
  }
});

test("a host read takes the first CPU ticks without waiting for them to move", async () => {
  let current: [number, number] | null = [10, 20];
  const ticks = mock.method(platform.host, "cpuTicks", () => current);
  try {
    const answer = await hostInfo(tmpdir(), null);
    assert.equal((answer.info as { cpuBusy: number | null }).cpuBusy, null);
    assert.deepEqual(answer.seen?.ticks, [10, 20]);
    assert.equal(answer.needsTicks, true);
    const previous = { at: wall.now(), ticks: [4, 10] as [number, number] };
    const measured = await hostInfo(tmpdir(), previous);
    assert.equal((measured.info as { cpuBusy: number | null }).cpuBusy, 0.6);
    assert.equal(measured.needsTicks, false);
    current = null;
    const unavailable = await hostInfo(tmpdir(), previous);
    assert.equal((unavailable.info as { cpuBusy: number | null }).cpuBusy, null);
    assert.equal(unavailable.needsTicks, false, "an unavailable counter is not retried");
    assert.deepEqual(unavailable.seen, previous);
  } finally {
    ticks.mock.restore();
  }
});

test("a host sample waits for unmoved CPU ticks and looks at them again, shared by those who ask at once", async () => {
  const delays: number[] = [];
  let clock = 1_000;
  const now = mock.method(wall, "now", () => clock);
  const sleep = mock.method(wall, "sleep", async (ms: number) => { delays.push(ms); clock += ms; });
  const seen: [number, number][] = [[10, 20], [20, 40]];
  const ticks = mock.method(platform.host, "cpuTicks", () => seen.shift() ?? [20, 40]);
  const read = async () => ({ info: { checkedAt: 1_000, cpuBusy: null }, seen: { at: 1_000, ticks: [10, 20] as [number, number] }, needsTicks: true });
  const host = new Host("/data", { read: async () => null }, read);
  try {
    const sample = host.sample("en");
    assert.equal(host.sample("en"), sample, "simultaneous requests share the sample");
    const info = await sample;
    assert.deepEqual(delays, [500, 100], "unchanged ticks are looked at again after a moment");
    assert.equal(info.cpuBusy, 0.5);
  } finally {
    ticks.mock.restore();
    sleep.mock.restore();
    now.mock.restore();
  }
});

test("a host sample of this machine says how busy its CPUs are", async () => {
  const info = await new Host(tmpdir(), { read: async () => null }).sample("en");
  assert.equal(typeof info.hostname, "string");
  assert.ok(info.cpuBusy === null || (info.cpuBusy >= 0 && info.cpuBusy <= 1));
});
