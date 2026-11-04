// The machine's GPUs, for other stations choosing where work goes (station_list, load.ts): on Apple Silicon the
// chip, GPU cores and utilization (ioreg), NVIDIA's through nvidia-smi when it is there (how busy they
// are and their memory, read again at most every ten seconds), Linux DRM cards (linux-gpu.ts), and AMD models from
// Windows' video controllers. Never more than a moment's wait: a
// command that does not answer within GPU_WAIT_MS counts as none. On Intel Macs, system_profiler can identify
// discrete AMD and NVIDIA GPUs even where no utilization reader is installed.
import { execFile } from "node:child_process";
import { wall } from "../ops/fibers.ts";
import { platform } from "../platform/index.ts";
import { amdIntegrated } from "./amd-integrated.ts";
import { linuxGpus, type LinuxGpu } from "./linux-gpu.ts";

export type Gpu = { name: string; cores?: number; memoryTotalBytes?: number; memoryUsedBytes?: number; busy?: number };

/// What a command printed; null when it failed or took longer than `ms`, undefined when there is no such command.
export type Run = (file: string, args: string[], ms: number) => Promise<string | null | undefined>;

const GPU_WAIT_MS = 1500;
const NVIDIA_KEEP_MS = 10_000;
const MAC_DISPLAYS_KEEP_MS = 60_000;
const WINDOWS_AMD = "(Get-CimInstance -ClassName Win32_VideoController | Where-Object { $_.PNPDeviceID -like 'PCI\\VEN_1002*' } | Select-Object Name,PNPDeviceID) | ConvertTo-Json -Compress";

const run: Run = (file, args, ms) =>
  new Promise((resolve) => {
    execFile(file, args, { timeout: ms, killSignal: "SIGKILL", maxBuffer: 1 << 20 }, (error, stdout) =>
      resolve(error ? ((error as NodeJS.ErrnoException).code === "ENOENT" ? undefined : null) : String(stdout)),
    );
  });

/// Apple Silicon's GPU from `ioreg -rc AGXAccelerator -d1`, including its device utilization where reported.
export function appleGpu(ioreg: string): Gpu | null {
  const name = /"model" = "([^"]+)"/.exec(ioreg)?.[1];
  const cores = /"gpu-core-count" = (\d+)/.exec(ioreg)?.[1];
  const busy = /"Device Utilization %"\s*=\s*(\d+)/.exec(ioreg)?.[1];
  if (name === undefined && cores === undefined && busy === undefined) return null;
  const percent = busy === undefined ? null : Number(busy);
  return { name: name ?? "Apple GPU", ...(cores === undefined ? {} : { cores: Number(cores) }), ...(percent !== null && percent <= 100 ? { busy: percent / 100 } : {}) };
}

/// NVIDIA's GPUs from `nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu --format=csv,noheader,nounits`:
/// a line each, memory in MiB, how busy in percent ("[N/A]" where it cannot say).
export function nvidiaGpus(csv: string): Gpu[] {
  const gpus: Gpu[] = [];
  for (const line of csv.split("\n")) {
    const [name, total, used, busy] = line.split(",").map((p) => p.trim());
    if (!name) continue;
    const num = (v: string | undefined) => (v !== undefined && /^\d+(\.\d+)?$/.test(v) ? Number(v) : null);
    const gpu: Gpu = { name };
    if (num(total) !== null) gpu.memoryTotalBytes = num(total)! * 1024 * 1024;
    if (num(used) !== null) gpu.memoryUsedBytes = num(used)! * 1024 * 1024;
    if (num(busy) !== null) gpu.busy = Math.round(num(busy)!) / 100;
    gpus.push(gpu);
  }
  return gpus;
}

/// Windows PowerShell 5.1 returns one controller as an object and several as an array. Empty or unreadable is none.
export function windowsAmdGpus(json: string): Gpu[] {
  try {
    const v: unknown = JSON.parse(json);
    const controllers = Array.isArray(v) ? v : [v];
    return controllers.flatMap((controller: unknown) => {
      if (typeof controller !== "object" || controller === null) return [];
      const c = controller as Record<string, unknown>;
      if (typeof c.Name !== "string" || c.Name.trim() === "") return [];
      const id = typeof c.PNPDeviceID === "string" ? /(?:^|&)DEV_([0-9a-f]{4})(?:&|$)/i.exec(c.PNPDeviceID)?.[1] : undefined;
      return amdIntegrated(id) ? [] : [{ name: c.Name.trim() }];
    });
  } catch {
    return [];
  }
}

/// Intel Macs can have an AMD or NVIDIA PCIe GPU alongside Intel's integrated graphics. `system_profiler` says the
/// discrete cards' models and total VRAM, but not their current use; an unknown reading stays unknown.
export function macDiscreteGpus(json: string): { vendor: "amd" | "nvidia"; gpu: Gpu }[] {
  try {
    const value: unknown = JSON.parse(json);
    if (typeof value !== "object" || value === null || !("SPDisplaysDataType" in value) || !Array.isArray(value.SPDisplaysDataType)) return [];
    return value.SPDisplaysDataType.flatMap((entry: unknown) => {
      if (typeof entry !== "object" || entry === null) return [];
      const e = entry as Record<string, unknown>;
      if (e.sppci_bus !== "spdisplays_pcie_device" || typeof e.spdisplays_vendor !== "string") return [];
      const vendor = /(?:^|[_\W])(?:amd|ati)(?:$|[_\W])/i.test(e.spdisplays_vendor) ? "amd" : /(?:^|[_\W])nvidia(?:$|[_\W])/i.test(e.spdisplays_vendor) ? "nvidia" : null;
      if (vendor === null) return [];
      const name = typeof e.sppci_model === "string" && e.sppci_model.trim() ? e.sppci_model.trim() : `${vendor === "amd" ? "AMD" : "NVIDIA"} GPU`;
      const gpu: Gpu = { name };
      const vram = e.spdisplays_vram ?? e._spdisplays_vram;
      const memory = typeof vram === "string" ? /^\s*(\d+(?:\.\d+)?)\s*(GB|MB)\s*$/i.exec(vram) : null;
      if (memory) gpu.memoryTotalBytes = Number(memory[1]) * (memory[2]!.toUpperCase() === "GB" ? 1024 ** 3 : 1024 ** 2);
      return [{ vendor, gpu }];
    });
  } catch {
    return [];
  }
}

export class Gpus {
  private run: Run;
  private os: string;
  private arch: string;
  private now: () => number;
  private apple: { at: number; gpu: Gpu | null } | null = null;
  private appleAsking: Promise<Gpu | null> | null = null;
  /// nvidia-smi's last answer and when it was asked; `absent` once there was no such command (one installed under a
  /// running station is seen when it starts again).
  private nvidia: { at: number; gpus: Gpu[] } | null = null;
  private asking: Promise<Gpu[]> | null = null;
  private absent = false;
  private linuxRead: () => Promise<LinuxGpu[]>;
  private linux: { at: number; cards: LinuxGpu[] } | null = null;
  private linuxAsking: Promise<LinuxGpu[]> | null = null;
  private windows: { at: number; gpus: Gpu[] } | null = null;
  private windowsAsking: Promise<Gpu[]> | null = null;
  private macDisplays: { at: number; cards: ReturnType<typeof macDiscreteGpus> } | null = null;
  private macDisplaysAsking: Promise<ReturnType<typeof macDiscreteGpus>> | null = null;

  constructor(options: { run?: Run; os?: string; arch?: string; now?: () => number; linux?: () => Promise<LinuxGpu[]> } = {}) {
    this.run = options.run ?? run;
    this.os = options.os ?? platform.os;
    this.arch = options.arch ?? process.arch;
    this.now = options.now ?? wall.now;
    this.linuxRead = options.linux ?? (() => linuxGpus(this.run));
  }

  /// The GPUs, or null when none is known. nvidia-smi is asked again once its answer is NVIDIA_KEEP_MS old; until the
  /// new one comes the last is given (the first is waited for, GPU_WAIT_MS at most).
  async read(): Promise<Gpu[] | null> {
    const gpus: Gpu[] = [];
    if (this.os === "macos" && this.arch === "x64" && this.macDisplaysAsking === null && (this.macDisplays === null || this.now() - this.macDisplays.at >= MAC_DISPLAYS_KEEP_MS)) {
      const at = this.now();
      this.macDisplaysAsking = this.run("system_profiler", ["SPDisplaysDataType", "-json"], GPU_WAIT_MS).catch(() => null).then((out) => {
        const cards = typeof out === "string" ? macDiscreteGpus(out) : [];
        this.macDisplays = { at, cards };
        return cards;
      }).finally(() => (this.macDisplaysAsking = null));
    }
    if (this.os === "linux" && this.linuxAsking === null && (this.linux === null || this.now() - this.linux.at >= NVIDIA_KEEP_MS)) {
      const at = this.now();
      this.linuxAsking = this.linuxRead().catch(() => []).then((cards) => {
        this.linux = { at, cards };
        return cards;
      }).finally(() => (this.linuxAsking = null));
    }
    if (this.os === "windows" && this.windowsAsking === null && (this.windows === null || this.now() - this.windows.at >= NVIDIA_KEEP_MS)) {
      const at = this.now();
      this.windowsAsking = this.run("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", WINDOWS_AMD], GPU_WAIT_MS).catch(() => null).then((out) => {
        const found = typeof out === "string" ? windowsAmdGpus(out) : [];
        this.windows = { at, gpus: found };
        return found;
      }).finally(() => (this.windowsAsking = null));
    }
    if (this.os === "macos" && this.arch === "arm64") {
      if (this.appleAsking === null && (this.apple === null || this.now() - this.apple.at >= NVIDIA_KEEP_MS)) {
        const at = this.now();
        this.appleAsking = this.run("ioreg", ["-rc", "AGXAccelerator", "-d1"], GPU_WAIT_MS).catch(() => null).then((out) => {
          const gpu = typeof out === "string" ? appleGpu(out) : null;
          this.apple = { at, gpu };
          return gpu;
        }).finally(() => (this.appleAsking = null));
      }
      const apple = this.apple?.gpu ?? (this.appleAsking ? await this.appleAsking : null);
      if (apple !== null) gpus.push(apple);
    }
    if (!this.absent) {
      if (this.asking === null && (this.nvidia === null || this.now() - this.nvidia.at >= NVIDIA_KEEP_MS)) {
        const at = this.now();
        this.asking = this.run("nvidia-smi", ["--query-gpu=name,memory.total,memory.used,utilization.gpu", "--format=csv,noheader,nounits"], GPU_WAIT_MS)
          .then((out) => {
            if (out === undefined) this.absent = true;
            const found = typeof out === "string" ? nvidiaGpus(out) : [];
            this.nvidia = { at, gpus: found };
            return found;
          })
          .finally(() => (this.asking = null));
      }
      gpus.push(...(this.nvidia?.gpus ?? (this.asking ? await this.asking : [])));
    }
    if (this.os === "linux") {
      const cards = this.linux?.cards ?? (this.linuxAsking ? await this.linuxAsking : []);
      // nvidia-smi has richer readings and sees headless cards; keep its entries in preference to DRM's copies.
      const hasNvidia = gpus.length > 0;
      gpus.push(...cards.filter((c) => c.vendor !== "0x10de" || !hasNvidia).map((c) => c.gpu));
    }
    if (this.os === "macos" && this.arch === "x64") {
      const cards = this.macDisplays?.cards ?? (this.macDisplaysAsking ? await this.macDisplaysAsking : []);
      const hasNvidia = gpus.length > 0;
      gpus.push(...cards.filter((c) => c.vendor !== "nvidia" || !hasNvidia).map((c) => c.gpu));
    }
    if (this.os === "windows") gpus.push(...(this.windows?.gpus ?? (this.windowsAsking ? await this.windowsAsking : [])));
    return gpus.length === 0 ? null : gpus;
  }
}
