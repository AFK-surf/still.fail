// What the agents start (their runtimes, and the jobs they ask for) runs at a lower CPU priority than the station: on a
// machine its agents keep busy (a build on every core, a browser), the station's own work (answering its clients,
// telling them what changed) is not held behind theirs. One station's machine ran at a load of 20 on 9 cores, the
// station using 3% of one, and a list it read in 50 ms took a second and more. What the agents do is as fast as
// before while the machine has room; their children (a build a runtime starts) are as low as they are.

import { platform } from "../platform/index.ts";

/// How much lower than the station: STILLFAIL_AGENT_NICE (0: as the station), else 10.
export function agentNice(): number {
  const asked = Number(process.env.STILLFAIL_AGENT_NICE);
  return Number.isInteger(asked) && asked >= 0 && asked <= 19 ? asked : 10;
}

/// `command` with `args` as it is started lower (nice), where the system can (platform.lowered: not on Windows, nor
/// without nice).
export function niced(command: string, args: string[]): [string, string[]] {
  return platform.lowered(command, args, agentNice());
}
