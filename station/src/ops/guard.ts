// The station's guard over the machine its agents share with it. An agent runs as the station's own user, in no
// sandbox: what macOS has to keep one apart breaks what agents run (a Seatbelt sandbox leaves the programs under it
// none of their own: Chromium's, SwiftPM's and Claude Code's fail), or needs root (a volume with a quota). So the
// station watches what an agent can bring it down by, the disk it keeps its data on and the machine's memory, and acts
// on the agents' commands (the shells a runtime starts them in, and their jobs), never on a runtime itself:
// - the disk running low: the agents at work are told to clear what they made, once;
// - the disk all but full: the commands running then are paused (SIGSTOP), so the station and its database do not go
//   down with them, and go on (SIGCONT) once there is room again. Commands started after are not: an agent clearing
//   space runs them;
// - memory at the system's critical pressure: the command holding the most is ended, and its agent told.
import type { MemoryPressure, ProcessEntry } from "../platform/index.ts";
import { log } from "./log.ts";

const GiB = 1024 ** 3;

/// Room on the data disk below which the agents are told (`low`) and their commands paused (`full`): these, or on a
/// small disk (a VM's) these shares of it.
export function diskLimits(total: number): { low: number; full: number } {
  return { low: Math.min(8 * GiB, total * 0.1), full: Math.min(2 * GiB, total * 0.03) };
}

/// Paused commands go on once twice the `full` room is free: not at the line itself, where the next write stops them.
const RESUME_FACTOR = 2;
/// A command is ended for memory only when it holds this much (kB): ending a smaller one frees nothing that matters.
const KILL_MIN_KB = 512 * 1024;
/// After ending one, the system is given this long to take its memory back before another is.
const KILL_SPACING_MS = 30_000;
/// How long a command asked to end (SIGTERM) has before it is made to.
const KILL_GRACE_MS = 5_000;
/// How often the guard looks.
export const GUARD_EVERY_MS = 10_000;

const SHELLS = new Set(["sh", "bash", "zsh", "dash", "fish", "ksh"]);

/// A program's name as ps gives it: no directory, no login shell's `-`.
const programName = (command: string) => command.slice(command.lastIndexOf("/") + 1).replace(/^-/, "");

/// An agent's runtime process (claude, codex app-server), with the session it is when the runtime is one session's.
export type Runtime = { pid: number; session: string | null };
/// A job running (jobs/jobs.ts), its group.
export type RunningJob = { id: string; pgid: number; session: string; name: string };

/// One command of an agent's: a shell its runtime started and all under it, or a job's group.
export type Command = { pids: number[]; rssKb: number; session: string | null; what: string; job: RunningJob | null };

/// The agents' commands among the machine's processes: each job's group and what its members started, and each shell a
/// runtime started with what it started. A runtime's other processes (its MCP servers) are its own, not commands.
export function commands(table: ProcessEntry[], runtimes: Runtime[], jobs: RunningJob[]): Command[] {
  const children = new Map<number, ProcessEntry[]>();
  for (const p of table) if (p.ppid !== p.pid) children.set(p.ppid, [...(children.get(p.ppid) ?? []), p]);
  const taken = new Set<number>();
  const under = (roots: ProcessEntry[]): ProcessEntry[] => {
    const out: ProcessEntry[] = [];
    const stack = [...roots];
    while (stack.length > 0) {
      const p = stack.pop()!;
      if (taken.has(p.pid)) continue;
      taken.add(p.pid);
      out.push(p);
      stack.push(...(children.get(p.pid) ?? []));
    }
    return out;
  };
  const command = (members: ProcessEntry[], session: string | null, job: RunningJob | null): Command => {
    // Said by its biggest program that is not a shell (the build, the browser), or its shell.
    const named = [...members].sort((a, b) => b.rssKb - a.rssKb).find((p) => !SHELLS.has(programName(p.command))) ?? members[0]!;
    return {
      pids: members.map((p) => p.pid),
      rssKb: members.reduce((n, p) => n + p.rssKb, 0),
      session,
      what: job ? `job "${job.name}"` : programName(named.command),
      job,
    };
  };
  const found: Command[] = [];
  for (const job of jobs) {
    const members = under(table.filter((p) => p.pgid === job.pgid));
    if (members.length > 0) found.push(command(members, job.session, job));
  }
  for (const runtime of runtimes) {
    // The first shell down each line from the runtime: one started by it is under what it runs as (codex's npm
    // launcher runs its binary, which starts the shells).
    const stack = [...(children.get(runtime.pid) ?? [])];
    while (stack.length > 0) {
      const child = stack.pop()!;
      if (!SHELLS.has(programName(child.command))) {
        stack.push(...(children.get(child.pid) ?? []));
        continue;
      }
      const members = under([child]);
      if (members.length > 0) found.push(command(members, runtime.session, null));
    }
  }
  return found;
}

export type GuardDeps = {
  /// The data disk's room (bytes), none when it cannot be read.
  disk(): { free: number; total: number } | null;
  memoryPressure(): Promise<MemoryPressure | null>;
  processes(): Promise<ProcessEntry[]>;
  runtimes(): Runtime[];
  jobs(): RunningJob[];
  /// The session whose workspace `pid` works in (a command of a runtime several sessions share).
  sessionAt(pid: number): Promise<string | null>;
  /// The sessions whose agent is at work now.
  atWork(): string[];
  signal(pid: number, signal: "SIGSTOP" | "SIGCONT" | "SIGTERM" | "SIGKILL"): void;
  stopJob(id: string): Promise<void>;
  /// A word from the station for a session's agent (Hub.notify).
  tell(session: string, text: string): void;
  now(): number;
  sleep(ms: number): Promise<void>;
};

const gb = (bytes: number) => `${(bytes / GiB).toFixed(1)} GB`;

export class Guard {
  readonly #deps: GuardDeps;
  #disk: "ok" | "low" | "full" = "ok";
  /// The processes paused for the disk, with their sessions.
  #paused = new Map<number, string | null>();
  #lastKill: number | null = null;
  #looking = false;

  constructor(deps: GuardDeps) {
    this.#deps = deps;
  }

  /// Looks once (GUARD_EVERY_MS); a look still going is not doubled.
  async look(): Promise<void> {
    if (this.#looking) return;
    this.#looking = true;
    try {
      await this.#lookAtDisk();
      await this.#lookAtMemory();
    } finally {
      this.#looking = false;
    }
  }

  /// What it paused goes on: the station stops (the next one pauses again if the disk is still full).
  close() {
    for (const pid of this.#paused.keys()) this.#signal(pid, "SIGCONT");
    this.#paused.clear();
  }

  async #lookAtDisk() {
    const room = this.#deps.disk();
    if (room === null) return;
    const { low, full } = diskLimits(room.total);
    let level: "ok" | "low" | "full" = room.free < full ? "full" : room.free < low ? "low" : "ok";
    if (this.#disk === "full" && room.free < full * RESUME_FACTOR) level = "full";
    const was = this.#disk;
    if (level === was) return;
    this.#disk = level;
    log.warn("guard", "the data disk's room changed", { level, was, free: room.free });
    if (level === "full") return this.#pause(room.free, full);
    if (was === "full") this.#resume(room.free);
    if (level === "low" && was === "ok") {
      for (const session of this.#deps.atWork()) this.#tell(session, `${this.#lowWords(room.free)} Clear what you made that can be made again (build output, node_modules, logs and files you left in /tmp) and write nothing large here until there is room.`);
    }
  }

  #lowWords(free: number) {
    return `The disk this station keeps its data on has ${gb(free)} left.`;
  }

  async #pause(free: number, full: number) {
    const found = await this.#commands();
    const bySession = new Map<string | null, string[]>();
    for (const c of found) {
      for (const pid of c.pids) {
        this.#signal(pid, "SIGSTOP");
        this.#paused.set(pid, c.session);
      }
      bySession.set(c.session, [...(bySession.get(c.session) ?? []), c.what]);
    }
    log.warn("guard", "the data disk is all but full: the agents' commands paused", { free, commands: found.map((c) => c.what).join(" "), processes: this.#paused.size });
    const resumeAt = gb(full * RESUME_FACTOR);
    for (const [session, whats] of bySession) {
      if (session === null) continue;
      this.#tell(session, `${this.#lowWords(free)} Your commands running then are paused (not ended) so the station does not go down: ${whats.join(", ")}. Free space now (build output, node_modules, logs and files you left in /tmp; nothing someone else needs): they go on by themselves once ${resumeAt} is free. Commands you start now run.`);
    }
    for (const session of this.#deps.atWork()) {
      if (bySession.has(session)) continue;
      this.#tell(session, `${this.#lowWords(free)} Other agents' commands are paused until ${resumeAt} is free. Clear what you made that can be made again and write nothing large here.`);
    }
  }

  #resume(free: number) {
    const sessions = new Set([...this.#paused.values()].filter((s): s is string => s !== null));
    this.close();
    log.info("guard", "room on the data disk again: the paused commands go on", { free });
    for (const session of sessions) this.#tell(session, `There is room on the disk again (${gb(free)} free): your paused commands go on.`);
  }

  async #lookAtMemory() {
    if ((await this.#deps.memoryPressure()) !== "critical") return;
    const now = this.#deps.now();
    if (this.#lastKill !== null && now - this.#lastKill < KILL_SPACING_MS) return;
    const biggest = (await this.#commands()).filter((c) => c.rssKb >= KILL_MIN_KB).sort((a, b) => b.rssKb - a.rssKb)[0];
    if (!biggest) return;
    this.#lastKill = now;
    const session = biggest.session ?? (await this.#deps.sessionAt(biggest.pids[0]!));
    log.warn("guard", "memory is critically short: ending the agents' biggest command", { what: biggest.what, kb: biggest.rssKb, session });
    if (biggest.job) await this.#deps.stopJob(biggest.job.id).catch((error) => log.warn("guard", "the job did not stop", { job: biggest.job!.id, error: (error as Error).message }));
    else {
      for (const pid of biggest.pids) this.#signal(pid, "SIGTERM");
      // A paused one takes its signal once it goes on.
      for (const pid of biggest.pids) if (this.#paused.delete(pid)) this.#signal(pid, "SIGCONT");
      await this.#deps.sleep(KILL_GRACE_MS);
      for (const pid of biggest.pids) this.#signal(pid, "SIGKILL");
    }
    if (session !== null) {
      this.#tell(session, `This machine ran out of memory, and the station ended your ${biggest.what} (${gb(biggest.rssKb * 1024)}), the agents' command holding the most. Run it again with less at once (fewer workers or browsers), or on another station.`);
    }
  }

  /// The agents' commands now; none when the processes cannot be read.
  async #commands(): Promise<Command[]> {
    try {
      return commands(await this.#deps.processes(), this.#deps.runtimes(), this.#deps.jobs());
    } catch (error) {
      log.warn("guard", "the processes were not read", { error: (error as Error).message });
      return [];
    }
  }

  #signal(pid: number, signal: "SIGSTOP" | "SIGCONT" | "SIGTERM" | "SIGKILL") {
    try {
      this.#deps.signal(pid, signal);
    } catch {
      // Gone already.
    }
  }

  #tell(session: string, text: string) {
    try {
      this.#deps.tell(session, text);
    } catch (error) {
      log.warn("guard", "a session was not told", { session, error: (error as Error).message });
    }
  }
}
