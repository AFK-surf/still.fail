// The station's queue for other stations' tasks (station_task, jobs/remote.ts; docs/station-scheduling.md): a task
// that arrives while the machine is busy waits here, so agents that each looked at the load and saw room do not all
// start at once. Nothing is estimated beforehand (a build takes more or less by its caches): what is measured decides.
//
// - With no task of the queue running, the first that waits starts, however busy the machine is: one always goes on.
// - Another starts only once the last one started has had RAMP_MS to get going, and the CPUs were busy less than
//   BUSY_MAX over the last BUSY_SPAN_MS: tasks come in one by one while there is room.
// - None starts while the system says its memory is under pressure (high or critical).
// - A task that uses the screen (windows, a simulator, screenshots) starts only while no other such task runs.
// - Which one: of the sessions that have tasks waiting, the one whose task last started longest ago (one never started
//   first), its oldest task. A session that asks for ten does not keep the others behind them.
//
// A task started with others running is told how many CPUs are free (STILLFAIL_CPUS, and the build tools' own
// variables when its environment has none of them), so a build does not take every core for itself.
import type { Ticks } from "../read/host.ts";

/// What the system says of its memory: under pressure (high), or about to run out (critical); null where it cannot be
/// read.
export type Pressure = "normal" | "high" | "critical";

/// How long the last task started is left to get going before the CPUs are looked at for another.
export const RAMP_MS = 30_000;
/// The CPUs busy less than this over BUSY_SPAN_MS: there is room for another task.
export const BUSY_MAX = 0.8;
/// Over how long the CPUs are looked at, and how often.
export const BUSY_SPAN_MS = 20_000;
export const LOOK_MS = 5000;

export type Waiting = { id: string; session: string; screen: boolean; queuedAt: number };
export type Started = { id: string; screen: boolean };

/// Why a task waits, for its agent (station_task's answer).
export type Why = "memory" | "busy" | "screen";

/// The CPUs' ticks noted at each look, for how busy they have been over the last BUSY_SPAN_MS.
export class Busy {
  private seen: { at: number; ticks: Ticks }[] = [];

  /// The ticks now; those older than BUSY_SPAN_MS go (after a while unwatched, none are left to compare with).
  note(at: number, ticks: Ticks | null): void {
    this.seen = this.seen.filter((s) => at - s.at <= BUSY_SPAN_MS);
    if (ticks !== null) this.seen.push({ at, ticks });
  }

  /// The share (0–1) since the oldest ticks kept; null before they span half of BUSY_SPAN_MS.
  share(): number | null {
    const first = this.seen[0];
    const last = this.seen.at(-1);
    if (first === undefined || last === undefined || last.at - first.at < BUSY_SPAN_MS / 2) return null;
    const [b0, t0] = first.ticks;
    const [b1, t1] = last.ticks;
    if (t1 <= t0) return null;
    return Math.min(Math.max((b1 - b0) / (t1 - t0), 0), 1);
  }
}

export type Room = { busy: number | null; pressure: Pressure | null };

/// The task to start now, if any, and else why the first waiting waits.
export function pick(
  waiting: readonly Waiting[],
  running: readonly Started[],
  room: Room,
  now: number,
  lastStart: number | null,
  lastOf: (session: string) => number | null,
): { start: Waiting } | { wait: Why } | null {
  if (waiting.length === 0) return null;
  if (room.pressure === "high" || room.pressure === "critical") return { wait: "memory" };
  const screenBusy = running.some((r) => r.screen);
  const able = waiting.filter((w) => !(w.screen && screenBusy));
  if (able.length === 0) return { wait: "screen" };
  if (running.length > 0) {
    if (lastStart !== null && now - lastStart < RAMP_MS) return { wait: "busy" };
    if (room.busy === null || room.busy >= BUSY_MAX) return { wait: "busy" };
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
