// Modules the station installs itself (docs/station-modules.md, 「包」): config.json names one by `package` rather than by
// a command, and the station gets the package where it gets its own releases (the control plane's release base, on
// the station's channel), signed the same way (docs/release-signing.md). The feed, releases/modules/<p>/<p>.json
// (<p>-beta.json on the beta), is verified (signed.ts verifyModule) and taken only when it is newer than what is
// installed and for a station as new as it needs (`needsStation`); the archive it names is downloaded, checked against
// what was signed (sha256 and size), and its files (plain ones only: updates/archive.ts) opened into
// <data>/modules/<id>/app/<build>/; then <data>/modules/<id>/app/state.json, written whole, is switched to it, and the
// module is run again (modules/live.ts), by the station's own Node: <build>/<entry>, as the package's module.json says.
// The build before stays, to go back to when the new one never comes up (it ends again and again before it answers
// its manifest); a build older than one that came up is never run again: it could not read what a newer one wrote
// (media.db's user_version). Packages are read whenever the station reads its own updates (updates.ts: the overview
// says each as `module:<id>`), at once for one named and not yet installed, and when someone asks from the pages; what
// is newer is installed by itself.
import { randomBytes } from "node:crypto";
import { mkdirSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import type { Clock } from "effect";
import { Fibers } from "../ops/fibers.ts";
import { type Lang, tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { readArchive, safePath } from "../updates/archive.ts";
import { Unverified, type ModuleRelease, sha256, trustedKeys, verifyModule } from "../updates/signed.ts";
import { type SoftwareVersion, writeWhole } from "../updates/updates.ts";
import { type Channel, type Words, INSTALLING, platform, say } from "../updates/versions.ts";
import type { ModuleSpec, PackageSpec } from "./modules.ts";

const UA = { "user-agent": "stillfail-station" };
/// How many times a build just switched to may end before it answers before the one before is gone back to.
export const TRIES = 3;
/// How soon a package named and not installed is looked for again after it could not be.
const AGAIN_MS = 10 * 60_000;
/// How long a package's archive may take to come.
const DOWNLOAD_MS = 5 * 60_000;

/// Where releases say a package's latest (scripts/module-bundle.ts, cloud/src/install.ts).
export const moduleFeed = (base: string, name: string, channel: Channel) => `${base}/releases/modules/${name}/${name}${channel === "beta" ? "-beta" : ""}.json`;

/// A package's archive for `platform` (`any`: the one for every machine), beside its feed.
export const archiveOf = (base: string, name: string, version: string, platform: string) =>
  `${base}/releases/modules/${name}/${name}-${version}${platform === "any" ? "" : `-${platform}`}.tar.gz`;

/// What <data>/modules/<id>/app/state.json says: which package, the build run (`current`), the one before it (kept, to
/// go back to), the newest that came up (none older is run again), and those gone back from (not taken again).
export type Installed = { package: string | null; current: number | null; previous: number | null; ran: number | null; failed: number[] };

const NONE: Installed = { package: null, current: null, previous: null, ran: null, failed: [] };

const build = (v: unknown) => (Number.isSafeInteger(v) && (v as number) > 0 ? (v as number) : null);

export function readInstalled(app: string): Installed {
  try {
    const said = JSON.parse(readFileSync(join(app, "state.json"), "utf8"));
    return {
      package: typeof said?.package === "string" ? said.package : null,
      current: build(said?.current),
      previous: build(said?.previous),
      ran: build(said?.ran),
      failed: Array.isArray(said?.failed) ? said.failed.filter((b: unknown) => build(b) !== null) : [],
    };
  } catch {
    return NONE;
  }
}

function writeInstalled(app: string, state: Installed) {
  mkdirSync(app, { recursive: true, mode: 0o700 });
  writeWhole(join(app, "state.json"), `${JSON.stringify(state)}\n`);
}

/// The entry a build's module.json names (a path in it), or null when it names none.
export function entryOf(dir: string): string | null {
  try {
    const entry = JSON.parse(readFileSync(join(dir, "module.json"), "utf8"))?.entry;
    return typeof entry === "string" && safePath(entry) ? entry : null;
  } catch {
    return null;
  }
}

/// A refusal, in words the pages say in their reader's language.
class Refused extends Error {
  readonly words: Words;
  constructor(words: Words) {
    super(say(words, "en"));
    this.words = words;
  }
}

/// The archive at `url`, its bytes checked as they come against what was signed: no more than `size`, then exactly
/// `size` bytes hashing to `sha`.
async function download(url: string, b: { sha256: string; size: number }): Promise<Buffer> {
  const response = await fetch(url, { headers: UA, signal: AbortSignal.timeout(DOWNLOAD_MS) });
  if (!response.ok || !response.body) throw new Error(`${url}: ${response.status}`);
  const parts: Buffer[] = [];
  let got = 0;
  for await (const chunk of response.body as unknown as AsyncIterable<Uint8Array>) {
    got += chunk.length;
    if (got > b.size) throw new Refused({ key: "station.updates.moduleNotSigned" });
    parts.push(Buffer.from(chunk));
  }
  const bytes = Buffer.concat(parts);
  if (bytes.length !== b.size || sha256(bytes) !== b.sha256) throw new Refused({ key: "station.updates.moduleNotSigned" });
  return bytes;
}

/// `bytes` (a package's archive) opened into <app>/<build>: written aside, then moved in whole. Throws when it is not
/// one (anything but plain files under it, no module.json naming an entry it has).
export function unpack(app: string, buildOf: number, bytes: Uint8Array): void {
  let files;
  try {
    files = readArchive(bytes);
  } catch (e) {
    throw new Refused({ key: "station.updates.moduleBadPackage", args: { why: (e as Error).message } });
  }
  const aside = join(app, `.${buildOf}-${randomBytes(4).toString("hex")}`);
  try {
    for (const f of files) {
      mkdirSync(dirname(join(aside, f.path)), { recursive: true, mode: 0o700 });
      writeFileSync(join(aside, f.path), f.bytes, { mode: 0o600 });
    }
    const entry = entryOf(aside);
    if (entry === null || !files.some((f) => f.path === entry)) throw new Refused({ key: "station.updates.moduleBadPackage", args: { why: "module.json names no entry it has" } });
    rmSync(join(app, String(buildOf)), { recursive: true, force: true });
    renameSync(aside, join(app, String(buildOf)));
  } finally {
    rmSync(aside, { recursive: true, force: true });
  }
}

/// What the pages say of a package beside what is installed: the latest read, and how its last look went.
type Line = { latest: number | null; updating: boolean; note: Words | null; failed: Words | null };

export type PackagesOptions = {
  data: string;
  /// The station's own build (its release's BUILD); null for one that is no release (a clone): what a package needs
  /// is not asked then.
  station: number | null;
  /// Where releases are (the control plane's release base: still.fail cloud's origin, Comma's /stations), when the
  /// station is in one.
  base: () => string | null;
  /// The channel the station is updated on: its packages come from the same one.
  channel: () => Channel;
  /// The keys packages are signed with, by id (signed.ts trustedKeys: tests give their own).
  trusted?: Map<string, string>;
  /// The station process before this one gone (a handover's): nothing is installed before, as it may run the module.
  previousGone?: Promise<void>;
  clock?: Clock.Clock;
};

/// The packages config.json names, as installed and as out: installed and updated, run as the build they have, gone
/// back from a build that never comes up; and what the pages say of them (each a line of the station's updates).
export class Packages {
  readonly #o: PackagesOptions;
  readonly #trusted: Map<string, string>;
  readonly #fibers: Fibers;
  /// The modules named by their package now, by id.
  #named = new Map<string, PackageSpec>();
  #lines = new Map<string, Line>();
  /// A look under way, by id: asked again meanwhile, it is that one.
  #looking = new Map<string, Promise<Words | null>>();
  /// How many times the build each runs ended before it came up.
  #downs = new Map<string, number>();
  /// The next look at a package not installed, by id: what calls it off.
  #again = new Map<string, () => void>();
  #ready = false;
  #changes = new Set<() => void>();
  #switches = new Set<() => void>();

  constructor(o: PackagesOptions) {
    this.#o = o;
    this.#trusted = o.trusted ?? trustedKeys();
    this.#fibers = new Fibers("modules", o.clock);
    void (o.previousGone ?? Promise.resolve()).then(() => (this.#ready = true));
  }

  /// Where module `id`'s package is installed.
  appOf(id: string): string {
    return join(this.#o.data, "modules", id, "app");
  }

  /// Hears each change of what `get` says; gives the function that stops it.
  changes(listener: () => void): () => void {
    this.#changes.add(listener);
    return () => this.#changes.delete(listener);
  }

  /// Hears each switch of a module's build (installed, gone back from): the modules are followed again.
  switches(listener: () => void): () => void {
    this.#switches.add(listener);
    return () => this.#switches.delete(listener);
  }

  #changed() {
    for (const f of this.#changes) f();
  }

  /// The packages config.json names now (modules/live.ts follow): the others no longer said; one not installed looked
  /// for at once.
  named(specs: PackageSpec[]) {
    this.#named = new Map(specs.map((s) => [s.id, s]));
    for (const id of [...this.#lines.keys()]) if (!this.#named.has(id)) this.#lines.delete(id);
    for (const spec of specs) if (this.#current(spec) === null && !this.#looking.has(spec.id) && !this.#again.has(spec.id)) this.#soon(spec.id);
  }

  /// The build installed for `spec`, when the one installed is its package.
  #current(spec: PackageSpec): number | null {
    const state = readInstalled(this.appOf(spec.id));
    return state.package === spec.package ? state.current : null;
  }

  /// Looked for in the background, once the station before is gone; again a while after, while it is not installed.
  #soon(id: string) {
    this.#fibers.spawn(async () => {
      await (this.#o.previousGone ?? Promise.resolve());
      await this.#look(id);
      const spec = this.#named.get(id);
      if (spec === undefined || this.#current(spec) !== null || this.#again.has(id)) return;
      this.#again.set(id, this.#fibers.after(AGAIN_MS, () => {
        this.#again.delete(id);
        if (this.#named.has(id)) this.#soon(id);
      }));
    });
  }

  /// Module `spec` as it is run: the station's own Node (the desktop app's Electron as Node) on the entry of the build
  /// installed; null while none is.
  runnable(spec: PackageSpec): ModuleSpec | null {
    const current = this.#current(spec);
    if (current === null) return null;
    const dir = join(this.appOf(spec.id), String(current));
    const entry = entryOf(dir);
    if (entry === null) {
      log.warn("modules", "an installed package names no entry; it is not run", { module: spec.id, build: current });
      return null;
    }
    return {
      id: spec.id,
      command: process.execPath,
      args: [join(dir, entry), ...spec.args],
      env: { ...spec.env, ELECTRON_RUN_AS_NODE: "1" },
      installed: { package: spec.package, build: current },
    };
  }

  // ---- read and installed ----

  /// Every package named read, and what is newer installed (as the station reads its updates). Nothing before the
  /// station process before this one is gone: what is named is looked for then.
  async read(): Promise<void> {
    if (!this.#ready) return;
    await Promise.all([...this.#named.keys()].map((id) => this.#look(id)));
  }

  /// Module `id`'s package read now, and installed when newer (someone asked: `module:<id>`); what refused it thrown,
  /// in `lang`.
  async update(id: string, lang: Lang): Promise<void> {
    const name = id.startsWith("module:") ? id.slice("module:".length) : id;
    if (!this.#named.has(name)) throw new Error(tr(lang, "station.updates.noSuchItem", { id }));
    const failed = await this.#look(name);
    if (failed !== null) throw new Error(say(failed, lang));
  }

  /// Whether `id` is one of the lines it says.
  has(id: string): boolean {
    return id.startsWith("module:") && this.#named.has(id.slice("module:".length));
  }

  /// One look at a package (once at a time): its feed read and verified, and the release installed when the station
  /// takes it. What refused it, if anything (said on its line too).
  #look(id: string): Promise<Words | null> {
    const under = this.#looking.get(id);
    if (under !== undefined) return under;
    const look = this.#lookNow(id).finally(() => this.#looking.delete(id));
    this.#looking.set(id, look);
    return look;
  }

  async #lookNow(id: string): Promise<Words | null> {
    const spec = this.#named.get(id);
    if (spec === undefined) return null;
    const line = this.#lineOf(id);
    const base = this.#o.base();
    line.note = base === null ? { key: "station.updates.notJoined" } : null;
    if (base === null) {
      this.#changed();
      return line.note;
    }
    let release: ModuleRelease;
    try {
      const url = moduleFeed(base, spec.package, this.#o.channel());
      const response = await fetch(url, { headers: UA, signal: AbortSignal.timeout(15_000) });
      if (!response.ok) throw new Error(`${url}: ${response.status}`);
      release = verifyModule(await response.json(), spec.package, this.#trusted);
    } catch (e) {
      line.failed = e instanceof Unverified ? { key: "station.updates.unverified", args: { why: e.message } } : { text: (e as Error).message };
      log.warn("modules", "a module's package not read", { module: id, package: spec.package, error: (e as Error).message });
      this.#changed();
      return line.failed;
    }
    line.latest = release.build;
    line.failed = null;
    const state = readInstalled(this.appOf(id));
    const current = state.package === spec.package ? state.current : null;
    const ran = state.package === spec.package ? state.ran : null;
    // Not newer, or older than one that came up (its data may be newer than it), or one gone back from: kept as it is.
    if ((current !== null && release.build <= current) || (ran !== null && release.build < ran) || (state.package === spec.package && state.failed.includes(release.build))) {
      this.#changed();
      return null;
    }
    if (this.#o.station !== null && release.needsStation > this.#o.station) {
      line.note = { key: "station.updates.moduleNeedsStation", args: { version: release.version, needs: release.needsStation, current: `0.1.${this.#o.station}` } };
      log.info("modules", "a module's package needs a newer station; not installed", { module: id, version: release.version, needs: release.needsStation, station: this.#o.station });
      this.#changed();
      return line.note;
    }
    const machine = platform();
    const which = machine !== null && release.builds[machine] ? machine : "any";
    const b = release.builds[which];
    if (b === undefined) {
      line.failed = { key: "station.updates.noBuild", args: { version: release.version } };
      this.#changed();
      return line.failed;
    }
    line.updating = true;
    this.#changed();
    try {
      const bytes = await download(archiveOf(base, spec.package, release.version, which), b);
      const app = this.appOf(id);
      mkdirSync(app, { recursive: true, mode: 0o700 });
      unpack(app, release.build, bytes);
      // Switched whole; the build before kept to go back to, any other removed.
      const next: Installed = { package: spec.package, current: release.build, previous: current, ran, failed: state.package === spec.package ? state.failed : [] };
      writeInstalled(app, next);
      prune(app, next);
      this.#downs.delete(id);
      log.info("modules", "a module's package installed", { module: id, package: spec.package, version: release.version, from: current === null ? null : `0.1.${current}` });
    } catch (e) {
      line.failed = e instanceof Refused ? e.words : { text: (e as Error).message };
      log.warn("modules", "a module's package not installed", { module: id, version: release.version, error: (e as Error).message });
      return line.failed;
    } finally {
      line.updating = false;
      this.#changed();
    }
    for (const f of this.#switches) f();
    return null;
  }

  #lineOf(id: string): Line {
    let line = this.#lines.get(id);
    if (line === undefined) this.#lines.set(id, (line = { latest: null, updating: false, note: null, failed: null }));
    return line;
  }

  // ---- how a build does ----

  /// A module run as an installed build came up (answered its manifest): that build ran.
  up(spec: ModuleSpec) {
    if (spec.installed === undefined) return;
    this.#downs.delete(spec.id);
    const app = this.appOf(spec.id);
    const state = readInstalled(app);
    if (state.package !== spec.installed.package || (state.ran !== null && state.ran >= spec.installed.build)) return;
    writeInstalled(app, { ...state, ran: spec.installed.build });
  }

  /// A module run as an installed build ended before it came up. The TRIES-th time for a build that never came up, the
  /// build before it is gone back to (when it may be: not older than one that came up): whether it was, and so the
  /// module is run again as that one.
  down(spec: ModuleSpec): boolean {
    if (spec.installed === undefined) return false;
    const downs = (this.#downs.get(spec.id) ?? 0) + 1;
    this.#downs.set(spec.id, downs);
    if (downs < TRIES) return false;
    const app = this.appOf(spec.id);
    const state = readInstalled(app);
    const { build: failing } = spec.installed;
    if (state.package !== spec.installed.package || state.current !== failing || state.previous === null) return false;
    if (state.ran !== null && (state.ran >= failing || state.previous < state.ran)) return false;
    writeInstalled(app, { ...state, current: state.previous, previous: null, failed: [...state.failed, failing] });
    rmSync(join(app, String(failing)), { recursive: true, force: true });
    this.#downs.delete(spec.id);
    this.#lineOf(spec.id).failed = { key: "station.updates.moduleWentBack", args: { version: `0.1.${failing}`, back: `0.1.${state.previous}` } };
    log.warn("modules", "a module's new build never came up; back on the one before", { module: spec.id, build: failing, back: state.previous, tries: downs });
    this.#changed();
    for (const f of this.#switches) f();
    return true;
  }

  // ---- what the pages show ----

  /// A line each (`module:<id>`), in `lang`.
  get(lang: Lang): SoftwareVersion[] {
    return [...this.#named.values()].map((spec) => {
      const line = this.#lineOf(spec.id);
      const current = this.#current(spec);
      const v: SoftwareVersion = {
        id: `module:${spec.id}`,
        name: tr(lang, "station.updates.moduleName", { id: spec.id }),
        installed: current !== null,
        version: current === null ? undefined : `0.1.${current}`,
        latest: line.latest === null ? undefined : `0.1.${line.latest}`,
        newer: line.latest !== null && (current === null || line.latest > current),
        downgrade: false,
        // Not while what it needs is not there (a newer station, a workspace): updating all (the client core's) would stop
        // at it before the station's own update.
        updatable: this.#o.base() !== null && line.note === null,
        note: line.note ? say(line.note, lang) : undefined,
        state: line.updating ? "updating" : line.failed !== null ? "failed" : "idle",
        progress: line.updating ? say(INSTALLING, lang) : undefined,
        message: line.failed ? say(line.failed, lang) : undefined,
      };
      for (const k of Object.keys(v) as (keyof SoftwareVersion)[]) if (v[k] === undefined) delete v[k];
      return v;
    });
  }

  /// Stops what it does in the background.
  close(): Promise<void> {
    return this.#fibers.close();
  }
}

/// The builds in <app> but the one run and the one before it removed, and anything left aside.
function prune(app: string, state: Installed) {
  for (const name of readdirSync(app)) {
    if (name === "state.json" || name === String(state.current) || name === String(state.previous)) continue;
    rmSync(join(app, name), { recursive: true, force: true });
  }
}
