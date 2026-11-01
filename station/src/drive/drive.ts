// A station's drive (zdrive, brought in): its machine's files, which members browse and change over their link: list a
// folder, read a part of a file, write one in parts, make a folder, rename, remove. A member who may write (and so may
// have an agent do anything on the machine) reaches every folder (`anywhere`): any absolute path is a root to ask from.
// The folders pinned in config.json (`drive.roots`) are the list everyone sees first, and all a read-only member
// reaches. Every path is asked relative to a root and stays in it: `..` is refused rather than worked out, and, for a
// read-only member, the path as the file system has it (its links followed) must still be under the pinned root, so a
// link pointing out is refused too. The station's own data (its key, its config, the profiles' homes, the machine's
// runtime logins) is never reachable, as for the device tools: a listing leaves it out.
//
// On macOS the folders its privacy protection keeps from a station launchd runs (Documents, Desktop, Downloads, disks;
// fs.ts `protectedTop`) are reached through still.fail Helper (helper/files.ts), which holds the grants: the same checks
// here first, then the helper's operations instead of the file system's (`Fs`). The station never touches them itself
// while the helper is there, not even to see whether it may: macOS can hold such a call on a prompt for the station's
// launcher that nobody answers (seen on macOS 27: the station's thread stayed in opendir on ~/Documents). Without the
// grant, the helper's window asks for it on that Mac, and the request is refused saying so.
import { statSync } from "node:fs";
import { mkdir, readdir, rm, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, join, parse } from "node:path";
import { tmpdir } from "node:os";
import { randomUUID } from "node:crypto";
import { platform } from "../platform/index.ts";
import { wall } from "../ops/fibers.ts";
import { unreadableDir, unreadableDirAsync } from "../ops/files.ts";
import { TooBig, zipFolder } from "./zip.ts";
import { type Lang, tr } from "../ops/i18n.ts";
import { type Fs, type Grant, type Protected, direct, protectedTop, realOf } from "./fs.ts";
import type { ConfigFile } from "../ops/config.ts";

/// Why a request was refused (zdrive's codes, and `protected` for the station's own data), each with its status.
export const CODES = {
  invalid_request: 400,
  not_a_root: 404,
  not_found: 404,
  path_escape: 403,
  protected: 403,
  permission: 403,
  is_a_directory: 409,
  not_a_directory: 409,
  exists: 409,
  upload_lost: 409,
  no_trash: 409,
  too_large: 413,
  io: 500,
} as const;
export type Code = keyof typeof CODES;

export class DriveError extends Error {
  readonly code: Code;
  /// For `upload_lost`: how much of the upload the station has, to go on from.
  readonly have?: number;
  /// The path it is about, when that is not the one asked (a root named).
  about?: string;
  /// For `permission`: still.fail Helper may not open that protected folder yet (its grant, the folder), and what became
  /// of its window asking for it on that Mac (Protected.ask).
  need?: { grant: Grant; top: string; window: "up" | "closed" | "none" };
  constructor(code: Code, message: string, have?: number) {
    super(message);
    this.code = code;
    this.have = have;
  }
}

/// A folder's entry, as a listing gives it: `type` by its name (files only).
export type Entry = { name: string; dir: boolean; size: number; mtime: number; type: string };

/// A root as the settings and the drive's page show it: `ok`, or why it cannot be browsed now (`unreadable`: there but
/// the station may not list it, which on macOS is a folder privacy protection keeps from a station launchd runs).
export type RootView = { path: string; name: string; state: "ok" | "missing" | "not_a_directory" | "unreadable" };

/// Why a file is not sent in a chat (its words are the route's).
export const TOO_BIG = "too big to send";
/// At most this many roots.
export const MOST_ROOTS = 32;
/// A listing stops at this many entries (`truncated`).
const MOST_ENTRIES = 50_000;
/// The most one read gives.
export const MAX_READ = 8 * 1024 * 1024;
/// What an upload's file is called beside where it goes, until it is whole: left out of listings.
const PART = /^\.stillfail-up-[A-Za-z0-9_-]{1,64}\.part$/;
/// An upload not finished for this long is removed the next time one starts in its folder.
const STALE_MS = 24 * 3600 * 1000;

const key = (path: string) => platform.paths.key(path);
const within = (path: string, dir: string) => platform.paths.within(key(path), key(dir));

/// The roots config.json names (`drive.roots`): absolute paths, as written. Those of a workspace the station joined are
/// `drive.workspaces[<id>]` (docs/multi-workspace.md); none named, its home workspace's.
export function rootsOf(raw: any, workspace: string | null = null): string[] {
  const roots = workspace === null ? raw?.drive?.roots : raw?.drive?.workspaces?.[workspace];
  return Array.isArray(roots) ? roots.filter((r: unknown): r is string => typeof r === "string" && platform.paths.rooted(r)).map((r) => platform.paths.clean(r)) : [];
}

/// A root's name: its last component, or the path itself when it has none (`/`, a drive).
export const rootName = (path: string) => basename(path) || path;

export function rootView(path: string): RootView {
  const name = rootName(path);
  try {
    if (!statSync(path).isDirectory()) return { path, name, state: "not_a_directory" };
  } catch (e) {
    const code = (e as NodeJS.ErrnoException).code;
    return { path, name, state: code === "EPERM" || code === "EACCES" ? "unreadable" : "missing" };
  }
  return { path, name, state: unreadableDir(path) ? "unreadable" : "ok" };
}

/// A root as the drive and the overview show it: in a folder macOS protects, with still.fail Helper there for it
/// (`files`), by what is known of the helper's grant, never looked at by the station itself (listing it could hold the
/// station's thread on a prompt); elsewhere as `rootView` finds it.
export function rootViewThrough(path: string, files: Protected | null, home = homedir()): RootView {
  const top = files ? protectedTop(path, home) : null;
  if (top === null) return rootView(path);
  return { path, name: rootName(path), state: granted(files!, top) ? "ok" : "unreadable" };
}

/// Whether still.fail Helper may open the protected folder `top`, as last known (looked at when not known yet).
function granted(files: Protected, top: string): boolean {
  const known = files.known(top);
  if (known === undefined) files.check([top]);
  return known?.state === "granted";
}

/// Where a file a person drops into one of the station's screens is put (docs/remote-screens.md `drop`): the machine's
/// Downloads, where files from elsewhere land (a browser's, AirDrop's) and where its file dialogs look first; the home
/// where it has none. Only the folder's own entry is looked at, never what is in it: on macOS listing a protected
/// folder can put a privacy prompt up and hold the caller until it is answered (a whole station, for a sync call). A
/// station kept from writing there is refused as an upload is (`permission`); one that reaches it another way (still.fail
/// Helper) puts it there.
export function dropFolder(home: string): string {
  const downloads = join(home, "Downloads");
  try {
    return statSync(downloads).isDirectory() ? downloads : home;
  } catch {
    return home;
  }
}

/// A file's type by its name, as a page needs it to open it: what plays, what is read, what is shown.
export function typeOf(name: string): string {
  const dot = name.lastIndexOf(".");
  const ext = dot <= 0 ? "" : name.slice(dot + 1).toLowerCase();
  return TYPES[ext] ?? "application/octet-stream";
}

const TYPES: Record<string, string> = {
  png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp", svg: "image/svg+xml", heic: "image/heic", bmp: "image/bmp",
  mp4: "video/mp4", m4v: "video/mp4", mov: "video/quicktime", webm: "video/webm", mkv: "video/x-matroska", avi: "video/x-msvideo", ts: "video/mp2t",
  mp3: "audio/mpeg", m4a: "audio/mp4", aac: "audio/aac", flac: "audio/flac", wav: "audio/wav", ogg: "audio/ogg", opus: "audio/opus",
  pdf: "application/pdf", zip: "application/zip",
  txt: "text/plain; charset=utf-8", md: "text/markdown; charset=utf-8", markdown: "text/markdown; charset=utf-8", log: "text/plain; charset=utf-8",
  csv: "text/csv; charset=utf-8", json: "application/json", html: "text/html; charset=utf-8", htm: "text/html; charset=utf-8",
  srt: "application/x-subrip", vtt: "text/vtt", ass: "text/x-ssa", ssa: "text/x-ssa",
};

/// Names in the order a listing has them: numbers by their value (E2 before E10), case and accents aside.
const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

function failed(e: unknown): DriveError {
  if (e instanceof DriveError) return e;
  const err = e as NodeJS.ErrnoException & { grant?: Grant; top?: string };
  switch (err.code) {
    // still.fail Helper's refusals (helper/files.ts): out of the roots it was told, the station's own, no grant.
    case "outside":
      return new DriveError("path_escape", "that path leads out of its root");
    case "protected":
      return new DriveError("protected", "the station's own data is not part of its drive");
    case "grant": {
      const d = new DriveError("permission", "macOS has not let still.fail Helper open that folder");
      d.need = { grant: err.grant!, top: err.top ?? "", window: "none" };
      return d;
    }
    case "ENOENT":
      return new DriveError("not_found", "no such file or folder");
    case "EACCES":
    case "EPERM":
      return new DriveError("permission", "the station may not do that here");
    case "EEXIST":
    case "ENOTEMPTY":
      return new DriveError("exists", "there is already one by that name");
    case "EISDIR":
      return new DriveError("is_a_directory", "that is a folder");
    case "ENOTDIR":
      return new DriveError("not_a_directory", "that is not a folder");
    case "ENOSPC":
      return new DriveError("too_large", "the station's disk is full");
    default:
      return new DriveError("io", err.message ?? String(e));
  }
}

/// A path as the file system has it, links followed, as far as it exists (what is not there yet is under its nearest
/// parent that is).
const real = (path: string) => direct.real(path);

/// A folder to pick a root from: its name, where it is, whether the station may list it, whether it is a disk.
export type Folder = { name: string; path: string; unreadable: boolean; disk?: boolean };
export type Folders = { path: string; parent: string | null; home: string; folders: string[]; entries: Folder[]; unreadable: boolean; crumbs: { name: string; path: string }[]; places: Folder[] };

/// The home's own folders offered as places to start from, as they are named on disk (Videos: Linux and Windows).
const PLACES = ["Desktop", "Documents", "Downloads", "Movies", "Videos", "Music", "Pictures"];

const isDir = (path: string) => stat(path).then((s) => s.isDirectory(), () => false);

/// The way to `at`: from the home when it is under it (the home first, in words), else from the top.
function crumbs(at: string, home: string, lang: Lang): { name: string; path: string }[] {
  const under = platform.paths.relativeIn(home, at);
  // Else from the top of its own disk (`/`; on Windows its drive, `E:\`).
  const top = parse(at).root;
  const [first, rest] = under !== null ? [{ name: tr(lang, "station.drive.place.home"), path: home }, under] : [{ name: top, path: top }, at.slice(top.length)];
  const out = [first];
  let path = first.path;
  for (const part of rest.split(/[\\/]/).filter((p) => p !== "")) {
    path = join(path, part);
    out.push({ name: part, path });
  }
  return out;
}

/// A path asked of the drive: its root as named and as found, where it is as asked, as found (links followed), the entry
/// itself (its folder's links followed, not its own: what a rename or a removal acts on), its components, and how it is
/// reached (directly, or through still.fail Helper: `fs`, with `scope`, the root it is told to stay in).
type Place = { root: string; top: string; asked: string; found: string; entry: string; parts: string[]; fs: Fs; scope: string };

export type DriveDeps = {
  /// config.json as it is now.
  config: () => any;
  /// What no request may reach, even under a root (asked anew each time: a profile may be added meanwhile).
  protect: () => string[];
  now?: () => number;
  /// still.fail Helper's way to the folders macOS keeps from the station (macOS with the helper; none elsewhere).
  files?: Protected | null;
  /// The machine's home: whose trash what is deleted goes to, and where Documents, Desktop and Downloads are (a test's own).
  home?: string;
  /// Which disk a folder is on (its file system's device; null: it could not be told).
  disk?: (dir: string) => Promise<number | null>;
};

/// The station's drive, one for the admin API's routes and the modules' local API (modules/local.ts): config.json's
/// roots, the station's own never reached (its data directory, config, and `more`: what its parts add, ops/own.ts), the
/// folders macOS protects through still.fail Helper (`files`, where there is one).
export const stationDrive = (config: ConfigFile, more: () => string[], files: Protected | null) =>
  new Drive({ config: () => config.raw(), protect: () => [config.data, config.path, ...more()], files });

export class Drive {
  private deps: DriveDeps;
  constructor(deps: DriveDeps) {
    this.deps = deps;
  }

  roots(): RootView[] {
    return rootsOf(this.deps.config()).map((p) => this.rootView(p));
  }

  /// A root's state, as the station may reach it: one macOS keeps from the station is `ok` once still.fail Helper has
  /// the grant for it (looked at in the background the first time, the root told again when it is known).
  rootView(path: string): RootView {
    return rootViewThrough(path, this.deps.files ?? null, this.deps.home ?? homedir());
  }

  /// Whether still.fail Helper may open the protected folder `top`, as last known (looked at when not known yet).
  #granted(top: string): boolean {
    return granted(this.deps.files!, top);
  }

  /// The protected folder `path` is in (by its name) when still.fail Helper is there for it; null when the station
  /// reaches `path` directly.
  #locked(path: string): string | null {
    return this.deps.files ? protectedTop(path, this.deps.home ?? homedir()) : null;
  }

  /// `path` with its links followed as far as it exists: by still.fail Helper in a protected folder (never by the station
  /// there), else by the station.
  #real(path: string, fs: Fs): Promise<string> {
    return fs.helper && this.#locked(path) !== null ? fs.real(path) : real(path);
  }

  #disk(dir: string): Promise<number | null> {
    return this.deps.disk ? this.deps.disk(dir) : stat(dir).then((s) => s.dev, () => null);
  }

  /// Whether the station may not list `dir`, even through still.fail Helper: looked at off the main thread.
  async #unreadable(dir: string): Promise<boolean> {
    const top = this.#locked(dir);
    return top === null ? unreadableDirAsync(dir) : !this.#granted(top);
  }

  /// How paths in these scopes (the root each is told to stay in) are reached: through still.fail Helper when any is in
  /// a protected folder the station may not open, else directly.
  async #fs(places: { path: string; top: string }[]): Promise<{ fs: Fs; scopes: string[] }> {
    const locked = places.map(({ path }) => this.#locked(path));
    // The narrower of the root and the protected folder.
    const scopes = places.map(({ top }, i) => (locked[i] !== null && !within(top, locked[i]!) ? locked[i]! : top));
    if (locked.every((l) => l === null)) return { fs: direct, scopes };
    const protect = await this.protectedNow();
    return { fs: this.deps.files!.fs({ roots: [...new Set(scopes)], protect }), scopes };
  }

  /// `run`, its refusal a DriveError; one for a grant still.fail Helper lacks puts the helper's window up on this Mac
  /// unless it is up or was shown a moment ago (helper/files.ts AGAIN_MS), and says which.
  async #run<T>(run: () => Promise<T>): Promise<T> {
    try {
      return await run();
    } catch (e) {
      const d = failed(e);
      if (d.need && this.deps.files) d.need.window = await this.deps.files.ask(d.need.grant, d.need.top).catch(() => "none" as const);
      throw d;
    }
  }

  /// The drive as a workspace the station joined has it: its own pinned folders.
  scoped(workspace: string): Drive {
    return new Drive({ ...this.deps, config: () => {
      const raw = this.deps.config() ?? {};
      return { ...raw, drive: { ...(raw.drive ?? {}), roots: rootsOf(raw, workspace) } };
    } });
  }

  /// What is protected, as named and as found (links followed): asked once a request.
  private async protectedNow(): Promise<string[]> {
    const named = this.deps.protect();
    return [...named, ...(await Promise.all(named.map((p) => real(p))))];
  }

  /// Whether `path` is (or is under) what is protected, by its own name or through a link.
  private async isProtected(asked: string, found: string, protect?: string[]): Promise<boolean> {
    return (protect ?? (await this.protectedNow())).some((p) => within(asked, p) || within(found, p));
  }

  /// `path` under `root` as a request may use it, or why not. `anywhere`: the asker reaches every folder, `root` any
  /// absolute path (else one of those pinned).
  async place(root: string, path: string, anywhere = false): Promise<Place> {
    const roots = rootsOf(this.deps.config());
    const named = roots.find((r) => key(r) === key(platform.paths.clean(root))) ?? (anywhere && platform.paths.rooted(root) ? platform.paths.clean(root) : undefined);
    if (named === undefined) throw new DriveError("not_a_root", "that folder is not one of this station's drive");
    const parts = path.split("/").filter((p) => p !== "" && p !== ".");
    if (parts.some((p) => p === ".." || p.includes("\0") || (platform.paths.sep === "\\" && (p.includes("\\") || p.includes(":"))))) {
      throw new DriveError("path_escape", "a path stays in its root");
    }
    // The root as the station finds it, or, in a protected folder, as still.fail Helper does.
    let top = this.#locked(named) === null ? await real(named) : named;
    const { fs, scopes } = await this.#fs([{ path: parts.length === 0 ? top : join(top, ...parts), top }]);
    if (fs.helper && this.#locked(top) !== null) top = await fs.real(top);
    const asked = parts.length === 0 ? top : join(top, ...parts);
    const found = await this.#real(asked, fs);
    if (!anywhere && !within(found, top)) throw new DriveError("path_escape", "that path leads out of its root");
    if (await this.isProtected(asked, found)) throw new DriveError("protected", "the station's own data is not part of its drive");
    const entry = parts.length === 0 ? top : join(await this.#real(dirname(asked), fs), basename(asked));
    return { root: named, top, asked, found, entry, parts, fs, scope: scopes[0]! };
  }

  /// A folder's entries, folders first, each part by name; what is protected or leads out of the root left out.
  list(root: string, path: string, anywhere = false): Promise<{ path: string; entries: Entry[]; truncated: boolean }> {
    return this.#run(async () => {
      const at = await this.place(root, path, anywhere);
      try {
        const listed = await at.fs.list(at.found, MOST_ENTRIES);
        const entries: Entry[] = [];
        const protect = await this.protectedNow();
        for (const d of listed.entries) {
          if (PART.test(d.name)) continue;
          const asked = join(at.found, d.name);
          // A broken link, one gone meanwhile, one leading out of the root or into the station's own data: left out.
          if (d.stat === null || (!anywhere && !within(d.real, at.top)) || (await this.isProtected(asked, d.real, protect))) continue;
          const dir = d.stat.dir;
          entries.push({ name: d.name, dir, size: dir ? 0 : d.stat.size, mtime: Math.round(d.stat.mtimeMs), type: dir ? "" : typeOf(d.name) });
        }
        entries.sort((a, b) => (a.dir !== b.dir ? (a.dir ? -1 : 1) : collator.compare(a.name, b.name) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0)));
        return { path: at.parts.join("/"), entries, truncated: listed.more };
      } catch (e) {
        throw failed(e);
      }
    });
  }

  stat(root: string, path: string, anywhere = false): Promise<Entry> {
    return this.#run(async () => {
      const at = await this.place(root, path, anywhere);
      try {
        const s = await at.fs.stat(at.found);
        const name = at.parts.at(-1) ?? rootName(at.root);
        return { name, dir: s.dir, size: s.dir ? 0 : s.size, mtime: Math.round(s.mtimeMs), type: s.dir ? "" : typeOf(name) };
      } catch (e) {
        throw failed(e);
      }
    });
  }

  /// `length` bytes of a file from `offset` (fewer at its end, none past it), with its whole size and time.
  read(root: string, path: string, offset: number, length: number, anywhere = false): Promise<{ bytes: Buffer; total: number; mtime: number; type: string }> {
    return this.#run(async () => {
      if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(length) || length < 0 || length > MAX_READ) throw new DriveError("invalid_request", "invalid offset or length");
      const at = await this.place(root, path, anywhere);
      try {
        const got = await at.fs.read(at.found, offset, length);
        return { bytes: got.bytes, total: got.size, mtime: Math.round(got.mtimeMs), type: typeOf(at.parts.at(-1) ?? "") };
      } catch (e) {
        throw failed(e);
      }
    });
  }

  /// A file for what opens it by its path itself (the image codecs, a video's poster; modules/media.ts): where it is as
  /// the file system has it (`found`, what it is known by), its name, size and time. `copy` is there when it is reached
  /// through still.fail Helper, which the station does not open itself: the file copied to `to` (a new file of the
  /// station's own) to be read there instead.
  file(root: string, path: string, anywhere = false): Promise<{ found: string; name: string; size: number; mtime: number; copy: ((to: string) => Promise<void>) | null }> {
    return this.#run(async () => {
      const at = await this.place(root, path, anywhere);
      try {
        const s = await at.fs.stat(at.found);
        if (s.dir) throw new DriveError("is_a_directory", "that is a folder");
        const copy = at.fs.helper ? (to: string) => at.fs.copyTo(at.found, to).catch((e) => Promise.reject(failed(e))) : null;
        return { found: at.found, name: at.parts.at(-1) ?? rootName(at.root), size: s.size, mtime: Math.round(s.mtimeMs), copy };
      } catch (e) {
        throw failed(e);
      }
    });
  }

  /// A part of a file being written (an upload `id` of the asker's choosing): its bytes at `offset` of `total`. The file
  /// is put together beside where it goes and put there whole once its last part is in (synced, then renamed), so
  /// nobody sees half of it. A part asked again is written again (the same bytes); one that leaves a gap is refused
  /// with how much the station has (`upload_lost`), to go on from there. An existing file is replaced only when asked.
  upload(root: string, path: string, id: string, offset: number, total: number, body: Buffer, replace: boolean, anywhere = false): Promise<{ have: number; entry: Entry | null }> {
    return this.#run(async () => {
      if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) throw new DriveError("invalid_request", "an upload's id is 1 to 64 letters, digits, - or _");
      if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(total) || total < 0 || offset + body.length > total) throw new DriveError("invalid_request", "invalid offset or total");
      const at = await this.place(root, path, anywhere);
      const name = at.parts.at(-1);
      if (name === undefined) throw new DriveError("invalid_request", "a file needs a name");
      const fs = at.fs;
      const folder = dirname(at.found);
      const part = join(folder, `.stillfail-up-${id}.part`);
      const taken = async () => {
        const s = await fs.stat(at.found).catch(() => null);
        if (s?.dir) throw new DriveError("is_a_directory", "there is a folder by that name");
        if (s !== null && !replace) throw new DriveError("exists", "there is already a file by that name");
      };
      const final = offset + body.length === total;
      // Once its last part is in: what fails from there leaves nothing behind.
      let last = false;
      try {
        if (offset === 0) {
          await taken();
          await this.sweep(folder, fs);
        }
        // The last part synced and the file at its size, before it is put in place.
        const written = await fs.write(part, { create: offset === 0, offset, data: body, ...(offset > 0 ? { atLeast: offset } : {}), ...(final ? { truncate: total, sync: true } : {}) }).catch((e) => {
          if ((e as NodeJS.ErrnoException).code === "ENOENT" && offset > 0) throw new DriveError("upload_lost", "the station has none of that upload", 0);
          throw e;
        });
        if (written.short) throw new DriveError("upload_lost", "a part before this one is missing", written.size);
        if (!final) return { have: written.size, entry: null };
        last = true;
        await taken();
        await fs.rename(part, at.found);
      } catch (e) {
        if (last) await fs.unlink(part).catch(() => {});
        throw failed(e);
      }
      return { have: total, entry: await this.stat(root, at.parts.join("/"), anywhere) };
    });
  }

  /// Uploads in `folder` left unfinished long ago, removed.
  private async sweep(folder: string, fs: Fs) {
    const now = (this.deps.now ?? wallNow)();
    for (const name of await fs.names(folder).catch(() => [] as string[])) {
      if (!PART.test(name)) continue;
      const s = await fs.stat(join(folder, name)).catch(() => null);
      if (s !== null && now - s.mtimeMs > STALE_MS) await fs.unlink(join(folder, name)).catch(() => {});
    }
  }

  mkdir(root: string, path: string, anywhere = false): Promise<Entry> {
    return this.#run(async () => {
      const at = await this.place(root, path, anywhere);
      if (at.parts.length === 0) throw new DriveError("exists", "the root is there");
      try {
        if (await at.fs.stat(at.found).then(() => true, () => false)) throw new DriveError("exists", "there is already one by that name");
        await at.fs.mkdir(at.found, true);
      } catch (e) {
        throw failed(e);
      }
      return this.stat(root, at.parts.join("/"), anywhere);
    });
  }

  /// Renamed or moved within its root; what is there already is not replaced (a change of case alone is a rename).
  rename(root: string, from: string, to: string, anywhere = false): Promise<Entry> {
    return this.#run(async () => {
      const a = await this.place(root, from, anywhere);
      const b = await this.place(root, to, anywhere);
      if (a.parts.length === 0 || b.parts.length === 0) throw new DriveError("invalid_request", "the root itself is not renamed");
      if (within(b.entry, a.entry) && key(b.entry) !== key(a.entry)) throw new DriveError("invalid_request", "a folder cannot go into itself");
      // Both ends one way: through still.fail Helper, told both roots, when either is in a folder only it may open.
      const fs = a.fs.helper || b.fs.helper ? this.deps.files!.fs({ roots: [...new Set([a.scope, b.scope])], protect: await this.protectedNow() }) : direct;
      try {
        await fs.lstat(a.entry);
        const there = await fs.lstat(b.entry).then(() => true, () => false);
        if (there && key(a.entry) !== key(b.entry)) throw new DriveError("exists", "there is already one by that name");
        await fs.mkdir(dirname(b.entry), true);
        await fs.rename(a.entry, b.entry);
      } catch (e) {
        throw failed(e);
      }
      return this.stat(root, b.parts.join("/"), anywhere);
    });
  }

  /// A file copied to `into` (where a chat's uploads wait for the message that sends them), for a member to send it in a
  /// chat as if it had been uploaded: a clone where the disk can make one (APFS, btrfs), so even a big one costs nothing.
  /// `zip`: a folder put into a zip of its own name instead (links not followed, the station's own data left out).
  stage(root: string, path: string, into: (name: string) => { safe: string; path: string }, most: number, anywhere = false, zip = false): Promise<{ name: string; path: string; size: number }> {
    return this.#run(async () => {
      const at = await this.place(root, path, anywhere);
      const fs = at.fs;
      const name = at.parts.at(-1) ?? rootName(at.root);
      try {
        const s = await fs.stat(at.found);
        if (s.dir && zip) {
          const to = into(`${name}.zip`);
          const protect = await this.protectedNow();
          const skip = async (p: string, n: string) => PART.test(n) || (await this.isProtected(p, await this.#real(p, fs), protect));
          try {
            return { name: to.safe, path: to.path, size: await zipFolder(at.found, to.path, most, skip, fs) };
          } catch (e) {
            await direct.unlink(to.path).catch(() => {});
            throw e instanceof TooBig ? new DriveError("too_large", TOO_BIG) : e;
          }
        }
        if (s.dir) throw new DriveError("is_a_directory", "that is a folder");
        if (s.size > most) throw new DriveError("too_large", TOO_BIG);
        const to = into(name);
        await fs.copyTo(at.found, to.path);
        return { name: to.safe, path: to.path, size: s.size };
      } catch (e) {
        throw failed(e);
      }
    });
  }

  /// Put in the machine's trash (./trash.ts), as its own file browser does (through still.fail Helper, macOS's own, in
  /// a folder macOS protects): `no_trash` where none takes it, for the asker to say whether it goes for good.
  /// `permanent`: removed, a folder with all it holds. The root itself is not.
  remove(root: string, path: string, anywhere = false, permanent = false): Promise<void> {
    return this.#run(async () => {
      const at = await this.place(root, path, anywhere);
      if (at.parts.length === 0) throw new DriveError("invalid_request", "the root itself is not removed");
      try {
        // A link is removed as a link, not what it points at.
        await at.fs.lstat(at.entry);
        if (!permanent) {
          if ((await at.fs.trash(at.entry, (this.deps.now ?? wallNow)(), this.deps.home)) === null) throw new DriveError("no_trash", "no trash takes it here");
          return;
        }
        await at.fs.remove(at.entry);
      } catch (e) {
        throw failed(e);
      }
    });
  }

  /// A folder put into a zip of its own name (links not followed, the station's own data left out), for a member to
  /// download it: made in a folder of its own in the machine's temporary files, read from there as any file of the
  /// drive is (`root`, `path`); those made more than an hour ago are let go as another is made.
  zip(root: string, path: string, most: number, anywhere = false): Promise<{ root: string; path: string; name: string; size: number }> {
    return this.#run(async () => {
      const at = await this.place(root, path, anywhere);
      const name = `${at.parts.at(-1) ?? rootName(at.root)}.zip`;
      const zips = join(tmpdir(), "stillfail-zips");
      await sweep(zips, ZIPS_KEPT_MS, (this.deps.now ?? wallNow)());
      const dir = join(zips, randomUUID());
      try {
        if (!(await at.fs.stat(at.found)).dir) throw new DriveError("not_a_directory", "that is a file");
        await mkdir(dir, { recursive: true, mode: 0o700 });
        const protect = await this.protectedNow();
        const skip = async (p: string, n: string) => PART.test(n) || (await this.isProtected(p, await this.#real(p, at.fs), protect));
        const size = await zipFolder(at.found, join(dir, name), most, skip, at.fs);
        return { root: dir, path: name, name, size };
      } catch (e) {
        await rm(dir, { recursive: true, force: true }).catch(() => {});
        throw e instanceof TooBig ? new DriveError("too_large", TOO_BIG) : failed(e);
      }
    });
  }

  /// The folder at `path` as the file system has it, to watch (./watch.ts) for the asker, who may list it. One reached
  /// through still.fail Helper is not watched (the station does not touch it): refused, so the client stops asking (and
  /// no window is put up for it: watching is nobody's asking).
  async folderToWatch(root: string, path: string, anywhere = false): Promise<string> {
    const at = await this.place(root, path, anywhere);
    if (at.fs.helper) throw new DriveError("permission", "a folder reached through still.fail Helper is not watched");
    try {
      if (!(await stat(at.found)).isDirectory()) throw new DriveError("not_a_directory", "that is a file");
    } catch (e) {
      throw failed(e);
    }
    return at.found;
  }

  /// For the settings that name the roots: the folders in `path` (the home when none), for owners and admins to pick
  /// one. Hidden ones (a name starting with `.`) and what is protected are left out; each says whether the station may
  /// list it (`unreadable`: macOS keeps Documents, Desktop, Downloads and removable volumes from a station launchd
  /// runs). With it, the way there (`crumbs`, from the home when it is under it) and the usual places to start from
  /// (`places`: the home's own folders, the disks mounted), in the asker's words. `folders`, the names alone, for the
  /// pages from before.
  async folders(path: string, home: string, lang: Lang = "zh"): Promise<Folders> {
    const at = platform.paths.clean(path === "" ? home : path);
    if (!platform.paths.rooted(path === "" ? home : path)) throw new DriveError("invalid_request", "an absolute path");
    try {
      const { fs } = await this.#fs([{ path: at, top: at }]);
      // One the station may not list is still where the picker is: said so (`unreadable`), with nothing in it. One only
      // still.fail Helper may list, without its grant: its window asks for it on this Mac (a person opened it).
      const listed = await fs.list(at, MOST_ENTRIES).then((d) => ({ d: d.entries, unreadable: false }), async (e) => {
        const code = (e as NodeJS.ErrnoException).code;
        if (code === "grant") await this.#run(() => Promise.reject(e)).catch(() => {});
        if (code === "EPERM" || code === "EACCES" || code === "grant") return { d: [], unreadable: true };
        throw e;
      });
      const protect = await this.protectedNow();
      const entries: Folder[] = [];
      // (a folder another file system is mounted on is a disk: not opened to see whether it may be listed, as one whose
      // server is gone holds what opens it for good, 2026-11-02 Studio's ~/OrbStack)
      const here = await this.#disk(at);
      for (const d of listed.d) {
        if (d.name.startsWith(".")) continue;
        const asked = join(at, d.name);
        if (!d.stat?.dir || (await this.isProtected(asked, d.real, protect))) continue;
        if (here !== null && (await this.#disk(asked)) !== here) entries.push({ name: d.name, path: asked, unreadable: false, disk: true });
        else entries.push({ name: d.name, path: asked, unreadable: await this.#unreadable(asked) });
      }
      entries.sort((a, b) => collator.compare(a.name, b.name));
      const parent = dirname(at);
      return { path: at, parent: parent === at ? null : parent, home, folders: entries.map((e) => e.name), entries, unreadable: listed.unreadable, crumbs: crumbs(at, home, lang), places: await this.places(home, lang, protect) };
    } catch (e) {
      throw failed(e);
    }
  }

  /// Where a folder to lend usually is: the home's own folders that are there, then the disks mounted.
  private async places(home: string, lang: Lang, protect: string[]): Promise<Folder[]> {
    const found: Folder[] = [{ name: tr(lang, "station.drive.place.home"), path: home, unreadable: await this.#unreadable(home) }];
    for (const name of PLACES) {
      const path = join(home, name);
      if (await isDir(path)) found.push({ name: tr(lang, `station.drive.place.${name}`), path, unreadable: await this.#unreadable(path) });
    }
    // Disks: those the machine has (macOS's own, in /Volumes a link to /, left out).
    for (const { name, path } of await platform.disks(home)) {
      if (!(await isDir(path)) || (await real(path)) === "/" || (await this.isProtected(path, await real(path), protect))) continue;
      found.push({ name, path, unreadable: await this.#unreadable(path), disk: true });
    }
    return found;
  }

  /// Whether `path` may be a root: there, a folder, none of the station's own data.
  async checkRoot(path: string): Promise<string> {
    const about = (e: DriveError) => ((e.about = path), e);
    if (!platform.paths.rooted(path)) throw about(new DriveError("invalid_request", "not an absolute path"));
    const clean = platform.paths.clean(path);
    const { fs } = await this.#fs([{ path: clean, top: clean }]);
    const s = await this.#run(() => fs.stat(clean)).catch((e) => {
      throw about(failed(e));
    });
    if (!s.dir) throw about(new DriveError("not_a_directory", "not a folder"));
    if (await this.isProtected(clean, await this.#real(clean, fs))) throw about(new DriveError("protected", "the station's own data"));
    return clean;
  }
}

/// The machine's time, for a drive given no clock.
const wallNow = () => wall.now();

/// How long a zip made for a download is kept.
const ZIPS_KEPT_MS = 60 * 60_000;

/// The folders in `dir` made more than `ms` ago, removed.
async function sweep(dir: string, ms: number, now: number): Promise<void> {
  for (const name of await readdir(dir).catch(() => [] as string[])) {
    const at = join(dir, name);
    const s = await stat(at).catch(() => null);
    if (s && now - s.mtimeMs > ms) await rm(at, { recursive: true, force: true }).catch(() => {});
  }
}
