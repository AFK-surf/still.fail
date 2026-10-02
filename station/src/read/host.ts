// What the machine a station runs on looks like (GET /host), ported from mesh/app/src/host.rs: for people deciding
// where work goes and whether a station is struggling. Memory on macOS comes from vm_stat (what Activity Monitor counts
// as used: app, wired and compressed pages, not reclaimable cache); disk is the file system holding the station's data
// directory. It runs commands and may wait a moment for the CPUs, so it runs in a reader thread; what the Rust keeps
// between looks (the ticks last seen, the answer of the last ten seconds) the main thread keeps (api/routes/usage.ts)
// and hands in, as readers come and go.
import { spawnSync } from "node:child_process";
import { readFileSync, statfsSync } from "node:fs";
import { availableParallelism, cpus as cpuList, hostname as osHostname, loadavg, release, type as osType } from "node:os";

const MACOS = process.platform === "darwin";

/// CPU time since boot, all CPUs together: (busy, total).
export type Ticks = [busy: number, total: number];
/// The ticks last seen, and when (host.rs TICKS).
export type Seen = { at: number; ticks: Ticks } | null;

/// Rust's str::trim (char::is_whitespace).
const WS = "\\t\\n\\v\\f\\r \\u0085\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000";
const TRIM = new RegExp(`^[${WS}]+|[${WS}]+$`, "g");
const trim = (s: string) => s.replace(TRIM, "");
const SPLIT = new RegExp(`[${WS}]+`);
const firstWord = (s: string) => s.split(SPLIT).find((w) => w !== "") ?? "";

/// str::parse::<u64>: digits (a `+` before them at most); none otherwise.
const parseU64 = (s: string): number | null => (/^\+?[0-9]+$/.test(s) ? Number(s) : null);
/// str::parse::<f64> for what these commands write (no inf or nan here).
const parseF64 = (s: string): number | null => (/^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$/.test(s) ? Number(s) : null);

/// output: a command's output, trimmed, or none when it cannot be run (within a few seconds) or fails.
function output(command: string, args: string[]): string | null {
  const out = spawnSync(command, args, { timeout: 3000, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  return out.status === 0 && typeof out.stdout === "string" ? trim(out.stdout) : null;
}

/// field: the number after `label:` in `text`, e.g. vm_stat's and /proc/meminfo's lines (0 when it does not read).
export function field(text: string, label: string): number {
  for (const line of text.split("\n")) {
    if (!line.startsWith(`${label}:`)) continue;
    return parseU64(firstWord(trim(line.slice(label.length + 1)).replace(/\.+$/, ""))) ?? 0;
  }
  return 0;
}

/// hostname, without a `.local`.
function hostname(): string {
  const name = osHostname();
  return name.endsWith(".local") ? name.slice(0, -".local".length) : name;
}

/// cpu_ticks: on macOS the CPUs' user, system, idle and nice time (os.cpus, from the same counters as Mach's
/// HOST_CPU_LOAD_INFO, in ms rather than ticks: the share is the same).
function cpuTicks(): Ticks | null {
  if (MACOS) {
    const all = cpuList();
    if (all.length === 0) return null;
    let [busy, total] = [0, 0];
    for (const { times: t } of all) {
      busy += t.user + t.sys + t.nice;
      total += t.user + t.sys + t.idle + t.nice;
    }
    return [busy, total];
  }
  try {
    return procStatTicks(readFileSync("/proc/stat", "utf8"));
  } catch {
    return null;
  }
}

/// proc_stat_ticks: CPU time from /proc/stat's first line; waiting on disks (iowait) counts as idle, as top counts it.
export function procStatTicks(stat: string): Ticks | null {
  const line = stat.split("\n").find((l) => l.startsWith("cpu "));
  if (line === undefined) return null;
  const v = splitWords(line).slice(1, 9).map(parseU64).filter((n): n is number => n !== null);
  if (v.length < 4) return null;
  const total = v.reduce((a, b) => a + b, 0);
  const idle = v[3]! + (v[4] ?? 0);
  return [total - idle, total];
}
const splitWords = (s: string) => s.split(SPLIT).filter((w) => w !== "");

/// A real sleep, in a reader thread.
const sleep = (ms: number) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

/// cpu_busy: how busy the CPUs have been since the last look, if that was within a minute; otherwise over the next
/// moment. With the ticks seen now, for the next look.
function cpuBusy(last: Seen): [busy: number | null, seen: Seen] {
  const share = ([b0, t0]: Ticks, [b1, t1]: Ticks) => (t1 > t0 ? Math.min(Math.max(Math.max(b1 - b0, 0) / (t1 - t0), 0), 1) : null);
  const before = last !== null && Date.now() - last.at < 60_000 ? last.ticks : null;
  let now = cpuTicks();
  if (now === null) return [null, last];
  let busy = before === null ? null : share(before, now);
  if (busy === null) {
    // macOS updates the ticks only now and then (seen unchanged after a real 505 ms, 2026-09-30), so it looks again,
    // up to 2 s, until they have moved.
    const then = now;
    const start = Date.now();
    sleep(500);
    let again: Ticks | null;
    for (;;) {
      again = cpuTicks();
      if (again === null || again[1] > then[1] || Date.now() - start >= 2000) break;
      sleep(100);
    }
    if (again === null) return [null, last];
    now = again;
    busy = share(then, now);
    if (busy === null) return [null, last];
  }
  return [Math.round(busy * 100) / 100, { at: Date.now(), ticks: now }];
}

/// disk: the file system holding `path`: its size and what is free for the station.
function disk(path: string) {
  try {
    const st = statfsSync(path);
    return { path, totalBytes: st.blocks * st.bsize, freeBytes: st.bavail * st.bsize };
  } catch {
    return { path, totalBytes: 0, freeBytes: 0 };
  }
}

/// memory: total, used (on macOS as Activity Monitor counts it), and swap used.
function memory() {
  if (MACOS) {
    const total = parseU64(output("sysctl", ["-n", "hw.memsize"]) ?? "") ?? 0;
    const vm = output("vm_stat", []);
    if (vm !== null) {
      const after = vm.split("page size of ")[1];
      const page = (after !== undefined ? parseU64(firstWord(after)) : null) ?? 16384;
      const pages = (label: string) => field(vm, label);
      const used = Math.max(pages("Anonymous pages") - pages("Pages purgeable") + pages("Pages wired down") + pages("Pages occupied by compressor"), 0) * page;
      const swapText = output("sysctl", ["-n", "vm.swapusage"]);
      const usedText = swapText?.split("used = ")[1]?.split("M")[0];
      const swapMb = usedText === undefined ? null : parseF64(usedText);
      return { totalBytes: total, usedBytes: Math.min(used, total), swapUsedBytes: swapMb === null ? null : Math.round(swapMb * 1024 * 1024) };
    }
    return { totalBytes: total, usedBytes: 0, swapUsedBytes: null };
  }
  let info = "";
  try {
    info = readFileSync("/proc/meminfo", "utf8");
  } catch {
    // None: zeros.
  }
  const kb = (k: string) => field(info, k) * 1024;
  return {
    totalBytes: kb("MemTotal"),
    usedBytes: Math.max(kb("MemTotal") - kb("MemAvailable"), 0),
    swapUsedBytes: Math.max(kb("SwapTotal") - kb("SwapFree"), 0),
  };
}

function cpuModel(): string {
  if (MACOS) return output("sysctl", ["-n", "machdep.cpu.brand_string"]) ?? "";
  let info = "";
  try {
    info = readFileSync("/proc/cpuinfo", "utf8");
  } catch {
    // None: empty.
  }
  for (const l of info.split("\n")) {
    if (!l.startsWith("model name")) continue;
    const colon = l.indexOf(":", "model name".length);
    if (colon >= 0) return trim(l.slice(colon + 1));
  }
  return "";
}

function uptimeSec(): number {
  if (MACOS) {
    // "{ sec = 1790000000, usec = 0 } ..."
    const text = output("sysctl", ["-n", "kern.boottime"]);
    const sec = text?.split("sec = ")[1]?.split(",")[0];
    const boot = sec === undefined ? null : /^[+-]?[0-9]+$/.test(trim(sec)) ? Number(trim(sec)) : null;
    return boot === null ? 0 : Math.max(Math.trunc(Date.now() / 1000) - boot, 0);
  }
  try {
    const s = parseF64(firstWord(readFileSync("/proc/uptime", "utf8")));
    return s === null ? 0 : Math.round(s);
  } catch {
    return 0;
  }
}

function osName(): string {
  if (MACOS) {
    const version = output("sw_vers", ["-productVersion"]);
    return version !== null ? `macOS ${version}` : `macOS (Darwin ${release()})`;
  }
  return `${osType()} ${release()}`;
}

/// own_rss: the station's resident memory (this process's: a reader is a thread of it).
function ownRss(): number {
  const kb = parseU64(trim(output("ps", ["-o", "rss=", "-p", String(process.pid)]) ?? ""));
  return kb === null ? 0 : kb * 1024;
}

/// host_info (without its ten-second cache, which the caller keeps): the machine's state now, and the ticks seen.
export function hostInfo(dataDir: string, last: Seen): { info: unknown; seen: Seen } {
  const mem = memory();
  const os = osName();
  const model = cpuModel();
  const uptime = uptimeSec();
  const rss = ownRss();
  const [busy, seen] = cpuBusy(last);
  const n = availableParallelism();
  const info = {
    hostname: hostname(),
    os,
    arch: process.arch,
    cpus: n,
    cpuModel: model,
    load: Math.round((loadavg()[0]! / Math.max(n, 1)) * 100) / 100,
    cpuBusy: busy,
    uptimeSec: uptime,
    memory: mem,
    disk: disk(dataDir),
    emberRssBytes: rss,
    checkedAt: Date.now(),
  };
  return { info, seen };
}
