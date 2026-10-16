// A station's drive (zdrive, brought in): its machine's files, which members browse and change over their link: list a
// folder, read a part of a file, write one in parts, make a folder, rename, remove. A member who may write (and so may
// have an agent do anything on the machine) reaches every folder (`anywhere`): any absolute path is a root to ask from.
// The folders pinned in config.json (`drive.roots`) are the list everyone sees first, and all a read-only member
// reaches. Every path is asked relative to a root and stays in it: `..` is refused rather than worked out, and, for a
// read-only member, the path as the file system has it (its links followed) must still be under the pinned root, so a
// link pointing out is refused too. The station's own data (its key, its config, the profiles' homes, the machine's
// runtime logins) is never reachable, as for the device tools: a listing leaves it out.
import { constants, statSync } from "node:fs";
import { copyFile, lstat, mkdir, open, readdir, realpath, rename, rm, stat, unlink } from "node:fs/promises";
import { basename, dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { randomUUID } from "node:crypto";
import { platform } from "../platform/index.ts";
import { unreadableDir } from "../ops/files.ts";
import { TooBig, zipFolder } from "./zip.ts";
import { toTrash } from "./trash.ts";
import { type Lang, tr } from "../ops/i18n.ts";

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
/// Entries stated at once while listing.
const AT_ONCE = 64;

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
  const err = e as NodeJS.ErrnoException;
  switch (err.code) {
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
async function real(path: string): Promise<string> {
  try {
    return await realpath(path);
  } catch {
    const parent = dirname(path);
    return parent === path ? path : join(await real(parent), basename(path));
  }
}

/// A folder to pick a root from: its name, where it is, whether the station may list it, whether it is a disk.
export type Folder = { name: string; path: string; unreadable: boolean; disk?: boolean };
export type Folders = { path: string; parent: string | null; home: string; folders: string[]; entries: Folder[]; unreadable: boolean; crumbs: { name: string; path: string }[]; places: Folder[] };

/// The home's own folders offered as places to start from, as they are named on disk (Videos: Linux and Windows).
const PLACES = ["Desktop", "Documents", "Downloads", "Movies", "Videos", "Music", "Pictures"];

const isDir = (path: string) => stat(path).then((s) => s.isDirectory(), () => false);

/// The way to `at`: from the home when it is under it (the home first, in words), else from the top.
function crumbs(at: string, home: string, lang: Lang): { name: string; path: string }[] {
  const under = platform.paths.relativeIn(home, at);
  const [top, rest] = under !== null ? [{ name: tr(lang, "station.drive.place.home"), path: home }, under] : [{ name: platform.paths.clean("/"), path: platform.paths.clean("/") }, at];
  const out = [top];
  let path = top.path;
  for (const part of rest.split(/[\\/]/).filter((p) => p !== "")) {
    path = join(path, part);
    out.push({ name: part, path });
  }
  return out;
}

/// A path asked of the drive: where it is as asked, as found (links followed), the entry itself (its folder's links
/// followed, not its own: what a rename or a removal acts on), and its components.
type Place = { root: string; asked: string; found: string; entry: string; parts: string[] };

export type DriveDeps = {
  /// config.json as it is now.
  config: () => any;
  /// What no request may reach, even under a root (asked anew each time: a profile may be added meanwhile).
  protect: () => string[];
  now?: () => number;
  /// Whose trash what is deleted goes to (the machine's home; a test's own).
  home?: string;
};

export class Drive {
  private deps: DriveDeps;
  constructor(deps: DriveDeps) {
    this.deps = deps;
  }

  roots(): RootView[] {
    return rootsOf(this.deps.config()).map(rootView);
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
    return [...named, ...(await Promise.all(named.map(real)))];
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
    const top = await real(named);
    const asked = parts.length === 0 ? top : join(top, ...parts);
    const found = await real(asked);
    if (!anywhere && !within(found, top)) throw new DriveError("path_escape", "that path leads out of its root");
    if (await this.isProtected(asked, found)) throw new DriveError("protected", "the station's own data is not part of its drive");
    const entry = parts.length === 0 ? top : join(await real(dirname(asked)), basename(asked));
    return { root: named, asked, found, entry, parts };
  }

  /// A folder's entries, folders first, each part by name; what is protected or leads out of the root left out.
  async list(root: string, path: string, anywhere = false): Promise<{ path: string; entries: Entry[]; truncated: boolean }> {
    const at = await this.place(root, path, anywhere);
    const top = await real(at.root);
    try {
      const dirents = await readdir(at.found, { withFileTypes: true });
      const entries: Entry[] = [];
      const protect = await this.protectedNow();
      // The first by the order shown (folders first, then by name) when there are more than are listed, not the disk's.
      const visible = dirents.filter((d) => !PART.test(d.name)).sort((a, b) => (a.isDirectory() !== b.isDirectory() ? (a.isDirectory() ? -1 : 1) : collator.compare(a.name, b.name)));
      const shown = visible.slice(0, MOST_ENTRIES);
      for (let i = 0; i < shown.length; i += AT_ONCE) {
        const batch = await Promise.all(
          shown.slice(i, i + AT_ONCE).map(async (d): Promise<Entry | null> => {
            const asked = join(at.found, d.name);
            const found = d.isSymbolicLink() ? await real(asked) : asked;
            if ((!anywhere && !within(found, top)) || (await this.isProtected(asked, found, protect))) return null;
            try {
              const s = await stat(found);
              const dir = s.isDirectory();
              return { name: d.name, dir, size: dir ? 0 : s.size, mtime: Math.round(s.mtimeMs), type: dir ? "" : typeOf(d.name) };
            } catch {
              // A broken link, or one gone meanwhile.
              return null;
            }
          }),
        );
        for (const e of batch) if (e !== null) entries.push(e);
      }
      entries.sort((a, b) => (a.dir !== b.dir ? (a.dir ? -1 : 1) : collator.compare(a.name, b.name) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0)));
      return { path: at.parts.join("/"), entries, truncated: visible.length > shown.length };
    } catch (e) {
      throw failed(e);
    }
  }

  async stat(root: string, path: string, anywhere = false): Promise<Entry> {
    const at = await this.place(root, path, anywhere);
    try {
      const s = await stat(at.found);
      const dir = s.isDirectory();
      const name = at.parts.at(-1) ?? rootName(at.root);
      return { name, dir, size: dir ? 0 : s.size, mtime: Math.round(s.mtimeMs), type: dir ? "" : typeOf(name) };
    } catch (e) {
      throw failed(e);
    }
  }

  /// `length` bytes of a file from `offset` (fewer at its end, none past it), with its whole size and time.
  async read(root: string, path: string, offset: number, length: number, anywhere = false): Promise<{ bytes: Buffer; total: number; mtime: number; type: string }> {
    if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(length) || length < 0 || length > MAX_READ) throw new DriveError("invalid_request", "invalid offset or length");
    const at = await this.place(root, path, anywhere);
    let handle;
    try {
      handle = await open(at.found, constants.O_RDONLY);
      const s = await handle.stat();
      if (s.isDirectory()) throw new DriveError("is_a_directory", "that is a folder");
      const want = Math.max(0, Math.min(length, s.size - offset));
      const bytes = Buffer.alloc(want);
      let got = 0;
      while (got < want) {
        const { bytesRead } = await handle.read(bytes, got, want - got, offset + got);
        if (bytesRead === 0) break;
        got += bytesRead;
      }
      return { bytes: bytes.subarray(0, got), total: s.size, mtime: Math.round(s.mtimeMs), type: typeOf(at.parts.at(-1) ?? "") };
    } catch (e) {
      throw failed(e);
    } finally {
      await handle?.close();
    }
  }

  /// A part of a file being written (an upload `id` of the asker's choosing): its bytes at `offset` of `total`. The file
  /// is put together beside where it goes and put there whole once its last part is in (synced, then renamed), so
  /// nobody sees half of it. A part asked again is written again (the same bytes); one that leaves a gap is refused
  /// with how much the station has (`upload_lost`), to go on from there. An existing file is replaced only when asked.
  async upload(root: string, path: string, id: string, offset: number, total: number, body: Buffer, replace: boolean, anywhere = false): Promise<{ have: number; entry: Entry | null }> {
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) throw new DriveError("invalid_request", "an upload's id is 1 to 64 letters, digits, - or _");
    if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(total) || total < 0 || offset + body.length > total) throw new DriveError("invalid_request", "invalid offset or total");
    const at = await this.place(root, path, anywhere);
    const name = at.parts.at(-1);
    if (name === undefined) throw new DriveError("invalid_request", "a file needs a name");
    const folder = dirname(at.found);
    const part = join(folder, `.stillfail-up-${id}.part`);
    const taken = async () => {
      const s = await stat(at.found).catch(() => null);
      if (s?.isDirectory()) throw new DriveError("is_a_directory", "there is a folder by that name");
      if (s !== null && !replace) throw new DriveError("exists", "there is already a file by that name");
    };
    let handle;
    // Once its last part is in: what fails from there leaves nothing behind.
    let last = false;
    try {
      if (offset === 0) {
        await taken();
        await this.sweep(folder);
        handle = await open(part, "w");
      } else {
        handle = await open(part, "r+").catch((e) => {
          if ((e as NodeJS.ErrnoException).code === "ENOENT") throw new DriveError("upload_lost", "the station has none of that upload", 0);
          throw e;
        });
        const have = (await handle.stat()).size;
        if (have < offset) throw new DriveError("upload_lost", "a part before this one is missing", have);
      }
      let written = 0;
      while (written < body.length) written += (await handle.write(body, written, body.length - written, offset + written)).bytesWritten;
      const have = (await handle.stat()).size;
      if (offset + body.length < total) return { have, entry: null };
      last = true;
      await handle.truncate(total);
      await handle.sync();
      await handle.close();
      handle = undefined;
      await taken();
      await rename(part, at.found);
      return { have: total, entry: await this.stat(root, at.parts.join("/"), anywhere) };
    } catch (e) {
      if (last) await unlink(part).catch(() => {});
      throw failed(e);
    } finally {
      await handle?.close();
    }
  }

  /// Uploads in `folder` left unfinished long ago, removed.
  private async sweep(folder: string) {
    const now = (this.deps.now ?? Date.now)();
    for (const name of await readdir(folder).catch(() => [] as string[])) {
      if (!PART.test(name)) continue;
      const s = await stat(join(folder, name)).catch(() => null);
      if (s !== null && now - s.mtimeMs > STALE_MS) await unlink(join(folder, name)).catch(() => {});
    }
  }

  async mkdir(root: string, path: string, anywhere = false): Promise<Entry> {
    const at = await this.place(root, path, anywhere);
    if (at.parts.length === 0) throw new DriveError("exists", "the root is there");
    try {
      if (await stat(at.found).then(() => true, () => false)) throw new DriveError("exists", "there is already one by that name");
      await mkdir(at.found, { recursive: true });
    } catch (e) {
      throw failed(e);
    }
    return this.stat(root, at.parts.join("/"), anywhere);
  }

  /// Renamed or moved within its root; what is there already is not replaced (a change of case alone is a rename).
  async rename(root: string, from: string, to: string, anywhere = false): Promise<Entry> {
    const a = await this.place(root, from, anywhere);
    const b = await this.place(root, to, anywhere);
    if (a.parts.length === 0 || b.parts.length === 0) throw new DriveError("invalid_request", "the root itself is not renamed");
    if (within(b.entry, a.entry) && key(b.entry) !== key(a.entry)) throw new DriveError("invalid_request", "a folder cannot go into itself");
    try {
      await lstat(a.entry);
      const there = await lstat(b.entry).then(() => true, () => false);
      if (there && key(a.entry) !== key(b.entry)) throw new DriveError("exists", "there is already one by that name");
      await mkdir(dirname(b.entry), { recursive: true });
      await rename(a.entry, b.entry);
    } catch (e) {
      throw failed(e);
    }
    return this.stat(root, b.parts.join("/"), anywhere);
  }

  /// A file copied to `into` (where a chat's uploads wait for the message that sends them), for a member to send it in a
  /// chat as if it had been uploaded: a clone where the disk can make one (APFS, btrfs), so even a big one costs nothing.
  /// `zip`: a folder put into a zip of its own name instead (links not followed, the station's own data left out).
  async stage(root: string, path: string, into: (name: string) => { safe: string; path: string }, most: number, anywhere = false, zip = false): Promise<{ name: string; path: string; size: number }> {
    const at = await this.place(root, path, anywhere);
    const name = at.parts.at(-1) ?? rootName(at.root);
    try {
      const s = await stat(at.found);
      if (s.isDirectory() && zip) {
        const to = into(`${name}.zip`);
        const protect = await this.protectedNow();
        const skip = async (p: string, n: string) => PART.test(n) || (await this.isProtected(p, await real(p), protect));
        try {
          return { name: to.safe, path: to.path, size: await zipFolder(at.found, to.path, most, skip) };
        } catch (e) {
          await unlink(to.path).catch(() => {});
          throw e instanceof TooBig ? new DriveError("too_large", TOO_BIG) : e;
        }
      }
      if (s.isDirectory()) throw new DriveError("is_a_directory", "that is a folder");
      if (s.size > most) throw new DriveError("too_large", TOO_BIG);
      const to = into(name);
      await copyFile(at.found, to.path, constants.COPYFILE_EXCL | constants.COPYFILE_FICLONE);
      return { name: to.safe, path: to.path, size: s.size };
    } catch (e) {
      throw failed(e);
    }
  }

  /// Put in the machine's trash (./trash.ts), as its own file browser does: `no_trash` where none takes it, for the
  /// asker to say whether it goes for good. `permanent`: removed, a folder with all it holds. The root itself is not.
  async remove(root: string, path: string, anywhere = false, permanent = false): Promise<void> {
    const at = await this.place(root, path, anywhere);
    if (at.parts.length === 0) throw new DriveError("invalid_request", "the root itself is not removed");
    try {
      // A link is removed as a link, not what it points at.
      await lstat(at.entry);
      if (!permanent) {
        if ((await toTrash(at.entry, this.deps.home)) === null) throw new DriveError("no_trash", "no trash takes it here");
        return;
      }
      await rm(at.entry, { recursive: true });
    } catch (e) {
      throw failed(e);
    }
  }

  /// A folder put into a zip of its own name (links not followed, the station's own data left out), for a member to
  /// download it: made in a folder of its own in the machine's temporary files, read from there as any file of the
  /// drive is (`root`, `path`); those made more than an hour ago are let go as another is made.
  async zip(root: string, path: string, most: number, anywhere = false): Promise<{ root: string; path: string; name: string; size: number }> {
    const at = await this.place(root, path, anywhere);
    const name = `${at.parts.at(-1) ?? rootName(at.root)}.zip`;
    const zips = join(tmpdir(), "stillfail-zips");
    await sweep(zips, ZIPS_KEPT_MS);
    const dir = join(zips, randomUUID());
    try {
      if (!(await stat(at.found)).isDirectory()) throw new DriveError("not_a_directory", "that is a file");
      await mkdir(dir, { recursive: true, mode: 0o700 });
      const protect = await this.protectedNow();
      const skip = async (p: string, n: string) => PART.test(n) || (await this.isProtected(p, await real(p), protect));
      const size = await zipFolder(at.found, join(dir, name), most, skip);
      return { root: dir, path: name, name, size };
    } catch (e) {
      await rm(dir, { recursive: true, force: true }).catch(() => {});
      throw e instanceof TooBig ? new DriveError("too_large", TOO_BIG) : failed(e);
    }
  }

  /// The folder at `path` as the file system has it, to watch (./watch.ts) for the asker, who may list it.
  async folderToWatch(root: string, path: string, anywhere = false): Promise<string> {
    const at = await this.place(root, path, anywhere);
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
      // One the station may not list is still where the picker is: said so (`unreadable`), with nothing in it.
      const listed = await readdir(at, { withFileTypes: true }).then((d) => ({ d, unreadable: false }), (e) => {
        const code = (e as NodeJS.ErrnoException).code;
        if (code === "EPERM" || code === "EACCES") return { d: [], unreadable: true };
        throw e;
      });
      const dirents = listed.d;
      const protect = await this.protectedNow();
      const entries: Folder[] = [];
      for (const d of dirents) {
        if (d.name.startsWith(".")) continue;
        const asked = join(at, d.name);
        let dir = d.isDirectory();
        if (d.isSymbolicLink()) dir = await stat(asked).then((s) => s.isDirectory(), () => false);
        if (dir && !(await this.isProtected(asked, await real(asked), protect))) entries.push({ name: d.name, path: asked, unreadable: unreadableDir(asked) });
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
    const found: Folder[] = [{ name: tr(lang, "station.drive.place.home"), path: home, unreadable: unreadableDir(home) }];
    for (const name of PLACES) {
      const path = join(home, name);
      if (await isDir(path)) found.push({ name: tr(lang, `station.drive.place.${name}`), path, unreadable: unreadableDir(path) });
    }
    // Disks: macOS mounts them in /Volumes (the system's own there is a link to /), Linux in /media/<user> and /mnt.
    for (const mounts of ["/Volumes", join("/media", basename(home)), "/mnt"]) {
      for (const name of (await readdir(mounts).catch(() => [] as string[])).sort((a, b) => collator.compare(a, b))) {
        if (name.startsWith(".")) continue;
        const path = join(mounts, name);
        if (!(await isDir(path)) || (await real(path)) === "/" || (await this.isProtected(path, await real(path), protect))) continue;
        found.push({ name, path, unreadable: unreadableDir(path), disk: true });
      }
    }
    return found;
  }

  /// Whether `path` may be a root: there, a folder, none of the station's own data.
  async checkRoot(path: string): Promise<string> {
    const about = (e: DriveError) => ((e.about = path), e);
    if (!platform.paths.rooted(path)) throw about(new DriveError("invalid_request", "not an absolute path"));
    const clean = platform.paths.clean(path);
    const s = await stat(clean).catch((e) => {
      throw about(failed(e));
    });
    if (!s.isDirectory()) throw about(new DriveError("not_a_directory", "not a folder"));
    if (await this.isProtected(clean, await real(clean))) throw about(new DriveError("protected", "the station's own data"));
    return clean;
  }
}

/// How long a zip made for a download is kept.
const ZIPS_KEPT_MS = 60 * 60_000;

/// The folders in `dir` made more than `ms` ago, removed.
async function sweep(dir: string, ms: number): Promise<void> {
  const now = Date.now();
  for (const name of await readdir(dir).catch(() => [] as string[])) {
    const at = join(dir, name);
    const s = await stat(at).catch(() => null);
    if (s && now - s.mtimeMs > ms) await rm(at, { recursive: true, force: true }).catch(() => {});
  }
}
