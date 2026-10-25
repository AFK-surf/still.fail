// The station's watch over the memory of what its agents run (docs/station-scheduling.md): their jobs and other
// stations' tasks here, and the commands the agents' runtimes run themselves (a test an agent starts in its own shell).
// Nothing is stopped for using much: its agent is told. Only when the system says it is about to run out of memory
// (critical) is the largest of them stopped, one at a time, its agent told why: the machine is kept up.
//
// - A unit is what is stopped together: a job's process group (and what its members started), or one command a
//   runtime started (a child of the runtime's process, and all under it). The runtimes themselves, the runners and the
//   station are never units.
// - A unit over LIMIT (an eighth of the machine's memory, 2 GiB at least): its agent told, again each time it doubles.
// - The memory under pressure (high): the agents of the largest few told, once each while it lasts. (The queue,
//   jobs/admit.ts, starts no task meanwhile.)
// - Critical: the largest unit stopped (SIGTERM, SIGKILL after STOP_GRACE_MS); another only SETTLE_MS later, if it is
//   still critical.
//
// Looked at every WATCH_MS, every PRESSED_MS under pressure, when the memory is read exactly (macOS: the processes'
// footprint, which counts what is compressed or swapped out, where resident memory does not).
import { totalmem } from "node:os";
import type { Clock } from "effect";
import { runnerId } from "../agents/process.ts";
import { existingRunners, type RunnerInfo } from "../agents/runner.ts";
import { RUNTIME_KINDS } from "../agents/runtime.ts";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { type ProcessInfo, platform } from "../platform/index.ts";
import type { Store } from "../store/store.ts";
import type { Pressure } from "./admit.ts";
import { type Jobs, named } from "./jobs.ts";

export const WATCH_MS = 10_000;
export const PRESSED_MS = 5000;
export const SETTLE_MS = 15_000;
export const STOP_GRACE_MS = 5000;
/// What is told under pressure and stopped when critical is at least this big: a small one would not help.
export const TOLD_MIN = 512 * 1024 ** 2;
/// How many agents are told when the memory comes under pressure.
export const TOLD_PRESSED = 3;

/// A unit's agent told when it is over this: an eighth of the machine's memory, 2 GiB at least.
export const limitOf = (totalBytes: number): number => Math.max(2 * 1024 ** 3, Math.floor(totalBytes / 8));

export type Unit = {
  /// The same unit from one look to the next: its job, or the command's pid.
  key: string;
  /// Whose (a session key); null when not known (a command of a runtime shared by sessions, in no session's directory).
  session: string | null;
  /// Its job, when it is one.
  job: string | null;
  /// How its agent is told of it.
  label: string;
  pids: number[];
  bytes: number;
};

export type WatchedJob = { id: string; session: string; pgid: number; label: string };
export type WatchedAgent = { pid: number; session: string | null };

/// The units of `table`: the jobs' groups first, then the commands each runtime started (children of `agents`' pids).
export function unitsOf(table: readonly ProcessInfo[], jobs: readonly WatchedJob[], agents: readonly WatchedAgent[], self: number): Unit[] {
  const children = new Map<number, number[]>();
  const byPid = new Map<number, ProcessInfo>();
  for (const p of table) {
    byPid.set(p.pid, p);
    if (p.pid !== p.ppid) children.set(p.ppid, [...(children.get(p.ppid) ?? []), p.pid]);
  }
  const taken = new Set<number>([self]);
  // What runs the agents is never part of a unit.
  for (const a of agents) taken.add(a.pid);
  const under = (roots: number[]): number[] => {
    const out: number[] = [];
    for (const queue = [...roots]; queue.length > 0; ) {
      const pid = queue.pop()!;
      if (taken.has(pid) || !byPid.has(pid)) continue;
      taken.add(pid);
      out.push(pid);
      queue.push(...(children.get(pid) ?? []));
    }
    return out;
  };
  const sum = (pids: number[]) => pids.reduce((n, pid) => n + (byPid.get(pid)?.bytes ?? 0), 0);
  const units: Unit[] = [];
  for (const j of jobs) {
    const pids = under(table.filter((p) => p.pgid === j.pgid).map((p) => p.pid));
    if (pids.length > 0) units.push({ key: `job:${j.id}`, session: j.session, job: j.id, label: j.label, pids, bytes: sum(pids) });
  }
  for (const a of agents) {
    for (const child of children.get(a.pid) ?? []) {
      const pids = under([child]);
      if (pids.length === 0) continue;
      // Named by its biggest process, the one people would recognize (node, cargo, zig), and the command's pid.
      const big = pids.reduce((b, pid) => ((byPid.get(pid)?.bytes ?? 0) > (byPid.get(b)?.bytes ?? 0) ? pid : b), child);
      const program = (byPid.get(big)?.command ?? "").split("/").at(-1) || "a command";
      units.push({ key: `pid:${child}`, session: a.session, job: null, label: `command ${program} (pid ${child})`, pids, bytes: sum(pids) });
    }
  }
  return units;
}

export type MemoryOptions = {
  clock?: Clock.Clock;
  pressure(): Promise<Pressure | null>;
  table(exact: boolean): Promise<ProcessInfo[] | null>;
  totalBytes(): number;
  /// The working directories of processes, for a command whose session its runtime does not say.
  cwds(pids: number[]): Promise<Map<number, string>>;
  jobs(): WatchedJob[];
  agents(): WatchedAgent[];
  /// The session whose directory `dir` is in.
  sessionAt(dir: string): string | null;
  /// Tells a unit's agent: a job's through the job (another station's task: its notices), a command's its session's.
  tell(unit: Unit, text: string): void;
  stopJob(id: string): Promise<void>;
  signal(pid: number, signal: NodeJS.Signals): void;
  self: number;
};

const gib = (bytes: number) => `${(bytes / 1024 ** 3).toFixed(1)} GiB`;

export class MemoryWatch {
  readonly #o: MemoryOptions;
  readonly #fibers: Fibers;
  /// How big each unit was when its agent was last told it is over the limit.
  #told = new Map<string, number>();
  /// The units told while the memory is under pressure (each once while it lasts).
  #toldPressed = new Set<string>();
  #pressed = false;
  #lastStop: number | null = null;
  #stopping = new Set<string>();

  constructor(options: MemoryOptions) {
    this.#o = options;
    this.#fibers = new Fibers("memory", options.clock);
  }

  /// Looks every WATCH_MS (PRESSED_MS under pressure) until closed.
  start(): void {
    const next = (ms: number) =>
      this.#fibers.after(ms, async () => {
        let pressure: Pressure | null = null;
        try {
          pressure = await this.look();
        } finally {
          next(pressure === "high" || pressure === "critical" ? PRESSED_MS : WATCH_MS);
        }
      });
    next(WATCH_MS);
  }

  close(): Promise<void> {
    return this.#fibers.close();
  }

  /// One look: what the system says of its memory, the units, who is told, what is stopped.
  async look(): Promise<Pressure | null> {
    const pressure = await this.#o.pressure().catch(() => null);
    const pressed = pressure === "high" || pressure === "critical";
    const table = await this.#o.table(pressed).catch(() => null);
    if (table === null) return pressure;
    const units = unitsOf(table, this.#o.jobs(), this.#o.agents(), this.#o.self).sort((a, b) => b.bytes - a.bytes);
    await this.#whose(units);
    const present = new Set(units.map((u) => u.key));
    for (const key of this.#told.keys()) if (!present.has(key)) this.#told.delete(key);

    const limit = limitOf(this.#o.totalBytes());
    for (const u of units) {
      const last = this.#told.get(u.key);
      if (u.bytes <= limit || (last !== undefined && u.bytes < last * 2)) continue;
      this.#told.set(u.key, u.bytes);
      this.#tell(u, `Your ${u.label} on this station uses ${gib(u.bytes)} of memory, more than an eighth of the machine's ${gib(this.#o.totalBytes())}. The station does not stop it for that: only when the machine is about to run out of memory is the largest of what the agents run here stopped.`);
    }

    if (!pressed) {
      this.#pressed = false;
      this.#toldPressed.clear();
      return pressure;
    }
    if (!this.#pressed) log.warn("memory", "the memory is under pressure", { pressure, largest: units.slice(0, TOLD_PRESSED).map((u) => [u.label, u.bytes]) });
    this.#pressed = true;
    for (const u of units.slice(0, TOLD_PRESSED)) {
      if (u.bytes < TOLD_MIN || this.#toldPressed.has(u.key) || this.#stopping.has(u.key)) continue;
      this.#toldPressed.add(u.key);
      this.#tell(u, `This station's memory is under pressure, and your ${u.label} uses ${gib(u.bytes)}, among the most of what the agents run here. New station tasks wait until it eases; if the machine is about to run out of memory, the largest is stopped.`);
    }
    const now = this.#fibers.now();
    if (pressure === "critical" && (this.#lastStop === null || now - this.#lastStop >= SETTLE_MS)) {
      const largest = units.find((u) => u.bytes >= TOLD_MIN && !this.#stopping.has(u.key));
      if (largest) {
        this.#lastStop = now;
        await this.#stop(largest);
      }
    }
    return pressure;
  }

  /// The sessions of commands their runtime does not say (a runtime shared by sessions): the one whose directory each
  /// command runs in.
  async #whose(units: Unit[]): Promise<void> {
    const unknown = units.filter((u) => u.session === null && u.job === null);
    if (unknown.length === 0) return;
    const cwds = await this.#o.cwds(unknown.map((u) => u.pids[0]!)).catch(() => new Map<number, string>());
    for (const u of unknown) {
      const dir = cwds.get(u.pids[0]!);
      if (dir !== undefined) u.session = this.#o.sessionAt(dir);
    }
  }

  #tell(u: Unit, text: string): void {
    try {
      this.#o.tell(u, text);
    } catch (error) {
      log.warn("memory", "not told", { unit: u.key, error: (error as Error).message });
    }
  }

  async #stop(u: Unit): Promise<void> {
    log.warn("memory", "the memory is about to run out: stopping the largest", { unit: u.key, label: u.label, bytes: u.bytes, session: u.session });
    this.#stopping.add(u.key);
    this.#tell(u, `This station was about to run out of memory, so it stopped your ${u.label} (${gib(u.bytes)}, the largest of what the agents run here) to keep the machine up.`);
    try {
      if (u.job !== null) {
        await this.#o.stopJob(u.job);
        return;
      }
      for (const pid of u.pids) this.#o.signal(pid, "SIGTERM");
      await this.#fibers.sleep(STOP_GRACE_MS);
      for (const pid of u.pids) this.#o.signal(pid, "SIGKILL");
    } catch (error) {
      log.warn("memory", "not stopped", { unit: u.key, error: (error as Error).message });
    } finally {
      this.#stopping.delete(u.key);
    }
  }
}

/// The jobs running now, as the watches see them (the resources' too, resources/watch.ts).
export function watchedJobs(store: Store): WatchedJob[] {
  return store.jobsRunning().flatMap((j) => (j.pgid !== null ? [{ id: j.id, session: j.sessionKey, pgid: j.pgid, label: named(j) }] : []));
}

/// The session of `sessions` whose directory (its workspace, or where it runs) holds `dir`, the deepest; null for none.
function sessionIn(sessions: { key: string; workspace: string; cwd: string | null }[], dir: string): string | null {
  let best: { key: string; length: number } | null = null;
  for (const s of sessions) {
    for (const root of [s.workspace, s.cwd]) {
      if (!root || !(dir === root || dir.startsWith(root.endsWith("/") ? root : `${root}/`))) continue;
      if (best === null || root.length > best.length) best = { key: s.key, length: root.length };
    }
  }
  return best?.key ?? null;
}

/// Which session each runner id is (a runner is a session's, its id made of the session's key, or a profile's, shared
/// by its sessions): the sessions shown asked each time; every session ever only as a runner none of them names comes
/// (an archived session's left on, a profile's), and what that found kept.
export function runnerSessions(store: Store): (ids: string[]) => Map<string, string> {
  let all: Map<string, string> | null = null;
  const unnamed = new Set<string>();
  const of = (sessions: { key: string }[]) => {
    const whose = new Map<string, string>();
    for (const s of sessions) for (const kind of RUNTIME_KINDS) whose.set(runnerId(kind, s.key), s.key);
    return whose;
  };
  return (ids) => {
    const whose = of(store.liveSessions());
    const rest = ids.filter((id) => !whose.has(id));
    if (rest.some((id) => !unnamed.has(id) && !all?.has(id))) {
      all = of(store.listSessions());
      for (const id of rest) if (!all.has(id)) unnamed.add(id);
    }
    for (const id of rest) {
      const key = all?.get(id);
      if (key !== undefined) whose.set(id, key);
    }
    return whose;
  };
}

/// The runners alive (<data>/run/runners), each with its session (`whose`: runnerSessions).
export function runnersWithSessions(data: string, whose: (ids: string[]) => Map<string, string>): (RunnerInfo & { session: string | null })[] {
  const runners = existingRunners(data);
  const named = whose(runners.map((r) => r.id));
  return runners.map((r) => ({ ...r, session: named.get(r.id) ?? null }));
}

/// The watch as the station runs it: over its jobs (`jobs`' store) and the commands of its runtimes (the runners of
/// before and now, <data>/run/runners), on this machine's memory.
export function liveMemory(o: { data: string; store: Store; jobs: Jobs; notify: (session: string, text: string) => void; clock?: Clock.Clock }): MemoryWatch {
  const { store } = o;
  const whose = runnerSessions(store);
  return new MemoryWatch({
    clock: o.clock,
    pressure: () => platform.memoryPressure(),
    table: (exact) => platform.processTable(exact),
    totalBytes: () => totalmem(),
    cwds: (pids) => platform.cwds(pids),
    jobs: () => watchedJobs(store),
    agents: () => runnersWithSessions(o.data, whose).map((r) => ({ pid: r.pid, session: r.session })),
    // Among the sessions shown first; every session ever only for a directory none of them has (an archived one's).
    sessionAt: (dir) => sessionIn(store.liveSessions(), dir) ?? sessionIn(store.listSessions(), dir),
    tell: (unit, text) => {
      const job = unit.job !== null ? store.getJob(unit.job) : null;
      // Another station's task: its notices, which go back to the session that asked for it (jobs/remote.ts).
      if (job !== null && job.sessionKey.startsWith("remote:")) store.addJobNotice(job.id, text);
      else if (unit.session !== null) o.notify(unit.session, text);
    },
    stopJob: async (id) => void (await o.jobs.stop(id)),
    signal: (pid, signal) => {
      try {
        process.kill(pid, signal);
      } catch {}
    },
    self: process.pid,
  });
}
