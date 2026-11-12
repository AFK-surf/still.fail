// The files and processes as the station's main thread waits on them, timed. A synchronous call of node:fs holds every
// device and every agent until the disk answers: on a machine short of memory one existsSync took most of a second, and
// the few dozen an overview makes held the station 16 s (2026-10-25), with no query slow and its process doing next to
// no work. A process waited on (node:child_process's execSync, execFileSync, spawnSync) holds it until that process has
// started, run and ended: under memory pressure, seconds each. Every such call of the main thread's is timed; those of
// WAITED_MS (ops/waits.ts) or more are put down with who made them (a stack is taken only then), for the line that says
// the main thread was held (main.ts). Never the paths or the commands' arguments: they name people's files.
import childProcess from "node:child_process";
import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { performance } from "node:perf_hooks";
import { askedBy, noWaits, waited, type Waits } from "./waits.ts";

/// What was waited on since it was last asked (`take`), and the calls put back as they were (`stop`).
export type Timed = { take: () => Waits; stop: () => void };

/// The functions of `target` that `wanted` names timed, in this thread (for the modules' named imports too).
function timeCalls(target: Record<string, unknown>, wanted: (name: string) => boolean, now: () => number): Timed {
  let waits = noWaits();
  // A call made inside another (readFileSync's own readSync, openSync, …) is the outer one's: put down once.
  let depth = 0;
  const kept = new Map<string, (...args: unknown[]) => unknown>();
  for (const name of Object.keys(target)) {
    const call = target[name];
    if (!wanted(name) || typeof call !== "function") continue;
    const original = call as (...args: unknown[]) => unknown;
    kept.set(name, original);
    const timedCall = function (this: unknown, ...args: unknown[]) {
      if (depth > 0) return original.apply(this, args);
      const at = now();
      depth++;
      try {
        return original.apply(this, args);
      } finally {
        depth--;
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

/// node:fs's synchronous calls timed, in this thread.
export function timeFiles(now: () => number = () => performance.now()): Timed {
  return timeCalls(fs as unknown as Record<string, unknown>, (name) => name.endsWith("Sync"), now);
}

/// node:child_process's waited-on processes timed, in this thread.
export function timeProcesses(now: () => number = () => performance.now()): Timed {
  return timeCalls(childProcess as unknown as Record<string, unknown>, (name) => name.endsWith("Sync"), now);
}
