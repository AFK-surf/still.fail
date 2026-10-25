// The files as the station's main thread waits on them, timed. A synchronous call of node:fs holds every device and
// every agent until the disk answers: on a machine short of memory one existsSync took most of a second, and the few
// dozen an overview makes held the station 16 s (2026-10-25), with no query slow and its process doing next to no work.
// Every such call of the main thread's is timed; those of WAITED_MS or more are put down with who made them (a stack
// is taken only then), for the line that says the main thread was held (main.ts). Never the paths: they name people's
// files.
import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { performance } from "node:perf_hooks";
import { askedBy } from "../store/timed.ts";

/// A call that took this long waited on the disk (from the cache, one takes microseconds): put down with who made it.
export const WAITED_MS = 20;

/// What the main thread waited on files since it was last asked: all its synchronous calls' time and number, and those
/// of WAITED_MS or more by the call and who made it.
export type FileWaits = { ms: number; calls: number; by: Map<string, { ms: number; calls: number }> };

/// node:fs's synchronous calls timed, in this thread (for the modules' named imports too); `take` gives what was waited
/// since it was last called, `stop` puts the calls back as they were.
export function timeFiles(now: () => number = () => performance.now()): { take: () => FileWaits; stop: () => void } {
  let waits: FileWaits = { ms: 0, calls: 0, by: new Map() };
  const target = fs as unknown as Record<string, unknown>;
  const kept = new Map<string, (...args: unknown[]) => unknown>();
  for (const name of Object.keys(target)) {
    const call = target[name];
    if (!name.endsWith("Sync") || typeof call !== "function") continue;
    const original = call as (...args: unknown[]) => unknown;
    kept.set(name, original);
    const timedCall = function (this: unknown, ...args: unknown[]) {
      const at = now();
      try {
        return original.apply(this, args);
      } finally {
        const ms = now() - at;
        waits.ms += ms;
        waits.calls++;
        if (ms >= WAITED_MS) {
          const where: { stack?: string } = {};
          Error.captureStackTrace(where, timedCall);
          const key = `${name} ${askedBy(where.stack)}`;
          const was = waits.by.get(key) ?? { ms: 0, calls: 0 };
          waits.by.set(key, { ms: was.ms + ms, calls: was.calls + 1 });
        }
      }
    };
    // What hangs off a call (realpathSync.native) stays.
    target[name] = Object.assign(timedCall, original);
  }
  syncBuiltinESMExports();
  return {
    take() {
      const taken = waits;
      waits = { ms: 0, calls: 0, by: new Map() };
      return taken;
    },
    stop() {
      for (const [name, original] of kept) target[name] = original;
      syncBuiltinESMExports();
    },
  };
}

/// The longest waits, as the log says them: `<call> <who made it> <ms>ms×<calls>`, the longest first.
export function longestWaits(waits: FileWaits, most = 3): string {
  return [...waits.by]
    .sort((a, b) => b[1].ms - a[1].ms)
    .slice(0, most)
    .map(([key, w]) => `${key} ${Math.round(w.ms)}ms×${w.calls}`)
    .join("; ");
}
