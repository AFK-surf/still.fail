// The station restarting itself when asked from its page (`POST /station/restart`): its launcher (run/station.json's
// pid, which says `handoff: 1`) is asked to hand over, as an installer's update does (SIGUSR2, a line on Windows'
// pipe): a new station process starts, takes the sessions over and reads config.json afresh (the mesh's advanced
// network settings among it), the old one ends. A station run without a launcher (a checkout) cannot.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { platform } from "../platform/index.ts";

/// How to ask this station's launcher to hand over, or null when there is none to ask.
export function restarter(data: string): (() => Promise<void>) | null {
  let said: any = null;
  try {
    said = JSON.parse(readFileSync(join(data, "run", "station.json"), "utf8"));
  } catch {
    return null;
  }
  const pid = Number.isSafeInteger(said?.pid) && said.pid > 0 ? (said.pid as number) : null;
  if (pid === null || said?.handoff !== 1 || !platform.isLauncher(pid)) return null;
  return () => platform.askLauncher(pid, "handover");
}
