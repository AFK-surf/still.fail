// Presets: what a chat starts knowing, chosen as it is opened (docs/presets.md). A preset names the directories its
// chats work with and what people want of them there; it does not bind the agent to them (it runs in its own session
// workspace as every chat does). A workspace's presets are its agent home's presets.json; a chat opened with one keeps a
// copy of it in its session workspace (`.stillfail-preset.json`), so a preset changed later changes none of the chats
// already opened with it.
import { type Dirent, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { readFile, readdir, stat, writeFile } from "node:fs/promises";
import { basename, isAbsolute, join, resolve, sep } from "node:path";
import { homedir } from "node:os";
import { randomBytes } from "node:crypto";
import { protectedPlace } from "../drive/fs.ts";
import { SKILL_HOMES } from "./agent-home.ts";

/// A directory a preset works with: a path, and the repository it is a clone of (its origin), if one. `station`
/// (its address) and `stationName`: another station of the workspace's it is on; none: the station the preset is on.
/// In a chat's copy, `elsewhere`: the station it is on by name, where that is not the chat's.
export type PresetDir = { path: string; repo: string | null; station?: string; stationName?: string; elsewhere?: string; guides?: Guide[]; skills?: string[] };

/// A folder's instructions for agents as the chat was opened with them (its AGENTS.md, its CLAUDE.md): the file, what
/// it said (its start, where it is long), whether that is all of it.
export type Guide = { file: string; text: string; whole: boolean };

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

/// What a chat was opened with: the preset as it was then, each folder's `elsewhere` said where it is not the chat's
/// station's.
export type PresetCopy = { id: string; name: string; dirs: PresetDir[]; instructions: string };

const FILE = "presets.json";
const COPY = ".stillfail-preset.json";
const NAME_MAX = 60;
const INSTRUCTIONS_MAX = 20_000;
const DIRS_MAX = 20;

const str = (v: unknown): string | null => (typeof v === "string" ? v : null);

function dirsOf(v: unknown): PresetDir[] {
  if (!Array.isArray(v)) return [];
  return v.flatMap((d) => {
    if (typeof d?.path !== "string") return [];
    const dir: PresetDir = { path: d.path, repo: str(d.repo) };
    for (const k of ["station", "stationName", "elsewhere"] as const) if (typeof d[k] === "string" && d[k] !== "") dir[k] = d[k];
    if (Array.isArray(d.guides)) dir.guides = d.guides.filter((g: any) => typeof g?.file === "string" && typeof g?.text === "string").map((g: any) => ({ file: g.file, text: g.text, whole: g.whole !== false }));
    if (Array.isArray(d.skills)) dir.skills = d.skills.filter((n: unknown) => typeof n === "string");
    return [dir];
  });
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
    // (another station's, as the app read it there: taken as said, not looked for here)
    const at = typeof d === "object" && d !== null ? str((d as { station?: unknown }).station) : null;
    if (at !== null && at !== "") {
      const stationName = str((d as { stationName?: unknown }).stationName) ?? "";
      if (!dirs.some((x) => x.path === given && x.station === at)) dirs.push({ path: given, repo: str((d as { repo?: unknown }).repo), station: at, ...(stationName ? { stationName } : {}) });
      continue;
    }
    const path = expand(given.trim());
    if (!isDirectory(path)) throw new Error(`${given} is no directory on this station`);
    if (dirs.some((x) => x.path === path && x.station === undefined)) continue;
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
  } catch (e) {
    // (one macOS guards, picked through still.fail Helper: the station is not let look, but it is there)
    const code = (e as NodeJS.ErrnoException).code;
    return code === "EPERM" || code === "EACCES";
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
    // (its other stations' folders said to be there)
    const dirs = p.dirs.map(({ station, stationName, ...d }) => (station === undefined ? d : { ...d, elsewhere: stationName || station }));
    return keepCopy(workspace, { id: p.id, name: p.name, dirs, instructions: p.instructions });
  }
}

export class NoPreset extends Error {
  constructor(id: string) {
    super(`no preset ${id}`);
  }
}

/// Keeps `copy` as what a chat in `workspace` is opened with.
/// The files a folder's instructions for agents are in, as Claude Code and Codex read them in their own directory.
const GUIDES = ["AGENTS.md", "CLAUDE.md", join(".claude", "CLAUDE.md")];
/// What of a folder's instruction file the chat is told at most (the rest is read there).
const GUIDE_MOST = 16 * 1024;

/// Keeps `copy` as what a chat in `workspace` is opened with. Its folders on this machine are made the chat's as a
/// runtime opened in them would have them (neither reads them where it does not run): their instruction files kept
/// with the copy (told with the station's instructions), their skills linked into the chat's workspace under both
/// runtimes' skill directories, so each finds them as its own.
export function keepCopy(workspace: string, copy: PresetCopy): PresetCopy {
  const linked = new Set<string>();
  const dirs = copy.dirs.map((d) => {
    if (d.elsewhere !== undefined) return d;
    const guides = GUIDES.flatMap((file): Guide[] => {
      try {
        const bytes = readFileSync(join(d.path, file));
        const whole = bytes.length <= GUIDE_MOST;
        return [{ file, text: bytes.subarray(0, GUIDE_MOST).toString("utf8").trim(), whole }];
      } catch {
        return [];
      }
    });
    const skills: string[] = [];
    for (const home of SKILL_HOMES) {
      let names: string[] = [];
      try {
        names = readdirSync(join(d.path, home));
      } catch {}
      for (const n of names) {
        const from = join(d.path, home, n);
        if (!existsSync(join(from, "SKILL.md"))) continue;
        // (one of the same name already linked: this folder's under its folder's name before it)
        const name = linked.has(n) ? `${basename(d.path)}-${n}` : n;
        if (linked.has(name)) continue;
        linked.add(name);
        skills.push(name);
        for (const to of SKILL_HOMES) {
          mkdirSync(join(workspace, to), { recursive: true });
          try {
            symlinkSync(from, join(workspace, to, name), "dir");
          } catch {}
        }
      }
    }
    return { ...d, ...(guides.length > 0 ? { guides } : {}), ...(skills.length > 0 ? { skills } : {}) };
  });
  const kept = { ...copy, dirs };
  writeFileSync(join(workspace, COPY), `${JSON.stringify(kept, null, 2)}\n`);
  return kept;
}

/// A preset of another station's as the asking app gives it (POST /sessions `presetCopy`: what it read there, each
/// folder's `elsewhere` where it is not this station's), taken as said.
export function presetCopyInput(v: unknown): PresetCopy {
  const o = (v ?? {}) as Record<string, unknown>;
  const name = (str(o.name) ?? "").trim();
  if (name === "" || Array.from(name).length > NAME_MAX) throw new Error("presetCopy: a preset needs a name");
  const dirs = dirsOf(o.dirs).slice(0, DIRS_MAX);
  const instructions = (str(o.instructions) ?? "").slice(0, INSTRUCTIONS_MAX);
  return { id: str(o.id) ?? "", name, dirs: dirs.map(({ station: _s, stationName: _n, guides: _g, skills: _k, ...d }) => d), instructions };
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
  const dirs = copy.dirs.map((d) =>
    d.elsewhere === undefined
      ? `  - ${d.path}${d.repo ? ` (a clone of ${d.repo}: change it in a worktree of your own, as with any repository)` : ""}`
      : d.repo
        ? `  - ${d.repo}: this station's clone of it (in the repository cache; clone it there if it is not yet), a worktree of your own to change it (on ${d.elsewhere} it is ${d.path})`
        : `  - ${d.path} on station ${d.elsewhere}: read it there with the station tools (station_task, station_file), not copied here`,
  );
  const lines = [
    "",
    "",
    `This chat was opened with the preset "${copy.name}": what people set up for this kind of work. It does not change for this chat.`,
    ...(dirs.length > 0
      ? [
          "- The directories it works with (no need to ask which; you still run in your session workspace and may go anywhere):",
          ...dirs,
          ...(copy.dirs.some((d) => (d.skills ?? []).length > 0) ? [`  Their skills are linked into your workspace (.claude/skills, .agents/skills): ${copy.dirs.flatMap((d) => d.skills ?? []).join(", ")}; use them as your own.`] : []),
          ...copy.dirs.flatMap((d) =>
            (d.guides ?? []).flatMap((g) => [
              `<folder-instructions path="${join(d.path, g.file)}">`,
              g.text,
              ...(g.whole ? [] : [`(only its start: read the rest there)`]),
              "</folder-instructions>",
            ]),
          ),
          ...(copy.dirs.some((d) => d.elsewhere !== undefined) ? ["  For those on other stations, read their AGENTS.md, CLAUDE.md and skills there before the first task."] : []),
        ]
      : []),
    ...(copy.instructions !== "" ? ["- What people want of chats with this preset (theirs to change, not yours):", "<preset-instructions>", copy.instructions, "</preset-instructions>"] : []),
  ];
  return lines.join("\n");
}

/// A directory to offer for a new preset: one this station has, by how many chats worked in it.
/// `where`: where it is as people read it (`~/code/app`); `cached`: only the station's cache has it (no checkout of the
/// person's on the machine).
/// `icon`: its own picture, found where projects keep one (repoIcon), as a data URL.
export type Candidate = { path: string; name: string; repo: string | null; chats: number; lastAt: number; where?: string; cached?: boolean; icon?: string };

/// The directories offered as a preset is made (GET /presets `candidates`): the clones in the station's repository
/// cache and the repositories found on the machine (`found`, RepoIndex), the ones its chats made worktrees of first
/// (most, then the latest), the rest by when they last changed; and those other presets name. Read off the main
/// thread's way (a cache can hold many clones, each many worktrees).
export async function candidates(reposDir: string, presets: Preset[], found: Candidate[] = []): Promise<Candidate[]> {
  const list = async (dir: string) => readdir(dir).catch(() => [] as string[]);
  const cached = await Promise.all(
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
      const icon = await cachedIcon(path, lastAt);
      return { path, name, repo: originIn(config), chats: sessions.size, lastAt: Math.floor(lastAt), ...(icon ? { icon } : {}) };
    }),
  );
  // One a repository (by its origin), a folder of no repository by its path: the person's own checkout where the
  // machine has one, the cache's clone (said as its repository, not its path) where it has not; the chats that worked
  // in the cache's clone counted on it either way.
  const out = new Map<string, Candidate>();
  const keyOf = (c: Candidate) => c.repo ?? c.path;
  for (const c of found) if (!out.has(keyOf(c))) out.set(keyOf(c), { ...c, where: shortPath(c.path) });
  for (const c of cached) {
    if (c === null) continue;
    const mine = out.get(keyOf(c));
    if (mine) out.set(keyOf(c), { ...mine, chats: mine.chats + c.chats, lastAt: Math.max(mine.lastAt, c.lastAt), ...(mine.icon || !c.icon ? {} : { icon: c.icon }) });
    else out.set(keyOf(c), { ...c, cached: true, where: c.repo ?? shortPath(c.path) });
  }
  for (const p of presets) for (const d of p.dirs) if (!out.has(d.repo ?? d.path)) out.set(d.repo ?? d.path, { path: d.path, name: basename(d.path), repo: d.repo, chats: 0, lastAt: p.updatedAt, where: shortPath(d.path) });
  return [...out.values()].sort((a, b) => b.chats - a.chats || b.lastAt - a.lastAt || a.name.localeCompare(b.name));
}

/// What a project's picture is called where it keeps one (its site's icons, its app's icon, its logo).
const ICON_NAMES = /^(favicon|apple-touch-icon|app-icon|appicon|icon|logo)([-_.@][\w@.-]*)?\.(png|jpe?g)$/i;
/// Where projects keep their picture: the root, a site's public and static folders, assets, docs, .github, an app's.
const ICON_PLACES = ["", "public", "static", "assets", "images", "img", "icons", "docs", ".github", "resources", "web/public", "app/public", "site/public", "src/assets", "public/icons", "assets/icons", "static/img", "docs/assets"];
/// A picture larger than this is no icon (a screenshot, a banner): the repository goes without.
const ICON_MOST_BYTES = 24 * 1024;

/// A repository's own picture, where projects keep one (ICON_PLACES: a listing each, not a walk of its tree), as a data
/// URL: the best named (a touch icon first), then the nearest the root, then the smallest; null for none.
export async function repoIcon(root: string): Promise<string | null> {
  const found: { path: string; rank: number; depth: number; size: number; type: string }[] = [];
  await Promise.all(
    ICON_PLACES.map(async (place, depth) => {
      const dir = join(root, place);
      for (const e of await readdir(dir, { withFileTypes: true }).catch(() => [])) {
        const m = e.isFile() ? ICON_NAMES.exec(e.name) : null;
        if (!m) continue;
        const at = join(dir, e.name);
        const size = (await stat(at).catch(() => null))?.size ?? 0;
        if (size === 0 || size > ICON_MOST_BYTES) continue;
        // (the touch icon first: square and large; a favicon is often 16 or 32 across, blurred where it is drawn)
        const rank = ["apple-touch-icon", "app-icon", "appicon", "icon", "favicon", "logo"].indexOf(m[1]!.toLowerCase());
        found.push({ path: at, rank, depth, size, type: /png$/i.test(e.name) ? "png" : "jpeg" });
      }
    }),
  );
  found.sort((a, b) => a.rank - b.rank || a.depth - b.depth || a.size - b.size);
  const best = found[0];
  if (!best) return null;
  const bytes = await readFile(best.path).catch(() => null);
  return bytes ? `data:image/${best.type};base64,${bytes.toString("base64")}` : null;
}

/// The cache's clones' pictures as last looked for, by path and when the clone last changed (looked for again then).
const icons = new Map<string, { at: number; icon: string | null }>();
async function cachedIcon(path: string, at: number): Promise<string | null> {
  const held = icons.get(path);
  if (held && held.at === at) return held.icon;
  const icon = await repoIcon(path);
  icons.set(path, { at, icon });
  return icon;
}

/// A path as people read it: under the home, `~/…`.
export function shortPath(path: string): string {
  const home = homedir();
  return path === home ? "~" : path.startsWith(home + sep) ? `~${path.slice(home.length)}` : path;
}

/// Where on the machine repositories are looked for: under its home, so many levels down.
const INDEX_DEPTH = 4;
/// At most so many directories looked into in one pass (a home with a huge tree is not walked all of it).
const INDEX_DIRS_MOST = 20_000;
/// A pass is this old before the next one (it runs while what is held is answered).
const INDEX_FRESH_MS = 10 * 60 * 1000;
/// Not looked into: what holds no repositories of a person's, what is huge, and what macOS asks the person before an
/// app reads (a dialog on that machine's screen): the desktop, documents and downloads, and the libraries.
const INDEX_SKIPPED = new Set(["node_modules", "Library", "Applications", "Pictures", "Movies", "Music", "Public", "Desktop", "Documents", "Downloads", "Pods", "target", "dist", "build", "vendor", "venv"]);

/// The repositories on the machine (directories with a `.git`), found by walking its home a few levels down, so a
/// preset's folders are picked rather than typed. Kept in `file` (the station's data directory) and walked again when
/// there is none or the last is old, in the background: what is held is answered meanwhile (none before the first pass
/// ends: a home can take long to walk). What macOS protects is not looked into (drive/fs.ts protectedPlace: Documents,
/// a disk mounted anywhere, OrbStack's NFS in the home among them): opening one waits on a dialog on that machine's
/// screen for as long as nobody answers.
export class RepoIndex {
  readonly roots: () => string[];
  readonly file: () => string;
  readonly now: () => number;
  /// Directories it never looks into (the station's own data: its sessions' worktrees are its cache's clones).
  readonly besides: () => string[];
  /// What a directory holds; whether it is one the station does not open itself (protectedPlace).
  readonly list: (dir: string) => Promise<Dirent[]>;
  readonly guarded: (dir: string) => boolean;
  #held: { at: number; repos: Candidate[] } | null = null;
  #read = false;
  #walking: Promise<void> | null = null;

  constructor(o: {
    roots: () => string[];
    file: () => string;
    now: () => number;
    besides?: () => string[];
    list?: (dir: string) => Promise<Dirent[]>;
    guarded?: (dir: string) => boolean;
  }) {
    this.roots = o.roots;
    this.file = o.file;
    this.now = o.now;
    this.besides = o.besides ?? (() => []);
    this.list = o.list ?? ((dir) => readdir(dir, { withFileTypes: true }));
    this.guarded = o.guarded ?? ((dir) => protectedPlace(dir) !== null);
  }

  /// The repositories found, as the last pass found them (none before the first ends); a pass begun when there is none
  /// or that is old, `walked` told as it ends.
  async repos(walked: () => void = () => {}): Promise<Candidate[]> {
    if (!this.#read) {
      this.#read = true;
      try {
        const kept = JSON.parse(await readFile(this.file(), "utf8"));
        if (typeof kept?.at === "number" && Array.isArray(kept?.repos)) this.#held ??= { at: kept.at, repos: kept.repos };
      } catch {}
    }
    if (this.#walking === null && (this.#held === null || this.now() - this.#held.at > INDEX_FRESH_MS)) void this.walk().then(walked);
    return this.#held?.repos ?? [];
  }

  /// One pass, the one under way if there is.
  walk(): Promise<void> {
    this.#walking ??= this.#walk().finally(() => (this.#walking = null));
    return this.#walking;
  }

  async #walk(): Promise<void> {
    const found: Candidate[] = [];
    const skip = new Set(this.besides().map((p) => resolve(p)));
    let looked = 0;
    const into = async (dir: string, depth: number): Promise<void> => {
      if (looked++ >= INDEX_DIRS_MOST || skip.has(dir)) return;
      if (this.guarded(dir)) return;
      const entries = await this.list(dir).catch(() => []);
      if (entries.some((e) => e.name === ".git")) {
        const git = join(dir, ".git");
        const [config, head] = await Promise.all([readFile(join(git, "config"), "utf8").catch(() => ""), stat(join(git, "index")).catch(() => stat(git).catch(() => null))]);
        const icon = await repoIcon(dir);
        found.push({ path: dir, name: basename(dir), repo: originIn(config), chats: 0, lastAt: Math.floor(head?.mtimeMs ?? 0), ...(icon ? { icon } : {}) });
        return;
      }
      if (depth >= INDEX_DEPTH) return;
      for (const e of entries) {
        if (!e.isDirectory() || e.name.startsWith(".") || INDEX_SKIPPED.has(e.name)) continue;
        await into(join(dir, e.name), depth + 1);
      }
    };
    for (const root of this.roots()) await into(resolve(root), 0);
    this.#held = { at: this.now(), repos: found };
    try {
      await writeFile(this.file(), `${JSON.stringify(this.#held)}\n`);
    } catch {}
  }
}
