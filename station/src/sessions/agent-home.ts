// The agents' home (from the Rust station's agent_home.rs): one MEMORY.md and one skills/ directory used by every
// profile of every runtime. It lives in the data dir, not the repository, since it holds team-specific memory. A
// workspace the station joined has its own, beside it (`workspaceAgentHome`, docs/multi-workspace.md). A session is
// given its workspace's, not through the profile's home (a profile serves every workspace): the memory with its
// instructions, the skills linked where it runs (`sessionSkills`). The station's own skills are written into each at
// start. Their text is src/skills/*.md, read from there when running from source and from dist/skills/ (copied there by
// the build) when bundled.
import { closeSync, existsSync, linkSync as hardLinkSync, lstatSync, mkdirSync, openSync, readdirSync, readFileSync, readlinkSync, readSync, realpathSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { RUNTIME_KINDS } from "../agents/runtime.ts";
import { linkSync } from "../ops/links.ts";
import { log } from "../ops/log.ts";
import { within } from "../ops/paths.ts";
import { sharedTranscripts, transcriptDir } from "../read/transcript.ts";
import type { Runtime } from "./config.ts";

export const agentHomePaths = (agentHome: string): [string, string] => [join(agentHome, "MEMORY.md"), join(agentHome, "skills")];

/// The agent home of workspace `ws` (docs/multi-workspace.md): the home workspace's (`home`; null outside any, when
/// there is no telling) is the agent home itself, a joined one's workspaces/<ws> in it, made with its MEMORY.md and
/// skills/ (the station's own skills in it, as the home workspace has them) when missing. A session is given its
/// workspace's; the station shares the home workspace's skills only (share/index.ts).
export function workspaceAgentHome(agentHome: string, ws: string | null, home: string | null): string {
  if (ws === null || home === null || ws === home) return agentHome;
  if (!/^[0-9A-Za-z_-]{1,128}$/.test(ws)) throw new Error(`not a workspace id: ${JSON.stringify(ws)}`);
  const dir = join(agentHome, "workspaces", ws);
  const [memory, skills] = agentHomePaths(dir);
  if (!existsSync(skills)) {
    mkdirSync(skills, { recursive: true });
    writeBuiltinSkills(dir, existsSync(join(agentHomePaths(agentHome)[1], FEEDBACK_SKILL)));
  }
  if (!existsSync(memory)) writeFileSync(memory, "# still.fail memory\n");
  return dir;
}

/// The agent home and those of the workspaces the station joined (made so far).
export const agentHomes = (agentHome: string): string[] => [agentHome, ...entries(join(agentHome, "workspaces")).map((ws) => join(agentHome, "workspaces", ws)).filter(realDir)];

/// The skills the station brings, by directory name: about its own tools, so they are rewritten at every start and
/// change with the station (the team's own skills sit beside them).
const BUILTIN_SKILLS = ["stillfail-jobs", "stillfail-show", "stillfail-viz", "stillfail-browser", "stillfail-login", "stillfail-vault", "stillfail-cron"];
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

/// The paths already said to be left alone: said once, not at each look.
const leftAlone = new Set<string>();

/// Whether `path` is a link to `target`, however either is spelled (~/.ember is a link to ~/.stillfail).
function linksTo(path: string, target: string): boolean {
  try {
    return lstatSync(path).isSymbolicLink() && (readlinkSync(path) === target || realpathSync(path) === realpathSync(target));
  } catch {
    return false;
  }
}

/// Whether `path` is a link to something in directory `dir` (one of its skills, gone or not), however either is spelled.
function linksInto(path: string, dir: string): boolean {
  try {
    if (!lstatSync(path).isSymbolicLink()) return false;
    if (dirname(readlinkSync(path)) === dir) return true;
    return dirname(realpathSync(path)) === realpathSync(dir);
  } catch {
    return false;
  }
}

/// Takes away what stations before this one linked into every profile home: the home workspace's memory and skills,
/// under the names its runtimes load by themselves (CLAUDE.md/AGENTS.md, skills/, Grok Build's and Hermes' own). A
/// profile serves every workspace the station is in, so its home holds no workspace's: a joined workspace's sessions
/// were given the home workspace's memory and skills that way. A session has its own workspace's instead: its memory
/// with its instructions (agents/instructions.ts), its skills where it runs (`sessionSkills`). Anything else is left.
export function unlinkAgentHome(agentHome: string, profiles: ProfileHome[]) {
  const [memory, skills] = agentHomePaths(agentHome);
  for (const { home } of profiles) {
    for (const name of ["CLAUDE.md", "AGENTS.md", join("grok", "AGENTS.md")]) {
      if (linksTo(join(home, name), memory)) rmSync(join(home, name), { force: true });
    }
    for (const dir of ["skills", join("hermes", "skills"), join("grok", "skills")]) {
      const path = join(home, dir);
      // (not recursive: a junction's target is not to go with it)
      if (linksTo(path, skills)) rmSync(path, { force: true });
      else for (const entry of entries(path)) if (linksInto(join(path, entry), skills)) rmSync(join(path, entry), { force: true });
    }
  }
}

/// Where the runtimes find skills in the directory they run in: Claude Code's project skills, Codex's (the Agent
/// Skills standard's) repository ones.
export const SKILL_HOMES = [join(".claude", "skills"), join(".agents", "skills")];

/// Links the skills of a session's workspace (`skills`, its agent home's) into the directory it runs in (`workspace`),
/// where its runtime loads them as its own (SKILL_HOMES), as a preset's folders' are (presets.ts `keepCopy`); a link to
/// one gone is taken away. One of the same name there already (a preset's) is left.
export function sessionSkills(workspace: string, skills: string) {
  const names = entries(skills).filter((n) => existsSync(join(skills, n, "SKILL.md")));
  for (const home of SKILL_HOMES) {
    const dir = join(workspace, home);
    for (const entry of entries(dir)) if (!names.includes(entry) && linksInto(join(dir, entry), skills)) rmSync(join(dir, entry), { force: true });
    if (names.length === 0) continue;
    mkdirSync(dir, { recursive: true });
    for (const name of names) {
      const at = join(dir, name);
      if (!existsSync(at) && !isLink(at)) linkSync(join(skills, name), at, { junction: true });
    }
  }
}

/// One place for each runtime's transcripts (read/transcript.ts `sharedTranscripts`), shared by every home the station
/// keeps: a session is the station's, not an account's, so any account can take it on (another, when one's quota is
/// used up) with all it had, and its history is found there whatever the config says now (a profile's home changed, or
/// the profile gone, while a runtime still wrote in the home it started in). Each profile home's transcript directory
/// (`transcriptDir`) is a link there. One that is a real directory (a runtime made it before it was linked) puts what it
/// holds there too and gives way to the link (`share`); so does one in a home under the data directory's homes/ that no
/// profile names any more. A home outside the data directory whose runtime keeps its transcripts there is the person's
/// own: left alone, with a warning (the profile then keeps its own, read there).
export function linkTranscripts(dataDir: string, profiles: ProfileHome[]) {
  const data = canonical(dataDir);
  for (const { id, runtimes, home } of profiles) {
    mkdirSync(home, { recursive: true });
    for (const runtime of runtimes) share(join(home, transcriptDir(runtime)), sharedTranscripts(dataDir, runtime), within(canonical(home), data), id);
  }
  const named = new Set(profiles.map((p) => canonical(p.home)));
  const homes = join(dataDir, "homes");
  for (const name of entries(homes)) {
    const home = join(homes, name);
    if (named.has(canonical(home)) || !realDir(home)) continue;
    for (const runtime of RUNTIME_KINDS) {
      const dir = join(home, transcriptDir(runtime));
      // Codex keeps its rollouts by date, in directories; Claude Code's own sessions/ in a home of its holds files only.
      if (realDir(dir) && (runtime !== "codex" || entries(dir).some((e) => realDir(join(dir, e))))) share(dir, sharedTranscripts(dataDir, runtime), true, name);
    }
  }
}

const canonical = (path: string) => {
  try {
    return realpathSync(path);
  } catch {
    return path;
  }
};
const entries = (dir: string): string[] => {
  try {
    return readdirSync(dir);
  } catch {
    return [];
  }
};
const realDir = (path: string) => lstatSync(path, { throwIfNoEntry: false })?.isDirectory() === true;

/// Makes transcript directory `dir` (of the home of profile `of`) a link to the shared place `shared`. A real directory
/// there, when it `gathers` (it is in the data directory), puts everything it holds in the shared place as well, the
/// same files, and is moved aside for the link while its runtime may still be writing there; then what was written
/// meanwhile is gathered too, and what is aside goes, unless some of it could not be put there. Otherwise it is left.
function share(dir: string, shared: string, gathers: boolean, of: string) {
  mkdirSync(shared, { recursive: true });
  mkdirSync(dirname(dir), { recursive: true });
  // A runtime writing there in the moment it is moved aside makes it again: gathered again.
  for (let tries = 0; tries < 3; tries++) {
    const meta = lstatSync(dir, { throwIfNoEntry: false });
    if (meta === undefined) {
      if (linkDir(shared, dir)) return;
      continue;
    }
    if (linksTo(dir, shared)) return;
    if (!gathers || !meta.isDirectory()) {
      if (!leftAlone.has(dir)) log.warn("agent_home", "a profile's transcripts are not in the shared place", { profile: of, path: dir });
      leftAlone.add(dir);
      return;
    }
    gather(dir, shared);
    let aside = `${dir}.unshared`;
    for (let n = 2; lstatSync(aside, { throwIfNoEntry: false }) !== undefined; n++) aside = `${dir}.unshared-${n}`;
    try {
      renameSync(dir, aside);
    } catch (error) {
      // In use where a directory in use cannot be moved (Windows): as it was, its files in the shared place as well.
      log.warn("agent_home", "a home's transcripts not moved to the shared place", { profile: of, path: dir, error: (error as Error).message });
      return;
    }
    let made: boolean;
    try {
      made = linkDir(shared, dir);
    } catch (error) {
      renameSync(aside, dir);
      throw error;
    }
    const left = gather(aside, shared);
    if (left.length === 0) rmSync(aside, { recursive: true, force: true });
    else log.warn("agent_home", "transcripts kept aside: the shared place has others of the same names", { profile: of, path: aside, files: left.length, first: left[0] });
    if (made) {
      log.info("agent_home", "a home's transcripts moved to the shared place", { profile: of, path: dir });
      return;
    }
  }
}

/// `path` made a link to directory `target` (a junction where links are refused); false when something is there first.
function linkDir(target: string, path: string): boolean {
  try {
    return linkSync(target, path, { junction: true }) !== "refused";
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "EEXIST") return false;
    throw error;
  }
}

/// Puts every file under `from` at the same place under `to` as well: the same file (a hard link, so a runtime that
/// goes on writing it by either path writes both), directories made as needed; through a link, what it links to. A
/// file of the same name already there that is not the same file stays, unless it is a copy of this one from before it
/// grew (a home copied while its runtime went on writing in the original): then this one takes its place. One that
/// holds all this one does and more is that copy further along: this one is in it. The files left out: where each went
/// on its own way.
function gather(from: string, to: string, left: string[] = [], seen = new Set<string>()): string[] {
  for (const name of entries(from)) {
    const path = join(from, name);
    const there = join(to, name);
    try {
      const real = realpathSync(path);
      const st = statSync(real);
      if (st.isDirectory()) {
        if (seen.has(real) || real === canonical(there)) continue;
        seen.add(real);
        mkdirSync(there, { recursive: true });
        gather(real, there, left, seen);
        continue;
      }
      const other = statSync(there, { throwIfNoEntry: false });
      if (!st.isFile()) left.push(path);
      else if (other === undefined) hardLinkSync(real, there);
      else if (other.dev === st.dev && other.ino === st.ino) continue;
      else if (st.size > other.size && begins(real, there, other.size)) {
        const next = `${there}.${process.pid}.sharing`;
        rmSync(next, { force: true });
        hardLinkSync(real, next);
        renameSync(next, there);
      } else if (!(other.size >= st.size && begins(there, real, st.size))) left.push(path);
    } catch {
      left.push(path);
    }
  }
  return left;
}

/// Whether file `a` begins with the first `n` bytes of file `b`.
function begins(a: string, b: string, n: number): boolean {
  const [fa, fb] = [openSync(a, "r"), openSync(b, "r")];
  try {
    const [ba, bb] = [Buffer.alloc(1 << 20), Buffer.alloc(1 << 20)];
    for (let at = 0; at < n; ) {
      const want = Math.min(ba.length, n - at);
      const [ra, rb] = [readSync(fa, ba, 0, want, at), readSync(fb, bb, 0, want, at)];
      if (ra !== want || rb !== want || !ba.subarray(0, want).equals(bb.subarray(0, want))) return false;
      at += want;
    }
    return true;
  } finally {
    closeSync(fa);
    closeSync(fb);
  }
}
