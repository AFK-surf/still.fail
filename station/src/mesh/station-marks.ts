// What a station is called and the mark it shows (its name, an emoji or an icon), kept by the station itself (the user,
// 2026-11-14: 「谁看都存在 station 上」; the root AGENTS.md, The cloud is the account system): one record a station,
// the same in every workspace it is in, changed only on the station it is of, by an owner or an admin of the workspace
// the asking device is in (`PUT /station-mark`), and never while that station is off (nothing else takes a change of it).
//
// The other stations of its workspaces keep a copy, so a device reads every station's of a workspace from any of them
// (`GET /station-marks`) while one is off; they are brought level over `stillfail/station/1` (`stationMarks.get`, `stationMarks.put`:
// followMarks), the newer of two by its `at` (only the station it is of makes one, so two never race). Devices are told
// a change on their event streams (`stationMarks`, tellMarks). A station with no record yet goes by what still.fail cloud
// lists of it, which the device has already (none is given for it here): the cloud's list was where it was kept
// before, and the device keeps writing there too until every app reads it here.
//
// A picture is not kept here: the device puts it up in still.fail cloud's store of pictures as before (cloud/src/icons.ts)
// and the record keeps its address. A topic carries no picture's bytes, and the app has no way yet of fetching one
// from a station.
//
// A station that only runs tasks (a rig) keeps none: no device reaches it, and it answers no new method (the station's
// AGENTS.md); its name and mark stay the cloud's.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { Cloud } from "../cloud/state.ts";
import { meshDir } from "../cloud/state.ts";
import { wall } from "../ops/fibers.ts";
import { writePrivateSoon } from "../ops/files.ts";
import { log } from "../ops/log.ts";
import type { PeerCall } from "./bus.ts";

/// How long a station waits before it tries a peer again that it could not bring level, at first; each failure after
/// doubles it, up to RETRY_MOST_MS (as ways.ts's).
const RETRY_MS = 5_000;
const RETRY_MOST_MS = 10 * 60_000;

/// A station's name and mark: `emoji` and `icon` empty where it has none (it shows its name's first letter), `at` when
/// it was set, by the clock of the station it is of.
export type MarkRecord = { name: string; emoji: string; icon: string; at: number };

const HEX64 = /^[0-9a-f]{64}$/;

/// A name as still.fail cloud takes one (cloud/src/directory.ts cleanName): trimmed, spaces made one, 1 to 80 long.
export function markName(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const clean = raw.trim().replace(/\s+/g, " ");
  return clean && clean.length <= 80 ? clean : null;
}

/// An emoji as the cloud takes one (cleanEmoji): the first of what was given, one that is an emoji; "" for none.
export function markEmoji(raw: unknown): string | null {
  if (raw === "" || raw === null) return "";
  if (typeof raw !== "string") return null;
  const first = [...new Intl.Segmenter().segment(raw.trim())][0]?.segment;
  return first && first.length <= 32 && /\p{Extended_Pictographic}|\p{Regional_Indicator}/u.test(first) ? first : null;
}

/// An icon as the cloud takes one (cleanIcon): one of the app's glyphs in a colour, or the address of a picture put up
/// in a still.fail cloud's store (`/v1/icons/<hash>.<kind>`, on whichever cloud the device is signed in to: a station
/// knows only its own); "" for none. Never a picture's bytes: a record stays small.
export function markIcon(raw: unknown): string | null {
  if (raw === "" || raw === null) return "";
  if (typeof raw !== "string") return null;
  if (/^glyph:[a-z0-9-]{1,40}(:[a-z]{1,16})?$/.test(raw)) return raw;
  if (raw.length > 300 || !URL.canParse(raw)) return null;
  const url = new URL(raw);
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash) return null;
  return /^\/v1\/icons\/[0-9a-f]{32}\.(png|webp|jpeg|gif)$/.test(url.pathname) ? url.href : null;
}

/// A record as a file or a peer says it; null when it is none.
export function markOf(raw: any): MarkRecord | null {
  if (raw === null || typeof raw !== "object" || !Number.isSafeInteger(raw.at) || raw.at <= 0) return null;
  const name = markName(raw.name);
  const emoji = markEmoji(raw.emoji ?? "");
  const icon = markIcon(raw.icon ?? "");
  if (name === null || emoji === null || icon === null) return null;
  return { name, emoji, icon, at: raw.at };
}

/// Why a change of a station's mark is refused: what was wrong, said to the one who asked.
export class MarkRefusal extends Error {}

export class StationMarks {
  readonly cloud: Cloud;
  readonly #path: string;
  /// Each station's record this station keeps, its own among them: by the station's id.
  readonly #kept = new Map<string, MarkRecord>();
  readonly #told = new Set<(station: string) => void>();
  #writing: Promise<void> = Promise.resolve();

  constructor(cloud: Cloud, path: string = join(meshDir(cloud.data), "station-marks.json")) {
    this.cloud = cloud;
    this.#path = path;
    try {
      const text = existsSync(path) ? readFileSync(path, "utf8") : null; // sync: read once, as the mesh starts, before it serves
      if (text !== null) for (const [station, raw] of Object.entries(JSON.parse(text) ?? {})) {
        const r = markOf(raw);
        if (r !== null && HEX64.test(station)) this.#kept.set(station, r);
      }
    } catch (e) {
      log.warn("mesh", "station-marks.json not read; the stations' names are as still.fail cloud lists them", { error: (e as Error).message });
    }
  }

  /// This station's id; "" before it is enrolled.
  get me(): string {
    return this.cloud.state?.station ?? "";
  }

  /// What this station keeps of `station`: null where it keeps none.
  record(station: string): MarkRecord | null {
    return this.#kept.get(station) ?? null;
  }

  /// The stations of `ws` this station knows (its roster's whole stations, itself among them).
  stationsOf(ws: string): string[] {
    const m = this.cloud.membership(ws);
    if (m === null) return [];
    const ids = m.peers.flatMap((p: any) => (typeof p?.id === "string" && HEX64.test(p.id) ? [p.id as string] : []));
    const me = this.me;
    return me !== "" && !ids.includes(me) ? [me, ...ids] : ids;
  }

  /// The records this station keeps of `ws`'s stations, by id: what a device of `ws` or a peer in it is given.
  of(ws: string): Record<string, MarkRecord> {
    const out: Record<string, MarkRecord> = {};
    for (const id of this.stationsOf(ws)) {
      const r = this.#kept.get(id);
      if (r !== undefined) out[id] = r;
    }
    return out;
  }

  /// A peer's record of `station`, kept when it is newer than this station's; whether it was.
  take(station: string, record: MarkRecord): boolean {
    const mine = this.#kept.get(station);
    if (mine !== undefined && record.at <= mine.at) return false;
    this.#keep(station, record);
    return true;
  }

  /// This station's own name and mark changed: what is given set, the rest as it was (`was`: what still.fail cloud lists
  /// where this station keeps none yet). Made the newest, whatever this machine's clock says.
  change(said: { name?: unknown; emoji?: unknown; icon?: unknown }, was: { name: string; emoji: string; icon: string }): MarkRecord {
    const me = this.me;
    if (me === "") throw new MarkRefusal("this station is not enrolled");
    const now = this.#kept.get(me);
    const base = now ?? { name: was.name, emoji: was.emoji, icon: was.icon, at: 0 };
    const name = said.name === undefined ? base.name : markName(said.name);
    if (name === null) throw new MarkRefusal("name: 1 to 80 characters");
    const emoji = said.emoji === undefined ? base.emoji : markEmoji(said.emoji);
    if (emoji === null) throw new MarkRefusal("emoji: one emoji, or empty for none");
    const icon = said.icon === undefined ? base.icon : markIcon(said.icon);
    if (icon === null) throw new MarkRefusal("icon: glyph:<name>[:<colour>], a picture's address in still.fail cloud (/v1/icons/…), or empty for none");
    const record: MarkRecord = { name, emoji, icon, at: Math.max(wall.now(), base.at + 1) };
    this.#keep(me, record);
    return record;
  }

  #keep(station: string, record: MarkRecord): void {
    this.#kept.set(station, record);
    const text = JSON.stringify(Object.fromEntries(this.#kept), null, 2);
    // One write after another, the last one last.
    this.#writing = this.#writing.then(() => writePrivateSoon(this.#path, text)).catch((e) => log.warn("mesh", "station-marks.json not written", { error: (e as Error).message }));
    for (const f of [...this.#told]) f(station);
  }

  /// Told each time a station's record changes here (its id); returns what stops it.
  listen(f: (station: string) => void): () => void {
    this.#told.add(f);
    return () => void this.#told.delete(f);
  }

  /// Written, as far as it was changed (tests).
  written(): Promise<void> {
    return this.#writing;
  }
}

const kept = new WeakMap<Cloud, StationMarks>();
/// The marks this station keeps (one for its data directory's cloud.json).
export function stationMarksOf(cloud: Cloud): StationMarks {
  let m = kept.get(cloud);
  if (m === undefined) kept.set(cloud, (m = new StationMarks(cloud)));
  return m;
}

// ── between the workspace's stations ──

/// A peer's `stationMarks.*` request, in the workspace it was asked in (the transport checked the peer is of it): only records
/// of that workspace's stations are given or taken.
export function answerMarks(marks: StationMarks, request: any, workspace: string): unknown {
  switch (request?.method) {
    case "stationMarks.get":
      return { marks: marks.of(workspace) };
    case "stationMarks.put": {
      const ids = new Set(marks.stationsOf(workspace));
      const taken: string[] = [];
      for (const [station, raw] of Object.entries(request?.marks ?? {})) {
        const record = markOf(raw);
        if (record === null) throw new Error("a malformed mark");
        if (ids.has(station) && marks.take(station, record)) taken.push(station);
      }
      return { taken };
    }
  }
  throw new Error("unknown stationMarks method");
}

/// What of `a` is newer than `b`'s, by station.
const newerOf = (a: Record<string, MarkRecord>, b: Record<string, MarkRecord>) => Object.fromEntries(Object.entries(a).filter(([id, r]) => b[id] === undefined || r.at > b[id]!.at));

/// Brings one peer and this station level in `ws`: each station's newer record kept by both.
async function level(marks: StationMarks, call: PeerCall, peer: string, ws: string, home: boolean): Promise<void> {
  const got: any = await call(peer, home ? null : ws, { method: "stationMarks.get" });
  const theirs: Record<string, MarkRecord> = {};
  for (const [id, raw] of Object.entries(got?.marks ?? {})) {
    const r = markOf(raw);
    if (r !== null) theirs[id] = r;
  }
  const ids = new Set(marks.stationsOf(ws));
  for (const [id, r] of Object.entries(theirs)) if (ids.has(id)) marks.take(id, r);
  const give = newerOf(marks.of(ws), theirs);
  if (Object.keys(give).length > 0) await call(peer, home ? null : ws, { method: "stationMarks.put", marks: give });
}

/// A station from before the marks were the stations': nothing to bring level with it.
const before = (e: unknown) => /unknown (marks )?method|no such method|not found/i.test((e as Error)?.message ?? "");

/// What of `ws`'s records a peer was brought level with, as a word that changes when any of them does.
const wordOf = (marks: StationMarks, ws: string) => JSON.stringify(Object.entries(marks.of(ws)).map(([id, r]) => [id, r.at]));

/// Whenever a station's record changes here, or a roster comes, each station of its workspaces is brought level with
/// this one; one that could not be (offline, the line between them down) is tried again, sooner at first, until it is.
export function followMarks(marks: StationMarks, call: PeerCall, after: (ms: number, f: () => void) => () => void = wall.after): () => void {
  const cloud = marks.cloud;
  const levelAt = new Map<string, string>();
  const going = new Set<string>();
  const retries = new Map<string, { wait: number; due: boolean; cancel: () => void }>();
  let stopped = false;
  const bring = (peer: string, ws: string, home: boolean) => {
    const key = `${ws}|${peer}`;
    const at = wordOf(marks, ws);
    const retry = retries.get(key);
    if (levelAt.get(key) === at || going.has(key) || (retry !== undefined && !retry.due)) return;
    going.add(key);
    level(marks, call, peer, ws, home).then(
      () => {
        levelAt.set(key, wordOf(marks, ws));
        retries.delete(key);
      },
      (e) => {
        // One from before: nothing of the marks there; level with it until this station's records change again.
        if (before(e)) {
          levelAt.set(key, at);
          retries.delete(key);
          return;
        }
        log.info("mesh", "a station's marks were not brought level", { peer: peer.slice(0, 12), workspace: ws, error: (e as Error).message });
        if (stopped) return;
        const wait = retry === undefined ? RETRY_MS : Math.min(retry.wait * 2, RETRY_MOST_MS);
        const next = { wait, due: false, cancel: () => {} };
        next.cancel = after(wait, () => { // timer: a retry after a failure, with a backoff
          next.due = true;
          look();
        });
        retries.set(key, next);
      },
    ).finally(() => {
      going.delete(key);
      if (!stopped) look();
    });
  };
  const look = () => {
    const st = cloud.state;
    // (a station that only runs tasks asks nothing of the others, peer.ts: it keeps none)
    if (stopped || !st || !cloud.peersCurrent || st.rig !== undefined) return;
    for (const m of cloud.memberships()) for (const p of m.peers) if (typeof p?.id === "string" && p.id !== st.station) bring(p.id, m.workspace, m.home);
  };
  look();
  const unlistenCloud = cloud.listen(look);
  const unlistenMarks = marks.listen(look);
  return () => {
    stopped = true;
    unlistenCloud();
    unlistenMarks();
    for (const r of retries.values()) r.cancel();
    retries.clear();
  };
}

// ── to the members' devices ──

export type Tell = (event: string, data: unknown, of: string, to: { workspace: string }) => void;

/// Tells each change of a station's record to the devices of every workspace it is in here (`stationMarks`, `{workspace}`):
/// they read `GET /station-marks` again.
export function tellMarks(marks: StationMarks, tell: Tell): () => void {
  return marks.listen((station) => {
    for (const m of marks.cloud.memberships()) if (marks.stationsOf(m.workspace).includes(station)) tell("stationMarks", { workspace: m.workspace }, `stationMarks\0${m.workspace}`, { workspace: m.workspace });
  });
}
