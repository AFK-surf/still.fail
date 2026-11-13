// The station's commands other than `run` (the Rust station's main.rs `main`): enroll, status, id. Their output is what
// people and `bin/stillfail` read, so its words are the catalog's, as the Rust station says them.
import { existsSync, mkdirSync, readFileSync, renameSync } from "node:fs";
import { dirname, join } from "node:path";
import { loadKey } from "./cloud/key.ts";
import { Cloud, joinedLockPath, joinedPendingPath, pendingLockPath, readLock, readState, writeState, type CloudState } from "./cloud/state.ts";
import { nowSecs, writePrivate } from "./ops/files.ts";
import { entryHash, shortCode } from "./cloud/lock.ts";
import { rmSync } from "node:fs";
import { type Provider, specOf } from "./cloud/provider.ts";
import { stationLang, tr } from "./ops/i18n.ts";
import { version } from "./ops/version.ts";

const strings = (v: unknown): string[] => (Array.isArray(v) ? v.filter((s): s is string => typeof s === "string") : []);

/// Joins a workspace with a one-time token: proves this station holds its key, writes cloud.json. `provider`: whose
/// control plane it is (still.fail cloud unless told; cloud/provider.ts). `lock`: the workspace lock's hash (a locked
/// workspace's command names it): pinned once the control plane brings a lock holding that entry. A lock pinned before
/// is let go: joining (again) is the machine's own say, as `lock reset` is. `rig`: the machine joins as a rig (a station that only runs tasks),
/// whose person is the one the token is of, their own lock's hash (`rig`, which the command that adds it names) pinned:
/// who that person is, the control plane says once, here; what they signed is checked against that lock from then on.
export async function enroll(data: string, origin: string, token: string, provider: Provider = "stillfail", lock?: string, rig?: string) {
  const plane = specOf(provider);
  const key = loadKey(data);
  // A machine is a station or a rig, and changes only once taken out of its workspace: a station's chats would be
  // left with no agent, a rig's grants with a machine that asks nobody.
  const was = existsSync(join(data, "mesh", "cloud.json")) ? readState(data) : null;
  if (was !== null && was.workspace && was.removed_at === undefined && (was.rig !== undefined) !== (rig !== undefined)) {
    throw new Error(tr(stationLang(), was.rig !== undefined ? "station.cli.rig.isRig" : "station.cli.rig.isStation", { workspace: was.workspace_name || was.workspace }));
  }
  const body = await redeem(data, origin, token, provider, plane.enrollPath, rig !== undefined);
  if (rig !== undefined && typeof body.rig?.owner !== "string") throw new Error(`${plane.name} did not say whose rig this is`);
  const text = (k: string) => (typeof body[k] === "string" ? body[k] : "");
  const relays = strings(body.relay_urls);
  const state: CloudState = {
    origin, station: key.id, workspace: text("workspace"), workspace_name: text("workspace_name"), name: text("name"),
    // Comma names no relay of its own apart from the list: its first is the station's home.
    relay_url: text("relay_url") || (provider === "comma" ? (relays[0] ?? "") : ""), relay_urls: relays, grant_keys: body.grant_keys ?? null, peers: [], revocations: [],
  };
  if (provider !== "stillfail") {
    state.provider = provider;
    state.gateway_keys = strings(body.gateway_keys);
  }
  if (rig !== undefined) state.rig = { owner: body.rig.owner, owner_email: typeof body.rig.owner_email === "string" ? body.rig.owner_email : "", owner_name: typeof body.rig.owner_name === "string" ? body.rig.owner_name : "", person: rig };
  writeState(data, state);
  if (readLock(data) !== null) Cloud.resetLock(data);
  rmSync(pendingLockPath(data), { force: true });
  if (lock !== undefined) writePrivate(pendingLockPath(data), JSON.stringify({ hash: lock }));
  if (state.rig !== undefined) console.log(tr(stationLang(), "station.cli.rig.joined", { workspace: state.workspace_name, name: state.name, id: key.id.slice(0, 12), owner: state.rig.owner_email || state.rig.owner }));
  else console.log(tr(stationLang(), "station.cli.joined", { workspace: state.workspace_name, name: state.name, id: key.id.slice(0, 12) }));
  if (lock !== undefined) console.log(tr(stationLang(), state.rig !== undefined ? "station.cli.rig.pending" : "station.cli.lock.pending", { code: shortCode(key.id) }));
}

/// Whether `enroll --stay` (what the installers run) joins rather than enrolls: the station is in a workspace and not
/// removed from it. Re-enrolling moves a station out of every workspace it is in, which someone adding a machine
/// already in one to another does not mean; a machine is moved by removing it from its workspace first.
export function staysIn(data: string): boolean {
  const state = readState(data);
  return state !== null && !!state.workspace && state.removed_at === undefined;
}

/// Whether this machine is a rig now (in a workspace as one).
export function isRig(data: string): boolean {
  const state = readState(data);
  return state !== null && !!state.workspace && state.removed_at === undefined && state.rig !== undefined;
}

/// Joins one more workspace with its one-time token, staying in those the station is in:
/// at the control plane it is enrolled with, which then names it in its `state` frames. Kept in cloud.json's `joined`
/// at once, so `status` says it before the running station hears. A locked station joins none: its lock is one
/// workspace's. What it joined. `atMachine`: asked on this machine (the command line), whose person may set aside a lock
/// kept here for that workspace by naming another (nameJoinedLock); asked over the mesh, where who asks is the control
/// plane's word unless the home is locked, a kept lock not holding `lock` stays and the join throws KeptLock once done.
export async function joinWorkspace(data: string, token: string, lock?: string, { atMachine = false, cloud }: { atMachine?: boolean; cloud?: Cloud } = {}): Promise<{ workspace: string; workspace_name: string; name: string }> {
  const state = readState(data);
  if (state === null || !state.workspace || state.removed_at !== undefined) throw new Error("this station is in no workspace: enroll it first");
  if (state.rig !== undefined) throw new Error(tr(stationLang(), "station.cli.rig.isRig", { workspace: state.workspace_name || state.workspace }));
  // A locked station joins locked workspaces only: an unlocked one's members are the control plane's word, which its
  // home's lock took away. Which lock to pin is the joining device's word (`lock`, the head it has), as `enroll --lock`.
  // A home whose chain moved is locked as its root's log says now (off or on: Cloud.locked), never as the chain alone
  // (`cloud`: the running station's, asked over the mesh; else this machine's files read here).
  const home = readLock(data);
  const on = home !== null && !home.state?.disabled && (home.state?.moved === undefined || (cloud ?? new Cloud(data, false)).locked() !== null);
  if (on && lock === undefined) throw new Error("this station's workspace is locked: it joins only a workspace with a lock of its own");
  const provider = state.provider ?? "stillfail";
  const body = await redeem(data, state.origin, token, provider, specOf(provider).joinPath);
  const text = (k: string) => (typeof body[k] === "string" ? body[k] : "");
  const joined = { workspace: text("workspace"), workspace_name: text("workspace_name"), name: text("name") };
  if (joined.workspace === "") throw new Error(`${specOf(provider).name} did not say which workspace was joined`);
  const named = lock !== undefined && joined.workspace !== state.workspace ? nameJoinedLock(data, joined.workspace, lock, atMachine) : "pending";
  const now = readState(data) ?? state;
  // The plane's `state` frame may have named it already (it tells the station before it answers): that is kept, its
  // roster and whether it is locked with it, not put back to none until the next frame.
  if (joined.workspace !== now.workspace && !(now.joined ?? []).some((j) => j.workspace === joined.workspace)) {
    now.joined = [...(now.joined ?? []), { ...joined, peers: [], revocations: [] }];
    writeState(data, now);
  }
  // Joined all the same (the token is spent): the one asking is told the station goes by the lock it keeps there.
  if (named === "kept another") throw new KeptLock(joined.workspace);
  return joined;
}

/// A join asked over the mesh named a lock other than the one this station keeps for that workspace: it joined, and
/// goes by the lock it keeps until that is reset on this machine.
export class KeptLock extends Error {
  readonly workspace: string;
  constructor(workspace: string) {
    super(`this station joined the workspace but keeps another security mode record for it, which it goes by there; to take the one you named, run \`stillfail lock reset --workspace ${workspace}\` on that computer first`);
    this.workspace = workspace;
  }
}

/// Joining `ws` named the lock to pin there (`hash`, the joining person's word, as `enroll --lock`): pinned once the
/// control plane brings a lock holding that entry, the station taking nobody of `ws` till then (`pending`). A lock kept
/// here from before (the plane's word that the station left `ws` lets none go) stays when its chain holds `hash`
/// (`kept`). One that does not: set aside beside its file, as `lock reset` does the home one's, when asked on this
/// machine (`set aside`); else left as it is with nothing written (`kept another`): over the mesh, who asks is the
/// control plane's word where the home is not locked, and it would swap the lock for a chain of its own.
export function nameJoinedLock(data: string, ws: string, hash: string, atMachine = false): "pending" | "kept" | "set aside" | "kept another" {
  const kept = readLock(data, ws);
  if (kept?.entries.some((e) => entryHash(e) === hash)) {
    rmSync(joinedPendingPath(data, ws), { force: true });
    return "kept";
  }
  if (kept !== null && !atMachine) return "kept another";
  // What to pin first: at no moment is there neither, which would leave `ws` to the plane's word.
  mkdirSync(dirname(joinedPendingPath(data, ws)), { recursive: true });
  writePrivate(joinedPendingPath(data, ws), JSON.stringify({ hash }));
  if (kept === null) return "pending";
  renameSync(joinedLockPath(data, ws), `${joinedLockPath(data, ws)}.reset-${nowSecs()}`);
  return "set aside";
}

/// A one-time token redeemed at `path` (enroll or join): proves this station holds its key; the control plane's answer.
async function redeem(data: string, origin: string, token: string, provider: Provider, path: string, rig = false): Promise<any> {
  const plane = specOf(provider);
  const key = loadKey(data);
  let response: Response | undefined;
  // The new proof first; the old spelling only when a pre-rename cloud explicitly refuses the signature.
  for (const prefix of plane.enrollPrefixes) {
    const signature = key.sign(`${prefix}-station-enroll-v1:${origin}:${token}:${key.id}`);
    response = await fetch(`${origin}${path}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      // Joining: it pins the lock of a locked workspace it joins, which the plane asks before
      // letting it into one.
      // `rig`: it enrolls as a rig, which a rig's token alone makes.
      body: JSON.stringify({ token, station: key.id, signature, version: version(), ...(path === plane.joinPath ? { locks: true } : {}), ...(rig ? { rig: true } : {}) }),
      signal: AbortSignal.timeout(20_000),
    });
    if (prefix === plane.enrollPrefixes.at(-1) || response.status !== 401) break;
    const text = await response.text();
    let error: unknown;
    try {
      error = JSON.parse(text).error;
    } catch {}
    if (error !== "invalid_signature") throw new Error(`${plane.name} answered ${response.status}: ${text}`);
  }
  // A control plane from before several workspaces has no join: nothing changed there.
  if (path === plane.joinPath && response!.status === 404) {
    const text = await response!.text();
    if (!text.includes("enrollment_not_found")) throw new Error(`${plane.name} cannot add a station to more than one workspace yet; nothing changed`);
    throw new Error(`${plane.name} answered 404: ${text}`);
  }
  if (!response!.ok) throw new Error(`${plane.name} answered ${response!.status}: ${await response!.text()}`);
  return await response!.json();
}

/// `lock status`: whether a workspace lock is pinned here and how far it goes; `lock reset`: takes it away (kept beside
/// it), the control plane trusted again — for when every device that could sign is lost. The running station follows.
/// `workspace`: of a workspace it joined, its lock (and the one joining named to pin) taken away alike: the lock the
/// control plane's word alone never lets go (Cloud.leftJoined), reset by the person at the machine.
export function lockCommand(data: string, what: "status" | "reset", workspace?: string): string {
  const say = (key: string, args?: Record<string, unknown>) => tr(stationLang(), key, args);
  if (what === "reset" && workspace !== undefined && workspace !== readState(data)?.workspace) {
    return say(resetJoinedLock(data, workspace) ? "station.cli.lock.resetWorkspace" : "station.cli.lock.noneWorkspace", { workspace });
  }
  if (what === "reset") return say(Cloud.resetLock(data) ? "station.cli.lock.reset" : "station.cli.lock.none");
  const lock = readLock(data);
  if (lock === null) return say("station.cli.lock.none");
  if (lock.state === null) return say("station.cli.lock.broken");
  const s = lock.state;
  const status = say("station.cli.lock.status", { seq: s.seq, hash: s.head.slice(0, 16), members: s.members.size, devices: s.devices.size, stations: s.stations.size });
  // (the entries kept off the chain it goes by: cloud/log-keep.ts)
  const aside = lock.aside?.length ?? 0;
  return aside === 0 ? status : `${status}${say("station.cli.lock.aside", { n: aside })}`;
}

/// A joined workspace's lock taken away on this machine, kept beside as <file>.reset-<time>, and the lock joining named
/// to pin there forgotten; the running station reads it again (Cloud.reloadJoined). Whether there was either.
export function resetJoinedLock(data: string, ws: string): boolean {
  const lock = joinedLockPath(data, ws);
  const had = existsSync(lock) || existsSync(joinedPendingPath(data, ws));
  if (existsSync(lock)) renameSync(lock, `${lock}.reset-${nowSecs()}`);
  rmSync(joinedPendingPath(data, ws), { force: true });
  return had;
}

export function id(data: string) {
  console.log(loadKey(data).id);
}

/// Where the station is: running or not, its workspace, online or why not.
export function status(data: string): string {
  const say = (key: string, args?: Record<string, unknown>) => tr(stationLang(), key, args);
  const when = (secs: number) => new Date(secs * 1000).toISOString();
  const read = (path: string): any => {
    try {
      return JSON.parse(readFileSync(path, "utf8"));
    } catch {
      return null;
    }
  };
  const station = read(join(data, "run", "station.json"));
  const running = station && Number.isInteger(station.pid) && station.pid > 0 && alive(station.pid) ? station : null;
  const out = [say("station.cli.status.data", { path: data })];
  out.push(running ? say("station.cli.status.running", { pid: running.pid, version: typeof running.version === "string" ? running.version : "?" }) : say("station.cli.status.notRunning"));
  const join_ = say("station.cli.status.join");
  const state = existsSync(join(data, "mesh", "cloud.json")) ? readState(data) : null;
  if (!state) {
    out.push(say("station.cli.status.noWorkspace"), say("station.cli.status.idleUnjoined", { join: join_ }));
    return out.join("\n");
  }
  out.push(say("station.cli.status.workspace", { name: state.workspace_name, id: state.workspace }));
  out.push(say("station.cli.status.name", { name: state.name, id: state.station.slice(0, 12) }));
  if (state.rig !== undefined) out.push(say("station.cli.rig.status", { owner: state.rig.owner_email || state.rig.owner, person: state.rig.person.slice(0, 16) }));
  out.push(say("station.cli.status.cloud", { origin: state.origin }));
  if (readLock(data) !== null) out.push(lockCommand(data, "status"));
  if (state.removed_at !== undefined) {
    const how = state.removed_code === 4004 ? say("station.cli.status.removedOnClose")
      : state.removed_code === 404 ? say("station.cli.status.removedOn404")
      : state.removed_code !== undefined ? say("station.cli.status.removedCode", { code: state.removed_code }) : "";
    out.push(say("station.cli.status.removed", { workspace: state.workspace_name, at: when(state.removed_at), how }));
    out.push(say("station.cli.status.idleRemoved", { join: join_ }));
  }
  const presence = running ? read(join(data, "run", "presence.json")) : null;
  if (presence && presence.online === true) out.push(say("station.cli.status.onlineSince", { at: Number.isInteger(presence.at) ? when(presence.at) : "" }));
  else if (presence) out.push(say("station.cli.status.offlineWhy", { why: typeof presence.error === "string" ? presence.error : say("station.cli.status.notConnectedYet") }));
  else if (!running) out.push(say("station.cli.status.offlineNotRunning"));
  else out.push(say("station.cli.status.offline"));
  if (state.removed_at === undefined) out.push(say(state.rig !== undefined ? "station.cli.rig.working" : "station.cli.status.working"));
  return out.join("\n");
}

/// Whether a process is there (signal 0 only asks; one of another user's counts as not, as `kill` failing does).
function alive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}
