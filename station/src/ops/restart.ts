// The station restarting itself when asked from its page (`POST /station/restart`): its launcher (run/station.json's
// pid, which says `handoff: 1`) is asked to hand over, as an installer's update does (SIGUSR2, a line on Windows'
// pipe): a new station process starts, takes the sessions over and reads config.json afresh (the mesh's advanced
// network settings among it), the old one ends. A station run without a launcher (a checkout) cannot.
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { platform } from "../platform/index.ts";
import { wall } from "./fibers.ts";

/// How to ask this station's launcher to hand over, or null when there is none to ask.
export async function restarter(data: string): Promise<(() => Promise<void>) | null> {
  let said: any = null;
  try {
    said = JSON.parse(await readFile(join(data, "run", "station.json"), "utf8"));
  } catch {
    return null;
  }
  const pid = Number.isSafeInteger(said?.pid) && said.pid > 0 ? (said.pid as number) : null;
  if (pid === null || said?.handoff !== 1 || !(await platform.isLauncher(pid))) return null;
  return () => platform.askLauncher(pid, "handover");
}

/// How long after its launcher was asked to hand over a process still there asks again.
const AGAIN_MS = 5000;

/// This process gives way to one started anew as what the machine is now (a station made one that only runs tasks,
/// or whole again): handed over by its launcher, so its connections end as a restart's do; ended where it has none.
/// A launcher takes one handover at a time and drops one asked meanwhile (the machine made a rig and whole again
/// within a second: the first handover still under way), so it is asked again while this process is still there.
export function becomeOther(data: string): void {
  void restarter(data).then((again) => {
    if (again === null) process.exit(1);
    void again().catch(() => process.exit(1));
    wall.after(AGAIN_MS, () => becomeOther(data)); // timer: a retry after a failure (a handover dropped), until this process is gone
  }, () => process.exit(1));
}
