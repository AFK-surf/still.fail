// The files as the station's main thread waits on them, timed. A synchronous call of node:fs holds every device and
// every agent until the disk answers: on a machine short of memory one existsSync took most of a second, and the few
// dozen an overview makes held the station 16 s (2026-10-25), with no query slow and its process doing next to no work.
// Every such call of the main thread's is timed; those of WAITED_MS (ops/waits.ts) or more are put down with who made
// them (a stack is taken only then), for the line that says the main thread was held (main.ts). Never the paths: they
// name people's files.
import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { performance } from "node:perf_hooks";
import { askedBy, noWaits, waited, type Waits } from "./waits.ts";

/// node:fs's synchronous calls timed, in this thread (for the modules' named imports too); `take` gives what was waited
/// since it was last called, `stop` puts the calls back as they were.
export function timeFiles(now: () => number = () => performance.now()): { take: () => Waits; stop: () => void } {
  let waits = noWaits();
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
        waited(waits, now() - at, () => {
          const where: { stack?: string } = {};
          Error.captureStackTrace(where, timedCall);
          return `${name} ${askedBy(where.stack)}`;
        });
      }
    };
    // What hangs off a call (realpathSync.native) stays.
    target[name] = Object.assign(timedCall, original);
  }
  syncBuiltinESMExports();
  return {
    take() {
      const taken = waits;
      waits = noWaits();
      return taken;
    },
    stop() {
      for (const [name, original] of kept) target[name] = original;
      syncBuiltinESMExports();
    },
  };
}
