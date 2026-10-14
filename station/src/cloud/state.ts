// Where the station stands with still.fail cloud: <data>/mesh/cloud.json (its fields, mode and pretty JSON as the Rust
// station writes them: the desktop app and `bin/stillfail` read it too). One copy in memory, written through on every
// change and told to whoever listens; the file is watched only for `enroll` writing it from another process.
import { existsSync, readFileSync, renameSync, rmSync, watch } from "node:fs";
import { join } from "node:path";
import { nowSecs, writePrivate } from "../ops/files.ts";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { type Entry, type LockState, apply, asEntry, entryHash, fold } from "./lock.ts";
import { type Provider, providerOf } from "./provider.ts";

export type Revocation = { kind: string; id: string; at: number };

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
};

export const meshDir = (data: string) => join(data, "mesh");
const statePath = (data: string) => join(meshDir(data), "cloud.json");
/// The workspace's lock this station pinned (cloud/lock.ts): `{entries}`, from its genesis.
export const lockPath = (data: string) => join(meshDir(data), "lock.json");
/// The lock `enroll --lock <hash>` said to pin once the control plane brings it: `{hash}`.
export const pendingLockPath = (data: string) => join(meshDir(data), "lock-pending.json");

/// The pinned lock as lock.json has it: null without one. A file that does not hold a lock (edited by hand, cut short)
/// is a lock that admits nobody: refusing is safer than trusting the control plane again by itself.
export function readLock(data: string): { entries: Entry[]; state: LockState | null } | null {
  if (!existsSync(lockPath(data))) return null;
  try {
    const raw = JSON.parse(readFileSync(lockPath(data), "utf8"));
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
  writePrivate(statePath(data), JSON.stringify(out, null, 2));
}

/// The state in memory, and who wants to hear of its changes.
export class Cloud {
  state: CloudState | null;
  /// Whether `peers` is the cloud's roster as of the current presence socket (fail closed until a `state` frame says so).
  peersCurrent = false;
  /// Runs a device tool request that came over the presence socket (mesh/tools.ts `presenceTools`), while the mesh
  /// is up; null before it.
  toolCalls: ((request: unknown) => Promise<unknown>) | null = null;
  /// The workspace's lock, once pinned (null: none, the control plane is trusted as before). Its state null: lock.json
  /// is broken, nobody is admitted.
  lock: { entries: Entry[]; state: LockState | null } | null;
  /// How far the control plane's copy of the lock goes, as its last `state` frame said (null: a plane that keeps none).
  planeLockSeq: number | null = null;
  /// What the control plane last said of the roster and gateways, before the lock filtered them (this run only).
  private planePeers: any[] | null = null;
  private planeGateways: string[] | undefined;
  private listeners = new Set<(s: CloudState | null) => void>();
  private writing = false;
  private watcher: { close(): void } | undefined;
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
    } catch {
      // No mesh directory yet: `enroll` makes it, and the station is started anew after.
    }
  }

  close() {
    this.watcher?.close();
    this.listeners.clear();
  }

  reload() {
    const next = readState(this.data);
    if (JSON.stringify(next) !== JSON.stringify(this.state)) {
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

  /// The lock in force: null when none is pinned (or it was turned off). A broken lock.json is in force and admits
  /// nobody (`state` null).
  locked(): { state: LockState | null } | null {
    const l = this.lock;
    if (l === null || l.state?.disabled) return null;
    return l;
  }

  /// The credential keys that count: the lock's once pinned, else the control plane's.
  grantKeys(): any {
    const l = this.locked();
    return l === null ? this.state?.grant_keys : (l.state?.cloud_keys ?? null);
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
  takeLock(entries: Entry[]): number {
    const now = nowSecs();
    const had = this.lock?.state ? this.lock : null;
    if (this.lock !== null && had === null) throw new Error("this station's lock.json is broken; run `stillfail lock reset` on it");
    let kept = had?.entries ?? [];
    let state = had?.state ?? null;
    let taken = 0;
    let refused: Error | null = null;
    for (const e of entries) {
      try {
        if (state === null) {
          if (this.state && e.ws !== this.state.workspace) throw new Error("the lock is another workspace's");
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
      this.writing = true;
      try {
        writePrivate(lockPath(this.data), JSON.stringify({ entries: kept }, null, 2));
      } finally {
        wall.after(100, () => (this.writing = false));
      }
      this.lock = { entries: kept, state };
      if (state!.disabled) {
        // Off: nothing pinned, the control plane trusted as before (it sends its lists again on the next frame).
        rmSync(lockPath(this.data), { force: true });
        this.lock = null;
        log.info("lock", "the workspace lock was turned off by its owner");
      } else log.info("lock", had === null ? "pinned the workspace lock" : "took the workspace lock's new entries", { seq: state!.seq });
      this.refilter();
    }
    if (refused !== null && taken === 0) throw refused;
    if (refused !== null) log.warn("lock", "a lock entry was refused", { error: refused.message });
    return taken;
  }

  /// The lock's entries after `seq` (all of them for -1).
  lockAfter(seq: number): Entry[] {
    return (this.lock?.entries ?? []).filter((e) => e.seq > seq);
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
