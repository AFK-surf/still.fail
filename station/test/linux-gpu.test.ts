import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Gpus } from "../src/jobs/gpu.ts";
import { linuxGpus } from "../src/jobs/linux-gpu.ts";

test("Linux DRM cards keep discrete AMD measurements and skip integrated graphics", async () => {
  const root = await mkdtemp(join(tmpdir(), "stillfail-gpu-"));
  try {
    const drm = join(root, "drm");
    const devices = join(root, "devices");
    await mkdir(drm);
    await mkdir(devices);
    const card = async (n: number, slot: string, values: Record<string, string>) => {
      const device = join(devices, slot);
      const path = join(drm, `card${n}`);
      await mkdir(device);
      await mkdir(path);
      await symlink(device, join(path, "device"));
      await Promise.all(Object.entries(values).map(([key, value]) => writeFile(join(device, key), value)));
    };
    await card(0, "0000:01:00.0", { vendor: "0x1002", device: "0x744c", gpu_busy_percent: "73", mem_info_vram_total: "17179869184", mem_info_vram_used: "2147483648" });
    await card(1, "0000:00:02.0", { vendor: "0x8086" });
    // An AMD Granite Ridge integrated GPU next to the discrete card, as seen on a Ryzen station.
    await card(2, "0000:7a:00.0", { vendor: "0x1002", device: "0x13c0", mem_info_vram_total: "2147483648" });
    // A connector is not another card.
    await mkdir(join(drm, "card1-HDMI-A-1"));
    const lspci = "Slot:\t0000:01:00.0\nDevice:\tRadeon RX 7900\n\nSlot:\t0000:00:02.0\nDevice:\tIntegrated Graphics\n";
    const gpus = await linuxGpus(async (cmd) => cmd === "lspci" ? lspci : null, drm);
    assert.deepEqual(gpus, [
      { vendor: "0x1002", gpu: { name: "AMD Radeon RX 7900", busy: 0.73, memoryTotalBytes: 16 * 1024 ** 3, memoryUsedBytes: 2 * 1024 ** 3 } },
    ]);
    const withoutPci = await linuxGpus(async () => undefined, drm);
    assert.equal(withoutPci[0]?.gpu.name, "AMD GPU");
    assert.equal(withoutPci.length, 1);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("NVIDIA's richer readings replace its DRM entry while AMD GPUs remain", async () => {
  const linux = async () => [
    { vendor: "0x10de", gpu: { name: "NVIDIA GPU" } },
    { vendor: "0x1002", gpu: { name: "AMD GPU" } },
  ];
  const smi = new Gpus({ os: "linux", linux, run: async () => "NVIDIA RTX 4090, 24576, 1024, 20" });
  assert.deepEqual(await smi.read(), [
    { name: "NVIDIA RTX 4090", memoryTotalBytes: 24 * 1024 ** 3, memoryUsedBytes: 1024 ** 3, busy: 0.2 },
    { name: "AMD GPU" },
  ]);
  const noSmi = new Gpus({ os: "linux", linux, run: async () => undefined });
  assert.deepEqual(await noSmi.read(), [{ name: "NVIDIA GPU" }, { name: "AMD GPU" }]);
});
