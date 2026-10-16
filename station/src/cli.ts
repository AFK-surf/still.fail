// The station's commands other than `run` (the Rust station's main.rs `main`): enroll, status, id. Their output is what
// people and `bin/stillfail` read, so its words are the catalog's, as the Rust station says them.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { loadKey } from "./cloud/key.ts";
import { Cloud, pendingLockPath, readLock, readState, writeState, type CloudState } from "./cloud/state.ts";
import { writePrivate } from "./ops/files.ts";
import { shortCode } from "./cloud/lock.ts";
import { rmSync } from "node:fs";
import { type Provider, specOf } from "./cloud/provider.ts";
import { stationLang, tr } from "./ops/i18n.ts";
import { version } from "./ops/version.ts";

const strings = (v: unknown): string[] => (Array.isArray(v) ? v.filter((s): s is string => typeof s === "string") : []);

/// Joins a workspace with a one-time token: proves this station holds its key, writes cloud.json. `provider`: whose
/// control plane it is (still.fail cloud unless told; cloud/provider.ts). `lock`: the workspace lock's hash (a locked
/// workspace's command names it): pinned once the control plane brings a lock holding that entry. A lock pinned before
/// is let go: joining (again) is the machine's own say, as `lock reset` is.
export async function enroll(data: string, origin: string, token: string, provider: Provider = "stillfail", lock?: string) {
  const plane = specOf(provider);
  const key = loadKey(data);
  const body = await redeem(data, origin, token, provider, plane.enrollPath);
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
  writeState(data, state);
  if (readLock(data) !== null) Cloud.resetLock(data);
  rmSync(pendingLockPath(data), { force: true });
  if (lock !== undefined) writePrivate(pendingLockPath(data), JSON.stringify({ hash: lock }));
  console.log(tr(stationLang(), "station.cli.joined", { workspace: state.workspace_name, name: state.name, id: key.id.slice(0, 12) }));
  if (lock !== undefined) console.log(tr(stationLang(), "station.cli.lock.pending", { code: shortCode(key.id) }));
}

/// Joins one more workspace with its one-time token, staying in those the station is in (docs/multi-workspace.md):
/// at the control plane it is enrolled with, which then names it in its `state` frames. Kept in cloud.json's `joined`
/// at once, so `status` says it before the running station hears. A locked station joins none: its lock is one
/// workspace's. What it joined.
export async function joinWorkspace(data: string, token: string): Promise<{ workspace: string; workspace_name: string; name: string }> {
  const state = readState(data);
  if (state === null || !state.workspace || state.removed_at !== undefined) throw new Error("this station is in no workspace: enroll it first");
  const lock = readLock(data);
  if (lock !== null && !lock.state?.disabled) throw new Error("this station's workspace is locked: a locked station stays in that one workspace");
  const provider = state.provider ?? "stillfail";
  const body = await redeem(data, state.origin, token, provider, specOf(provider).joinPath);
  const text = (k: string) => (typeof body[k] === "string" ? body[k] : "");
  const joined = { workspace: text("workspace"), workspace_name: text("workspace_name"), name: text("name") };
  if (joined.workspace === "") throw new Error(`${specOf(provider).name} did not say which workspace was joined`);
  const now = readState(data) ?? state;
  if (joined.workspace !== now.workspace) {
    now.joined = [...(now.joined ?? []).filter((j) => j.workspace !== joined.workspace), { ...joined, peers: [], revocations: [] }];
    writeState(data, now);
  }
  return joined;
}

/// A one-time token redeemed at `path` (enroll or join): proves this station holds its key; the control plane's answer.
async function redeem(data: string, origin: string, token: string, provider: Provider, path: string): Promise<any> {
  const plane = specOf(provider);
  const key = loadKey(data);
  let response: Response | undefined;
  // The new proof first; the old spelling only when a pre-rename cloud explicitly refuses the signature.
  for (const prefix of plane.enrollPrefixes) {
    const signature = key.sign(`${prefix}-station-enroll-v1:${origin}:${token}:${key.id}`);
    response = await fetch(`${origin}${path}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token, station: key.id, signature, version: version() }),
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
export function lockCommand(data: string, what: "status" | "reset"): string {
  const say = (key: string, args?: Record<string, unknown>) => tr(stationLang(), key, args);
  if (what === "reset") return say(Cloud.resetLock(data) ? "station.cli.lock.reset" : "station.cli.lock.none");
  const lock = readLock(data);
  if (lock === null) return say("station.cli.lock.none");
  if (lock.state === null) return say("station.cli.lock.broken");
  const s = lock.state;
  return say("station.cli.lock.status", { seq: s.seq, hash: s.head.slice(0, 16), members: s.members.size, devices: s.devices.size, stations: s.stations.size });
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
  if (state.removed_at === undefined) out.push(say("station.cli.status.working"));
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
