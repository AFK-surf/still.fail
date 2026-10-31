// Where the core's time goes, by what took it: the parts of making a view counted as they run, so a page that waited
// says what of its wait went where (store.ts `chat.open`, docs/telemetry.md). A count only: nothing reads it to decide.

/// Milliseconds spent on each part since the core started.
export const spent: Record<string, number> = {};

let clock: () => number = () => 0;

/// The clock the parts are timed by (the host's monotonic one), set as the core starts.
export function spentClock(now: () => number): void {
  clock = now;
}

/// `f`, its time counted as `part`'s (a part inside another is counted in both).
export function timed<T>(part: string, f: () => T): T {
  const from = clock();
  try {
    return f();
  } finally {
    spent[part] = (spent[part] ?? 0) + clock() - from;
  }
}

/// What was spent on each part since `then` (a copy of `spent` taken before), the parts that took any.
export function spentSince(then: Record<string, number>): [string, number][] {
  return Object.entries(spent).flatMap(([part, ms]) => {
    const d = ms - (then[part] ?? 0);
    return d >= 0.5 ? [[part, d] as [string, number]] : [];
  });
}
