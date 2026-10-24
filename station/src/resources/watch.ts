// What of this machine still.fail uses (the resources page), as Activity Monitor says it: each look, every process's
// CPU time, memory footprint, wakeups and energy so far (macOS counts them, native/mesh/src/usage.rs), what each used
// since the last look put to whose it is:
// - a chat's: its agent's runner and all under it, its jobs' groups and all under them, and what runs in its directory
//   on its own (a script its agent left running with nohup, under launchd now: its arguments name the directory);
// - the agents': a runner no one session has (a profile's, codex) and all under it;
// - the app's: the desktop app (its bundle's id fail.still.desktop…) and all under it;
// - the station's: this process, its launcher, and what else is under it.
// The rest of the machine is no one's here and not read. A process that began since the last look counts whole; one
// that ended meanwhile loses what it used after the last look (a command of a few seconds may not show at all).
// Looked at every LOOK_MS while a page asks (within WANTED_MS), else every IDLE_MS. Kept: the last look by process,
// the totals of the last HISTORY_MS, and each hour's joules by whose for HOURS hours, in a file so a restart keeps them.
import { readFileSync } from "node:fs";
import { mkdir, rename, writeFile } from "node:fs/promises";
import { basename, dirname, join } from "node:path";
import type { Clock } from "effect";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import type { ProcessInfo } from "../platform/index.ts";

export const LOOK_MS = 5000;
export const IDLE_MS = 30_000;
/// A page asked this recently: looked at every LOOK_MS.
export const WANTED_MS = 30_000;
export const HISTORY_MS = 10 * 60_000;
export const HOURS = 24;
const HOUR_MS = 3_600_000;
/// The hours written out at most this often (and as the station stops).
const SAVE_MS = 60_000;

export type Whose = { key: string; kind: "chat" | "agents" | "app" | "station"; session: string | null };
/// What a process used now: CPU (100 a whole core), memory (bytes), watts, wakeups a second.
export type Use = { cpu: number; memory: number; watts: number; wakeups: number };
export type Process = Use & { pid: number; name: string };
export type Group = Whose & Use & { processes: Process[] };
export type Point = Use & { at: number };
export type Hour = { at: number; joules: Record<string, number> };
export type Snapshot = { at: number | null; everyMs: number; counted: boolean; total: Use; groups: Group[]; history: Point[]; hours: Hour[] };

export type Runner = { runner: number; pid: number; session: string | null };
export type Job = { session: string; pgid: number };
/// A chat's directory: what names it in its arguments is the chat's.
export type Place = { dir: string; session: string };
/// What a process has used so far (native/mesh/src/usage.rs).
export type Usage = { cpuNs: number; footprint: number; wakeups: number; energyNj: number };

export type ResourceOptions = {
  clock?: Clock.Clock;
  table(): Promise<ProcessInfo[] | null>;
  /// Each process's arguments (pid: its command line), for what is no one's otherwise.
  args?(): Promise<Map<number, string> | null>;
  /// The chats' directories.
  places?(): Place[];
  /// Each pid's usage so far, null where not read.
  usage(pids: number[]): (Usage | null)[];
  runners(): Runner[];
  jobs(): Job[];
  /// Whether the process of this executable is the desktop app's.
  isApp(command: string): boolean;
  /// The station's own processes: itself, its launcher.
  self: number[];
  /// Where the hours are kept; none: not kept.
  file?: string;
};

/// Each process's whose: the jobs' groups first, then the runners, the app, the station, each with all under it; then
/// what is left that names a chat's directory.
export function whoseOf(table: readonly ProcessInfo[], o: Pick<ResourceOptions, "runners" | "jobs" | "isApp" | "self">, args?: Map<number, string> | null, places: readonly Place[] = []): Map<number, Whose> {
  const children = new Map<number, number[]>();
  const byPid = new Map<number, ProcessInfo>();
  for (const p of table) {
    byPid.set(p.pid, p);
    if (p.pid !== p.ppid) children.set(p.ppid, [...(children.get(p.ppid) ?? []), p.pid]);
  }
  const out = new Map<number, Whose>();
  const give = (roots: number[], whose: Whose) => {
    for (const queue = [...roots]; queue.length > 0; ) {
      const pid = queue.pop()!;
      if (out.has(pid) || !byPid.has(pid)) continue;
      out.set(pid, whose);
      queue.push(...(children.get(pid) ?? []));
    }
  };
  const chat = (session: string): Whose => ({ key: `chat:${session}`, kind: "chat", session });
  for (const j of o.jobs()) give(table.filter((p) => p.pgid === j.pgid).map((p) => p.pid), chat(j.session));
  for (const r of o.runners()) give([r.runner, r.pid], r.session !== null ? chat(r.session) : { key: "agents", kind: "agents", session: null });
  // The app's main process: the first of its bundle's from the top (its helpers are under it).
  const app = table.filter((p) => o.isApp(p.command) && !(byPid.has(p.ppid) && o.isApp(byPid.get(p.ppid)!.command)));
  give(app.map((p) => p.pid), { key: "app", kind: "app", session: null });
  give(o.self, { key: "station", kind: "station", session: null });
  // What is left that names a chat's directory (the longest that it names), from the top: a script and all it runs.
  if (args && places.length > 0) {
    const dirs = places.map((p) => ({ ...p, dir: p.dir.endsWith("/") ? p.dir : `${p.dir}/` })).sort((a, b) => b.dir.length - a.dir.length);
    for (const p of table) {
      if (out.has(p.pid) || out.has(p.ppid)) continue;
      const line = args.get(p.pid);
      const place = line === undefined ? undefined : dirs.find((d) => line.includes(d.dir));
      if (place) give([p.pid], chat(place.session));
    }
  }
  return out;
}

/// A program as people know it: its executable's name.
const programOf = (command: string) => basename(command) || "?";
const zero = (): Use => ({ cpu: 0, memory: 0, watts: 0, wakeups: 0 });
const add = (to: Use, u: Use) => {
  to.cpu += u.cpu;
  to.memory += u.memory;
  to.watts += u.watts;
  to.wakeups += u.wakeups;
};

export class ResourceWatch {
  readonly #o: ResourceOptions;
  readonly #fibers: Fibers;
  /// Each process's usage at the last look, by pid and executable (a pid taken again is another process).
  #last = new Map<number, Usage & { command: string }>();
  #lastAt: number | null = null;
  /// Every pid of the last look's table (whosever), with its executable.
  #seen = new Map<number, string>();
  #now: { at: number; groups: Group[]; total: Use } | null = null;
  #history: Point[] = [];
  #hours = new Map<number, Record<string, number>>();
  #wanted = Number.NEGATIVE_INFINITY;
  #savedAt = 0;
  /// Whether anything was read: none, not macOS.
  #counted = false;

  constructor(options: ResourceOptions) {
    this.#o = options;
    this.#fibers = new Fibers("resources", options.clock);
    if (options.file) this.#load(options.file);
  }

  /// Looks now, then every LOOK_MS while asked, else IDLE_MS, until closed.
  start(): void {
    const next = (ms: number) =>
      this.#fibers.after(ms, async () => {
        try {
          await this.look();
        } finally {
          next(this.#asked() ? LOOK_MS : IDLE_MS);
        }
      });
    next(0);
  }

  async close(): Promise<void> {
    await this.#fibers.close();
    await this.#save();
  }

  /// A page asks: looked at often for a while. Looked at now if the last look is older than a look's time.
  async want(): Promise<void> {
    const now = this.#fibers.now();
    const quiet = !this.#asked();
    this.#wanted = now;
    if (quiet && (this.#lastAt === null || now - this.#lastAt >= LOOK_MS)) await this.look();
  }

  #asked(): boolean {
    return this.#fibers.now() - this.#wanted < WANTED_MS;
  }

  /// One look: the table, whose each process is, what each used since the last.
  async look(): Promise<void> {
    const table = await this.#o.table().catch(() => null);
    if (table === null) return;
    const at = this.#fibers.now();
    const args = this.#o.args ? await this.#o.args().catch(() => null) : null;
    const whose = whoseOf(table, this.#o, args, this.#o.places?.() ?? []);
    const mine = table.filter((p) => whose.has(p.pid));
    const used = this.#o.usage(mine.map((p) => p.pid));
    const since = this.#lastAt;
    const seconds = since === null ? 0 : (at - since) / 1000;
    const groups = new Map<string, Group>();
    const last = new Map<number, Usage & { command: string }>();
    mine.forEach((p, i) => {
      const u = used[i];
      if (!u) return;
      this.#counted = true;
      last.set(p.pid, { ...u, command: p.command });
      if (since === null || seconds <= 0) return;
      const w = whose.get(p.pid)!;
      const before = this.#last.get(p.pid);
      const same = before !== undefined && before.command === p.command && before.cpuNs <= u.cpuNs;
      // There before but no one's then (its chat begun since): from the next look on.
      if (!same && this.#seen.get(p.pid) === p.command) return;
      // Begun since the last look (or its pid taken again): all it used is since then.
      const was = same ? before : null;
      const use: Use = {
        cpu: Math.max(0, (u.cpuNs - (was?.cpuNs ?? 0)) / 1e9 / seconds) * 100,
        memory: u.footprint,
        watts: Math.max(0, (u.energyNj - (was?.energyNj ?? 0)) / 1e9 / seconds),
        wakeups: Math.max(0, (u.wakeups - (was?.wakeups ?? 0)) / seconds),
      };
      const g = groups.get(w.key) ?? { ...w, ...zero(), processes: [] };
      add(g, use);
      g.processes.push({ pid: p.pid, name: programOf(p.command), ...use });
      groups.set(w.key, g);
    });
    this.#last = last;
    this.#lastAt = at;
    this.#seen = new Map(table.map((p) => [p.pid, p.command]));
    if (since === null) return;
    const total = zero();
    const list = [...groups.values()].map((g) => ({ ...g, processes: g.processes.sort((a, b) => b.cpu - a.cpu) })).sort((a, b) => b.cpu - a.cpu);
    for (const g of list) add(total, g);
    this.#now = { at, groups: list, total };
    this.#history.push({ at, ...total });
    this.#history = this.#history.filter((p) => p.at > at - HISTORY_MS);
    const hour = Math.floor(at / HOUR_MS) * HOUR_MS;
    const joules = this.#hours.get(hour) ?? {};
    for (const g of list) joules[g.key] = (joules[g.key] ?? 0) + g.watts * seconds;
    this.#hours.set(hour, joules);
    for (const h of this.#hours.keys()) if (h <= hour - HOURS * HOUR_MS) this.#hours.delete(h);
    if (at - this.#savedAt >= SAVE_MS) {
      this.#savedAt = at;
      await this.#save();
    }
  }

  /// The last look, the history and the hours, the oldest first.
  snapshot(): Snapshot {
    return {
      at: this.#now?.at ?? null,
      everyMs: LOOK_MS,
      counted: this.#counted,
      total: this.#now?.total ?? zero(),
      groups: this.#now?.groups ?? [],
      history: [...this.#history],
      hours: [...this.#hours.entries()].sort(([a], [b]) => a - b).map(([at, joules]) => ({ at, joules })),
    };
  }

  #load(file: string): void {
    try {
      const raw = JSON.parse(readFileSync(file, "utf8")) as { hours?: Hour[] };
      for (const h of raw.hours ?? []) if (typeof h.at === "number" && h.joules && typeof h.joules === "object") this.#hours.set(h.at, h.joules);
    } catch {}
  }

  async #save(): Promise<void> {
    const file = this.#o.file;
    if (!file) return;
    try {
      await mkdir(dirname(file), { recursive: true });
      const part = `${file}.part`;
      await writeFile(part, JSON.stringify({ hours: this.snapshot().hours }));
      await rename(part, file);
    } catch (error) {
      log.warn("resources", "hours not kept", { error: (error as Error).message });
    }
  }
}

/// Where the hours are kept.
export const hoursFile = (data: string) => join(data, "resources", "hours.json");
