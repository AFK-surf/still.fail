// What of this machine still.fail uses (resources/watch.ts), as a part of the station (parts.ts): looked at while a
// page asks; GET /resources.
import { execFile, execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { rm } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import { promisify } from "node:util";
import { Effect, Layer } from "effect";
import { resourceRoutes } from "../api/routes/usage.ts";
import { runnerSessions, runnersWithSessions, watchedJobs } from "../jobs/memory.ts";
import { loadMesh } from "../mesh/native.ts";
import { platform } from "../platform/index.ts";
import { Agents } from "../sessions/agents.ts";
import { Parts, Paths, Store } from "../services.ts";
import { ResourceWatch } from "./watch.ts";

/// The desktop app's bundle ids begin so (apps/desktop: fail.still.desktop, fail.still.desktop.beta, …).
const APP_ID = "fail.still.desktop";

/// Whether `command` runs from a bundle of the desktop app's: its Info.plist names the id (as text in an XML plist or a
/// binary one alike). Each bundle read once.
function appBundles(): (command: string) => boolean {
  const known = new Map<string, boolean>();
  return (command) => {
    const at = command.indexOf(".app/Contents/");
    if (at < 0) return false;
    const bundle = command.slice(0, at + 4);
    let is = known.get(bundle);
    if (is === undefined) {
      try {
        is = readFileSync(`${bundle}/Contents/Info.plist`).includes(APP_ID);
      } catch {
        is = false;
      }
      known.set(bundle, is);
    }
    return is;
  };
}

const run = promisify(execFile);

/// `ps -o pid=,args=`: each pid's command line.
function parseArgs(text: string): Map<number, string> {
  const out = new Map<number, string>();
  for (const line of text.split("\n")) {
    const m = line.match(/^\s*(\d+)\s(.*)$/);
    if (m) out.set(Number(m[1]), m[2]!);
  }
  return out;
}

/// `nettop -P -L 1 -x -J bytes_in,bytes_out -n`: each process's bytes in and out so far, as `name.pid,in,out,` (its
/// name may have dots of its own).
export function parseNettop(text: string): Map<number, { in: number; out: number }> {
  const out = new Map<number, { in: number; out: number }>();
  for (const line of text.split("\n")) {
    const m = line.match(/\.(\d+),(\d+),(\d+),?$/);
    if (m) out.set(Number(m[1]), { in: Number(m[2]), out: Number(m[3]) });
  }
  return out;
}

/// Whether this process's parent is its launcher (stillfail-station), not a shell or launchd, whose all under it is not
/// the station's.
function launcher(): boolean {
  if (process.ppid <= 1) return false;
  try {
    return basename(execFileSync("ps", ["-o", "comm=", "-p", String(process.ppid)], { encoding: "utf8" }).trim()).startsWith("stillfail");
  } catch {
    return false;
  }
}

export const ResourcesLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const store = yield* Store;
    const { hub } = yield* Agents;
    // What processes used is read on macOS only; elsewhere there is nothing to look at.
    if (platform.os !== "macos") {
      (yield* Parts).routes((tools) => resourceRoutes(tools, null));
      return;
    }
    const mesh = loadMesh();
    const isApp = appBundles();
    const whose = runnerSessions(store);
    const watch = yield* Effect.acquireRelease(
      Effect.sync(() => new ResourceWatch({
        clock: hub.clock,
        table: () => platform.processTable(false),
        args: async () => parseArgs((await run("ps", ["-axo", "pid=,args="], { maxBuffer: 32 << 20 })).stdout),
        // A chat's own directory, not where it works (a repository people also work in).
        places: () => store.liveSessions().flatMap((s) => (s.workspace && s.workspace !== "/" && s.workspace !== homedir() ? [{ dir: s.workspace, session: s.key }] : [])),
        usage: (pids) => (typeof mesh.processUsage === "function" ? mesh.processUsage(pids) : pids.map(() => null)),
        // Every process's, once: some 20 ms.
        traffic: async () => parseNettop((await run("nettop", ["-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out", "-n"], { maxBuffer: 16 << 20, timeout: 5000 })).stdout),
        runners: () => runnersWithSessions(data, whose),
        jobs: () => watchedJobs(store),
        isApp,
        self: [process.pid, ...(launcher() ? [process.ppid] : [])],
      })),
      (w) => Effect.promise(() => w.close()),
    );
    // What was kept of the hours' energy before (no longer counted).
    void rm(join(data, "resources", "hours.json"), { force: true }).catch(() => {});
    (yield* Parts).routes((tools) => resourceRoutes(tools, watch));
  }),
);
