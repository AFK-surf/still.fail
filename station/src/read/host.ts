// What the machine a station runs on looks like (GET /host), ported from the Rust station's host.rs: for people deciding
// where work goes and whether a station is struggling. How each machine is read (memory, CPU time, uptime, its OS) is
// the platform's (platform/: macOS's sysctl and vm_stat, Linux's /proc, what Node's os says on Windows); disk is the
// file system holding the station's data directory. It runs commands in a reader thread; what the Rust keeps between
// looks (the ticks last seen, the answer of the last ten seconds) the main thread keeps and hands in as readers come
// and go. When another CPU sample is needed, the caller waits between reads without holding a reader.
import { statfsSync } from "node:fs";
import { availableParallelism, hostname as osHostname, loadavg } from "node:os";
import { wall } from "../ops/fibers.ts";
import { platform } from "../platform/index.ts";
import { cpuShare, type Ticks } from "../platform/cpu-share.ts";

export type { Ticks };
/// The ticks last seen, and when (host.rs TICKS).
export type Seen = { at: number; ticks: Ticks } | null;

/// hostname, without a `.local`.
function hostname(): string {
  const name = osHostname();
  return name.endsWith(".local") ? name.slice(0, -".local".length) : name;
}

/// cpu_busy: how busy the CPUs have been since the last look, if that was within a minute; otherwise over the next
/// moment. If they have not moved yet, return the first sample and let the caller ask again later.
function cpuBusy(last: Seen): [busy: number | null, seen: Seen, needsTicks: boolean] {
  const before = last !== null && wall.now() - last.at < 60_000 ? last.ticks : null;
  const now = platform.host.cpuTicks();
  if (now === null) return [null, last, false];
  const busy = before === null ? null : cpuShare(before, now);
  return [busy === null ? null : Math.round(busy * 100) / 100, { at: wall.now(), ticks: now }, busy === null];
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

/// host_info (without its ten-second cache, which the caller keeps): the machine's state now, and the ticks seen.
export function hostInfo(dataDir: string, last: Seen): { info: unknown; seen: Seen; needsTicks: boolean } {
  // The isolated app recording station must not put its host machine's identity and resource state in fixtures.
  if (process.env.STILLFAIL_TEST_HOST === "1") {
    return { info: {
      hostname: "test-station", os: "Test OS", arch: "arm64", cpus: 4, cpuModel: "Test CPU", load: 0.25,
      loadAvg: [1, 1, 1], cpuBusy: 0.25, uptimeSec: 3600,
      memory: { totalBytes: 8_000_000_000, usedBytes: 4_000_000_000, swapUsedBytes: 0 },
      disk: { path: "/test-station/data", totalBytes: 100_000_000_000, freeBytes: 50_000_000_000 },
      stationRssBytes: 100_000_000, checkedAt: wall.now(),
    }, seen: null, needsTicks: false };
  }
  const { host } = platform;
  const mem = host.memory();
  const os = host.osName();
  const model = host.cpuModel();
  const uptime = host.uptimeSec();
  const rss = host.ownRss();
  const [busy, seen, needsTicks] = cpuBusy(last);
  const n = availableParallelism();
  const info = {
    hostname: hostname(),
    os,
    arch: process.arch,
    cpus: n,
    cpuModel: model,
    load: Math.round((loadavg()[0]! / Math.max(n, 1)) * 100) / 100,
    // The run queue over 1, 5 and 15 minutes as `uptime` says it (Windows has none: Node says zeros).
    loadAvg: platform.os === "windows" ? null : loadavg().map((l) => Math.round(l * 100) / 100),
    cpuBusy: busy,
    uptimeSec: uptime,
    memory: mem,
    disk: disk(dataDir),
    stationRssBytes: rss,
    // Clients from before the name need this field, and refuse the whole station list without it.
    emberRssBytes: rss,
    checkedAt: wall.now(),
  };
  return { info, seen, needsTicks };
}
