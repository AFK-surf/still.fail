// This machine's station, run by the app: the release the app carries in its Resources (scripts/station-bundle.sh: the
// station in TypeScript, its launcher at mesh/target/release/stillfail-station with the command line the Rust station
// had), started with the app, started again when it ends, stopped when the app quits. Its data
// is ~/.stillfail, as an installed station's is, so the machine is one station whichever runs it; when one is installed
// and running already (stillfail-station exits with HELD), the app leaves it be. A machine that ran it before the
// rename has it in ~/.ember: the station moves it to ~/.stillfail as it starts (station/native/launcher, data.rs).
import { execFile, spawn, type ChildProcess } from "node:child_process";
import { existsSync, lstatSync, mkdirSync, openSync, readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";

/** stillfail-station's exit when another station runs the data directory (station/native/launcher: HELD). */
const HELD = 3;

const WINDOWS = process.platform === "win32";

/**
 * The environment the station runs in, with `first` before its PATH: where the agents (Claude Code, Codex) are found, as
 * an installed station's (cloud/src/install.ts). On Windows the variable is `Path` as often as not, and is one whatever
 * its case: the others are dropped, so the station is not given two.
 */
function withPath(env: NodeJS.ProcessEnv, first: string[], last: string[]): NodeJS.ProcessEnv {
  const key = Object.keys(env).find((k) => k.toUpperCase() === "PATH");
  const out: NodeJS.ProcessEnv = {};
  for (const [k, v] of Object.entries(env)) if (!(WINDOWS && k.toUpperCase() === "PATH")) out[k] = v;
  out.PATH = [...first, (key && env[key]) ?? "", ...last].filter((d) => d !== "").join(delimiter);
  return out;
}

/** The proxy variables a terminal has and an app opened from Finder does not (Claude Code and Codex follow only these). */
const PROXY = ["http_proxy", "https_proxy", "all_proxy", "no_proxy"].flatMap((name) => [name, name.toUpperCase()]);
const MARK = "__stillfail_env__";

/**
 * The proxy variables the user's login shell sets (an `export https_proxy=…` in ~/.zshrc, as proxy apps tell one to
 * write), for those the app was not started with: opened from Finder or the Dock it has launchd's environment, and the
 * station's agents would reach the API without the proxy the terminal's go through. Read once, by an interactive login
 * shell as a terminal's (what it prints of its own is cut off by the marks); none when it fails or takes over 5 s.
 */
let shellProxy: Promise<Record<string, string>> | null = null;
function proxyOfShell(): Promise<Record<string, string>> {
  shellProxy ??= new Promise((resolve) => {
    const shell = process.env.SHELL;
    if (process.platform === "win32" || !shell) return resolve({});
    execFile(shell, ["-ilc", `printf '${MARK}'; env; printf '${MARK}'`], { timeout: 5000, maxBuffer: 1 << 20 }, (error, stdout) => {
      const env = error ? undefined : stdout.split(MARK)[1];
      const found: Record<string, string> = {};
      for (const line of env?.split("\n") ?? []) {
        const at = line.indexOf("=");
        const name = line.slice(0, at);
        if (at > 0 && PROXY.includes(name) && process.env[name] === undefined) found[name] = line.slice(at + 1);
      }
      resolve(found);
    });
  });
  return shellProxy;
}

/** A directory with something in it (a link counts: ~/.ember once moved is one). */
function inUse(path: string): boolean {
  try {
    return lstatSync(path).isSymbolicLink() || readdirSync(path).length > 0;
  } catch {
    return false;
  }
}

/** Where this machine's station stands (LocalStation.place): `workspace` is the one it is, or was, in. */
export interface Place {
  state: "off" | "running" | "removed";
  workspace?: string;
}

export class LocalStation {
  /**
   * The data directory: ~/.stillfail; ~/.ember while that is where the data still is (only there, not moved yet), so
   * the log goes where the data is and the station, given it, moves it (nothing may be put in ~/.stillfail first: a
   * directory with anything in it is taken for one in use, and the old one is then left where it is). $STILLFAIL_DATA
   * instead when set, as stillfail-station itself takes it: for trying the app with a station of its own (a dev cloud).
   */
  get data(): string {
    if (process.env.STILLFAIL_DATA) return process.env.STILLFAIL_DATA;
    const now = join(homedir(), ".stillfail");
    const former = join(homedir(), ".ember");
    return !inUse(now) && inUse(former) ? former : now;
  }
  readonly #bin: string;
  #child: ChildProcess | null = null;
  /** Reading the shell's proxy before the first start. */
  #starting = false;
  #stopping = false;
  #backoff = 1000;
  /** Another station runs this machine's data: this one is not started again until the app is. */
  held = false;

  /** `dir`: the release, stillfail/ of scripts/station-bundle.sh. */
  constructor(readonly dir: string) {
    this.#bin = join(dir, "mesh", "target", "release", WINDOWS ? "stillfail-station.exe" : "stillfail-station");
  }

  /**
   * What the station's launcher runs it with: this app's own Electron as Node (ELECTRON_RUN_AS_NODE), which the release
   * names as its Node (.node-version, Electron's): the station carries none.
   */
  get #node(): Record<string, string> {
    return { STILLFAIL_NODE: process.execPath, ELECTRON_RUN_AS_NODE: "1" };
  }

  /** Whether the app carries a station (a build with SKIP_STATION=1 does not). */
  get carried(): boolean {
    return existsSync(this.#bin);
  }

  /**
   * Where this machine's station stands, by <data>/mesh/cloud.json (what `stillfail station enroll` writes): in no
   * workspace (off: no file), in one (running), or taken out of the one it was in (removed: the station keeps the file
   * and marks it `removed_at`, and the app never joins it again by itself). A file that cannot be read or parsed is
   * taken for one in a workspace, so that nothing joins this machine over whatever it says.
   */
  get place(): Place {
    let text: string;
    try {
      text = readFileSync(join(this.data, "mesh", "cloud.json"), "utf8");
    } catch (error) {
      return (error as NodeJS.ErrnoException).code === "ENOENT" ? { state: "off" } : { state: "running" };
    }
    try {
      const state = JSON.parse(text) as { workspace?: unknown; removed_at?: unknown };
      const workspace = typeof state.workspace === "string" && state.workspace ? { workspace: state.workspace } : {};
      return { state: state.removed_at == null ? "running" : "removed", ...workspace };
    } catch {
      return { state: "running" };
    }
  }

  /** Whether this machine's station is in a workspace (not removed from it). */
  get enrolled(): boolean {
    return this.place.state === "running";
  }

  start(): void {
    if (!this.carried || this.#child || this.#starting || this.#stopping || this.held) return;
    this.#starting = true;
    void proxyOfShell().then((proxy) => {
      this.#starting = false;
      if (!this.#child && !this.#stopping && !this.held) this.#spawn(proxy);
    });
  }

  #spawn(proxy: Record<string, string>): void {
    const data = this.data;
    mkdirSync(data, { recursive: true });
    const log = openSync(join(data, "stillfail.log"), "a");
    const started = Date.now();
    const child = spawn(this.#bin, ["run", "--app", this.dir, "--data", data, "--with-parent"], {
      // Opened from Finder the app has launchd's short PATH; the agents it starts (Claude Code, Codex) are found on this
      // one, as an installed station's (cloud/src/install.ts); and they go through the proxy the terminal's do.
      env: WINDOWS
        ? // Claude Code's own installer puts it in ~\.local\bin, which an app started from the Start menu may not have.
          withPath({ ...proxy, ...process.env, ...this.#node, STILLFAIL_DATA: data, EMBER_DATA: data }, [join(homedir(), ".local", "bin")], [])
        : { ...proxy, ...process.env, ...this.#node, STILLFAIL_DATA: data, EMBER_DATA: data, PATH: `${homedir()}/.local/bin:/opt/homebrew/bin:/usr/local/bin:${process.env.PATH ?? ""}:/usr/bin:/bin` },
      stdio: ["ignore", log, log],
      windowsHide: true,
    });
    this.#child = child;
    child.on("exit", (code) => {
      this.#child = null;
      if (code === HELD) {
        this.held = true;
        return;
      }
      if (this.#stopping) return;
      // One that ran a while starts again at once; one that keeps failing backs off.
      if (Date.now() - started > 60_000) this.#backoff = 1000;
      setTimeout(() => this.start(), this.#backoff);
      this.#backoff = Math.min(this.#backoff * 2, 30_000);
    });
  }

  /**
   * SIGTERM, which ends its runtimes first; SIGKILL if it has not ended in 25 s. On Windows both end the launcher at
   * once, and the station, its control pipe closed, stops by itself as it would have been told to (launcher.ts).
   */
  async stop(): Promise<void> {
    this.#stopping = true;
    const child = this.#child;
    if (!child) return;
    const ended = new Promise<void>((resolve) => child.once("exit", () => resolve()));
    child.kill("SIGTERM");
    const late = setTimeout(() => child.kill("SIGKILL"), 25_000);
    await ended;
    clearTimeout(late);
  }

  /** Joins the workspace a one-time token from 「添加 station」 is for. */
  enroll(origin: string, token: string): Promise<void> {
    return new Promise((resolve, reject) => {
      execFile(this.#bin, ["enroll", origin, token, "--data", this.data], { env: { ...process.env, ...this.#node } }, (error, _stdout, stderr) => {
        if (error) reject(new Error(stderr.trim() || error.message));
        else resolve();
      });
    });
  }
}
