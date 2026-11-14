// A person's presets and starred models as their devices carry them between the stations of a workspace (the user,
// 2026-11-14: 「预设和模型收藏会在整个 workspace 同步」, the person's own devices doing it): one rule for the station
// (station/src/sessions/presets.ts, station/src/api/routes/stars.ts) and the core, as titles.ts is for a chat's name.
// Stations do not bring these level with each other: a device reads each station's, keeps the newer of each record and
// brings a station what it lacks. No clock decides: a record counts its changes (`rev`), the higher wins, and a
// deletion is a record of its own, so a station that was off does not bring a deleted preset back. Pure, and run by
// Hermes too (no `Intl`, no `toSorted`).

/// A folder of a preset as carried: its path, the repository it is a clone of, and the station it is on (that
/// station's address, `<workspace>/<station id>`, as the app writes it for another station's folder).
export type RecordDir = { path: string; repo: string | null; station: string };

/// How a preset runs its chats' model, where it names one (as station/src/sessions/presets.ts `PresetModel`).
export type RecordModel = { model: string; runtime?: string; effort?: string; fast?: boolean; context?: number; profile?: string; profiles?: string[] };

/// A preset as kept and carried. `owner`: the `sub` of the person it is of ("" on one from before, until their device
/// says it); `rev`: how many times it was changed, from 1; `home`: the id of the station it was made on (the one that
/// lists it to apps from before).
export type PresetRecord = {
  id: string;
  name: string;
  dirs: RecordDir[];
  instructions: string;
  autoStation?: boolean;
  station?: string;
  stations?: string[];
  model?: RecordModel;
  createdBy: string;
  createdAt: number;
  updatedAt: number;
  owner: string;
  rev: number;
  home: string;
};

/// A preset deleted: nothing else of it kept.
export type GoneRecord = { id: string; owner: string; rev: number; gone: true; updatedAt: number };

export type KeptRecord = PresetRecord | GoneRecord;

export const isGone = (r: KeptRecord): r is GoneRecord => (r as GoneRecord).gone === true;

/// A preset's name is so many characters at most; its instructions so long; so many folders.
export const NAME_MAX = 60;
export const INSTRUCTIONS_MAX = 20_000;
export const DIRS_MAX = 20;
/// A folder's path, a station's address, a person's `sub` and email, an id: so long at most.
const PATH_MOST = 4096;
const ADDRESS_MOST = 300;
const WHO_MOST = 320;
const ID = /^[A-Za-z0-9_-]{1,64}$/;

/// `v` as one text whatever order its keys were put in: an object's keys sorted (by their UTF-16 code units, the same
/// in every engine), what JSON leaves out left out.
export function canonical(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map((x) => (x === undefined || typeof x === "function" ? "null" : canonical(x))).join(",")}]`;
  if (v !== null && typeof v === "object") {
    const o = v as Record<string, unknown>;
    const keys = Object.keys(o).filter((k) => o[k] !== undefined && typeof o[k] !== "function").sort();
    return `{${keys.map((k) => `${JSON.stringify(k)}:${canonical(o[k])}`).join(",")}}`;
  }
  return JSON.stringify(v) ?? "null";
}

/// The newer of two records of one preset: the higher `rev`; of the same, the deleted one; then the later `updatedAt`;
/// then the larger as canonical text. A total order: keepers holding the same records choose the same one whatever
/// order they came in.
export function newerRecord<T extends KeptRecord>(a: T, b: T): T {
  if (a.rev !== b.rev) return a.rev > b.rev ? a : b;
  const ga = isGone(a);
  if (ga !== isGone(b)) return ga ? a : b;
  if (a.updatedAt !== b.updatedAt) return a.updatedAt > b.updatedAt ? a : b;
  return canonical(a) >= canonical(b) ? a : b;
}

/// The deletions of one owner's (a person's `sub`; those of nobody said yet, of the routes of before, one owner of their
/// own) a keeper keeps at most: the latest by when each was deleted. Both sides keep the same by this one rule
/// (`goneKept`), the station as it writes and the device as it keeps, so a device never brings a deletion a station would
/// drop as it takes it (which went round for good with a bound of the workspace's, 2026-11-14). 200: a person's
/// presets are made by hand, tens of them, so a deletion is forgotten only after two hundred later ones of the same
/// person's, and only a keeper that held that preset live all that while could bring it back then; 200 deletions are
/// some 16 KB a person a station.
export const GONE_KEPT = 200;

/// Of `gone`, those kept (GONE_KEPT of each owner's: the latest by `updatedAt`, then the higher `rev`, then the lower
/// id, the same whatever their order), in the order given; `gone` itself where all are.
export function goneKept<T extends GoneRecord>(gone: readonly T[]): readonly T[] {
  const byOwner = new Map<string, T[]>();
  for (const g of gone) byOwner.set(g.owner, [...(byOwner.get(g.owner) ?? []), g]);
  if ([...byOwner.values()].every((list) => list.length <= GONE_KEPT)) return gone;
  const order = (a: T, b: T) => b.updatedAt - a.updatedAt || b.rev - a.rev || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
  const kept = new Set<T>();
  for (const list of byOwner.values()) for (const g of [...list].sort(order).slice(0, GONE_KEPT)) kept.add(g);
  return gone.filter((g) => kept.has(g));
}

/// `records` (by id) with the deletions `goneKept` does not keep left out; the same object where none is.
export function recordsKept<T extends KeptRecord>(records: Record<string, T>): Record<string, T> {
  const gone = Object.values(records).filter((r): r is T & GoneRecord => isGone(r));
  const kept = goneKept(gone);
  if (kept.length === gone.length) return records;
  const keep = new Set<KeptRecord>(kept);
  const out: Record<string, T> = {};
  for (const [id, r] of Object.entries(records)) if (!isGone(r) || keep.has(r)) out[id] = r;
  return out;
}

const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
const count = (v: unknown, least: number): boolean => typeof v === "number" && Number.isSafeInteger(v) && v >= least;

/// A model configuration as a preset is given one: each field trimmed, what is empty left out; none without a model.
export function modelOf(v: unknown): RecordModel | undefined {
  if (typeof v !== "object" || v === null) return undefined;
  const o = v as Record<string, unknown>;
  const m = (str(o.model) ?? "").trim();
  if (m === "") return undefined;
  const out: RecordModel = { model: m };
  const rt = (str(o.runtime) ?? "").trim();
  if (rt !== "") out.runtime = rt;
  const eff = (str(o.effort) ?? "").trim();
  if (eff !== "") out.effort = eff;
  if (typeof o.fast === "boolean") out.fast = o.fast;
  if (typeof o.context === "number" && Number.isInteger(o.context) && o.context > 0) out.context = o.context;
  const prof = (str(o.profile) ?? "").trim();
  if (prof !== "") out.profile = prof;
  if (Array.isArray(o.profiles)) {
    const ps: string[] = [];
    for (const x of o.profiles) if (typeof x === "string" && x.trim() !== "" && !ps.includes(x.trim())) ps.push(x.trim());
    if (ps.length > 0) out.profiles = ps;
  }
  return out;
}

/// Where a preset's chats are opened, as it is given: several stations (`stations`), one (`station`), any of those up
/// (`autoStation`), or none said.
export function stationsOf(o: Record<string, unknown>): { autoStation?: boolean; station?: string; stations?: string[] } {
  if (Array.isArray(o.stations)) {
    const list: string[] = [];
    for (const x of o.stations) if (typeof x === "string" && x.trim() !== "" && !list.includes(x.trim())) list.push(x.trim());
    if (list.length === 1) return { station: list[0]! };
    if (list.length > 1) return { stations: list };
    return {};
  }
  const s = (str(o.station) ?? "").trim();
  if (s !== "") return { station: s };
  if (o.autoStation === true) return { autoStation: true };
  return {};
}

/// Why a record is not taken: what is wrong with it.
export class RecordRefusal extends Error {}

/// A record as a device or a station says it, checked and made what both sides keep: its name and instructions
/// trimmed, its folders each named once, its station policy and model as a preset's are given (`stationsOf`,
/// `modelOf`), its keys in one order. Its folders are taken as said, never looked for. The same record made of what
/// it makes. Throws a RecordRefusal saying what is wrong.
export function recordOf(raw: unknown): KeptRecord {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) throw new RecordRefusal("a record is an object");
  const o = raw as Record<string, unknown>;
  const id = str(o.id);
  if (id === null || !ID.test(id)) throw new RecordRefusal("id: 1 to 64 letters, digits, - or _");
  const owner = str(o.owner);
  if (owner === null || owner.length > WHO_MOST) throw new RecordRefusal("owner: the sub of the person it is of");
  if (!count(o.rev, 1)) throw new RecordRefusal("rev: how many times it was changed, from 1");
  if (!count(o.updatedAt, 0)) throw new RecordRefusal("updatedAt: a time in ms");
  const rev = o.rev as number;
  const updatedAt = o.updatedAt as number;
  if (o.gone === true) return { id, owner, rev, gone: true, updatedAt };
  const name = (str(o.name) ?? "").trim();
  if (name === "") throw new RecordRefusal("a preset needs a name");
  if (Array.from(name).length > NAME_MAX) throw new RecordRefusal(`a preset's name is ${NAME_MAX} characters at most`);
  const instructions = (str(o.instructions) ?? "").trim();
  if (instructions.length > INSTRUCTIONS_MAX) throw new RecordRefusal("its instructions are too long");
  const given = o.dirs === undefined || o.dirs === null ? [] : o.dirs;
  if (!Array.isArray(given)) throw new RecordRefusal("dirs: a list of folders");
  const dirs: RecordDir[] = [];
  for (const d of given) {
    const path = str((d as { path?: unknown } | null)?.path);
    if (path === null || path.trim() === "" || path.length > PATH_MOST) throw new RecordRefusal("a folder needs a path");
    const station = str((d as { station?: unknown }).station);
    if (station === null || station.trim() === "" || station.length > ADDRESS_MOST) throw new RecordRefusal(`folder ${path}: station, the address of the station it is on`);
    const repo = str((d as { repo?: unknown }).repo);
    if (repo !== null && repo.length > PATH_MOST) throw new RecordRefusal(`folder ${path}: repo is too long`);
    if (!dirs.some((x) => x.path === path && x.station === station)) dirs.push({ path, repo: repo === "" ? null : repo, station });
  }
  if (dirs.length > DIRS_MAX) throw new RecordRefusal(`a preset has ${DIRS_MAX} folders at most`);
  const st = stationsOf(o);
  const model = modelOf(o.model);
  const createdBy = str(o.createdBy) ?? "";
  if (createdBy.length > WHO_MOST) throw new RecordRefusal("createdBy is too long");
  const createdAt = o.createdAt === undefined ? 0 : o.createdAt;
  if (!count(createdAt, 0)) throw new RecordRefusal("createdAt: a time in ms");
  const home = str(o.home);
  if (home === null || home === "" || home.length > ADDRESS_MOST) throw new RecordRefusal("home: the id of the station it was made on");
  return {
    id,
    name,
    dirs,
    instructions,
    ...(st.autoStation ? { autoStation: true } : {}),
    ...(st.station ? { station: st.station } : {}),
    ...(st.stations ? { stations: st.stations } : {}),
    ...(model ? { model } : {}),
    createdBy,
    createdAt: createdAt as number,
    updatedAt,
    owner,
    rev,
    home,
  };
}

// ── starred models ──

/// A model starred or unstarred by a person: `on` false is the unstarring, kept so that it is not starred back; `rev`
/// how many times its star was changed; `at` when it was starred (the order they are shown in).
export type Star = { on: boolean; rev: number; at: number };
export type Stars = Record<string, Star>;

/// A person keeps so many models' stars in a workspace at most, each model's key so long.
export const STARS_MOST = 200;
export const STAR_KEY_MOST = 200;

/// The newer of two stars of one model: the higher `rev`; then the unstarring; then the later `at`.
export function newerStar(a: Star, b: Star): Star {
  if (a.rev !== b.rev) return a.rev > b.rev ? a : b;
  if (a.on !== b.on) return a.on ? b : a;
  return b.at > a.at ? b : a;
}

/// Stars as a device or a station says them, checked: throws a RecordRefusal saying what is wrong.
export function starsOf(raw: unknown): Stars {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) throw new RecordRefusal("stars: an object of models' stars");
  const out: Stars = {};
  const keys = Object.keys(raw as object);
  if (keys.length > STARS_MOST) throw new RecordRefusal(`stars: ${STARS_MOST} models at most`);
  for (const k of keys) {
    const s = (raw as Record<string, any>)[k];
    if (k === "" || k.length > STAR_KEY_MOST) throw new RecordRefusal(`stars: a model's key is 1 to ${STAR_KEY_MOST} characters`);
    if (s === null || typeof s !== "object" || typeof s.on !== "boolean" || !count(s.rev, 1) || !count(s.at, 0)) throw new RecordRefusal(`stars: ${k} is {on, rev, at}`);
    out[k] = { on: s.on, rev: s.rev, at: s.at };
  }
  return out;
}

/// `given` merged into `kept` model by model, the newer of each kept; past STARS_MOST, the oldest unstarrings go first
/// (one of them starred back by a device that never heard of it is the cost), and the oldest stars after them. Its keys
/// in order, so that two keepers of the same stars write the same.
export function mergeStars(kept: Stars, given: Stars): Stars {
  const all: Stars = { ...kept };
  for (const k of Object.keys(given)) all[k] = all[k] === undefined ? given[k]! : newerStar(all[k]!, given[k]!);
  let keys = Object.keys(all).sort();
  if (keys.length > STARS_MOST) {
    const going = [...keys].sort((a, b) => Number(all[a]!.on) - Number(all[b]!.on) || all[a]!.at - all[b]!.at || (a < b ? -1 : a > b ? 1 : 0));
    const gone = new Set(going.slice(0, keys.length - STARS_MOST));
    keys = keys.filter((k) => !gone.has(k));
  }
  const out: Stars = {};
  for (const k of keys) out[k] = all[k]!;
  return out;
}
