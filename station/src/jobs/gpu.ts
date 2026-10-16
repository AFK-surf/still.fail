// The machine's GPUs, for other stations choosing where work goes (station_list, load.ts): on Apple Silicon the
// chip and its GPU cores (ioreg, once: they do not change), NVIDIA's through nvidia-smi when it is there (how busy they
// are and their memory, read again at most every ten seconds); none otherwise. Never more than a moment's wait: a
// command that does not answer within GPU_WAIT_MS counts as none.
import { execFile } from "node:child_process";
import { wall } from "../ops/fibers.ts";
import { platform } from "../platform/index.ts";

export type Gpu = { name: string; cores?: number; memoryTotalBytes?: number; memoryUsedBytes?: number; busy?: number };

/// What a command printed; null when it failed or took longer than `ms`, undefined when there is no such command.
export type Run = (file: string, args: string[], ms: number) => Promise<string | null | undefined>;

const GPU_WAIT_MS = 1500;
const NVIDIA_KEEP_MS = 10_000;

const run: Run = (file, args, ms) =>
  new Promise((resolve) => {
    execFile(file, args, { timeout: ms, killSignal: "SIGKILL", maxBuffer: 1 << 20 }, (error, stdout) =>
      resolve(error ? ((error as NodeJS.ErrnoException).code === "ENOENT" ? undefined : null) : String(stdout)),
    );
  });

/// Apple Silicon's GPU from `ioreg -rc AGXAccelerator -d1`: `"model" = "Apple M2 Max"` and `"gpu-core-count" = 30`.
export function appleGpu(ioreg: string): Gpu | null {
  const name = /"model" = "([^"]+)"/.exec(ioreg)?.[1];
  const cores = /"gpu-core-count" = (\d+)/.exec(ioreg)?.[1];
  if (name === undefined && cores === undefined) return null;
  return { name: name ?? "Apple GPU", ...(cores === undefined ? {} : { cores: Number(cores) }) };
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

export class Gpus {
  private run: Run;
  private os: string;
  private arch: string;
  private now: () => number;
  private apple: Promise<Gpu | null> | null = null;
  /// nvidia-smi's last answer and when it was asked; `absent` once there was no such command (one installed under a
  /// running station is seen when it starts again).
  private nvidia: { at: number; gpus: Gpu[] } | null = null;
  private asking: Promise<Gpu[]> | null = null;
  private absent = false;

  constructor(options: { run?: Run; os?: string; arch?: string; now?: () => number } = {}) {
    this.run = options.run ?? run;
    this.os = options.os ?? platform.os;
    this.arch = options.arch ?? process.arch;
    this.now = options.now ?? wall.now;
  }

  /// The GPUs, or null when none is known. nvidia-smi is asked again once its answer is NVIDIA_KEEP_MS old; until the
  /// new one comes the last is given (the first is waited for, GPU_WAIT_MS at most).
  async read(): Promise<Gpu[] | null> {
    const gpus: Gpu[] = [];
    if (this.os === "macos" && this.arch === "arm64") {
      this.apple ??= this.run("ioreg", ["-rc", "AGXAccelerator", "-d1"], GPU_WAIT_MS).then((out) => (typeof out === "string" ? appleGpu(out) : null));
      const apple = await this.apple;
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
    return gpus.length === 0 ? null : gpus;
  }
}
