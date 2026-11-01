// Files the station keeps: where its data directory is, and writing them whole (a reader never sees half a file).
import { closeSync, fsyncSync, mkdirSync, openSync, opendirSync, readFileSync, renameSync, writeSync } from "node:fs";
import { opendir } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { tr, type Lang } from "./i18n.ts";
import { wall } from "./fibers.ts";
import { platform } from "../platform/index.ts";

/// The data directory: `--data`, else $STILLFAIL_DATA, else $EMBER_DATA (before the rename), else ~/.stillfail.
export function dataDir(args: string[]): string {
  const at = args.indexOf("--data");
  if (at >= 0 && args[at + 1]) return args[at + 1];
  return process.env.STILLFAIL_DATA || process.env.EMBER_DATA || join(homedir(), ".stillfail");
}

/// Whether `data` is the machine's own data directory (~/.stillfail, or ~/.ember not moved yet), as the launcher's
/// data.rs `is_default`: only its station takes the usual ports (4750, 4760); one on another directory (a test's, a
/// development station's) takes free ones, so it never keeps the machine's station off them.
export function ownData(data: string, home = homedir()): boolean {
  const key = (path: string) => platform.paths.key(platform.paths.clean(path));
  return [".stillfail", ".ember"].some((d) => key(join(home, d)) === key(data));
}

/// Where the MCP endpoint's port is remembered (the launcher's ports.rs writes it too): agents a station leaves running
/// for the next were told it, so the next takes it again when it is free.
export const mcpPortFile = (data: string) => join(data, "run", "mcp.json");

export function rememberedMcpPort(data: string): number | undefined {
  try {
    const port = JSON.parse(readFileSync(mcpPortFile(data), "utf8")).port;
    return Number.isInteger(port) && port > 0 && port < 65536 ? port : undefined;
  } catch {
    return undefined;
  }
}

/// The ports to try, in order, for a listener of the station's own (no launcher): the one named alone; else the one
/// remembered, then the usual one on the machine's own data directory, then any (0).
export function portsToTry(named: number | undefined, remembered: number | undefined, usual: number, own: boolean): number[] {
  if (named !== undefined) return [named];
  return [...new Set([remembered, own ? usual : undefined, 0].filter((p): p is number => p !== undefined))];
}

/// The value after `flag` in argv, wherever it is (as the Rust station reads its flags).
export function flag(args: string[], name: string): string | undefined {
  const at = args.indexOf(name);
  return at >= 0 ? args[at + 1] : undefined;
}

/// Written beside and renamed into place, synced, readable by its owner only. Beside under this process's own name:
/// another process writing the same file at once (`enroll` while the station runs) has its own.
export function writePrivate(path: string, data: string | Uint8Array) {
  mkdirSync(dirname(path), { recursive: true });
  const tmp = `${path}.${process.pid}.tmp`;
  const fd = openSync(tmp, "w", 0o600);
  try {
    writeSync(fd, typeof data === "string" ? Buffer.from(data) : data);
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
  renameSync(tmp, path);
}

/// Seconds, as the cloud and the files say them: the machine's time.
export const nowSecs = () => Math.floor(wall.now() / 1000);

/// Whether `dir` is there but the station may not list it (EPERM, EACCES; it may still stat it). On macOS a folder the
/// system's privacy protection keeps (Documents, Desktop, Downloads, removable and network volumes) answers EPERM to a
/// process nobody gave access to, and a station launchd runs is never asked: an agent started there exits at once,
/// saying nothing of why.
export function unreadableDir(dir: string): boolean {
  try {
    opendirSync(dir).closeSync();
    return false;
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    return code === "EPERM" || code === "EACCES";
  }
}

/// `unreadableDir` off the main thread: opening a folder can wait for as long as what it is on does not answer (a
/// network file system whose server is gone: OrbStack's when its machine is stopped), and the station's thread with it.
export async function unreadableDirAsync(dir: string): Promise<boolean> {
  try {
    await (await opendir(dir)).close();
    return false;
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    return code === "EPERM" || code === "EACCES";
  }
}

/// What to tell when an agent's directory is unreadable (`unreadableDir`): on macOS, who to give access to and where.
/// The desktop app runs its station with --with-parent and is the one macOS asks about; an installed station is its
/// stillfail-station.
export function unreadableDirMessage(lang: Lang, dir: string, argv = process.argv): string {
  if (!platform.hasFolderPermissions) return tr(lang, "station.session.cwdDenied", { cwd: dir });
  const app = flag(argv, "--app");
  const program = argv.includes("--with-parent") || !app ? "still.fail" : join(app, "mesh", "target", "release", "stillfail-station");
  return tr(lang, "station.session.cwdDeniedMac", { cwd: dir, program });
}
