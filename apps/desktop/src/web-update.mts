// The web app without a new app (docs/desktop-web-updates.md): the beta app asks its feed (desktop/web/stillfail-beta-web.json)
// for a newer build of the web app it carries; one signed by a release key, for an app as old as this one or older
// (`needs`), and newer than the web app it runs is downloaded, checked against what was signed, and opened into
// userData/web/0.1.<build>. The pages then offer 刷新 (no restart): taking it makes that the web app served, and reloads
// them; the next start takes it by itself. At start, an app that has not asked for a while (`stale`) asks before its
// window opens, the download's progress shown (main.ts webAtStart). What the app carries stays, the last way back.
import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { mkdir, rename, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { type DesktopWebRelease, Unverified, trustedKeys, verifyDesktopWeb } from "../../../station/src/updates/signed.ts";
import { readArchive } from "./web-archive.mts";

/** A web app this app may serve: its build, the oldest app it works in, and where its files are. */
export interface WebBuild { build: number; needs: number; dir: string }

/** What a downloaded build says of itself, beside its files (what its feed said, once verified). */
const ABOUT = ".stillfail-web.json";
/** The build served, in userData/web (state.json; none: the one the app carries), and when this app last heard what is newest. */
const STATE = "state.json";
/** How many builds taken before the one served stay while the app runs, for a page opened on one to find its files. */
const KEEP = 2;

export interface WebUpdatesOptions {
  /** userData/web. */
  dir: string;
  /** The web app the app carries (Resources/web) and its build: the app's own. */
  carried: string;
  app: number;
  /** The feed's URL, and the archives' beside it. */
  feed: string;
  fetch: (url: string) => Promise<Response>;
  trusted?: Map<string, string>;
  now?: () => number;
}

/** A build being downloaded: bytes got of its size. */
export interface WebProgress { build: number; received: number; size: number }

export class WebUpdates {
  /** Downloaded and opened, newer than what is served: what 刷新 takes. */
  ready: WebBuild | null = null;
  private served: WebBuild;
  /** Taken before the one served since the app started: pages opened on them may still ask for their files. */
  private before: WebBuild[] = [];
  private checking: Promise<WebBuild | null> | null = null;
  /** When the feed last answered this app (a build of the app before it does not count: it was offered other builds). */
  private checked: number | null = null;
  /** Told as a build downloads. */
  progress: ((progress: WebProgress) => void) | null = null;
  private writing: Promise<void> = Promise.resolve();

  private readonly options: WebUpdatesOptions;

  constructor(options: WebUpdatesOptions) {
    this.options = options;
    const carried: WebBuild = { build: options.app, needs: options.app, dir: options.carried };
    this.served = carried;
    // The newest build downloaded for this app, if newer than the one it carries (an app updated since carries a newer
    // one): no page is open yet, so it is taken now rather than offered.
    const newest = this.list().at(-1);
    if (newest && newest.build > carried.build) this.served = newest;
    try {
      const state = JSON.parse(readFileSync(join(options.dir, STATE), "utf8")) as { checked?: { app: number; at: number } };
      if (state.checked?.app === options.app && Number.isFinite(state.checked.at)) this.checked = state.checked.at;
    } catch {}
  }

  /** Not asked for `within` ms (or never by this app): what is served may well be old. */
  stale(within: number): boolean {
    return this.checked === null || Math.abs(this.now() - this.checked) >= within;
  }

  /** At start: says what is served (state.json), and removes the builds that are not. */
  async settle(): Promise<void> {
    await this.writeState();
    await this.prune();
  }

  /** The web app served now. */
  current(): WebBuild {
    return this.served;
  }

  /**
   * Where a file of the web app is looked for, in order: the build served, the ones before it (a page opened on one asks
   * for its files, as a chunk it loads late), then the one the app carries.
   */
  roots(): string[] {
    return [...new Set([this.served.dir, ...this.before.map((b) => b.dir), this.options.carried])];
  }

  /** Asks the feed; a newer build for this app is downloaded and opened (ready), else null. One check at a time. */
  check(): Promise<WebBuild | null> {
    this.checking ??= this.fetchNewer().finally(() => (this.checking = null));
    return this.checking;
  }

  /** Serves the build ready (and keeps the one served before it, for the pages still on it). */
  async take(): Promise<WebBuild | null> {
    const next = this.ready;
    if (!next) return null;
    if (this.served.dir !== this.options.carried) this.before = [this.served, ...this.before.filter((b) => b.build !== this.served.build)].slice(0, KEEP);
    this.served = next;
    this.ready = null;
    await this.writeState();
    await this.prune();
    return next;
  }

  /**
   * The build `failed` failed to load (its page did not come up): if it is the one served, it is removed, and the one
   * before it served (one taken earlier this run, else the one the app carries). False otherwise.
   */
  async back(failed: number): Promise<boolean> {
    // Another window on the same build said so first: what is served now is another one, and not this page's.
    if (this.served.dir === this.options.carried || this.served.build !== failed) return false;
    const bad = this.served;
    this.served = this.before.shift() ?? { build: this.options.app, needs: this.options.app, dir: this.options.carried };
    if (this.ready?.build === bad.build) this.ready = null;
    await rm(bad.dir, { recursive: true, force: true });
    // Not taken again: the feed goes on offering it until a newer build is out.
    await writeFile(`${bad.dir}.rejected`, "");
    await this.writeState();
    return true;
  }

  private now(): number {
    return (this.options.now ?? Date.now)();
  }

  private async fetchNewer(): Promise<WebBuild | null> {
    const found = await this.askFeed();
    this.checked = this.now();
    await this.writeState();
    return found;
  }

  private async askFeed(): Promise<WebBuild | null> {
    const { feed, fetch, app } = this.options;
    const response = await fetch(feed);
    // No feed yet (none published for this channel): nothing newer.
    if (response.status === 404) return null;
    if (!response.ok) throw new Error(`${feed}: ${response.status}`);
    const current = Math.max(this.served.build, this.ready?.build ?? 0);
    let release: DesktopWebRelease;
    try {
      release = verifyDesktopWeb(await response.json(), app, current, this.options.trusted ?? trustedKeys());
    } catch (error) {
      // Not newer, or for a newer app than this one: nothing to take, and nothing wrong.
      if (error instanceof Unverified && /not newer|needs the app/.test(error.message)) return null;
      throw error;
    }
    if (existsSync(`${this.dirOf(release.build)}.rejected`)) return null;
    const known = this.downloaded(release.build);
    if (known) return (this.ready = known.build > this.served.build ? known : null);
    const url = new URL(release.file, feed).href;
    const got = await fetch(url);
    if (!got.ok) throw new Error(`${url}: ${got.status}`);
    const bytes = await this.read(got, release.build, release.size);
    if (bytes.length !== release.size || createHash("sha256").update(bytes).digest("hex") !== release.sha256) throw new Unverified(`${release.file} is not the one signed`);
    const files = readArchive(bytes);
    if (!files.some((f) => f.path === "index.html")) throw new Unverified(`${release.file} has no index.html`);
    // Opened beside, then moved into place: a directory named by its build is whole.
    const dir = this.dirOf(release.build);
    const part = `${dir}.part`;
    await rm(part, { recursive: true, force: true });
    for (const file of files) {
      const path = join(part, ...file.path.split("/"));
      await mkdir(dirname(path), { recursive: true });
      await writeFile(path, file.bytes);
    }
    await writeFile(join(part, ABOUT), `${JSON.stringify({ build: release.build, needs: release.needs, sha256: release.sha256 })}\n`);
    await rm(dir, { recursive: true, force: true });
    await rename(part, dir);
    this.ready = { build: release.build, needs: release.needs, dir };
    return this.ready;
  }

  /** A download's bytes, its progress told as they come; no more than `size` of them. */
  private async read(response: Response, build: number, size: number): Promise<Uint8Array> {
    const tell = (received: number) => this.progress?.({ build, received, size });
    tell(0);
    if (!response.body) {
      const bytes = new Uint8Array(await response.arrayBuffer());
      tell(bytes.length);
      return bytes;
    }
    const chunks: Uint8Array[] = [];
    let received = 0;
    for await (const chunk of response.body as AsyncIterable<Uint8Array>) {
      received += chunk.length;
      if (received > size) throw new Unverified(`build ${build} is longer than the one signed`);
      chunks.push(chunk);
      tell(received);
    }
    return Buffer.concat(chunks);
  }

  private dirOf(build: number): string {
    return join(this.options.dir, `0.1.${build}`);
  }

  /** A build downloaded before, whole (moved into place) and for this app; null otherwise. */
  private downloaded(build: number): WebBuild | null {
    const dir = this.dirOf(build);
    try {
      const about = JSON.parse(readFileSync(join(dir, ABOUT), "utf8")) as { build: number; needs: number };
      if (about.build !== build || !Number.isSafeInteger(about.needs) || about.needs > this.options.app || !existsSync(join(dir, "index.html"))) return null;
      return { build, needs: about.needs, dir };
    } catch {
      return null;
    }
  }

  /** The builds downloaded, oldest first. */
  private list(): WebBuild[] {
    let names: string[] = [];
    try {
      names = readdirSync(this.options.dir);
    } catch {}
    return names
      .map((name) => /^0\.1\.(\d+)$/.exec(name)?.[1])
      .filter((n): n is string => !!n)
      .map((n) => this.downloaded(Number(n)))
      .filter((b): b is WebBuild => !!b)
      .sort((a, b) => a.build - b.build);
  }

  /** One write at a time (a check answering as the app starts settling): each writes what is true when it runs. */
  private writeState(): Promise<void> {
    const write = this.writing.then(async () => {
      await mkdir(this.options.dir, { recursive: true });
      const checked = this.checked === null ? {} : { checked: { app: this.options.app, at: this.checked } };
      const state = { served: this.served.dir === this.options.carried ? null : this.served.build, ...checked };
      await writeFile(join(this.options.dir, `${STATE}.part`), `${JSON.stringify(state)}\n`);
      await rename(join(this.options.dir, `${STATE}.part`), join(this.options.dir, STATE));
    });
    this.writing = write.catch(() => {});
    return write;
  }

  /** What is neither served, nor kept for the pages before, nor ready goes. */
  private async prune(): Promise<void> {
    const keep = new Set([this.served.build, ...this.before.map((b) => b.build), ...(this.ready ? [this.ready.build] : [])]);
    let names: string[] = [];
    try {
      names = readdirSync(this.options.dir);
    } catch {}
    for (const name of names) {
      const n = /^0\.1\.(\d+)(\.part)?$/.exec(name);
      // A build being opened (.part) while a check is under way is that check's.
      if (n?.[2] && this.checking) continue;
      if (n && (n[2] || !keep.has(Number(n[1])))) await rm(join(this.options.dir, name), { recursive: true, force: true });
    }
  }
}
