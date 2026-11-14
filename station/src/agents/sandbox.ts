// Sandboxes as targets of station_task (托管重任务, 左子健 2026-11-13: 「直接写 station 配置就好吧，然后就多一个可以排任务的
// 目标」): each of config.json's `sandboxes` is an l4es front door (`{name}.WORKSPACE@host`, at a size of its operator's),
// listed by station_list and sent tasks by its name as a station is. Nothing is installed there and no agent runs there:
// the station takes the task itself (jobs/remote.ts `ask`), as its own job, and runs its command in a sandbox of the
// chat's (made on the first task, deleted by the front door once idle) through ./sandbox-bridge.mjs, which carries itself
// over ssh (the sandbox needs only node), copies the task's mirror there before the command and brings what the task
// brings back (`back`) here once it ends. The job's log, its exit and its notices are the station's own, as any job's.
import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { sandboxName } from "./sandbox-name.ts";
import type { Json } from "../store/store.ts";

/// How a sandbox is named as a station of station_task's: `sandbox:<its name>`.
export const SANDBOX = "sandbox:";

/// The bridge the station runs in a sandbox job's place.
export const BRIDGE = fileURLToPath(new URL("./sandbox-bridge.mjs", import.meta.url));

/// What the bridge says, and its exit code, when the connection to the sandbox was lost rather than the command
/// ending (sandbox-bridge.mjs `LOST`): a job is started again once.
export const CONNECTION_LOST = "sandbox: the connection to the sandbox was lost";
export const LOST_EXIT = 75;

/// One of config.json's `sandboxes`: its name, its front door, its size, and the key the station signs in with there
/// (none: the station's own, `identityOf`).
export type Sandbox = { name: string; target: string; size?: string; identity?: string };

/// Where a job runs in a sandbox: which (by its name), the chat (each has a sandbox of its own there) and what is
/// brought back.
export type SandboxPlace = { sandbox: string; session: string; back: string[] };

/// config.json's `sandboxes` as the station takes them: those that are not well formed left out (`checkSandboxes` says
/// why as one is written).
export function sandboxesOf(raw: any): Sandbox[] {
  const list = Array.isArray(raw?.sandboxes) ? raw.sandboxes : [];
  return list.filter((s: unknown) => sandboxRefusal(s) === null).map((s: any) => ({
    name: s.name, target: s.target, ...(typeof s.size === "string" ? { size: s.size } : {}), ...(typeof s.identity === "string" ? { identity: s.identity } : {}),
  }));
}

/// Throws what is wrong with config.json's `sandboxes`.
export function checkSandboxes(raw: any): void {
  const list = raw?.sandboxes;
  if (list === undefined || list === null) return;
  if (!Array.isArray(list)) throw new Error("sandboxes must be a list");
  const names = new Set<string>();
  for (const s of list) {
    const why = sandboxRefusal(s);
    if (why !== null) throw new Error(`sandboxes: ${why}`);
    if (names.has(s.name.toLowerCase())) throw new Error(`sandboxes: ${s.name} is named twice`);
    names.add(s.name.toLowerCase());
  }
}

/// Why `s` is no sandbox, or null.
function sandboxRefusal(s: any): string | null {
  if (s === null || typeof s !== "object") return "each is {name, target, size?, identity?}";
  if (typeof s.name !== "string" || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$/.test(s.name)) return "a name of letters, digits, ., _ and -";
  if (typeof s.target !== "string" || !/^[^\s@]*\{name\}[^\s@]*@[^\s@]+$/.test(s.target)) return `${s.name}'s target is its front door, like {name}.WORKSPACE@HOST`;
  if (s.size !== undefined && (typeof s.size !== "string" || !/^[a-z][a-z0-9-]{0,30}$/.test(s.size))) return `${s.name}'s size is the name of one of its operator's sizes`;
  if (s.identity !== undefined && (typeof s.identity !== "string" || !s.identity.startsWith("/"))) return `${s.name}'s identity is a key's absolute path`;
  return null;
}

/// What `describe` says of a sandbox in station_list.
export function sandboxDescribed(d: Sandbox): Json {
  return {
    kind: "sandbox", target: d.target, ...(d.size !== undefined ? { size: d.size } : {}),
    tasks: true, files: true, sync: 1, sessions: false, messages: false, reads: false, chats: false,
    note: "A sandbox: a Linux sandbox of this chat's, made for its first task and deleted once idle. Run builds and tests there with station_task (dir to sync, back to bring results here); no screen. The first time, its front door may ask for this station's key to be linked: the task's log gives the link a person opens.",
  };
}

/// The station's own ssh key for its sandboxes, and the host keys it took: made at the first task.
export const identityOf = (data: string) => join(data, "run", "sandbox", "id_ed25519");
const knownHostsOf = (data: string) => join(data, "run", "sandbox", "known_hosts");

/// The station's key made where it has none: the front door asks a person to link it once (its message, in the
/// task's log, names where).
export async function ensureIdentity(data: string): Promise<void> {
  const file = identityOf(data);
  if (existsSync(file)) return; // sync: one stat, the key made once
  await mkdir(join(data, "run", "sandbox"), { recursive: true });
  await new Promise<void>((resolve, reject) =>
    execFile("ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-C", "stillfail-station", "-f", file], (error) => (error ? reject(error) : resolve())));
}

/// ssh's command line to `destination` with `identity` (none: the station's key), up to (not including) the remote
/// command.
function sshTo(data: string, destination: string, identity = identityOf(data)): string[] {
  return [
    "ssh", "-T", "-o", "BatchMode=yes", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=4", "-o", "StrictHostKeyChecking=accept-new",
    "-i", identity, "-o", "IdentitiesOnly=yes", "-o", `UserKnownHostsFile=${knownHostsOf(data)}`, destination,
  ];
}

/// The sandbox of chat `session` at `d`, by its name at the front door.
export const sandboxOf = (d: Sandbox, session: string) => sandboxName(`${d.name}|${session}`);

/// What the shell runs in place of a job's command in a sandbox: the bridge, which makes the sandbox (of its
/// size) when there is none, makes the station's data directory there at its path, copies `cwd` there and runs
/// `command` in it by sh; then the bridge again, with no command, to bring `back`'s paths here. The command's exit code
/// is the job's. `ports`: the station's own ports its command reaches on 127.0.0.1 (a job's notice), listened for there.
export function sandboxCommand(data: string, d: Sandbox, place: SandboxPlace, command: string, cwd: string, ports: number[], lostFile: string, node = process.execPath): string {
  const name = sandboxOf(d, place.session);
  const base = {
    ssh: sshTo(data, d.target.replace("{name}", name), d.identity),
    ...(d.size !== undefined ? { create: [...sshTo(data, d.target.replace("{name}", "_"), d.identity), "create", name, "--size", d.size] } : {}),
    root: { path: data },
    dirs: [cwd],
  };
  // The task's directory goes there; what the command makes there stays there (its build output, for the next task).
  const run = { ...base, ports, sync: [{ path: cwd, mode: "whole", back: false, dir: true }], program: "/bin/sh", args: ["-c", command], cwd, lostFile };
  // What it brings back, once it ended: a file or a directory, whichever it is there.
  const back = { ...base, sync: place.back.map((b) => ({ path: join(cwd, b), mode: "whole", push: false, dir: false })) };
  const bridge = (spec: object) => [node, BRIDGE, "host", JSON.stringify(spec)].map(quoted).join(" ");
  return place.back.length === 0 ? bridge(run) : `${bridge(run)}; code=$?; ${bridge(back)}; exit $code`;
}

/// `s` as one word of sh's.
const quoted = (s: string) => `'${s.replace(/'/g, `'\\''`)}'`;

