// The station's queue for other stations' tasks (station_task, jobs/remote.ts; docs/station-scheduling.md): a task
// that arrives while the machine is busy waits here, so agents that each looked at the load and saw room do not all
// start at once. Nothing is estimated beforehand (a build takes more or less by its caches): what is measured decides.
//
// - With no task of the queue running, the first that waits starts, however busy the machine is: one always goes on.
// - Another starts only once the CPUs, looked at since the last one started (while that one still runs: one that
//   ended has nothing more to show), were busy less than BUSY_MAX: tasks come in one by one while there is room.
//   (A flat 30 s after each start held a task of an idle machine back minutes when several sessions each had one
//   waiting, 2026-10-24: two a minute, the CPUs at 5%.)
// - None starts while the system says its memory is under pressure (high or critical).
// - A task that uses the screen (windows, a simulator, screenshots) throughout starts only while no other task has the
//   screen, and none of the commands that asked for it before it came waits for it.
// - Which one: of the sessions that have tasks waiting, the one whose task last started longest ago (one never started
//   first), its oldest task. A session that asks for ten does not keep the others behind them.
//
// The screen is one task's at a time; a task has it while it uses it: one prepared with `screen` for as long as it
// runs, any other while a command of its holds it (`stillfail-job screen <command>`: a claim, below). A task that
// takes pictures between builds and tests has it only for the pictures: the rest of it runs beside the others' (with
// whole tasks having it, one that had drawn its pictures in 40 s held it minutes more for its tests, the others with
// pictures to take waited 20 minutes and more in line, the CPUs a third busy, 2026-10-25).
//
// The screen is a machine's work's, done in minutes: a window put up for a person and left there (a virtual machine
// to try, a simulator to look at) is no claim on it (`stillfail-job show <command>`: it waits for the screen to be
// free, opens, and holds nothing; a Mac VM held the screen 23 hours as a claim, every task with pictures to take in
// line behind it, 2026-10-27). And while a person uses the screen (the machine's input not idle: someone at it, or
// working it through still.fail), it is theirs: nothing more is given it, so no window comes up under their hand; what
// holds it goes on.
//
// A task started with others running is told how many CPUs are free (STILLFAIL_CPUS, and the build tools' own
// variables when its environment has none of them), so a build does not take every core for itself.
import type { Ticks } from "../read/host.ts";

/// What the system says of its memory: under pressure (high), or about to run out (critical); null where it cannot be
/// read.
export type Pressure = "normal" | "high" | "critical";

/// The CPUs busy less than this over BUSY_SPAN_MS: there is room for another task.
export const BUSY_MAX = 0.8;
/// Over how long the CPUs are looked at, and how often.
export const BUSY_SPAN_MS = 20_000;
export const LOOK_MS = 5000;
/// How long, at least, the CPUs are looked at after a task starts before another may (two looks: its load shows).
export const RAMP_MS = 2 * LOOK_MS;

export type Waiting = { id: string; session: string; screen: boolean; queuedAt: number };
export type Started = { id: string; screen: boolean };

/// Why a task waits, for its agent (station_task's answer): the screen another task's, or a person's.
export type Why = "memory" | "busy" | "screen" | "person";
/// A CPU wait is either for a sample or for CPUs the sample found busy.
export type BusyCause = "sampling" | "cpu";

/// The machine's input idle less than this: a person is at it (or works it through still.fail).
export const PERSON_IDLE_MS = 60_000;

/// A command that has held the screen this long while another waits for it: its agent is told (once), the screen
/// being for work done in minutes, a window left up for a person `stillfail-job show`'s.
export const HELD_LONG_MS = 10 * 60_000;

/// The CPUs' ticks noted at each look, for how busy they have been over the last BUSY_SPAN_MS.
export class Busy {
  private seen: { at: number; ticks: Ticks }[] = [];

  /// The ticks now; those older than BUSY_SPAN_MS go (after a while unwatched, none are left to compare with).
  note(at: number, ticks: Ticks | null): void {
    this.seen = this.seen.filter((s) => at - s.at <= BUSY_SPAN_MS);
    if (ticks !== null) this.seen.push({ at, ticks });
  }

  /// The measured share (0–1), its span and its last look; null before they span half of BUSY_SPAN_MS.
  sample(since: number | null = null): { share: number; seconds: number; checkedAt: number } | null {
    const first = since === null ? this.seen[0] : this.seen.find((s) => s.at >= since);
    const last = this.seen.at(-1);
    if (first === undefined || last === undefined || last.at - first.at < BUSY_SPAN_MS / 2) return null;
    const [b0, t0] = first.ticks;
    const [b1, t1] = last.ticks;
    if (t1 <= t0) return null;
    return { share: Math.min(Math.max((b1 - b0) / (t1 - t0), 0), 1), seconds: (last.at - first.at) / 1000, checkedAt: last.at };
  }

  /// The share since the oldest ticks kept, or the oldest noted at `since` or after.
  share(since: number | null = null): number | null {
    return this.sample(since)?.share ?? null;
  }
}

export type Room = { busy: number | null; pressure: Pressure | null; person?: boolean };

/// A command's claim on the screen (`stillfail-job screen`): its job, the process that asked (the command's shell),
/// when it first asked (the store's clock, as a task's queuedAt), whether it has the screen now, and since when (the
/// store's clock; none for one that does not, or one an earlier station gave it: then when it asked).
export type Claim = { job: string; pid: number; at: number; held: boolean; since?: number };

/// What the claims say to the queue: whether one holds the screen, and when the first still waiting asked.
export type Claims = { held: boolean; asked: number | null };

export const claimsOf = (claims: readonly Claim[]): Claims => ({
  held: claims.some((c) => c.held),
  asked: claims.find((c) => !c.held)?.at ?? null,
});

/// The claims with the screen given out (`now`: since when): to the first waiting while no task has it and no person
/// uses it (`person`), and at once to a job's that has it already (`screenJobs`: those running that use it
/// throughout; or a command of its own holds it), so a command inside another, or inside a task that has the screen
/// throughout, does not wait for itself.
export function served(claims: readonly Claim[], screenJobs: ReadonlySet<string>, now: number, person = false): Claim[] {
  const having = new Set([...screenJobs, ...claims.filter((c) => c.held).map((c) => c.job)]);
  return claims.map((c) => {
    if (c.held || (having.size > 0 && !having.has(c.job)) || (person && !having.has(c.job))) return c;
    having.add(c.job);
    return { ...c, held: true, since: now };
  });
}

/// The claims that have held the screen HELD_LONG_MS or more while another waits for it (none while none waits).
export function overstaying(claims: readonly Claim[], now: number): Claim[] {
  if (!claims.some((c) => !c.held)) return [];
  return claims.filter((c) => c.held && now - (c.since ?? c.at) >= HELD_LONG_MS);
}

/// The task to start now, if any, and else why the first waiting waits.
export function pick(
  waiting: readonly Waiting[],
  running: readonly Started[],
  room: Room,
  now: number,
  lastStart: number | null,
  lastOf: (session: string) => number | null,
  claims: Claims = { held: false, asked: null },
): { start: Waiting } | { wait: Why; cause?: BusyCause } | null {
  if (waiting.length === 0) return null;
  if (room.pressure === "high" || room.pressure === "critical") return { wait: "memory" };
  // (the screen another task's, a person's, or asked for by a command before this task came)
  const screenBusy = running.some((r) => r.screen) || claims.held;
  const person = room.person === true;
  const able = waiting.filter((w) => !(w.screen && (screenBusy || person || (claims.asked !== null && claims.asked <= w.queuedAt))));
  if (able.length === 0) return { wait: !screenBusy && person ? "person" : "screen" };
  if (running.length > 0) {
    if (lastStart !== null && now - lastStart < RAMP_MS) return { wait: "busy", cause: "sampling" };
    if (room.busy === null) return { wait: "busy", cause: "sampling" };
    if (room.busy >= BUSY_MAX) return { wait: "busy", cause: "cpu" };
  }
  // The session whose task last started longest ago (never: first), its oldest task.
  const last = (w: Waiting) => lastOf(w.session) ?? -Infinity;
  const chosen = [...able].sort((a, b) => last(a) - last(b) || a.queuedAt - b.queuedAt)[0]!;
  return { start: chosen };
}

/// Where a waiting task is in line: 1 for the next.
export function place(waiting: readonly Waiting[], id: string, lastOf: (session: string) => number | null): number | null {
  const last = (w: Waiting) => lastOf(w.session) ?? -Infinity;
  const i = [...waiting].sort((a, b) => last(a) - last(b) || a.queuedAt - b.queuedAt).findIndex((w) => w.id === id);
  return i < 0 ? null : i + 1;
}

/// The variables a task started beside others is given: how many CPUs it may take, for itself (STILLFAIL_CPUS) and as
/// make, cargo and cmake read it, where its environment does not say already. None for one started alone.
export function cpusFor(env: NodeJS.ProcessEnv, cpus: number, busy: number | null, alone: boolean): Record<string, string> {
  if (alone || cpus <= 0) return {};
  const free = Math.max(1, Math.round((1 - (busy ?? 1)) * cpus));
  const out: Record<string, string> = { STILLFAIL_CPUS: String(free) };
  if (env.MAKEFLAGS === undefined) out.MAKEFLAGS = `-j${free}`;
  if (env.CARGO_BUILD_JOBS === undefined) out.CARGO_BUILD_JOBS = String(free);
  if (env.CMAKE_BUILD_PARALLEL_LEVEL === undefined) out.CMAKE_BUILD_PARALLEL_LEVEL = String(free);
  return out;
}
