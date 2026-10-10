// Process groups as jobs use them (the Rust station's runtime/process.rs `signal_group`, `group_alive`, `still_ours`,
// `end_group`): a job runs in a group of its own, so it and what it starts are signalled together, and a group an
// earlier station recorded is checked to still be that group before it is touched (pids are reused).
//
// Windows has no process groups: a job's group is the job object of the `stillfail-runner --job` it runs under (its
// pgid that runner's pid), which ends whole when the runner is ended (any signal ends it there) and lives while
// anything of it does.
import { execFileSync } from "node:child_process";
import { Effect } from "effect";
import type { ProcessRow } from "../store/store.ts";
import { wall } from "../ops/fibers.ts";
import { WINDOWS } from "../ops/shell.ts";

/// Signals a whole group; one already gone is no error.
export function signalGroup(pgid: number, signal: NodeJS.Signals): void {
  if (WINDOWS) {
    try {
      process.kill(pgid, "SIGKILL");
    } catch {
      // ESRCH: already gone.
    }
    return;
  }
  try {
    process.kill(-pgid, signal);
  } catch {
    // ESRCH: the group is already gone.
  }
}

/// Whether any process of the group is there (kill(-pgid, 0) == 0, as the Rust has it).
export function groupAlive(pgid: number): boolean {
  if (WINDOWS) return pidAlive(pgid);
  try {
    process.kill(-pgid, 0);
    return true;
  } catch {
    return false;
  }
}

/// Whether one process is there.
export function pidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "EPERM";
  }
}

/// When `pid` started (ms), or null if it is not running: from its elapsed time as ps says it ([[dd-]hh:]mm:ss).
export function startTimeOf(pid: number): number | null {
  if (WINDOWS) return windowsStartTimeOf(pid);
  let text: string;
  try {
    text = execFileSync("ps", ["-o", "etime=", "-p", String(pid)], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
  } catch {
    return null;
  }
  if (text === "") return null;
  let days = 0;
  let rest = text;
  const dash = text.indexOf("-");
  if (dash >= 0) {
    days = Number(text.slice(0, dash));
    rest = text.slice(dash + 1);
    if (!Number.isInteger(days)) return null;
  }
  const parts = rest.split(":").map(Number);
  if (parts.some((p) => !Number.isInteger(p))) return null;
  let seconds: number;
  if (parts.length === 3) seconds = parts[0] * 3600 + parts[1] * 60 + parts[2];
  else if (parts.length === 2) seconds = parts[0] * 60 + parts[1];
  else return null;
  // ps says it on the machine's time.
  return wall.now() - (seconds + days * 86_400) * 1000;
}

/// When `pid` started, as Windows records it (to the millisecond), or null if it is not running or cannot be read.
function windowsStartTimeOf(pid: number): number | null {
  if (!Number.isInteger(pid) || pid <= 0) return null;
  try {
    const text = execFileSync(
      "powershell",
      ["-NoProfile", "-NonInteractive", "-Command", `(Get-Process -Id ${pid} -ErrorAction Stop).StartTime.ToUniversalTime().ToString('o')`],
      { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], windowsHide: true },
    ).trim();
    const at = Date.parse(text);
    return Number.isNaN(at) ? null : at;
  } catch {
    return null;
  }
}

/// Whether a group recorded by an earlier run is still that group. One whose leader is alive is only if the leader
/// started when it was recorded (pids get reused); one whose leader is gone but still has members is, because a pgid
/// cannot be reused while any member remains.
export function stillOurs(entry: ProcessRow): boolean {
  const started = startTimeOf(entry.pgid);
  // ps gives whole seconds: a few seconds either way is the same start.
  // On Windows a leader gone leaves nothing to know its tree by: only a leader known to be the one recorded is ours.
  const ours = started !== null ? Math.abs(started - entry.startedAt) < 5000 : !WINDOWS && groupAlive(entry.pgid);
  return ours && groupAlive(entry.pgid);
}

/// How often a group being ended is looked at.
const LOOK_MS = 100;

/// SIGTERM a group, SIGKILL it if it is still there after `graceMs`. A group that is not this process's children has
/// no exit to wait on: it is looked at every 100 ms within the grace (as the Rust does), and only then. On the clock of
/// whoever runs it.
export function endGroup(pgid: number, graceMs: number): Effect.Effect<void> {
  return Effect.gen(function* () {
    signalGroup(pgid, "SIGTERM");
    for (let i = 0; i < Math.max(1, Math.floor(graceMs / LOOK_MS)); i++) {
      yield* Effect.sleep(LOOK_MS);
      if (!groupAlive(pgid)) return;
    }
    signalGroup(pgid, "SIGKILL");
  });
}
