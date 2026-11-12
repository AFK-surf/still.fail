// Programs for the Linux X11 desktop. Prefer the machine's pair; on Debian-family systems the station can prepare
// its own pair without installing packages into the operating system or requiring an administrator.
import { accessSync, constants } from "node:fs";
import { mkdir, mkdtemp, readdir, rename, rm, writeFile } from "node:fs/promises";
import { delimiter, isAbsolute, join } from "node:path";
import { wall } from "../ops/fibers.ts";
import { endCommand, startCommand } from "../ops/processes.ts";

type Running = { env: NodeJS.ProcessEnv; signal: AbortSignal; timeout: number; maxBuffer?: number };

/// A command of the preparation, run as a group of its own (ops/processes.ts): stopped, out of time or saying too
/// much, it is ended whole, it and what it started (apt-get's fetchers), and it answers only once nothing of it holds
/// its output any more. What follows a stop, the stage removed, then meets no process of it still writing there: ended
/// alone, apt-get left one behind that put a package into the stage as it was removed, and the stage stayed.
function run(program: string, args: string[], o: Running): Promise<{ stdout: string }> {
  return new Promise((resolve, reject) => {
    const child = startCommand(program, args, { env: o.env, stdio: ["ignore", "pipe", "pipe"] });
    const most = o.maxBuffer ?? 1024 * 1024;
    let stdout = "", said = 0, failed: Error | null = null;
    const end = (why: Error) => {
      failed ??= why;
      endCommand(child, "SIGKILL");
    };
    const stopped = () => end(o.signal.reason instanceof Error ? o.signal.reason : new Error(`${program} stopped`));
    // The command's time, the machine's: one left going is ended, its whole group.
    const late = wall.after(o.timeout, () => end(new Error(`${program} took more than ${o.timeout} ms`)));
    const hear = (keep: boolean) => (chunk: Buffer) => {
      said += chunk.length;
      if (said > most) end(new Error(`${program} said more than ${most} bytes`));
      else if (keep) stdout += chunk.toString("utf8");
    };
    child.stdout!.on("data", hear(true));
    child.stderr!.on("data", hear(false));
    const done = (answer: () => void) => {
      late();
      o.signal.removeEventListener("abort", stopped);
      answer();
    };
    // (not started at all: nothing of it to wait for)
    child.on("error", (e) => done(() => reject(failed ?? e)));
    child.on("close", (code, signal) => done(() => (failed ? reject(failed) : code === 0 ? resolve({ stdout }) : reject(new Error(`${program} ended with ${code ?? signal}`)))));
    if (o.signal.aborted) stopped();
    else o.signal.addEventListener("abort", stopped, { once: true });
  });
}

/// Resolve only executables, without invoking a shell or consulting a different user's environment.
export function executable(name: string, env: NodeJS.ProcessEnv): string | null {
  const paths = isAbsolute(name) || name.includes("/") ? [name] : (env.PATH ?? "").split(delimiter).filter(Boolean).map((dir) => join(dir, name));
  return paths.find((path) => {
    try { accessSync(path, constants.X_OK); return true; } catch { return false; }
  }) ?? null;
}

export type LinuxToolPair = { ffmpeg: string; xdotool: string; env: NodeJS.ProcessEnv };

function pairAt(root: string, env: NodeJS.ProcessEnv): LinuxToolPair | null {
  const ffmpeg = executable(join(root, "usr/bin/ffmpeg"), env);
  const xdotool = executable(join(root, "usr/bin/xdotool"), env);
  const arch = process.arch === "x64" ? "x86_64-linux-gnu" : process.arch === "arm64" ? "aarch64-linux-gnu" : null;
  if (!ffmpeg || !xdotool || !arch) return null;
  const libraries = [join(root, "usr/lib", arch), join(root, "lib", arch), join(root, "usr/lib"), join(root, "lib"), env.LD_LIBRARY_PATH].filter(Boolean).join(delimiter);
  return { ffmpeg, xdotool, env: { ...env, LD_LIBRARY_PATH: libraries } };
}

/// Programs and their dependencies extracted under the station's data directory from the machine's APT repositories.
/// APT verifies its repositories' package hashes; dpkg-deb only unpacks the archives, never runs maintainer scripts.
export class LinuxScreenTools {
  readonly #dir: string;
  #preparing: Promise<void> | null = null;
  #abort: AbortController | null = null;
  #closed = false;

  constructor(data: string) { this.#dir = join(data, "screen-tools", "apt"); }

  /// The pair prepared here, with its libraries searched only by its own child processes.
  prepared(env: NodeJS.ProcessEnv): LinuxToolPair | null {
    try { accessSync(join(this.#dir, "ready"), constants.R_OK); } catch { return null; }
    return pairAt(join(this.#dir, "root"), env);
  }

  /// Whether this machine has the Debian package tools and an architecture the station ships for.
  canPrepare(env: NodeJS.ProcessEnv): boolean {
    return (process.arch === "x64" || process.arch === "arm64") && !!executable("apt-get", env) && !!executable("dpkg-deb", env);
  }

  /// Concurrent requests in one station share the download; an interrupted or failed preparation can be tried again.
  prepare(env: NodeJS.ProcessEnv): Promise<void> {
    if (this.#closed) return Promise.reject(new Error("screen tools closed"));
    if (this.prepared(env)) return Promise.resolve();
    if (!this.#preparing) {
      const abort = new AbortController();
      this.#abort = abort;
      this.#preparing = this.#install(env, abort.signal).finally(() => { this.#preparing = null; this.#abort = null; });
    }
    return this.#preparing;
  }

  close(): void { this.#closed = true; this.#abort?.abort(); }

  async #install(env: NodeJS.ProcessEnv, signal: AbortSignal): Promise<void> {
    const apt = executable("apt-get", env), dpkg = executable("dpkg-deb", env);
    if (!apt || !dpkg || !this.canPrepare(env)) throw new Error("APT package tools are unavailable");
    const parent = join(this.#dir, "..");
    await mkdir(parent, { recursive: true, mode: 0o700 });
    const stage = await mkdtemp(join(parent, ".apt-"));
    const archives = join(stage, "archives"), root = join(stage, "root");
    try {
      await mkdir(join(archives, "partial"), { recursive: true, mode: 0o700 });
      // This is read-only with respect to the system's package database. --reinstall downloads both commands even if
      // the database says one is already installed; the private cache and no-locking let it run as the station user.
      await run(apt, ["--download-only", "--assume-yes", "--reinstall", "--no-remove", "--no-install-recommends",
        "-o", "Debug::NoLocking=1", "-o", `Dir::Cache::archives=${archives}`,
        "-o", "Dir::Cache::pkgcache=", "-o", "Dir::Cache::srcpkgcache=", "install", "ffmpeg", "xdotool"],
        { env: { ...env, DEBIAN_FRONTEND: "noninteractive" }, signal, timeout: 180_000, maxBuffer: 4 * 1024 * 1024 });
      const packages = (await readdir(archives)).filter((f) => f.endsWith(".deb")).sort();
      if (!packages.length) throw new Error("APT returned no packages");
      await mkdir(root, { mode: 0o700 });
      for (const file of packages) await run(dpkg, ["--extract", join(archives, file), root], { env, signal, timeout: 30_000 });
      const pair = pairAt(root, env);
      if (!pair) throw new Error("APT packages lack the screen programs");
      const [devices] = await Promise.all([
        run(pair.ffmpeg, ["-hide_banner", "-devices"], { env: pair.env, signal, timeout: 30_000 }),
        run(pair.xdotool, ["--version"], { env: pair.env, signal, timeout: 30_000 }),
      ]);
      if (!/\bD\s+x11grab\b/.test(devices.stdout)) throw new Error("FFmpeg does not support X11 capture");
      await rm(archives, { recursive: true, force: true });
      await writeFile(join(stage, "ready"), "\n", { mode: 0o600 });
      signal.throwIfAborted();
      // Do not replace a pair another station process finished preparing during a handover.
      try { await rename(stage, this.#dir); }
      catch (error) { if (!this.prepared(env)) throw error; }
    } finally {
      await rm(stage, { recursive: true, force: true });
    }
  }
}
