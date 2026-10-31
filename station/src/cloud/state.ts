// Where the station stands with still.fail cloud: <data>/mesh/cloud.json (its fields, mode and pretty JSON as the Rust
// station writes them: the desktop app and `bin/stillfail` read it too). One copy in memory, written through on every
// change and told to whoever listens; the file is watched only for `enroll` writing it from another process.
import { type FSWatcher, existsSync, mkdirSync, readFileSync, renameSync, rmSync, watch } from "node:fs";
import { dirname, join } from "node:path";
import { nowSecs, writePrivate } from "../ops/files.ts";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { type Entry, type LockState, apply, asEntry, entryHash, fold } from "./lock.ts";
import { type Provider, providerOf } from "./provider.ts";

export type Revocation = { kind: string; id: string; at: number };

/// A workspace the station is in besides its home one (docs/multi-workspace.md): what it is called there, the other
/// stations there and what that workspace takes back.
/// `locked`: that workspace is in security mode, as the control plane says (its lock is pinned here before any of its
/// members is taken).
export type Joined = { workspace: string; workspace_name: string; name: string; peers: any[]; revocations: Revocation[]; locked?: true };

/// One of the workspaces the station is in, its home one (cloud.json's top level) or a joined one.
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
};

export const meshDir = (data: string) => join(data, "mesh");
const statePath = (data: string) => join(meshDir(data), "cloud.json");
/// The workspace's lock this station pinned (cloud/lock.ts): `{entries}`, from its genesis.
export const lockPath = (data: string) => join(meshDir(data), "lock.json");
/// The lock `enroll --lock <hash>` said to pin once the control plane brings it: `{hash}`.
export const pendingLockPath = (data: string) => join(meshDir(data), "lock-pending.json");
/// A workspace the station joined: the lock it pinned there, and the one joining said to pin (docs/multi-workspace.md),
/// beside the home one's, by the workspace's id.
const fileOf = (ws: string) => (/^[0-9A-Za-z_-]{1,64}$/.test(ws) ? ws : Buffer.from(ws).toString("hex").slice(0, 64));
export const joinedLockPath = (data: string, ws: string) => join(meshDir(data), "locks", `${fileOf(ws)}.json`);
export const joinedPendingPath = (data: string, ws: string) => join(meshDir(data), "locks", `${fileOf(ws)}.pending.json`);

/// The pinned lock as lock.json has it (a joined workspace's: its own file): null without one. A file that does not
/// hold a lock (edited by hand, cut short) is a lock that admits nobody: refusing is safer than trusting the control
/// plane again by itself.
export function readLock(data: string, ws: string | null = null): { entries: Entry[]; state: LockState | null } | null {
  const path = ws === null ? lockPath(data) : joinedLockPath(data, ws);
  if (!existsSync(path)) return null;
  try {
    const raw = JSON.parse(readFileSync(path, "utf8"));
    const entries = (Array.isArray(raw?.entries) ? raw.entries : []).map(asEntry);
    if (entries.some((e: Entry | null) => e === null)) throw new Error("an entry is malformed");
    return { entries, state: fold(entries, null) };
  } catch (e) {
    log.warn("lock", "lock.json holds no valid lock; nobody is admitted until `stillfail lock reset`", { error: (e as Error).message });
    return { entries: [], state: null };
  }
}

/// The state as the file has it, its optional parts filled as the Rust station's serde defaults fill them.
export function readState(data: string): CloudState | null {
  if (!existsSync(statePath(data))) return null;
  const raw = JSON.parse(readFileSync(statePath(data), "utf8"));
  const state: CloudState = { ...raw, relay_urls: raw.relay_urls ?? [], peers: raw.peers ?? [], revocations: raw.revocations ?? [] };
  if (raw.joined !== undefined) state.joined = joinedOf(raw.joined);
  if (raw.provider !== undefined) state.provider = providerOf(raw.provider);
  return state;
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
        }]
      : [],
  );
}

export const isRevocation = (r: any): r is Revocation => typeof r?.kind === "string" && typeof r?.id === "string" && Number.isInteger(r?.at) && r.at >= 0;

/// The state in memory, and who wants to hear of its changes.
export class Cloud {
  state: CloudState | null;
  /// Whether `peers` is the cloud's roster as of the current presence socket (fail closed until a `state` frame says so).
  peersCurrent = false;
  /// How many rosters the control plane said (presence.ts: one said since its socket ended keeps it current).
  rostersSaid = 0;
  /// Runs a device tool request that came over the presence socket (mesh/tools.ts `presenceTools`), while the mesh
  /// is up; null before it.
  toolCalls: ((request: unknown) => Promise<unknown>) | null = null;
  /// The workspace's lock, once pinned (null: none, the control plane is trusted as before). Its state null: lock.json
  /// is broken, nobody is admitted.
  lock: { entries: Entry[]; state: LockState | null } | null;
  /// The locks of the workspaces it joined, pinned there, by workspace (read from their files on first use).
  private joinedLocks = new Map<string, { entries: Entry[]; state: LockState | null } | null>();
  /// How far the control plane's copy of the lock goes, as its last `state` frame said (null: a plane that keeps none).
  planeLockSeq: number | null = null;
  /// The same of each joined workspace's lock.
  planeLockSeqs = new Map<string, number | null>();
  /// What the control plane last said of the roster and gateways, before the lock filtered them (this run only).
  private planePeers: any[] | null = null;
  private planeGateways: string[] | undefined;
  private listeners = new Set<(s: CloudState | null) => void>();
  private writing = false;
  private watcher: FSWatcher | undefined;
  readonly data: string;

  constructor(data: string) {
    this.data = data;
    this.state = readState(data);
    this.lock = readLock(data);
    // `enroll` from another process, or an older tool editing the file; `lock reset` taking the lock away.
    try {
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
    } catch {
      // No mesh directory yet: `enroll` makes it, and the station is started anew after.
    }
  }

  close() {
    this.watcher?.close();
    this.listeners.clear();
  }

  /// The state read again from its file; told when it changed, or anyway (`tell`: the station joined a workspace, and
  /// what to pin there is to be asked for at once, cloud.json as the plane's frame left it or not).
  reload(tell = false) {
    const next = readState(this.data);
    if (tell || JSON.stringify(next) !== JSON.stringify(this.state)) {
      this.state = next;
      this.tell();
    }
  }

  reloadLock() {
    const next = readLock(this.data);
    if (JSON.stringify(next?.entries ?? null) === JSON.stringify(this.lock?.entries ?? null) && (next?.state === null) === (this.lock?.state === null)) return;
    this.lock = next;
    log.info("lock", next === null ? "the workspace lock was taken away on this machine; the control plane is trusted again" : "the workspace lock was read anew");
    this.refilter();
  }

  /// Whether `ws` names the home workspace (none named does).
  private isHome(ws: string | null | undefined): boolean {
    return ws === null || ws === undefined || ws === this.state?.workspace;
  }

  /// The lock pinned in `ws` (the home one's when none is named), as its file has it.
  private lockOf(ws: string | null | undefined): { entries: Entry[]; state: LockState | null } | null {
    if (this.isHome(ws)) return this.lock;
    // (Made here too: a Cloud made without its constructor, as tests make one, has none yet.)
    const locks = (this.joinedLocks ??= new Map());
    if (!locks.has(ws!)) locks.set(ws!, this.data === undefined ? null : readLock(this.data, ws!));
    return locks.get(ws!) ?? null;
  }

  /// The lock in force in `ws` (the home one when none is named): null when none is pinned (or it was turned off). A
  /// broken lock file is in force and admits nobody (`state` null).
  locked(ws?: string | null): { state: LockState | null } | null {
    const l = this.lockOf(ws);
    if (l === null || l.state?.disabled) return null;
    return l;
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

  /// A joined workspace the station is no longer in: its lock and what it was to pin forgotten.
  forgetJoined(ws: string) {
    rmSync(joinedLockPath(this.data, ws), { force: true });
    rmSync(joinedPendingPath(this.data, ws), { force: true });
    this.joinedLocks.delete(ws);
    this.planeLockSeqs.delete(ws);
  }

  /// A workspace it joined takes over as its home one, the home it was taken out of gone (docs/multi-workspace.md): that
  /// workspace's lock, pinned or named by joining, is the home one's now (lock.json, lock-pending.json), the old home's
  /// forgotten. Refused (false) while the home one is locked and that workspace's lock is not pinned here: the station
  /// stays where its lock keeps it.
  succeed(ws: string): boolean {
    if (this.locked() !== null && this.locked(ws) === null) return false;
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

  private refilter() {
    if (!this.state) return this.tell();
    this.update((st) => {
      const { peers, gateways } = this.filtered(st);
      st.peers = peers;
      if (gateways !== undefined) st.gateway_keys = gateways;
    });
  }

  /// Pins a lock (its whole chain, from genesis), or takes more of the pinned one: what follows its head. Entries it
  /// already has are skipped; one that disagrees with them (a fork) or does not verify is refused, and nothing after it
  /// is taken. Returns how many were taken; throws why the first refused one was.
  takeLock(entries: Entry[], ws: string | null = null): number {
    const home = this.isHome(ws);
    const now = nowSecs();
    const current = this.lockOf(ws);
    const had = current?.state ? current : null;
    if (current !== null && had === null) throw new Error("this station's lock.json is broken; run `stillfail lock reset` on it");
    const workspace = home ? this.state?.workspace : ws!;
    let kept = had?.entries ?? [];
    let state = had?.state ?? null;
    let taken = 0;
    let refused: Error | null = null;
    for (const e of entries) {
      try {
        if (state === null) {
          if (workspace !== undefined && e.ws !== workspace) throw new Error("the lock is another workspace's");
          state = fold([e], now);
          kept = [e];
        } else if (e.seq <= state.seq) {
          if (kept[e.seq] === undefined || entryHash(kept[e.seq]!) !== entryHash(e)) throw new Error("the entry disagrees with this station's lock (a fork)");
          continue;
        } else {
          if (e.ws !== state.ws) throw new Error("an entry of another workspace's lock");
          state = apply(state, e, now);
          kept = [...kept, e];
        }
        taken++;
      } catch (error) {
        refused = error as Error;
        break;
      }
    }
    if (taken > 0) {
      const path = home ? lockPath(this.data) : joinedLockPath(this.data, ws!);
      const set = (l: { entries: Entry[]; state: LockState | null } | null) => (home ? (this.lock = l) : this.joinedLocks.set(ws!, l));
      this.writing = true;
      try {
        mkdirSync(dirname(path), { recursive: true });
        writePrivate(path, JSON.stringify({ entries: kept }, null, 2));
      } finally {
        wall.after(100, () => (this.writing = false));
      }
      set({ entries: kept, state });
      const which = home ? {} : { workspace: ws };
      if (state!.disabled) {
        // Off: nothing pinned, the control plane trusted as before (it sends its lists again on the next frame).
        rmSync(path, { force: true });
        set(null);
        log.info("lock", "the workspace lock was turned off by its owner", which);
      } else log.info("lock", had === null ? "pinned the workspace lock" : "took the workspace lock's new entries", { seq: state!.seq, ...which });
      if (home) this.refilter();
      else this.tell();
    }
    if (refused !== null && taken === 0) throw refused;
    if (refused !== null) log.warn("lock", "a lock entry was refused", { error: refused.message });
    return taken;
  }

  /// The lock's entries after `seq` (all of them for -1), in `ws` (the home one when none is named).
  lockAfter(seq: number, ws: string | null = null): Entry[] {
    return (this.lockOf(ws)?.entries ?? []).filter((e) => e.seq > seq);
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

  /// Every workspace the station is in now, its home one first (docs/multi-workspace.md). A joined workspace with a
  /// lock counts once this station pinned it (until then it waits: joining it said which to pin), its roster only the
  /// stations that lock names. A locked station is in locked workspaces only: an unlocked one's members are the control
  /// plane's word, which its home's lock took away.
  memberships(): Membership[] {
    const s = this.state;
    if (s === null || !s.workspace || this.removed()) return [];
    const home: Membership = { workspace: s.workspace, workspace_name: s.workspace_name, name: s.name, peers: s.peers, revocations: s.revocations, home: true };
    const joined = (s.joined ?? []).flatMap((j): Membership[] => {
      if (j.workspace === s.workspace || this.leftOut(j.workspace) !== null) return [];
      const own = this.locked(j.workspace);
      const peers = own === null ? j.peers : j.peers.filter((p) => own.state !== null && typeof p?.id === "string" && own.state.stations.has(p.id));
      return [{ ...j, peers, home: false }];
    });
    return [home, ...joined];
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

  /// The station in `workspace`, if it is in it now.
  membership(workspace: string): Membership | null {
    return this.memberships().find((m) => m.workspace === workspace) ?? null;
  }

  /// still.fail's relays, ours first, as `relays()` in the Rust station: `relay_urls`, else `relay_url`; what is no URL
  /// left out.
  relays(): string[] {
    const s = this.state;
    if (!s) return [];
    return (s.relay_urls.length > 0 ? s.relay_urls : [s.relay_url]).filter((u) => URL.canParse(u));
  }

  listen(f: (s: CloudState | null) => void): () => void {
    this.listeners.add(f);
    return () => this.listeners.delete(f);
  }

  private tell() {
    for (const f of this.listeners) f(this.state);
  }
}
