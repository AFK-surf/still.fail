// How a workspace's members' devices reach its stations, kept by its stations (the root AGENTS.md, The cloud is the
// account system; the user, 2026-11-11: an agent adds a relay itself, 「要手动加太不 ai native 了」): the relays it has of
// its own beside still.fail's, and the ways its devices do not take (`off`: a relay's URL, `lan`, `tailnet`, `direct`).
//
// One record a workspace, whole, the newest kept: a change made here is `at` this station's clock (after the record it
// changes), by this station; between two of the same time the larger station id. A station that holds none yet goes by
// what still.fail cloud kept before (`Cloud.waysSaid`). The workspace's stations keep each other level over
// `stillfail/station/1` (`ways.get`, `ways.put`: followWays), devices read it (`GET /ways`, serve.ts) and are told it
// changed on their event streams (`ways`, tellWays), and this station keeps every workspace's own relays as it keeps
// still.fail's (relays.ts).
//
// Nobody approves a relay: it carries only the mesh's packets, end to end encrypted, and one that is slow or does not
// answer is not taken (client/core-ts mesh.ts measures each way). Who added each is kept (`by`) and shown, so a person
// sees it and takes it away.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { Cloud } from "../cloud/state.ts";
import { meshDir } from "../cloud/state.ts";
import { wall } from "../ops/fibers.ts";
import { writePrivateSoon } from "../ops/files.ts";
import { log } from "../ops/log.ts";
import type { PeerCall } from "./bus.ts";

/// How long a station waits before it tries a peer again that it could not bring level, at first; each failure after
/// doubles it, up to RETRY_MOST_MS (as lock-sync.ts's).
const RETRY_MS = 5_000;
const RETRY_MOST_MS = 10 * 60_000;

/// A relay of the workspace's own: its URL, and who added it (a chat's name, a person's) where that is known.
export type OwnRelay = { url: string; by?: string };
/// What a workspace's stations keep of its ways: `at` and `station` say which of two is the newer.
export type WaysRecord = { relays: OwnRelay[]; off: string[]; at: number; station: string };
/// What a device or a peer is told: the record, or as still.fail cloud kept it (`at` 0, no station).
export type WaysView = { relays: OwnRelay[]; off: string[]; at: number; station: string };

/// At most this many relays of a workspace's own (as cloud/src/relays.ts `MAX_RELAYS` was).
export const MAX_OWN_RELAYS = 4;
/// The ways to a station that are no single relay, which a workspace may turn off as it may a relay (`ours`: all of still.fail's relays).
export const WAY_KINDS = ["lan", "tailnet", "direct", "ours"] as const;

/// A relay's URL as compared: its normal form without a trailing slash.
export const sameUrl = (url: string): string => (URL.canParse(url) ? new URL(url).href : url).replace(/\/+$/, "");

/// A relay's URL as one is kept: https (http too where `insecure`, a local setup), no account, query or fragment, no
/// trailing slash; null when it is none.
export function relayUrl(raw: unknown, insecure = false): string | null {
  if (typeof raw !== "string" || !URL.canParse(raw.trim())) return null;
  const url = new URL(raw.trim());
  if (!(url.protocol === "https:" || (insecure && url.protocol === "http:")) || url.username || url.password || url.search || url.hash) return null;
  return url.href.replace(/\/+$/, "");
}

const newer = (a: { at: number; station: string }, b: { at: number; station: string }) => a.at > b.at || (a.at === b.at && a.station > b.station);

/// A record as a file or a peer says it; null when it is none.
export function recordOf(raw: any): WaysRecord | null {
  if (raw === null || typeof raw !== "object" || !Array.isArray(raw.relays) || !Number.isSafeInteger(raw.at) || raw.at < 0 || typeof raw.station !== "string") return null;
  const relays: OwnRelay[] = [];
  for (const r of raw.relays) {
    const url = relayUrl(typeof r === "string" ? r : r?.url, true);
    if (url === null || relays.some((k) => sameUrl(k.url) === sameUrl(url))) continue;
    relays.push(typeof r?.by === "string" && r.by !== "" ? { url, by: r.by.slice(0, 200) } : { url });
  }
  const off = Array.isArray(raw.off) ? [...new Set(raw.off.filter((w: unknown): w is string => typeof w === "string"))] as string[] : [];
  return { relays: relays.slice(0, MAX_OWN_RELAYS), off, at: raw.at, station: raw.station };
}

export class Ways {
  readonly cloud: Cloud;
  readonly #path: string;
  readonly #kept = new Map<string, WaysRecord>();
  readonly #told = new Set<(workspace: string) => void>();
  #writing: Promise<void> = Promise.resolve();

  constructor(cloud: Cloud, path: string = join(meshDir(cloud.data), "ways.json")) {
    this.cloud = cloud;
    this.#path = path;
    try {
      const text = existsSync(path) ? readFileSync(path, "utf8") : null; // sync: read once, as the mesh starts, before it serves
      if (text !== null) for (const [ws, raw] of Object.entries(JSON.parse(text) ?? {})) {
        const r = recordOf(raw);
        if (r !== null) this.#kept.set(ws, r);
      }
    } catch (e) {
      log.warn("mesh", "ways.json not read; the workspaces' ways are as still.fail cloud kept them", { error: (e as Error).message });
    }
  }

  /// What this station keeps of `ws`'s ways: null where it keeps none (it goes by the cloud's then, `view`).
  record(ws: string): WaysRecord | null {
    return this.#kept.get(ws) ?? null;
  }

  /// `ws`'s ways as this station goes by them: its record, else as still.fail cloud kept them, else none.
  view(ws: string): WaysView {
    const kept = this.#kept.get(ws);
    if (kept !== undefined) return kept;
    const said = this.cloud.waysSaid(ws);
    return { relays: (said?.relays ?? []).flatMap((u) => { const url = relayUrl(u, true); return url === null ? [] : [{ url }]; }), off: said?.off ?? [], at: 0, station: "" };
  }

  /// Every relay of the workspaces this station is in, of their own: kept on as still.fail's are (relays.ts).
  relays(): string[] {
    const out: string[] = [];
    for (const m of this.cloud.memberships()) for (const r of this.view(m.workspace).relays) if (!out.some((u) => sameUrl(u) === sameUrl(r.url))) out.push(r.url);
    return out;
  }

  /// A peer's record, kept when it is newer than this station's; whether it was.
  take(ws: string, record: WaysRecord): boolean {
    const mine = this.#kept.get(ws);
    if (mine !== undefined && !newer(record, mine)) return false;
    this.#keep(ws, record);
    return true;
  }

  /// A change made here (an agent's, a member's device's): the record as it was, changed by `change`, made the newest.
  change(ws: string, change: (now: { relays: OwnRelay[]; off: string[] }) => { relays: OwnRelay[]; off: string[] }): WaysRecord {
    const was = this.view(ws);
    const next = change({ relays: was.relays, off: was.off });
    const station = this.cloud.state?.station ?? "";
    const record: WaysRecord = { relays: next.relays, off: next.off, at: Math.max(wall.now(), was.at + 1), station };
    this.#keep(ws, record);
    return record;
  }

  #keep(ws: string, record: WaysRecord): void {
    this.#kept.set(ws, record);
    const text = JSON.stringify(Object.fromEntries(this.#kept), null, 2);
    // One write after another, the last one last.
    this.#writing = this.#writing.then(() => writePrivateSoon(this.#path, text)).catch((e) => log.warn("mesh", "ways.json not written", { error: (e as Error).message }));
    for (const f of [...this.#told]) f(ws);
  }

  /// Told each time a workspace's ways change here (its id); returns what stops it.
  listen(f: (workspace: string) => void): () => void {
    this.#told.add(f);
    return () => void this.#told.delete(f);
  }

  /// Written, as far as it was changed (tests).
  written(): Promise<void> {
    return this.#writing;
  }
}

const kept = new WeakMap<Cloud, Ways>();
/// The ways this station keeps (one for its data directory's cloud.json).
export function waysOf(cloud: Cloud): Ways {
  let w = kept.get(cloud);
  if (w === undefined) kept.set(cloud, (w = new Ways(cloud)));
  return w;
}

// ── changes asked of it ──

/// Why a change of the ways is refused: what was wrong, said to the one who asked.
export class WaysRefusal extends Error {}

/// Whether still.fail's cloud is on http (a local setup), where a relay on http is taken too.
const insecure = (cloud: Cloud) => (cloud.state?.origin ?? "").startsWith("http:");

/// still.fail's own relays: what the control plane's `relay_urls` say, but the workspaces' own it puts after them
/// (as it kept them, `waysSaid`): every workspace has these.
export function stillFails(cloud: Cloud): string[] {
  const theirs = cloud.memberships().flatMap((m) => cloud.waysSaid(m.workspace)?.relays ?? []);
  return cloud.relays().filter((u) => !theirs.some((t) => sameUrl(t) === sameUrl(u)));
}

/// `url` added to `ws`'s own relays, by `by`. One already there stays as it is.
export function addRelay(ways: Ways, ws: string, raw: string, by: string | null): WaysRecord {
  const url = relayUrl(raw, insecure(ways.cloud));
  if (url === null) throw new WaysRefusal("not a relay's URL: https://host[:port][/path], with no account, query or fragment");
  if (stillFails(ways.cloud).some((u) => sameUrl(u) === sameUrl(url))) throw new WaysRefusal("that is one of still.fail's own relays, which every workspace has already");
  return ways.change(ws, (now) => {
    if (now.relays.some((r) => sameUrl(r.url) === sameUrl(url))) return now;
    if (now.relays.length >= MAX_OWN_RELAYS) throw new WaysRefusal(`a workspace has at most ${MAX_OWN_RELAYS} relays of its own: remove one first`);
    return { ...now, relays: [...now.relays, by ? { url, by } : { url }] };
  });
}

/// When removing custom relays would leave every relay off (still.fail's were turned off while custom relays were
/// there), still.fail's come back on so the workspace is never left without a relay.
function keepRelayOn(ours: string[], relays: OwnRelay[], off: string[]): string[] {
  if (ours.length === 0) return off;
  const all = [...ours, ...relays.map((r) => r.url)];
  const isRelayOff = (u: string) => off.some((w) => sameUrl(w) === sameUrl(u)) || (off.includes("ours") && ours.some((o) => sameUrl(o) === sameUrl(u)));
  return all.every(isRelayOff) ? off.filter((w) => w !== "ours" && !ours.some((o) => sameUrl(o) === sameUrl(w))) : off;
}

/// `url` taken out of `ws`'s own relays, and out of the ways turned off.
export function removeRelay(ways: Ways, ws: string, raw: string): WaysRecord {
  const url = relayUrl(raw, true) ?? String(raw);
  if (!ways.view(ws).relays.some((r) => sameUrl(r.url) === sameUrl(url))) throw new WaysRefusal("not one of this workspace's own relays");
  const ours = stillFails(ways.cloud);
  return ways.change(ws, (now) => {
    const relays = now.relays.filter((r) => sameUrl(r.url) !== sameUrl(url));
    const off = keepRelayOn(ours, relays, now.off.filter((w) => sameUrl(w) !== sameUrl(url)));
    return { relays, off };
  });
}

/// The whole list of `ws`'s own relays set at once (the app's 连接方式): who added those already there kept, the new ones
/// `by`; those gone taken out of the ways turned off.
export function setRelays(ways: Ways, ws: string, raws: unknown[], by: string | null): WaysRecord {
  const urls: string[] = [];
  const ours = stillFails(ways.cloud);
  for (const raw of raws) {
    const url = relayUrl(raw, insecure(ways.cloud));
    if (url === null) throw new WaysRefusal("not a relay's URL: https://host[:port][/path], with no account, query or fragment");
    if (!ours.some((u) => sameUrl(u) === sameUrl(url)) && !urls.some((u) => sameUrl(u) === sameUrl(url))) urls.push(url);
  }
  if (urls.length > MAX_OWN_RELAYS) throw new WaysRefusal(`a workspace has at most ${MAX_OWN_RELAYS} relays of its own`);
  return ways.change(ws, (now) => {
    const relays = urls.map((url) => now.relays.find((r) => sameUrl(r.url) === sameUrl(url)) ?? (by ? { url, by } : { url }));
    const off = keepRelayOn(
      ours,
      relays,
      now.off.filter((w) => !URL.canParse(w) || urls.some((u) => sameUrl(u) === sameUrl(w)) || ours.some((u) => sameUrl(u) === sameUrl(w))),
    );
    return { relays, off };
  });
}

/// One way turned on or off for `ws`'s devices: a relay (still.fail's or its own) or a kind of way (`ours` for all of
/// still.fail's relays). A relay stays on: the web app goes through relays alone, and a device that never reached a
/// station yet knows of no other way there.
export function setWay(ways: Ways, ws: string, way: string, on: boolean): WaysRecord {
  const ours = stillFails(ways.cloud);
  const own = ways.view(ws).relays.map((r) => r.url);
  const relays = [...ours, ...own];
  const isKind = (WAY_KINDS as readonly string[]).includes(way);
  const relay = isKind ? null : relays.find((u) => sameUrl(u) === sameUrl(way)) ?? null;
  if (!isKind && relay === null) throw new WaysRefusal("no such way: a relay of the workspace's, or ours, lan, tailnet, direct");
  const id = relay ?? way;
  return ways.change(ws, (now) => {
    const off = now.off.filter((w) => (id === "ours" ? w !== "ours" && !ours.some((o) => sameUrl(o) === sameUrl(w)) : isKind ? w !== id : sameUrl(w) !== sameUrl(id)));
    if (!on) off.push(id);
    const isRelayOff = (u: string) => off.some((w) => sameUrl(w) === sameUrl(u)) || (off.includes("ours") && ours.some((o) => sameUrl(o) === sameUrl(u)));
    if (relays.every(isRelayOff)) throw new WaysRefusal("the last relay stays on: the web app and a device new to the workspace reach its stations by relays alone");
    return { ...now, off };
  });
}

// ── between the workspace's stations ──

/// A peer's `ways.*` request, in the workspace it was asked in (the transport checked the peer is of it).
export function answerWays(ways: Ways, request: any, workspace: string): unknown {
  switch (request?.method) {
    case "ways.get":
      return { record: ways.record(workspace) };
    case "ways.put": {
      const record = recordOf(request.record);
      if (record === null) throw new Error("a malformed ways record");
      return { taken: ways.take(workspace, record) };
    }
  }
  throw new Error("unknown ways method");
}

/// Brings one peer and this station level in `ws`: the newer record of the two kept by both.
async function level(ways: Ways, call: PeerCall, peer: string, ws: string, home: boolean): Promise<void> {
  const got: any = await call(peer, home ? null : ws, { method: "ways.get" });
  const theirs = recordOf(got?.record);
  const mine = ways.record(ws);
  if (theirs !== null && (mine === null || newer(theirs, mine))) ways.take(ws, theirs);
  else if (mine !== null && (theirs === null || newer(mine, theirs))) await call(peer, home ? null : ws, { method: "ways.put", record: mine });
}

/// A station from before the ways were the stations': nothing to bring level with it.
const before = (e: unknown) => /unknown (ways )?method|no such method|not found/i.test((e as Error)?.message ?? "");

/// Whenever a workspace's ways change here, or a roster comes, each of its stations is brought level with this one; one
/// that could not be (offline, the line between them down) is tried again, sooner at first, until it is.
export function followWays(ways: Ways, call: PeerCall, after: (ms: number, f: () => void) => () => void = wall.after): () => void {
  const cloud = ways.cloud;
  // Each workspace's peer: the record this station had when last brought level with it; one being brought level now;
  // one that failed, how long it waits and whether that wait is over.
  const levelAt = new Map<string, string>();
  const going = new Set<string>();
  const retries = new Map<string, { wait: number; due: boolean; cancel: () => void }>();
  let stopped = false;
  const bring = (peer: string, ws: string, home: boolean) => {
    const key = `${ws}|${peer}`;
    const r = ways.record(ws);
    const at = r === null ? "" : `${r.at}:${r.station}`;
    const retry = retries.get(key);
    if (levelAt.get(key) === at || going.has(key) || (retry !== undefined && !retry.due)) return;
    going.add(key);
    level(ways, call, peer, ws, home).then(
      () => {
        const now = ways.record(ws);
        levelAt.set(key, now === null ? "" : `${now.at}:${now.station}`);
        retries.delete(key);
      },
      (e) => {
        // One from before: nothing of the ways there; level with it until this station's change again.
        if (before(e)) {
          levelAt.set(key, at);
          retries.delete(key);
          return;
        }
        log.info("mesh", "a station's ways were not brought level", { peer: peer.slice(0, 12), workspace: ws, error: (e as Error).message });
        if (stopped) return;
        const wait = retry === undefined ? RETRY_MS : Math.min(retry.wait * 2, RETRY_MOST_MS);
        const next = { wait, due: false, cancel: () => {} };
        next.cancel = after(wait, () => {
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
    if (stopped || !st || !cloud.peersCurrent) return;
    for (const m of cloud.memberships()) for (const p of m.peers) if (typeof p?.id === "string" && p.id !== st.station) bring(p.id, m.workspace, m.home);
  };
  look();
  const unlistenCloud = cloud.listen(look);
  const unlistenWays = ways.listen(look);
  return () => {
    stopped = true;
    unlistenCloud();
    unlistenWays();
    for (const r of retries.values()) r.cancel();
    retries.clear();
  };
}

// ── to the members' devices ──

export type Tell = (event: string, data: unknown, of: string, to: { workspace: string }) => void;

/// Tells each change of a workspace's ways to its members' devices (`ways`, `{workspace}`): they read `GET /ways` again.
/// Where this station keeps none yet, the ways as still.fail cloud keeps them, changed there (by an app from before).
export function tellWays(ways: Ways, tell: Tell): () => void {
  const told = (workspace: string) => tell("ways", { workspace }, `ways\0${workspace}`, { workspace });
  const said = new Map<string, string>();
  const look = () => {
    for (const m of ways.cloud.memberships()) {
      const now = JSON.stringify(ways.cloud.waysSaid(m.workspace));
      const was = said.get(m.workspace);
      said.set(m.workspace, now);
      if (was !== undefined && was !== now && ways.record(m.workspace) === null) told(m.workspace);
    }
  };
  look();
  const unlistenCloud = ways.cloud.listen(look);
  const unlistenWays = ways.listen(told);
  return () => {
    unlistenCloud();
    unlistenWays();
  };
}
