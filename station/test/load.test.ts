// What a station tells the others of how busy it is (jobs/load.ts): the CPUs over about a minute (api/host.ts
// CpuWindow), the GPUs (jobs/gpu.ts) from what the commands print, and the line station_list says, all on fake
// measurements and a clock of the test's.
import assert from "node:assert/strict";
import { test } from "node:test";
import { CPU_EVERY_MS, CPU_SPAN_MS, CpuWindow } from "../src/api/host.ts";
import { Gpus, type Run, appleGpu, nvidiaGpus } from "../src/jobs/gpu.ts";
import { Net, OLDER, detailed, measure, summary } from "../src/jobs/load.ts";

test("the CPUs' recent business is an average over about the last minute, not the moment's", () => {
  const w = new CpuWindow();
  assert.equal(w.busy(0, [0, 0]), null, "nothing noted yet");
  w.note(0, [0, 0]);
  assert.equal(w.busy(500, [10, 20]), null, "under a second: nothing to say yet");
  // Busy at 100% for the first 30 s, idle since: over the minute, half.
  let busy = 0;
  let total = 0;
  for (let at = CPU_EVERY_MS; at <= CPU_SPAN_MS; at += CPU_EVERY_MS) {
    total += CPU_EVERY_MS;
    if (at <= 30_000) busy += CPU_EVERY_MS;
    w.note(at, [busy, total]);
  }
  assert.deepEqual(w.busy(CPU_SPAN_MS, [busy, total]), { busy: 0.5, seconds: 60 });
  // Another minute idle: the busy half has left the window.
  for (let at = CPU_SPAN_MS + CPU_EVERY_MS; at <= 2 * CPU_SPAN_MS; at += CPU_EVERY_MS) {
    total += CPU_EVERY_MS;
    w.note(at, [busy, total]);
  }
  assert.deepEqual(w.busy(2 * CPU_SPAN_MS, [busy, total]), { busy: 0, seconds: 60 });
  assert.equal(w.latest()?.at, 2 * CPU_SPAN_MS);
  // Unreadable ticks are not noted.
  w.note(2 * CPU_SPAN_MS + 1, null);
  assert.equal(w.latest()?.at, 2 * CPU_SPAN_MS);
  assert.equal(w.busy(2 * CPU_SPAN_MS + 5000, null), null);
});

test("GPUs: Apple's chip and cores once, NVIDIA's as nvidia-smi says them, kept ten seconds; none where there are none", async () => {
  const ioreg = `+-o AGXAcceleratorG14X  <class AGXAcceleratorG14X>\n    {\n      "model" = "Apple M2 Max"\n      "gpu-core-count" = 30\n    }\n`;
  assert.deepEqual(appleGpu(ioreg), { name: "Apple M2 Max", cores: 30 });
  assert.equal(appleGpu("nothing"), null);
  assert.deepEqual(nvidiaGpus("NVIDIA GeForce RTX 4090, 24564, 1024, 37\nTesla T4, 15360, [N/A], [N/A]\n"), [
    { name: "NVIDIA GeForce RTX 4090", memoryTotalBytes: 24564 * 1024 * 1024, memoryUsedBytes: 1024 * 1024 * 1024, busy: 0.37 },
    { name: "Tesla T4", memoryTotalBytes: 15360 * 1024 * 1024 },
  ]);

  let now = 0;
  const asked: string[] = [];
  let smi = "NVIDIA A10, 23028, 0, 0";
  let answer: (() => void) | null = null;
  const run: Run = async (file) => {
    asked.push(file);
    if (file === "ioreg") return ioreg;
    if (asked.filter((f) => f === "nvidia-smi").length === 3) await new Promise<void>((r) => (answer = r));
    return smi;
  };
  const mac = new Gpus({ run, os: "macos", arch: "arm64", now: () => now });
  assert.deepEqual(await mac.read(), [{ name: "Apple M2 Max", cores: 30 }, { name: "NVIDIA A10", memoryTotalBytes: 23028 * 1024 * 1024, memoryUsedBytes: 0, busy: 0 }]);
  now = 9_999;
  smi = "NVIDIA A10, 23028, 1024, 50";
  await mac.read();
  assert.deepEqual(asked, ["ioreg", "nvidia-smi"], "ioreg once; nvidia-smi's answer kept ten seconds");
  // Ten seconds old: given once more while it is asked again, the new answer after.
  now = 10_000;
  assert.equal((await mac.read())![1]!.busy, 0);
  await new Promise((r) => setImmediate(r));
  assert.equal((await mac.read())![1]!.busy, 0.5);
  // A slow answer: the last one is given meanwhile, not waited for, and asked for once.
  now = 20_000;
  smi = "NVIDIA A10, 23028, 2048, 90";
  assert.equal((await mac.read())![1]!.busy, 0.5);
  assert.equal((await mac.read())![1]!.busy, 0.5);
  assert.equal(asked.filter((f) => f === "nvidia-smi").length, 3);
  answer!();
  await new Promise((r) => setImmediate(r));
  assert.equal((await mac.read())![1]!.busy, 0.9);

  // No nvidia-smi: asked once, never again; on Linux without one, none at all.
  const linuxAsked: string[] = [];
  const linux = new Gpus({ run: async (file) => (linuxAsked.push(file), undefined), os: "linux", arch: "x64", now: () => now });
  assert.equal(await linux.read(), null);
  now = 60_000;
  assert.equal(await linux.read(), null);
  assert.deepEqual(linuxAsked, ["nvidia-smi"]);
  // One that fails or does not answer in time is none, asked again later.
  const failing = new Gpus({ run: async () => null, os: "linux", arch: "x64", now: () => now });
  assert.equal(await failing.read(), null);
});

test("measured from the host page's sample, and said in one line; what a station leaves out is left out", async () => {
  const net = new Net();
  assert.equal(net.seen(), null, "off the mesh");
  const off = net.attach(() => "https://relay.example/");
  net.pinged("https://relay.example", 23.4);
  const sample = {
    os: "Ubuntu 24.04", arch: "x64", cpus: 4, cpuModel: "AMD EPYC", load: 0.5, loadAvg: [2, 1, 0.5], cpuBusy: 0.97,
    memory: { totalBytes: 8 * 1024 ** 3, usedBytes: 6.5 * 1024 ** 3, swapUsedBytes: 0 }, disk: { path: "/srv/st", totalBytes: 80 * 1024 ** 3, freeBytes: 3.25 * 1024 ** 3 }, checkedAt: 7,
  };
  let recent: { busy: number; seconds: number } | null = { busy: 0.25, seconds: 75 };
  const parts = {
    host: { sample: async () => sample, recentBusy: () => recent },
    gpus: { read: async () => null },
    running: () => ({ remoteTasks: 0, jobs: 1, services: 1, turns: 3 }),
    relay: () => net.seen(),
  };
  const load = await measure(parts);
  assert.deepEqual(load, {
    os: "Ubuntu 24.04", arch: "x64", cpus: 4, cpuModel: "AMD EPYC", cpuBusy: { share: 0.25, seconds: 75 }, loadAvg: [2, 1, 0.5],
    memory: { totalBytes: 8 * 1024 ** 3, availableBytes: 1.5 * 1024 ** 3 }, disk: { path: "/srv/st", totalBytes: 80 * 1024 ** 3, freeBytes: 3.25 * 1024 ** 3 },
    gpus: null, running: { remoteTasks: 0, jobs: 1, services: 1, turns: 3 }, relay: { home: "https://relay.example/", ping: { relay: "https://relay.example", ms: 23 } }, checkedAt: 7,
  });
  assert.equal(
    summary(load),
    "x64 Ubuntu 24.04, 4 cores (AMD EPYC); CPU 25% busy over the last 75 s, load 2 / 1 / 0.5 (1 / 5 / 15 min); memory 1.5 GiB of 8 GiB free, disk 3.3 GiB of 80 GiB free; running 0 remote tasks, 1 job, 1 service, 3 agent turns; relay ping 23 ms",
  );
  // Before the CPUs have been followed a while: the host page's own look.
  recent = null;
  assert.deepEqual((await measure(parts)).cpuBusy, { share: 0.97, seconds: null });
  off();
  assert.equal(net.seen(), null);
  // An NVIDIA GPU; a station that says less (Windows: no load average; a newer one's own fields) is said as far as it goes.
  assert.equal(
    summary({ os: "Windows 11", arch: "x64", cpus: 16, cpuModel: "", cpuBusy: { share: 0.1, seconds: null }, loadAvg: null, gpus: [{ name: "NVIDIA RTX 4090", memoryTotalBytes: 24 * 1024 ** 3, memoryUsedBytes: 4 * 1024 ** 3, busy: 0.05 }], extra: 1 }),
    "x64 Windows 11, 16 cores, GPU NVIDIA RTX 4090 (20 GiB of 24 GiB free, 5% busy); CPU 10% busy just now",
  );
  assert.equal(summary(null), OLDER);
  assert.equal(summary({ unavailable: "not measured within 1 s" }), "unknown (not measured within 1 s)");
  assert.deepEqual(detailed({ protocol: 1, tasks: true }), { protocol: 1, tasks: true, load: OLDER });
});

test("unknown memory is never reported as all available", async () => {
  const samples = [
    { totalBytes: 64 * 1024 ** 3 },
    { totalBytes: 64 * 1024 ** 3, usedBytes: 0, known: false },
    { totalBytes: 64 * 1024 ** 3, usedBytes: 65 * 1024 ** 3 },
    { totalBytes: 0, usedBytes: 0 },
  ];
  for (const memory of samples) {
    const load = await measure({
      host: { sample: async () => ({ memory }), recentBusy: () => null },
      gpus: { read: async () => null },
      running: () => ({ remoteTasks: 0, jobs: 0, services: 0, turns: 0 }),
      relay: () => null,
    });
    assert.equal(load.memory.availableBytes, null);
    assert.equal(load.cpus, null);
    assert.equal(load.disk.totalBytes, null);
    assert.equal(load.disk.freeBytes, null);
    assert.equal(load.checkedAt, null);
    assert.doesNotMatch(summary(load), /memory .* free/);
  }
});
