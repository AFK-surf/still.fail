// Execution in sandboxes (docs/sandbox-exec.md): with `sandbox` in config.json switched on, what the station starts for
// a session (its runtime's process, its jobs) runs in that session's own sandbox, reached over SSH (an l4es front door:
// `ssh NAME.WORKSPACE@host` makes the sandbox on first use and deletes it after it has been idle), through
// ./sandbox-bridge.mjs. The station itself, its chats, its store and its door stay here. The sandboxes see the
// same files at the same paths: the station's data directory is on storage they mount too (NFS), which switching on
// checks.
import { createHash, randomBytes } from "node:crypto";
import { execFile } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
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
};

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
  };
}

/// Checks a `sandbox` edit as config.json takes it: throws what is wrong.
export function checkSandbox(raw: any): void {
  const s = raw?.sandbox;
  if (s === undefined || s === null) return;
  if (typeof s !== "object") throw new Error("sandbox must be an object");
  if (s.enabled !== undefined && typeof s.enabled !== "boolean") throw new Error("sandbox.enabled must be true or false");
  if (typeof s.ssh !== "string" || !/^[^\s@]*\{name\}[^\s@]*@[^\s@]+$/.test(s.ssh)) throw new Error("sandbox.ssh must be like {name}.WORKSPACE@HOST");
  for (const k of ["identity", "knownHosts"]) if (s[k] !== undefined && typeof s[k] !== "string") throw new Error(`sandbox.${k} must be a path`);
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

/// ssh's command line to the sandbox `name`, up to (not including) the remote command.
export function sshArgs(config: SandboxConfig, name: string): string[] {
  const args = ["ssh", "-T", "-o", "BatchMode=yes", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=4", "-o", "StrictHostKeyChecking=accept-new"];
  if (config.identity !== undefined) args.push("-i", config.identity, "-o", "IdentitiesOnly=yes");
  if (config.knownHosts !== undefined) args.push("-o", `UserKnownHostsFile=${config.knownHosts}`);
  args.push(config.ssh.replace("{name}", name));
  return args;
}

/// Where the station's sandbox settings are, per data directory (a process may run several stations, as tests do).
const placed = new Map<string, { config: () => SandboxConfig | null; ports: () => number[] }>();

/// Says where this station's config and door are: from then on, what it starts goes to a sandbox while the config says so.
export function placeIn(data: string, config: () => SandboxConfig | null, ports: () => number[]): () => void {
  placed.set(data, { config, ports });
  return () => placed.delete(data);
}

/// Whether this station runs what it starts in sandboxes now.
export function sandboxed(data: string): boolean {
  return (placed.get(data)?.config() ?? null) !== null;
}

/// A size's name as the sandboxes' operator gives them (l4es `SBX_SANDBOX_SIZES`).
export const sizeName = (size: string) => /^[a-z][a-z0-9-]{0,30}$/.test(size);

/// How something is started in a sandbox: `node` runs the bridge; with a `size`, in a sandbox of the key's of that size,
/// which the front door is asked to make first; `agent`: a runtime's process, which ends those started there before;
/// `lostFile`: written when the connection to it is lost.
export type Placing = { node?: string; size?: string; agent?: boolean; lostFile?: string };

/// What to start in place of `program args` for `key` (a session's or a runner's key): the bridge, when this station
/// runs things in sandboxes; null to start it here.
export function inSandbox(data: string, key: string, program: string, args: string[], cwd: string, how: Placing = {}): { program: string; args: string[] } | null {
  const { node = process.execPath, size } = how;
  const at = placed.get(data);
  const config = at?.config() ?? null;
  if (at === undefined || config === null) return null;
  const name = size === undefined ? sandboxName(key) : sandboxName(`${key}|${size}`);
  const create = size === undefined ? undefined : [...sshArgs(config, "_"), "create", name, "--size", size];
  const spec = {
    ssh: sshArgs(config, name), program, args, cwd, ports: at.ports(),
    ...(create ? { create } : {}), ...(how.agent ? { agent: true } : {}), ...(how.lostFile ? { lostFile: how.lostFile } : {}),
  };
  return { program: node, args: [BRIDGE, "host", JSON.stringify(spec)] };
}

/// Whether a sandbox made with `config` sees this station's data directory at the same path: a file written here is
/// read there. Says why not when it does not (the reason switching on is refused).
export function checkReach(config: SandboxConfig, data: string, timeoutMs = 120_000): Promise<{ ok: true } | { ok: false; why: string }> {
  const dir = join(data, "run", "sandbox");
  mkdirSync(dir, { recursive: true });
  const token = randomBytes(16).toString("hex");
  const file = join(dir, `reach-${token}`);
  writeFileSync(file, token);
  const name = sandboxName("reach");
  const [ssh, ...args] = sshArgs(config, name);
  return new Promise((resolve) => {
    execFile(ssh, [...args, `cat '${file}'`], { timeout: timeoutMs }, (error, stdout, stderr) => {
      rmSync(file, { force: true });
      // Its sandbox is not kept: it would count against the workspace's sandboxes until it is reaped. The front door's
      // own commands are `_`'s (`ssh _.WORKSPACE@host rm NAME`).
      const said: { ok: true } | { ok: false; why: string } = !error && stdout.trim() === token
        ? { ok: true }
        : !error
          ? { ok: false, why: `the sandbox does not see ${data}: the station's data directory must be on storage its sandboxes mount at the same path` }
          : { ok: false, why: `the sandbox could not be reached: ${(stderr || error.message).trim().split("\n").pop()}` };
      const [door, ...doorArgs] = sshArgs(config, "_");
      execFile(door, [...doorArgs, "rm", name, "--force"], { timeout: timeoutMs }, () => resolve(said));
    });
  });
}
