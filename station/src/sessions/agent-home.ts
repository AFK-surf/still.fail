// The shared agent home (from the Rust station's agent_home.rs): one MEMORY.md and one skills/ directory used by every profile of
// both runtimes. It lives in the data dir, not the repository, since it holds team-specific memory. Each profile home
// links to it under the name its runtime loads automatically; the station's own skills are written into it at start.
// Their text is src/skills/*.md, read from there when running from source and from dist/skills/ (copied there by the
// build) when bundled. A workspace the station joined has its own, beside it (`workspaceAgentHome`,
// docs/multi-workspace.md).
import { existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, readlinkSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { log } from "../ops/log.ts";
import type { Runtime } from "./config.ts";

export const agentHomePaths = (agentHome: string): [string, string] => [join(agentHome, "MEMORY.md"), join(agentHome, "skills")];

/// The agent home of workspace `ws` (docs/multi-workspace.md): the home workspace's (`home`; null outside any, when
/// there is no telling) is the agent home itself, a joined one's workspaces/<ws> in it, made with its MEMORY.md and skills/ when missing. A session
/// is told its workspace's (its instructions name its MEMORY.md, the skills beside it); the station shares the home
/// workspace's skills only (share/index.ts).
export function workspaceAgentHome(agentHome: string, ws: string | null, home: string | null): string {
  if (ws === null || home === null || ws === home) return agentHome;
  if (!/^[0-9A-Za-z_-]{1,128}$/.test(ws)) throw new Error(`not a workspace id: ${JSON.stringify(ws)}`);
  const dir = join(agentHome, "workspaces", ws);
  const [memory, skills] = agentHomePaths(dir);
  if (!existsSync(skills)) mkdirSync(skills, { recursive: true });
  if (!existsSync(memory)) writeFileSync(memory, "# still.fail memory\n");
  return dir;
}

/// The skills the station brings, by directory name: about its own tools, so they are rewritten at every start and
/// change with the station (the team's own skills sit beside them).
const BUILTIN_SKILLS = ["stillfail-jobs", "stillfail-show", "stillfail-viz", "stillfail-browser", "stillfail-login", "stillfail-cron"];
/// When to offer a bug report to the still.fail team: only from a station on the stable channel, beside the
/// `feedback_send` tool; gone from one on the test channel (the team's own).
const FEEDBACK_SKILL = "stillfail-feedback";
/// The station's own skills as they were named before the rename: gone once the new ones are written (they would be
/// listed twice). A directory with more in it than the SKILL.md the station wrote is left.
const FORMER_BUILTIN_SKILLS = ["ember-jobs", "ember-show", "ember-viz"];

/// Where the skills' text is.
const skillsSource = (): URL => (import.meta.url.endsWith(".ts") ? new URL("../skills/", import.meta.url) : new URL("./skills/", import.meta.url));

/// A built-in skill's SKILL.md, as the station has it.
export const builtinSkill = (name: string): string => readFileSync(new URL(`${name}.md`, skillsSource()), "utf8");

/// Whether a directory holds nothing but the SKILL.md the station wrote.
function onlySkill(dir: string): boolean {
  try {
    return lstatSync(dir).isDirectory() && readdirSync(dir).every((e) => e === "SKILL.md");
  } catch {
    return false;
  }
}

/// Writes the station's own skills into the shared skills directory; `feedback`: the stillfail-feedback skill too
/// (else it is taken away, unless someone added to it).
export function writeBuiltinSkills(agentHome: string, feedback: boolean) {
  const [, skills] = agentHomePaths(agentHome);
  for (const name of FORMER_BUILTIN_SKILLS) {
    const dir = join(skills, name);
    if (onlySkill(dir)) rmSync(dir, { recursive: true, force: true });
  }
  if (!feedback && onlySkill(join(skills, FEEDBACK_SKILL))) rmSync(join(skills, FEEDBACK_SKILL), { recursive: true, force: true });
  for (const name of feedback ? [...BUILTIN_SKILLS, FEEDBACK_SKILL] : BUILTIN_SKILLS) {
    const text = builtinSkill(name);
    const dir = join(skills, name);
    mkdirSync(dir, { recursive: true });
    const path = join(dir, "SKILL.md");
    let now: string | null = null;
    try {
      now = readFileSync(path, "utf8");
    } catch {}
    if (now !== text) writeFileSync(path, text);
  }
}

export type ProfileHome = { id: string; runtimes: Runtime[]; home: string };

const isLink = (path: string) => {
  try {
    return lstatSync(path).isSymbolicLink();
  } catch {
    return false;
  }
};

/// Whether `path` is a directory with no file anywhere in it: what a runtime makes in its home before the link is
/// there (Claude Code's skills/synced/), so nothing is lost putting the link in its place.
function hollow(path: string): boolean {
  try {
    return lstatSync(path).isDirectory() && readdirSync(path).every((e) => hollow(join(path, e)));
  } catch {
    return false;
  }
}

/// The paths already said to be left alone: said once, not at each look.
const leftAlone = new Set<string>();

function link(target: string, path: string) {
  let meta;
  try {
    meta = lstatSync(path);
  } catch {
    meta = null;
  }
  if (meta?.isSymbolicLink() && readlinkSync(path) === target) return;
  if (meta && !hollow(path)) {
    // A real file or a different link: someone configured it by hand. Leave it and say so.
    if (!leftAlone.has(path)) log.warn("agent_home", "not linking the agent home over an existing path", { path, target });
    leftAlone.add(path);
    return;
  }
  if (meta) rmSync(path, { recursive: true, force: true });
  // A directory's link on Windows is a junction: a symbolic link there needs an administrator.
  symlinkSync(target, path, process.platform === "win32" && lstatSync(target).isDirectory() ? "junction" : undefined);
}

/// Creates the agent home if missing and links it into every profile home.
export function linkAgentHome(agentHome: string, profiles: ProfileHome[]) {
  const [memory, skills] = agentHomePaths(agentHome);
  mkdirSync(skills, { recursive: true });
  if (!existsSync(memory)) writeFileSync(memory, "# still.fail memory\n");
  for (const { runtimes, home } of profiles) {
    mkdirSync(home, { recursive: true });
    // Each runtime it runs reads the memory under its own name (Codex and DeepSeek Harness both AGENTS.md).
    for (const name of new Set(runtimes.filter((r) => r !== "grok").map((runtime) => (runtime === "claude" ? "CLAUDE.md" : "AGENTS.md")))) link(memory, join(home, name));
    link(skills, join(home, "skills"));
    // Grok Build's home is its own directory in the profile's (agents/grok.ts): AGENTS.md and skills/ there.
    if (runtimes.includes("grok")) {
      mkdirSync(join(home, "grok"), { recursive: true });
      link(memory, join(home, "grok", "AGENTS.md"));
      link(skills, join(home, "grok", "skills"));
    }
  }
}

/// One place for each runtime's transcripts, shared by every profile that runs it: a session is the station's, not an
/// account's, so any account can take it on (another, when one's quota is used up) with all it had. Each profile home's
/// transcript directory (Claude Code's projects/, Codex's sessions/, DeepSeek Harness's dsh-sessions/ as dsh.ts sets
/// it, Grok Build's grok/sessions/) is a link there. A real directory in its place is
/// left alone, with a warning (the profile then keeps its own).
/// Where in a profile home a runtime keeps its transcripts.
export const transcriptDir = (runtime: string) => (runtime === "claude" ? "projects" : runtime === "codex" ? "sessions" : runtime === "grok" ? "grok/sessions" : "dsh-sessions");

export function linkTranscripts(dataDir: string, profiles: ProfileHome[]) {
  for (const { id, runtimes, home } of profiles) {
    for (const runtime of runtimes) {
      const shared = join(dataDir, "transcripts", runtime);
      mkdirSync(shared, { recursive: true });
      mkdirSync(home, { recursive: true });
      const path = join(home, transcriptDir(runtime));
      mkdirSync(dirname(path), { recursive: true });
      if (!existsSync(path) && !isLink(path)) symlinkSync(shared, path);
      else if (!isLink(path) || readlinkSync(path) !== shared) log.warn("agent_home", "a profile's transcripts are not in the shared place", { profile: id, path });
    }
  }
}
