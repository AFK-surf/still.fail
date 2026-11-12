// Where the station stands with still.fail cloud: <data>/mesh/cloud.json (its fields, mode and pretty JSON as the Rust
// station writes them: the desktop app and `bin/stillfail` read it too). One copy in memory, written through on every
// change and told to whoever listens; the file is watched only for `enroll` writing it from another process.
import { type FSWatcher, existsSync, mkdirSync, readFileSync, renameSync, rmSync, watch } from "node:fs";
import { dirname, join } from "node:path";
import { nowSecs, writePrivate } from "../ops/files.ts";
import { wall } from "../ops/fibers.ts";
import { readJsonFile } from "../ops/json-file.ts";
import { log } from "../ops/log.ts";
import { setStationCloud } from "../ops/i18n.ts";
import { createHash } from "node:crypto";
import { type Entry, type LockState, apply, asEntry, canonical, entryHash, fold, genesis, lockChain, sayWord, state4, wsTag } from "./lock.ts";
import { type BodyRefused, LockBodies } from "./lock-bodies.ts";
import { type Kept, type LogRules, type OffChain, hashOf, keep, rechoose } from "./log-keep.ts";
import { PersonChains } from "../mesh/person-chains.ts";
import { type Provider, providerOf } from "./provider.ts";

export type Revocation = { kind: string; id: string; at: number };

/// A workspace the station is in besides its home one: what it is called there, the other
/// stations there and what that workspace takes back.
/// `locked`: that workspace is in security mode, as the control plane says (its lock is pinned here before any of its
/// members is taken).
export type Joined = { workspace: string; workspace_name: string; name: string; peers: any[]; revocations: Revocation[]; locked?: true; rigs?: Rig[]; ways?: WaysSaid };

/// A workspace's own relays and the ways its members' devices do not take to its stations (`lan`, `tailnet`, `direct`,
/// a relay's URL), as still.fail cloud kept them before the stations did: what a station takes as its first of them
/// where it holds none yet (mesh/ways.ts). Absent from planes of before, and from Comma's.
export type WaysSaid = { relays: string[]; off: string[] };

/// A rig of a workspace (a station that only runs tasks): a machine that only runs what the workspace's stations send it, its person's
/// (`owner`, who added it), as the control plane names it. In security mode that is not taken on the plane's word:
/// `Cloud.rigVouched` says which of them its person signed for (rigs/adds.ts).
export type Rig = { id: string; name: string; owner: string; owner_email: string; owner_name: string; version?: string | null };

/// What this machine is when it is a rig: whose (`owner`, as the control plane said when it joined), and the hash of
/// that person's own lock, which the command that added it named (`person`: the rig takes only what a key on it
/// signed, rig/grants.ts).
export type RigSelf = { owner: string; owner_email: string; owner_name: string; person: string };

/// One of the workspaces the station is in, its home one (cloud.json's top level) or a joined one.
/// Why a station `Cloud.unprotected` names cannot be called (its refusal, and its line in station_list): an agent took
/// the plain "not another station" for a bug (FB-11). What is to be done, in the app's words for it.
export const UNPROTECTED =
  "that station is in this workspace but not protected by its safe mode (安全模式): it was offline or too old when safe mode was turned on. It is not a bug: stations safe mode protects run no remote tasks for an unprotected one, nor share with it, and it cannot be called from here. An owner or admin of the workspace protects it in the app's Settings → Security (设置 → 安全) with Protect (保护), updating it first if it is too old.";
export type Membership = Joined & { home: boolean };

export type CloudState = {
  /// The control plane it is enrolled in (cloud/provider.ts): absent is still.fail cloud, as files from before say.
  provider?: Provider;
  origin: string;
  station: string;
  workspace: string;
  workspace_name: string;
  name: string;
  relay_url: string;
  /// Every relay, still.fail's (`relay_url`) first; missing from files of before there were several.
  relay_urls: string[];
  grant_keys: any;
  /// The workspace's stations this one may call (peer RPC); none from old clouds.
  peers: any[];
  revocations: Revocation[];
  /// The iroh ids that may call the device tools (Comma's gateways); absent from still.fail cloud.
  gateway_keys?: string[];
  /// When the cloud said the station was removed from its workspace (unix seconds), and how (4004 / 404).
  removed_at?: number;
  removed_code?: number;
  /// The workspaces it joined besides its home one (the top level), as the control plane's `state` frame said last;
  /// absent from files of before, and from stations in one workspace.
  joined?: Joined[];
  /// The home workspace's rigs, as the control plane said last; absent from planes of before them.
  rigs?: Rig[];
  /// The home workspace's own relays and ways turned off, as the control plane kept them (WaysSaid).
  ways?: WaysSaid;
  /// This machine is a rig, not a whole station: a station that only runs tasks (set by `enroll --rig`, or by
  /// `rig_due` below; never by the control plane's word alone).
  rig?: RigSelf;
  /// A whole station asked to run only tasks from now on, by a member's device that reached it itself (rigs/module.ts
  /// `POST /mode`): whose it will be (who asked; the control plane lets only its owner list it so), and their own
  /// lock to pin. Good for `MODE_PENDING_S` from `at`.
  rig_pending?: RigSelf & { at: number };
  /// The control plane lists it as that person's rig now (cloud/presence.ts): it stops what it runs as a station and
  /// becomes one (sessions/agents.ts).
  rig_due?: true;
  /// A rig its person signed whole again (rig/module.ts `rig.full`), at `at`: it becomes a station once the control
  /// plane lists it as one.
  full_pending?: { at: number };
};

/// How long a change of a station's mode asked of the machine waits for the control plane to list it so.
export const MODE_PENDING_S = 3600;

/// What a rig keeps of its person's grants (rig/grants.ts): gone with every change of what the machine is, so one
/// person's are never read under another's lock.
export const rigGrantsPath = (data: string) => join(data, "rig", "grants.json");

export const meshDir = (data: string) => join(data, "mesh");
const statePath = (data: string) => join(meshDir(data), "cloud.json");
/// The workspace's lock this station pinned (cloud/lock.ts): `{entries}`, from its genesis.
export const lockPath = (data: string) => join(meshDir(data), "lock.json");
/// The lock `enroll --lock <hash>` said to pin once the control plane brings it: `{hash}`.
export const pendingLockPath = (data: string) => join(meshDir(data), "lock-pending.json");
/// A workspace the station joined: the lock it pinned there, and the one joining said to pin,
/// beside the home one's, by the workspace's id.
const fileOf = (ws: string) => (/^[0-9A-Za-z_-]{1,64}$/.test(ws) ? ws : Buffer.from(ws).toString("hex").slice(0, 64));
export const joinedLockPath = (data: string, ws: string) => join(meshDir(data), "locks", `${fileOf(ws)}.json`);
/// The locks a workspace's owner turned off here (beside its lock.json, `{genesis: [hash]}`): none is pinned again. Each
/// device that changed one before brings it the whole chain up to then, and one coming after the `disable` (its
/// answer slower than the control plane's) would lock the station again in a lock no longer on anywhere else.
///
/// With every branch kept (2026-11-12) a `disable` can lose its place to an entry after the same parent that another
/// station took first: what was kept of the lock as it was turned off is kept beside (`logs`, by genesis, the last few),
/// and where what a device brings later makes the chain the rules choose one that is not turned off, it is on again here
/// (Cloud.keepLock), as it is at the stations that took the other first.
const turnedOffPath = (path: string) => `${path}.off`;
/// How far ahead of this station's clock a web device's `at` may be and still count (rules/src/lock/state4.mbt
/// `web_skew_secs`).
const WEB_SKEW = 600;
/// How many locks turned off keep what was kept of them beside.
const OFF_LOGS = 4;
function readOff(path: string): { genesis: string[]; logs: Record<string, Kept> } {
  try {
    const raw = JSON.parse(readFileSync(turnedOffPath(path), "utf8")); // sync: one step with the entries it judges, as it was read before
    const g = raw?.genesis;
    const logs: Record<string, Kept> = {};
    for (const [h, l] of Object.entries(raw?.logs ?? {})) {
      const entries = Array.isArray((l as any)?.entries) ? (l as any).entries.map(asEntry) : [];
      const aside = Array.isArray((l as any)?.aside) ? (l as any).aside.map(asEntry) : [];
      if (entries.length > 0 && !entries.some((e: Entry | null) => e === null)) logs[h] = { entries, aside: aside.filter((e: Entry | null): e is Entry => e !== null) };
    }
    return { genesis: Array.isArray(g) ? g.filter((h): h is string => typeof h === "string") : [], logs };
  } catch {
    return { genesis: [], logs: {} };
  }
}
/// The record of the locks turned off here, with `genesis` the one off now (and what was kept of it) or none.
function writeOff(path: string, off: { genesis: string[]; logs: Record<string, Kept> }) {
  const genesis = off.genesis.slice(-16);
  const kept = Object.keys(off.logs).filter((h) => genesis.includes(h)).slice(-OFF_LOGS);
  writePrivate(turnedOffPath(path), JSON.stringify({ genesis, ...(kept.length > 0 ? { logs: Object.fromEntries(kept.map((h) => [h, off.logs[h]])) } : {}) }));
}
export const joinedPendingPath = (data: string, ws: string) => join(meshDir(data), "locks", `${fileOf(ws)}.pending.json`);
/// The bodies of a workspace's statements kept here (cloud/lock-bodies.ts), beside its lock, by the workspace's id (the
/// home one's too: it stays where it is when a joined workspace takes over as home).
export const bodiesPath = (data: string, ws: string) => join(meshDir(data), "locks", `${fileOf(ws)}.bodies.json`);

/// What a device is told where a workspace's chain moved to its people's logs and this station has not the root's log
/// or its `open` in force yet (Cloud `locked`'s `waiting`): nobody is let in until a trusted device or another station
/// of the workspace brings them, the next one that does mending it.
export const NOT_GIVEN = "this station has not yet been given this workspace's settings by a trusted device: connect from a device of the workspace's owner, or wait for another of its stations to bring them";

/// The person logs of each Cloud (mesh/person-chains.ts), made on first use: a Cloud made without its constructor, as
/// tests make one, has its own too.
const personChains = new WeakMap<object, PersonChains>();
export function personChainsOf(cloud: Cloud): PersonChains {
  let c = personChains.get(cloud);
  if (c === undefined) {
    personChains.set(cloud, (c = new PersonChains(cloud.data === undefined ? null : join(meshDir(cloud.data), "person-chains.json"))));
    if (cloud instanceof Cloud) cloud.heardPersons(c);
  }
  return c;
}

/// A workspace's state where its chain moved, as made last (Cloud `forceOf`): of which kept lock, which logs and
/// bodies, good from `from` until `until` by this station's clock (a web device counting or run out between).
type InForce = {
  lock: KeptLock;
  ver: string;
  from: number;
  until: number;
  on: "on" | "off" | "not on" | "no root";
  out: { state: LockState; waiting?: true };
  needs: Set<string>;
  word: string;
};

/// A pinned lock as kept: its active chain (`entries`, from its genesis), the entries the rules take that are off it
/// (`aside`), and the state of the chain (null: its file is broken, nobody is admitted).
export type KeptLock = { entries: Entry[]; aside?: Entry[]; state: LockState | null };

/// The pinned lock as lock.json has it (a joined workspace's: its own file): null without one. `entries` is its active
/// chain in order, as every reader from before reads it; `aside`, absent from files of before 2026-11-12 and while none
/// is, the entries kept off it (cloud/log-keep.ts): the chain is chosen again among all of them as it is read. A file
/// that does not hold a lock (edited by hand, cut short) is a lock that admits nobody: refusing is safer than trusting
/// the control plane again by itself.
export function readLock(data: string, ws: string | null = null): KeptLock | null {
  const path = ws === null ? lockPath(data) : joinedLockPath(data, ws);
  if (!existsSync(path)) return null;
  let read: { entries: Entry[]; aside: Entry[]; state: LockState };
  try {
    const raw = JSON.parse(readFileSync(path, "utf8"));
    const entries = (Array.isArray(raw?.entries) ? raw.entries : []).map(asEntry);
    if (entries.some((e: Entry | null) => e === null)) throw new Error("an entry is malformed");
    const aside = (Array.isArray(raw?.aside) ? raw.aside : []).map(asEntry).filter((e: Entry | null): e is Entry => e !== null);
    read = { entries, aside, state: fold(entries, null) };
  } catch (e) {
    log.warn("lock", "lock.json holds no valid lock; nobody is admitted until `stillfail lock reset`", { error: (e as Error).message });
    return { entries: [], state: null };
  }
  if (read.aside.length === 0) return { entries: read.entries, state: read.state };
  try {
    const { kept } = rechoose(read, lockRules(read.state, null, new Map()));
    const same = kept.entries.length === read.entries.length && kept.entries.every((e, i) => hashOf(e) === hashOf(read.entries[i]!));
    return { entries: kept.entries, aside: kept.aside, state: same ? read.state : fold(kept.entries, null) };
  } catch (e) {
    log.warn("lock", "the entries kept off the lock's chain could not be read; it goes by its chain", { error: (e as Error).message });
    return { entries: read.entries, state: read.state };
  }
}

/// The workspace lock's rules for keeping (cloud/log-keep.ts), of the lock whose chain's state is `s`: entries of its
/// workspace, each checked after its parent with the station's time `now` (none: taken before), the states after the
/// entries kept made once (`states`, by hash).
function lockRules(s: LockState, now: number | null, states: Map<string, LockState>): LogRules {
  states.set(s.head, s);
  return {
    chain: (all) => lockChain(all, s.genesis),
    pre: (e) => (e.ws !== s.ws ? "an entry of another workspace's lock" : null),
    now: now === null ? undefined : (parent, e, find) => {
      const at = stateAt(parent, find, states);
      if (at === null) return null;
      try {
        apply(at, e, now);
        return null;
      } catch (error) {
        return (error as Error).message;
      }
    },
  };
}

/// The lock's state after the entry of hash `h`, from the nearest state made (`states`) along its parents; null where
/// they do not go back to one (the chain says why).
function stateAt(h: string, find: (hash: string) => Entry | undefined, states: Map<string, LockState>): LockState | null {
  const path: Entry[] = [];
  let at: string | null = h;
  while (at !== null && !states.has(at)) {
    const e = find(at);
    if (e === undefined) return null;
    path.push(e);
    at = e.prev;
  }
  let s: LockState | null = at === null ? null : states.get(at)!;
  for (const e of path.reverse()) {
    try {
      s = s === null ? genesis(e) : apply(s, e, null);
    } catch {
      return null;
    }
    states.set(hashOf(e), s);
  }
  return s;
}

/// A lock turned off here (`off`, its genesis `g`) with `brought` taken into what was kept of it: the chain the rules
/// choose and its state where that is not turned off; else null, or "kept" where what was kept beside changed (in `off`).
function onAgain(off: { genesis: string[]; logs: Record<string, Kept> }, g: string, brought: Entry[], now: number): { kept: Kept; state: LockState; taken: number } | "kept" | null {
  const was = off.logs[g];
  if (was === undefined) return null;
  try {
    const t = keep(was, brought, lockRules(fold(was.entries, null), now, new Map()));
    const state = fold(t.kept.entries, null);
    if (!state.disabled) return { kept: t.kept, state, taken: t.taken };
    if (t.changed) {
      off.logs[g] = t.kept;
      return "kept";
    }
  } catch {}
  return null;
}

/// What a station answers an entry that lost its place, or that disagrees with the chain it goes by and follows none it
/// keeps: as it answered a fork before it kept every branch (an app from before calls an answer "taken" whose head is
/// as far as its entry, so the words and status stay).
export const FORK = "the entry disagrees with this station's lock (a fork)";

/// What taking entries of a lock did: how many were kept that were not (on the chain or aside), each one brought that
/// is not on the chain now and why, and the refusal an answer from before gave (none where all are on it).
export type LockTook = { taken: number; off: OffChain[]; refusal: Error | null };

/// What is kept of a lock, as a word that changes when any of it does.
const keptText = (l: KeptLock | null | undefined) => JSON.stringify(l === null || l === undefined ? null : [l.entries, l.aside ?? []]);

/// still.fail cloud's host before the rename, and its host now: a station enrolled then has the old one in cloud.json
/// (its origin, its relays), moved to the new one when the station starts. The cloud answers both until the old goes.
const FORMER_HOST = "https://ember.3720.org";
const HOST = "https://app.still.fail";

/// cloud.json with the old host (FORMER_HOST) in it, written with the new one; anything else left as it is.
export function moveFormerHost(data: string) {
  if (!existsSync(statePath(data))) return;
  const text = readFileSync(statePath(data), "utf8");
  if (!text.includes(FORMER_HOST)) return;
  const raw = JSON.parse(text);
  const moved = (url: unknown) => (typeof url === "string" && (url === FORMER_HOST || url.startsWith(`${FORMER_HOST}/`)) ? HOST + url.slice(FORMER_HOST.length) : url);
  raw.origin = moved(raw.origin);
  if (raw.relay_url !== undefined) raw.relay_url = moved(raw.relay_url);
  if (Array.isArray(raw.relay_urls)) raw.relay_urls = raw.relay_urls.map(moved);
  writePrivate(statePath(data), JSON.stringify(raw, null, 2));
  log.info("cloud", "moved to still.fail cloud's host", { from: FORMER_HOST, to: HOST });
}

/// The state as the file has it, its optional parts filled as the Rust station's serde defaults fill them.
export function readState(data: string): CloudState | null {
  if (!existsSync(statePath(data))) return null;
  const raw = readJsonFile(statePath(data));
  const state: CloudState = { ...raw, relay_urls: raw.relay_urls ?? [], peers: raw.peers ?? [], revocations: raw.revocations ?? [] };
  if (raw.joined !== undefined) state.joined = joinedOf(raw.joined);
  if (raw.provider !== undefined) state.provider = providerOf(raw.provider);
  if (raw.rigs !== undefined) state.rigs = rigsOf(raw.rigs);
  const ways = waysSaidOf(raw.ways);
  if (ways !== null) state.ways = ways;
  else delete state.ways;
  const rig = rigSelfOf(raw.rig);
  if (rig !== null) state.rig = rig;
  else delete state.rig;
  const at = (v: any) => Number.isSafeInteger(v?.at);
  const pending = rigSelfOf(raw.rig_pending);
  if (pending !== null && at(raw.rig_pending)) state.rig_pending = { ...pending, at: raw.rig_pending.at };
  else delete state.rig_pending;
  if (raw.rig_due !== true || state.rig_pending === undefined) delete state.rig_due;
  if (at(raw.full_pending)) state.full_pending = { at: raw.full_pending.at };
  else delete state.full_pending;
  return state;
}

const HEX32 = /^[0-9a-f]{64}$/;

/// The rigs a file or a `state` frame names, what is malformed in them left out.
export function rigsOf(raw: unknown): Rig[] {
  if (!Array.isArray(raw)) return [];
  const text = (v: unknown) => (typeof v === "string" ? v : "");
  return raw.flatMap((r: any) =>
    typeof r?.id === "string" && HEX32.test(r.id) && typeof r.owner === "string" && r.owner !== ""
      ? [{ id: r.id, name: text(r.name), owner: r.owner, owner_email: text(r.owner_email), owner_name: text(r.owner_name), ...(typeof r.version === "string" ? { version: r.version } : {}) }]
      : [],
  );
}

function rigSelfOf(raw: any): RigSelf | null {
  if (raw === null || typeof raw !== "object" || typeof raw.owner !== "string" || raw.owner === "" || typeof raw.person !== "string" || !HEX32.test(raw.person)) return null;
  return { owner: raw.owner, owner_email: typeof raw.owner_email === "string" ? raw.owner_email : "", owner_name: typeof raw.owner_name === "string" ? raw.owner_name : "", person: raw.person };
}

/// Pretty JSON, field order as the Rust struct's, the removal only while there is one; the provider and the gateways
/// only when there are (a still.fail station's file is as it always was).
export function writeState(data: string, s: CloudState) {
  const out: Record<string, unknown> = {
    ...(s.provider !== undefined ? { provider: s.provider } : {}),
    origin: s.origin, station: s.station, workspace: s.workspace, workspace_name: s.workspace_name, name: s.name,
    relay_url: s.relay_url, relay_urls: s.relay_urls, grant_keys: s.grant_keys, peers: s.peers, revocations: s.revocations,
  };
  if (s.gateway_keys !== undefined) out.gateway_keys = s.gateway_keys;
  if (s.removed_at !== undefined) out.removed_at = s.removed_at;
  if (s.removed_code !== undefined) out.removed_code = s.removed_code;
  if (s.joined !== undefined && s.joined.length > 0) out.joined = s.joined;
  if (s.rigs !== undefined && s.rigs.length > 0) out.rigs = s.rigs;
  if (s.ways !== undefined) out.ways = s.ways;
  if (s.rig !== undefined) out.rig = s.rig;
  if (s.rig_pending !== undefined) out.rig_pending = s.rig_pending;
  if (s.rig_due === true) out.rig_due = true;
  if (s.full_pending !== undefined) out.full_pending = s.full_pending;
  writePrivate(statePath(data), JSON.stringify(out, null, 2));
}

/// The joined workspaces a file or a `state` frame's `workspaces` names, what is malformed in them left out.
export function joinedOf(raw: unknown): Joined[] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((j: any) =>
    typeof j?.workspace === "string" && j.workspace !== ""
      ? [{
          workspace: j.workspace,
          workspace_name: typeof j.workspace_name === "string" ? j.workspace_name : j.workspace,
          name: typeof j.name === "string" ? j.name : "",
          peers: Array.isArray(j.peers) ? j.peers : [],
          revocations: Array.isArray(j.revocations) ? j.revocations.filter(isRevocation) : [],
          ...(j.locked === true ? { locked: true as const } : {}),
          ...(Array.isArray(j.rigs) && j.rigs.length > 0 ? { rigs: rigsOf(j.rigs) } : {}),
          ...(waysSaidOf(j.ways) !== null ? { ways: waysSaidOf(j.ways)! } : {}),
        }]
      : [],
  );
}

/// The ways a file or a `state` frame says (WaysSaid); null when it says none.
export function waysSaidOf(raw: any): WaysSaid | null {
  if (raw === null || typeof raw !== "object" || !Array.isArray(raw.relays)) return null;
  const strings = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []);
  return { relays: strings(raw.relays), off: strings(raw.off) };
}

export const isRevocation = (r: any): r is Revocation => typeof r?.kind === "string" && typeof r?.id === "string" && Number.isInteger(r?.at) && r.at >= 0;

/// The state in memory, and who wants to hear of its changes.
export class Cloud {
  state: CloudState | null;
  /// Whether `peers` is taken as the workspace's stations: the roster the cloud said last, kept in cloud.json, through a
  /// presence socket gone and a restart (user, 2026-11-04: a station cut off from the cloud for an hour refused every
  /// other one, a shared Profile's copy among them). Not once the station is removed; a station removed meanwhile is
  /// refused when a fresh roster says so.
  peersCurrent = false;
  /// Whether the roster is the one of the current presence socket (a minute's grace after it ends): the pages say a
  /// station cut off from still.fail cloud.
  reached = false;
  /// How many rosters the control plane said (presence.ts: one said since its socket ended keeps it current).
  rostersSaid = 0;
  /// Runs a device tool request that came over the presence socket (mesh/tools.ts `presenceTools`), while the mesh
  /// is up; null before it.
  toolCalls: ((request: unknown) => Promise<unknown>) | null = null;
  /// The workspace's lock, once pinned (null: none, the control plane is trusted as before). Its state null: lock.json
  /// is broken, nobody is admitted.
  lock: KeptLock | null;
  /// The locks of the workspaces it joined, pinned there, by workspace (read from their files on first use).
  private joinedLocks = new Map<string, KeptLock | null>();
  /// How far the control plane's copy of the lock goes, as its last `state` frame said (null: a plane that keeps none).
  planeLockSeq: number | null = null;
  /// The same of each joined workspace's lock.
  planeLockSeqs = new Map<string, number | null>();
  /// The hash of the control plane's head of each lock (`""` the home one's), as its last `state` frame said (none: it
  /// said none). Where it parted from the one this station goes by (it kept the entry that lost), it is given this
  /// station's as another keeper's (presence.ts `syncLock`, `planeParted`).
  planeLockHashes = new Map<string, string>();
  /// The plane's head found parted from the chain gone by here and this station's head then (`<plane>><here>`), each
  /// pair given this station's chain once, by lock (`""` the home one's).
  planeParted = new Map<string, string>();
  /// Which of a locked workspace's rigs its person signed for (rigs/adds.ts sets it): until then none of them is
  /// taken, the control plane's word counting for nothing there.
  rigVouched: (workspace: string, rig: Rig) => boolean = () => false;
  /// What the control plane last said of the roster and gateways, before the lock filtered them (this run only).
  private planePeers: any[] | null = null;
  private planeGateways: string[] | undefined;
  private listeners = new Set<(s: CloudState | null) => void>();
  /// The bodies kept of each workspace's statements, by its id (read on first use).
  private lockBodies = new Map<string, LockBodies>();
  /// Each moved workspace's state as made last, by its id, and the word of each as last told.
  private inForce = new Map<string, InForce>();
  private toldWords = new Map<string, string>();
  /// Counts each change of the person logs kept.
  private personsVer = 0;
  private writing = false;
  private watcher: FSWatcher | undefined;
  private locksWatcher: FSWatcher | undefined;
  readonly data: string;

  /// `watchFiles`: whether the files are watched for others' changes (tests that start and stop many stations leave it out:
  /// macOS takes a good while to end each watch).
  constructor(data: string, watchFiles = true) {
    this.data = data;
    try {
      moveFormerHost(data);
    } catch (error) {
      log.warn("cloud", "could not move cloud.json to still.fail cloud's host", { error: String(error) });
    }
    this.state = readState(data);
    setStationCloud(this.state?.origin);
    this.peersCurrent = this.state !== null && !this.removed();
    this.lock = readLock(data);
    // `enroll` from another process, or an older tool editing the file; `lock reset` taking the lock away.
    if (watchFiles) try {
      this.watcher = watch(meshDir(data), { persistent: false }, (_, name) => {
        if (name === "cloud.json" && !this.writing) this.reload();
        if (name === "lock.json" && !this.writing) this.reloadLock();
      });
      // The watch failing later (macOS turning it down: EMFILE) ends it, not the station.
      this.watcher.on("error", (error) => {
        log.warn("cloud", "cloud.json no longer watched", { error: error.message });
        this.watcher?.close();
        this.watcher = undefined;
      });
      // The joined workspaces' locks: `lock reset --workspace`, or a join on this machine setting one aside.
      mkdirSync(join(meshDir(data), "locks"), { recursive: true }); // sync: once, as the station starts
      this.locksWatcher = watch(join(meshDir(data), "locks"), { persistent: false }, () => {
        if (!this.writing) this.reloadJoined();
      });
      this.locksWatcher.on("error", (error) => {
        log.warn("cloud", "the joined workspaces' locks no longer watched", { error: error.message });
        this.locksWatcher?.close();
        this.locksWatcher = undefined;
      });
    } catch {
      // No mesh directory yet: `enroll` makes it, and the station is started anew after.
    }
  }

  close() {
    this.watcher?.close();
    this.locksWatcher?.close();
    this.listeners.clear();
  }

  /// The state read again from its file; told when it changed, or anyway (`tell`: the station joined a workspace, and
  /// what to pin there is to be asked for at once, cloud.json as the plane's frame left it or not).
  reload(tell = false) {
    let next: CloudState | null;
    try {
      next = readState(this.data);
    } catch (error) {
      log.warn("cloud", "cloud.json could not be read; keeping the previous state", { error: (error as Error).message });
      return;
    }
    if (tell || JSON.stringify(next) !== JSON.stringify(this.state)) {
      this.state = next;
      setStationCloud(next?.origin);
      this.tell();
    }
  }

  reloadLock() {
    const next = readLock(this.data);
    if (keptText(next) === keptText(this.lock) && (next?.state === null) === (this.lock?.state === null)) return;
    this.lock = next;
    log.info("lock", next === null ? "the workspace lock was taken away on this machine; the control plane is trusted again" : "the workspace lock was read anew");
    this.refilter();
  }

  /// The joined workspaces' locks read again from their files (another process changed one: `lock reset --workspace`, a
  /// join on this machine); told when one did.
  reloadJoined() {
    const locks = (this.joinedLocks ??= new Map());
    const changed = [...locks].filter(([ws, was]) => {
      const now = readLock(this.data, ws);
      return keptText(now) !== keptText(was) || (now?.state === null) !== (was?.state === null);
    });
    if (changed.length === 0) return;
    for (const [ws] of changed) locks.delete(ws);
    log.info("lock", "a joined workspace's lock was changed on this machine", { workspaces: changed.map(([ws]) => ws) });
    this.tell();
  }

  /// Whether `ws` names the home workspace (none named does).
  private isHome(ws: string | null | undefined): boolean {
    return ws === null || ws === undefined || ws === this.state?.workspace;
  }

  /// The lock pinned in `ws` (the home one's when none is named), as its file has it.
  private lockOf(ws: string | null | undefined): KeptLock | null {
    if (this.isHome(ws)) return this.lock;
    // (Made here too: a Cloud made without its constructor, as tests make one, has none yet.)
    const locks = (this.joinedLocks ??= new Map());
    if (!locks.has(ws!)) locks.set(ws!, this.data === undefined ? null : readLock(this.data, ws!));
    return locks.get(ws!) ?? null;
  }

  /// The lock in force in `ws` (the home one when none is named): null when none is pinned (or it was turned off). A
  /// broken lock file is in force and admits nobody (`state` null). Where its chain moved (`moved {root}` on the active
  /// chain, whichever branch the fork choice leaves there: on another, the folded chain is the state again), the state
  /// its people's logs and the bodies kept say by this station's clock (`state4`): off as a lock turned off is, nothing
  /// let go; without the root's log or an `open` in force (`waiting`), a state that names nobody, never the folded
  /// chain's or the control plane's word. What reads the chain itself (its seq, head, genesis: the sync, the cloud's
  /// copy) reads `chain`.
  locked(ws?: string | null): { state: LockState | null; waiting?: true } | null {
    const l = this.lockOf(ws);
    if (l === null || l.state?.disabled) return null;
    const root = l.state?.moved;
    if (root === undefined) return l;
    const f = this.forceOf(ws ?? null, l, root);
    return f.on === "off" ? null : f.out;
  }

  /// The workspace lock's own chain pinned in `ws` as kept (its fold: seq, head and genesis are the chain's), whether
  /// it moved or not: null when none is pinned (or it was turned off).
  chain(ws?: string | null): { state: LockState | null } | null {
    const l = this.lockOf(ws);
    if (l === null || l.state?.disabled) return null;
    return l;
  }

  /// The id of workspace `ws` (the home one when null).
  private idOf(ws: string | null | undefined): string {
    return this.isHome(ws) ? (this.state?.workspace ?? "") : ws!;
  }

  /// The bodies of `ws`'s statements kept here (cloud/lock-bodies.ts).
  bodies(ws: string | null): LockBodies {
    const id = this.idOf(ws);
    const bodies = (this.lockBodies ??= new Map());
    let b = bodies.get(id);
    if (b === undefined) bodies.set(id, (b = new LockBodies(this.data === undefined || id === "" ? null : bodiesPath(this.data, id))));
    return b;
  }

  /// Bodies of `ws`'s statements given by a device or a station of it, each taken where the rules find an entry kept
  /// here that commits to it under the workspace's tag (a lock pinned there: else none); each not, and why. Whatever
  /// is made of them is made again and told.
  takeBodies(ws: string | null, bodies: unknown[]): { taken: number; refused: BodyRefused[] } {
    if (this.lockOf(ws) === null) return { taken: 0, refused: bodies.map(() => ({ hash: null, why: "it names no workspace this keeper keeps" })) };
    const chains = personChainsOf(this);
    this.writing = true;
    let t: { taken: number; refused: BodyRefused[] };
    try {
      t = this.bodies(ws).take(this.idOf(ws), bodies, (h) => chains.commitsTo(h));
    } finally {
      wall.after(100, () => (this.writing = false));
    }
    if (t.taken > 0) this.forceChanged();
    return t;
  }

  /// The person logs `ws`'s state is made of where its chain moved (the root's, each a statement binds a member by,
  /// each holding an entry of its tag): none where it did not.
  needs(ws: string | null): ReadonlySet<string> {
    const l = this.lockOf(ws);
    const root = l?.state?.disabled ? undefined : l?.state?.moved;
    if (l === null || root === undefined) return new Set();
    return this.forceOf(ws, l, root).needs;
  }

  /// The person logs a device of `ws` is given to work out its state itself (GET /lock/logs): those it is made of where
  /// its chain moved (`needs`), else each holding a statement of the workspace; none without a lock pinned there.
  logsOf(ws: string | null): string[] {
    const l = this.lockOf(ws);
    if (l === null || l.state === null) return [];
    const needed = this.needs(ws);
    if (needed.size > 0) return [...needed];
    const id = this.idOf(ws);
    return personChainsOf(this).every().filter(([g, es]) => {
      const t = wsTag(id, g);
      return es.some((e) => e.kind === "ws" && (e.body as { t?: unknown } | null)?.t === t);
    }).map(([g]) => g);
  }

  /// The statements of `ws` on the active chain of a log kept here whose body is not kept, by the body's hash (what a
  /// commitment carries as `h`; the rules' `lacking` names their entries): what this station asks the others for, and
  /// tells devices, so the one that signed one brings it again.
  lacking(ws: string | null): string[] {
    if (this.lockOf(ws) === null) return [];
    const id = this.idOf(ws), bodies = this.bodies(ws), out: string[] = [];
    for (const [g, es] of personChainsOf(this).every()) {
      const t = wsTag(id, g);
      for (const e of es) {
        const b = e.body as { t?: unknown; h?: unknown } | null;
        if (e.kind === "ws" && b?.t === t && typeof b.h === "string" && !bodies.has(b.h)) out.push(b.h);
      }
    }
    return [...new Set(out)];
  }

  /// A word that changes whenever the state in force in `ws` does where its chain moved ("" where it did not): told
  /// to devices with the chain's head (mesh/lock-events.ts), so they read again as a member's log or a body comes.
  forceWord(ws: string | null): string {
    const l = this.lockOf(ws);
    const root = l?.state?.disabled ? undefined : l?.state?.moved;
    if (l === null || root === undefined) return "";
    return this.forceOf(ws, l, root).word;
  }

  /// Told by the person logs as they are made (personChainsOf): a change of any log makes every moved state again, and
  /// what each of them now says, said; the logs a state needs count as heard in its workspace.
  heardPersons(chains: PersonChains) {
    chains.needs = (ws) => this.needs(this.isHome(ws) ? null : ws);
    chains.watch(() => {
      this.personsVer = (this.personsVer ?? 0) + 1;
      this.forceChanged();
    });
  }

  /// Each moved workspace's state made again where what it is made of changed; where what one says did, told (the
  /// home one's stations through the roster, as a lock's change is).
  private forceChanged() {
    let told = false, home = false;
    const locks: [string | null, KeptLock | null][] = [[null, this.lock], ...[...(this.joinedLocks ?? new Map())].map(([ws, l]) => [ws, l] as [string | null, KeptLock | null])];
    for (const [ws, l] of locks) {
      const root = l?.state?.disabled ? undefined : l?.state?.moved;
      if (l === null || l === undefined || root === undefined) continue;
      const id = this.idOf(ws);
      const f = this.forceOf(ws, l, root);
      const word = `${f.on}:${f.word}`;
      if (this.toldWords.get(id) === word) continue;
      this.toldWords.set(id, word);
      told = true;
      if (ws === null) home = true;
    }
    if (home) this.refilter();
    else if (told) this.tell();
  }

  /// `ws`'s state where its chain `l` moved to the log of genesis `root`: made again when the chain, a log kept or a
  /// body changed, or this station's clock passed the next web device's `at - SKEW` or `exp` (no timer: the next one
  /// to ask makes it).
  private forceOf(ws: string | null, l: KeptLock, root: string): InForce {
    const id = this.idOf(ws);
    const now = nowSecs();
    const bodies = this.bodies(ws);
    const ver = `${this.personsVer}:${bodies.version}`;
    const forces = (this.inForce ??= new Map());
    const was = forces.get(id);
    if (was !== undefined && was.lock === l && was.ver === ver && now >= was.from && now < was.until) return was;
    const logs = personChainsOf(this).every();
    const kept = [...bodies.all().values()];
    const s = state4(id, root, logs.map(([, es]) => es), kept, now);
    const out = s.on === "on" || s.on === "off" ? { state: s.state } : { state: state4(id, root, [], [], now).state, waiting: true as const };
    const st = out.state;
    const word = createHash("sha256").update(canonical({
      on: s.on, origins: st.origins, rp_id: st.rp_id, cloud_keys: st.cloud_keys ?? null,
      members: [...st.members].sort(([a], [b]) => (a < b ? -1 : 1)), persons: [...st.persons].sort(([a], [b]) => (a < b ? -1 : 1)),
      devices: [...st.devices.keys()].sort(), stations: [...st.stations.keys()].sort(),
    })).digest("hex");
    sayWord(st, word);
    // (what the state is made of: the root's log, each one a member is bound by, each holding a statement of this
    // workspace)
    const needs = new Set<string>([root, ...s.state.persons.values()]);
    let from = -Infinity, until = Infinity;
    for (const [g, es] of logs) {
      const t = wsTag(id, g);
      for (const e of es) {
        if (e.kind === "ws" && (e.body as { t?: unknown } | null)?.t === t) needs.add(g);
        if (e.kind !== "web") continue;
        for (const x of [e.at - WEB_SKEW, Number((e.body as { exp?: unknown } | null)?.exp)]) {
          if (!Number.isFinite(x)) continue;
          if (x <= now) from = Math.max(from, x);
          else until = Math.min(until, x);
        }
      }
    }
    const f: InForce = { lock: l, ver, from, until, on: s.on, out, needs, word };
    forces.set(id, f);
    return f;
  }

  /// The credential keys that count in `ws`: its lock's once pinned, else the control plane's.
  grantKeys(ws?: string | null): any {
    const l = this.locked(ws);
    return l === null ? this.state?.grant_keys : (l.state?.cloud_keys ?? null);
  }

  /// The lock hash joining `ws` said to pin once the control plane brings that lock (none: it joined an unlocked one).
  pendingLock(ws: string): string | null {
    try {
      const hash = JSON.parse(readFileSync(joinedPendingPath(this.data, ws), "utf8"))?.hash;
      return typeof hash === "string" && /^[0-9a-f]{64}$/.test(hash) ? hash : null;
    } catch {
      return null;
    }
  }

  /// A joined workspace the control plane no longer names: not served (memberships), but its lock and what joining
  /// named to pin are kept, and go on deciding once it is named again. Only the plane said so, which may hold the
  /// workspace back for a frame and name it again unlocked: the lock is let go only by its own `disable`, on this machine
  /// (`lock reset --workspace`, a join there naming another: cli.ts), or by `succeed`.
  leftJoined(ws: string) {
    this.planeLockSeqs.delete(ws);
  }

  /// A workspace it joined takes over as its home one, the home it was taken out of gone (or, its home not locked, any
  /// the plane makes its home that it keeps a lock for: presence.ts `took`): that
  /// workspace's lock, pinned or named by joining, is the home one's now (lock.json, lock-pending.json), the old home's
  /// forgotten. Refused (false) while the home one is locked and that workspace's lock is not pinned here: the station
  /// stays where its lock keeps it.
  succeed(ws: string): boolean {
    if (this.chain() !== null && this.chain(ws) === null) return false;
    this.writing = true;
    try {
      for (const [from, to] of [[joinedLockPath(this.data, ws), lockPath(this.data)], [joinedPendingPath(this.data, ws), pendingLockPath(this.data)]] as const) {
        if (existsSync(from)) renameSync(from, to);
        else rmSync(to, { force: true });
      }
    } finally {
      wall.after(100, () => (this.writing = false));
    }
    this.lock = readLock(this.data);
    this.joinedLocks.delete(ws);
    this.planeLockSeqs.delete(ws);
    log.info("lock", "a workspace this station joined took over as its home one; its lock is the home one's now", { workspace: ws, locked: this.lock !== null });
    return true;
  }

  /// What the control plane says of the roster and gateways (a `state` frame), kept as the lock lets it: only stations
  /// and gateways in the lock too. The control plane can leave one out, never add one.
  setPlaneLists(peers: any[], gateways: string[] | undefined) {
    this.planePeers = peers;
    this.planeGateways = gateways;
  }

  /// The roster and gateways as the lock lets them, from what the control plane said last.
  filtered(st: CloudState) {
    const peers = this.planePeers ?? st.peers;
    const gateways = this.planeGateways ?? st.gateway_keys;
    const l = this.locked();
    if (l === null) return { peers, gateways };
    const s = l.state;
    return {
      peers: peers.filter((p) => s !== null && typeof p?.id === "string" && s.stations.has(p.id)),
      gateways: gateways === undefined ? undefined : gateways.filter((g) => s !== null && s.gateways.has(g)),
    };
  }

  /// The stations the control plane lists in `ws` (the home one when none is named) that the lock in force there leaves
  /// out: not protected by safe mode (offline or too old when it was turned on), so the stations it protects neither
  /// call them nor take their calls. Said to agents (`UNPROTECTED`) instead of letting them vanish. Empty without a
  /// lock, with a broken one, and for the home one until the control plane's first roster of this run.
  unprotected(ws?: string | null): any[] {
    const s = this.locked(ws)?.state;
    if (!s || !this.state) return [];
    const listed = this.isHome(ws) ? (this.planePeers ?? []) : ((this.state.joined ?? []).find((j) => j.workspace === ws)?.peers ?? []);
    return listed.filter((p) => typeof p?.id === "string" && p.id !== this.state!.station && !s.stations.has(p.id));
  }

  private refilter() {
    if (!this.state) return this.tell();
    this.update((st) => {
      const { peers, gateways } = this.filtered(st);
      st.peers = peers;
      if (gateways !== undefined) st.gateway_keys = gateways;
    });
  }

  /// Pins a lock (its whole chain, from genesis), or takes more of the pinned one (keepLock). Returns how many entries
  /// were kept that were not; where none was, throws why the first one brought that is not on the chain is not, as
  /// before every branch was kept (a fork, the rules' refusal).
  takeLock(entries: Entry[], ws: string | null = null, fork = false): number {
    const t = this.keepLock(entries, ws, fork);
    if (t.refusal !== null && t.taken === 0) throw t.refusal;
    if (t.refusal !== null) log.warn("lock", "a lock entry was refused", { error: t.refusal.message });
    return t.taken;
  }

  /// Pins a lock (its genesis first, which must be of this workspace and not one turned off here: else throws why), or
  /// takes more of the pinned one.
  ///
  /// `fork`: entries another keeper already took (a station of the lock, or a device saying so: `keep`), every one the
  /// rules take after a parent kept, in any order, also one off the chain gone by (cloud/log-keep.ts); the chain is the
  /// rules' fork choice among all it keeps, and one that wins at its parent moves it to that branch. Else (what a
  /// device brings itself, the hello's, the control plane's) only what goes on from the head, in order, as always: one
  /// that does not is refused and not kept (`not on the head`), its signer at hand to sign it again after the head. So
  /// this station changes branch only for what another took first, never for a fork it would be the first to make: a
  /// device of today's core, which only goes on from what it read, is never left on an entry the station moved off for
  /// one that came to it alone (2026-11-12). Refusing to keep a fresh entry decides nothing for anyone else (any keeper
  /// may drop one), every keeper holding the same entries still chooses the same chain, and the stations of a lock still
  /// give each other all they keep.
  keepLock(entries: Entry[], ws: string | null = null, fork = false): LockTook {
    const home = this.isHome(ws);
    const now = nowSecs();
    const current = this.lockOf(ws);
    const had = current?.state ? current : null;
    if (current !== null && had === null) throw new Error("this station's lock.json is broken; run `stillfail lock reset` on it");
    const workspace = home ? this.state?.workspace : ws!;
    const path = home ? lockPath(this.data) : joinedLockPath(this.data, ws!);
    let kept: Kept = { entries: had?.entries ?? [], aside: had?.aside ?? [] };
    let state = had?.state ?? null;
    let taken = 0;
    let changed = false;
    let rest = entries;
    let off: OffChain[] = [];
    if (state === null) {
      const e = entries[0];
      if (e === undefined) return { taken: 0, off: [], refusal: null };
      if (workspace !== undefined && e.ws !== workspace) throw new Error("the lock is another workspace's");
      const wasOff = readOff(path);
      const back = fork && wasOff.genesis.includes(entryHash(e)) ? onAgain(wasOff, entryHash(e), entries, now) : null;
      if (back === "kept") this.offWritten(path, wasOff);
      if (wasOff.genesis.includes(entryHash(e)) && (back === null || back === "kept")) throw new Error("this lock was turned off by its owner here; it is not taken again");
      if (back !== null && back !== "kept") {
        // Its `disable` lost its place to what was brought: on again, as where that was taken first.
        this.offWritten(path, { genesis: wasOff.genesis.filter((h) => h !== entryHash(e)), logs: wasOff.logs });
        state = back.state;
        kept = back.kept;
        taken = back.taken;
        rest = [];
        log.info("lock", "the workspace lock is on again here: its owner's disable lost its place to an entry after the same one", { seq: state.seq, ...(home ? {} : { workspace: ws }) });
      } else {
        state = fold([e], now);
        kept = { entries: [e], aside: [] };
        taken = 1;
        rest = entries.slice(1);
      }
      changed = true;
    }
    const head = state.head;
    const known = new Set([...kept.entries, ...kept.aside].map(hashOf));
    const fresh = rest.filter((e) => !known.has(hashOf(e)) && (known.add(hashOf(e)), true));
    if (!fork || (kept.aside.length === 0 && fresh.every((e, i) => e.prev === (i === 0 ? head : hashOf(fresh[i - 1]!))))) {
      // On from the head alone, as always: each checked after the last, none after one refused or not on the head.
      for (const e of fresh) {
        if (e.prev !== state.head) {
          off = [{ why: "not on the head", hash: hashOf(e), seq: e.seq, kept: false }];
          break;
        }
        try {
          if (e.ws !== state.ws) throw new Error("an entry of another workspace's lock");
          state = apply(state, e, now);
          kept = { entries: [...kept.entries, e], aside: kept.aside };
          taken++;
          changed = true;
        } catch (error) {
          off = [{ why: "refused", refusal: (error as Error).message, hash: hashOf(e), seq: e.seq, kept: false }];
          break;
        }
      }
    } else {
      const t = keep(kept, rest, lockRules(state, now, new Map()));
      if (t.changed) {
        changed = true;
        taken += t.taken;
        if (t.moved || t.kept.entries.length !== kept.entries.length) state = fold(t.kept.entries, null);
        kept = t.kept;
      }
      off = t.off;
    }
    const on = new Set(kept.entries.map(hashOf));
    const refusal = this.refusalOf(entries, on, off, state, now);
    if (changed) {
      const set = (l: KeptLock | null) => (home ? (this.lock = l) : this.joinedLocks.set(ws!, l));
      this.writing = true;
      try {
        mkdirSync(dirname(path), { recursive: true });
        writePrivate(path, JSON.stringify(kept.aside.length > 0 ? { entries: kept.entries, aside: kept.aside } : { entries: kept.entries }, null, 2));
      } finally {
        wall.after(100, () => (this.writing = false));
      }
      set({ entries: kept.entries, ...(kept.aside.length > 0 ? { aside: kept.aside } : {}), state });
      const which = home ? {} : { workspace: ws };
      if (state!.disabled) {
        // Off: nothing pinned, the control plane trusted as before (it sends its lists again on the next frame).
        const wasOff = readOff(path);
        this.offWritten(path, { genesis: [...wasOff.genesis.filter((h) => h !== state!.genesis), state!.genesis], logs: { ...wasOff.logs, [state!.genesis]: kept } });
        rmSync(path, { force: true });
        set(null);
        log.info("lock", "the workspace lock was turned off by its owner", which);
      } else if (had === null) log.info("lock", "pinned the workspace lock", { seq: state!.seq, ...which });
      else if (!on.has(had.state!.head)) log.info("lock", "the workspace lock goes by another branch now", { seq: state!.seq, head: state!.head.slice(0, 12), was: had.state!.head.slice(0, 12), aside: kept.aside.length, ...which });
      else log.info("lock", "took the workspace lock's new entries", { seq: state!.seq, ...(kept.aside.length > 0 ? { aside: kept.aside.length } : {}), ...which });
      if (home) this.refilter();
      else this.tell();
    }
    return { taken, off, refusal };
  }

  /// Why the first of `entries` not on the chain (`on`) is not, as a station answered before it kept every branch:
  /// lost its place, or disagreeing with the chain where it follows nothing kept, a fork; else the rules' refusal.
  private refusalOf(entries: Entry[], on: Set<string>, off: OffChain[], state: LockState, now: number): Error | null {
    const e = entries.find((x) => !on.has(hashOf(x)));
    if (e === undefined) return null;
    const o = off.find((x) => x.hash === hashOf(e));
    if (o?.why === "refused") return new Error(o.refusal);
    if (o === undefined || (o.why !== "no parent" && o.why !== "not on the head") || e.seq <= state.seq) return new Error(FORK);
    try {
      apply(state, e, now);
    } catch (error) {
      return error as Error;
    }
    return new Error(FORK);
  }

  /// The lock's entries after `seq` (all of them for -1), in `ws` (the home one when none is named): its active chain.
  lockAfter(seq: number, ws: string | null = null): Entry[] {
    return (this.lockOf(ws)?.entries ?? []).filter((e) => e.seq > seq);
  }

  /// Every entry kept of the lock in `ws`: its active chain, then those off it.
  lockKept(ws: string | null = null): Entry[] {
    const l = this.lockOf(ws);
    return l === null ? [] : [...l.entries, ...(l.aside ?? [])];
  }

  /// What was kept of the lock of `ws` last turned off here, where none is pinned there now (its chain ends with the
  /// `disable`): offered to the stations it names, so that one that missed the `disable` hears it, and taken from them,
  /// so that a `disable` that lost its place there is let go here too (keepLock). Null when there is none.
  lockOff(ws: string | null = null): Kept | null {
    if (this.lockOf(ws) !== null) return null;
    const path = this.isHome(ws) ? lockPath(this.data) : joinedLockPath(this.data, ws!);
    const offs = (this.offLogs ??= new Map());
    if (!offs.has(path)) {
      const off = readOff(path);
      const g = off.genesis.at(-1);
      offs.set(path, g === undefined ? null : (off.logs[g] ?? null));
    }
    return offs.get(path) ?? null;
  }

  /// The locks turned off here as written, what was kept of the last of each, by its file (lockOff, read once).
  private offLogs = new Map<string, Kept | null>();

  private offWritten(path: string, off: { genesis: string[]; logs: Record<string, Kept> }) {
    writeOff(path, off);
    const g = off.genesis.at(-1);
    (this.offLogs ??= new Map()).set(path, g === undefined ? null : (off.logs[g] ?? null));
  }

  /// Takes the lock away on this machine (`stillfail lock reset`): kept beside as lock.json.reset-<time>.
  static resetLock(data: string): boolean {
    if (!existsSync(lockPath(data))) return false;
    renameSync(lockPath(data), `${lockPath(data)}.reset-${nowSecs()}`);
    return true;
  }

  /// Changes the state, writes it, tells the listeners.
  update(change: (s: CloudState) => void) {
    if (!this.state) return;
    change(this.state);
    setStationCloud(this.state.origin);
    this.writing = true;
    try {
      writeState(this.data, this.state);
    } finally {
      // Its own write, seen by the file's watch a moment later (the file system's time).
      wall.after(100, () => (this.writing = false));
    }
    this.tell();
  }

  /// The control plane it is enrolled in.
  provider(): Provider {
    return providerOf(this.state?.provider);
  }

  removed(): boolean {
    return this.state?.removed_at !== undefined;
  }

  /// The workspace it was enrolled in first (cloud.json's top level), where its station-wide settings are managed;
  /// null outside any.
  home(): string | null {
    const s = this.state;
    return s && s.workspace && !this.removed() ? s.workspace : null;
  }

  private homeMembership(s: CloudState): Membership {
    return { workspace: s.workspace, workspace_name: s.workspace_name, name: s.name, peers: s.peers, revocations: s.revocations, home: true };
  }

  private joinedMembership(j: Joined, home: string): Membership | null {
    if (j.workspace === home || this.leftOut(j.workspace) !== null) return null;
    const own = this.locked(j.workspace);
    const peers = own === null ? j.peers : j.peers.filter((p) => own.state !== null && typeof p?.id === "string" && own.state.stations.has(p.id));
    return { ...j, peers, home: false };
  }

  /// Every workspace the station is in now, its home one first. A joined workspace with a
  /// lock counts once this station pinned it (until then it waits: joining it said which to pin), its roster only the
  /// stations that lock names. A locked station is in locked workspaces only: an unlocked one's members are the control
  /// plane's word, which its home's lock took away.
  memberships(): Membership[] {
    const s = this.state;
    if (s === null || !s.workspace || this.removed()) return [];
    const joined = (s.joined ?? []).flatMap((j): Membership[] => {
      const membership = this.joinedMembership(j, s.workspace);
      return membership === null ? [] : [membership];
    });
    return [this.homeMembership(s), ...joined];
  }

  /// Why a workspace this station joined is none it takes members of now (`memberships` leaves it out): the lock joining
  /// named not brought by the control plane yet (`pending`); locked, with no lock named to pin (`unpinned`: joined before
  /// it was locked); or this station's home locked and it not (`home`). Null when it is in, or is none it joined.
  leftOut(ws: string): "pending" | "unpinned" | "home" | null {
    const s = this.state;
    if (s === null || !s.workspace || this.removed() || ws === s.workspace) return null;
    const j = (s.joined ?? []).find((x) => x.workspace === ws);
    if (j === undefined || this.locked(ws) !== null) return null;
    if (this.pendingLock(ws) !== null) return "pending";
    if (j.locked === true) return "unpinned";
    return this.locked() !== null ? "home" : null;
  }

  /// The rigs of `workspace` this station sends work to: those the control plane names, in security mode only those
  /// their person signed for (`rigVouched`). None while the roster is not current, none for a rig (it asks nothing of
  /// another), none outside the workspace.
  rigs(workspace: string): Rig[] {
    const s = this.state;
    if (s === null || s.rig !== undefined || this.membership(workspace) === null) return [];
    const named = workspace === s.workspace ? (s.rigs ?? []) : ((s.joined ?? []).find((j) => j.workspace === workspace)?.rigs ?? []);
    const mine = named.filter((r) => r.id !== s.station);
    return this.locked(workspace) === null ? mine : mine.filter((r) => this.rigVouched?.(workspace, r) === true);
  }

  /// The rigs of `workspace` as the control plane names them, signed for or not (what a person is shown to sign for).
  rigsNamed(workspace: string): Rig[] {
    const s = this.state;
    if (s === null || s.rig !== undefined || this.membership(workspace) === null) return [];
    return (workspace === s.workspace ? (s.rigs ?? []) : ((s.joined ?? []).find((j) => j.workspace === workspace)?.rigs ?? [])).filter((r) => r.id !== s.station);
  }

  /// The workspace `id` is a rig of, of those this station is in (`workspace`: that one alone); null when of none.
  rigOf(id: string, workspace: string | null = null): { workspace: string; rig: Rig } | null {
    for (const m of this.memberships()) {
      if (workspace !== null && m.workspace !== workspace) continue;
      const rig = this.rigs(m.workspace).find((r) => r.id === id);
      if (rig !== undefined) return { workspace: m.workspace, rig };
    }
    return null;
  }

  /// The station in `workspace`, if it is in it now.
  membership(workspace: string): Membership | null {
    const s = this.state;
    if (s === null || !s.workspace || this.removed()) return null;
    if (workspace === s.workspace) return this.homeMembership(s);
    const joined = (s.joined ?? []).find((j) => j.workspace === workspace);
    return joined === undefined ? null : this.joinedMembership(joined, s.workspace);
  }

  /// A workspace's own relays and ways turned off as the control plane kept them (WaysSaid): null when it said none.
  waysSaid(workspace: string): WaysSaid | null {
    const s = this.state;
    if (s === null) return null;
    if (workspace === s.workspace) return s.ways ?? null;
    return (s.joined ?? []).find((j) => j.workspace === workspace)?.ways ?? null;
  }

  /// still.fail's relays, ours first, as `relays()` in the Rust station: `relay_urls`, else `relay_url`; what is no URL
  /// left out.
  relays(): string[] {
    const s = this.state;
    if (!s) return [];
    return (s.relay_urls.length > 0 ? s.relay_urls : [s.relay_url]).filter((u) => URL.canParse(u));
  }

  /// The roster said last is no longer the socket's (presence.ts `lapse`): still taken, unless the station was removed;
  /// told, as a new one is, so what shows whether it is reached hears it.
  lapsed() {
    const current = !this.removed() && this.peersCurrent;
    if (!this.reached && current === this.peersCurrent) return;
    this.reached = false;
    this.peersCurrent = current;
    this.tell();
  }

  listen(f: (s: CloudState | null) => void): () => void {
    this.listeners.add(f);
    return () => this.listeners.delete(f);
  }

  private tell() {
    for (const f of this.listeners) f(this.state);
  }
}
