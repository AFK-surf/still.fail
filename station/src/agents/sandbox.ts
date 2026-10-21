// Execution in sandboxes (docs/sandbox-exec.md): with `sandbox` in config.json switched on, what the station starts for
// a session (its runtime's process, its jobs) runs in that session's own sandbox, reached over SSH (an l4es front door:
// `ssh NAME.WORKSPACE@host` makes the sandbox on first use and deletes it after it has been idle), through
// ./sandbox-bridge.mjs. The station itself, its chats, its store and its door stay here. The sandboxes share no file
// system with it: the station's data directory is made at the same path in each (on storage the sandboxes keep, when
// `persist` names it), and the bridge copies there what the station gives a program (its runtime's home, the station's
// agent home, the session's uploads) and copies back what the program writes that the station reads (transcripts, the
// agent home's memory and skills); `fetch` brings a file the agent attaches.
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { existsSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

export const BRIDGE = fileURLToPath(new URL("./sandbox-bridge.mjs", import.meta.url));

/// What the bridge says, and its exit code, when the connection to the sandbox was lost rather than the program ending
/// (sandbox-bridge.mjs `LOST`): what is started again once.
export const CONNECTION_LOST = "sandbox: the connection to the sandbox was lost";
export const LOST_EXIT = 75;

/// `sandbox` in config.json.
export type SandboxConfig = {
  enabled: boolean;
  /// The SSH destination, `{name}` standing for the sandbox's name: e.g. `{name}.team@l4es.afk.surf`.
  ssh: string;
  /// The private key the station signs in with (linked to the account whose workspace the sandboxes are in).
  identity?: string;
  /// Where the front door's host key is kept (accepted the first time).
  knownHosts?: string;
  /// A directory in the sandboxes, on storage they keep (an NFS mount), where the station's data directory there is:
  /// a session's files outlive its sandbox. None: each sandbox has them on its own disk, gone with it.
  persist?: string;
  /// How long a session's runtime process may be idle (no turn) before it is ended and its sandbox stopped (once no job
  /// of the session runs there): `stopIdle`.
  idleMinutes: number;
};

/// A session's sandbox is stopped this long after its last turn when config.json says nothing else.
export const IDLE_MINUTES = 10;

/// What the bridge copies between here and a sandbox (sandbox-bridge.mjs `sync`).
export type SyncEntry = { path: string; to?: string; mode: "whole" | "append"; skip?: string[]; push?: boolean; back?: boolean; dir?: boolean };

/// The config's `sandbox` as the station takes it; null when it is not there, off or not usable.
export function sandboxConfig(raw: any): SandboxConfig | null {
  const s = raw?.sandbox;
  if (s === null || typeof s !== "object" || s.enabled === false) return null;
  if (typeof s.ssh !== "string" || !s.ssh.includes("{name}")) return null;
  return {
    enabled: true,
    ssh: s.ssh,
    ...(typeof s.identity === "string" ? { identity: s.identity } : {}),
    ...(typeof s.knownHosts === "string" ? { knownHosts: s.knownHosts } : {}),
    ...(typeof s.persist === "string" ? { persist: s.persist } : {}),
    idleMinutes: typeof s.idleMinutes === "number" ? s.idleMinutes : IDLE_MINUTES,
  };
}

/// Checks a `sandbox` edit as config.json takes it: throws what is wrong.
export function checkSandbox(raw: any): void {
  const s = raw?.sandbox;
  if (s === undefined || s === null) return;
  if (typeof s !== "object") throw new Error("sandbox must be an object");
  if (s.enabled !== undefined && typeof s.enabled !== "boolean") throw new Error("sandbox.enabled must be true or false");
  if (typeof s.ssh !== "string" || !/^[^\s@]*\{name\}[^\s@]*@[^\s@]+$/.test(s.ssh)) throw new Error("sandbox.ssh must be like {name}.WORKSPACE@HOST");
  for (const k of ["identity", "knownHosts", "persist"]) if (s[k] !== undefined && typeof s[k] !== "string") throw new Error(`sandbox.${k} must be a path`);
  if (typeof s.persist === "string" && !s.persist.startsWith("/")) throw new Error("sandbox.persist must be an absolute path in the sandboxes");
  if (s.idleMinutes !== undefined && (typeof s.idleMinutes !== "number" || !(s.idleMinutes > 0))) throw new Error("sandbox.idleMinutes must be a number of minutes above 0");
}

/// A sandbox's name for a station's key (a session's): what the front door takes (a lowercase letter, then lowercase
/// letters, digits and `-`, 31 at most), the same for the same key, apart for keys that clean up the same.
export function sandboxName(key: string): string {
  const clean = key.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 16).replace(/-+$/, "");
  const hash = createHash("sha256").update(key).digest("hex").slice(0, 10);
  return clean === "" ? `s-${hash}` : `s-${clean}-${hash}`;
}

/// The key a runner's id was made from (agents/process.ts `runnerId`: `<kind>-<clean>[-<hash>]`): the session's for a
/// session's process, the profile's for a process its sessions share (Codex's host).
export function keyOfRunner(id: string): string {
  return id.replace(/^[a-z]+-/, "");
}

/// A station's key (a session's) as a runner's id has it after its kind (agents/process.ts `runnerId`): safe as a file
/// name, a hash keeping two keys that clean up the same apart. A session's sandbox is named from it.
export function keyPart(key: string): string {
  const clean = key.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 24);
  return clean === key ? clean : `${clean}-${createHash("sha256").update(key).digest("hex").slice(0, 10)}`;
}

/// ssh's command line to the sandbox `name`, up to (not including) the remote command.
export function sshArgs(config: SandboxConfig, name: string): string[] {
  const args = ["ssh", "-T", "-o", "BatchMode=yes", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=4", "-o", "StrictHostKeyChecking=accept-new"];
  if (config.identity !== undefined) args.push("-i", config.identity, "-o", "IdentitiesOnly=yes");
  if (config.knownHosts !== undefined) args.push("-o", `UserKnownHostsFile=${config.knownHosts}`);
  args.push(config.ssh.replace("{name}", name));
  return args;
}

/// Where the station's sandbox settings are, per data directory (a process may run several stations, as tests do).
type Placed = { config: () => SandboxConfig | null; ports: () => number[]; agentHome: string };
const placed = new Map<string, Placed>();

/// Says where this station's config, door and agent home are: from then on, what it starts goes to a sandbox while the
/// config says so.
export function placeIn(data: string, config: () => SandboxConfig | null, ports: () => number[], agentHome = join(data, "agent")): () => void {
  placed.set(data, { config, ports, agentHome });
  return () => placed.delete(data);
}

/// What of a runtime's home is its own, made as it runs, and stays in the sandbox (its login is given each process:
/// `lentFile`, the Claude driver's token).
const CLAUDE_OWN = ["projects", "todos", "shell-snapshots", "statsig", "debug", "logs", "file-history", "ide", "session-env", "plugins", "cache", "telemetry", "paste-cache", "history.jsonl", "backups", ".credentials.json"];
const CODEX_OWN = ["sessions", "archived_sessions", "log", "tmp", ".tmp", "shell_snapshots", "cache", "history.jsonl", "models_cache.json", "auth.json"];

/// Where a Codex login lent to its sandboxes is kept here (its refresh token stays here): copied there as auth.json.
export function lentFile(data: string, home: string): string {
  return join(data, "run", "sandbox", "lent", createHash("sha256").update(home).digest("hex").slice(0, 16), "auth.json");
}

/// What goes with a program started for a session: its runtime's home (`runtime`'s variable in `env` says where; a
/// variable another runtime's left in the station's environment is not looked at), the station's agent home, the
/// session's uploads, the jobs' command; the transcripts come back as they grow.
export function syncFor(data: string, runtime: string, env: NodeJS.ProcessEnv, cwd: string): SyncEntry[] {
  const at = placed.get(data);
  const sync: SyncEntry[] = [];
  if (runtime === "claude" && env.CLAUDE_CONFIG_DIR) {
    const home = env.CLAUDE_CONFIG_DIR;
    sync.push({ path: home, mode: "whole", skip: CLAUDE_OWN }, { path: join(home, "projects"), mode: "append" });
  }
  if (runtime === "codex" && env.CODEX_HOME) {
    const home = env.CODEX_HOME;
    sync.push({ path: home, mode: "whole", skip: CODEX_OWN }, { path: join(home, "sessions"), mode: "append" }, { path: join(home, "archived_sessions"), mode: "append" });
    const lent = lentFile(data, home);
    if (existsSync(lent)) sync.push({ path: lent, to: join(home, "auth.json"), mode: "whole", back: false });
  }
  const other: Record<string, string> = { dsh: "DSH_HOME", grok: "GROK_HOME" };
  const home = other[runtime] && env[other[runtime]];
  if (home) sync.push({ path: home, mode: "whole" });
  if (at) sync.push({ path: at.agentHome, mode: "whole" });
  return [...sync, ...sessionSync(data, cwd)];
}

/// What the station puts in a session's workspace (its uploads, what other stations' tasks brought back, its
/// instructions) and the jobs' command (`stillfail-job`): copied there, never back.
export function sessionSync(data: string, cwd: string): SyncEntry[] {
  return [
    ...["uploads", "station-back", ".stillfail-instructions.md"].map((name) => ({ path: join(cwd, name), mode: "whole" as const, back: false })),
    { path: join(data, "jobs", "bin"), mode: "whole", back: false },
  ];
}

/// Whether this station runs what it starts in sandboxes now.
export function sandboxed(data: string): boolean {
  return (placed.get(data)?.config() ?? null) !== null;
}

/// How long a session's runtime process may idle before it is ended, while the station runs things in sandboxes; null
/// when it does not.
export function sandboxIdleMs(data: string): number | null {
  const config = placed.get(data)?.config() ?? null;
  return config === null ? null : config.idleMinutes * 60_000;
}

/// Stops (deletes) `key`'s sandbox, `size`'s of it when given: what it has on its own disk goes, its files in
/// `persist` stay for the next. The front door refuses while anything still has a connection to it (a job, a program
/// started since): then it stays, and is stopped when that ends. Whether it was stopped.
export function stopSandbox(data: string, key: string, size?: string, timeoutMs = 60_000): Promise<boolean> {
  const config = placed.get(data)?.config() ?? null;
  if (config === null) return Promise.resolve(false);
  const name = size === undefined ? sandboxName(key) : sandboxName(`${key}|${size}`);
  const [ssh, ...args] = sshArgs(config, "_");
  return new Promise((resolve) => execFile(ssh, [...args, "rm", name], { timeout: timeoutMs }, (error, out) => resolve(!error && /^deleting /m.test(out))));
}

/// A size's name as the sandboxes' operator gives them (l4es `SBX_SANDBOX_SIZES`).
export const sizeName = (size: string) => /^[a-z][a-z0-9-]{0,30}$/.test(size);

/// How something is started in a sandbox: `node` runs the bridge; with a `size`, in a sandbox of the key's of that size,
/// which the front door is asked to make first; `agent`: a runtime's process, which ends those started there before;
/// `lostFile`: written when the connection to it is lost; `sync`: what is copied there and back (`syncFor`).
export type Placing = { node?: string; size?: string; agent?: boolean; lostFile?: string; sync?: SyncEntry[] };

/// The bridge's spec for sandbox `name`, without a program: what is copied, where the data directory is.
function bridgeSpec(at: Placed, config: SandboxConfig, data: string, name: string, cwd: string | null, sync: SyncEntry[]) {
  return {
    ssh: sshArgs(config, name), ports: at.ports(),
    root: { path: data, ...(config.persist ? { persist: config.persist } : {}) },
    dirs: cwd === null ? [] : [cwd], sync,
  };
}

/// What to start in place of `program args` for `key` (a session's or a runner's key): the bridge, when this station
/// runs things in sandboxes; null to start it here.
export function inSandbox(data: string, key: string, program: string, args: string[], cwd: string, how: Placing = {}): { program: string; args: string[] } | null {
  const { node = process.execPath, size } = how;
  const at = placed.get(data);
  const config = at?.config() ?? null;
  if (at === undefined || config === null) return null;
  const name = size === undefined ? sandboxName(key) : sandboxName(`${key}|${size}`);
  const create = size === undefined ? undefined : [...sshArgs(config, "_"), "create", name, "--size", size];
  const sync = how.sync ?? sessionSync(data, cwd);
  // What a session's workspace has from the station goes there with it (syncChanged has nothing to copy then).
  if (size === undefined) copied.set(`${data}|${key}`, signature(sessionSync(data, cwd)));
  const spec = {
    ...bridgeSpec(at, config, data, name, cwd, sync), program, args, cwd,
    ...(create ? { create } : {}), ...(how.agent ? { agent: true } : {}), ...(how.lostFile ? { lostFile: how.lostFile } : {}),
  };
  return { program: node, args: [BRIDGE, "host", JSON.stringify(spec)] };
}

/// What `sync`'s entries have here, by size and time: the same as when last copied to a sandbox, nothing is copied.
/// None of them there at all: "" (nothing to copy).
function signature(sync: SyncEntry[]): string {
  const seen: string[] = [];
  const walk = (path: string, depth: number) => {
    let st;
    try {
      st = statSync(path);
    } catch {
      return;
    }
    if (st.isDirectory() && depth < 16) for (const name of readdirSync(path).sort()) walk(join(path, name), depth + 1);
    else if (st.isFile()) seen.push(`${path}:${st.size}:${st.mtimeMs}`);
  };
  for (const e of sync) if (e.push !== false) walk(e.path, 0);
  return seen.length === 0 ? "" : createHash("sha256").update(seen.join("\n")).digest("hex");
}

/// What was last copied to each sandbox (by its key), as `signature` has it.
const copied = new Map<string, string>();

/// Runs the bridge only to copy files, for `key`'s sandbox: `sync`'s entries, either way, unless what goes there is
/// as it was when last copied. Resolves once they are, or with why not. Nothing when the station does not run things
/// in sandboxes.
export async function syncChanged(data: string, key: string, sync: SyncEntry[]): Promise<void> {
  const now = signature(sync);
  const id = `${data}|${key}`;
  if (copied.get(id) === now || (now === "" && !copied.has(id))) return;
  await syncNow(data, key, sync);
  copied.set(id, now);
}

/// Runs the bridge only to copy files, for `key`'s sandbox: `sync`'s entries, either way. Resolves once they are, or
/// with why not. Nothing when the station does not run things in sandboxes.
export function syncNow(data: string, key: string, sync: SyncEntry[], timeoutMs = 120_000, node = process.execPath): Promise<void> {
  const at = placed.get(data);
  const config = at?.config() ?? null;
  if (at === undefined || config === null || sync.length === 0) return Promise.resolve();
  const spec = bridgeSpec(at, config, data, sandboxName(key), null, sync);
  return new Promise((resolve, reject) => {
    execFile(node, [BRIDGE, "host", JSON.stringify(spec)], { timeout: timeoutMs, maxBuffer: 16 * 1024 * 1024 }, (error, _out, err) =>
      error ? reject(new Error(err.trim().split("\n").slice(-3).join(" ") || error.message)) : resolve());
  });
}

/// Brings files of `key`'s sandbox here, at the same paths: ones the agent attaches that only it has. A path here
/// already is left as it is.
export function fetchFiles(data: string, key: string, paths: string[]): Promise<void> {
  const missing = paths.filter((p) => p.startsWith("/") && !existsSync(p));
  return syncNow(data, key, missing.map((path) => ({ path, mode: "whole" as const, push: false, dir: false })));
}

/// Whether a sandbox can be had with `config` and the station's data directory made there at its path (`persist`'s
/// link, sudo where its parent is not the sandbox user's). Says why not when it cannot (the reason switching on is
/// refused).
export function checkReach(config: SandboxConfig, data: string, timeoutMs = 120_000, node = process.execPath): Promise<{ ok: true } | { ok: false; why: string }> {
  const name = sandboxName("reach");
  const spec = { ssh: sshArgs(config, name), ports: [], root: { path: data, ...(config.persist ? { persist: config.persist } : {}) }, dirs: [], sync: [] };
  return new Promise((resolve) => {
    execFile(node, [BRIDGE, "host", JSON.stringify(spec)], { timeout: timeoutMs }, (error, _out, err) => {
      const said: { ok: true } | { ok: false; why: string } = !error ? { ok: true } : { ok: false, why: `the sandbox could not be had: ${(err || error.message).trim().split("\n").pop()}` };
      // Its sandbox is not kept: it would count against the workspace's sandboxes until it is reaped. The front door's
      // own commands are `_`'s (`ssh _.WORKSPACE@host rm NAME`).
      const [door, ...doorArgs] = sshArgs(config, "_");
      execFile(door, [...doorArgs, "rm", name, "--force"], { timeout: timeoutMs }, () => resolve(said));
    });
  });
}
