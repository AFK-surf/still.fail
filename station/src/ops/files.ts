// Files the station keeps: where its data directory is, and writing them whole (a reader never sees half a file).
import { closeSync, fsyncSync, mkdirSync, openSync, renameSync, writeSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

/// The data directory: `--data`, else $STILLFAIL_DATA, else $EMBER_DATA (before the rename), else ~/.stillfail.
export function dataDir(args: string[]): string {
  const at = args.indexOf("--data");
  if (at >= 0 && args[at + 1]) return args[at + 1];
  return process.env.STILLFAIL_DATA || process.env.EMBER_DATA || join(homedir(), ".stillfail");
}

/// The value after `flag` in argv, wherever it is (as the Rust station reads its flags).
export function flag(args: string[], name: string): string | undefined {
  const at = args.indexOf(name);
  return at >= 0 ? args[at + 1] : undefined;
}

/// Written beside and renamed into place, synced, readable by its owner only.
export function writePrivate(path: string, data: string | Uint8Array) {
  mkdirSync(dirname(path), { recursive: true });
  const tmp = `${path}.tmp`;
  const fd = openSync(tmp, "w", 0o600);
  try {
    writeSync(fd, typeof data === "string" ? Buffer.from(data) : data);
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
  renameSync(tmp, path);
}

export const nowSecs = () => Math.floor(Date.now() / 1000);
