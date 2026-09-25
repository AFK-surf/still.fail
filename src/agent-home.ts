// The shared agent home: one MEMORY.md and one skills/ directory used by every
// profile of both runtimes. It lives in the data dir, not the repository, since
// it holds team-specific memory. Each profile home links to it under the name
// its runtime loads automatically.
import { existsSync, lstatSync, mkdirSync, readlinkSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { Profile } from "./config.ts";
import { log } from "./log.ts";

export function agentHomePaths(agentHome: string): { memory: string; skills: string } {
  return { memory: join(agentHome, "MEMORY.md"), skills: join(agentHome, "skills") };
}

/** Creates the agent home if missing and links it into every profile home. */
export function linkAgentHome(agentHome: string, profiles: readonly Pick<Profile, "runtime" | "home">[]): void {
  const { memory, skills } = agentHomePaths(agentHome);
  mkdirSync(skills, { recursive: true });
  if (!existsSync(memory)) writeFileSync(memory, "# ember memory\n");
  for (const profile of profiles) {
    mkdirSync(profile.home, { recursive: true });
    const memoryName = profile.runtime === "claude" ? "CLAUDE.md" : "AGENTS.md";
    link(memory, join(profile.home, memoryName));
    link(skills, join(profile.home, "skills"));
  }
}

function link(target: string, path: string): void {
  let stat;
  try {
    stat = lstatSync(path);
  } catch {
    symlinkSync(target, path);
    return;
  }
  if (stat.isSymbolicLink() && readlinkSync(path) === target) return;
  // A real file or a different link: someone configured it by hand. Leave it and say so.
  log.warn("not linking the agent home over an existing path", { path, target });
}
