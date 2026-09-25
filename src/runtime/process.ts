// Runtime processes run in their own process group, recorded in the store, so
// ember can end everything a runtime started (tool subprocesses, dev servers)
// and reap groups a previous ember run left behind.
import { execFileSync, spawn, type ChildProcess } from "node:child_process";
import { createInterface } from "node:readline";
import type { RuntimeKind } from "../config.ts";
import { log } from "../log.ts";

export interface ProcessRegistry {
  recordProcess(pgid: number, startedAt: number, runtime: RuntimeKind, label: string): void;
  forgetProcess(pgid: number): void;
  listProcesses(): { pgid: number; startedAt: number; runtime: RuntimeKind; label: string }[];
}

export interface GroupProcess {
  readonly pgid: number;
  readonly child: ChildProcess;
  write(line: string): void;
  /** Resolves with the exit code (or signal name) once the leader exits. */
  readonly exited: Promise<string>;
  /** SIGTERM the whole group, SIGKILL whatever is left after `graceMs`. */
  kill(graceMs?: number): Promise<void>;
}

export function spawnGroup(options: {
  command: string;
  args: string[];
  cwd: string;
  env: NodeJS.ProcessEnv;
  runtime: RuntimeKind;
  label: string;
  registry: ProcessRegistry;
  onLine(line: string): void;
}): GroupProcess {
  const child = spawn(options.command, options.args, {
    cwd: options.cwd,
    env: options.env,
    stdio: ["pipe", "pipe", "pipe"],
    detached: true,
  });
  const pgid = child.pid;
  if (pgid === undefined) throw new Error(`failed to spawn ${options.command}`);
  options.registry.recordProcess(pgid, Date.now(), options.runtime, options.label);

  createInterface({ input: child.stdout! }).on("line", options.onLine);
  createInterface({ input: child.stderr! }).on("line", (line) =>
    log.debug("runtime stderr", { runtime: options.runtime, label: options.label, line: line.slice(0, 2000) }));
  child.stdin!.on("error", () => { /* the process went away; exit handling reports it */ });

  const exited = new Promise<string>((resolve) => {
    child.on("exit", (code, signal) => resolve(code === null ? String(signal) : String(code)));
    child.on("error", (error) => resolve(`spawn error: ${error.message}`));
  });
  let killing: Promise<void> | undefined;

  return {
    pgid,
    child,
    exited,
    write(line) {
      if (child.stdin!.writable) child.stdin!.write(line.endsWith("\n") ? line : `${line}\n`);
    },
    kill(graceMs = 5000) {
      killing ??= (async () => {
        signalGroup(pgid, "SIGTERM");
        const deadline = Date.now() + graceMs;
        while (Date.now() < deadline && groupAlive(pgid)) await new Promise((r) => setTimeout(r, 100));
        if (groupAlive(pgid)) signalGroup(pgid, "SIGKILL");
        options.registry.forgetProcess(pgid);
      })();
      return killing;
    },
  };
}

function signalGroup(pgid: number, signal: NodeJS.Signals): void {
  try {
    process.kill(-pgid, signal);
  } catch {
    // ESRCH: the group is already gone.
  }
}

function groupAlive(pgid: number): boolean {
  try {
    process.kill(-pgid, 0);
    return true;
  } catch {
    return false;
  }
}

/** Start time of `pid` in ms, or undefined if it is not running. */
function startTimeOf(pid: number): number | undefined {
  try {
    const out = execFileSync("ps", ["-o", "lstart=", "-p", String(pid)], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
    const time = Date.parse(out);
    return Number.isNaN(time) ? undefined : time;
  } catch {
    return undefined;
  }
}

/**
 * Kills process groups recorded by an earlier ember run. A group whose leader
 * is alive is only ours if the leader started when we recorded it (pids get
 * reused); a group whose leader is gone but still has members is ours, because
 * a pgid cannot be reused while any member remains.
 */
export async function reapStaleGroups(registry: ProcessRegistry): Promise<number> {
  let reaped = 0;
  for (const entry of registry.listProcesses()) {
    const leaderStart = startTimeOf(entry.pgid);
    const ours = leaderStart === undefined ? groupAlive(entry.pgid) : Math.abs(leaderStart - entry.startedAt) < 5000;
    if (ours && groupAlive(entry.pgid)) {
      log.warn("reaping process group left by a previous run", entry);
      signalGroup(entry.pgid, "SIGTERM");
      await new Promise((r) => setTimeout(r, 2000));
      if (groupAlive(entry.pgid)) signalGroup(entry.pgid, "SIGKILL");
      reaped++;
    }
    registry.forgetProcess(entry.pgid);
  }
  return reaped;
}
