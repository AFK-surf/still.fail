// Linux DRM cards: AMD and NVIDIA when nvidia-smi cannot see it. A card's PCI name
// comes from lspci when available; AMD's sysfs files give utilization and dedicated VRAM without special privileges.
import { readdir, readFile, realpath } from "node:fs/promises";
import { basename, join } from "node:path";
import { amdIntegrated } from "./amd-integrated.ts";
import type { Gpu, Run } from "./gpu.ts";

export type LinuxGpu = { vendor: string; gpu: Gpu };

/// PCI slots and their device names from `lspci -D -vmm`. A missing PCI database or command is fine.
export function pciNames(text: string): Map<string, string> {
  const names = new Map<string, string>();
  for (const block of text.split(/\n\s*\n/)) {
    const fields = new Map(block.split("\n").flatMap((line) => {
      const i = line.indexOf(":\t");
      return i < 0 ? [] : [[line.slice(0, i), line.slice(i + 2).trim()] as const];
    }));
    const slot = fields.get("Slot");
    const device = fields.get("Device");
    if (slot && device) names.set(slot.toLowerCase(), device);
  }
  return names;
}

export async function linuxGpus(run: Run, root = "/sys/class/drm"): Promise<LinuxGpu[]> {
  const entries = (await readdir(root).catch(() => [])).filter((name) => /^card\d+$/.test(name)).sort((a, b) =>
    Number(a.slice(4)) - Number(b.slice(4)),
  );
  const read = (path: string) => readFile(path, "utf8").then((s) => s.trim()).catch(() => null);
  const cards = (await Promise.all(entries.map(async (entry) => {
    const path = join(root, entry, "device");
    const [vendor, device, pciId, busy, total, used] = await Promise.all([
      read(join(path, "vendor")), realpath(path).catch(() => null), read(join(path, "device")), read(join(path, "gpu_busy_percent")),
      read(join(path, "mem_info_vram_total")), read(join(path, "mem_info_vram_used")),
    ]);
    const id = vendor?.toLowerCase();
    return (id !== "0x1002" && id !== "0x10de") || (id === "0x1002" && amdIntegrated(pciId)) || device === null ? null : { vendor: id, slot: basename(device).toLowerCase(), busy, total, used };
  }))).filter((c) => c !== null);
  if (cards.length === 0) return [];
  const out = await run("lspci", ["-D", "-vmm"], 1500).catch(() => null);
  const names = pciNames(typeof out === "string" ? out : "");
  const number = (s: string | null) => s !== null && /^\d+$/.test(s) && Number.isSafeInteger(Number(s)) ? Number(s) : null;
  const seen = new Set<string>();
  return cards.flatMap((card) => {
    if (seen.has(card.slot)) return [];
    seen.add(card.slot);
    const vendor = card.vendor === "0x1002" ? "AMD" : "NVIDIA";
    const model = names.get(card.slot);
    const name = model ? [vendor, model].filter(Boolean).join(" ") : vendor ? `${vendor} GPU` : "GPU";
    const gpu: Gpu = { name };
    const busy = number(card.busy);
    const total = number(card.total);
    const used = number(card.used);
    if (busy !== null && busy <= 100) gpu.busy = busy / 100;
    if (total !== null && total > 0) gpu.memoryTotalBytes = total;
    if (used !== null) gpu.memoryUsedBytes = used;
    return [{ vendor: card.vendor, gpu }];
  });
}
