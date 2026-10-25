// The station process before this one (a launcher's handover, docs/station-ts.md): it holds the sessions, the agents'
// door, Slack's socket and the mesh's fixed port until it exits. What only one process may have waits for it to be
// gone; making the parts must not (the launcher stops the old process once this one says it is ready).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { log } from "./log.ts";
import { wall } from "./fibers.ts";

/// How long the previous station process is waited for before its sessions are taken up all the same.
const PREVIOUS_LIMIT_MS = 40_000;

/// Whether a process is alive (signal 0).
function alive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return (e as NodeJS.ErrnoException).code === "EPERM";
  }
}

/// The station process that held the sessions before (run/hub.json), and its end: `pid` none when none holds them (the
/// one before let go of them as it stopped, or none ran), `gone` once it is gone or has been waited for long enough.
export function previousProcess(run: string): { pid: number | null; gone: Promise<void> } {
  let pid: unknown = null;
  try {
    pid = JSON.parse(readFileSync(join(run, "hub.json"), "utf8")).pid;
  } catch {}
  if (typeof pid !== "number" || pid === process.pid) return { pid: null, gone: Promise.resolve() };
  return { pid, gone: gone(pid) };
}

/// Waits for process `pid` to be gone, PREVIOUS_LIMIT_MS at most.
async function gone(pid: number) {
  if (!alive(pid)) return;
  log.info("hub", "waiting for the previous station process to hand over", { pid });
  const until = wall.now() + PREVIOUS_LIMIT_MS;
  // A process's end can only be looked for (another program's: the machine's time): every 100 ms, for the seconds a
  // handover takes.
  while (alive(pid) && wall.now() < until) await wall.sleep(100);
  if (alive(pid)) log.warn("hub", "the previous station process is still there; taking up its sessions all the same", { pid });
}
