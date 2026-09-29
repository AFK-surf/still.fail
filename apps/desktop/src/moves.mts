// The desktop app's moves from its name before the rename, with nothing of Electron in them (main.ts and bridge.ts use
// them; test/desktop-moves.test.ts runs them on a temporary directory). An .mts: an ES module to the tests, whose
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

/** The fields of an electron-builder feed (latest-mac.yml) the bridge needs: they are at its top level. */
export function parseFeed(yml: string): { version: string; path: string; sha512: string } | null {
  const field = (name: string) => new RegExp(`^${name}:\\s*['"]?([^'"\\n]+?)['"]?\\s*$`, "m").exec(yml)?.[1];
  const version = field("version");
  const path = field("path");
  const sha512 = field("sha512");
  return version && path && sha512 ? { version, path, sha512 } : null;
}
