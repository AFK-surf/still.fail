// What the platforms and the rest of the station both use and that is the same on every machine, in a module that
// imports nothing of the station's (so platform/windows.ts can use it without importing platform/index.ts back).
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";

/// The runner binary: STILLFAIL_RUNNER, else beside the station's code in a release, else where cargo built it.
export function runnerBinary(): string {
  const name = process.platform === "win32" ? "stillfail-runner.exe" : "stillfail-runner";
  const candidates = [
    process.env.STILLFAIL_RUNNER,
    fileURLToPath(new URL(`./${name}`, import.meta.url)),
    fileURLToPath(new URL(`../../native/runner/target/release/${name}`, import.meta.url)),
  ];
  const found = candidates.find((p) => p && existsSync(p));
  if (!found) throw new Error(`stillfail-runner is not there (looked at ${candidates.filter(Boolean).join(", ")})`);
  return found;
}

/// Whether one process is there.
export function pidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "EPERM";
  }
}
