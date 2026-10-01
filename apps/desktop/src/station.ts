// This machine's station, run by the app (docs/station-rust.md, 1.5): the release the app carries in its Resources
// (scripts/station-bundle.sh), started with the app, started again when it ends, stopped when the app quits. Its data
// is ~/.stillfail, as an installed station's is, so the machine is one station whichever runs it; when one is installed
// and running already (stillfail-station exits with HELD), the app leaves it be. A machine that ran it before the
// rename has it in ~/.ember: the station moves it to ~/.stillfail as it starts (mesh/app/src/former.rs).
import { execFile, spawn, type ChildProcess } from "node:child_process";
import { existsSync, lstatSync, mkdirSync, openSync, readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

/** stillfail-station's exit when another station runs the data directory (mesh/station/src/main.rs). */
const HELD = 3;

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
  #stopping = false;
  #backoff = 1000;
  /** Another station runs this machine's data: this one is not started again until the app is. */
  held = false;

  /** `dir`: the release, stillfail/ of scripts/station-bundle.sh. */
  constructor(readonly dir: string) {
    this.#bin = join(dir, "mesh", "target", "release", "stillfail-station");
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
    if (!this.carried || this.#child || this.#stopping || this.held) return;
    const data = this.data;
    mkdirSync(data, { recursive: true });
    const log = openSync(join(data, "stillfail.log"), "a");
    const started = Date.now();
    const child = spawn(this.#bin, ["run", "--app", this.dir, "--data", data, "--with-parent"], {
      // Opened from Finder the app has launchd's short PATH; the agents it starts (Claude Code, Codex) are found on this
      // one, as an installed station's (cloud/src/install.ts).
      env: { ...process.env, STILLFAIL_DATA: data, EMBER_DATA: data, PATH: `${homedir()}/.local/bin:/opt/homebrew/bin:/usr/local/bin:${process.env.PATH ?? ""}:/usr/bin:/bin` },
      stdio: ["ignore", log, log],
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

  /** SIGTERM, which ends its runtimes first; SIGKILL if it has not ended in 25 s. */
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
      execFile(this.#bin, ["enroll", origin, token, "--data", this.data], (error, _stdout, stderr) => {
        if (error) reject(new Error(stderr.trim() || error.message));
        else resolve();
      });
    });
  }
}
