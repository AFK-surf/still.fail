// Presets: what a chat starts knowing, chosen as it is opened (docs/presets.md). A preset names the directories its
// chats work with and what people want of them there; it does not bind the agent to them (it runs in its own session
// workspace as every chat does). A workspace's presets are its agent home's presets.json; a chat opened with one keeps a
// copy of it in its session workspace (`.stillfail-preset.json`), so a preset changed later changes none of the chats
// already opened with it.
import { mkdirSync, readFileSync, renameSync, statSync, writeFileSync } from "node:fs";
import { readFile, readdir, stat } from "node:fs/promises";
import { basename, isAbsolute, join, resolve, sep } from "node:path";
import { homedir } from "node:os";
import { randomBytes } from "node:crypto";

/// A directory a preset works with: a path on this station, and the repository it is a clone of (its origin), if one.
export type PresetDir = { path: string; repo: string | null };

export type Preset = {
  id: string;
  name: string;
  dirs: PresetDir[];
  /// What people want of its chats, as they wrote it.
  instructions: string;
  createdBy: string;
  createdAt: number;
  updatedAt: number;
};

/// What a chat was opened with: the preset as it was then.
export type PresetCopy = { id: string; name: string; dirs: PresetDir[]; instructions: string };

const FILE = "presets.json";
const COPY = ".stillfail-preset.json";
const NAME_MAX = 60;
const INSTRUCTIONS_MAX = 20_000;
const DIRS_MAX = 20;

const str = (v: unknown): string | null => (typeof v === "string" ? v : null);

function dirsOf(v: unknown): PresetDir[] {
  if (!Array.isArray(v)) return [];
  return v.flatMap((d) => (typeof d?.path === "string" ? [{ path: d.path, repo: str(d.repo) }] : []));
}

function presetOf(v: any): Preset | null {
  if (typeof v?.id !== "string" || typeof v?.name !== "string") return null;
  return {
    id: v.id,
    name: v.name,
    dirs: dirsOf(v.dirs),
    instructions: str(v.instructions) ?? "",
    createdBy: str(v.createdBy) ?? "",
    createdAt: typeof v.createdAt === "number" ? v.createdAt : 0,
    updatedAt: typeof v.updatedAt === "number" ? v.updatedAt : 0,
  };
}

/// The presets of the workspace whose agent home is `home`, as written; none when there is no file yet.
export function readPresets(home: string): Preset[] {
  try {
    const raw = JSON.parse(readFileSync(join(home, FILE), "utf8"));
    return (Array.isArray(raw?.presets) ? raw.presets : []).flatMap((p: unknown) => presetOf(p) ?? []);
  } catch {
    return [];
  }
}

function writePresets(home: string, presets: Preset[]): void {
  mkdirSync(home, { recursive: true });
  const path = join(home, FILE);
  const temp = `${path}.${randomBytes(4).toString("hex")}`;
  writeFileSync(temp, `${JSON.stringify({ presets }, null, 2)}\n`);
  renameSync(temp, path);
}

/// What a preset is said to be (POST, PUT /presets): its name and instructions trimmed, its directories each a
/// directory on this machine (`~` its home), named once each.
export function presetInput(v: unknown): { name: string; dirs: PresetDir[]; instructions: string } {
  const o = (v ?? {}) as Record<string, unknown>;
  const name = (str(o.name) ?? "").trim();
  if (name === "") throw new Error("a preset needs a name");
  if (Array.from(name).length > NAME_MAX) throw new Error(`a preset's name is ${NAME_MAX} characters at most`);
  const instructions = (str(o.instructions) ?? "").trim();
  if (instructions.length > INSTRUCTIONS_MAX) throw new Error("its instructions are too long");
  if (!Array.isArray(o.dirs)) throw new Error("dirs: a list of directories");
  const dirs: PresetDir[] = [];
  for (const d of o.dirs) {
    const given = typeof d === "string" ? d : str((d as { path?: unknown })?.path);
    if (given === null || given.trim() === "") throw new Error("a directory needs a path");
    const path = expand(given.trim());
    if (!isDirectory(path)) throw new Error(`${given} is no directory on this station`);
    if (dirs.some((x) => x.path === path)) continue;
    dirs.push({ path, repo: originOf(path) });
  }
  if (dirs.length > DIRS_MAX) throw new Error(`a preset has ${DIRS_MAX} directories at most`);
  return { name, dirs, instructions };
}

function expand(path: string): string {
  if (path === "~") return homedir();
  if (path.startsWith("~/")) return join(homedir(), path.slice(2));
  return isAbsolute(path) ? resolve(path) : resolve(homedir(), path);
}

function isDirectory(path: string): boolean {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

/// The repository a clone at `path` is of (its origin's URL, as `host/owner/name`), if it is one.
export function originOf(path: string): string | null {
  let config: string;
  try {
    config = readFileSync(join(gitDir(path) ?? join(path, ".git"), "config"), "utf8");
  } catch {
    return null;
  }
  return originIn(config);
}

/// The origin a git config names, as `host/owner/name`.
function originIn(config: string): string | null {
  const at = config.search(/\[remote "origin"\]/);
  if (at < 0) return null;
  const url = /^\s*url\s*=\s*(.+)$/m.exec(config.slice(at))?.[1]?.trim();
  return url ? repoName(url) : null;
}

/// A worktree's `.git` is a file naming its directory in the clone it was made from: the clone's own then.
function gitDir(path: string): string | null {
  try {
    const dotGit = join(path, ".git");
    if (statSync(dotGit).isDirectory()) return dotGit;
    const named = /^gitdir:\s*(.+)$/m.exec(readFileSync(dotGit, "utf8"))?.[1]?.trim();
    if (!named) return null;
    const dir = resolve(path, named);
    // <clone>/.git/worktrees/<name>: its config is the clone's.
    const parts = dir.split(sep);
    const i = parts.lastIndexOf("worktrees");
    return i > 0 ? parts.slice(0, i).join(sep) : dir;
  } catch {
    return null;
  }
}

/// `git@github.com:o/r.git`, `https://github.com/o/r.git` → `github.com/o/r`.
export function repoName(url: string): string {
  let u = url.trim().replace(/\.git$/, "").replace(/\/+$/, "");
  const scp = /^[^@/]+@([^:/]+):(.+)$/.exec(u);
  if (scp) return `${scp[1]}/${scp[2]}`;
  u = u.replace(/^[a-z+]+:\/\//i, "").replace(/^[^@/]+@/, "");
  return u;
}

export class Presets {
  /// `home`: the agent home of each workspace (its presets.json is there); `now`: the station's clock.
  readonly home: (ws: string | null) => string;
  readonly now: () => number;

  constructor(home: (ws: string | null) => string, now: () => number) {
    this.home = home;
    this.now = now;
  }

  list(ws: string | null): Preset[] {
    return readPresets(this.home(ws));
  }

  get(ws: string | null, id: string): Preset | null {
    return this.list(ws).find((p) => p.id === id) ?? null;
  }

  add(ws: string | null, input: unknown, by: string): Preset {
    const given = presetInput(input);
    const all = this.list(ws);
    const now = this.now();
    const preset: Preset = { id: `p-${randomBytes(5).toString("hex")}`, ...given, createdBy: by, createdAt: now, updatedAt: now };
    writePresets(this.home(ws), [...all, preset]);
    return preset;
  }

  put(ws: string | null, id: string, input: unknown): Preset {
    const all = this.list(ws);
    const at = all.findIndex((p) => p.id === id);
    if (at < 0) throw new NoPreset(id);
    const preset = { ...all[at]!, ...presetInput(input), updatedAt: this.now() };
    all[at] = preset;
    writePresets(this.home(ws), all);
    return preset;
  }

  delete(ws: string | null, id: string): void {
    const all = this.list(ws);
    if (!all.some((p) => p.id === id)) throw new NoPreset(id);
    writePresets(this.home(ws), all.filter((p) => p.id !== id));
  }

  /// Keeps what a chat in `workspace` is opened with: preset `id` as it is now.
  keepFor(workspace: string, ws: string | null, id: string): PresetCopy {
    const p = this.get(ws, id);
    if (p === null) throw new NoPreset(id);
    const copy: PresetCopy = { id: p.id, name: p.name, dirs: p.dirs, instructions: p.instructions };
    writeFileSync(join(workspace, COPY), `${JSON.stringify(copy, null, 2)}\n`);
    return copy;
  }
}

export class NoPreset extends Error {
  constructor(id: string) {
    super(`no preset ${id}`);
  }
}

/// What a chat whose session workspace is `workspace` was opened with, if anything.
export function presetCopyOf(workspace: string): PresetCopy | null {
  try {
    const v = JSON.parse(readFileSync(join(workspace, COPY), "utf8"));
    if (typeof v?.id !== "string" || typeof v?.name !== "string") return null;
    return { id: v.id, name: v.name, dirs: dirsOf(v.dirs), instructions: str(v.instructions) ?? "" };
  } catch {
    return null;
  }
}

/// What the agent of a chat opened with `copy` is told of it, after the station's own instructions.
export function presetInstructions(copy: PresetCopy): string {
  const dirs = copy.dirs.map((d) => `  - ${d.path}${d.repo ? ` (a clone of ${d.repo}: change it in a worktree of your own, as with any repository)` : ""}`);
  const lines = [
    "",
    "",
    `This chat was opened with the preset "${copy.name}": what people set up for this kind of work. It does not change for this chat.`,
    ...(dirs.length > 0
      ? [
          "- The directories it works with (no need to ask which; you still run in your session workspace and may go anywhere):",
          ...dirs,
          "  Before the first task, read each one's AGENTS.md and CLAUDE.md if there, and the skills in its .claude/skills and .agents/skills, as you would your own.",
        ]
      : []),
    ...(copy.instructions !== "" ? ["- What people want of chats with this preset (theirs to change, not yours):", "<preset-instructions>", copy.instructions, "</preset-instructions>"] : []),
  ];
  return lines.join("\n");
}

/// A directory to offer for a new preset: one this station has, by how many chats worked in it.
export type Candidate = { path: string; name: string; repo: string | null; chats: number; lastAt: number };

/// The directories offered as a preset is made (GET /presets `candidates`): the clones in the station's repository
/// cache, by the chats that made worktrees of them (most first, then the latest), and those other presets name. Read
/// off the main thread's way (a cache can hold many clones, each many worktrees).
export async function candidates(reposDir: string, presets: Preset[]): Promise<Candidate[]> {
  const list = async (dir: string) => readdir(dir).catch(() => [] as string[]);
  const found = await Promise.all(
    (await list(reposDir)).map(async (name): Promise<Candidate | null> => {
      const path = join(reposDir, name);
      const git = join(path, ".git");
      const at = await stat(git).catch(() => null);
      if (at === null || !at.isDirectory()) return null;
      let lastAt = at.mtimeMs;
      const sessions = new Set<string>();
      for (const t of await list(join(git, "worktrees"))) {
        const file = join(git, "worktrees", t, "gitdir");
        const [where, when] = await Promise.all([readFile(file, "utf8").catch(() => ""), stat(file).catch(() => null)]);
        const session = /[/\\]sessions[/\\][^/\\]+[/\\]([^/\\]+)[/\\]workspace[/\\]/.exec(where)?.[1];
        if (session) sessions.add(session);
        if (when) lastAt = Math.max(lastAt, when.mtimeMs);
      }
      const config = await readFile(join(git, "config"), "utf8").catch(() => "");
      return { path, name, repo: originIn(config), chats: sessions.size, lastAt: Math.floor(lastAt) };
    }),
  );
  const out = new Map<string, Candidate>();
  for (const c of found) if (c !== null) out.set(c.path, c);
  for (const p of presets) for (const d of p.dirs) if (!out.has(d.path)) out.set(d.path, { path: d.path, name: basename(d.path), repo: d.repo, chats: 0, lastAt: p.updatedAt });
  return [...out.values()].sort((a, b) => b.chats - a.chats || b.lastAt - a.lastAt || a.name.localeCompare(b.name));
}
