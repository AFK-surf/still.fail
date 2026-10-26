// Which versions this station and the machine's runtimes (Claude Code, Codex) are, whether newer ones are out, and
// updating them from the pages (the Rust station's updates.rs, whose rules this keeps):
// - The station: its release says its version in BUILD (`0.1.<n>`); the latest is what still.fail cloud serves as
//   releases/station.json, or on the test channel (`updateChannel: "beta"` in config.json; a release installed from the
//   beta and not told otherwise is on it) releases/station-beta.json, only as its signature verifies (signed.ts,
//   docs/release-signing.md: a feed that does not is no newer release). Switched back from the beta, the older stable
//   release is offered as going back (`downgrade`), only then. It is updated as `stillfail update` does (release.ts):
//   by the installer this release carries, told what the new one must hash to, run apart from the station; only a
//   release the installer put in <data>/app is (the desktop app's comes with the desktop app, a clone's with the clone). With `autoUpdate: true` it does so by itself once the
//   station has been quiet a while (never back from the beta, and a version it already went for, not again).
// - Claude Code and Codex: `--version`, and the latest their npm packages say (Devin: its installer's manifest); updated
//   the way each was installed.
//   Cursor is no command: its SDK's package, in the station's own npm prefix (agents/cursor.ts), its version the package's.
//   Running agents go on with what they started with; the next process starts the new one.
// - Software wired in after (`add`): the packages of the modules the station installs itself (modules/packages.ts),
//   read when the rest is, a line each after the others'.
//
// The TS release (docs/station-ts-native.md) is updated by the same files as the Rust one was:
// run/update.started (this side's, so the process that runs after a handover or restart follows the update to its
// end), run/update.step (download | handoff | drain | restart, the installer's), run/update.log and run/update.exit,
// and the installer is given STILLFAIL_CHANNEL, STILLFAIL_DATA and EMBER_DATA as it was (and now what release.ts
// gives it). Where it
// differs (see also the report in the station-ts work):
// - The release is `--app` (Paths.app), not two up from dist/admin; BUILD and CHANNEL are read from it the same way.
// - The installer's handoff (swap <data>/app, SIGUSR2 to the pid in run/station.json) reaches the launcher, which
//   starts a new Node from the swapped-in <app>/node/bin/node <app>/station/main.js and lets this one go; the launcher
//   binary itself is not replaced (pid kept: that is what the installer checks). The new Node follows update.started
//   as the Rust binary did after exec. The old Node never sees update.exit (written after the handover).
// - The installer is started in a session of its own (Node's `detached`, setsid) rather than a process group of its
//   own: either way launchd/systemd stopping the station does not take it along. On Windows by a scheduled task of
//   its own (startInstaller).
// - The installer's progress is heard by watching run/ (fs.watch), with a slow look as a safety net and for the
//   drain's count of running turns, in place of a look every second.
// - Words the pages show are kept as catalog keys and said in each reader's language (the Rust said them once, in the
//   language of whoever caused the reading).
// - `stillfail-station channel` reaches this process as the launcher's `{"op":"hup"}` (it holds SIGHUP for it):
//   `answerChannelAsk`.

import { createHash } from "node:crypto";
import { type FSWatcher, createReadStream, createWriteStream, existsSync, mkdirSync, readFileSync, realpathSync, renameSync, rmSync, statSync, watch, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, parse } from "node:path";
import { type Clock, Effect, Fiber } from "effect";
import { Fibers } from "../ops/fibers.ts";
import type { ConfigFile } from "../ops/config.ts";
import { type Lang, stationLang, tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import type { RuntimeKind } from "../agents/runtime.ts";
import { platform as machine } from "../platform/index.ts";
import { holding, onLetGo } from "./holds.ts";
import { planUpdate, readFeed, verifiedOrNull, type Plan } from "./release.ts";
import { SDK_PACKAGE, sdkPrefix, sdkVersion } from "../agents/cursor.ts";
import {
  DEVIN_MANIFEST, type Env, type How, type Kind, KINDS, NotFinished, type OwnNode, RUNTIMES, Unable, findCommand, howToInstall, howToUpdate, isNpmInstall,
  kindCommand, kindName, kindPackage, linkBesideNpm, npmInstall, ownNode, ownNodeHome, pinNpmVersion, putOwnNodes, removeOwnNodeLinks, run,
  runLines,
} from "./runtimes.ts";
import {
  type Channel, type Words, INSTALLING, channelOf, downloading, newer, offer, platform, releaseChannel, sameWords, say, stationDownloadPercent,
  stationVersion, stepOf, tail, versionIn,
} from "./versions.ts";

/// A line of what the pages show (client/core-ts/src/shapes/schema.ts SoftwareVersion; fields that are none are left out, as serde does).
export type SoftwareVersion = {
  id: string;
  name: string;
  installed: boolean;
  version?: string;
  latest?: string;
  newer: boolean;
  downgrade: boolean;
  channel?: string;
  auto?: boolean;
  updatable: boolean;
  note?: string;
  state: "idle" | "updating" | "failed";
  progress?: string;
  percent?: number;
  done?: string;
  message?: string;
  checkedAt?: number;
};

/// Software read and updated with the station's own and the runtimes, wired in after the updates are made (the packages
/// of the modules the station installs itself: modules/packages.ts): its lines follow the others'.
export type MoreSoftware = {
  /// Reads what is out (and installs what it takes by itself).
  read(): Promise<void>;
  /// Its lines, in `lang` (when what is out was read is the updates').
  get(lang: Lang): SoftwareVersion[];
  /// Whether `id` is one of its lines; updating one, as someone asked.
  has(id: string): boolean;
  update(id: string, lang: Lang): Promise<void>;
  /// Hears each change of what `get` says; gives the function that stops it.
  changes(listener: () => void): () => void;
};

/// How long things take, given so tests can be quick.
export type Timing = {
  /// How often what is out is read again, and while the station updates itself.
  every: number;
  autoEvery: number;
  /// How long a runtime's update may take; the station's installer.
  runtimeLimit: number;
  stationLimit: number;
  /// How long how a station's update went is shown after it ended.
  doneShown: number;
  /// The slow look at an update under way (beside the watch on run/).
  followLook: number;
};

export const TIMING: Timing = {
  every: 6 * 3600_000,
  autoEvery: 10 * 60_000,
  runtimeLimit: 10 * 60_000,
  stationLimit: 20 * 60_000,
  doneShown: 10 * 60_000,
  followLook: 5_000,
};

export type UpdatesOptions = {
  /// The release this station runs from (`--app`).
  app: string;
  data: string;
  config: ConfigFile;
  /// The still.fail cloud it is in, when it is (cloud.json's origin).
  origin: () => string | null | undefined;
  /// The station's environment (its PATH finds the runtimes); process.env when none.
  env?: Env;
  /// Where the runtimes' latest versions are read: npm's registry.
  registry?: string;
  /// Where the Devin CLI's latest version is read: its installer's manifest (runtimes.ts DEVIN_MANIFEST).
  devinManifest?: string;
  /// Where Claude Code's builds are said (its installer's downloads, for how much of one is in).
  claudeReleases?: string;
  /// Where Node's builds are (nodejs.org's), for npm where the machine has none (runtimes.ts OwnNode).
  nodeDist?: string;
  /// How many turns run now (the hub's), for what a drain waits on and an automatic update waits for.
  running?: () => number;
  /// Told when a runtime was installed or updated here (the machine's logins read again), and whether it is there now.
  runtimeChanged?: (kind: RuntimeKind, installed: boolean) => void;
  timing?: Partial<Timing>;
  /// Its time (a TestClock in tests).
  clock?: Clock.Clock;
  /// The keys its releases are signed with, by id (signed.ts trustedKeys: tests give their own).
  trusted?: Map<string, string>;
};

type Item = {
  installed: boolean;
  version: string | null;
  latest: string | null;
  how: How | null;
  /// Why it cannot be updated from here.
  note: Words | null;
  /// When an update started, while it runs.
  updating: number | null;
  /// A runtime's, while it updates: where it is.
  progress: Words | null;
  /// The station's, while it updates: the installer's step (its words are said as the pages read them).
  step: string | null;
  /// While what it downloads comes in: how much of it is (0–100).
  percent: number | null;
  /// The station's, a while after an update ended well: how it went.
  done: Words | null;
  failed: Words | null;
  /// The station's: the channel whose latest `latest` is.
  channel: Channel | null;
};

const empty = (): Item => ({ installed: false, version: null, latest: null, how: null, note: null, updating: null, progress: null, step: null, percent: null, done: null, failed: null, channel: null });

/// What the station's update started from the pages leaves in <data>/run/update.started, for whichever process runs
/// the station when it ends.
type Started = { at: number; from: string | null };

/// Starts the installer `script` apart from the station (platform.startInstaller: in the background of a shell, or on
/// Windows by a scheduled task of its own), its exit to run/update.exit and what it said to run/update.log. Whether it
/// was started.
export const startInstaller = (script: string, runDir: string, env: Record<string, string>, app: string): Promise<boolean> =>
  machine.startInstaller(script, runDir, env, app);

const UA = { "user-agent": "stillfail-station" };

async function fetchJson(url: string, ms = 15_000): Promise<any> {
  const response = await fetch(url, { headers: UA, signal: AbortSignal.timeout(ms) });
  if (!response.ok) throw new Error(`${url}: ${response.status}`);
  return response.json();
}

/// A file's SHA-256, as SHASUMS256.txt says it (hex).
function sha256(file: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const hash = createHash("sha256");
    createReadStream(file)
      .on("data", (chunk) => hash.update(chunk))
      .on("end", () => resolve(hash.digest("hex")))
      .on("error", reject);
  });
}

async function fetchText(url: string): Promise<string> {
  const response = await fetch(url, { headers: UA, signal: AbortSignal.timeout(15_000) });
  if (!response.ok) throw new Error(`${url}: ${response.status}`);
  return response.text();
}

/// A runtime's install that failed, its words said in each reader's language.
class Failed extends Error {
  readonly words: Words;
  constructor(words: Words) {
    super(say(words, "en"));
    this.words = words;
  }
}

/// An error whose words are said in the asker's language.
const refused = (lang: Lang, key: string, args?: Record<string, unknown>) => new Error(tr(lang, key, args));

const canonical = (p: string) => {
  try {
    return realpathSync(p);
  } catch {
    return null;
  }
};

export class Updates {
  readonly app: string;
  readonly data: string;
  private config: ConfigFile;
  private origin: () => string | null | undefined;
  private env: Env;
  private registry: string;
  private devinManifest: string;
  private claudeReleases: string;
  private nodeDist: string;
  /// Node being put in place for npm (installNode), while it is.
  private nodeInstalling: Promise<void> | null = null;
  private timing: Timing;
  private trusted: Map<string, string> | undefined;
  /// The channel the running release came from: as it says (CHANNEL), else the channel it started on.
  readonly installed: Channel;
  private items: Record<Kind, Item> = { station: empty(), claude: empty(), codex: empty(), dsh: empty(), grok: empty(), cursor: empty(), devin: empty(), hermes: empty() };
  private checkedAt: number | null = null;
  private checking: Promise<void> | null = null;
  private listeners = new Set<() => void>();
  private more: MoreSoftware[] = [];
  /// The version the station's last update in this process went for: updating by itself, not tried again.
  tried: string | null = null;
  private lastCheck: number | null = null;
  private running: () => number;
  private runtimeChanged: (kind: RuntimeKind, installed: boolean) => void;
  // Long-lived work, and time: fibers in this part's scope on its clock, ended with it.
  private fibers: Fibers;
  private closed = false;
  /// Started: it reads on its own (made but not started, as in tests, it reads only when asked).
  private started = false;
  private tick: Fiber.Fiber<unknown, unknown> | null = null;
  private unlisten: (() => void) | null = null;
  private unhold: (() => void) | null = null;
  private lastSetting = "";
  /// The update of the station followed now: what ends following it.
  private following: (() => void) | null = null;

  constructor(o: UpdatesOptions) {
    this.app = o.app;
    this.data = o.data;
    this.config = o.config;
    this.origin = o.origin;
    this.env = o.env ?? process.env;
    // The Nodes it installed for npm, on its PATH (and what it starts): what they installed is found there.
    removeOwnNodeLinks(this.env, this.data);
    putOwnNodes(this.env, this.data);
    this.registry = o.registry ?? "https://registry.npmjs.org";
    this.devinManifest = o.devinManifest ?? DEVIN_MANIFEST;
    this.claudeReleases = o.claudeReleases ?? "https://downloads.claude.ai/claude-code-releases";
    this.nodeDist = o.nodeDist ?? "https://nodejs.org/dist";
    this.timing = { ...TIMING, ...o.timing };
    this.trusted = o.trusted;
    this.running = o.running ?? (() => 0);
    this.runtimeChanged = o.runtimeChanged ?? (() => {});
    // Read before an update can replace the release.
    this.installed = releaseChannel(this.app) ?? channelOf(this.config.raw(), this.app);
    this.fibers = new Fibers("updates", o.clock);
  }

  // ---- what is wired in after it is made (the hub, the event streams, the machine's logins) ----

  /// How many turns run now, for what an update waits on when it has to restart the station.
  countRunning(running: () => number) {
    this.running = running;
  }

  /// What to do when a runtime was installed or updated from here.
  onRuntimeChanged(f: (kind: RuntimeKind, installed: boolean) => void) {
    this.runtimeChanged = f;
  }

  /// Software read and updated with the rest from now on; gives the function that leaves it out again.
  add(more: MoreSoftware): () => void {
    this.more.push(more);
    const unlisten = more.changes(() => this.changed());
    this.changed();
    return () => {
      unlisten();
      this.more = this.more.filter((m) => m !== more);
      this.changed();
    };
  }

  /// A runtime a session found not on PATH: read again when the pages still say it is there (removed since the last
  /// check), so what they offer is installing it.
  missing(kind: RuntimeKind) {
    if (!this.items[kind].installed || this.items[kind].updating !== null) return;
    this.spawn(async () => {
      const read = await this.readRuntime(kind);
      if (this.items[kind].updating === null) this.set(kind, (i) => Object.assign(i, read));
    });
  }

  /// Hears each change of what `get` says; gives the function that stops it.
  changes(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /// The channel the station is updated on now.
  channel(): Channel {
    return channelOf(this.config.raw(), this.app);
  }

  /// Whether the station updates itself (`autoUpdate` in its config; off unless someone turned it on).
  auto(): boolean {
    return this.config.raw()?.autoUpdate === true;
  }

  // ---- the life of the part ----

  /// Reads them at once and every few hours after (every ten minutes while the station updates itself); an update of
  /// the station started before this process (by the one it took over from, or the one before a restart) is followed
  /// to its end. The config edited elsewhere (the channel, updating by itself) is heard as it changes.
  start() {
    if (this.closed) return;
    this.lastSetting = this.setting();
    this.unlisten = this.config.listen(() => {
      const now = this.setting();
      if (now === this.lastSetting) return;
      this.lastSetting = now;
      this.changed();
      this.schedule();
    });
    // What held an update back (holds.ts) let go: one that waited goes ahead.
    this.unhold = onLetGo(() => {
      if (!this.closed) this.autoUpdate("what held the update back ended");
    });
    this.started = true;
    this.followStarted();
    this.schedule();
  }

  /// Stops what it does on its own (an installer it started goes on: it is not this process's).
  async close() {
    if (this.closed) return;
    this.closed = true;
    this.unlisten?.();
    this.unhold?.();
    this.following?.();
    this.following = null;
    await this.fibers.close();
  }

  private setting() {
    return `${this.channel()} ${this.auto()}`;
  }

  private spawn(f: () => Promise<unknown>) {
    if (this.closed) return;
    this.fibers.spawn(f);
  }

  /// Runs `f` after `ms` in this part's scope; the function returned cancels it.
  private later(ms: number, f: () => unknown): () => void {
    if (this.closed) return () => {};
    return this.fibers.after(ms, f);
  }

  /// The next look: when the next reading is due.
  private schedule() {
    if (this.closed || !this.started) return;
    if (this.tick) void Effect.runFork(Fiber.interrupt(this.tick));
    const due = this.lastCheck === null ? 0 : Math.max(0, this.lastCheck + (this.auto() ? this.timing.autoEvery : this.timing.every) - this.fibers.now());
    this.tick = this.fibers.fork(Effect.sleep(due).pipe(Effect.andThen(Effect.promise(() => this.look()))));
  }

  private async look() {
    this.tick = null;
    try {
      const every = this.auto() ? this.timing.autoEvery : this.timing.every;
      // A reading under way (asked from a page) is waited for, not looked at again and again.
      if (this.checking) await this.checking;
      else if (this.lastCheck === null || this.fibers.now() - this.lastCheck >= every) await this.check();
      this.autoUpdate("a newer release read");
    } catch (e) {
      // Not read: tried again when the next reading is due, not at once.
      this.lastCheck = this.fibers.now();
      log.warn("updates", "the updates not looked at", { error: (e as Error).message });
    }
    if (this.tick === null) this.schedule();
  }

  private changed() {
    for (const f of this.listeners) {
      try {
        f();
      } catch {}
    }
  }

  private set(kind: Kind, f: (i: Item) => void) {
    f(this.items[kind]);
    this.changed();
  }

  // ---- what the pages read and ask ----

  /// What the pages show, one line each, in `lang`.
  get(lang: Lang = stationLang()): SoftwareVersion[] {
    const channel = this.channel();
    const own = KINDS.map((kind) => {
      const item = this.items[kind];
      const station = kind === "station";
      // Read from another channel than the one it is on now: not yet known.
      const latest = station && item.channel !== channel ? null : item.latest;
      const [isNewer, downgrade] = station
        ? offer(item.version, latest, channel, this.installed)
        : [item.version !== null && latest !== null && newer(item.version, latest), false];
      // Only where it can be updated from here.
      const here = station && item.note === null && item.version !== null;
      const progress = item.updating === null ? null : station ? this.progressOf(item.step) : item.progress;
      const line: SoftwareVersion = {
        id: kind,
        name: kindName(kind),
        installed: item.installed,
        version: item.version ?? undefined,
        latest: latest ?? undefined,
        newer: isNewer,
        downgrade,
        channel: here ? channel : undefined,
        auto: here ? this.auto() : undefined,
        updatable: item.how !== null || here,
        note: item.note ? say(item.note, lang) : undefined,
        state: item.updating !== null ? "updating" : item.failed !== null ? "failed" : "idle",
        progress: progress ? say(progress, lang) : undefined,
        percent: item.updating !== null && item.percent !== null ? item.percent : undefined,
        done: item.done ? say(item.done, lang) : undefined,
        message: item.failed ? say(item.failed, lang) : undefined,
        checkedAt: this.checkedAt ?? undefined,
      };
      for (const k of Object.keys(line) as (keyof SoftwareVersion)[]) if (line[k] === undefined) delete line[k];
      return line;
    });
    const more = this.more.flatMap((m) => m.get(lang)).map((line) => (this.checkedAt === null ? line : { ...line, checkedAt: this.checkedAt }));
    return [...own, ...more];
  }

  /// Reads every version and what is out, now (once at a time: asked while a reading goes on, it is that reading);
  /// a newer release of the station's channel is installed when it updates itself.
  check(): Promise<void> {
    if (this.checking) return Promise.resolve();
    this.checking = this.read().finally(() => (this.checking = null));
    return this.checking;
  }

  private async read() {
    const more = Promise.all(this.more.map((m) => m.read().catch((e) => log.warn("updates", "software beside the station's not read", { error: (e as Error).message }))));
    let [station, ...runtimes] = await Promise.all([this.readStation(this.channel()), ...RUNTIMES.map((kind) => this.readRuntime(kind))]);
    // Put on another channel while it was read: read from that one.
    while (station.channel !== this.channel()) station = await this.readStation(this.channel());
    for (const [kind, read] of [["station", station] as const, ...RUNTIMES.map((kind, i) => [kind, runtimes[i]!] as const)]) {
      const item = this.items[kind];
      // One that is updating keeps what it was until it is done; but one not yet read (an update this process took
      // over following) is read.
      if (item.updating === null) this.items[kind] = { ...read, failed: item.failed, done: item.done };
      else if (!item.installed) this.items[kind] = { ...read, updating: item.updating, progress: item.progress, step: item.step, percent: item.percent };
    }
    await more;
    this.checkedAt = this.fibers.now();
    this.lastCheck = this.fibers.now();
    this.changed();
    this.autoUpdate("a newer release out");
    this.schedule();
  }

  private async readStation(channel: Channel): Promise<Item> {
    const version = stationVersion(this.app) ?? null;
    const app = canonical(this.app);
    let note: Words | null =
      app !== null && app === canonical(join(this.data, "app")) ? null
      : this.app.includes(".app/Contents") ? { key: "station.updates.withDesktop" }
      : { key: "station.updates.notInstaller" };
    const origin = this.origin() || null;
    if (note === null && origin === null) note = { key: "station.updates.notJoined" };
    let latest: string | null = null;
    if (origin !== null) {
      try {
        // Only a release whose words verify is one (none is newer than a feed that does not).
        const { release, why } = verifiedOrNull(await readFeed(channel, origin), this.trusted);
        if (release === null) log.warn("updates", "the station's latest release does not verify: not offered", { channel, why });
        latest = release?.version ?? null;
      } catch (e) {
        log.warn("updates", "the station's latest release not read", { error: (e as Error).message });
      }
    }
    return { ...empty(), installed: true, version, latest, note, channel };
  }

  private async readRuntime(kind: Kind): Promise<Item> {
    if (kind === "cursor") return this.readCursor();
    const found = findCommand(kindCommand(kind), this.env);
    let version: string | null = null;
    if (found) {
      try {
        const [ok, out] = await run(found.onPath, ["--version"], this.env, 20_000);
        if (ok) version = versionIn(out);
      } catch {}
    }
    let latest: string | null = null;
    if (kind === "hermes") return { ...empty(), installed: found !== null, version, latest: null, how: null, note: { key: "station.updates.hermesExternal" } };
    try {
      // Devin's builds are its installer's, said in its manifest; the others' npm packages.
      const said = await fetchJson(kind === "devin" ? this.devinManifest : `${this.registry}/${kindPackage(kind)}/latest`);
      latest = typeof said?.version === "string" ? said.version : null;
    } catch (e) {
      log.warn("updates", "the runtime's latest version not read", { runtime: kind, error: (e as Error).message });
    }
    const how = found ? howToUpdate(kind, found, this.env) : howToInstall(kind, this.env, this.ownNode());
    return {
      ...empty(),
      installed: found !== null,
      version,
      latest,
      how: how instanceof Unable ? null : how,
      note: how instanceof Unable ? { key: how.key, args: how.args } : null,
    };
  }

  /// The Node npm is installed with where the machine has none: the version the station runs on (its release's
  /// NODE_VERSION).
  private ownNode(): OwnNode | null {
    let version = process.versions.node;
    try {
      version = readFileSync(join(this.app, "NODE_VERSION"), "utf8").trim() || version;
    } catch {}
    return ownNode(this.data, version);
  }

  /// Cursor's SDK, a package npm keeps in the station's own prefix (agents/cursor.ts): installed and updated by the same
  /// npm install there.
  private async readCursor(): Promise<Item> {
    const version = sdkVersion(this.data);
    let latest: string | null = null;
    try {
      const said = await fetchJson(`${this.registry}/${kindPackage("cursor")}/latest`);
      latest = typeof said?.version === "string" ? said.version : null;
    } catch (e) {
      log.warn("updates", "the runtime's latest version not read", { runtime: "cursor", error: (e as Error).message });
    }
    const how = npmInstall(this.env, this.ownNode(), ["install", "-g", "--prefix", sdkPrefix(this.data), `${SDK_PACKAGE}@latest`], kindName("cursor"));
    return { ...empty(), installed: version !== null, version, latest, how: how instanceof Unable ? null : how, note: how instanceof Unable ? { key: how.key, args: how.args } : null };
  }

  /// Turns updating by itself on or off (as someone asked, from a page): kept in its config; turned on, what is out is
  /// read at once, and a newer release installed.
  async setAuto(on: boolean, lang: Lang = stationLang()) {
    this.refuseStationNote(lang);
    if (this.auto() !== on) {
      this.config.update((raw) => {
        raw.autoUpdate = on;
      });
      this.lastSetting = this.setting();
      log.info("updates", "the station's updating by itself set", { on });
      this.changed();
    }
    if (on) await this.check();
    this.schedule();
  }

  /// Puts the station on `channel` (as someone asked, from a page): kept in its config, and what is out read again from
  /// that channel.
  async setChannel(channel: Channel, lang: Lang = stationLang()) {
    this.refuseStationNote(lang);
    this.keepChannel(channel);
    await this.check();
  }

  /// Keeps `channel` in the config, when it is another one than now.
  keepChannel(channel: Channel) {
    if (this.channel() === channel) return;
    this.config.update((raw) => {
      raw.updateChannel = channel;
    });
    this.lastSetting = this.setting();
    log.info("updates", "the station's update channel set", { channel });
    this.changed();
  }

  /// `stillfail-station channel <name>` asked the running station (SIGHUP, through the launcher's `hup`): takes the
  /// channel in run/channel-ask, keeps it, reads what is out on it, and answers in run/channel-answer.
  answerChannelAsk() {
    answerChannelAsk(join(this.data, "run"), (channel) => {
      this.keepChannel(channel);
      this.spawn(() => this.check());
    });
  }

  private refuseStationNote(lang: Lang) {
    const note = this.items.station.note;
    if (note) throw refused(lang, "station.list.labeled", { name: kindName("station"), note: say(note, lang) });
  }

  // ---- updating by itself ----

  /// The runtime being installed or updated now, when one is: the station is not updated meanwhile (its update hands
  /// over to another process or restarts, and the install would go on unfollowed).
  private runtimeUpdating(): Kind | null {
    return RUNTIMES.find((k) => this.items[k].updating !== null) ?? null;
  }

  /// The version the station updates itself to now, when it does: it updates itself, can be updated from here, is not
  /// updating, and its channel's latest is newer (not an older stable one back from the beta) and not one it already
  /// went for. Running turns are not waited for: the update hands them over (or, restarting, to the next start). What
  /// is not handed over is (holds.ts: a command run with a vault grant, whose proxy would go with this process).
  toUpdateTo(): string | null {
    if (!this.auto() || holding() > 0) return null;
    const item = this.items.station;
    if (item.note !== null || item.updating !== null || item.channel !== this.channel() || this.runtimeUpdating() !== null) return null;
    if (item.latest === null) return null;
    const [isNewer] = offer(item.version, item.latest, this.channel(), this.installed);
    return isNewer && this.tried !== item.latest ? item.latest : null;
  }

  private autoUpdate(why: string) {
    const to = this.toUpdateTo();
    if (to === null) return;
    log.info("updates", `${why}: the station updates itself`, { to });
    this.updateStation(stationLang()).catch((e) => log.warn("updates", "the station not updated by itself", { error: (e as Error).message }));
  }

  // ---- updating ----

  /// Updates one (`station`, `claude`, `codex`, `dsh`, or software added: `module:<id>`), or installs a runtime the machine has not: answers once it has
  /// started; how it goes shows in `get`. Refusals are said in `lang`.
  async update(id: string, lang: Lang = stationLang()): Promise<void> {
    const more = this.more.find((m) => m.has(id));
    if (more !== undefined) return more.update(id, lang);
    const kind = KINDS.find((k) => k === id);
    if (kind === undefined) throw refused(lang, "station.updates.noSuchItem", { id });
    const item = this.items[kind];
    const name = kindName(kind);
    if (item.updating !== null) throw refused(lang, "station.updates.alreadyUpdating", { name });
    if (item.note) throw refused(lang, "station.list.labeled", { name, note: say(item.note, lang) });
    if (kind === "station") {
      const runtime = this.runtimeUpdating();
      if (runtime !== null) throw refused(lang, "station.updates.runtimeBusy", { name: kindName(runtime) });
      return this.updateStation(lang);
    }
    if (this.items.station.updating !== null) throw refused(lang, item.installed ? "station.updates.stationBusyUpdate" : "station.updates.stationBusyInstall", { name });
    const how = item.how;
    if (how === null) throw refused(lang, "station.updates.notHere", { name });
    this.set(kind, (i) => {
      i.updating = this.fibers.now();
      i.progress = null;
      i.percent = null;
      i.failed = null;
      i.done = null;
    });
    this.spawn(() => this.updateRuntime(kind, how));
  }

  private async updateRuntime(kind: Kind, how: How) {
    log.info("updates", "updating or installing a runtime", { runtime: kind, program: how.program, args: how.args });
    let failed: Words | null = null;
    try {
      const [ok, said, code] = await this.install(kind, how);
      // Its package manager has nothing newer to apply yet (winget's sources behind npm's latest): said as that, with
      // what it said.
      if (!ok && how.noUpdate !== undefined && code === how.noUpdate) failed = { key: "station.updates.noApplicableUpdate", args: { program: parse(how.program).name, said: tail(said, stationLang()) } };
      else if (!ok) failed = { text: tail(said, stationLang()) };
    } catch (e) {
      failed = e instanceof NotFinished ? { key: "station.updates.timedOut" } : e instanceof Failed ? e.words : { text: (e as Error).message };
    }
    if (failed) log.warn("updates", "the runtime not updated", { runtime: kind, failed: say(failed, "en") });
    let read = await this.readRuntime(kind);
    if (failed === null && !read.installed && (await linkBesideNpm(kind, how, this.env).catch(() => false))) {
      log.info("updates", "the runtime npm installed off PATH linked beside npm", { runtime: kind, npm: how.program });
      read = await this.readRuntime(kind);
    }
    // Done without an error but not there, or not newer: installed somewhere the station's PATH does not find.
    if (failed === null) {
      if (!read.installed) failed = { key: "station.updates.notOnPath", args: { program: how.program, command: kindCommand(kind) } };
      else if (read.version !== null && read.latest !== null && newer(read.version, read.latest)) {
        failed = { key: "station.updates.notNewer", args: { program: how.program, command: kindCommand(kind), version: read.version, latest: read.latest } };
      }
    }
    this.set(kind, (i) => Object.assign(i, read, { failed }));
    try {
      this.runtimeChanged(kind as RuntimeKind, read.installed);
    } catch {}
    // The station's own update waited for this one.
    this.autoUpdate("a newer release out, waited for a runtime");
  }

  /// Runs `how`, saying where it is as it goes: a download that can be measured, by how much of it is in (Codex's
  /// build for this machine, fetched here first; Claude Code's, as its installer writes it), else the step the command
  /// says it is at (Homebrew's, Claude Code's installer's).
  private async install(kind: Kind, how: How): Promise<[boolean, string, number | null]> {
    if (how.node) await this.installNode(kind, how.node);
    const npm = isNpmInstall(how);
    if (kind === "codex" && npm) {
      const version = await this.fetchCodex(how.program);
      // That version, as npm's cache has its build (`latest` from a cached list could be an older one).
      if (version !== null) how = pinNpmVersion(how, kindPackage(kind), version);
    }
    // npm of the station's own Node runs on it (its #! takes the node PATH finds first).
    const env = how.node ? machine.prependPath(this.env, how.node.bin) : this.env;
    const installing = { now: false };
    // Claude Code's own installer (not `claude update`, nor Homebrew).
    const own = how.program === "/bin/sh" || how === machine.claudeInstall;
    const stop = kind === "claude" && own ? this.watchClaudeDownload(installing) : () => {};
    try {
      return await runLines(how.program, how.args, env, this.timing.runtimeLimit, (line) => {
        const step = stepOf(line);
        if (step === null) return;
        if (sameWords(step, INSTALLING)) installing.now = true;
        this.say(kind, step, null);
      });
    } finally {
      stop();
    }
  }

  /// The Node an npm install runs on where the machine had none (runtimes.ts OwnNode): nodejs.org's build for this
  /// machine, its download measured and checked against the release's SHASUMS256, unpacked in <data>/node once (kept
  /// for the next install, and for npm to update what it installed), and put last on the station's PATH.
  private async installNode(kind: Kind, node: OwnNode) {
    // Two runtimes installed at once: one Node, put there by the first.
    while (this.nodeInstalling) await this.nodeInstalling.catch(() => {});
    const done = this.placeNode(kind, node);
    this.nodeInstalling = done;
    try {
      await done;
    } finally {
      this.nodeInstalling = null;
    }
    putOwnNodes(this.env, this.data);
  }

  private async placeNode(kind: Kind, node: OwnNode) {
    if (existsSync(join(node.bin, node.build.npm))) return;
    const home = ownNodeHome(this.data);
    mkdirSync(home, { recursive: true });
    const { dist, archive } = node.build;
    const file = join(home, archive);
    const unpacked = join(home, `.unpacking-${dist}`);
    try {
      const base = `${this.nodeDist}/v${node.version}`;
      const sums = await fetchText(`${base}/SHASUMS256.txt`);
      const want = sums.split("\n").map((l) => l.trim().split(/\s+/)).find(([, f]) => f === archive)?.[0];
      if (want === undefined) throw new Failed({ key: "station.updates.nodeUnverified" });
      await this.download(kind, `Node ${node.version}`, `${base}/${archive}`, file);
      if ((await sha256(file)) !== want) throw new Failed({ key: "station.updates.nodeUnverified" });
      this.say(kind, INSTALLING, null);
      rmSync(unpacked, { recursive: true, force: true });
      mkdirSync(unpacked);
      const [ok, said] = await run(node.build.tar, ["-xf", file, "-C", unpacked], this.env, 120_000);
      if (!ok) throw new Error(tail(said, stationLang()));
      rmSync(node.at, { recursive: true, force: true });
      renameSync(join(unpacked, dist), node.at);
      log.info("updates", "Node installed for npm", { runtime: kind, at: node.at });
    } finally {
      rmSync(file, { force: true });
      rmSync(unpacked, { recursive: true, force: true });
    }
  }

  /// Where a runtime's update is (while it updates), and how much of a download is in.
  private say(kind: Kind, progress: Words, percent: number | null) {
    const item = this.items[kind];
    if (item.updating === null || (sameWords(item.progress, progress) && item.percent === percent)) return;
    item.progress = progress;
    item.percent = percent;
    this.changed();
  }

  private sayDownloading(kind: Kind, version: string, got: number, total: number | null) {
    const [words, percent] = downloading(version, got, total);
    this.say(kind, words, percent);
  }

  /// Codex's build for this machine (nearly all its install downloads), fetched here so how much is in can be said,
  /// and put in npm's cache for the install to take: the version fetched; null when it was not (npm then downloads it
  /// itself, unmeasured).
  private async fetchCodex(npm: string): Promise<string | null> {
    const p = platform();
    if (p === null) return null;
    const pkg = kindPackage("codex");
    let version: string;
    let url: string;
    try {
      version = (await fetchJson(`${this.registry}/${pkg}/latest`))?.version;
      url = (await fetchJson(`${this.registry}/${pkg}/${version}-${p}`))?.dist?.tarball;
      if (typeof version !== "string" || typeof url !== "string") return null;
    } catch {
      return null;
    }
    const file = join(tmpdir(), `stillfail-codex-${version}-${p}.tgz`);
    try {
      await this.download("codex", version, url, file);
      this.say("codex", INSTALLING, null);
      const [ok, said] = await run(npm, ["cache", "add", file], this.env, 120_000);
      if (ok) return version;
      log.warn("updates", "Codex's build not put in npm's cache; npm downloads it", { said: tail(said, "en") });
      return null;
    } catch (e) {
      log.warn("updates", "Codex's build not fetched; npm downloads it", { error: (e as Error).message });
      return null;
    } finally {
      rmSync(file, { force: true });
    }
  }

  /// Downloads `url` to `to`, saying how much of it is in; a minute without anything coming in ends it.
  private async download(kind: Kind, version: string, url: string, to: string) {
    const stalled = new AbortController();
    const over = new AbortController();
    let stall = this.fibers.after(60_000, () => stalled.abort());
    const limit = this.fibers.after(this.timing.runtimeLimit, () => over.abort(new DOMException("timed out", "TimeoutError")));
    try {
      const response = await fetch(url, { headers: UA, signal: AbortSignal.any([stalled.signal, over.signal]) });
      if (!response.ok || !response.body) throw new Error(`${url}: ${response.status}`);
      const length = Number(response.headers.get("content-length"));
      const total = Number.isFinite(length) && length > 0 ? length : null;
      const out = createWriteStream(to);
      let got = 0;
      this.sayDownloading(kind, version, got, total);
      try {
        for await (const chunk of response.body as unknown as AsyncIterable<Uint8Array>) {
          stall();
          stall = this.fibers.after(60_000, () => stalled.abort());
          if (!out.write(chunk)) await new Promise<void>((r) => out.once("drain", () => r()));
          got += chunk.length;
          this.sayDownloading(kind, version, got, total);
        }
      } catch (e) {
        if (stalled.signal.aborted) throw refused(stationLang(), "station.updates.downloadStalled");
        throw e;
      } finally {
        await new Promise<void>((r) => out.end(() => r()));
      }
    } finally {
      stall();
      limit();
    }
  }

  /// Says how much of Claude Code's build its installer has downloaded (into ~/.claude/downloads, its size in the
  /// release's manifest; the zstd one when the machine has zstd), until it sets it up. Its installer is another
  /// program writing a file: looked at twice a second while it runs. Gives what stops it.
  private watchClaudeDownload(installing: { now: boolean }): () => void {
    const home = this.env.HOME;
    const p = platform();
    if (!home || p === null) return () => {};
    let stopped = false;
    let next: (() => void) | null = null;
    void (async () => {
      let version: string;
      let plain: number | null = null;
      let zst: number | null = null;
      try {
        version = (await fetchText(`${this.claudeReleases}/latest`)).trim();
        const size = (m: any) => (typeof m?.platforms?.[p]?.size === "number" ? m.platforms[p].size : null);
        const [a, b] = await Promise.allSettled([fetchJson(`${this.claudeReleases}/${version}/manifest.json`), fetchJson(`${this.claudeReleases}/${version}/manifest.zst.json`)]);
        plain = a.status === "fulfilled" ? size(a.value) : null;
        zst = b.status === "fulfilled" ? size(b.value) : null;
      } catch {
        return;
      }
      const file = join(home, ".claude/downloads", `claude-${version}-${p}`);
      const look = () => {
        if (stopped || installing.now) return;
        const len = (f: string) => {
          try {
            return statSync(f).size;
          } catch {
            return null;
          }
        };
        const [gotZst, gotPlain] = [len(`${file}.zst`), len(file)];
        const got = gotZst !== null ? (zst !== null ? [gotZst, zst] : null) : gotPlain !== null && plain !== null ? [gotPlain, plain] : null;
        if (got) this.sayDownloading("claude", version, got[0]!, got[1]!);
        next = this.fibers.after(500, look);
      };
      look();
    })();
    return () => {
      stopped = true;
      next?.();
    };
  }

  /// Runs the installer this release carries apart from the station, as `stillfail update` does (release.ts), and
  /// follows it: by this process, and after a handover or a restart by the one that runs then (run/update.started says
  /// to).
  private async updateStation(lang: Lang): Promise<void> {
    const origin = this.origin() || null;
    if (origin === null) throw refused(lang, "station.updates.notJoined");
    const runDir = join(this.data, "run");
    mkdirSync(runDir, { recursive: true });
    for (const f of ["update.exit", "update.step"]) rmSync(join(runDir, f), { force: true });
    const station = this.items.station;
    // Taken now, so another ask meanwhile finds it updating.
    const before = { updating: station.updating, failed: station.failed, done: station.done };
    station.updating = this.fibers.now();
    const channel = this.channel();
    // The release verified, the installer to run and what it is told (refused in `lang`: not left updating).
    let plan: Plan;
    try {
      plan = await planUpdate({ base: origin, channel, app: this.app, installed: this.installed, lang, trusted: this.trusted });
    } catch (e) {
      Object.assign(station, before);
      throw e;
    }
    const env: Record<string, string> = {};
    for (const [k, v] of Object.entries(this.env)) if (v !== undefined) env[k] = v;
    // Under both names, as installers from before the rename read the old one.
    Object.assign(env, { STILLFAIL_DATA: this.data, EMBER_DATA: this.data }, plan.env);
    const ok = await startInstaller(plan.script, runDir, env, this.app);
    if (!ok) {
      Object.assign(station, before);
      throw refused(lang, "station.updates.couldNotStart");
    }
    log.info("updates", "updating the station", { origin, channel, to: plan.release.version });
    this.tried = plan.release.version;
    const started: Started = { at: this.fibers.now(), from: stationVersion(this.app) ?? null };
    try {
      writeFileSync(join(runDir, "update.started"), JSON.stringify(started));
    } catch (e) {
      log.warn("updates", "update.started not written; a handover or restart will not say how the update went", { error: (e as Error).message });
    }
    this.follow(started);
  }

  /// An update started before this process, when one is: followed as if started here.
  followStarted() {
    const runDir = join(this.data, "run");
    let started: Started;
    try {
      const said = JSON.parse(readFileSync(join(runDir, "update.started"), "utf8"));
      if (typeof said?.at !== "number") return;
      started = { at: said.at, from: typeof said.from === "string" ? said.from : null };
    } catch {
      return;
    }
    if (this.fibers.now() - started.at > this.timing.stationLimit) {
      for (const f of ["update.started", "update.step"]) rmSync(join(runDir, f), { force: true });
      return;
    }
    log.info("updates", "following the station's update started before this process");
    this.follow(started);
  }

  /// Shows how the station's update goes (the installer's steps, in run/update.step) until it says how it ended in
  /// run/update.exit (and what it said in run/update.log), then how it went for a while.
  follow(started: Started) {
    this.following?.();
    this.set("station", (i) => {
      i.updating = started.at;
      i.step = null;
      i.progress = null;
      i.percent = null;
      i.failed = null;
      i.done = null;
    });
    const runDir = join(this.data, "run");
    const [exitFile, logFile, stepFile] = ["update.exit", "update.log", "update.step"].map((f) => join(runDir, f)) as [string, string, string];
    let over = false;
    let watcher: FSWatcher | null = null;
    let soon: (() => void) | null = null;
    let slow: (() => void) | null = null;
    let lastRunning = this.running();
    const end = () => {
      over = true;
      watcher?.close();
      soon?.();
      slow?.();
    };
    this.following = end;
    const look = () => {
      soon = null;
      if (over) return;
      let step = "";
      try {
        step = readFileSync(stepFile, "utf8").trim();
      } catch {}
      let code: string | null = null;
      try {
        code = readFileSync(exitFile, "utf8");
      } catch {}
      // Made but not yet written (the shell opens it, then writes the code): not ended yet; its write is seen next.
      if (code !== null && code.trim() === "") code = null;
      let failed: Words | null = null;
      let done: Words | null = null;
      if (code !== null && code.trim() === "0") done = this.done(started, step);
      else if (code !== null) {
        let said: string | null = null;
        try {
          said = readFileSync(logFile, "utf8");
        } catch {}
        failed = said !== null ? { text: tail(said, stationLang()) } : { key: "station.updates.installerExit", args: { code: code.trim() } };
      } else if (this.fibers.now() - started.at > this.timing.stationLimit) failed = { key: "station.updates.installerTimedOut" };
      else {
        const item = this.items.station;
        const percent = step === "download" ? stationDownloadPercent(logFile) : null;
        const running = this.running();
        if (item.step !== (step || null) || item.percent !== percent || (step === "drain" && running !== lastRunning)) {
          item.step = step || null;
          item.percent = percent;
          lastRunning = running;
          this.changed();
        }
        return;
      }
      end();
      if (this.following === end) this.following = null;
      for (const f of ["update.started", "update.step"]) rmSync(join(runDir, f), { force: true });
      log.info("updates", "the station's update ended", { failed: failed !== null });
      this.set("station", (i) => {
        i.updating = null;
        i.step = null;
        i.progress = null;
        i.percent = null;
        i.failed = failed;
        i.done = done;
      });
      this.spawn(() => this.check());
      if (done !== null) {
        const shown = done;
        // Unless another update has said something since.
        this.later(this.timing.doneShown, () => {
          if (sameWords(this.items.station.done, shown)) this.set("station", (i) => (i.done = null));
        });
      }
    };
    const lookSoon = () => {
      if (!over && soon === null) soon = this.fibers.after(50, look);
    };
    try {
      mkdirSync(runDir, { recursive: true });
      watcher = watch(runDir, (_, name) => {
        if (name === null || name.startsWith("update.")) lookSoon();
      });
      watcher.on("error", () => {});
    } catch (e) {
      log.warn("updates", "run/ not watched; the update is looked at now and then", { error: (e as Error).message });
    }
    slow = this.fibers.every(this.timing.followLook, look);
    look();
  }

  /// Where the update is, by the installer's step, as the pages say it.
  private progressOf(step: string | null): Words | null {
    switch (step) {
      case "download":
        return { key: "station.updates.downloadingStation" };
      case "handoff":
        return { key: "station.updates.handoff" };
      case "drain": {
        const n = this.running();
        return n === 0 ? { key: "station.updates.restarting" } : { key: "station.updates.draining", args: { n } };
      }
      case "restart":
        return { key: "station.updates.restarting" };
      default:
        return null;
    }
  }

  /// How an update that ended well went, by the step it ended on.
  private done(started: Started, step: string): Words {
    const now = stationVersion(this.app) ?? null;
    if (now !== null && now === started.from) return { key: "station.updates.upToDate" };
    const [withVersion, without] =
      step === "handoff" ? ["station.updates.doneHandoff", "station.updates.doneHandoffNoVersion"]
      : step === "drain" || step === "restart" ? ["station.updates.doneRestart", "station.updates.doneRestartNoVersion"]
      : ["station.updates.done", "station.updates.doneNoVersion"];
    return now !== null ? { key: withVersion, args: { version: now } } : { key: without };
  }

  // ---- for tests ----

  /// The station's line as if its latest were `latest`, read from the channel it is on.
  stationWith(latest: string, lang: Lang = "zh"): SoftwareVersion {
    const item = this.items.station;
    item.version = stationVersion(this.app) ?? null;
    item.latest = latest;
    item.channel = this.channel();
    return this.get(lang)[0]!;
  }

  /// Sets a line's state by hand (tests).
  poke(kind: Kind, f: (i: Item) => void) {
    f(this.items[kind]);
  }
}

/// Where `stillfail-station channel` asks the running station for an update channel, and where it answers.
export const CHANNEL_ASK = "channel-ask";
export const CHANNEL_ANSWER = "channel-answer";

/// Writes `text` to `path` whole (a reader never sees half of it).
export function writeWhole(path: string, text: string) {
  const tmp = `${path}.tmp-${process.pid}`;
  writeFileSync(tmp, text);
  renameSync(tmp, path);
}

/// The running station's side: takes the channel asked for in <run>/channel-ask (if any), sets it, and answers in
/// <run>/channel-answer (`ok <channel>`, or `error <why>`).
export function answerChannelAsk(runDir: string, set: (channel: Channel) => void) {
  const ask = join(runDir, CHANNEL_ASK);
  let asked: string;
  try {
    asked = readFileSync(ask, "utf8");
  } catch {
    return;
  }
  rmSync(ask, { force: true });
  const channel = asked.trim() === "stable" || asked.trim() === "beta" ? (asked.trim() as Channel) : null;
  let answer: string;
  if (channel === null) answer = `error ${tr(stationLang(), "station.cli.unknownChannel", { channel: asked.trim() })}`;
  else {
    try {
      set(channel);
      answer = `ok ${channel}`;
    } catch (e) {
      answer = `error ${(e as Error).message}`;
    }
  }
  try {
    writeWhole(join(runDir, CHANNEL_ANSWER), `${answer}\n`);
  } catch (e) {
    log.warn("updates", "the update channel's answer not written", { error: (e as Error).message });
  }
}

/// Makes the station's updates: `start` reads them and keeps reading; `close` stops that.
export function makeUpdates(o: UpdatesOptions): Updates {
  return new Updates(o);
}
