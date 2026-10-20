// The photo library (docs/media-service.md 照片): the folders it is made of, each an album, and the backup folder the
// phones upload to; indexed through the station's local API as the member who last set the folders (an owner or admin;
// until one has, as the last member who may write who asked for photos, and the backup folder only), followed by the
// station's drive/watch on the folders it knows (non-recursive: the folders, then the ones changed lately, up to
// WATCHES) and gone over whole every hour. Thumbnails through the station (/thumb, /poster) or macOS's sips (HEIC, GIF),
// kept in the module's folder by the file's id, time and size.
import { execFile } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { createReadStream } from "node:fs";
import { copyFile, mkdir, open, readFile, readdir, rename, rm, stat, unlink, utimes, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join, posix } from "node:path";
import { MediaError, bad } from "./errors.ts";
import { sniff } from "./images.ts";
import { HEAD, type Kind, type Meta, extOf, kindOf, metaOf } from "./photometa.ts";
import type { Viewer } from "./server.ts";
import { type DriveEntry, PART, type Picture, type StationLink, list, picture, readAll, readPart, stat as driveStat, watch } from "./station.ts";
import type { PhotoRow, Store } from "./store.ts";
import { readBmp, thumbHash } from "./thumbhash.ts";

/// An item's id: the first 20 hex digits of sha256(root + "\n" + path); a library folder's (its album's) the same.
export const photoId = (root: string, path: string) => createHash("sha256").update(`${root}\n${path}`).digest("hex").slice(0, 20);

/// The backup folder when none is given (MEDIA_BACKUP_DIR).
export const defaultBackup = () => process.env.MEDIA_BACKUP_DIR || join(homedir(), "Pictures", "still.fail");

/// The station's local date of a time, YYYY-MM-DD.
export function localDay(ms: number): string {
  const d = new Date(ms);
  return `${String(d.getFullYear()).padStart(4, "0")}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/// The most folders a library has.
export const MOST_FOLDERS = 64;
/// The most folders watched at once (the station keeps 256 watches for everyone).
export const WATCHES = 32;
/// How deep a walk goes, and how many folders one pass lists at most.
export const DEPTH = 32;
export const MOST_DIRS = 100_000;
/// How often the library is gone over whole.
export const HOURLY = 60 * 60 * 1000;
/// Folders a NAS or a system keeps its own things in; bundles that hold a library of their own.
const SKIP_DIRS = new Set(["@eaDir", "@Recycle", "@Recently-Snapshot", "#recycle", "#snapshot", "$RECYCLE.BIN", "System Volume Information", "node_modules"]);
const BUNDLES = /\.(photoslibrary|photolibrary|migratedphotolibrary|aplibrary|lrdata|app)$/i;
/// What sips turns into a JPEG here (the station's /thumb does not read them).
const BY_SIPS = new Set(["heic", "heif", "gif"]);
/// The largest file given to sips, and a GIF shown as it is where there is no sips.
const MOST_SIPS = 128 * 1024 * 1024;
/// The station's long poll asked as this.
const WATCH_ID = "media-photos";
/// Upload parts left this long are removed.
const STALE_UPLOAD = 7 * 24 * 60 * 60 * 1000;
/// While many thumbnails are made, the library is said to have changed at most this often.
export const FILL_TOLD = 15_000;

export type Folder = { root: string; path: string };
type Album = Folder & { id: string; title: string };
/// A folder the library knows (listed in the last pass), for its watch.
type Dir = { root: string; dir: string; album: string; mtime: number };

export type Thumb = { bytes: Buffer; type: string; w: number; h: number; hash: string | null };

export type LibraryOptions = {
  store: Store;
  link: StationLink;
  /// The module's folder: thumbnails, uploads in progress, sips' scratch.
  dir: string;
  /// The backup folder (absolute).
  backup: string;
  /// sips (macOS), or null where there is none.
  sips: string | null;
  /// The library changed (debounced by the caller).
  changed: () => void;
};

export const hidden = (name: string) => name.startsWith(".");
export const skipDir = (name: string) => hidden(name) || SKIP_DIRS.has(name) || BUNDLES.test(name);
export const parentOf = (p: string) => {
  const d = posix.dirname(p);
  return d === "." || d === "/" ? "" : d;
};
export const join2 = (dir: string, name: string) => (dir ? `${dir}/${name}` : name);
export const under = (dir: string, p: string) => dir === "" || p === dir || p.startsWith(`${dir}/`);
export const dirKey = (root: string, dir: string) => `${root}\n${dir}`;

function run(cmd: string, args: string[]): Promise<void> {
  return new Promise((done, fail) => execFile(cmd, args, { timeout: 60_000 }, (e) => (e ? fail(e) : done())));
}

/// A folder's path as kept: relative, no `.`/`..`, no slashes at either end.
export function cleanPath(p: string): string {
  const parts = p.split("/").filter((x) => x !== "" && x !== ".");
  if (parts.some((x) => x === "..")) throw bad("路径（path）不能含 ..");
  return parts.join("/");
}

export class Library {
  readonly #o: LibraryOptions;
  #closed = false;
  /// What changes the index, one at a time: passes and folders' scans.
  #chain: Promise<unknown> = Promise.resolve();
  #pending = 0;
  #passQueued = false;
  #filling: Promise<void> | null = null;
  #hourly: NodeJS.Timeout | null = null;
  #dirs = new Map<string, Dir>();
  #watching = new Map<string, AbortController>();
  #making = new Map<string, Promise<Thumb | null>>();
  #uploads = new Map<string, Promise<unknown>>();
  #writer: string | undefined;

  constructor(o: LibraryOptions) {
    this.#o = o;
    this.#writer = o.store.photoSetting("writer");
  }

  /// Starts the hourly passes, and a first one now when someone is known to act as.
  start() {
    this.#hourly = setInterval(() => this.pass(), HOURLY);
    this.#hourly.unref();
    if (this.#actor()) this.pass();
  }

  async close() {
    this.#closed = true;
    if (this.#hourly) clearInterval(this.#hourly);
    for (const c of this.#watching.values()) c.abort();
    this.#watching.clear();
    await this.settled();
  }

  /// Once nothing is being indexed or thumbnailed.
  async settled() {
    for (;;) {
      const chain = this.#chain;
      const filling = this.#filling;
      await chain.catch(() => {});
      await filling?.catch(() => {});
      if (chain === this.#chain && filling === this.#filling && this.#pending === 0) return;
    }
  }

  // Who the library is read as.

  /// The header the library is read as: the last owner's or admin's who set the folders, else the last member's who
  /// may write who asked for photos.
  #actor(): string | null {
    return this.#o.store.photoSetting("actor") ?? this.#writer ?? null;
  }

  /// A member who may write asked for photos: kept to read the library as until an owner or admin sets the folders.
  noteWriter(v: Viewer) {
    if (this.#writer === v.raw) return;
    const first = this.#actor() === null;
    this.#writer = v.raw;
    this.#o.store.setPhotoSetting("writer", v.raw);
    if (first) this.pass();
  }

  // Folders and albums.

  folders(): Folder[] {
    const kept = this.#o.store.photoSetting("folders");
    return kept ? (JSON.parse(kept) as Folder[]) : [];
  }

  view() {
    return { folders: this.folders(), backup: { root: this.#o.backup, path: "" } };
  }

  /// Sets the library's folders (each must be a folder the member reaches) and reads them as this member from now on.
  async setFolders(v: Viewer, given: unknown) {
    if (!Array.isArray(given)) throw bad("缺少文件夹列表（folders）");
    if (given.length > MOST_FOLDERS) throw bad(`文件夹最多 ${MOST_FOLDERS} 个`);
    const out: Folder[] = [];
    for (const f of given as unknown[]) {
      const g = f as Record<string, unknown> | null;
      if (!g || typeof g.root !== "string" || !g.root || g.root.length > 4096) throw bad("文件夹的根目录（root）无效");
      if (g.path !== undefined && (typeof g.path !== "string" || g.path.length > 4096)) throw bad("文件夹的路径（path）无效");
      const folder = { root: g.root, path: cleanPath((g.path as string | undefined) ?? "") };
      if (out.some((x) => x.root === folder.root && x.path === folder.path)) continue;
      if (folder.root === this.#o.backup && folder.path === "") continue;
      const entry = await driveStat(this.#o.link, v.raw, folder.root, folder.path);
      if (!entry.dir) throw bad(`${folder.path || folder.root} 不是文件夹`);
      out.push(folder);
    }
    this.#o.store.setPhotoSetting("folders", JSON.stringify(out));
    this.#o.store.setPhotoSetting("actor", v.raw);
    this.pass();
    return this.view();
  }

  #albums(): Album[] {
    const name = (f: Folder) => posix.basename(f.path) || posix.basename(f.root) || f.root;
    return [{ id: "backup", root: this.#o.backup, path: "", title: "手机备份" }, ...this.folders().map((f) => ({ ...f, id: photoId(f.root, f.path), title: name(f) }))];
  }

  albums() {
    const have = new Map(this.#o.store.photoAlbums().map((a) => [a.album, a]));
    return { albums: this.#albums().map((a) => ({ id: a.id, title: a.title, cover: have.get(a.id)?.cover ?? null, count: have.get(a.id)?.count ?? 0 })) };
  }

  // Indexing.

  /// `f` after what changes the index now (one at a time).
  #queue<T>(f: () => Promise<T>): Promise<T> {
    this.#pending++;
    const next = this.#chain.catch(() => {}).then(f);
    this.#chain = next.finally(() => this.#pending--);
    return next;
  }

  /// A whole pass, after the one running (two asked meanwhile are one).
  pass(): Promise<void> {
    if (this.#passQueued) return Promise.resolve();
    this.#passQueued = true;
    return this.#queue(async () => {
      this.#passQueued = false;
      await this.#pass();
    }).catch((e) => console.error("media: photo pass failed", e));
  }

  async #pass() {
    const actor = this.#actor();
    if (!actor || this.#closed) return;
    await mkdir(this.#o.backup, { recursive: true }).catch((e) => console.error("media: no backup folder", e));
    await this.#dropStaleUploads();
    const seen = Date.now();
    const albums = this.#albums();
    const dirs = new Map<string, Dir>();
    const budget = { dirs: MOST_DIRS };
    let changed = false;
    for (const album of albums) {
      if (this.#closed) return;
      const failed: string[] = [];
      changed = (await this.#walk(actor, album, albums, album.path, 0, seen, dirs, failed, budget)) || changed;
      if (this.#closed) return;
      // What was not found again (and not in a folder that could not be read) is gone.
      const gone = this.#o.store.photosOfAlbum(album.id).filter((p) => p.seen < seen && !failed.some((f) => under(f, p.dir)));
      this.#o.store.removePhotos(gone.map((p) => p.id));
      changed = changed || gone.length > 0;
    }
    // Albums no longer in the library.
    const ids = new Set(albums.map((a) => a.id));
    for (const a of this.#o.store.photoAlbums()) {
      if (ids.has(a.album)) continue;
      this.#o.store.removePhotos(this.#o.store.photosOfAlbum(a.album).map((p) => p.id));
      changed = true;
    }
    this.#dirs = dirs;
    this.#rewatch();
    if (changed) this.#o.changed();
    this.#fill();
  }

  /// Lists `dir` of the album and what is under it, indexing what is new or changed; answers whether anything was.
  async #walk(actor: string, album: Album, albums: Album[], dir: string, depth: number, seen: number, dirs: Map<string, Dir>, failed: string[], budget: { dirs: number }, mtime = Number.MAX_SAFE_INTEGER): Promise<boolean> {
    if (this.#closed || budget.dirs-- <= 0) {
      failed.push(dir);
      return false;
    }
    let listing: { entries: DriveEntry[]; truncated?: boolean };
    try {
      listing = await list(this.#o.link, actor, album.root, dir);
    } catch (e) {
      console.error(`media: cannot list ${album.root} ${dir}: ${(e as Error).message}`);
      failed.push(dir);
      return false;
    }
    dirs.set(dirKey(album.root, dir), { root: album.root, dir, album: album.id, mtime });
    let changed = false;
    for (const e of listing.entries) {
      if (this.#closed) return changed;
      const p = join2(dir, e.name);
      if (e.dir) {
        if (skipDir(e.name) || depth >= DEPTH || this.#another(album, albums, p)) continue;
        changed = (await this.#walk(actor, album, albums, p, depth + 1, seen, dirs, failed, budget, e.mtime)) || changed;
      } else if (!hidden(e.name) && kindOf(e.name)) {
        changed = (await this.#indexOne(actor, album.id, album.root, p, e, seen)) || changed;
      }
    }
    return changed;
  }

  /// Whether `path` of the album's root is another album's folder (walked as that one), or the backup folder.
  #another(album: Album, albums: Album[], path: string): boolean {
    if (albums.some((a) => a !== album && a.root === album.root && a.path === path)) return true;
    return album.root.startsWith("/") && posix.join(album.root, path) === this.#o.backup;
  }

  /// Indexes a file, logging (and keeping what it had) when it cannot be read.
  async #indexOne(actor: string, album: string, root: string, path: string, e: DriveEntry, seen: number): Promise<boolean> {
    try {
      return await this.#index(actor, album, root, path, e, seen);
    } catch (err) {
      console.error(`media: cannot index ${root} ${path}: ${(err as Error).message}`);
      const had = this.#o.store.photo(photoId(root, path));
      if (had) this.#o.store.seePhoto(had.id, seen, album);
      return false;
    }
  }

  /// Keeps the file's item, read again only when its size or time changed; answers whether it changed.
  async #index(actor: string, album: string, root: string, path: string, e: { size: number; mtime: number }, seen: number): Promise<boolean> {
    const id = photoId(root, path);
    const had = this.#o.store.photo(id);
    if (had && had.size === e.size && had.mtime === e.mtime) {
      if (had.seen !== seen || had.album !== album) this.#o.store.seePhoto(id, seen, album);
      return false;
    }
    const read = async (offset: number, length: number) => {
      const parts: Buffer[] = [];
      let got = 0;
      while (got < length) {
        const part = await readPart(this.#o.link, actor, root, path, offset + got, length - got);
        if (part.bytes.length === 0) break;
        parts.push(part.bytes);
        got += part.bytes.length;
      }
      return Buffer.concat(parts);
    };
    const meta = await metaOf({ size: e.size, head: await read(0, Math.min(HEAD, e.size)), read });
    this.#o.store.putPhoto(this.#row(id, album, root, path, e, meta, seen, had && had.size === e.size ? had.sha256 : null));
    return true;
  }

  #row(id: string, album: string, root: string, path: string, e: { size: number; mtime: number }, meta: Meta, seen: number, sha256: string | null): PhotoRow {
    const taken = meta.taken ?? e.mtime;
    return {
      id,
      root,
      path,
      dir: parentOf(path),
      album,
      kind: kindOf(path) as Kind,
      size: e.size,
      mtime: e.mtime,
      taken,
      day: localDay(taken),
      w: meta.w ?? null,
      h: meta.h ?? null,
      duration: meta.duration ?? null,
      camera: meta.camera ?? null,
      lens: meta.lens ?? null,
      lat: meta.gps?.lat ?? null,
      lon: meta.gps?.lon ?? null,
      thumbhash: null,
      sha256,
      seen,
    };
  }

  /// A folder the station said changed: its files again, its new folders walked, the ones gone dropped.
  #scan(d: Dir): Promise<void> {
    return this.#queue(async () => {
      const actor = this.#actor();
      const album = this.#albums().find((a) => a.id === d.album && a.root === d.root);
      if (!actor || !album || this.#closed) return;
      const store = this.#o.store;
      const seen = Date.now();
      let listing: { entries: DriveEntry[] };
      try {
        listing = await list(this.#o.link, actor, d.root, d.dir);
      } catch (e) {
        if (!(e instanceof MediaError && e.code === "not_found")) return;
        // The folder is gone: what was in it too.
        const gone = store.photosUnder(d.root, d.dir);
        store.removePhotos(gone.map((p) => p.id));
        for (const [k, x] of this.#dirs) if (x.root === d.root && under(d.dir, x.dir)) this.#dirs.delete(k);
        this.#rewatch();
        if (gone.length > 0) this.#o.changed();
        return;
      }
      let changed = false;
      const files = new Set<string>();
      const folders = new Map<string, DriveEntry>();
      const albums = this.#albums();
      for (const e of listing.entries) {
        const p = join2(d.dir, e.name);
        if (e.dir) {
          if (!skipDir(e.name) && !this.#another(album, albums, p)) folders.set(p, e);
        } else if (!hidden(e.name) && kindOf(e.name)) {
          files.add(p);
          changed = (await this.#indexOne(actor, album.id, d.root, p, e, seen)) || changed;
        }
      }
      // Another album's folder in this one is that album's to scan.
      const gone = store
        .photosUnder(d.root, d.dir)
        .filter((p) => p.album === album.id && ((p.dir === d.dir && !files.has(p.path)) || (p.dir !== d.dir && !folders.has(this.#childOf(d.dir, p.dir)))));
      store.removePhotos(gone.map((p) => p.id));
      changed = changed || gone.length > 0;
      for (const [k, x] of this.#dirs) {
        if (x.root === d.root && x.album === album.id && x.dir !== d.dir && under(d.dir, x.dir) && !folders.has(this.#childOf(d.dir, x.dir))) this.#dirs.delete(k);
      }
      const failed: string[] = [];
      const budget = { dirs: MOST_DIRS };
      const depth = d.dir.split("/").length - (album.path ? album.path.split("/").length : 0);
      for (const [p, e] of folders) {
        if (this.#dirs.has(dirKey(d.root, p))) continue;
        changed = (await this.#walk(actor, album, albums, p, depth + 1, seen, this.#dirs, failed, budget, e.mtime)) || changed;
      }
      this.#rewatch();
      if (changed) {
        this.#o.changed();
        this.#fill();
      }
    });
  }

  /// The folder right in `dir` that `p` (under it) is in.
  #childOf(dir: string, p: string): string {
    const rest = dir ? p.slice(dir.length + 1) : p;
    return join2(dir, rest.split("/")[0]!);
  }

  // Watching.

  /// Watches the albums' folders, then the folders changed lately, WATCHES at most; stops the others.
  #rewatch() {
    if (this.#closed) return;
    const tops = new Set(this.#albums().map((a) => dirKey(a.root, a.path)));
    const ranked = [...this.#dirs.entries()].sort((a, b) => Number(tops.has(b[0])) - Number(tops.has(a[0])) || b[1].mtime - a[1].mtime).slice(0, WATCHES);
    const want = new Map(ranked);
    for (const [k, c] of this.#watching) {
      if (!want.has(k)) {
        c.abort();
        this.#watching.delete(k);
      }
    }
    for (const [k, d] of want) {
      if (this.#watching.has(k)) continue;
      const c = new AbortController();
      this.#watching.set(k, c);
      void this.#follow(k, d, c.signal);
    }
  }

  async #follow(key: string, d: Dir, signal: AbortSignal) {
    while (!signal.aborted && !this.#closed) {
      const actor = this.#actor();
      if (!actor) return;
      try {
        if (await watch(this.#o.link, actor, d.root, d.dir, WATCH_ID, signal)) await this.#scan(this.#dirs.get(key) ?? d);
      } catch (e) {
        if (signal.aborted) return;
        // A folder the station does not watch (through still.fail Helper): the hourly pass reads it.
        if (e instanceof MediaError && (e.code === "forbidden" || e.code === "not_found")) {
          if (this.#watching.get(key)?.signal === signal) this.#watching.delete(key);
          return;
        }
        await new Promise((r) => setTimeout(r, 60_000).unref());
      }
    }
  }

  // Thumbnails.

  /// Makes the thumbnails (and so the ThumbHashes) not made yet, newest first, one at a time.
  #fill() {
    if (this.#filling || this.#closed) return;
    this.#filling = (async () => {
      let told = Date.now();
      let made = false;
      for (;;) {
        const actor = this.#actor();
        if (this.#closed || !actor) return;
        const batch = this.#o.store.unhashed(16);
        if (batch.length === 0) {
          if (made) this.#o.changed();
          return;
        }
        for (const item of batch) {
          if (this.#closed) return;
          try {
            await this.#thumb(item, actor);
          } catch (e) {
            // The station not there: later.
            if (e instanceof MediaError && e.code === "station") return;
            this.#o.store.setThumbhash(item.id, "", item.mtime, item.size);
          }
        }
        // The ThumbHashes told now and then while a lot are made, and once all are.
        made = true;
        if (Date.now() - told > FILL_TOLD) {
          told = Date.now();
          made = false;
          this.#o.changed();
        }
      }
    })().finally(() => (this.#filling = null));
  }

  #cacheOf(item: PhotoRow) {
    return { dir: join(this.#o.dir, "thumbs", item.id.slice(0, 2)), name: `${item.id}-${item.mtime}-${item.size}` };
  }

  /// The item's thumbnail: kept, or made (and kept, its ThumbHash with the item); null when none can be made.
  async thumb(id: string): Promise<Thumb | null> {
    const item = this.#o.store.photo(id);
    if (!item) throw new MediaError("not_found", "找不到这张照片");
    const actor = this.#actor();
    if (!actor) throw new MediaError("not_found", "找不到这张照片");
    return this.#thumb(item, actor);
  }

  async #thumb(item: PhotoRow, actor: string): Promise<Thumb | null> {
    const at = this.#cacheOf(item);
    const file = join(at.dir, at.name);
    const kept = await readFile(file).catch(() => null);
    if (kept && kept.length > 4) {
      const n = kept.readUInt32BE(0);
      const head = JSON.parse(kept.toString("utf8", 4, 4 + n)) as { type: string; w: number; h: number };
      return { bytes: kept.subarray(4 + n), ...head, hash: item.thumbhash || null };
    }
    const making = this.#making.get(file);
    if (making) return making;
    const work = this.#make(item, actor, at.dir, at.name).finally(() => this.#making.delete(file));
    this.#making.set(file, work);
    return work;
  }

  async #make(item: PhotoRow, actor: string, dir: string, name: string): Promise<Thumb | null> {
    const ext = extOf(item.path);
    let pic: Picture | null;
    if (item.kind === "video") {
      pic = await picture(this.#o.link, actor, "poster", item.root, item.path);
      if (pic && !pic.hash && this.#o.sips) pic = { ...pic, hash: await this.#sipsHash(pic.bytes) };
    } else if (BY_SIPS.has(ext)) {
      pic = await this.#bySips(item, actor, ext);
    } else {
      pic = await picture(this.#o.link, actor, "thumb", item.root, item.path);
    }
    if (!pic) {
      this.#o.store.setThumbhash(item.id, "", item.mtime, item.size);
      return null;
    }
    const s = sniff(pic.bytes, pic.type);
    const head = { type: s.type, w: pic.w ?? s.w ?? 0, h: pic.h ?? s.h ?? 0 };
    const json = Buffer.from(JSON.stringify(head));
    const len = Buffer.alloc(4);
    len.writeUInt32BE(json.length);
    await mkdir(dir, { recursive: true });
    const tmp = join(dir, `.${name}.${randomBytes(4).toString("hex")}`);
    await writeFile(tmp, Buffer.concat([len, json, pic.bytes]));
    await rename(tmp, join(dir, name));
    // The thumbnails of what the file was before.
    for (const other of await readdir(dir).catch(() => [] as string[])) {
      if (other.startsWith(`${item.id}-`) && other !== name) await rm(join(dir, other), { force: true });
    }
    this.#o.store.setThumbhash(item.id, pic.hash ?? "", item.mtime, item.size);
    return { bytes: pic.bytes, ...head, hash: pic.hash ?? null };
  }

  /// A HEIC/HEIF (or GIF) made a JPEG by sips, at most 720 across; a GIF as it is where there is no sips.
  async #bySips(item: PhotoRow, actor: string, ext: string): Promise<Picture | null> {
    if (item.size > MOST_SIPS) return null;
    if (!this.#o.sips) {
      if (ext !== "gif" || item.size > PART) return null;
      const whole = await readAll(this.#o.link, actor, item.root, item.path, PART);
      return { bytes: whole.bytes, type: "image/gif" };
    }
    const whole = await readAll(this.#o.link, actor, item.root, item.path, MOST_SIPS);
    return this.#scratch(async (base) => {
      await writeFile(`${base}.${ext}`, whole.bytes);
      try {
        await run(this.#o.sips!, ["-s", "format", "jpeg", "-Z", "720", `${base}.${ext}`, "--out", `${base}.jpg`]);
      } catch {
        return null;
      }
      const bytes = await readFile(`${base}.jpg`).catch(() => null);
      if (!bytes) return null;
      const hash = await this.#sipsHashOf(`${base}.jpg`, base);
      return { bytes, type: "image/jpeg", ...(hash ? { hash } : {}) };
    });
  }

  /// The ThumbHash of a JPEG's bytes, by a small BMP sips makes of it.
  async #sipsHash(jpeg: Buffer): Promise<string | undefined> {
    return this.#scratch(async (base) => {
      await writeFile(`${base}.jpg`, jpeg);
      return this.#sipsHashOf(`${base}.jpg`, base);
    });
  }

  async #sipsHashOf(file: string, base: string): Promise<string | undefined> {
    try {
      await run(this.#o.sips!, ["-s", "format", "bmp", "-Z", "100", file, "--out", `${base}.bmp`]);
      const bmp = readBmp(await readFile(`${base}.bmp`));
      return bmp && bmp.w <= 100 && bmp.h <= 100 ? thumbHash(bmp.w, bmp.h, bmp.rgba) : undefined;
    } catch {
      return undefined;
    }
  }

  /// `f` given a scratch path's base in the module's folder, whatever it made there removed after.
  async #scratch<T>(f: (base: string) => Promise<T>): Promise<T> {
    const dir = join(this.#o.dir, "tmp", randomBytes(6).toString("hex"));
    await mkdir(dir, { recursive: true });
    try {
      return await f(join(dir, "x"));
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  }

  // Reading the library.

  item(id: string) {
    const p = this.#o.store.photo(id);
    if (!p) throw new MediaError("not_found", "找不到这张照片");
    return {
      id: p.id,
      kind: p.kind,
      taken: p.taken,
      w: p.w ?? 0,
      h: p.h ?? 0,
      size: p.size,
      root: p.root,
      path: p.path,
      ...(p.duration !== null ? { duration: p.duration } : {}),
      ...(p.camera ? { camera: p.camera } : {}),
      ...(p.lens ? { lens: p.lens } : {}),
      ...(p.lat !== null && p.lon !== null ? { gps: { lat: p.lat, lon: p.lon } } : {}),
    };
  }

  /// The days around `around` (newest first): it, `before` days with items before it and `after` after it; without
  /// `around`, from the newest day back.
  timeline(q: URLSearchParams) {
    const count = (k: string, fallback: number) => {
      const v = q.get(k);
      if (v === null || v === "") return fallback;
      const n = Number(v);
      if (!Number.isInteger(n) || n < 0 || n > 366) throw bad(`${k} 无效（0 到 366）`);
      return n;
    };
    const given = q.get("around");
    if (given !== null && given !== "" && !/^\d{4}-\d{2}-\d{2}$/.test(given)) throw bad("around 无效（YYYY-MM-DD）");
    let before = count("before", 30);
    let after = count("after", 30);
    const store = this.#o.store;
    let around = given || null;
    if (!around) {
      around = store.newestDay();
      after = 0;
      if (!around) return { days: [], more: { before: false, after: false } };
    }
    const older = store.days(around, before + 1, true);
    const newer = store.days(around, after + 1, false);
    const days = [...newer.slice(0, after).reverse(), ...(store.hasDay(around) ? [around] : []), ...older.slice(0, before)];
    return {
      days: days.map((day) => ({
        day,
        items: store.photosOn(day).map((p) => ({ id: p.id, kind: p.kind, taken: p.taken, w: p.w ?? 0, h: p.h ?? 0, thumbhash: p.thumbhash || null, ...(p.duration !== null ? { duration: p.duration } : {}) })),
      })),
      more: { before: older.length > before, after: newer.length > after },
    };
  }

  has(hash: string | null) {
    if (!hash || !/^[0-9a-fA-F]{64}$/.test(hash)) throw bad("hash 无效（sha256 的 64 位十六进制）");
    return { id: this.#o.store.photoByHash(hash.toLowerCase()) ?? null };
  }

  // Uploads.

  /// A part of a phone's upload at `offset` (the parts so far kept in the module's folder by account, hash and size);
  /// once whole and its sha256 is the one given, into the member's backup folder, indexed.
  async upload(v: Viewer, q: URLSearchParams, body: () => Promise<Buffer>): Promise<{ status?: number; json: unknown }> {
    const name = q.get("name") ?? "";
    if (!name || Buffer.byteLength(name) > 255 || /[/\\\0]/.test(name) || hidden(name) || name.trim() !== name) throw bad("文件名（name）无效");
    if (!kindOf(name)) throw new MediaError("unsupported", "只备份照片（jpg、jpeg、png、heic、heif、webp、gif）和视频（mp4、mov、m4v）");
    const num = (k: string, optional: boolean) => {
      const s = q.get(k);
      if ((s === null || s === "") && optional) return undefined;
      const n = Number(s);
      if (s === null || s === "" || !Number.isSafeInteger(n) || n < 0) throw bad(`${k} 无效`);
      return n;
    };
    const size = num("size", false)!;
    const offset = num("offset", false)!;
    const taken = num("taken", true);
    const hash = (q.get("hash") ?? "").toLowerCase();
    if (!/^[0-9a-f]{64}$/.test(hash)) throw bad("hash 无效（sha256 的 64 位十六进制）");
    if (size === 0) throw bad("size 无效");

    const had = this.#o.store.photoByHash(hash);
    if (had) return { json: { have: size, id: had } };
    const bytes = await body();
    if (offset + bytes.length > size) throw bad("这一段超出了文件的大小（size）");

    const key = createHash("sha256").update(`${v.sub}\n${hash}\n${size}`).digest("hex").slice(0, 32);
    const dir = join(this.#o.dir, "uploads");
    const part = join(dir, `${key}.part`);
    const prior = this.#uploads.get(key) ?? Promise.resolve();
    const work = prior.catch(() => {}).then(async (): Promise<{ status?: number; json: unknown }> => {
      await mkdir(dir, { recursive: true });
      let have = (await stat(part).catch(() => null))?.size ?? 0;
      if (offset > have) return { status: 409, json: { error: "上传的位置不对，请从已收到的地方接着传", code: "conflict", have } };
      if (bytes.length > 0) {
        const f = await open(part, have === 0 && offset === 0 ? "w" : "r+");
        try {
          await f.write(bytes, 0, bytes.length, offset);
        } finally {
          await f.close();
        }
        have = Math.max(have, offset + bytes.length);
      }
      if (have < size) return { json: { have } };
      const got = await new Promise<string>((done, fail) => {
        const h = createHash("sha256");
        createReadStream(part)
          .on("data", (c) => h.update(c))
          .on("end", () => done(h.digest("hex")))
          .on("error", fail);
      });
      if (got !== hash) {
        await rm(part, { force: true });
        throw new MediaError("conflict", "收到的文件和它的 sha256 对不上，请重新上传");
      }
      const again = this.#o.store.photoByHash(hash);
      if (again) {
        await rm(part, { force: true });
        return { json: { have, id: again } };
      }
      const id = await this.#keepUpload(v, part, name, size, taken, hash);
      return { json: { have, id } };
    });
    const tail = work.finally(() => {
      if (this.#uploads.get(key) === tail) this.#uploads.delete(key);
    });
    this.#uploads.set(key, tail);
    return tail;
  }

  /// The whole upload moved into `<backup>/<email>/<YYYY>/<MM>/<name>` (a name taken given a number), its time the
  /// one it was taken at, and indexed now.
  async #keepUpload(v: Viewer, part: string, name: string, size: number, taken: number | undefined, sha256: string): Promise<string> {
    const email = v.email.toLowerCase();
    const who = email && !/[/\\\0]/.test(email) && !email.startsWith(".") && Buffer.byteLength(email) <= 255 ? email : v.sub;
    const when = new Date(taken ?? Date.now());
    const rel = [who, String(when.getFullYear()), String(when.getMonth() + 1).padStart(2, "0")].join("/");
    const folder = join(this.#o.backup, ...rel.split("/"));
    await mkdir(folder, { recursive: true });
    const dot = name.lastIndexOf(".");
    const [stem, ext] = dot > 0 ? [name.slice(0, dot), name.slice(dot)] : [name, ""];
    let file = name;
    for (let n = 1; await stat(join(folder, file)).then(() => true, () => false); n++) file = `${stem} (${n})${ext}`;
    const dest = join(folder, file);
    try {
      await rename(part, dest);
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== "EXDEV") throw e;
      await copyFile(part, dest);
      await unlink(part);
    }
    if (taken !== undefined) await utimes(dest, taken / 1000, taken / 1000).catch(() => {});
    const st = await stat(dest);
    const f = await open(dest, "r");
    try {
      const read = async (offset: number, length: number) => {
        const b = Buffer.alloc(Math.max(0, Math.min(length, st.size - offset)));
        const { bytesRead } = await f.read(b, 0, b.length, offset);
        return b.subarray(0, bytesRead);
      };
      const meta = await metaOf({ size: st.size, head: await read(0, HEAD), read });
      const path = `${rel}/${file}`;
      const id = photoId(this.#o.backup, path);
      this.#o.store.putPhoto(this.#row(id, "backup", this.#o.backup, path, { size, mtime: Math.round(st.mtimeMs) }, meta, Date.now(), sha256));
      this.#o.changed();
      this.#fill();
      return id;
    } finally {
      await f.close();
    }
  }

  async #dropStaleUploads() {
    const dir = join(this.#o.dir, "uploads");
    for (const name of await readdir(dir).catch(() => [] as string[])) {
      const st = await stat(join(dir, name)).catch(() => null);
      if (st && Date.now() - st.mtimeMs > STALE_UPLOAD) await rm(join(dir, name), { force: true });
    }
  }
}
