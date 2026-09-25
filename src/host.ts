// What the machine a station runs on looks like: for people deciding where
// work goes and whether a station is struggling. Memory on macOS comes from
// vm_stat, since os.freemem() counts reclaimable cache as used; disk is the
// file system holding ember's data directory.
import { execFile } from "node:child_process";
import { statfs } from "node:fs/promises";
import os from "node:os";
import { promisify } from "node:util";

const run = promisify(execFile);

export interface HostInfo {
  hostname: string;
  /** e.g. "macOS 26.0" or "Linux 6.8". */
  os: string;
  arch: string;
  cpus: number;
  cpuModel: string;
  /** 1-minute load average divided by CPU count, 0–1+. */
  load: number;
  uptimeSec: number;
  memory: { totalBytes: number; usedBytes: number; swapUsedBytes: number | null };
  disk: { path: string; totalBytes: number; freeBytes: number };
  /** ember's own process. */
  emberRssBytes: number;
  checkedAt: number;
}

async function macosVersion(): Promise<string> {
  try {
    return `macOS ${(await run("sw_vers", ["-productVersion"], { timeout: 3000 })).stdout.trim()}`;
  } catch {
    return `macOS (Darwin ${os.release()})`;
  }
}

/** Memory in use the way Activity Monitor counts it: app, wired and compressed pages. */
async function memory(): Promise<HostInfo["memory"]> {
  const total = os.totalmem();
  if (process.platform === "darwin") {
    try {
      const { stdout } = await run("vm_stat", [], { timeout: 3000 });
      const page = Number(/page size of (\d+) bytes/.exec(stdout)?.[1] ?? 16384);
      const pages = (label: string) => Number(new RegExp(`${label}:\\s+(\\d+)`).exec(stdout)?.[1] ?? 0);
      const used = (pages("Anonymous pages") - pages("Pages purgeable") + pages("Pages wired down") + pages("Pages occupied by compressor")) * page;
      let swap: number | null = null;
      try {
        const s = (await run("sysctl", ["-n", "vm.swapusage"], { timeout: 3000 })).stdout;
        const m = /used = ([\d.]+)M/.exec(s);
        if (m) swap = Math.round(Number(m[1]) * 1024 * 1024);
      } catch {
        // swap unknown
      }
      return { totalBytes: total, usedBytes: Math.min(total, Math.max(0, used)), swapUsedBytes: swap };
    } catch {
      // fall through to the portable estimate
    }
  }
  if (process.platform === "linux") {
    try {
      const { readFile } = await import("node:fs/promises");
      const info = await readFile("/proc/meminfo", "utf8");
      const kb = (k: string) => Number(new RegExp(`${k}:\\s+(\\d+)`).exec(info)?.[1] ?? 0) * 1024;
      return { totalBytes: kb("MemTotal"), usedBytes: kb("MemTotal") - kb("MemAvailable"), swapUsedBytes: kb("SwapTotal") - kb("SwapFree") };
    } catch {
      // fall through
    }
  }
  return { totalBytes: total, usedBytes: total - os.freemem(), swapUsedBytes: null };
}

let cached: { value: HostInfo; at: number } | null = null;

/** The machine's state, at most ten seconds old. */
export async function hostInfo(dataDir: string): Promise<HostInfo> {
  if (cached && Date.now() - cached.at < 10_000) return cached.value;
  const [mem, fsStat, osName] = await Promise.all([
    memory(),
    statfs(dataDir).catch(() => null),
    process.platform === "darwin" ? macosVersion() : Promise.resolve(`${os.type()} ${os.release()}`),
  ]);
  const cpus = os.cpus();
  const value: HostInfo = {
    hostname: os.hostname().replace(/\.local$/, ""),
    os: osName,
    arch: os.arch(),
    cpus: cpus.length,
    cpuModel: cpus[0]?.model.trim() ?? "",
    load: Math.round((os.loadavg()[0]! / Math.max(1, cpus.length)) * 100) / 100,
    uptimeSec: Math.round(os.uptime()),
    memory: mem,
    disk: fsStat ? { path: dataDir, totalBytes: fsStat.blocks * fsStat.bsize, freeBytes: fsStat.bavail * fsStat.bsize } : { path: dataDir, totalBytes: 0, freeBytes: 0 },
    emberRssBytes: process.memoryUsage().rss,
    checkedAt: Date.now(),
  };
  cached = { value, at: Date.now() };
  return value;
}
