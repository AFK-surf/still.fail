import { mkdtempSync, rmSync } from "node:fs";

/// A test directory with a short, caller-chosen prefix (the runner's sockets have a 104-byte limit on macOS).
export function tempDir(prefix: string): string {
  const data = mkdtempSync(prefix);
  // Node may exit successfully while an async after hook is waiting on an unref'd timer. Remove the directory even then.
  process.once("exit", () => rmSync(data, { recursive: true, force: true, maxRetries: 3 }));
  return data;
}
