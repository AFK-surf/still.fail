// A Codex copied without its code-mode host cannot use the station's tools. Recognise the native executable (including
// npm's launcher), and only offer to replace a command in the person's home. The old entry is kept as a backup.
import { randomBytes } from "node:crypto";
import { accessSync, closeSync, constants, linkSync, lstatSync, openSync, readlinkSync, readSync, realpathSync, renameSync, statSync, symlinkSync, unlinkSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, isAbsolute, join } from "node:path";
import { platform as machine } from "../platform/index.ts";
import { withShellCommand } from "../ops/shell-path.ts";
import { type Env, type Found, findCommand, run } from "./runtimes.ts";
import { platform as npmPlatform } from "./versions.ts";

const TRIPLES: Record<string, string> = {
  "linux-x64": "x86_64-unknown-linux-musl",
  "linux-arm64": "aarch64-unknown-linux-musl",
  "darwin-x64": "x86_64-apple-darwin",
  "darwin-arm64": "aarch64-apple-darwin",
};

/// A native executable, not a shell or another package manager's wrapper whose target we cannot know.
function native(path: string): boolean {
  let fd: number | undefined;
  try {
    fd = openSync(path, "r");
    const bytes = Buffer.alloc(4);
    if (readSync(fd, bytes, 0, bytes.length, 0) !== bytes.length) return false;
    return new Set(["7f454c46", "feedfacf", "cffaedfe", "feedface", "cefaedfe", "cafebabe", "bebafeca"]).has(bytes.toString("hex"));
  } catch {
    return false;
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

function executable(path: string): boolean {
  try {
    accessSync(path, constants.X_OK);
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

export const hasCodexHost = (binary: string): boolean => executable(join(dirname(binary), machine.exe("codex-code-mode-host")));

/// The actual executable behind npm's official launcher, or the native command itself. Unknown wrappers stay unknown.
export function codexBinary(found: Found): string | null {
  if (native(found.real)) return found.real;
  if (!found.real.replaceAll("\\", "/").endsWith("/node_modules/@openai/codex/bin/codex.js")) return null;
  const target = npmPlatform();
  const triple = target === null ? undefined : TRIPLES[target];
  if (!target || !triple) return null;
  try {
    const require = createRequire(found.real);
    const packageFile = require.resolve(`@openai/codex-${target}/package.json`);
    const binary = join(dirname(packageFile), "vendor", triple, "bin", machine.exe("codex"));
    return native(binary) && executable(binary) ? realpathSync(binary) : null;
  } catch {
    return null;
  }
}

/// Only flag a missing host when this version says it uses one. Older Codex releases and unknown wrappers are left alone.
export async function missingCodexHost(
  found: Found,
  env: Env,
  features: (command: string, env: Env) => Promise<string | null> = async (command, e) => {
    try {
      const [ok, out] = await run(command, ["features", "list"], e, 20_000);
      return ok ? out : null;
    } catch {
      return null;
    }
  },
): Promise<{ binary: string; helper: string } | null> {
  const binary = codexBinary(found);
  if (binary === null) return null;
  const helper = join(dirname(binary), machine.exe("codex-code-mode-host"));
  if (hasCodexHost(binary)) return null;
  const listed = await features(found.onPath, env);
  return listed !== null && /^code_mode_host[ \t]+(?!removed\b)[^\r\n]*?[ \t]+true[ \t]*$/m.test(listed) ? { binary, helper } : null;
}

/// Resolve the command the runner will use; an unknown relative path is left for the runner to handle.
export async function findMissingCodexHost(command: string, env: Env): Promise<{ binary: string; helper: string } | null> {
  const effective = await withShellCommand(command, env);
  let found: Found | null = null;
  if (isAbsolute(command)) {
    try { found = { onPath: command, real: realpathSync(command) }; } catch {}
  } else if (!/[\\/]/.test(command)) found = findCommand(command, effective);
  return found ? missingCodexHost(found, effective) : null;
}

/// Changing a command in a system directory or through a directory link out of the home is not an automatic repair.
export function canSwitchCodex(found: Found, env: Env): boolean {
  if (!machine.codexStandalone || !isAbsolute(found.onPath)) return false;
  const home = machine.home(env);
  if (!home) return false;
  try {
    const dir = realpathSync(dirname(found.onPath));
    if (!machine.paths.within(dir, realpathSync(home))) return false;
    accessSync(dir, constants.W_OK);
    const entry = lstatSync(found.onPath);
    return (entry.isFile() || entry.isSymbolicLink()) && realpathSync(found.onPath) === found.real;
  } catch {
    return false;
  }
}

type Identity = { dev: number; ino: number; size: number; mtimeMs: number };
export type CodexEntry = { found: Found; entry: Identity; target: Identity };
const identity = (s: Identity): Identity => ({ dev: s.dev, ino: s.ino, size: s.size, mtimeMs: s.mtimeMs });
const same = (a: Identity, b: Identity) => a.dev === b.dev && a.ino === b.ino && a.size === b.size && a.mtimeMs === b.mtimeMs;

/// Remember the entry and its target before npm runs, so a change made meanwhile is never replaced.
export function captureCodex(found: Found, env: Env): CodexEntry | null {
  if (!canSwitchCodex(found, env)) return null;
  try {
    return { found, entry: identity(lstatSync(found.onPath)), target: identity(statSync(found.onPath)) };
  } catch {
    return null;
  }
}

/// Installs the new link only if the entry still names the one checked; the old entry, including a symlink, is kept.
export function switchCodex(captured: CodexEntry, launcher: string, env: Env): string {
  const { found } = captured;
  if (!canSwitchCodex(found, env)) throw new Error("Codex command changed or is not writable in the home directory");
  const suffix = randomBytes(8).toString("hex");
  const backup = `${found.onPath}.stillfail-backup-${suffix}`;
  if (!same(identity(lstatSync(found.onPath)), captured.entry) || !same(identity(statSync(found.onPath)), captured.target) || realpathSync(found.onPath) !== found.real) throw new Error("Codex command changed while repairing it");
  renameSync(found.onPath, backup);
  try {
    const saved = lstatSync(backup);
    if (!same(identity(saved), captured.entry) || !same(identity(statSync(backup)), captured.target) || (saved.isSymbolicLink() && realpathSync(backup) !== found.real)) throw new Error("Codex command changed while repairing it");
    // symlink() fails if someone created an entry while the old one was being moved; it never replaces theirs.
    symlinkSync(launcher, found.onPath);
    return backup;
  } catch (error) {
    try {
      restoreEntry(backup, found.onPath);
    } catch {
      throw new Error(`Codex command could not be restored; its backup is ${backup}`);
    }
    throw error;
  }
}

/// Link the saved entry back without replacing any command someone created in the meantime.
function restoreEntry(backup: string, path: string): void {
  if (lstatSync(backup).isSymbolicLink()) symlinkSync(readlinkSync(backup), path);
  else linkSync(backup, path);
  unlinkSync(backup);
}

/// Do not overwrite a command someone changed after the switch, even when a later validation fails.
export function restoreCodex(path: string, launcher: string, backup: string): void {
  const entry = lstatSync(path);
  if (!entry.isSymbolicLink() || readlinkSync(path) !== launcher) throw new Error(`Codex command changed; its backup is ${backup}`);
  const moved = `${path}.stillfail-failed-${randomBytes(8).toString("hex")}`;
  renameSync(path, moved);
  try {
    if (!same(identity(lstatSync(moved)), identity(entry)) || readlinkSync(moved) !== launcher) throw new Error("Codex command changed while restoring it");
    restoreEntry(backup, path);
  } catch (error) {
    try { restoreEntry(moved, path); } catch {}
    throw new Error(`Codex command could not be restored; its backup is ${backup}: ${(error as Error).message}`);
  }
  try { unlinkSync(moved); } catch {}
}
