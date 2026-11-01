// How the drive (drive.ts) reaches the machine's files: directly, or, for the folders macOS keeps from a station launchd
// runs, through still.fail Helper (helper/files.ts), which holds the grants. The same few operations either way, on
// paths the drive has already checked (the helper checks them again against the roots it is told).
import { constants, lstatSync } from "node:fs";
import { copyFile, lstat, mkdir, open, readdir, readFile, realpath, rename, rm, stat, unlink } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";
import { platform } from "../platform/index.ts";
import { toTrash } from "./trash.ts";

export type Stat = { dir: boolean; file: boolean; link: boolean; size: number; mtimeMs: number };
/// A folder's entry: whether it is a link, where it leads (links followed; itself when not a link), and what is there
/// (null: a link to nothing, one gone meanwhile, one leading where it may not).
export type Listed = { name: string; link: boolean; real: string; stat: Stat | null };
/// A part written: the file's size after (`short`: it was smaller than `atLeast`, so nothing was written).
export type Written = { size: number; short?: boolean };
export type Write = { create: boolean; offset: number; data: Buffer; atLeast?: number; truncate?: number; sync?: boolean };

export interface Fs {
  /// Whether it goes through still.fail Helper.
  readonly helper: boolean;
  /// A folder's entries, at most `most` of them stated (`more`: there were more).
  list(dir: string, most: number): Promise<{ entries: Listed[]; more: boolean }>;
  names(dir: string): Promise<string[]>;
  stat(path: string): Promise<Stat>;
  lstat(path: string): Promise<Stat>;
  /// Links followed, as far as the path exists (what is not there yet is under its nearest parent that is).
  real(path: string): Promise<string>;
  /// `length` bytes from `offset` (fewer at the end, none past it), with the file's size and time; EISDIR for a folder.
  read(path: string, offset: number, length: number): Promise<{ bytes: Buffer; size: number; mtimeMs: number }>;
  readAll(path: string): Promise<Buffer>;
  /// The file copied to `to`, a new file of the station's own (a clone where the disk can).
  copyTo(path: string, to: string): Promise<void>;
  /// `data` written at `offset` (the file made anew with `create`, else it must be there), then truncated to
  /// `truncate` and synced, as asked.
  write(path: string, w: Write): Promise<Written>;
  rename(from: string, to: string): Promise<void>;
  mkdir(path: string, recursive: boolean): Promise<void>;
  /// A folder with all it holds; anything else (a link too) itself.
  remove(path: string): Promise<void>;
  /// Put in the machine's trash, as its own file browser does: where it is there now, null where no trash takes it.
  /// `now`: when (the freedesktop trash notes it); `home`: whose trash (the machine's when none).
  trash(path: string, now: number, home?: string): Promise<string | null>;
  unlink(path: string): Promise<void>;
}

const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

const statOf = (s: import("node:fs").Stats): Stat => ({ dir: s.isDirectory(), file: s.isFile(), link: s.isSymbolicLink(), size: s.isDirectory() ? 0 : s.size, mtimeMs: s.mtimeMs });

/// Entries stated at once while listing.
const AT_ONCE = 64;

/// Links followed, as far as the path exists.
export async function realOf(path: string): Promise<string> {
  try {
    return await realpath(path);
  } catch {
    const parent = dirname(path);
    return parent === path ? path : join(await realOf(parent), basename(path));
  }
}

export const direct: Fs = {
  helper: false,
  async list(dir, most) {
    // The first by the order shown (folders first, then by name) when there are more than are listed, not the disk's.
    const dirents = (await readdir(dir, { withFileTypes: true })).sort((a, b) => (a.isDirectory() !== b.isDirectory() ? (a.isDirectory() ? -1 : 1) : collator.compare(a.name, b.name)));
    const shown = dirents.slice(0, most);
    const entries: Listed[] = [];
    for (let i = 0; i < shown.length; i += AT_ONCE) {
      entries.push(
        ...(await Promise.all(
          shown.slice(i, i + AT_ONCE).map(async (d): Promise<Listed> => {
            const path = join(dir, d.name);
            const link = d.isSymbolicLink();
            const real = link ? await realOf(path) : path;
            return { name: d.name, link, real, stat: await stat(real).then(statOf, () => null) };
          }),
        )),
      );
    }
    return { entries, more: dirents.length > shown.length };
  },
  names: (dir) => readdir(dir),
  stat: async (path) => statOf(await stat(path)),
  lstat: async (path) => statOf(await lstat(path)),
  real: realOf,
  async read(path, offset, length) {
    const handle = await open(path, constants.O_RDONLY);
    try {
      const s = await handle.stat();
      if (s.isDirectory()) throw Object.assign(new Error("that is a folder"), { code: "EISDIR" });
      const want = Math.max(0, Math.min(length, s.size - offset));
      const bytes = Buffer.alloc(want);
      let got = 0;
      while (got < want) {
        const { bytesRead } = await handle.read(bytes, got, want - got, offset + got);
        if (bytesRead === 0) break;
        got += bytesRead;
      }
      return { bytes: bytes.subarray(0, got), size: s.size, mtimeMs: s.mtimeMs };
    } finally {
      await handle.close();
    }
  },
  readAll: (path) => readFile(path),
  copyTo: (path, to) => copyFile(path, to, constants.COPYFILE_EXCL | constants.COPYFILE_FICLONE),
  async write(path, w) {
    const handle = await open(path, w.create ? "w" : "r+");
    try {
      const before = (await handle.stat()).size;
      if (w.atLeast !== undefined && before < w.atLeast) return { size: before, short: true };
      let written = 0;
      while (written < w.data.length) written += (await handle.write(w.data, written, w.data.length - written, w.offset + written)).bytesWritten;
      if (w.truncate !== undefined) await handle.truncate(w.truncate);
      if (w.sync) await handle.sync();
      return { size: (await handle.stat()).size };
    } finally {
      await handle.close();
    }
  },
  rename: (from, to) => rename(from, to),
  mkdir: async (path, recursive) => void (await mkdir(path, { recursive })),
  async remove(path) {
    await lstat(path);
    await rm(path, { recursive: true });
  },
  trash: (path, now, home) => toTrash(path, platform.trash, now, home),
  unlink: (path) => unlink(path),
};

/// The folders macOS keeps from a process nobody gave access to (and so from a station launchd runs): the home's
/// Documents, Desktop and Downloads, and the disks mounted, in /Volumes other than the system's own (a link to / there)
/// or wherever else one is (`mounts`: OrbStack's NFS in the home). The one `path` is (or is under), by name, case aside
/// as macOS's disks have it; null for any other path.
export function protectedTop(path: string, home = homedir(), mounts = platform.mounts()): string | null {
  const place = protectedPlace(path, home, mounts);
  return place?.helper ? place.top : null;
}

/// The folders macOS protects, by name (nothing under them touched): those still.fail Helper opens (`helper`, as
/// `protectedTop`), and iCloud Drive and the other file providers' folders (~/Library/Mobile Documents,
/// ~/Library/CloudStorage), which macOS protects too but the helper has no grant for. The one `path` is (or is under);
/// null for any other path. The drive reaches the first through the helper; a directory the station is to work in
/// (ops/places.ts) is never looked at by the station's own thread in any of them. A disk is one by where it is mounted
/// (`mounts`, the platform's), not by its path's name alone: opening one mounted elsewhere waits on macOS asking the
/// person as one in /Volumes does (2026-11-02, Studio's ~/OrbStack held the station for good).
export function protectedPlace(path: string, home = homedir(), mounts = platform.mounts()): { top: string; helper: boolean } | null {
  const lower = path.toLowerCase();
  const under = (top: string) => lower === top.toLowerCase() || lower.startsWith(`${top.toLowerCase()}/`);
  for (const name of ["Documents", "Desktop", "Downloads"]) {
    const top = join(home, name);
    if (under(top)) return { top, helper: true };
  }
  for (const name of ["Library/Mobile Documents", "Library/CloudStorage"]) {
    const top = join(home, name);
    if (under(top)) return { top, helper: false };
  }
  // (mounted elsewhere: the deepest mount it is under)
  let mount: string | null = null;
  for (const m of mounts) if (!lower.startsWith("/volumes/") && under(m) && m.length > (mount?.length ?? 0)) mount = m;
  if (mount !== null) return { top: mount, helper: true };
  const disk = /^\/volumes\/([^/]+)/.exec(lower);
  if (disk === null) return null;
  const top = `/Volumes/${path.split("/")[2]}`;
  try {
    return lstatSync(top).isSymbolicLink() ? null : { top, helper: true };
  } catch {
    return null;
  }
}

/// What still.fail Helper says of a protected folder: the grant that opens it, and whether macOS gave it (`unknown`:
/// never asked; `denied`: refused).
export type Grant = "documents" | "desktop" | "downloads" | "removable" | "network";
export type Access = { grant: Grant; state: "granted" | "denied" | "unknown" };

/// The drive's way to still.fail Helper's side (helper/files.ts).
export interface Protected {
  /// The helper's operations, for a request that may reach `roots` and none of `protect`.
  fs(scope: { roots: string[]; protect: string[] }): Fs;
  /// What is known of a protected folder (its top), without asking; undefined before it is known.
  known(top: string): Access | undefined;
  /// Looked at in the background (the helper started for it), told (`changed`) when it is not what was known.
  check(tops: string[]): void;
  /// The helper's window asking for `grant`, on this Mac, unless it is up or was shown for it a moment ago: `up`,
  /// `closed` (shown a moment ago, closed since, not shown again yet) or `none` (it could not be shown).
  ask(grant: Grant, top: string): Promise<"up" | "closed" | "none">;
}
