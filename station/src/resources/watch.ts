// What of this machine still.fail uses (a station's 进程), as Activity Monitor says it: each look, every process's CPU
// time, memory footprint and bytes read from and written to disk (macOS counts them, native/mesh/src/usage.rs) and the
// bytes it took in and sent out over the network so far (nettop: what Activity Monitor's Network tab says), what each
// used since the last look put to whose it is:
// - a chat's: its agent's runner and all under it, its jobs' groups and all under them, and what runs in its directory
//   on its own (a script its agent left running with nohup, under launchd now: its arguments name the directory);
// - the agents': a runner no one session has (a profile's, codex) and all under it;
// - the app's: the desktop app (its bundle's id fail.still.desktop…) and all under it;
// - the station's: this process, its launcher, and what else is under it.
// The rest of the machine is no one's here and not read. A process that began since the last look counts whole; one
// that ended meanwhile loses what it used after the last look (a command of a few seconds may not show at all).
// Looked at only while a page asks (within WANTED_MS) or follows (`follow`: told each look), every LOOK_MS; nothing
// read otherwise. Kept: the last look by
// process and the totals of the last HISTORY_MS. A chat's process (not its agent's own) can be ended from the page.
import { basename } from "node:path";
import type { Clock } from "effect";
import { Fibers } from "../ops/fibers.ts";
import type { ProcessInfo } from "../platform/index.ts";

export const LOOK_MS = 5000;
/// A page asked this recently: looked at every LOOK_MS.
export const WANTED_MS = 30_000;
export const HISTORY_MS = 10 * 60_000;
/// Woken, how long after the first look (what the next is counted from) the second is, for figures at once.
export const FIRST_MS = 1000;

export type Whose = { key: string; kind: "chat" | "agents" | "app" | "station"; session: string | null };
/// What a process used now: CPU (100 a whole core), memory (bytes), bytes in and out a second, bytes read and written
/// a second.
export type Use = { cpu: number; memory: number; netIn: number; netOut: number; diskRead: number; diskWrite: number };
/// `endable`: a chat's, not its agent's own (its runner, the runtime it runs): one the page may end.
export type Process = Use & { pid: number; name: string; endable: boolean };
export type Group = Whose & Use & { processes: Process[] };
export type Point = Use & { at: number };
/// `net`: whether the network was read (its figures 0 else).
/// `disk`: whether what they read and wrote was (a mesh.node from before has none).
export type Snapshot = { at: number | null; everyMs: number; counted: boolean; net: boolean; disk: boolean; total: Use; groups: Group[]; history: Point[] };

export type Runner = { runner: number; pid: number; session: string | null };
export type Job = { session: string; pgid: number };
/// A chat's directory: what names it in its arguments is the chat's.
export type Place = { dir: string; session: string };
/// What a process has used so far (native/mesh/src/usage.rs).
export type Usage = { cpuNs: number; footprint: number; diskRead?: number | undefined; diskWritten?: number | undefined };
/// What a process has taken in and sent out over the network so far, in bytes.
export type Traffic = { in: number; out: number };

export type ResourceOptions = {
  clock?: Clock.Clock;
  table(): Promise<ProcessInfo[] | null>;
  /// Each process's arguments (pid: its command line), for what is no one's otherwise.
  args?(): Promise<Map<number, string> | null>;
  /// The chats' directories.
  places?(): Place[];
  /// Each pid's usage so far, null where not read.
  usage(pids: number[]): (Usage | null)[];
  /// Each pid's traffic so far (those with none left out); null: not read.
  traffic?(): Promise<Map<number, Traffic> | null>;
  /// The agents' runners (their files, read off the station's thread).
  runners(): Promise<Runner[]>;
  jobs(): Job[];
  /// Whether the process of this executable is the desktop app's.
  isApp(command: string): boolean;
  /// The station's own processes: itself, its launcher.
  self: number[];
};

/// Each process's whose: the jobs' groups first, then the runners, the app, the station, each with all under it; then
/// what is left that names a chat's directory.
export function whoseOf(table: readonly ProcessInfo[], o: Pick<ResourceOptions, "jobs" | "isApp" | "self">, runners: readonly Runner[], args?: Map<number, string> | null, places: readonly Place[] = []): Map<number, Whose> {
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
  for (const r of runners) give([r.runner, r.pid], r.session !== null ? chat(r.session) : { key: "agents", kind: "agents", session: null });
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

/// The agents' own processes: each runner and the runtime it runs (ending one is stopping the agent, not this page's).
const agentsOwn = (runners: readonly Runner[]) => new Set(runners.flatMap((r) => [r.runner, r.pid]));

/// A program as people know it: its executable's name.
const programOf = (command: string) => basename(command) || "?";
const zero = (): Use => ({ cpu: 0, memory: 0, netIn: 0, netOut: 0, diskRead: 0, diskWrite: 0 });
const add = (to: Use, u: Use) => {
  to.cpu += u.cpu;
  to.memory += u.memory;
  to.netIn += u.netIn;
  to.netOut += u.netOut;
  to.diskRead += u.diskRead;
  to.diskWrite += u.diskWrite;
};

/// Why a process was not ended: gone (or another now), or not one the page may end.
export class NotEndable extends Error {}

/// How long after SIGTERM one still there (the same) is sent SIGKILL.
export const KILL_AFTER_MS = 5000;

export class ResourceWatch {
  readonly #o: ResourceOptions;
  readonly #fibers: Fibers;
  /// Each process's usage at the last look, by pid and executable (a pid taken again is another process).
  #last = new Map<number, Usage & Traffic & { command: string }>();
  #lastAt: number | null = null;
  /// Every pid of the last look's table (whosever), with its executable.
  #seen = new Map<number, string>();
  #now: { at: number; groups: Group[]; total: Use } | null = null;
  #history: Point[] = [];
  #wanted = Number.NEGATIVE_INFINITY;
  /// Those following: told after each look, and looked at for while any is.
  readonly #followers = new Set<() => void>();
  /// Whether looks are going (a page asked lately).
  #going = false;
  /// Whether anything was read: none, not macOS.
  #counted = false;
  /// Whether the network was read at the last look.
  #net = false;
  /// Whether disk reads and writes were.
  #disk = false;

  constructor(options: ResourceOptions) {
    this.#o = options;
    this.#fibers = new Fibers("resources", options.clock);
  }

  async close(): Promise<void> {
    await this.#fibers.close();
  }

  /// A page asks: looked at every LOOK_MS for a while. Woken, looked at now and again FIRST_MS later, for what was used
  /// meanwhile, before it answers.
  async want(): Promise<void> {
    this.#wanted = this.#fibers.now();
    if (this.#going) return;
    this.#going = true;
    if (!this.#fresh()) {
      await this.look();
      await this.#fibers.sleep(FIRST_MS);
    }
    await this.look();
    const next = () =>
      this.#fibers.after(LOOK_MS, async () => {
        try {
          await this.look();
        } finally {
          for (const told of this.#followers) told();
          if (this.#followers.size > 0 || this.#fibers.now() - this.#wanted < WANTED_MS) next();
          else this.#going = false;
        }
      });
    next();
  }

  /// Followed (a page's stream, GET /resources as events): `told` after each look from the first on, until the
  /// returned stop. Looks go on while any follows.
  follow(told: () => void): () => void {
    this.#followers.add(told);
    void this.want().then(() => this.#followers.has(told) && told());
    return () => void this.#followers.delete(told);
  }

  /// Whether the last look is recent enough to count from: else what was used since is a long while's average.
  #fresh(): boolean {
    return this.#lastAt !== null && this.#fibers.now() - this.#lastAt <= 3 * LOOK_MS;
  }

  /// One look: the table, whose each process is, what each used since the last (none after a long while: it is only
  /// counted from).
  async look(): Promise<void> {
    const fresh = this.#fresh();
    const table = await this.#o.table().catch(() => null);
    if (table === null) return;
    const at = this.#fibers.now();
    const args = this.#o.args ? await this.#o.args().catch(() => null) : null;
    const runners = await this.#o.runners();
    const whose = whoseOf(table, this.#o, runners, args, this.#o.places?.() ?? []);
    const mine = table.filter((p) => whose.has(p.pid));
    const agent = agentsOwn(runners);
    const used = this.#o.usage(mine.map((p) => p.pid));
    const traffic = this.#o.traffic ? await this.#o.traffic().catch(() => null) : null;
    this.#net = traffic !== null;
    const since = fresh ? this.#lastAt : null;
    const seconds = since === null ? 0 : (at - since) / 1000;
    const groups = new Map<string, Group>();
    const last = new Map<number, Usage & Traffic & { command: string }>();
    mine.forEach((p, i) => {
      const read = used[i];
      if (!read) return;
      // Not in nettop's list this time (no socket open now, or not read): what it had, its counts only growing.
      const had = this.#last.get(p.pid);
      const u = { ...read, ...(traffic?.get(p.pid) ?? (had?.command === p.command ? { in: had.in, out: had.out } : { in: 0, out: 0 })) };
      this.#counted = true;
      if (read.diskRead !== undefined) this.#disk = true;
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
        netIn: Math.max(0, (u.in - (was?.in ?? 0)) / seconds),
        netOut: Math.max(0, (u.out - (was?.out ?? 0)) / seconds),
        diskRead: Math.max(0, ((u.diskRead ?? 0) - (was?.diskRead ?? 0)) / seconds),
        diskWrite: Math.max(0, ((u.diskWritten ?? 0) - (was?.diskWritten ?? 0)) / seconds),
      };
      const g = groups.get(w.key) ?? { ...w, ...zero(), processes: [] };
      add(g, use);
      g.processes.push({ pid: p.pid, name: programOf(p.command), ...use, endable: w.kind === "chat" && !agent.has(p.pid) });
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
  }

  /// Ends a chat's process (`session`'s, not its agent's own), as it is now: SIGTERM, then SIGKILL if it is still there
  /// KILL_AFTER_MS later. `kill`: the signal sent (process.kill, a test's).
  async end(pid: number, session: string, kill: (pid: number, signal: NodeJS.Signals) => void = process.kill): Promise<{ name: string }> {
    const table = await this.#o.table();
    const now = table?.find((p) => p.pid === pid);
    if (!table || !now) throw new NotEndable("gone");
    const args = this.#o.args ? await this.#o.args().catch(() => null) : null;
    const runners = await this.#o.runners();
    const w = whoseOf(table, this.#o, runners, args, this.#o.places?.() ?? []).get(pid);
    if (w?.kind !== "chat" || w.session !== session || agentsOwn(runners).has(pid)) throw new NotEndable("not a chat's");
    kill(pid, "SIGTERM");
    this.#fibers.after(KILL_AFTER_MS, async () => {
      const still = (await this.#o.table().catch(() => null))?.find((p) => p.pid === pid);
      if (still?.command === now.command) {
        try {
          kill(pid, "SIGKILL");
        } catch {}
      }
    });
    return { name: programOf(now.command) };
  }

  /// The last look and the history, the oldest first.
  snapshot(): Snapshot {
    return {
      at: this.#now?.at ?? null,
      everyMs: LOOK_MS,
      counted: this.#counted,
      net: this.#net,
      disk: this.#disk,
      total: this.#now?.total ?? zero(),
      groups: this.#now?.groups ?? [],
      history: [...this.#history],
    };
  }
}
