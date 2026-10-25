// What held the station's main thread, put down by who made it wait, for the line that says it was held (main.ts):
// its statements (store/timed.ts) and its synchronous calls of node:fs (ops/file-waits.ts).

/// A wait this long is put down with who made it (from the cache, a call takes microseconds; a statement of an index,
/// a millisecond or so).
export const WAITED_MS = 20;

/// The time waited since it was last asked: all of it and how many waits, and those of WAITED_MS or more by who made
/// them.
export type Waits = { ms: number; calls: number; by: Map<string, { ms: number; calls: number }> };

export const noWaits = (): Waits => ({ ms: 0, calls: 0, by: new Map() });

/// A wait of `ms` put down; `who` made it, asked only for one of WAITED_MS or more (it takes a stack).
export function waited(waits: Waits, ms: number, who: () => string): void {
  waits.ms += ms;
  waits.calls++;
  if (ms < WAITED_MS) return;
  const key = who();
  const was = waits.by.get(key) ?? { ms: 0, calls: 0 };
  waits.by.set(key, { ms: was.ms + ms, calls: was.calls + 1 });
}

/// The longest waits, as the log says them: `<who> <ms>ms×<waits>`, the longest first.
export function longestWaits(waits: Waits, most = 3): string {
  return [...waits.by]
    .sort((a, b) => b[1].ms - a[1].ms)
    .slice(0, most)
    .map(([key, w]) => `${key} ${Math.round(w.ms)}ms×${w.calls}`)
    .join("; ");
}

/// Who asked, as a stack names them, nearest first: the first functions past these wrappers and the store's own helpers
/// (`#one`, `#all`, …). Their names alone: in the bundled station a file and line say nothing.
export function askedBy(stack: string | undefined): string {
  const names: string[] = [];
  for (const line of (stack ?? "").split("\n").slice(1)) {
    const name = /^\s*at (?:async )?([^\s(]+) \(/.exec(line)?.[1];
    // (`time2`: `time` as the bundle names it.)
    if (name === undefined || /^time\d*$/.test(name) || name.includes("#") || name.includes("<anonymous>")) continue;
    names.push(name);
    if (names.length === 3) break;
  }
  return names.join(" < ");
}
