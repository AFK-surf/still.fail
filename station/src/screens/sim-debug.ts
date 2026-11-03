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
import { mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";

/// One line of an app's log, `seq` counting from the first this device's stream held.
export type SimLog = { seq: number; at: string; level: string; app: string; text: string };
/// An app a person installed on the device.
export type SimApp = { id: string; name: string; running: boolean };

/// What can be set of the device from a person's app, each as `simctl ui` calls it.
export type SimSettings = { appearance: string; textSize: string };
const APPEARANCES = ["light", "dark"];
const TEXT_SIZES = ["extra-small", "small", "medium", "large", "extra-large", "extra-extra-large", "extra-extra-extra-large", "accessibility-medium", "accessibility-large", "accessibility-extra-large", "accessibility-extra-extra-large", "accessibility-extra-extra-extra-large"];

export type Run = (file: string, args: string[]) => Promise<string>;
/// `log stream`'s process, its stdout read line by line.
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
const TIDY_BAR = [
  "override",
  ...["--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3"],
  ...["--cellularMode", "active", "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100"],
];

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

  /// `picture`: the device's screen as a view has it (a JPEG): not `simctl io`'s, which of a foldable's screens it picks
  /// is not the one in use (an iPhone Duo's: black).
  constructor(simctl: string, udid: string, run: Run, picture: () => Promise<Uint8Array>, stream: LogStream = logStream) {
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
    const [appearance, textSize] = await Promise.all([
      this.#run(this.#simctl, ["ui", this.#udid, "appearance"]),
      this.#run(this.#simctl, ["ui", this.#udid, "content_size"]),
    ]);
    return { appearance: appearance.trim(), textSize: textSize.trim() };
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
