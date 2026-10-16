// still.fail Helper (station/native/helper, docs/station-ts-native.md §4): the station's macOS app for what macOS
// grants an app (Screen Recording, Accessibility), so that a grant, which takes effect only once the process holding
// it starts again, restarts this app and never the station. LaunchServices starts it (`open -n -g`), which makes it its
// own responsible process: the one macOS asks about, the one a person drags into System Settings. A process the
// station started would be the launcher's.
//
// The release's app is copied to <data>/helper first (a path of its own, outside any other app: the desktop app has
// the station inside it), anew when its code changed. The station talks to it on a Unix socket there, each connection
// one request: a JSON line with the token in <data>/helper/token (0600; the app reads it there too, so the app macOS
// starts again itself after a grant, its Quit & Reopen, finds the station), answered with a JSON line, or with a
// stream (`screen.view`). One app a directory: a lock there ends any second one.
//
// The station watches the app it started (a connection held open, `watch`): when the app ends without being asked
// (macOS's Quit & Reopen when it did not reopen it, a crash), the station waits a moment for it to come back by itself
// (its own restart, macOS's reopen), then starts it again; `onBack` is told either way (the desktop puts its window up
// again when a grant is still missing).
import { execFile } from "node:child_process";
import { randomBytes } from "node:crypto";
import { cpSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import net from "node:net";
import { basename, join } from "node:path";
import { fileURLToPath } from "node:url";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";

export const HELPER_APP = "still.fail Helper.app";
/// How long a started app has to answer, at most.
const START_MS = 15_000;
/// How long an app that ended is given to come back by itself before the station starts it.
const COMING_BACK_MS = 3_000;
/// Started again this many times within REVIVALS_MS without staying up: the station stops trying (until it is needed).
const REVIVALS = 5;
const REVIVALS_MS = 60_000;

/// The release's helper app: STILLFAIL_HELPER, or beside the station's code in a release.
export function helperApp(env: NodeJS.ProcessEnv = process.env): string | null {
  const candidates = [env.STILLFAIL_HELPER, fileURLToPath(new URL(`./${HELPER_APP}`, import.meta.url))];
  return candidates.find((p) => p && existsSync(join(p, "Contents/Info.plist"))) ?? null;
}

/// How the app is started: by LaunchServices, a new instance, in the background, with its socket and token.
export type Launch = (app: string, env: Record<string, string>) => Promise<void>;
export const openApp: Launch = (app, env) =>
  new Promise((resolve, reject) => {
    const args = ["-n", "-g", ...Object.entries(env).flatMap(([k, v]) => ["--env", `${k}=${v}`]), app];
    execFile("open", args, { timeout: START_MS }, (error) => (error ? reject(error) : resolve()));
  });

/// The files that say an installed copy is the release's: its code and its signature.
const CODE = ["Contents/MacOS/stillfail-helper", "Contents/Info.plist", "Contents/_CodeSignature/CodeResources"];

/// The release's app copied into `dir`, unless the copy there is the same; whether it was copied.
export function install(app: string, dir: string): { path: string; replaced: boolean } {
  const path = join(dir, basename(app));
  const same = CODE.every((f) => {
    try {
      return readFileSync(join(app, f)).equals(readFileSync(join(path, f)));
    } catch {
      return false;
    }
  });
  if (same) return { path, replaced: false };
  mkdirSync(dir, { recursive: true });
  const staging = join(dir, `.staging-${randomBytes(4).toString("hex")}`);
  cpSync(app, staging, { recursive: true, verbatimSymlinks: true });
  const old = `${path}.old-${randomBytes(4).toString("hex")}`;
  if (existsSync(path)) renameSync(path, old);
  renameSync(staging, path);
  rmSync(old, { recursive: true, force: true });
  return { path, replaced: true };
}

export class HelperApp {
  readonly app: string;
  readonly dir: string;
  readonly socket: string;
  readonly #launch: Launch;
  #token: string | null;
  #starting: Promise<void> | null = null;
  #watch: net.Socket | null = null;
  #quitting = false;
  #revivals: number[] = [];
  readonly #onBack: (() => void) | undefined;

  constructor(options: { app: string; dir: string; launch?: Launch; onBack?: () => void }) {
    this.app = options.app;
    this.dir = options.dir;
    this.socket = join(options.dir, "helper.sock");
    this.#launch = options.launch ?? openApp;
    this.#onBack = options.onBack;
    try {
      this.#token = readFileSync(join(options.dir, "token"), "utf8").trim() || null;
    } catch {
      this.#token = null;
    }
  }

  /// A request's answer (`op` and its fields), the app started first when it is not up.
  async request(op: Record<string, unknown>): Promise<any> {
    await this.ensure();
    return this.#ask(op);
  }

  /// A connection for a stream (`screen.view`): its request written, the rest the caller's.
  async connect(op: Record<string, unknown>): Promise<net.Socket> {
    await this.ensure();
    const socket = await this.#dial();
    socket.write(`${JSON.stringify({ ...op, token: this.#token })}\n`);
    return socket;
  }

  /// The app up and answering: started (or started again) when not.
  ensure(): Promise<void> {
    this.#quitting = false;
    this.#starting ??= this.#ensure()
      .then(() => this.#watching())
      .finally(() => (this.#starting = null));
    return this.#starting;
  }

  /// The app watched: its end (not asked for) starts it again.
  async #watching() {
    if (this.#watch !== null) return;
    const socket = await this.#dial();
    this.#watch = socket;
    socket.on("error", () => {});
    // Read (its answer, then nothing): a socket not read never hears that the other end went.
    socket.on("data", () => {});
    socket.on("close", () => {
      if (this.#watch === socket) this.#watch = null;
      if (!this.#quitting) void this.#revive();
    });
    socket.write(`${JSON.stringify({ op: "watch", token: this.#token })}\n`);
  }

  /// The app ended by itself: back by itself in a moment, or started again.
  async #revive() {
    const now = wall.now();
    this.#revivals = [...this.#revivals.filter((t) => now - t < REVIVALS_MS), now];
    if (this.#revivals.length > REVIVALS) {
      log.warn("helper", "still.fail Helper keeps ending; not started again until it is needed");
      return;
    }
    try {
      await this.back(COMING_BACK_MS).catch(async () => {
        log.info("helper", "still.fail Helper ended; starting it again");
        await this.ensure();
      });
      await this.#watching();
      this.#onBack?.();
    } catch (error) {
      log.warn("helper", "still.fail Helper not started again", { error: (error as Error).message });
    }
  }

  async #ensure() {
    const { path, replaced } = install(this.app, this.dir);
    const up = await this.#hello();
    // Its code changed: the one running is the old one.
    if (up && replaced) await this.#ask({ op: "quit" }).catch(() => {});
    else if (up) return;
    // The token stays what it is: an app started by macOS itself reads it beside it.
    if (this.#token === null) {
      const token = randomBytes(32).toString("hex");
      writeFileSync(join(this.dir, "token"), token, { mode: 0o600 });
      this.#token = token;
    }
    rmSync(this.socket, { force: true });
    log.info("helper", "starting still.fail Helper", { app: path });
    await this.#launch(path, { STILLFAIL_HELPER_SOCKET: this.socket, STILLFAIL_HELPER_TOKEN: this.#token });
    await this.back();
  }

  /// Until it answers again (started, or starting itself again for a grant), at most `ms`.
  async back(ms = START_MS): Promise<void> {
    const until = wall.now() + ms;
    while (!(await this.#hello())) {
      if (wall.now() > until) throw new Error("still.fail Helper did not start");
      await wall.sleep(100);
    }
  }

  async #hello(): Promise<boolean> {
    if (this.#token === null || !existsSync(this.socket)) return false;
    try {
      return (await this.#ask({ op: "hello" }))?.ok === true;
    } catch {
      return false;
    }
  }

  #dial(): Promise<net.Socket> {
    return new Promise((resolve, reject) => {
      const socket = net.createConnection(this.socket);
      socket.once("connect", () => {
        socket.off("error", reject);
        resolve(socket);
      });
      socket.once("error", reject);
    });
  }

  /// One request on a connection of its own: its answer line.
  async #ask(op: Record<string, unknown>): Promise<any> {
    const socket = await this.#dial();
    return new Promise((resolve, reject) => {
      let got = "";
      socket.setEncoding("utf8");
      socket.on("data", (chunk: string) => {
        got += chunk;
        const at = got.indexOf("\n");
        if (at < 0) return;
        socket.destroy();
        try {
          const answer = JSON.parse(got.slice(0, at));
          if (typeof answer?.error === "string") reject(new Error(answer.error));
          else resolve(answer);
        } catch (e) {
          reject(e as Error);
        }
      });
      socket.on("error", reject);
      socket.on("close", () => reject(new Error("still.fail Helper closed the connection")));
      socket.write(`${JSON.stringify({ ...op, token: this.#token })}\n`);
    });
  }

  /// The station stopping: the app ends too (started again when next needed).
  async quit() {
    this.#quitting = true;
    if (await this.#hello()) await this.#ask({ op: "quit" }).catch(() => {});
    this.#watch?.destroy();
    this.#watch = null;
  }
}
