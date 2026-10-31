// Reading what a machine's commands and files say (read/host.ts's, for every machine): Rust's str methods as host.rs
// uses them.
import { spawnSync } from "node:child_process";

/// Rust's str::trim (char::is_whitespace).
const WS = "\\t\\n\\v\\f\\r \\u0085\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000";
const TRIM = new RegExp(`^[${WS}]+|[${WS}]+$`, "g");
export const trim = (s: string) => s.replace(TRIM, "");
const SPLIT = new RegExp(`[${WS}]+`);
export const firstWord = (s: string) => s.split(SPLIT).find((w) => w !== "") ?? "";
export const splitWords = (s: string) => s.split(SPLIT).filter((w) => w !== "");

/// str::parse::<u64>: digits (a `+` before them at most); none otherwise.
export const parseU64 = (s: string): number | null => (/^\+?[0-9]+$/.test(s) ? Number(s) : null);
/// str::parse::<f64> for what these commands write (no inf or nan here).
export const parseF64 = (s: string): number | null => (/^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$/.test(s) ? Number(s) : null);

/// output: a command's output, trimmed, or none when it cannot be run (within a few seconds) or fails.
export function output(command: string, args: string[]): string | null {
  const out = spawnSync(command, args, { timeout: 3000, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  return out.status === 0 && typeof out.stdout === "string" ? trim(out.stdout) : null;
}

/// What a system's memory left says of its pressure (where it has no level of its own): under a tenth available is high,
/// under 4% critical.
export function pressureOfAvailable(available: number | null, total: number | null): "normal" | "high" | "critical" | null {
  if (available === null || total === null || !(total > 0) || !(available >= 0) || available > total) return null;
  const share = available / total;
  return share < 0.04 ? "critical" : share < 0.1 ? "high" : "normal";
}

/// macOS's kern.memorystatus_vm_pressure_level: 1 normal, 2 warn, 4 critical.
export function pressureOfLevel(level: string): "normal" | "high" | "critical" | null {
  switch (trim(level)) {
    case "1":
      return "normal";
    case "2":
      return "high";
    case "4":
      return "critical";
    default:
      return null;
  }
}

/// `ps -axo pid=,ppid=,pgid=,rss=,comm=`: each process with its resident memory (bytes).
export function parsePs(text: string): { pid: number; ppid: number; pgid: number; bytes: number; command: string }[] {
  const out: { pid: number; ppid: number; pgid: number; bytes: number; command: string }[] = [];
  for (const line of text.split("\n")) {
    const m = line.match(/^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s?(.*)$/);
    if (!m) continue;
    out.push({ pid: Number(m[1]), ppid: Number(m[2]), pgid: Number(m[3]), bytes: Number(m[4]) * 1024, command: trim(m[5] ?? "") });
  }
  return out;
}

/// `top -l 1 -stats pid,mem`: each process's footprint (bytes) as top says it (27M, 3056K, 1.2G, a + or - after it).
export function parseTopMem(text: string): Map<number, number> {
  const out = new Map<number, number>();
  const unit: Record<string, number> = { B: 1, K: 1024, M: 1024 ** 2, G: 1024 ** 3, T: 1024 ** 4 };
  for (const line of text.split("\n")) {
    const m = line.match(/^\s*(\d+)\s+([\d.]+)([BKMGT])[+-]?\s*$/);
    if (m) out.set(Number(m[1]), Math.round(Number(m[2]) * unit[m[3]!]!));
  }
  return out;
}

/// The number after `label:` in `text` (vm_stat and /proc/meminfo); null if absent or unreadable.
export function fieldOrNull(text: string, label: string): number | null {
  for (const line of text.split("\n")) {
    if (!line.startsWith(`${label}:`)) continue;
    return parseU64(firstWord(trim(line.slice(label.length + 1)).replace(/\.+$/, "")));
  }
  return null;
}

/// proc_stat_ticks: CPU time from /proc/stat's first line; waiting on disks (iowait) counts as idle, as top counts it.
export function procStatTicks(stat: string): [busy: number, total: number] | null {
  const line = stat.split("\n").find((l) => l.startsWith("cpu "));
  if (line === undefined) return null;
  const v = splitWords(line).slice(1, 9).map(parseU64).filter((n): n is number => n !== null);
  if (v.length < 4) return null;
  const total = v.reduce((a, b) => a + b, 0);
  const idle = v[3]! + (v[4] ?? 0);
  return [total - idle, total];
}

/// lsof -Fn's names of the sockets listening at `port`: `n127.0.0.1:8085`, `n[::1]:8085`, `n*:8085` → the addresses.
export function parseLsof(text: string, port: number): string[] {
  const found: string[] = [];
  for (const line of text.split("\n")) {
    if (!line.startsWith("n")) continue;
    const name = line.slice(1).trim();
    const at = name.lastIndexOf(":");
    if (at < 0 || Number(name.slice(at + 1)) !== port) continue;
    const address = name.slice(0, at).replace(/^\[|\]$/g, "");
    if (!found.includes(address)) found.push(address);
  }
  return found;
}

/// How long the input has been idle (ms) by what `ioreg -c IOHIDSystem -r -k HIDIdleTime` says (its first
/// HIDIdleTime, in ns); none when it says none.
export function idleOfIoreg(text: string): number | null {
  const m = /"HIDIdleTime"\s*=\s*([0-9]+)/.exec(text);
  return m === null ? null : Number(m[1]) / 1e6;
}
