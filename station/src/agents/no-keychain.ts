// Claude Code on macOS keeps its login in the keychain, under a name made from its config directory's path, and falls
// back to <config dir>/.credentials.json only when the keychain refuses. A profile's login
// has to live in its home (homes are renamed after a sign-in, quota and checks read the file, the keychain is out of
// reach outside the desktop session). So profile processes get a `security` first on their PATH that finds and stores
// nothing of Claude Code's (exit 44, "not found"); anything else goes to the real one. Machine profiles are not touched.
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { chmodSync, closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, renameSync, writeFileSync, writeSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { writePrivateSoon } from "../ops/files.ts";
import { log } from "../ops/log.ts";
import { platform } from "../platform/index.ts";

/// Claude Code asks with its item's name in the arguments, or (`security -i`) in the commands it writes to stdin.
const STUB = `#!/bin/sh
# still.fail: profile logins are kept in files, not the keychain; the rest goes to the real security.
case "$*" in *"Claude Code"*) exit 44 ;; esac
if [ "$1" = "-i" ]; then
  input=$(cat)
  case "$input" in *"Claude Code"*) exit 44 ;; esac
  printf '%s\\n' "$input" | /usr/bin/security "$@"
  exit $?
fi
exec /usr/bin/security "$@"
`;

/// The directory with the stand-in `security`, made (again) when missing or an older one.
export function stubDir(): string {
  const dir = join(tmpdir(), `stillfail-no-keychain-${process.getuid?.() ?? 0}`);
  const path = join(dir, "security");
  let current: string | undefined;
  try {
    current = readFileSync(path, "utf8");
  } catch {}
  if (current !== STUB) {
    try {
      mkdirSync(dir, { recursive: true });
      // Written aside and moved in: a process may be running the old one.
      const fresh = join(dir, `security.${process.pid}`);
      writeFileSync(fresh, STUB);
      chmodSync(fresh, 0o755);
      renameSync(fresh, path);
    } catch {}
  }
  return dir;
}

/// Keeps Claude Code off the keychain in `env` (macOS only; elsewhere it uses the file anyway).
export function fileCredentials(env: Record<string, string>) {
  if (!platform.hasKeychain) return;
  const path = env.PATH ?? process.env.PATH ?? "";
  env.PATH = `${stubDir()}:${path}`;
}

/// The keychain item Claude Code keeps the login of a config directory in.
export function keychainItem(home: string): string {
  return `Claude Code-credentials-${createHash("sha256").update(home).digest("hex").slice(0, 8)}`;
}

const security = (args: string[]) =>
  new Promise<{ ok: boolean; stdout: string }>((resolve) => {
    execFile("/usr/bin/security", args, { timeout: 5000 }, (error, stdout) => resolve({ ok: !error, stdout: String(stdout) }));
  });

/// A profile's login that Claude Code moved into the keychain, moved back into its home's file. Nothing when the file
/// is there or unreadable.
export async function takeBack(home: string) {
  if (!platform.hasKeychain) return;
  const file = join(home, ".credentials.json");
  if (existsSync(file)) return;
  const item = keychainItem(home);
  const found = await security(["find-generic-password", "-w", "-s", item]);
  if (!found.ok) return;
  const text = found.stdout.trim();
  let isLogin = false;
  try {
    isLogin = JSON.parse(text)?.claudeAiOauth !== undefined;
  } catch {}
  if (!isLogin) return;
  try {
    writePrivate(file, text);
  } catch (error) {
    log.warn("agents::no_keychain", "could not move a profile's login out of the keychain", { home, error: String(error) });
    return;
  }
  await security(["delete-generic-password", "-s", item]);
  log.info("agents::no_keychain", "a profile's login moved back from the keychain to its file", { home });
}

/// As `takeBack`, off the station's thread once `.credentials.json` was already found missing (`ENOENT`).
export async function takeBackMissing(home: string): Promise<boolean> {
  if (!platform.hasKeychain) return false;
  const item = keychainItem(home);
  const found = await security(["find-generic-password", "-w", "-s", item]);
  if (!found.ok) return false;
  const text = found.stdout.trim();
  let isLogin = false;
  try {
    isLogin = JSON.parse(text)?.claudeAiOauth !== undefined;
  } catch {}
  if (!isLogin) return false;
  try {
    await writePrivateSoon(join(home, ".credentials.json"), text);
  } catch (error) {
    log.warn("agents::no_keychain", "could not move a profile's login out of the keychain", { home, error: String(error) });
    return false;
  }
  await security(["delete-generic-password", "-s", item]);
  log.info("agents::no_keychain", "a profile's login moved back from the keychain to its file", { home });
  return true;
}

/// Written aside (readable by its owner only) and moved in.
export function writePrivate(file: string, text: string) {
  const aside = `${file.replace(/\.json$/, "")}.json.${process.pid}`;
  const fd = openSync(aside, "w", 0o600);
  try {
    writeSync(fd, text);
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
  renameSync(aside, file);
}
