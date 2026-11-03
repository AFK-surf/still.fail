// What a person debugging an app on an iOS Simulator has beside its picture (docs/remote-screens.md "Simulators"): the
// logs of the apps installed on it and their restart, all simctl's. The log is `log stream` inside the device, started
// as it is first asked for and left running a while after (so what happens between two looks is there), its newest
// lines held here. Only apps a person installed log into it (their image is in the device's Containers), which leaves
// out the system's thousands of lines a second, and of those only what the app's own code says, Foundation's for it
// (NSLog) and any error: the frameworks inside it say hundreds of lines a second more. `print` goes to an app's stdout,
// not to the log, so it is not here.
import { type ChildProcess, spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdirSync } from "node:fs";
import { mkdtemp, open, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";

/// One line of an app's log, `seq` counting from the first this device's stream held.
export type SimLog = { seq: number; at: string; level: string; app: string; text: string };
/// An app a person installed on the device.
export type SimApp = { id: string; name: string; running: boolean };

/// What can be set of the device from a person's app, each as `simctl ui` calls it.
export type SimSettings = { appearance: string; textSize: string; recording: boolean; enrolled: boolean };
const APPEARANCES = ["light", "dark"];
const TEXT_SIZES = ["extra-small", "small", "medium", "large", "extra-large", "extra-extra-large", "extra-extra-extra-large", "accessibility-medium", "accessibility-large", "accessibility-extra-large", "accessibility-extra-extra-large", "accessibility-extra-extra-extra-large"];

export type Run = (file: string, args: string[]) => Promise<string>;
/// `log stream`'s process, its stdout read line by line.
/// `simctl io recordVideo`'s process.
export type Recorder = (args: string[]) => { started: Promise<void>; ended: Promise<void>; stop: () => void };
export type LogStream = (args: string[], line: (text: string) => void, ended: () => void) => { stop: () => void };

const HELD = 2000;
const SENT = 500;
/// How long the stream goes on after the last time it was asked for.
const IDLE_MS = 10 * 60_000;
const INSTALLED = '"/Containers/Bundle/Application/"';
const PREDICATE = `processImagePath CONTAINS ${INSTALLED} AND (senderImagePath CONTAINS ${INSTALLED} OR senderImagePath ENDSWITH "/Foundation" OR messageType == error OR messageType == fault)`;
const BUNDLE_ID = /^[A-Za-z0-9][A-Za-z0-9.-]*$/;
const URL_SCHEME = /^[A-Za-z][A-Za-z0-9+.-]*:\S*$/;
const MAX_URL = 8192;
const APP_DEPTH = 3;
const ENROLLED = "com.apple.BiometricKit.enrollmentChanged";
/// The panels of an iPhone Duo as `simctl io` numbers its displays (and its touches their targets: DTUHIDKeys).
const DISPLAY_COVER = 1;
const DISPLAY_INNER = 3;
/// The longest a recording goes on: one left running does not fill the disk (some 80 MB a minute).
const RECORD_MS = 10 * 60_000;
const RECORD_START_MS = 5_000;
const RECORD_STOP_MS = 15_000;
const TIDY_BAR = [
  "override",
  ...["--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3"],
  ...["--cellularMode", "active", "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100"],
];

/// The quarter turns clockwise a panel's picture is shown at, from `simctl io enumerate`'s words of it (as the helper's
/// SimulatorView.turnOf).
export function turnOf(said: string, panel: string): number {
  for (const block of said.split("Device Name: ").slice(1)) {
    if (!block.startsWith(`${panel}\n`)) continue;
    const line = block.split("\n").find((l) => l.includes("UI Orientation:"));
    if (line?.trimEnd().endsWith("Landscape Left")) return 1;
    if (line?.trimEnd().endsWith("Landscape Right")) return 3;
    if (line?.trimEnd().endsWith("Portrait Upside Down")) return 2;
    return 0;
  }
  return 0;
}

/// The movie at `file` said to be shown `turn` quarter turns clockwise (its video track's matrix): nothing encoded again.
export async function turnMovie(file: string, turn: number): Promise<boolean> {
  const f = await open(file, "r+");
  try {
    const { size } = await f.stat();
    if (size === 0) return false;
    if (turn === 0) return true;
    const head = async (at: number): Promise<[string, number, number]> => {
      const b = Buffer.alloc(16);
      await f.read(b, 0, 16, at);
      const short = b.readUInt32BE(0);
      const long = short === 1;
      return [b.toString("latin1", 4, 8), long ? Number(b.readBigUInt64BE(8)) : short === 0 ? size - at : short, long ? 16 : 8];
    };
    const find = async (name: string, from: number, to: number): Promise<[number, number, number] | null> => {
      for (let at = from; at + 8 <= to; ) {
        const [kind, length, skip] = await head(at);
        if (length < 8) return null;
        if (kind === name) return [at + skip, at + length, length];
        at += length;
      }
      return null;
    };
    const moov = await find("moov", 0, size);
    if (moov === null) return false;
    for (let at = moov[0]; at + 8 <= moov[1]; ) {
      const [kind, length, skip] = await head(at);
      if (length < 8) return false;
      if (kind === "trak") {
        const tkhd = await find("tkhd", at + skip, at + length);
        const mdia = await find("mdia", at + skip, at + length);
        const hdlr = mdia && (await find("hdlr", mdia[0], mdia[1]));
        const handler = Buffer.alloc(4);
        if (hdlr) await f.read(handler, 0, 4, hdlr[0] + 8);
        if (tkhd && handler.toString("latin1") === "vide") {
          const version = Buffer.alloc(1);
          await f.read(version, 0, 1, tkhd[0]);
          const matrix = tkhd[0] + (version[0] === 1 ? 52 : 40);
          const shape = Buffer.alloc(8);
          await f.read(shape, 0, 8, matrix + 36);
          const [w, h] = [shape.readUInt32BE(0), shape.readUInt32BE(4)];
          const one = 0x10000;
          // a b u, c d v, tx ty w: (x, y) goes to (ax + cy + tx, bx + dy + ty), in 16.16 but u, v and w
          const m = turn === 1 ? [0, one, 0, -one, 0, 0, h, 0] : turn === 2 ? [-one, 0, 0, 0, -one, 0, w, h] : [0, -one, 0, one, 0, 0, 0, w];
          const out = Buffer.alloc(36);
          m.forEach((v, i) => out.writeInt32BE(v, i * 4));
          out.writeInt32BE(0x40000000, 32);
          await f.write(out, 0, 36, matrix);
          return true;
        }
      }
      at += length;
    }
    return false;
  } finally {
    await f.close();
  }
}

/// The first .app under `dir`, at most `depth` folders down (an .ipa's in Payload, a build's zip with a folder round it).
async function appIn(dir: string, depth: number): Promise<string | null> {
  const entries = await readdir(dir, { withFileTypes: true });
  for (const e of entries) if (e.isDirectory() && e.name.endsWith(".app")) return join(dir, e.name);
  if (depth <= 0) return null;
  for (const e of entries) {
    if (!e.isDirectory() || e.name === "__MACOSX") continue;
    const found = await appIn(join(dir, e.name), depth - 1);
    if (found !== null) return found;
  }
  return null;
}

/// A line of `log stream --style ndjson` as a person reads it; null for what is not one (its own words at its start).
export function logOf(line: string): Omit<SimLog, "seq"> | null {
  let e: any;
  try {
    e = JSON.parse(line);
  } catch {
    return null;
  }
  if (typeof e?.eventMessage !== "string") return null;
  const image = typeof e.processImagePath === "string" ? e.processImagePath : "";
  return {
    at: typeof e.timestamp === "string" ? e.timestamp : "",
    level: typeof e.messageType === "string" ? e.messageType : "",
    app: image.slice(image.lastIndexOf("/") + 1),
    text: e.eventMessage,
  };
}

/// The apps a person installed, from `simctl listapps` (as JSON) and what `launchctl list` inside the device runs.
export function appsOf(installed: unknown, launchctl: string): SimApp[] {
  const running = new Set([...launchctl.matchAll(/UIKitApplication:([^\[\s]+)\[/g)].map((m) => m[1]!));
  const apps: SimApp[] = [];
  for (const [id, app] of Object.entries((installed ?? {}) as Record<string, any>)) {
    if (app?.ApplicationType !== "User") continue;
    const name = [app.CFBundleDisplayName, app.CFBundleName].find((n) => typeof n === "string" && n !== "");
    apps.push({ id, name: name ?? id, running: running.has(id) });
  }
  return apps.sort((a, b) => Number(b.running) - Number(a.running) || a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
}

const recorder: Recorder = (args) => {
  const child: ChildProcess = spawn(args[0]!, args.slice(1), { stdio: ["ignore", "pipe", "ignore"] });
  const ended = new Promise<void>((done) => {
    child.on("error", () => done());
    child.on("close", () => done());
  });
  const started = new Promise<void>((done) => {
    child.stdout!.setEncoding("utf8");
    child.stdout!.on("data", (chunk: string) => {
      if (chunk.includes("Recording started")) done();
    });
    void ended.then(done);
    wall.after(RECORD_START_MS, done);
  });
  return {
    started,
    ended,
    stop: () => {
      // (SIGINT is what ends it with its movie whole)
      child.kill("SIGINT");
      wall.after(RECORD_STOP_MS, () => void child.kill("SIGKILL"));
    },
  };
};

const logStream: LogStream = (args, line, ended) => {
  const child: ChildProcess = spawn(args[0]!, args.slice(1), { stdio: ["ignore", "pipe", "ignore"] });
  let rest = "";
  child.stdout!.setEncoding("utf8");
  child.stdout!.on("data", (chunk: string) => {
    const parts = (rest + chunk).split("\n");
    rest = parts.pop()!;
    for (const part of parts) line(part);
  });
  child.on("error", ended);
  child.on("close", ended);
  return { stop: () => void child.kill() };
};

/// One booted device's logs and apps.
export class SimDebug {
  readonly #simctl: string;
  readonly #udid: string;
  readonly #run: Run;
  readonly #stream: LogStream;
  readonly #picture: () => Promise<Uint8Array>;
  readonly #held: SimLog[] = [];
  #next = 0;
  #running: { stop: () => void } | null = null;
  #idle: (() => void) | null = null;
  #closed = false;
  readonly #record: Recorder;
  #recording: { child: ReturnType<Recorder>; folder: string; name: string; turn: number; limit: () => void } | null = null;

  /// `picture`: the device's screen as a view has it (a JPEG): not `simctl io`'s, which of a foldable's screens it picks
  /// is not the one in use (an iPhone Duo's: black).
  constructor(simctl: string, udid: string, run: Run, picture: () => Promise<Uint8Array>, stream: LogStream = logStream, record: Recorder = recorder) {
    this.#record = record;
    this.#simctl = simctl;
    this.#udid = udid;
    this.#run = run;
    this.#picture = picture;
    this.#stream = stream;
  }

  /// The lines after `after` (the newest of them if there are more than go at once), and where to ask from next.
  logs(after: number): { next: number; lines: SimLog[] } {
    this.#follow();
    const lines = this.#held.filter((l) => l.seq >= after);
    return { next: this.#next, lines: lines.slice(-SENT) };
  }

  async apps(): Promise<SimApp[]> {
    const [installed, launchctl] = await Promise.all([
      // listapps says an old-style plist, which only plutil reads, from its stdin here.
      this.#run("/bin/sh", ["-c", '"$0" listapps "$1" | plutil -convert json -o - -', this.#simctl, this.#udid]),
      this.#run(this.#simctl, ["spawn", this.#udid, "launchctl", "list"]),
    ]);
    return appsOf(JSON.parse(installed), launchctl);
  }

  /// Ends `app` if it runs, and starts it; false when it is no app a person installed here.
  async relaunch(app: string): Promise<boolean> {
    if (!BUNDLE_ID.test(app) || !(await this.apps()).some((a) => a.id === app)) return false;
    this.#follow();
    await this.#run(this.#simctl, ["launch", "--terminate-running-process", this.#udid, app]);
    return true;
  }

  async settings(): Promise<SimSettings> {
    const [appearance, textSize, enrolled] = await Promise.all([
      this.#run(this.#simctl, ["ui", this.#udid, "appearance"]),
      this.#run(this.#simctl, ["ui", this.#udid, "content_size"]),
      this.#run(this.#simctl, ["spawn", this.#udid, "notifyutil", "-g", ENROLLED]).catch(() => ""),
    ]);
    return { appearance: appearance.trim(), textSize: textSize.trim(), recording: this.#recording !== null, enrolled: enrolled.trim().endsWith(" 1") };
  }

  /// Sets one of them; false when it is no such setting or value.
  async setSetting(name: string, value: string): Promise<boolean> {
    const allowed = name === "appearance" ? APPEARANCES : name === "textSize" ? TEXT_SIZES : [];
    if (!allowed.includes(value)) return false;
    await this.#run(this.#simctl, ["ui", this.#udid, name === "appearance" ? "appearance" : "content_size", value]);
    return true;
  }

  /// Opens a link in it (its browser, or the app that takes it: a deep link); false when it is no URL.
  async openUrl(url: string): Promise<boolean> {
    if (url.length > MAX_URL || !URL_SCHEME.test(url)) return false;
    await this.#run(this.#simctl, ["openurl", this.#udid, url]);
    return true;
  }

  /// Puts it at `at` ("latitude,longitude"), or back to none (null); false when that is no place.
  async location(at: string | null): Promise<boolean> {
    if (at === null) {
      await this.#run(this.#simctl, ["location", this.#udid, "clear"]);
      return true;
    }
    const place = /^\s*(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)\s*$/.exec(at);
    if (place === null || Math.abs(Number(place[1])) > 90 || Math.abs(Number(place[2])) > 180) return false;
    await this.#run(this.#simctl, ["location", this.#udid, "set", `${place[1]},${place[2]}`]);
    return true;
  }

  /// Its status bar tidy, as App Store screenshots have it (9:41, full bars and battery), or as it really is.
  async statusBar(tidy: boolean): Promise<void> {
    await this.#run(this.#simctl, ["status_bar", this.#udid, ...(tidy ? TIDY_BAR : ["clear"])]);
  }

  /// A notification saying `text` to `app`; false when it is no app a person installed here or says nothing.
  async push(app: string, text: string): Promise<boolean> {
    if (text.trim() === "" || !BUNDLE_ID.test(app) || !(await this.apps()).some((a) => a.id === app)) return false;
    const file = join(tmpdir(), `stillfail-sim-${randomBytes(8).toString("hex")}.apns`);
    try {
      await writeFile(file, JSON.stringify({ aps: { alert: text, sound: "default" } }));
      await this.#run(this.#simctl, ["push", this.#udid, app, file]);
    } finally {
      await rm(file, { force: true });
    }
    return true;
  }

  /// Where a file to install on it goes up to (`install`): among the machine's temporary files, not Downloads, which macOS may
  /// keep simctl from reading.
  installFolder(): string {
    const folder = join(tmpdir(), "stillfail-sim-install");
    mkdirSync(folder, { recursive: true });
    return folder;
  }

  /// The app in `path` (an .ipa, or a .zip with a .app in it, in `installFolder`) installed and started, the file let go of:
  /// its bundle id; null when that is no such file or there is no app in it.
  async install(path: string): Promise<string | null> {
    if (dirname(resolve(path)) !== this.installFolder() || !/\.(ipa|zip)$/i.test(path) || basename(path).startsWith("-")) return null;
    const out = await mkdtemp(join(tmpdir(), "stillfail-sim-app-"));
    try {
      // (what does not unpack is no such file either)
      if (!(await this.#run("ditto", ["-x", "-k", path, out]).then(() => true, () => false))) return null;
      const app = await appIn(out, APP_DEPTH);
      if (app === null) return null;
      await this.#run(this.#simctl, ["install", this.#udid, app]);
      const id = JSON.parse(await this.#run("plutil", ["-convert", "json", "-o", "-", join(app, "Info.plist")])).CFBundleIdentifier;
      if (typeof id !== "string" || !BUNDLE_ID.test(id)) return null;
      await this.#run(this.#simctl, ["launch", "--terminate-running-process", this.#udid, id]);
      return id;
    } finally {
      await Promise.all([rm(out, { recursive: true, force: true }), rm(path, { force: true })]);
    }
  }

  /// Takes `app` a person installed off it; false when it is none.
  async uninstall(app: string): Promise<boolean> {
    if (!BUNDLE_ID.test(app) || !(await this.apps()).some((a) => a.id === app)) return false;
    await this.#run(this.#simctl, ["uninstall", this.#udid, app]);
    return true;
  }

  /// Face ID or Touch ID, whichever it has: enrolled or not, or the face or finger shown just now to what asks for it (a first
  /// asking waits on the system's own question first). False when it is no such thing. By what BiometricKit listens for in the device.
  async biometrics(what: string): Promise<boolean> {
    const notify = (...args: string[]) => this.#run(this.#simctl, ["spawn", this.#udid, "notifyutil", ...args]);
    if (what === "enrol" || what === "unenrol") {
      await notify("-s", ENROLLED, what === "enrol" ? "1" : "0");
      await notify("-p", ENROLLED);
      return true;
    }
    if (what !== "match" && what !== "nomatch") return false;
    await notify("-p", `com.apple.BiometricKit_Sim.pearl.${what}`);
    return true;
  }

  /// Starts recording its screen, `panel`'s where it has two ("inner" or "cover"); what it started before goes on.
  async recordStart(panel: string | null): Promise<void> {
    if (this.#recording !== null) return;
    const folder = join(tmpdir(), "stillfail-sim-recordings");
    await rm(folder, { recursive: true, force: true });
    mkdirSync(folder, { recursive: true });
    const name = `${this.#udid.slice(0, 8)}-${randomBytes(4).toString("hex")}.mp4`;
    const file = join(folder, name);
    const turn = panel === "inner" ? turnOf(await this.#run(this.#simctl, ["io", this.#udid, "enumerate"]), "primary-1") : 0;
    const display = panel === null ? [] : [`--display=${panel === "inner" ? DISPLAY_INNER : DISPLAY_COVER}`];
    const child = this.#record([this.#simctl, "io", this.#udid, "recordVideo", "--codec=h264", ...display, "--force", file]);
    const limit = wall.after(RECORD_MS, () => child.stop());
    this.#recording = { child, folder, name, turn, limit };
    await child.started;
  }

  get recording(): boolean {
    return this.#recording !== null;
  }

  /// Ends the recording and says where its movie is, the drive's way (`root`, `path`); null when none goes on.
  async recordStop(): Promise<{ root: string; path: string } | null> {
    const r = this.#recording;
    if (r === null) return null;
    this.#recording = null;
    r.limit();
    r.child.stop();
    await r.child.ended;
    if (!(await turnMovie(join(r.folder, r.name), r.turn).catch(() => false))) throw new Error("nothing was recorded");
    return { root: r.folder, path: r.name };
  }

  /// The device's screen as a PNG, in its own pixels.
  async screenshot(): Promise<Buffer> {
    const base = join(tmpdir(), `stillfail-sim-${randomBytes(8).toString("hex")}`);
    try {
      await writeFile(`${base}.jpg`, await this.#picture());
      await this.#run("sips", ["-s", "format", "png", `${base}.jpg`, "--out", `${base}.png`]);
      return await readFile(`${base}.png`);
    } finally {
      await Promise.all([rm(`${base}.jpg`, { force: true }), rm(`${base}.png`, { force: true })]);
    }
  }

  /// The device shut down (or the station stops).
  close() {
    this.#closed = true;
    this.#recording?.limit();
    this.#recording?.child.stop();
    this.#recording = null;
    this.#idle?.();
    this.#running?.stop();
    this.#running = null;
  }

  #follow() {
    if (this.#closed) return;
    this.#idle?.();
    this.#idle = wall.after(IDLE_MS, () => {
      this.#running?.stop();
      this.#running = null;
    });
    if (this.#running !== null) return;
    const args = [this.#simctl, "spawn", this.#udid, "log", "stream", "--style", "ndjson", "--level", "debug", "--predicate", PREDICATE];
    const running = this.#stream(args, (line) => this.#line(line), () => {
      // Its own end, not one asked for: the next look starts it again.
      if (this.#running === running) this.#running = null;
    });
    this.#running = running;
    log.info("screens", "a simulator's log followed", { udid: this.#udid });
  }

  #line(line: string) {
    const said = logOf(line);
    if (said === null) return;
    this.#held.push({ seq: this.#next++, ...said });
    if (this.#held.length > HELD) this.#held.splice(0, this.#held.length - HELD);
  }
}
