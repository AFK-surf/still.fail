// What a process has used so far on Linux (resources/watch.ts `Usage`), read from /proc as the user's own processes
// allow without root: CPU time (`stat`), private memory (`status`), bytes read from and written to disk (`io`).
// What each took in and sent out over the network is not counted per process on Linux without root (a network
// namespace's counters are its every process's), so the network is not read here.
import { readFile } from "node:fs/promises";
import type { Usage } from "./watch.ts";

/// `/proc/<pid>/stat`: user and system time (its 14th and 15th fields), in clock ticks. The name (2nd, in parentheses)
/// may hold spaces and parentheses of its own: the fields are counted from after its last `)`.
export function ticksOfStat(text: string): number | null {
  const end = text.lastIndexOf(")");
  if (end < 0) return null;
  // After the name: state (3rd), …, utime (14th), stime (15th).
  const f = text.slice(end + 1).trim().split(/\s+/);
  const user = Number(f[11]);
  const system = Number(f[12]);
  return Number.isFinite(user) && Number.isFinite(system) ? user + system : null;
}

const kB = (text: string, name: string): number | null => {
  const m = text.match(new RegExp(`^${name}:\\s*(\\d+)\\s*kB`, "m"));
  return m ? Number(m[1]) * 1024 : null;
};

/// `/proc/<pid>/status`: its memory as macOS's footprint counts it, what is its own (anonymous, resident or swapped
/// out), not the files it maps; its resident set where the kernel does not split it (before 4.5).
export function footprintOfStatus(text: string): number | null {
  const anon = kB(text, "RssAnon");
  if (anon !== null) return anon + (kB(text, "RssShmem") ?? 0) + (kB(text, "VmSwap") ?? 0);
  return kB(text, "VmRSS");
}

/// `/proc/<pid>/io`: bytes it had read from and written to the disk (not the page cache's).
export function diskOfIo(text: string): { diskRead: number; diskWritten: number } | null {
  const read = text.match(/^read_bytes:\s*(\d+)/m);
  const written = text.match(/^write_bytes:\s*(\d+)/m);
  return read && written ? { diskRead: Number(read[1]), diskWritten: Number(written[1]) } : null;
}

/// Each of `pids`' usage so far, none for one gone or not readable; `tick`: a clock tick's nanoseconds (USER_HZ, 100 a
/// second on every architecture Linux builds for today).
export async function linuxUsage(pids: readonly number[], read: (path: string) => Promise<string> = (path) => readFile(path, "utf8"), tick = 1e7): Promise<(Usage | null)[]> {
  return Promise.all(pids.map(async (pid) => {
    const at = `/proc/${pid}`;
    const [stat, status, io] = await Promise.all([read(`${at}/stat`).catch(() => null), read(`${at}/status`).catch(() => null), read(`${at}/io`).catch(() => null)]);
    const ticks = stat === null ? null : ticksOfStat(stat);
    if (ticks === null) return null;
    const disk = io === null ? null : diskOfIo(io);
    return { cpuNs: ticks * tick, footprint: (status === null ? null : footprintOfStatus(status)) ?? 0, ...(disk ?? {}) };
  }));
}
