// A screen of its own on the phone for each chat it is lent to (2026-11-04,
// user: 「会有一个虚拟屏跑 app 不影响我自己操作」): a virtual display, made and held by a run of scrcpy's server on the
// phone (android.ts SERVER_FILE, `new_display`), in the grant's adb server. The agent starts its apps there
// (`am start --display`), touches it (`input -d`) and takes its pictures (`screencap -d`, SurfaceFlinger's id of it),
// while the person uses the phone's own screen. It is made as phone_use says how the phone is reached, and goes as the
// grant ends, as nothing of the agent's has used the phone for IDLE_MS (its apps closed with it: they do not move onto
// the person's screen), or as the phone's link goes. Its pictures are encoded small and seldom, and read only to keep
// it up: they are no one's.
import { type ChildProcess, spawn } from "node:child_process";
import { randomInt } from "node:crypto";
import { statSync } from "node:fs";
import net from "node:net";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { platform } from "../platform/index.ts";
import { adbEnv, SERVER_FILE, SERVER_VERSION, sizeOf } from "../screens/android.ts";
import { DISPLAY_MARK } from "./activity.ts";

/// How long scrcpy has to make the display.
const START_TIMEOUT = 20_000;
/// How long an adb command of the station's is given.
const ADB_TIMEOUT = 15_000;
/// A display nothing of the agent's used the phone for this long is closed.
export const IDLE_MS = 10 * 60_000;
/// How often displays are looked at for that.
const IDLE_CHECK = 60_000;
/// What scrcpy encodes of it, only to keep it up (the link to the phone carries it): small, seldom.
const KEEP_SIDE = 320, KEEP_FPS = 1, KEEP_RATE = 100_000;

/// A display up now: Android's id of it (`--display`, `-d` of `input`) and the one `screencap -d` takes (SurfaceFlinger's
/// from Android 13 or so; before, as on an Android 12 emulator, Android's own), its size and density.
export type Display = { id: number; surface: string; width: number; height: number; density: number };

/// `New display: 1080x2400/420 (id=2)`, as scrcpy says it at log level info.
export function displayOf(said: string): { id: number; width: number; height: number; density: number } | null {
  const m = /New display: (\d+)x(\d+)\/(\d+) \(id=(\d+)\)/.exec(said);
  return m ? { width: Number(m[1]), height: Number(m[2]), density: Number(m[3]), id: Number(m[4]) } : null;
}

/// `wm density`: the override over the physical.
export function densityOf(wm: string): number {
  const m = /Override density: (\d+)/.exec(wm) ?? /Physical density: (\d+)/.exec(wm);
  return m ? Number(m[1]) : 0;
}

/// SurfaceFlinger's id of Android's display `id`: its unique id from `dumpsys display`, found in `dumpsys SurfaceFlinger
/// --display-id`'s lines (`Display 11529215046400789845 (Virtual display): displayName="scrcpy" uniqueId="virtual:…"`);
/// where they name none (ColorOS 17, 2026-11-04: `Display 11529215049903610350 (Virtual display): displayName="scrcpy"`),
/// by its layer stack in `dumpsys SurfaceFlinger` (`flinger()`: `Display 115… (virtual, "scrcpy")` then `layerFilter={layerStack=12 …`).
export async function surfaceOf(displays: string, ids: string, id: number, flinger: () => Promise<string>): Promise<string | null> {
  const info = displays.split("\n").find((l) => l.includes("mBaseDisplayInfo=") && new RegExp(`\\bdisplayId ${id},`).test(l));
  if (info === undefined) return null;
  const unique = /uniqueId "([^"]+)"/.exec(info)?.[1];
  const line = unique ? ids.split("\n").find((l) => l.includes(`uniqueId="${unique}"`)) : undefined;
  if (line !== undefined) return /^Display (\d+)/.exec(line.trim())?.[1] ?? null;
  const stack = /layerStack (\d+)/.exec(info)?.[1];
  if (stack === undefined || !/\(Virtual display\)/.test(ids) || ids.includes("uniqueId=")) return null;
  let at: string | null = null;
  for (const l of (await flinger()).split("\n")) {
    const display = /^Display (\d+) \(virtual\b/.exec(l.trim());
    if (display) at = display[1]!;
    else if (/^\S/.test(l)) at = null;
    else if (at !== null && new RegExp(`layerFilter=\\{layerStack=${stack}\\b`).test(l)) return at;
  }
  return null;
}

/// The root tasks `am stack list` says are on display `id` (`RootTask id=7723 bounds=[…] displayId=13 userId=0`).
export function rootTasksOn(list: string, id: number): number[] {
  return [...list.matchAll(/^(?:RootTask|Stack) id=(\d+)\b.*\bdisplayId=(\d+)/gm)].filter((m) => Number(m[2]) === id).map((m) => Number(m[1]));
}

type Held = {
  grant: string;
  owner: string;
  title: string;
  display: Display;
  opened: number;
  child: ChildProcess;
  socket: net.Socket;
  forward: { port: number; adb: string[] };
  closing: boolean;
};

export type DisplaysOptions = {
  adb: () => string | null;
  /// When a grant was last used by its agent (grants.ts `lastUsedAt`), null when it is not live.
  usedAt: (grant: string) => number | null;
  /// The displays of `owner`'s phone changed (one opened or closed).
  changed: (owner: string) => void;
  file?: string;
  idleMs?: number;
};

export class PhoneDisplays {
  readonly #o: DisplaysOptions;
  readonly #file: string;
  readonly #held = new Map<string, Held>();
  readonly #opening = new Map<string, Promise<Display>>();
  #check: (() => void) | null = null;
  #closed = false;

  constructor(o: DisplaysOptions) {
    this.#o = o;
    this.#file = o.file ?? SERVER_FILE;
  }

  /// Grant `grant`'s display, made if it has none (`port`: its adb server, `serial`: the phone in it).
  open(grant: string, owner: string, title: string, port: number, serial: string): Promise<Display> {
    const held = this.#held.get(grant);
    if (held !== undefined && !held.closing) {
      held.title = title;
      return Promise.resolve(held.display);
    }
    let opening = this.#opening.get(grant);
    if (opening === undefined) {
      opening = this.#start(grant, owner, title, ["-P", String(port), "-s", serial]).finally(() => this.#opening.delete(grant));
      this.#opening.set(grant, opening);
    }
    return opening;
  }

  /// The titles of the chats whose displays are up on `owner`'s phone.
  titles(owner: string): string[] {
    return [...this.#held.values()].filter((h) => h.owner === owner && !h.closing).map((h) => h.title);
  }

  /// Whether grant `grant` has a display up.
  has(grant: string): boolean {
    const h = this.#held.get(grant);
    return h !== undefined && !h.closing;
  }

  async #start(grant: string, owner: string, title: string, server: string[]): Promise<Display> {
    const adb = this.#o.adb();
    if (adb === null) throw new Error("adb is not on this machine");
    const run = (args: string[]) => adbRun(adb, [...server, ...args]);
    const shell = (command: string) => run(["shell", `${DISPLAY_MARK} ${command}`]);
    const sdk = Number((await shell("getprop ro.build.version.sdk")).trim());
    const size = sizeOf(await shell("wm size"));
    const density = densityOf(await shell("wm density"));
    if (size.width === 0 || density === 0) throw new Error("the phone did not say its screen's size");
    const scid = randomInt(1, 0x7fffffff).toString(16).padStart(8, "0");
    // Kept on the phone for the next (the link to it may carry 0.1 MB/s): put again when it is not the same.
    const jar = `/data/local/tmp/stillfail-display-${SERVER_VERSION}.jar`;
    const there = Number((await shell(`stat -c %s ${jar} 2>/dev/null`).catch(() => "")).trim());
    if (there !== statSync(this.#file).size) await run(["push", this.#file, jar]);
    const port = Number((await run(["forward", "tcp:0", `localabstract:scrcpy_${scid}`])).trim());
    if (!Number.isInteger(port) || port <= 0) throw new Error("adb gave no port for the display");
    const forward = { port, adb: [adb, ...server] };
    const args = [
      `scid=${scid}`, "log_level=info", "audio=false", "control=false", "tunnel_forward=true", "cleanup=false", "video_codec=h264",
      `max_size=${KEEP_SIDE}`, `max_fps=${KEEP_FPS}`, `video_bit_rate=${KEEP_RATE}`, "power_on=false",
      `new_display=${size.width}x${size.height}/${density}`,
      // No keyboard shown for it, on it or on the person's screen: the agent types by key events (`input text`), which need
      // none. Its keyboard on it (`local`) took the phone's one keyboard over to it, and a field the person tapped on
      // their own screen meanwhile drew it there, out of their sight, until a fold changed the screens (2026-11-05: the
      // person's keyboard gone while a chat's display was up). Android 12 refuses a policy of a display that is not
      // trusted, as every one of the shell's is there.
      ...(sdk >= 33 ? ["display_ime_policy=hide"] : []),
    ];
    const child = spawnAdb(adb, [...server, "shell", `${DISPLAY_MARK} CLASSPATH=${jar} app_process / com.genymobile.scrcpy.Server ${SERVER_VERSION} ${args.join(" ")}`]);
    let said = "";
    child.stdout?.on("data", (d) => (said += d));
    child.stderr?.on("data", (d) => (said += d));
    let ended = false;
    child.on("close", () => (ended = true));
    let socket: net.Socket | null = null;
    const fail = (why: string): never => {
      socket?.destroy();
      child.kill();
      void adbRun(adb, [...server, "forward", "--remove", `tcp:${port}`]).catch(() => {});
      throw new Error(said.trim().split("\n").slice(-3).join(" ") || why);
    };
    // (a forward tunnel takes a connection before anything listens: the byte the program sends first says it does)
    const until = wall.now() + START_TIMEOUT;
    while (socket === null) {
      if (ended) fail("scrcpy ended");
      if (wall.now() > until) fail("scrcpy did not start");
      const s = await connect(port).catch(() => null);
      if (s !== null && (await firstOf(s))) {
        socket = s;
        break;
      }
      s?.destroy();
      await wall.sleep(100);
    }
    // Read only to keep it flowing (scrcpy blocks on a full socket).
    socket.on("data", () => {});
    socket.on("error", () => {});
    socket.resume();
    let made = displayOf(said);
    while (made === null) {
      if (ended) fail("scrcpy ended");
      if (wall.now() > until) fail("scrcpy made no display");
      await wall.sleep(100);
      made = displayOf(said);
    }
    const surface = await surfaceOf(await shell("dumpsys display").catch(() => ""), await shell("dumpsys SurfaceFlinger --display-id").catch(() => ""), made.id,
      () => shell("dumpsys SurfaceFlinger").catch(() => ""));
    const display: Display = { ...made, surface: surface ?? String(made.id) };
    const held: Held = { grant, owner, title, display, opened: wall.now(), child, socket, forward, closing: false };
    this.#held.set(grant, held);
    const gone = () => void this.#gone(held);
    child.on("close", gone);
    socket.on("close", gone);
    socket.on("error", gone);
    // (ended while it was looked at)
    if (this.#closed || ended || socket.destroyed) {
      gone();
      throw new Error(this.#closed ? "the station is stopping" : said.trim().split("\n").slice(-3).join(" ") || "scrcpy ended");
    }
    log.info("adb", "a chat's display made on the phone", { grant, id: made.id, surface, size: `${made.width}x${made.height}` });
    this.#watch();
    this.#o.changed(owner);
    return display;
  }

  /// Done once its apps are closed and scrcpy is ended (the grant's adb server is still needed till then).
  #gone(held: Held): Promise<void> {
    if (this.#held.get(held.grant) !== held) return Promise.resolve();
    this.#held.delete(held.grant);
    held.closing = true;
    const [adb, ...server] = held.forward.adb;
    const shell = (command: string) => adbRun(adb!, [...server, "shell", `${DISPLAY_MARK} ${command}`]);
    // Its apps closed before it: left to Android as the display goes, ColorOS's Settings (its activities arranged by
    // another of its processes) stayed half-removed, in the recents and on a display the phone kept (2026-11-04).
    const closing = held.child.exitCode === null && !held.socket.destroyed
      ? shell("am stack list").then((list) => {
        const tasks = rootTasksOn(list, held.display.id);
        return tasks.length === 0 ? "" : shell(tasks.map((t) => `am stack remove ${t}`).join("; "));
      })
      : Promise.resolve("");
    const ended = closing.catch(() => "").then(() => {
      held.socket.destroy();
      held.child.kill();
      return adbRun(adb!, [...server, "forward", "--remove", `tcp:${held.forward.port}`]).then(() => {}, () => {});
    });
    log.info("adb", "a chat's display closed", { grant: held.grant });
    this.#o.changed(held.owner);
    if (this.#held.size === 0) {
      this.#check?.();
      this.#check = null;
    }
    return ended;
  }

  /// Grant `grant`'s display closed (the grant ended, handed back); its apps close with it. Done when the phone is
  /// through with it: the grant's adb server is stopped only then.
  close(grant: string): Promise<void> {
    const held = this.#held.get(grant);
    return held === undefined ? Promise.resolve() : this.#gone(held);
  }

  #watch() {
    if (this.#check !== null) return;
    const tick = () => {
      this.#check = wall.after(IDLE_CHECK, tick);
      this.idle();
    };
    this.#check = wall.after(IDLE_CHECK, tick);
  }

  /// The displays whose grants nothing of the agent's used for IDLE_MS (nor since they were made) closed.
  idle() {
    const now = wall.now();
    const most = this.#o.idleMs ?? IDLE_MS;
    for (const held of [...this.#held.values()]) {
      const used = this.#o.usedAt(held.grant);
      if (used === null || now - Math.max(used, held.opened) >= most) void this.#gone(held);
    }
  }

  closeAll() {
    this.#closed = true;
    for (const held of [...this.#held.values()]) void this.#gone(held);
  }
}

function spawnAdb(path: string, args: string[]): ChildProcess {
  const env = adbEnv();
  const r = platform.runnable(path, args, env);
  return spawn(r.file, r.args, { windowsHide: true, windowsVerbatimArguments: r.windowsVerbatimArguments, env });
}

function adbRun(path: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawnAdb(path, args);
    let out = "", err = "";
    const stop = wall.after(ADB_TIMEOUT, () => child.kill());
    child.stdout?.on("data", (d) => (out += d));
    child.stderr?.on("data", (d) => (err += d));
    child.on("error", (e) => (stop(), reject(e)));
    child.on("close", (code) => {
      stop();
      if (code === 0) resolve(out);
      else reject(new Error(err.trim() || `adb ended with ${code}`));
    });
  });
}

function connect(port: number): Promise<net.Socket> {
  return new Promise((resolve, reject) => {
    const socket = net.connect(port, "127.0.0.1");
    socket.once("connect", () => (socket.off("error", reject), resolve(socket)));
    socket.once("error", reject);
  });
}

/// Whether a socket says something before it ends (it is paused after).
function firstOf(socket: net.Socket): Promise<boolean> {
  return new Promise((resolve) => {
    const settled = (got: boolean) => {
      socket.pause();
      socket.off("data", data);
      socket.off("close", none);
      socket.off("error", none);
      resolve(got);
    };
    const data = () => settled(true);
    const none = () => settled(false);
    socket.on("data", data);
    socket.on("close", none);
    socket.on("error", none);
  });
}
