// This machine's station, run by the app (docs/station-rust.md, 1.5): the release the app carries in its Resources
// (scripts/station-bundle.sh), started with the app, started again when it ends, stopped when the app quits. Its data
// is ~/.ember, as an installed station's is, so the machine is one station whichever runs it; when one is installed
// and running already (ember-station exits with HELD), the app leaves it be.
import { execFile, spawn, type ChildProcess } from "node:child_process";
import { existsSync, mkdirSync, openSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

/** ember-station's exit when another station runs the data directory (mesh/station/src/main.rs). */
const HELD = 3;

export class LocalStation {
  readonly data = join(homedir(), ".ember");
  readonly #bin: string;
  #child: ChildProcess | null = null;
  #stopping = false;
  #backoff = 1000;
  /** Another station runs this machine's data: this one is not started again until the app is. */
  held = false;

  /** `dir`: the release, ember/ of scripts/station-bundle.sh. */
  constructor(readonly dir: string) {
    this.#bin = join(dir, "mesh", "target", "release", "ember-station");
  }

  /** Whether the app carries a station (a build with SKIP_STATION=1 does not). */
  get carried(): boolean {
    return existsSync(this.#bin);
  }

  /** Whether this machine's station is in a workspace. */
  get enrolled(): boolean {
    return existsSync(join(this.data, "mesh", "cloud.json"));
  }

  start(): void {
    if (!this.carried || this.#child || this.#stopping || this.held) return;
    mkdirSync(this.data, { recursive: true });
    const log = openSync(join(this.data, "ember.log"), "a");
    const started = Date.now();
    const child = spawn(this.#bin, ["run", "--app", this.dir, "--node", join(this.dir, "node", "bin", "node"), "--data", this.data, "--with-parent"], {
      // Opened from Finder the app has launchd's short PATH; the agents it starts (Claude Code, Codex) are found on this
      // one, as an installed station's (cloud/src/install.ts).
      env: { ...process.env, EMBER_DATA: this.data, PATH: `${homedir()}/.local/bin:/opt/homebrew/bin:/usr/local/bin:${process.env.PATH ?? ""}:/usr/bin:/bin` },
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
