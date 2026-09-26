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
export function linkAgentHome(agentHome: string, profiles: readonly Pick<Profile, "runtimes" | "home">[]): void {
  const { memory, skills } = agentHomePaths(agentHome);
  mkdirSync(skills, { recursive: true });
  if (!existsSync(memory)) writeFileSync(memory, "# ember memory\n");
  for (const profile of profiles) {
    mkdirSync(profile.home, { recursive: true });
    // Each runtime it runs reads the memory under its own name.
    for (const runtime of profile.runtimes) link(memory, join(profile.home, runtime === "claude" ? "CLAUDE.md" : "AGENTS.md"));
    link(skills, join(profile.home, "skills"));
  }
}

/**
 * One place for each runtime's transcripts, shared by every profile that runs it: a session is the station's, not an
 * account's, so any account can take it on (another, when one's quota is used up) with all it had. Each profile home's
 * transcript directory (Claude Code's projects/, Codex's sessions/) is a link there. A real directory in its place is
 * left alone, with a warning (the profile then keeps its own).
 */
export function linkTranscripts(dataDir: string, profiles: readonly Pick<Profile, "id" | "runtimes" | "home">[]): void {
  for (const profile of profiles) {
    for (const runtime of profile.runtimes) {
      const shared = join(dataDir, "transcripts", runtime);
      mkdirSync(shared, { recursive: true });
      mkdirSync(profile.home, { recursive: true });
      const path = join(profile.home, runtime === "claude" ? "projects" : "sessions");
      if (!existsSync(path) && !isLink(path)) symlinkSync(shared, path);
      else if (!isLink(path) || readlinkSync(path) !== shared) log.warn("a profile's transcripts are not in the shared place", { profile: profile.id, path });
    }
  }
}

function isLink(path: string): boolean {
  try {
    return lstatSync(path).isSymbolicLink();
  } catch {
    return false;
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
