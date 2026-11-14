// Files the station keeps: where its data directory is, and writing them whole (a reader never sees half a file).
import { closeSync, fsyncSync, mkdirSync, openSync, opendirSync, readFileSync, renameSync, writeSync } from "node:fs";
import { mkdir, open, opendir, rename } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { tr, type Lang } from "./i18n.ts";
import { wall } from "./fibers.ts";
import { platform } from "../platform/index.ts";

/// The data directory: `--data`, else $STILLFAIL_DATA, else ~/.stillfail.
export function dataDir(args: string[]): string {
  const at = args.indexOf("--data");
  if (at >= 0 && args[at + 1]) return args[at + 1];
  return process.env.STILLFAIL_DATA || join(homedir(), ".stillfail");
}

/// Whether `data` is the machine's own data directory (~/.stillfail), as the launcher's
/// data.rs `is_default`: only its station takes the usual ports (4750, 4760); one on another directory (a test's, a
/// development station's) takes free ones, so it never keeps the machine's station off them.
export function ownData(data: string, home = homedir()): boolean {
  const key = (path: string) => platform.paths.key(platform.paths.clean(path));
  return key(join(home, ".stillfail")) === key(data);
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

/// `writePrivate` off the station's thread: its sync waits on the disk, a fraction of a second on one kept busy.
export async function writePrivateSoon(path: string, data: string | Uint8Array): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  const tmp = `${path}.${process.pid}.tmp`;
  const file = await open(tmp, "w", 0o600);
  try {
    await file.writeFile(data);
    await file.sync();
  } finally {
    await file.close();
  }
  await rename(tmp, path);
}

/// A file of the station's own that it keeps in memory and writes through (`writePrivateSoon`): what is asked while a
/// write is on its way is written after it, the latest only. What it gives resolves once what was asked is written.
export class PrivateFile {
  readonly path: string;
  #latest: string | Uint8Array | null = null;
  #writing: Promise<void> | null = null;

  constructor(path: string) {
    this.path = path;
  }

  write(data: string | Uint8Array): Promise<void> {
    this.#latest = data;
    return (this.#writing ??= this.#flush());
  }

  /// Once what was asked is written (or failed).
  async written(): Promise<void> {
    await this.#writing?.catch(() => undefined);
  }

  async #flush(): Promise<void> {
    try {
      while (this.#latest !== null) {
        const data = this.#latest;
        this.#latest = null;
        await writePrivateSoon(this.path, data);
      }
    } finally {
      this.#writing = null;
    }
  }
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
