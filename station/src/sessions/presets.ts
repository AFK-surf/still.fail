// Presets: what a chat starts knowing, chosen as it is opened. A preset names the directories its
// chats work with and what people want of them there; it does not bind the agent to them (it runs in its own session
// workspace as every chat does). A workspace's presets are its agent home's presets.json; a chat opened with one keeps a
// copy of it in its session workspace (`.stillfail-preset.json`), so a preset changed later changes none of the chats
// already opened with it.
//
// A preset is its person's (`owner`), carried by that person's devices to every station of the workspace (the user,
// 2026-11-14): a device keeps its person's records, reads each station's (GET /presets/kept), keeps the newer of each
// (client/core-ts/src/preset-records.ts `newerRecord`) and brings a station what it lacks (PUT /presets/kept). The
// stations do not bring them level with each other. A station keeps and gives what it is brought, as it was brought;
// it changes a record itself only for an app from before (POST, PUT, DELETE /presets), counting the change (`rev`), a
// deletion kept as a record of its own (`gone`) so that it is not brought back. Every live record it keeps in a
// workspace is its agents' (chat_create `preset`) and opens a chat here, whoever's and wherever it was made; an app
// from before is listed only those made here (`home`), so that one carried to three stations is not shown three times.
import { type Dirent, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { readFile, readdir, stat, writeFile } from "node:fs/promises";
import { basename, isAbsolute, join, resolve, sep } from "node:path";
import { homedir } from "node:os";
import { randomBytes } from "node:crypto";
import { protectedPlace } from "../drive/fs.ts";
import { SKILL_HOMES } from "./agent-home.ts";
import { type Lang, tr } from "../ops/i18n.ts";
import {
  DIRS_MAX,
  type GoneRecord,
  INSTRUCTIONS_MAX,
  type KeptRecord,
  NAME_MAX,
  type PresetRecord,
  canonical,
  isGone,
  modelOf,
  newerRecord,
  recordOf,
  stationsOf,
} from "../../../client/core-ts/src/preset-records.ts";

/// A directory a preset works with: a path, and the repository it is a clone of (its origin), if one. `station`: the
/// station it is on (its address: what a device carried says of every folder, what the app says of another station's);
/// none: this station (one made here by an app from before). `stationName`: that station's name as an app from before
/// said it (shown by those apps; not carried, the name is looked up where it is told).
/// In a chat's copy, `elsewhere`: the station it is on by name, where that is not the chat's.
export type PresetDir = { path: string; repo: string | null; station?: string; stationName?: string; elsewhere?: string; guides?: Guide[]; skills?: string[] };

/// A folder's instructions for agents as the chat was opened with them (its AGENTS.md, its CLAUDE.md): the file, what
/// it said (its start, where it is long), whether that is all of it.
export type Guide = { file: string; text: string; whole: boolean };

/// A model configuration a preset runs with; absent when unrestricted ("不限模型").
export type PresetModel = {
  model: string;
  runtime?: string;
  effort?: string;
  fast?: boolean;
  context?: number;
  profile?: string;
  profiles?: string[];
};

export type Preset = {
  id: string;
  name: string;
  dirs: PresetDir[];
  /// What people want of its chats, as they wrote it.
  instructions: string;
  /// True when auto-allocating across all eligible online stations; absent when unrestricted or pinned/subset.
  autoStation?: boolean;
  /// Fixed station id/address when pinned to one station; absent when unrestricted or auto-allocated.
  station?: string;
  /// Station ids/addresses to auto-allocate among when a subset is checked; absent when unrestricted or all stations.
  stations?: string[];
  /// Model configuration for chats opened with this preset; absent when unrestricted.
  model?: PresetModel;
  createdBy: string;
  createdAt: number;
  updatedAt: number;
  /// The `sub` of the person it is of ("" on one from before, until their device says it).
  owner: string;
  /// How many times it was changed, from 1 (one from before: 1).
  rev: number;
  /// The id of the station it was made on (one from before: this station's).
  home: string;
};

/// A preset deleted, as kept so that it is not brought back (preset-records.ts).
export type PresetGone = GoneRecord;

/// What a chat was opened with: the preset as it was then, each folder's `elsewhere` said where it is not the chat's
/// station's.
export type PresetCopy = { id: string; name: string; dirs: PresetDir[]; instructions: string; model?: PresetModel; stations?: string[] };

/// What a preset binds its chats to, as the page shows it unchangeable (the user, 2026-11-13: 「锁住，绑定了的不能改」):
/// the model it names (and its runtime, where it names one), and the stations (ids or addresses) they may be opened
/// on. Where a chat asked for differs, why it is not opened, said with the way to have it (edit the preset, or open it
/// with none); null: it may be. How it runs that model (effort, accounts, Fast) only the app holds to: a level or an
/// account no longer offered here would otherwise make the preset open nothing. `here`: this station's id (null: none
/// known, the stations not held to).
export function presetRefusal(
  p: { name: string; model?: PresetModel; station?: string; stations?: string[] },
  here: string | null,
  asked: { runtime: string; model: string | null },
  lang: Lang,
): string | null {
  const m = p.model;
  if (m !== undefined && (asked.model !== m.model || (m.runtime !== undefined && m.runtime !== asked.runtime))) {
    return tr(lang, "station.presets.modelBound", { preset: p.name, model: m.model });
  }
  const named = p.station !== undefined ? [p.station] : (p.stations ?? []);
  if (here !== null && named.length > 0 && !named.some((s) => s === here || s.endsWith(`/${here}`))) {
    return tr(lang, "station.presets.stationBound", { preset: p.name });
  }
  return null;
}

const FILE = "presets.json";
const COPY = ".stillfail-preset.json";
/// The deleted presets a workspace's file keeps at most, the latest: a deletion is forgotten only after this many
/// later ones, and only a device or a station that held the preset live all that while (a person's presets are made by
/// hand, tens of them) could bring it back then.
export const GONE_MOST = 500;
/// The live presets a workspace's file keeps at most: one more a device brings is refused.
export const LIVE_MOST = 1000;

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

function presetModelOf(o: Record<string, unknown>): PresetModel | undefined {
  return modelOf(o.model) ?? (typeof o.models === "object" && o.models !== null ? modelOf((o.models as Record<string, unknown>).lead) : undefined);
}

/// A preset as presets.json says it, `me` this station's id: one from before (no `rev`) is changed once, made here, of
/// nobody said yet.
function presetOf(v: any, me: string): Preset | null {
  if (typeof v?.id !== "string" || typeof v?.name !== "string") return null;
  const st = stationsOf(v);
  const model = presetModelOf(v);
  return {
    id: v.id,
    name: v.name,
    dirs: dirsOf(v.dirs),
    instructions: str(v.instructions) ?? "",
    ...(st.autoStation ? { autoStation: true } : {}),
    ...(st.station ? { station: st.station } : {}),
    ...(st.stations ? { stations: st.stations } : {}),
    ...(model ? { model } : {}),
    createdBy: str(v.createdBy) ?? "",
    createdAt: typeof v.createdAt === "number" ? v.createdAt : 0,
    updatedAt: typeof v.updatedAt === "number" ? v.updatedAt : 0,
    owner: str(v.owner) ?? "",
    rev: Number.isSafeInteger(v.rev) && v.rev >= 1 ? v.rev : 1,
    home: str(v.home) || me,
  };
}

function goneOf(v: any): PresetGone | null {
  if (v?.gone !== true || typeof v?.id !== "string" || !Number.isSafeInteger(v?.rev)) return null;
  return { id: v.id, owner: str(v.owner) ?? "", rev: v.rev, gone: true, updatedAt: typeof v.updatedAt === "number" ? v.updatedAt : 0 };
}

/// What a workspace's presets.json keeps: its live presets and its deleted ones.
export type PresetsFile = { presets: Preset[]; gone: PresetGone[] };

/// The presets of the workspace whose agent home is `home`, as written (one from before as presetOf reads it, the file
/// not written for it); none when there is no file yet. `me`: this station's id.
export function readPresetsFile(home: string, me = ""): PresetsFile {
  try {
    const raw = JSON.parse(readFileSync(join(home, FILE), "utf8"));
    const presets: Preset[] = (Array.isArray(raw?.presets) ? raw.presets : []).flatMap((p: unknown) => presetOf(p, me) ?? []);
    const gone: PresetGone[] = (Array.isArray(raw?.gone) ? raw.gone : []).flatMap((g: unknown) => goneOf(g) ?? []);
    return { presets, gone };
  } catch {
    return { presets: [], gone: [] };
  }
}

/// The live presets of the workspace whose agent home is `home` (readPresetsFile).
export function readPresets(home: string, me = ""): Preset[] {
  return readPresetsFile(home, me).presets;
}

/// The latest GONE_MOST of `gone`, by when each was deleted (then the higher `rev`, then the id: the same whatever their
/// order).
function latestGone(gone: PresetGone[]): PresetGone[] {
  if (gone.length <= GONE_MOST) return gone;
  const order = (a: PresetGone, b: PresetGone) => b.updatedAt - a.updatedAt || b.rev - a.rev || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
  const kept = new Set([...gone].sort(order).slice(0, GONE_MOST));
  return gone.filter((g) => kept.has(g));
}

function writePresets(home: string, presets: Preset[], gone: PresetGone[]): void {
  mkdirSync(home, { recursive: true });
  const path = join(home, FILE);
  const temp = `${path}.${randomBytes(4).toString("hex")}`;
  // (the deleted ones beside the live, which is all a reader from before reads)
  writeFileSync(temp, `${JSON.stringify({ presets, gone: latestGone(gone) }, null, 2)}\n`); // sync: read, changed and written in one step that must not be split
  renameSync(temp, path);
}

/// What a preset is said to be (POST, PUT /presets): its name and instructions trimmed, its directories each a
/// directory on this machine (`~` its home), named once each, plus optional station policy and model configuration.
export function presetInput(v: unknown): {
  name: string;
  dirs: PresetDir[];
  instructions: string;
  autoStation?: boolean;
  station?: string;
  stations?: string[];
  model?: PresetModel;
} {
  const o = (v ?? {}) as Record<string, unknown>;
  const name = (str(o.name) ?? "").trim();
  if (name === "") throw new Error("a preset needs a name");
  if (Array.from(name).length > NAME_MAX) throw new Error(`a preset's name is ${NAME_MAX} characters at most`);
  const instructions = (str(o.instructions) ?? "").trim();
  if (instructions.length > INSTRUCTIONS_MAX) throw new Error("its instructions are too long");
  const rawDirs = o.dirs === undefined || o.dirs === null ? [] : o.dirs;
  if (!Array.isArray(rawDirs)) throw new Error("dirs: a list of directories");
  const dirs: PresetDir[] = [];
  for (const d of rawDirs) {
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
  const st = stationsOf(o);
  const model = presetModelOf(o);
  return {
    name,
    dirs,
    instructions,
    ...(st.autoStation ? { autoStation: true } : {}),
    ...(st.station ? { station: st.station } : {}),
    ...(st.stations ? { stations: st.stations } : {}),
    ...(model ? { model } : {}),
  };
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
export function originIn(config: string): string | null {
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

/// Where the presets are: this station's id (null: none yet), the workspace a `ws` of the Presets' is (null for the
/// home one: the home one's id), and the name this station knows another station of its workspaces by (null: none).
export type PresetsPlace = {
  station?: () => string | null;
  workspace?: (ws: string | null) => string | null;
  stationName?: (id: string) => string | null;
};

/// Who asks: their `sub` and email, as their credential says.
export type Asker = { sub: string; email: string };

/// What PUT /presets/kept answers: what this station keeps now of each id asked (in the order first asked), and each
/// record not taken with why (`at`: its place in what was given).
export type Carried = { records: KeptRecord[]; refused: { at: number; id: string | null; error: string }[]; changed: boolean };

const sameEmail = (a: string, b: string) => a !== "" && a.toLowerCase() === b.toLowerCase();

export class Presets {
  /// `home`: the agent home of each workspace (its presets.json is there); `now`: the station's clock.
  readonly home: (ws: string | null) => string;
  readonly now: () => number;
  readonly place: PresetsPlace;

  constructor(home: (ws: string | null) => string, now: () => number, place: PresetsPlace = {}) {
    this.home = home;
    this.now = now;
    this.place = place;
  }

  /// This station's id ("" before it has one).
  me(): string {
    return this.place.station?.() ?? "";
  }

  /// Whether a folder's `station` (an address, or an id) is this station.
  isHere(station: string): boolean {
    const me = this.me();
    return me !== "" && (station === me || station.endsWith(`/${me}`));
  }

  /// The name a folder's station is told by: as this station knows it, else as an app from before said it, else its id.
  nameOf(station: string, said?: string): string {
    const id = station.slice(station.lastIndexOf("/") + 1);
    return this.place.stationName?.(id) || said || id;
  }

  /// This station's address in workspace `ws` (its id alone where the workspace is not known).
  #address(ws: string | null): string {
    const w = this.place.workspace?.(ws) ?? ws;
    return w ? `${w}/${this.me()}` : this.me();
  }

  #file(ws: string | null): PresetsFile {
    return readPresetsFile(this.home(ws), this.me());
  }

  /// Every live preset this station keeps in `ws`, whoever's and wherever made: what its agents and chats open with.
  list(ws: string | null): Preset[] {
    return this.#file(ws).presets;
  }

  /// Those made here, as an app from before is listed them (GET /presets).
  listed(ws: string | null): Preset[] {
    const me = this.me();
    return this.list(ws).filter((p) => p.home === me);
  }

  get(ws: string | null, id: string): Preset | null {
    return this.list(ws).find((p) => p.id === id) ?? null;
  }

  /// A preset made by an app from before (POST /presets): `by` the email of who made it, `owner` their sub.
  add(ws: string | null, input: unknown, by: string, owner = ""): Preset {
    const given = presetInput(input);
    const file = this.#file(ws);
    const now = this.now();
    const preset: Preset = { id: `p-${randomBytes(5).toString("hex")}`, ...given, createdBy: by, createdAt: now, updatedAt: now, owner, rev: 1, home: this.me() };
    writePresets(this.home(ws), [...file.presets, preset], file.gone);
    return preset;
  }

  /// Whose a preset is once `who` changes it: its owner, or, one from before of nobody said yet that they made, theirs.
  #ownerAfter(prev: Preset, who: Asker | undefined): string {
    if (prev.owner !== "" || who === undefined || who.sub === "") return prev.owner;
    return sameEmail(prev.createdBy, who.email) ? who.sub : "";
  }

  /// A preset changed by an app from before (PUT /presets/:id): one change more.
  put(ws: string | null, id: string, input: unknown, who?: Asker): Preset {
    const file = this.#file(ws);
    const all = file.presets;
    const at = all.findIndex((p) => p.id === id);
    if (at < 0) throw new NoPreset(id);
    const prev = all[at]!;
    const preset: Preset = {
      id: prev.id, ...presetInput(input), createdBy: prev.createdBy, createdAt: prev.createdAt, updatedAt: this.now(),
      owner: this.#ownerAfter(prev, who), rev: prev.rev + 1, home: prev.home,
    };
    all[at] = preset;
    writePresets(this.home(ws), all, file.gone);
    return preset;
  }

  /// A preset deleted by an app from before (DELETE /presets/:id): kept deleted, one change more.
  delete(ws: string | null, id: string, who?: Asker): void {
    const file = this.#file(ws);
    const prev = file.presets.find((p) => p.id === id);
    if (prev === undefined) throw new NoPreset(id);
    const gone: PresetGone = { id, owner: this.#ownerAfter(prev, who), rev: prev.rev + 1, gone: true, updatedAt: this.now() };
    writePresets(this.home(ws), file.presets.filter((p) => p.id !== id), [...file.gone.filter((g) => g.id !== id), gone]);
  }

  /// A preset as it is carried (preset-records.ts): every folder naming its station (this station's address where it
  /// names none), nothing of it that is not of the record (an app's `stationName`).
  record(ws: string | null, p: Preset): PresetRecord {
    const here = this.#address(ws);
    return {
      id: p.id,
      name: p.name,
      dirs: p.dirs.map((d) => ({ path: d.path, repo: d.repo, station: d.station ?? here })),
      instructions: p.instructions,
      ...(p.autoStation ? { autoStation: true } : {}),
      ...(p.station ? { station: p.station } : {}),
      ...(p.stations ? { stations: p.stations } : {}),
      ...(p.model ? { model: p.model } : {}),
      createdBy: p.createdBy,
      createdAt: p.createdAt,
      updatedAt: p.updatedAt,
      owner: p.owner,
      rev: p.rev,
      home: p.home,
    };
  }

  /// Every record of `ws` kept here, each the newer where an id is both live and deleted (a file put together by hand).
  #records(ws: string | null): Map<string, KeptRecord> {
    const file = this.#file(ws);
    const out = new Map<string, KeptRecord>();
    for (const r of [...file.presets.map((p) => this.record(ws, p)), ...file.gone]) {
      const was = out.get(r.id);
      out.set(r.id, was === undefined ? r : newerRecord(was, r));
    }
    return out;
  }

  /// Whether `r` is `who`'s: theirs by its owner, or one from before (no owner yet) that they made.
  static theirs(r: KeptRecord, who: Asker): boolean {
    if (who.sub === "") return false;
    if (r.owner === who.sub) return true;
    return r.owner === "" && !isGone(r) && sameEmail(r.createdBy, who.email);
  }

  /// What GET /presets/kept answers: `who`'s records kept here, deleted ones too.
  kept(ws: string | null, who: Asker): KeptRecord[] {
    return [...this.#records(ws).values()].filter((r) => Presets.theirs(r, who));
  }

  /// What GET /presets/others answers: everyone else's live records kept here.
  others(ws: string | null, who: Asker): PresetRecord[] {
    return [...this.#records(ws).values()].filter((r): r is PresetRecord => !isGone(r) && !Presets.theirs(r, who));
  }

  /// Records `who`'s device brings (PUT /presets/kept): each checked as both sides check one (recordOf), taken only
  /// where it is theirs (its owner their sub; an id kept here only where that is theirs too, or a deletion of nobody
  /// said) and newer than what is kept, as it was brought. Answers what is kept now of each id asked.
  carry(ws: string | null, who: Asker, given: unknown[]): Carried {
    const all = this.#records(ws);
    const out: Carried = { records: [], refused: [], changed: false };
    const asked: string[] = [];
    let live = [...all.values()].filter((r) => !isGone(r)).length;
    given.forEach((raw, at) => {
      const id = typeof (raw as { id?: unknown } | null)?.id === "string" ? ((raw as { id: string }).id) : null;
      let r: KeptRecord;
      try {
        r = recordOf(raw);
      } catch (e) {
        out.refused.push({ at, id, error: (e as Error).message });
        return;
      }
      if (who.sub === "" || r.owner !== who.sub) {
        out.refused.push({ at, id, error: "a record is taken only from its owner's devices (owner: their sub)" });
        return;
      }
      const was = all.get(r.id);
      if (was !== undefined && was.owner !== "" && was.owner !== who.sub) {
        out.refused.push({ at, id, error: `preset ${r.id} is someone else's` });
        return;
      }
      if (was !== undefined && was.owner === "" && !isGone(was) && !Presets.theirs(was, who)) {
        out.refused.push({ at, id, error: `preset ${r.id} was made by someone else` });
        return;
      }
      if (!asked.includes(r.id)) asked.push(r.id);
      if (was !== undefined && (newerRecord(was, r) === was || canonical(was) === canonical(r))) return;
      const nowLive = !isGone(r) && (was === undefined || isGone(was));
      if (nowLive && live >= LIVE_MOST) {
        out.refused.push({ at, id, error: `this station keeps ${LIVE_MOST} presets of a workspace at most` });
        return;
      }
      if (nowLive) live++;
      else if (isGone(r) && was !== undefined && !isGone(was)) live--;
      all.set(r.id, r);
      out.changed = true;
    });
    if (out.changed) this.#write(ws, all);
    for (const id of asked) out.records.push(all.get(id)!);
    return out;
  }

  /// `all` written as presets.json: what was kept as it was (this station's folders without `station`, as an app from
  /// before reads them), what was brought as it was brought.
  #write(ws: string | null, all: Map<string, KeptRecord>): void {
    const file = this.#file(ws);
    const before = new Map(file.presets.map((p) => [p.id, p]));
    const presets: Preset[] = [];
    const gone: PresetGone[] = [];
    for (const r of all.values()) {
      if (isGone(r)) gone.push(r);
      else {
        const held = before.get(r.id);
        presets.push(held !== undefined && canonical(this.record(ws, held)) === canonical(r) ? held : r);
      }
    }
    writePresets(this.home(ws), presets, gone);
  }

  /// Keeps what a chat in `workspace` is opened with: preset `id` as it is now. A folder this station is on is this
  /// machine's; another station's is said to be there, by its name.
  keepFor(workspace: string, ws: string | null, id: string): PresetCopy {
    const p = this.get(ws, id);
    if (p === null) throw new NoPreset(id);
    const dirs = p.dirs.map(({ station, stationName, ...d }) => (station === undefined || this.isHere(station) ? d : { ...d, elsewhere: this.nameOf(station, stationName) }));
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
  const model = modelOf(o.model);
  const st = stationsOf({ stations: o.stations });
  const stations = st.station !== undefined ? [st.station] : st.stations;
  return {
    id: str(o.id) ?? "",
    name,
    dirs: dirs.map(({ station: _s, stationName: _n, guides: _g, skills: _k, ...d }) => d),
    instructions,
    ...(model ? { model } : {}),
    ...(stations ? { stations } : {}),
  };
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
/// `here`: whether a folder's station is this one (Presets `isHere`).
export async function candidates(reposDir: string, presets: { dirs: PresetDir[]; updatedAt: number; [more: string]: unknown }[], found: Candidate[] = [], here: (station: string) => boolean = () => false): Promise<Candidate[]> {
  const list = async (dir: string) => readdir(dir).catch(() => [] as string[]);
  const cached = await Promise.all(
    (await list(reposDir)).map(async (name): Promise<Candidate | null> => {
      // (one being cloned, sessions/clones.ts: not there until it is whole)
      if (name.startsWith(".")) return null;
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
  // A preset may also name another station's folders. Those are not candidates on this machine: treating them as
  // local both puts them in the wrong group and can make a later save try to validate a remote path here.
  for (const p of presets) for (const d of p.dirs) if ((!d.station || here(d.station)) && !out.has(d.repo ?? d.path)) out.set(d.repo ?? d.path, { path: d.path, name: basename(d.path), repo: d.repo, chats: 0, lastAt: p.updatedAt, where: shortPath(d.path) });
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
