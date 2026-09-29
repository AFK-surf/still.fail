// The desktop app's move from its name before the rename, with nothing of Electron in it (main.ts uses it;
// test/desktop-moves.test.ts runs it on a temporary directory). An .mts: an ES module to the tests, whose
// TypeScript takes this package's .ts files for CommonJS.
import { lstatSync, readdirSync, readlinkSync, renameSync, rmdirSync, symlinkSync } from "node:fs";
import { join } from "node:path";

const there = (path: string) => {
  try {
    lstatSync(path);
    return true;
  } catch {
    return false;
  }
};

/**
 * Moves the app's data (userData) from `former` (…/Application Support/ember, the app's name before the rename) to
 * `now`, leaving a link at the old place, and answers where the data is to be. Nothing moves when `now` has the core's
 * data already (it is in use) or `former` is gone or a link (moved before); `former` is answered while the old app runs
 * on it (its SingletonLock names a process `alive` says is running), or when the move failed.
 */
export function moveUserData(now: string, former: string, alive: (pid: number) => boolean): { dir: string; moved: boolean; error?: string } {
  if (now === former || !there(former) || lstatSync(former).isSymbolicLink() || there(join(now, "core"))) return { dir: now, moved: false };
  try {
    const pid = Number(/-(\d+)$/.exec(readlinkSync(join(former, "SingletonLock")))?.[1]);
    if (pid && alive(pid)) return { dir: former, moved: false };
  } catch { /* no lock */ }
  try {
    if (!there(now)) renameSync(former, now);
    else {
      // Made already (by Electron, before this ran): what it lacks comes over, entry by entry.
      for (const name of readdirSync(former)) if (!there(join(now, name))) renameSync(join(former, name), join(now, name));
      rmdirSync(former);
    }
    symlinkSync(now, former);
    return { dir: now, moved: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { dir: !there(join(now, "core")) && there(join(former, "core")) ? former : now, moved: false, error: message };
  }
}
