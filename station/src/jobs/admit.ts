// The station's queue for other stations' tasks (station_task, jobs/remote.ts): a task
// that arrives while the machine's memory is under pressure, or the screen it needs is taken, waits here. Nothing is
// estimated beforehand (a build takes more or less by its caches): what is measured decides.
//
// - How busy the CPUs are holds no task back: busy CPUs make the tasks slower, not the machine unable to run them.
//   (They did, and wasted the machine: their busy share is 100% as soon as each core has something, however little
//   waits; the load average lags a minute, high while the cores sit idle after tasks end; a ramp after each start held
//   tasks of an idle machine back. 2026-10-24, 2026-11-09.) Nor is a task told how many CPUs to take: the same share
//   made that one (`MAKEFLAGS=-j1`) on a machine whose cores each had something, a build beside others on one core
//   of twelve; the system shares the cores among what runs (the user, 2026-11-10).
// - None starts while the system says its memory is under pressure (high or critical), but a small task while it is only
//   high: there is always a way to look at a machine short of running out (a small diagnostic waited with the rest
//   over 40 minutes, nothing else able to reach it, #4355).
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
// One explicitly small offscreen task may run beside busy builds. Its own slot is bounded to one task, it is told to
// use one CPU, and it waits only when memory is critical. This is for brief work such as drawing with a prebuilt renderer.

/// What the system says of its memory: under pressure (high), or about to run out (critical); null where it cannot be
/// read.
export type Pressure = "normal" | "high" | "critical";

/// How often the queue looks at the machine (its memory, a person at it) while a task waits.
export const LOOK_MS = 5000;

export type Waiting = { id: string; session: string; screen: boolean; queuedAt: number; small?: boolean };
export type Started = { id: string; screen: boolean; small?: boolean };

/// Why a task waits, for its agent (station_task's answer): the memory under pressure, the small tasks' slot taken, the
/// screen another task's, or a person's.
export type Why = "memory" | "small" | "screen" | "person";

/// The machine's input idle less than this: a person is at it (or works it through still.fail).
export const PERSON_IDLE_MS = 60_000;

/// A command that has held the screen this long while another waits for it: its agent is told (once), the screen
/// being for work done in minutes, a window left up for a person `stillfail-job show`'s.
export const HELD_LONG_MS = 10 * 60_000;

export type Room = { pressure: Pressure | null; person?: boolean };

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
  lastOf: (session: string) => number | null,
  claims: Claims = { held: false, asked: null },
): { start: Waiting } | { wait: Why } | null {
  if (waiting.length === 0) return null;
  if (room.pressure === "critical") return { wait: "memory" };
  const roomy = room.pressure !== "high";
  if (!roomy && !waiting.some((w) => w.small === true)) return { wait: "memory" };
  // (the screen another task's, a person's, or asked for by a command before this task came)
  const screenBusy = running.some((r) => r.screen) || claims.held;
  const person = room.person === true;
  const able = waiting.filter((w) => (roomy || w.small === true) && !(w.screen && (screenBusy || person || (claims.asked !== null && claims.asked <= w.queuedAt))));
  if (!roomy && able.length === 0) return { wait: "memory" };
  if (able.length === 0) return { wait: !screenBusy && person ? "person" : "screen" };
  // (one small task at a time beside the rest)
  const smallBusy = running.some((r) => r.small === true);
  const ready = able.filter((w) => w.small !== true || !smallBusy);
  if (ready.length === 0) return { wait: "small" };
  // The session whose task last started longest ago (never: first), its oldest task.
  const last = (w: Waiting) => lastOf(w.session) ?? -Infinity;
  const chosen = [...ready].sort((a, b) => last(a) - last(b) || a.queuedAt - b.queuedAt)[0]!;
  return { start: chosen };
}

/// Where a waiting task is in line: 1 for the next.
export function place(waiting: readonly Waiting[], id: string, lastOf: (session: string) => number | null): number | null {
  const last = (w: Waiting) => lastOf(w.session) ?? -Infinity;
  const i = [...waiting].sort((a, b) => last(a) - last(b) || a.queuedAt - b.queuedAt).findIndex((w) => w.id === id);
  return i < 0 ? null : i + 1;
}
