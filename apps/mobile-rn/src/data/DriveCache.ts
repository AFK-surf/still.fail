// Files of a drive kept on the phone once read (data/DriveCache.kt), so opening one again does not fetch it again: a
// text the reader reads, a picture, PDF or page the viewer shows, a file handed to another app. Each is kept by where it
// is (station, root, path) and as it was (its mtime and size, as its folder says): a file changed on the station is
// fetched anew and the old one deleted. What is kept is the file from its start (the reader reads only the first 16 MB
// of a longer one), gone on from when more is asked; a fetch cut off is gone on from next time. The least lately opened
// go once all pass FILES_MAX. Videos and songs are kept apart, by the ranges played (PLAYED_MAX; the player's cache over
// DriveSource). Both are shown and cleared in settings → files kept (KeptFiles.tsx).
import { CryptoDigestAlgorithm, digestStringAsync } from "expo-crypto";
import { Directory, File, Paths } from "expo-file-system";
import { DRIVE_PART, type StationApi } from "./Calls";

const TAG = "drive-cache";

/** One at a time per file (kotlinx's Mutex): `locked` while a fetch of it runs. */
class Mutex {
  #tail: Promise<void> = Promise.resolve();
  #holders = 0;
  get isLocked(): boolean { return this.#holders > 0; }
  async withLock<T>(run: () => Promise<T>): Promise<T> {
    this.#holders++;
    const before = this.#tail;
    let release!: () => void;
    this.#tail = new Promise<void>((r) => { release = r; });
    try {
      await before;
      return await run();
    } finally {
      this.#holders--;
      release();
    }
  }
}

/** A file kept: where on the phone, and the whole file's size as the station last said. */
export class Kept {
  constructor(readonly file: File, readonly total: number) {}
}

/** Files read whole (or from their start): the least lately opened go past this. */
const FILES_MAX = 512 * 1024 * 1024;
/** Videos and songs, by the ranges played. */
const PLAYED_MAX = 1536 * 1024 * 1024;
/** How many times a file found changed while it is fetched is fetched again from its start before what came is taken. */
const CHANGED_TRIES = 2;
/**
 * When a file's place in the cache was last opened, in a file of its own beside it (the phone's file API sets no
 * folder's time): what the least lately opened are told by. A kept file's own name never starts with `.` (named).
 */
const OPENED = ".opened";

const locks = new Map<string, Mutex>();
const lock = (id: string) => { let m = locks.get(id); if (!m) { m = new Mutex(); locks.set(id, m); } return m; };
const busy = (id: string) => locks.get(id)?.isLocked === true;

const dir = () => new Directory(Paths.cache, "drive");
const playedDir = () => new Directory(Paths.cache, "drive-played");

/** A file's own name in the cache: where it is, hashed (a path may be long, and say more than a name should). */
async function idOf(station: string, root: string, path: string): Promise<string> {
  const hex = await digestStringAsync(CryptoDigestAlgorithm.SHA256, `${station}\n${root}\n${path}`);
  return hex.toLowerCase().substring(0, 32);
}

const home = (id: string, mtime: number, size: number) => new Directory(dir(), `${id}-${mtime}-${size}`);
function named(home: Directory, path: string): File {
  const last = path.substring(path.lastIndexOf("/") + 1).replace(/[\u0000-\u001f]/g, "_").replace(/^\.+/, "").substring(0, 120);
  return new File(home, last || "file");
}

const lengthOf = (f: File) => (f.exists ? f.size : 0);

function read(file: File, n: number): Uint8Array {
  if (n <= 0) return new Uint8Array(0);
  const h = file.open();
  try {
    h.offset = 0;
    return h.readBytes(n);
  } finally {
    h.close();
  }
}

function sizeOf(f: File | Directory): number {
  if (f instanceof Directory) {
    if (!f.exists) return 0;
    return f.list().reduce((n, it) => n + sizeOf(it), 0);
  }
  return lengthOf(f);
}

function openedOf(h: Directory): number {
  try {
    const marker = new File(h, OPENED);
    return marker.exists ? Number(marker.textSync()) || 0 : 0;
  } catch {
    return 0;
  }
}

function touch(h: Directory): void {
  const marker = new File(h, OPENED);
  if (!marker.exists) marker.create();
  marker.write(String(Date.now()));
}

/** The least lately opened go while all of them are past FILES_MAX: never the one just opened, nor one being fetched. */
function trim(keep: Directory): void {
  const all = dir();
  if (!all.exists) return;
  const homes = all.list().filter((it): it is Directory => it instanceof Directory).map((h) => ({ h, at: openedOf(h) })).sort((a, b) => b.at - a.at);
  let total = 0;
  for (const { h } of homes) {
    const n = sizeOf(h);
    total += n;
    if (total <= FILES_MAX || h.uri === keep.uri || busy(h.name.split("-")[0]!)) continue;
    h.delete();
    total -= n;
  }
}

/**
 * The file `path` of `root` (`mtime` and `size` as its folder says) kept on the phone, its first `upto` bytes at least
 * (all of it by default): what is kept already is not fetched again, what is missing is, a part at a time. `onProgress`
 * hears the bytes kept so far and the whole size as they come. Found changed on the station meanwhile, it is fetched
 * anew from its start, as it is now.
 */
async function fetch(api: StationApi, root: string, path: string, mtime: number, size: number, upto: number = Number.MAX_SAFE_INTEGER, onProgress: (got: number, total: number) => void = () => {}): Promise<Kept> {
  const id = await idOf(api.station, root, path);
  return lock(id).withLock(async () => {
    let m = mtime;
    let total = size;
    let tries = 0;
    let kept: Kept | null = null;
    while (kept === null) {
      const h = home(id, m, total);
      const file = named(h, path);
      // What was kept of it before it changed.
      const all = dir();
      if (!all.exists) all.create({ intermediates: true, idempotent: true });
      for (const it of all.list()) if (it.name.startsWith(`${id}-`) && it.uri !== h.uri) it.delete();
      if (!h.exists) h.create({ intermediates: true, idempotent: true });
      if (lengthOf(file) > total) file.delete();
      const want = Math.min(upto, total);
      let have = lengthOf(file);
      let changed = false;
      if (have < want) {
        if (!file.exists) file.create();
        const out = file.open();
        try {
          out.offset = have;
          onProgress(have, total);
          while (have < want) {
            const from = have;
            const got = await api.driveRead(root, path, have, Math.min(DRIVE_PART, want - have), (n: number) => onProgress(from + n, total));
            if (got.total !== total || (got.mtime != null && got.mtime !== m)) {
              console.info(TAG, `${path} changed: ${total} B at ${m}, now ${got.total} B at ${got.mtime}`);
              total = got.total; m = got.mtime ?? m; changed = true;
              break;
            }
            if (got.bytes.length === 0) break;
            out.writeBytes(got.bytes);
            have += got.bytes.length;
            onProgress(have, total);
          }
        } finally {
          out.close();
        }
      }
      if (changed && tries++ < CHANGED_TRIES) continue;
      touch(h);
      trim(h);
      kept = new Kept(file, total);
    }
    return kept;
  });
}

/** The first `upto` bytes of the file (all of it by default), kept or fetched as [fetch] does, and its whole size. */
async function bytes(api: StationApi, root: string, path: string, mtime: number, size: number, upto: number = Number.MAX_SAFE_INTEGER, onProgress: (got: number, total: number) => void = () => {}): Promise<[Uint8Array, number]> {
  const kept = await fetch(api, root, path, mtime, size, upto, onProgress);
  return [read(kept.file, Math.min(upto, lengthOf(kept.file))), kept.total];
}

/** The first `length` bytes of the file if that much is kept (nothing fetched); else null. */
async function head(station: string, root: string, path: string, mtime: number, size: number, length: number): Promise<Uint8Array | null> {
  const file = named(home(await idOf(station, root, path), mtime, size), path);
  const n = Math.min(length, size);
  return lengthOf(file) < n ? null : read(file, n);
}

// ── played ──────────────────────────────────────────────────────────

/**
 * Videos and songs as played: one cache for the app, in its own folder, the least lately played going past PLAYED_MAX
 * (media3's SimpleCache over a LeastRecentlyUsedCacheEvictor on Android).
 */
function played(): Directory {
  // NATIVE: a ranged cache of what was played (media3's SimpleCache in playedDir, LRU at PLAYED_MAX, keyed by playedKey) under the player's drive data source; here only its folder, measured and cleared.
  const d = playedDir();
  if (!d.exists) d.create({ intermediates: true, idempotent: true });
  return d;
}

/** What a video or song is kept by: where it is and as it was (a file changed is another). */
const playedKey = (station: string, root: string, path: string, mtime: number, size: number) => `${station}\n${root}\n${path}\n${mtime}\n${size}`;

/** Everything kept: files and what was played. */
const sizeAll = (): number => sizeOf(dir()) + sizeOf(played());

/** Deletes everything kept: read again from the stations when opened. */
function clear(): void {
  const all = dir();
  if (all.exists) for (const it of all.list()) if (!busy(it.name.split("-")[0]!)) it.delete();
  for (const it of played().list()) it.delete();
}

export const DriveCache = {
  FILES_MAX,
  PLAYED_MAX,
  /** Nothing to start here (the Android app hands it its context); kept so the app starts it where the Kotlin does. */
  start() {},
  dir,
  playedDir,
  fetch,
  bytes,
  head,
  played,
  playedKey,
  size: sizeAll,
  clear,
};
