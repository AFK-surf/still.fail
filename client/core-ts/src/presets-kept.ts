// What the device keeps of its person's presets and starred models in each workspace (views/presets.ts carries them
// between the workspace's stations; choose.ts reads them for the new chat's page): one record a workspace in its own
// database, `presetRecords` (by the workspace's id): the person's records, deleted ones too, by id, and which of the
// workspace's stations are from before (they answer no GET /presets/kept: read as before, never PUT to). The starred
// models are the new chat's `choice` record `ws:<ws>:liked`, a map of preset-records.ts `Stars` (a list from before
// read as each key starred). The rule both sides keep is preset-records.ts; nothing here decides otherwise. Pure.
import { type KeptRecord, type PresetRecord, type Stars, canonical, isGone, newerRecord, newerStar, recordOf, starsOf } from "./preset-records.ts";
import { isObject } from "./util.ts";

export const TABLE = "presetRecords";

/// What the device keeps of `ws`: its person's records by id, and the ids of its stations from before (their GET
/// /presets/kept answered `no route`).
export type Held = { records: Record<string, KeptRecord>; before: string[] };

const NONE: Held = Object.freeze({ records: Object.freeze({}) as Record<string, KeptRecord>, before: Object.freeze([]) as unknown as string[] });

/// What is kept of `ws` (none kept: nothing). A record that does not read is left out.
export function heldOf(data: { record(table: string, key: string): unknown }, ws: string): Held {
  const raw = data.record(TABLE, ws);
  if (!isObject(raw)) return NONE;
  const records = isObject(raw.records) ? (raw.records as Record<string, KeptRecord>) : {};
  const before = Array.isArray(raw.before) ? raw.before.filter((x): x is string => typeof x === "string") : [];
  return { records, before };
}

/// Who the device is in a workspace: its account's `sub` and email.
export type Who = { sub: string; email: string };

const sameEmail = (a: string, b: string) => a !== "" && a.toLowerCase() === b.toLowerCase();

/// Whether a record a station keeps is `who`'s (as the station's `Presets.theirs`): by its owner, or one from before
/// (no owner yet) that they made.
export function theirs(r: KeptRecord, who: Who): boolean {
  if (who.sub === "") return false;
  if (r.owner === who.sub) return true;
  return r.owner === "" && !isGone(r) && sameEmail((r as PresetRecord).createdBy, who.email);
}

/// A record of `who`'s as the device takes it: one from before (no owner) said again as theirs, one change more (its
/// time as it was, so that every device of theirs says the same record of it).
export function adopted(r: KeptRecord, who: Who): KeptRecord {
  return r.owner === "" ? { ...r, owner: who.sub, rev: r.rev + 1 } : r;
}

/// `given` (records a station said, each checked) taken into `records` where newer: what is kept then, the same object
/// where nothing was taken. Only `who`'s.
export function taken(records: Record<string, KeptRecord>, given: readonly KeptRecord[], who: Who): Record<string, KeptRecord> {
  let out: Record<string, KeptRecord> | null = null;
  for (const raw of given) {
    if (!theirs(raw, who)) continue;
    const r = adopted(raw, who);
    const was = (out ?? records)[r.id];
    if (was !== undefined && (newerRecord(was, r) === was || canonical(was) === canonical(r))) continue;
    out ??= { ...records };
    out[r.id] = r;
  }
  return out ?? records;
}

/// What a station said of records, each checked as both sides check one; one that does not check left out.
export function recordsOf(raw: unknown): KeptRecord[] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((r) => {
    try {
      return [recordOf(r)];
    } catch {
      return [];
    }
  });
}

/// Of `records`, those a station holding `said` (by id) lacks or holds older: what it is brought, and only that.
export function lacking(records: Record<string, KeptRecord>, said: ReadonlyMap<string, KeptRecord>, who: Who): KeptRecord[] {
  return Object.values(records).filter((r) => {
    if (r.owner !== who.sub) return false;
    const there = said.get(r.id);
    return there === undefined || (newerRecord(there, r) === r && canonical(there) !== canonical(r));
  });
}

/// `records` in turns a station takes (preset-records.ts: at most `most` a request, and a megabyte).
export function turns(records: readonly KeptRecord[], most = 100, bytes = 900_000): KeptRecord[][] {
  const out: KeptRecord[][] = [];
  let now: KeptRecord[] = [];
  let size = 0;
  for (const r of records) {
    const n = JSON.stringify(r).length + 1;
    if (now.length > 0 && (now.length >= most || size + n > bytes)) {
      out.push(now);
      now = [];
      size = 0;
    }
    now.push(r);
    size += n;
  }
  if (now.length > 0) out.push(now);
  return out;
}

/// A preset as a station from before lists it (GET /presets: its own folders without `station`) as a record of
/// nobody said yet, made on that station (`address`): what the device takes it as once its person changes it here.
/// Null where it does not check.
export function fromBefore(p: unknown, address: string): PresetRecord | null {
  if (!isObject(p)) return null;
  const id = address.slice(address.lastIndexOf("/") + 1);
  const dirs = Array.isArray(p.dirs)
    ? p.dirs.flatMap((d) => (isObject(d) && typeof d.path === "string" ? [{ path: d.path, repo: typeof d.repo === "string" ? d.repo : null, station: typeof d.station === "string" && d.station !== "" ? d.station : address }] : []))
    : [];
  try {
    const r = recordOf({ ...p, dirs, owner: "", rev: 1, home: id, updatedAt: typeof p.updatedAt === "number" ? p.updatedAt : 0 });
    return isGone(r) ? null : r;
  } catch {
    return null;
  }
}

/// A preset id made here, as a station makes one (`p-` and ten hexadecimal digits).
export function presetId(): string {
  return `p-${Array.from(crypto.getRandomValues(new Uint8Array(5)), (b) => b.toString(16).padStart(2, "0")).join("")}`;
}

// ── starred models ──

/// The stars kept as `raw` says them (the `choice` record `ws:<ws>:liked`): a map as preset-records.ts says one; a
/// list from before as each of its keys starred once, in its order (`at` its place); null where none is kept.
export function starsHeld(raw: unknown): Stars | null {
  if (raw === undefined || raw === null) return null;
  if (Array.isArray(raw)) {
    const out: Stars = {};
    raw.forEach((k, i) => {
      if (typeof k === "string" && k !== "" && out[k] === undefined) out[k] = { on: true, rev: 1, at: i };
    });
    return out;
  }
  try {
    return starsOf(raw);
  } catch {
    return null;
  }
}

/// The keys starred in `stars`, the first starred first (by `at`, then by key).
export function starredKeys(stars: Stars): string[] {
  return Object.keys(stars)
    .filter((k) => stars[k]!.on)
    .sort((a, b) => stars[a]!.at - stars[b]!.at || (a < b ? -1 : a > b ? 1 : 0));
}

/// Of `stars`, those a station holding `said` lacks or holds older.
export function starsLacking(stars: Stars, said: Stars): Stars {
  const out: Stars = {};
  for (const [k, s] of Object.entries(stars)) {
    const there = said[k];
    if (there === undefined || (canonical(there) !== canonical(s) && newerStar(there, s) === s)) out[k] = s;
  }
  return out;
}
