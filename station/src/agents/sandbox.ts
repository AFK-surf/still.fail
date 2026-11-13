// Execution in sandboxes: with `sandbox` in config.json switched on, what the station starts for
// a session (its runtime's process, its jobs) runs in that session's own sandbox, reached over SSH (an l4es front door:
// `ssh NAME.WORKSPACE@host` makes the sandbox on first use and deletes it after it has been idle), through
// ./sandbox-bridge.mjs. The station itself, its chats, its store and its door stay here. The sandboxes share no file
// system with it: the station's data directory is made at the same path in each (on storage the sandboxes keep, when
// `persist` names it), and the bridge copies there what the station gives a program (its runtime's home, the station's
// agent home, the session's uploads) and copies back what the program writes that the station reads (transcripts, the
// agent home's memory and skills); `fetch` brings a file the agent attaches.
import { createHash, randomBytes } from "node:crypto";
import { execFile } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { mkdir, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { log } from "../ops/log.ts";
import { sandboxName } from "./sandbox-name.ts";
export { keyPart, sandboxName } from "./sandbox-name.ts";

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
  /// The node labels every sandbox it makes requires (l4es `create NAME LABEL ...`): e.g. the nodes `persist`'s NFS
  /// server can be reached from. None: any node.
  labels?: string[];
  /// How long a session's runtime process may be idle (no turn) before it is ended and its sandbox stopped (once no job
  /// of the session runs there): `stopIdle`.
  idleMinutes: number;
  /// How many sandboxes are kept made and reached ahead of need, each given to the next session whose agent starts
  /// without one (`claimFor`), another made in its place: a session starts in seconds, not in the minute and more a
  /// sandbox takes to be made and booted. They count against the l4es workspace's sandboxes.
  warm: number;
};

/// A session's sandbox is stopped this long after its last turn when config.json says nothing else.
export const IDLE_MINUTES = 10;

/// Sandboxes kept warm when config.json says nothing else, and the most it takes.
export const WARM = 1;
export const WARM_MOST = 8;

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
    ...(Array.isArray(s.labels) && s.labels.length > 0 ? { labels: s.labels } : {}),
    idleMinutes: typeof s.idleMinutes === "number" ? s.idleMinutes : IDLE_MINUTES,
    warm: typeof s.warm === "number" ? s.warm : WARM,
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
  if (s.labels !== undefined && (!Array.isArray(s.labels) || !s.labels.every((l: unknown) => typeof l === "string" && labelName(l)))) throw new Error("sandbox.labels must be a list of node labels (lowercase letters, digits, -, _ and .)");
  if (s.idleMinutes !== undefined && (typeof s.idleMinutes !== "number" || !(s.idleMinutes > 0))) throw new Error("sandbox.idleMinutes must be a number of minutes above 0");
  if (s.warm !== undefined && (!Number.isInteger(s.warm) || s.warm < 0 || s.warm > WARM_MOST)) throw new Error(`sandbox.warm must be a whole number from 0 to ${WARM_MOST}`);
}

/// The key a runner's id was made from (agents/process.ts `runnerId`: `<kind>-<clean>[-<hash>]`): the session's for a
/// session's process, the profile's for a process its sessions share (Codex's host).
export function keyOfRunner(id: string): string {
  // A Codex app-server started while one of its key was being replaced has `.<n>` after it (codex.ts `runnerFor`).
  return id.replace(/^[a-z]+-/, "").replace(/\.[0-9a-z]+$/, "");
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
  pools.set(data, loadPool(data));
  void warmUp(data);
  return () => {
    placed.delete(data);
    pools.delete(data);
  };
}

/// The warm sandboxes of a station (`warm`): `made`, those made or being made and given to no session yet (`ready` of
/// them reached once, the station's data directory made there); `claims`, the sandbox each session was given in place
/// of its own name's, until it is stopped. Kept in `run/sandbox/pool.json`, so a station started again finds them (a
/// runner it takes up still runs in a claimed one). `id` keeps two stations' names apart in one l4es workspace.
type Pool = { id: string; next: number; made: string[]; ready: Set<string>; claims: Map<string, string>; saving: Promise<void>; last: SandboxConfig | null };
const pools = new Map<string, Pool>();

const poolFile = (data: string) => join(data, "run", "sandbox", "pool.json");

function loadPool(data: string): Pool {
  let kept: any = null;
  try {
    kept = JSON.parse(readFileSync(poolFile(data), "utf8")); // sync: read once as the station places itself, before it serves
  } catch {}
  const strings = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []);
  return {
    id: typeof kept?.id === "string" ? kept.id : randomBytes(4).toString("hex"),
    next: Number.isSafeInteger(kept?.next) ? kept.next : 0,
    made: strings(kept?.made),
    ready: new Set(),
    claims: new Map(Object.entries(kept?.claims ?? {}).filter((e): e is [string, string] => typeof e[1] === "string")),
    saving: Promise.resolve(),
    last: null,
  };
}

/// Writes the pool's file, one write after another, each whole (a new file renamed over the old).
function savePool(data: string, pool: Pool): Promise<void> {
  const body = JSON.stringify({ id: pool.id, next: pool.next, made: pool.made, claims: Object.fromEntries(pool.claims) });
  const file = poolFile(data);
  pool.saving = pool.saving.then(async () => {
    await mkdir(join(data, "run", "sandbox"), { recursive: true });
    await writeFile(`${file}.new`, body);
    await rename(`${file}.new`, file);
  }).catch((e) => log.warn("sandbox", "the warm sandboxes' file was not written", { error: (e as Error).message }));
  return pool.saving;
}

/// The sandbox `key` (a session's or a runner's) runs in: the warm one it was given, else its own name's.
export function nameFor(data: string, key: string): string {
  return pools.get(data)?.claims.get(key) ?? sandboxName(key);
}

/// The warm sandboxes ready to be given, by name.
export function warmReady(data: string): string[] {
  const pool = pools.get(data);
  return pool === undefined ? [] : pool.made.filter((n) => pool.ready.has(n));
}

/// Gives `key` a warm sandbox that is ready, when it has none given and one is (another is made in its place); its
/// sandbox's name either way.
function claimFor(data: string, key: string): string {
  const pool = pools.get(data);
  const given = pool?.claims.get(key);
  if (pool === undefined || given !== undefined) return given ?? sandboxName(key);
  const name = pool.made.find((n) => pool.ready.has(n));
  if (name === undefined) return sandboxName(key);
  pool.made = pool.made.filter((n) => n !== name);
  pool.ready.delete(name);
  pool.claims.set(key, name);
  void savePool(data, pool);
  void warmUp(data);
  log.info("sandbox", "a warm sandbox given to a session", { session: key, sandbox: name });
  return name;
}

/// Makes and reaches warm sandboxes until `warm` of them are made, and deletes those beyond it (all of them when the
/// station runs nothing in sandboxes). Made with `--keep`: the front door's idle expiry passes them over, and the
/// station deletes each itself (`stopSandbox`, `sweepPool`). A sandbox that could not be had is forgotten; the next
/// look (a claim, the sweep) makes another.
export async function warmUp(data: string): Promise<void> {
  const pool = pools.get(data);
  const at = placed.get(data);
  if (pool === undefined || at === undefined) return;
  const config = at.config();
  // Switched off, the front door is the one last used.
  const door = config ?? pool.last;
  pool.last = door;
  const want = config?.warm ?? 0;
  const extra = pool.made.slice(want);
  if (extra.length > 0 && door !== null) {
    pool.made = pool.made.slice(0, want);
    for (const n of extra) pool.ready.delete(n);
    await savePool(data, pool);
    for (const n of extra) await removeSandbox(door, n);
  }
  if (config === null) return;
  const making: string[] = [];
  while (pool.made.length < want) {
    const name = sandboxName(`warm|${pool.id}|${pool.next++}`);
    pool.made.push(name);
    making.push(name);
  }
  // Those kept in the file and not reached since the station started are reached again (made already, or made now).
  for (const n of pool.made) if (!pool.ready.has(n) && !making.includes(n) && !reaching.has(`${data}|${n}`)) making.push(n);
  if (making.length === 0) return;
  await savePool(data, pool);
  await Promise.all(making.map(async (name) => {
    const id = `${data}|${name}`;
    reaching.add(id);
    const reached = await reach(at, config, data, name);
    reaching.delete(id);
    if (!pool.made.includes(name)) return;
    if (reached.ok) pool.ready.add(name);
    else {
      pool.made = pool.made.filter((n) => n !== name);
      await savePool(data, pool);
      log.warn("sandbox", "a warm sandbox could not be had", { sandbox: name, why: reached.why });
    }
  }));
}
/// The warm sandboxes being reached now, by data directory and name.
const reaching = new Set<string>();

/// Whether `name` is one of the station's warm sandboxes, given to a session or not.
function isWarm(data: string, name: string): boolean {
  const pool = pools.get(data);
  return pool !== undefined && (pool.made.includes(name) || [...pool.claims.values()].includes(name));
}

/// Makes warm sandbox `name` (kept, with the config's labels) and reaches it: the station's data directory made there,
/// nothing run. Says why not when it cannot.
function reach(at: Placed, config: SandboxConfig, data: string, name: string, timeoutMs = 300_000, node = process.execPath): Promise<{ ok: true } | { ok: false; why: string }> {
  const spec = { ssh: sshArgs(config, name), create: createFor(config, name, undefined, true), ports: at.ports(), root: { path: data, ...(config.persist ? { persist: config.persist } : {}) }, dirs: [], sync: [] };
  return new Promise((resolve) =>
    execFile(node, [BRIDGE, "host", JSON.stringify(spec)], { timeout: timeoutMs }, (error, _out, err) =>
      resolve(!error ? { ok: true } : { ok: false, why: (err || error.message).trim().split("\n").pop() ?? "" })));
}

/// Stops the sandboxes given to sessions whose processes are all gone (`running` says no): one whose process ended
/// some other way than going idle (it exited, the station restarted without it), which the front door's idle list
/// does not show, being kept. Then makes or deletes warm ones as `warm` says. At each sweep (hub.ts `sweepSandboxes`).
export async function sweepPool(data: string, running: (key: string) => boolean): Promise<void> {
  const pool = pools.get(data);
  if (pool === undefined) return;
  for (const key of [...pool.claims.keys()]) if (!running(key)) await stopSandbox(data, key);
  await warmUp(data);
}

/// Deletes sandbox `name` at the front door; whether it was.
function removeSandbox(config: SandboxConfig, name: string, timeoutMs = 60_000): Promise<boolean> {
  const [ssh, ...args] = sshArgs(config, "_");
  return new Promise((resolve) => execFile(ssh, [...args, "rm", name], { timeout: timeoutMs }, (error, out) => resolve(!error && /^deleting /m.test(out))));
}

/// What of a runtime's home is its own, made as it runs, and stays in the sandbox (its login is given each process:
/// `lentFile`, the Claude driver's token).
const CLAUDE_OWN = ["projects", "todos", "shell-snapshots", "statsig", "debug", "logs", "file-history", "ide", "session-env", "plugins", "cache", "telemetry", "paste-cache", "history.jsonl", "backups", ".credentials.json"];
const CODEX_OWN = ["sessions", "archived_sessions", "log", "tmp", ".tmp", "shell_snapshots", "cache", "history.jsonl", "models_cache.json", "auth.json"];
const AGY_OWN = [
  "annotations",
  "bin",
  "brain",
  "builtin",
  "cache",
  "cli.log",
  "conversations",
  "crashes",
  "implicit",
  "log",
  "persistent_terminals",
  "updater",
  "conversation_summaries.db",
  "conversation_summaries.db-shm",
  "conversation_summaries.db-wal",
  "jetbox_summaries_proto.pb",
  "last_check.timestamp",
];

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
  if (runtime === "agy" && env.ANTIGRAVITY_GEMINI_DIR) {
    sync.push({ path: env.ANTIGRAVITY_GEMINI_DIR, mode: "whole", skip: AGY_OWN });
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

/// The sandboxes of the l4es workspace no connection holds now, by name (`ls` says when idle expiry would take them).
export function idleSandboxes(data: string, timeoutMs = 60_000): Promise<string[]> {
  const config = placed.get(data)?.config() ?? null;
  if (config === null) return Promise.resolve([]);
  const [ssh, ...args] = sshArgs(config, "_");
  return new Promise((resolve) =>
    execFile(ssh, [...args, "ls"], { timeout: timeoutMs }, (error, out) =>
      resolve(error ? [] : out.split("\n").flatMap((line) => (/^\S+\s+running\s.*\sdeleted in /.test(line) ? [line.split(/\s+/)[0]!] : [])))),
  );
}

/// Stops (deletes) `key`'s sandbox, `size`'s of it when given: what it has on its own disk goes, its files in
/// `persist` stay for the next. The front door refuses while anything still has a connection to it (a job, a program
/// started since): then it stays, and is stopped when that ends. Whether it was stopped.
export async function stopSandbox(data: string, key: string, size?: string, timeoutMs = 60_000): Promise<boolean> {
  const config = placed.get(data)?.config() ?? null;
  if (config === null) return false;
  const name = size === undefined ? nameFor(data, key) : sandboxName(`${key}|${size}`);
  const stopped = await removeSandbox(config, name, timeoutMs);
  // A warm one given to the session is gone with it: its next start is given another, or makes its own.
  const pool = pools.get(data);
  if (stopped && size === undefined && pool?.claims.get(key) === name) {
    pool.claims.delete(key);
    await savePool(data, pool);
  }
  return stopped;
}

/// A size's name as the sandboxes' operator gives them (l4es `SBX_SANDBOX_SIZES`).
export const sizeName = (size: string) => /^[a-z][a-z0-9-]{0,30}$/.test(size);

/// A node label as l4es takes one.
const labelName = (label: string) => /^[a-z0-9][a-z0-9_.-]{0,62}$/.test(label);

/// The front door's command that makes sandbox `name` (or finds it there, made the same way) before it is connected
/// to: with a size or the config's labels. None: the first connection makes it, of the default size on any node.
function createFor(config: SandboxConfig, name: string, size?: string, keep = false): string[] | undefined {
  const labels = config.labels ?? [];
  if (size === undefined && labels.length === 0 && !keep) return undefined;
  return [...sshArgs(config, "_"), "create", name, ...(size === undefined ? [] : ["--size", size]), ...(keep ? ["--keep"] : []), ...labels];
}

/// How something is started in a sandbox: `node` runs the bridge; with a `size`, in a sandbox of the key's of that size,
/// which the front door is asked to make first; `agent`: a runtime's process, which ends those started there before;
/// `lostFile`: written when the connection to it is lost; `sync`: what is copied there and back (`syncFor`).
export type Placing = { node?: string; size?: string; agent?: boolean; lostFile?: string; sync?: SyncEntry[] };

/// The bridge's spec for sandbox `name`, without a program: what is copied, where the data directory is.
function bridgeSpec(at: Placed, config: SandboxConfig, data: string, name: string, cwd: string | null, sync: SyncEntry[], size?: string) {
  // A warm one is made again as it was (kept) when the front door lost it, not as a session's own.
  const create = createFor(config, name, size, size === undefined && isWarm(data, name));
  return {
    ssh: sshArgs(config, name), ports: at.ports(), ...(create ? { create } : {}),
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
  // A session's agent starting without a sandbox of its own takes a warm one; what else it starts (its jobs) goes where
  // its agent is.
  const name = size !== undefined ? sandboxName(`${key}|${size}`) : how.agent ? claimFor(data, key) : nameFor(data, key);
  const sync = how.sync ?? sessionSync(data, cwd);
  // What a session's workspace has from the station goes there with it (syncChanged has nothing to copy then).
  if (size === undefined) copied.set(`${data}|${key}`, signature(sessionSync(data, cwd)));
  const spec = {
    ...bridgeSpec(at, config, data, name, cwd, sync, size), program, args, cwd,
    ...(how.agent ? { agent: true } : {}), ...(how.lostFile ? { lostFile: how.lostFile } : {}),
    // The station's GitHub login, lent to what runs there (sandbox-bridge.mjs `lendGh`).
    gh: true,
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
  const spec = bridgeSpec(at, config, data, nameFor(data, key), null, sync);
  return new Promise((resolve, reject) => {
    execFile(node, [BRIDGE, "host", JSON.stringify(spec)], { timeout: timeoutMs, maxBuffer: 16 * 1024 * 1024 }, (error, _out, err) =>
      error ? reject(new Error(err.trim().split("\n").slice(-3).join(" ") || error.message)) : resolve());
  });
}

/// A path in a sandbox as the station names it: one under `persist` (where the data directory's link leads there, as
/// an agent may see it) is the same file under the data directory.
export function stationPath(data: string, path: string): string {
  const persist = placed.get(data)?.config()?.persist;
  if (!persist) return path;
  const base = persist.replace(/\/+$/, "");
  return path === base ? data : path.startsWith(`${base}/`) ? join(data, path.slice(base.length + 1)) : path;
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
  const create = createFor(config, name);
  const spec = { ssh: sshArgs(config, name), ...(create ? { create } : {}), ports: [], root: { path: data, ...(config.persist ? { persist: config.persist } : {}) }, dirs: [], sync: [] };
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
