// The video library (docs/media-service.md 影视): the folders it is made of, each of films or of shows, indexed
// through the station's local API as the owner or admin who last set them (as the photo library is: a recursive walk,
// drive/watch on the folders it knows, a whole pass every hour). What each file is comes from its names and the .nfo
// beside it (videoname.ts); what is in it from ffprobe, run on the file itself when the service may read it (not a
// folder macOS protects, read through still.fail Helper: those are only named, and played directly). Posters: a
// picture beside it through the station's /thumb, else a frame at 10% made by ffmpeg, else the station's /poster;
// kept in the module's folder with their ThumbHash. Each account's place in what it watches.
import { execFile } from "node:child_process";
import { randomBytes, createHash } from "node:crypto";
import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { join, posix } from "node:path";
import { MediaError, bad } from "./errors.ts";
import { type Probe, type Tools, probe as runProbe, output, readable, runFfmpeg } from "./ffmpeg.ts";
import { sniff } from "./images.ts";
import { DEPTH, FILL_TOLD, HOURLY, MOST_DIRS, MOST_FOLDERS, WATCHES, cleanPath, dirKey, hidden, join2, photoId, skipDir, under } from "./photos.ts";
import type { Viewer } from "./server.ts";
import { type DriveEntry, type Picture, type StationLink, list, picture, readAll, stat as driveStat, watch } from "./station.ts";
import type { Progress, ShowRow, Store, VideoRow } from "./store.ts";
import { type ExternalSub, subtitlesOf, toVtt } from "./subtitles.ts";
import { readBmp, thumbHash } from "./thumbhash.ts";
import { decodeText } from "./txt.ts";
import { type Nfo, parseEpisodeName, parseMovieName, parseNfo, parseSeasonDir, parseShowDir, showKey, stemOf } from "./videoname.ts";

export type FolderKind = "movies" | "shows";
export type VideoFolder = { root: string; path: string; kind: FolderKind };
type LibFolder = VideoFolder & { id: string };
/// A folder the library knows (listed in the last pass), for its watch.
type Dir = { root: string; dir: string; folder: string; mtime: number };
/// A show as a walk found it: its folder (`visited`: listed in this walk, so its tvshow.nfo and poster are known).
type ShowSeen = { folder: string; root: string; dir: string; title: string; year?: number; nfo: DriveEntry | null; poster: DriveEntry | null; visited: boolean };
/// Where a folder is in a library folder of shows: in which show's folder (null: loose in the library folder), that
/// show's title by its folder's name, the season its folders name.
type ShowCtx = { showDir: string | null; title: string | null; year?: number; season: number | null };
export type Poster = { bytes: Buffer; type: string; w: number; h: number; hash: string | null };

export const VIDEO_EXTS = new Set(["mkv", "mp4", "m4v", "mov", "avi", "webm", "ts", "m2ts"]);
const extOf = (name: string) => name.slice(name.lastIndexOf(".") + 1).toLowerCase();
export const isVideo = (name: string) => name.lastIndexOf(".") > 0 && VIDEO_EXTS.has(extOf(name));
/// Folders of a film's extras, and samples, not in the library.
const EXTRAS = /^(?:extras?|featurettes?|behind[ ._-]the[ ._-]scenes|deleted[ ._-]scenes|interviews?|scenes|shorts|trailers?|samples?|bonus|other|花絮|特辑|特輯|预告|預告)$/i;
const SAMPLE = /(?:^|[.\s_-])sample$/i;
/// A file's name that says nothing of the film: its folder's name is taken.
const GENERIC = /^(?:movie|video|film|main|feature|title|disc\s*\d*|cd\s*\d+|part\s*\d+|\d{1,3}|vts_\d+_\d+|index)$/i;
/// A folder that is only a season (the library folder is then the show).
const SEASON_ONLY = /^(?:(?:season|series|staffel|saison)[\s._-]*\d{1,3}|s\d{1,3}|第\s*[0-9零〇一二两三四五六七八九十百]+\s*季|specials?|特别篇|特別篇)$/i;
const IMAGES = ["jpg", "jpeg", "png", "webp"];
const NFO_MOST = 1024 * 1024;
const SUB_MOST = 16 * 1024 * 1024;
const WATCH_ID = "media-videos";
/// The share of a film's length its poster's frame is taken at.
const FRAME_AT = 0.1;

/// A poster kept without its ThumbHash (none could be made here: no sips, and the package's ffmpeg reads no JPEG).
const NO_HASH = "-";
/// How a film's or a show's poster is told: its ThumbHash (null when it has none or none is known), whether there is one.
const art = (thumbhash: string | null) => ({ poster: thumbhash && thumbhash !== NO_HASH ? thumbhash : null, hasPoster: !!thumbhash });
const sigOf = (e: DriveEntry | null | undefined) => (e ? `${e.name}:${e.mtime}:${e.size}` : null);
/// The name of a picture kept as `name:mtime:size`.
const nameOfSig = (sig: string) => sig.split(":").slice(0, -2).join(":");
const json = <T>(s: string | null, fallback: T): T => {
  if (!s) return fallback;
  try {
    return JSON.parse(s) as T;
  } catch {
    return fallback;
  }
};

export type VideosOptions = {
  store: Store;
  link: StationLink;
  /// The module's folder: posters, subtitles made by ffmpeg, scratch.
  dir: string;
  tools: Tools;
  /// macOS's sips (a picture's ThumbHash, by a small BMP of it, as the photo library makes them), null where there is none.
  sips: string | null;
  /// The library changed (debounced by the caller).
  changed: () => void;
};

export class Videos {
  readonly #o: VideosOptions;
  readonly tools: Tools;
  #closed = false;
  #chain: Promise<unknown> = Promise.resolve();
  #pending = 0;
  #passQueued = false;
  #filling: Promise<void> | null = null;
  #hourly: NodeJS.Timeout | null = null;
  #dirs = new Map<string, Dir>();
  #watching = new Map<string, AbortController>();
  #making = new Map<string, Promise<Poster | null>>();
  #subs = new Map<string, Promise<string>>();

  constructor(o: VideosOptions) {
    this.#o = o;
    this.tools = o.tools;
  }

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

  /// Once nothing is being indexed, probed or given its poster.
  async settled() {
    for (;;) {
      const chain = this.#chain;
      const filling = this.#filling;
      await chain.catch(() => {});
      await filling?.catch(() => {});
      if (chain === this.#chain && filling === this.#filling && this.#pending === 0) return;
    }
  }

  /// The header the library is read as: the last owner's or admin's who set its folders.
  #actor(): string | null {
    return this.#o.store.photoSetting("videos.actor") ?? null;
  }

  // Folders.

  folders(): VideoFolder[] {
    return json<VideoFolder[]>(this.#o.store.photoSetting("videos.folders") ?? null, []);
  }

  view() {
    return { folders: this.folders() };
  }

  #libFolders(): LibFolder[] {
    return this.folders().map((f) => ({ ...f, id: photoId(f.root, f.path) }));
  }

  /// Sets the library's folders (each a folder the member reaches, of films or of shows) and reads them as this
  /// member from now on.
  async setFolders(v: Viewer, given: unknown) {
    if (!Array.isArray(given)) throw bad("缺少文件夹列表（folders）");
    if (given.length > MOST_FOLDERS) throw bad(`文件夹最多 ${MOST_FOLDERS} 个`);
    const out: VideoFolder[] = [];
    for (const f of given as unknown[]) {
      const g = f as Record<string, unknown> | null;
      if (!g || typeof g.root !== "string" || !g.root || g.root.length > 4096) throw bad("文件夹的根目录（root）无效");
      if (g.path !== undefined && (typeof g.path !== "string" || g.path.length > 4096)) throw bad("文件夹的路径（path）无效");
      if (g.kind !== "movies" && g.kind !== "shows") throw bad("文件夹的类型（kind）只能是 movies 或 shows");
      const folder: VideoFolder = { root: g.root, path: cleanPath((g.path as string | undefined) ?? ""), kind: g.kind };
      if (out.some((x) => x.root === folder.root && x.path === folder.path)) continue;
      const entry = await driveStat(this.#o.link, v.raw, folder.root, folder.path);
      if (!entry.dir) throw bad(`${folder.path || folder.root} 不是文件夹`);
      out.push(folder);
    }
    this.#o.store.setPhotoSetting("videos.folders", JSON.stringify(out));
    this.#o.store.setPhotoSetting("videos.actor", v.raw);
    this.pass();
    return this.view();
  }

  // Indexing.

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
    }).catch((e) => console.error("media: video pass failed", e));
  }

  async #pass() {
    const actor = this.#actor();
    if (!actor || this.#closed) return;
    const store = this.#o.store;
    // What could not be probed (no ffprobe then, or a file the service could not read) is tried again.
    if (this.tools.ffprobe) store.reprobe();
    const seen = Date.now();
    const folders = this.#libFolders();
    const dirs = new Map<string, Dir>();
    const budget = { dirs: MOST_DIRS };
    const shows = new Map<string, ShowSeen>();
    let changed = false;
    for (const f of folders) {
      if (this.#closed) return;
      const failed: string[] = [];
      changed = (await this.#walk(actor, f, folders, f.path, 0, seen, dirs, failed, budget, shows)) || changed;
      if (this.#closed) return;
      const gone = store.videosUnder(f.id).filter((p) => p.seen < seen && !failed.some((d) => under(d, p.dir)));
      store.removeVideos(gone.map((p) => p.id));
      changed = changed || gone.length > 0;
    }
    const ids = new Set(folders.map((f) => f.id));
    for (const folder of store.videoFolders()) {
      if (ids.has(folder)) continue;
      store.removeVideos(store.videosUnder(folder).map((p) => p.id));
      changed = true;
    }
    changed = (await this.#keepShows(actor, shows)) || changed;
    changed = store.dropEmptyShows() > 0 || changed;
    this.#dirs = dirs;
    this.#rewatch();
    if (changed) this.#o.changed();
    this.#fill();
  }

  async #walk(actor: string, f: LibFolder, folders: LibFolder[], dir: string, depth: number, seen: number, dirs: Map<string, Dir>, failed: string[], budget: { dirs: number }, shows: Map<string, ShowSeen>, mtime = Number.MAX_SAFE_INTEGER): Promise<boolean> {
    if (this.#closed || budget.dirs-- <= 0) {
      failed.push(dir);
      return false;
    }
    let listing: { entries: DriveEntry[] };
    try {
      listing = await list(this.#o.link, actor, f.root, dir);
    } catch (e) {
      console.error(`media: cannot list ${f.root} ${dir}: ${(e as Error).message}`);
      failed.push(dir);
      return false;
    }
    dirs.set(dirKey(f.root, dir), { root: f.root, dir, folder: f.id, mtime });
    let { changed } = await this.#files(actor, f, dir, listing.entries, seen, shows);
    for (const e of listing.entries) {
      if (this.#closed) return changed;
      if (!e.dir || this.#skip(f, folders, dir, e.name) || depth >= DEPTH) continue;
      changed = (await this.#walk(actor, f, folders, join2(dir, e.name), depth + 1, seen, dirs, failed, budget, shows, e.mtime)) || changed;
    }
    return changed;
  }

  /// Whether the folder `name` in `dir` is left out: hidden, a NAS's, extras, another library folder (walked as that one).
  #skip(f: LibFolder, folders: LibFolder[], dir: string, name: string): boolean {
    const p = join2(dir, name);
    return skipDir(name) || EXTRAS.test(name) || folders.some((o) => o !== f && o.root === f.root && o.path === p);
  }

  /// A show's folder, title and season by where `dir` is in a library folder of shows: `Show/Season 1/…` (a season's
  /// pack `Show.S01.1080p/…` too), or the library folder itself when its folders are seasons.
  #showCtx(f: LibFolder, dir: string): ShowCtx {
    const rel = dir === f.path ? "" : f.path ? dir.slice(f.path.length + 1) : dir;
    const parts = rel ? rel.split("/") : [];
    const own = () => parseShowDir(posix.basename(f.path) || posix.basename(f.root) || f.root);
    if (parts.length === 0) return { showDir: null, title: null, season: null };
    const itself = SEASON_ONLY.test(parts[0]!.trim());
    const showDir = itself ? f.path : join2(f.path, parts[0]!);
    const name = itself ? own() : parseShowDir(parts[0]!);
    // A season's pack's folder names its season too (Show.S02.1080p), the folders in it theirs.
    let season: number | null = null;
    for (const p of parts) season = parseSeasonDir(p) ?? season;
    return { showDir, title: name.title, ...(name.year ? { year: name.year } : {}), season };
  }

  #showId(f: LibFolder, title: string) {
    return createHash("sha256").update(`${f.id}\n${showKey(title) || title}`).digest("hex").slice(0, 20);
  }

  /// The videos right in `dir` indexed (what is new or changed read again); a show's folder's tvshow.nfo and poster
  /// noted. Answers whether anything changed, and the videos' paths.
  async #files(actor: string, f: LibFolder, dir: string, entries: DriveEntry[], seen: number, shows: Map<string, ShowSeen>): Promise<{ changed: boolean; paths: Set<string> }> {
    const files = entries.filter((e) => !e.dir && !hidden(e.name));
    const lower = new Map(files.map((e) => [e.name.toLowerCase(), e]));
    const videos = files.filter((e) => isVideo(e.name) && !SAMPLE.test(stemOf(e.name)));
    const ctx = f.kind === "shows" ? this.#showCtx(f, dir) : null;
    if (f.kind === "shows") {
      const isShowDir = ctx!.showDir === dir;
      // The library folder itself is a show when it has a tvshow.nfo.
      const rootShow = dir === f.path && lower.has("tvshow.nfo");
      if (isShowDir || rootShow) {
        const name = isShowDir ? { title: ctx!.title!, year: ctx!.year } : parseShowDir(posix.basename(f.path) || posix.basename(f.root) || f.root);
        const id = this.#showId(f, name.title);
        shows.set(id, { folder: f.id, root: f.root, dir, title: name.title, ...(name.year ? { year: name.year } : {}), nfo: lower.get("tvshow.nfo") ?? null, poster: pictureOf(lower, ["poster", "folder", "cover", "show", "fanart"]), visited: true });
      }
    }
    let changed = false;
    const paths = new Set<string>();
    for (const e of videos) {
      if (this.#closed) break;
      const path = join2(dir, e.name);
      paths.add(path);
      try {
        changed = (await this.#index(actor, f, dir, e, files, lower, videos.length, ctx, seen, shows)) || changed;
      } catch (err) {
        console.error(`media: cannot index ${f.root} ${path}: ${(err as Error).message}`);
        const had = this.#o.store.video(photoId(f.root, path));
        if (had) this.#o.store.seeVideo(had.id, seen);
      }
    }
    return { changed, paths };
  }

  /// Keeps a video's row: read again (its .nfo) when it, or what beside it it is known by, changed; probed and given
  /// its poster later (#fill). Answers whether it changed.
  async #index(actor: string, f: LibFolder, dir: string, e: DriveEntry, files: DriveEntry[], lower: Map<string, DriveEntry>, count: number, ctx: ShowCtx | null, seen: number, shows: Map<string, ShowSeen>): Promise<boolean> {
    const store = this.#o.store;
    const path = join2(dir, e.name);
    const id = photoId(f.root, path);
    const stem = stemOf(e.name);
    const nfoEntry = lower.get(`${stem.toLowerCase()}.nfo`) ?? (f.kind === "movies" && count === 1 ? lower.get("movie.nfo") : undefined);
    const subs = subtitlesOf(e.name, files.map((x) => x.name));
    const poster = f.kind === "movies" ? pictureOf(lower, [`${stem}-poster`, `${stem}.poster`, ...(count === 1 ? ["poster", "folder", "cover", "movie", "fanart", `${stem}-fanart`] : [])]) : null;

    // An episode's show: its folder's, else the one its name says, else the library folder's.
    const ep = f.kind === "shows" ? parseEpisodeName(e.name) : null;
    let show: { id: string; title: string; year?: number } | null = null;
    if (f.kind === "shows") {
      const own = parseShowDir(posix.basename(f.path) || posix.basename(f.root) || f.root);
      const name = ctx!.showDir !== null ? { title: ctx!.title!, year: ctx!.year } : ep?.show ? { title: ep.show, year: ep.year } : own;
      show = { id: this.#showId(f, name.title), title: name.title, ...(name.year ? { year: name.year } : {}) };
      if (!shows.has(show.id)) shows.set(show.id, { folder: f.id, root: f.root, dir: ctx!.showDir ?? "", title: show.title, ...(show.year ? { year: show.year } : {}), nfo: null, poster: null, visited: false });
    }

    const sides = JSON.stringify({ nfo: sigOf(nfoEntry), subs: subs.map((s) => s.name), poster: sigOf(poster), show: show?.id ?? null, season: ctx?.season ?? null });
    const had = store.video(id);
    if (had && had.size === e.size && had.mtime === e.mtime && had.sides === sides && had.folder === f.id) {
      if (had.seen !== seen) store.seeVideo(id, seen);
      return false;
    }
    const nfo = nfoEntry ? await this.#readNfo(actor, f.root, join2(dir, nfoEntry.name)) : null;
    const same = had !== undefined && had.size === e.size && had.mtime === e.mtime;
    const row: VideoRow = {
      id,
      folder: f.id,
      root: f.root,
      path,
      dir,
      kind: f.kind === "movies" ? "movie" : "episode",
      size: e.size,
      mtime: e.mtime,
      sides,
      title: "",
      original_title: null,
      year: null,
      plot: nfo?.plot ?? null,
      genres: JSON.stringify(nfo?.genres ?? []),
      runtime: nfo?.runtime ?? null,
      show: null,
      season: null,
      episode: null,
      episode_end: null,
      subs: JSON.stringify(subs),
      probe: same ? had.probe : null,
      probe_state: same ? had.probe_state : "pending",
      poster: sigOf(poster),
      thumbhash: null,
      added: had?.added ?? Date.now(),
      seen,
    };
    if (f.kind === "movies") {
      const fromFile = parseMovieName(stem);
      const parent = dir !== f.path ? posix.basename(dir) : null;
      let name = fromFile;
      if (parent && (GENERIC.test(stem.trim()) || !fromFile.year)) {
        const fromDir = parseMovieName(parent);
        if (fromDir.title && (GENERIC.test(stem.trim()) || fromDir.year)) name = fromDir;
      }
      row.title = nfo?.title ?? name.title;
      row.original_title = nfo?.originalTitle ?? name.originalTitle ?? null;
      row.year = nfo?.year ?? name.year ?? null;
      row.thumbhash = same && had.poster === row.poster ? had.thumbhash : null;
    } else {
      row.show = show!.id;
      row.season = nfo?.season ?? ep?.season ?? ctx?.season ?? 1;
      row.episode = nfo?.episode ?? ep?.episode ?? null;
      row.episode_end = ep?.episodeEnd ?? null;
      row.title = nfo?.title ?? ep?.title ?? "";
      row.year = nfo?.year ?? null;
      // Episodes are shown by their show's poster.
      row.thumbhash = "";
    }
    store.putVideo(row);
    return true;
  }

  async #readNfo(actor: string, root: string, path: string): Promise<Nfo | null> {
    try {
      const { bytes } = await readAll(this.#o.link, actor, root, path, NFO_MOST);
      return parseNfo(decodeText(bytes));
    } catch (e) {
      console.error(`media: cannot read ${root} ${path}: ${(e as Error).message}`);
      return null;
    }
  }

  /// The shows a walk found kept: new ones made, the ones whose folder was listed given what their tvshow.nfo and
  /// poster now are. Answers whether any changed.
  async #keepShows(actor: string, shows: Map<string, ShowSeen>): Promise<boolean> {
    const store = this.#o.store;
    let changed = false;
    for (const [id, s] of shows) {
      const had = store.show(id);
      if (had && !s.visited) continue;
      const nfoSig = s.visited ? (sigOf(s.nfo) ?? "") : "";
      const posterSig = s.visited ? sigOf(s.poster) : null;
      if (had && had.nfo === nfoSig && had.poster === posterSig && had.dir === s.dir && had.folder === s.folder) continue;
      let meta: Pick<ShowRow, "title" | "original_title" | "year" | "plot" | "genres">;
      if (had && had.nfo === nfoSig) meta = { title: had.title, original_title: had.original_title, year: had.year, plot: had.plot, genres: had.genres };
      else {
        const nfo = s.nfo ? await this.#readNfo(actor, s.root, join2(s.dir, s.nfo.name)) : null;
        meta = { title: nfo?.title ?? s.title, original_title: nfo?.originalTitle ?? null, year: nfo?.year ?? s.year ?? null, plot: nfo?.plot ?? null, genres: JSON.stringify(nfo?.genres ?? []) };
      }
      store.putShow({ id, folder: s.folder, root: s.root, dir: s.dir, ...meta, nfo: nfoSig, poster: posterSig, thumbhash: had && had.poster === posterSig ? had.thumbhash : null, added: had?.added ?? Date.now() });
      changed = true;
    }
    return changed;
  }

  /// A folder the station said changed: its videos again, its new folders walked, what is gone dropped.
  #scan(d: Dir): Promise<void> {
    return this.#queue(async () => {
      const actor = this.#actor();
      const folders = this.#libFolders();
      const f = folders.find((x) => x.id === d.folder && x.root === d.root);
      if (!actor || !f || this.#closed) return;
      const store = this.#o.store;
      const seen = Date.now();
      const all = d.dir === f.path && f.path === "" ? undefined : d.dir;
      let listing: { entries: DriveEntry[] };
      try {
        listing = await list(this.#o.link, actor, d.root, d.dir);
      } catch (e) {
        if (!(e instanceof MediaError && e.code === "not_found")) return;
        const gone = store.videosUnder(f.id, all);
        store.removeVideos(gone.map((p) => p.id));
        for (const [k, x] of this.#dirs) if (x.root === d.root && under(d.dir, x.dir)) this.#dirs.delete(k);
        this.#rewatch();
        if (gone.length > 0 || store.dropEmptyShows() > 0) this.#o.changed();
        return;
      }
      const shows = new Map<string, ShowSeen>();
      let { changed, paths } = await this.#files(actor, f, d.dir, listing.entries, seen, shows);
      const subdirs = new Map<string, DriveEntry>();
      for (const e of listing.entries) if (e.dir && !this.#skip(f, folders, d.dir, e.name)) subdirs.set(join2(d.dir, e.name), e);
      const childOf = (p: string) => join2(d.dir, (d.dir ? p.slice(d.dir.length + 1) : p).split("/")[0]!);
      const gone = store.videosUnder(f.id, all).filter((p) => (p.dir === d.dir ? !paths.has(p.path) : !subdirs.has(childOf(p.dir))));
      store.removeVideos(gone.map((p) => p.id));
      changed = changed || gone.length > 0;
      for (const [k, x] of this.#dirs) {
        if (x.root === d.root && x.folder === f.id && x.dir !== d.dir && under(d.dir, x.dir) && !subdirs.has(childOf(x.dir))) this.#dirs.delete(k);
      }
      const failed: string[] = [];
      const budget = { dirs: MOST_DIRS };
      const depth = d.dir === f.path ? 0 : d.dir.split("/").length - (f.path ? f.path.split("/").length : 0);
      for (const [p, e] of subdirs) {
        if (this.#dirs.has(dirKey(d.root, p))) continue;
        changed = (await this.#walk(actor, f, folders, p, depth + 1, seen, this.#dirs, failed, budget, shows, e.mtime)) || changed;
      }
      changed = (await this.#keepShows(actor, shows)) || changed;
      changed = store.dropEmptyShows() > 0 || changed;
      this.#rewatch();
      if (changed) {
        this.#o.changed();
        this.#fill();
      }
    });
  }

  // Watching (as the photo library's).

  #rewatch() {
    if (this.#closed) return;
    const tops = new Set(this.#libFolders().map((f) => dirKey(f.root, f.path)));
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
        if (e instanceof MediaError && (e.code === "forbidden" || e.code === "not_found")) {
          if (this.#watching.get(key)?.signal === signal) this.#watching.delete(key);
          return;
        }
        await new Promise((r) => setTimeout(r, 60_000).unref());
      }
    }
  }

  // Probing and posters, in the background.

  /// The file's path for ffmpeg, when the service may read it itself.
  async fileOf(item: { root: string; path: string }): Promise<string | null> {
    if (!item.root.startsWith("/")) return null;
    const file = posix.join(item.root, item.path);
    return (await readable(file)) ? file : null;
  }

  #fill() {
    if (this.#filling || this.#closed) return;
    this.#filling = (async () => {
      const store = this.#o.store;
      let told = Date.now();
      let made = false;
      const tell = () => {
        made = true;
        if (Date.now() - told > FILL_TOLD) {
          told = Date.now();
          made = false;
          this.#o.changed();
        }
      };
      for (;;) {
        if (this.#closed) return;
        const batch = store.unprobed(8);
        if (batch.length === 0) break;
        for (const item of batch) {
          if (this.#closed) return;
          await this.#probe(item);
        }
        tell();
      }
      for (;;) {
        const actor = this.#actor();
        if (this.#closed || !actor) return;
        const items = store.unposted(8);
        const shows = store.unpostedShows(8);
        if (items.length === 0 && shows.length === 0) break;
        for (const item of items) {
          if (this.#closed) return;
          if (item.kind !== "movie") {
            store.setVideoThumbhash(item.id, "", item.mtime, item.size);
            continue;
          }
          try {
            await this.#posterOf(`m${item.id}`, () => this.#makeMoviePoster(item, actor));
          } catch (e) {
            if (e instanceof MediaError && e.code === "station") return;
            store.setVideoThumbhash(item.id, "", item.mtime, item.size);
          }
        }
        for (const show of shows) {
          if (this.#closed) return;
          try {
            await this.#posterOf(`s${show.id}`, () => this.#makeShowPoster(show, actor));
          } catch (e) {
            if (e instanceof MediaError && e.code === "station") return;
            store.setShowThumbhash(show.id, "", show.poster);
          }
        }
        tell();
      }
      if (made) this.#o.changed();
    })().finally(() => (this.#filling = null));
  }

  async #probe(item: VideoRow) {
    const store = this.#o.store;
    if (!this.tools.ffprobe) return store.setProbe(item.id, null, "no-ffprobe", item.mtime, item.size);
    const file = await this.fileOf(item);
    if (!file) return store.setProbe(item.id, null, "unreadable", item.mtime, item.size);
    try {
      const p = await runProbe(this.tools.ffprobe, file);
      store.setProbe(item.id, JSON.stringify(p), "done", item.mtime, item.size);
    } catch (e) {
      console.error(`media: cannot probe ${file}: ${(e as Error).message}`);
      store.setProbe(item.id, null, "failed", item.mtime, item.size);
    }
  }

  /// One making of a poster at a time for each film or show.
  #posterOf(key: string, make: () => Promise<Poster | null>): Promise<Poster | null> {
    const making = this.#making.get(key);
    if (making) return making;
    const work = make().finally(() => this.#making.delete(key));
    this.#making.set(key, work);
    return work;
  }

  #posterFile(id: string) {
    return join(this.#o.dir, "videos", "posters", id.slice(0, 2), id);
  }

  async #makeMoviePoster(item: VideoRow, actor: string): Promise<Poster | null> {
    const pic = await this.#picture(actor, item.root, item.poster ? join2(item.dir, nameOfSig(item.poster)) : null, item);
    const kept = pic ? await this.#keep(item.id, pic) : null;
    this.#o.store.setVideoThumbhash(item.id, kept ? kept.hash || NO_HASH : "", item.mtime, item.size);
    return kept;
  }

  async #makeShowPoster(show: ShowRow, actor: string): Promise<Poster | null> {
    const first = this.#o.store.episodes(show.id)[0] ?? null;
    const pic = await this.#picture(actor, show.root, show.poster ? join2(show.dir, nameOfSig(show.poster)) : null, first);
    const kept = pic ? await this.#keep(show.id, pic) : null;
    this.#o.store.setShowThumbhash(show.id, kept ? kept.hash || NO_HASH : "", show.poster);
    return kept;
  }

  /// A poster: the picture beside it (the station's /thumb), else a frame of the video at 10% (ffmpeg, when the
  /// service may read it), else the station's /poster of it; null when there is none.
  async #picture(actor: string, root: string, beside: string | null, video: VideoRow | null): Promise<Picture | null> {
    if (beside) {
      try {
        const pic = await picture(this.#o.link, actor, "thumb", root, beside);
        if (pic) return pic.hash ? pic : { ...pic, ...(await this.#hashOf(pic.bytes)) };
      } catch (e) {
        if (e instanceof MediaError && e.code === "station") throw e;
      }
    }
    if (!video) return null;
    const p = video.probe_state === "done" ? json<Probe | null>(video.probe, null) : null;
    const file = this.tools.ffmpeg && p?.video ? await this.fileOf(video) : null;
    if (file) {
      const jpeg = await this.#frame(file, p!.duration);
      if (jpeg) return { bytes: jpeg, type: "image/jpeg", ...(await this.#hashOf(jpeg)) };
    }
    const pic = await picture(this.#o.link, actor, "poster", video.root, video.path);
    return pic ? (pic.hash ? pic : { ...pic, ...(await this.#hashOf(pic.bytes)) }) : null;
  }

  /// A JPEG of the video's frame at 10% of it (at most 720 across and down).
  async #frame(file: string, duration: number | null): Promise<Buffer | null> {
    return this.#scratch(async (base) => {
      for (const at of [duration ? duration * FRAME_AT : 10, 0]) {
        try {
          await runFfmpeg(this.tools.ffmpeg!, ["-ss", at.toFixed(3), "-i", file, "-frames:v", "1", "-an", "-sn", "-dn", "-vf", "scale=w='min(720,iw)':h='min(720,ih)':force_original_aspect_ratio=decrease,format=yuvj420p", "-q:v", "3", "-f", "image2", "-c:v", "mjpeg", `${base}.jpg`], 60_000);
          const bytes = await readFile(`${base}.jpg`).catch(() => null);
          if (bytes && bytes.length > 0) return bytes;
        } catch (e) {
          console.error(`media: no frame of ${file} at ${at}: ${(e as Error).message}`);
        }
      }
      return null;
    });
  }

  /// The ThumbHash of a JPEG (or PNG), from a picture of it at most 100×100: a BMP by sips (macOS), else raw RGBA by
  /// ffmpeg when it can (a developer's; the package's has no image demuxer nor rawvideo muxer). Without either, none.
  async #hashOf(bytes: Buffer): Promise<{ hash?: string; w?: number; h?: number }> {
    const s = sniff(bytes, "image/jpeg");
    if (!s.w || !s.h) return {};
    const size = { w: s.w, h: s.h };
    const ext = s.type === "image/png" ? "png" : "jpg";
    return this.#scratch(async (base) => {
      await writeFile(`${base}.${ext}`, bytes);
      if (this.#o.sips) {
        try {
          await new Promise<void>((done, fail) => execFile(this.#o.sips!, ["-s", "format", "bmp", "-Z", "100", `${base}.${ext}`, "--out", `${base}.bmp`], { timeout: 60_000 }, (e) => (e ? fail(e) : done())));
          const bmp = readBmp(await readFile(`${base}.bmp`));
          if (bmp && bmp.w <= 100 && bmp.h <= 100) return { hash: thumbHash(bmp.w, bmp.h, bmp.rgba), ...size };
        } catch {}
      }
      if (!this.tools.ffmpeg) return size;
      const scale = Math.min(1, 100 / Math.max(s.w!, s.h!));
      const w = Math.max(1, Math.round(s.w! * scale));
      const h = Math.max(1, Math.round(s.h! * scale));
      try {
        const rgba = await output(this.tools.ffmpeg, ["-hide_banner", "-loglevel", "error", "-i", `${base}.${ext}`, "-vf", `scale=${w}:${h}`, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgba", "-"], 30_000);
        return rgba.length === w * h * 4 ? { hash: thumbHash(w, h, rgba), ...size } : size;
      } catch {
        return size;
      }
    });
  }

  async #keep(id: string, pic: Picture): Promise<Poster> {
    const s = sniff(pic.bytes, pic.type);
    const head = { type: s.type, w: pic.w ?? s.w ?? 0, h: pic.h ?? s.h ?? 0 };
    const meta = Buffer.from(JSON.stringify(head));
    const len = Buffer.alloc(4);
    len.writeUInt32BE(meta.length);
    const file = this.#posterFile(id);
    await mkdir(posix.dirname(file), { recursive: true });
    const tmp = `${file}.${randomBytes(4).toString("hex")}`;
    await writeFile(tmp, Buffer.concat([len, meta, pic.bytes]));
    await rename(tmp, file);
    return { bytes: pic.bytes, ...head, hash: pic.hash ?? null };
  }

  /// A film's or a show's poster: kept, or made now; null when it has none.
  async poster(id: string): Promise<Poster | null> {
    const store = this.#o.store;
    const movie = store.video(id);
    const show = movie ? undefined : store.show(id);
    if ((!movie || movie.kind !== "movie") && !show) throw new MediaError("not_found", "找不到这部片子");
    const hash = movie ? movie.thumbhash : show!.thumbhash;
    if (hash === "") return null;
    if (hash !== null) {
      const kept = await readFile(this.#posterFile(id)).catch(() => null);
      if (kept && kept.length > 4) {
        const n = kept.readUInt32BE(0);
        const head = JSON.parse(kept.toString("utf8", 4, 4 + n)) as { type: string; w: number; h: number };
        return { bytes: kept.subarray(4 + n), ...head, hash: hash === NO_HASH ? null : hash };
      }
    }
    const actor = this.#actor();
    if (!actor) return null;
    return movie ? this.#posterOf(`m${id}`, () => this.#makeMoviePoster(movie, actor)) : this.#posterOf(`s${id}`, () => this.#makeShowPoster(show!, actor));
  }

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

  /// A film or an episode (what can be played), or 404.
  item(id: string): VideoRow {
    const v = this.#o.store.video(id);
    if (!v) throw new MediaError("not_found", "找不到这个视频");
    return v;
  }

  probeOf(v: VideoRow): Probe | null {
    return v.probe_state === "done" ? json<Probe | null>(v.probe, null) : null;
  }

  externalSubs(v: VideoRow): ExternalSub[] {
    return json<ExternalSub[]>(v.subs, []);
  }

  durationOf(v: VideoRow): number | null {
    return this.probeOf(v)?.duration ?? v.runtime ?? null;
  }

  /// The subtitles a video has: the ones beside it (`x<n>`), then its own text tracks (`s<stream>`, made WebVTT by
  /// ffmpeg, so only when there is one).
  subtitles(v: VideoRow) {
    const p = this.probeOf(v);
    const external = this.externalSubs(v).map((s, k) => ({ id: `x${k}`, lang: s.lang, title: s.title, format: s.format, external: true, forced: s.forced, default: false, text: true }));
    const own = (p?.subtitles ?? []).map((s) => ({ id: `s${s.index}`, lang: s.lang, title: s.title, format: s.codec, external: false, forced: s.forced, default: s.default, text: s.text }));
    return [...external, ...own];
  }

  #progressView(p: Progress | null | undefined) {
    return p ? { position: p.position, duration: p.duration, done: p.done, at: p.at } : null;
  }

  library(v: Viewer) {
    const store = this.#o.store;
    const progress = store.progresses(v.sub);
    const movies = store.movies();
    const shows = store.shows();
    const byShow = new Map<string, VideoRow[]>();
    for (const e of store.episodes()) {
      const list = byShow.get(e.show!) ?? [];
      list.push(e);
      byShow.set(e.show!, list);
    }
    const showOf = new Map(shows.map((s) => [s.id, s]));
    const recent: unknown[] = [];
    const watching = [...progress.entries()].filter(([, p]) => !p.done && p.position > 0).sort((a, b) => b[1].at - a[1].at);
    for (const [id, p] of watching) {
      if (recent.length >= 20) break;
      const item = store.video(id);
      if (!item) continue;
      const duration = p.duration ?? this.durationOf(item);
      if (item.kind === "movie") recent.push({ id, kind: "movie", title: item.title, year: item.year, ...art(item.thumbhash), position: p.position, duration, at: p.at });
      else {
        const s = showOf.get(item.show!);
        if (!s) continue;
        recent.push({ id, kind: "episode", show: s.id, showTitle: s.title, season: item.season, episode: item.episode, title: item.title || null, ...art(s.thumbhash), position: p.position, duration, at: p.at });
      }
    }
    return {
      movies: movies.map((m) => {
        const p = progress.get(m.id);
        return { id: m.id, title: m.title, year: m.year, ...art(m.thumbhash), added: m.added, ...(p ? { progress: this.#progressView(p) } : {}) };
      }),
      shows: shows.map((s) => {
        const eps = byShow.get(s.id) ?? [];
        return { id: s.id, title: s.title, year: s.year, ...art(s.thumbhash), seasons: new Set(eps.map((e) => e.season)).size, episodes: eps.length, unwatched: eps.filter((e) => !progress.get(e.id)?.done).length, added: s.added };
      }),
      recent,
      ffmpeg: this.tools.ffmpeg !== null,
      ffprobe: this.tools.ffprobe !== null,
    };
  }

  /// What the title page says of a film or an episode.
  #itemView(v: VideoRow, sub: string) {
    const p = this.probeOf(v);
    const out: Record<string, unknown> = {
      id: v.id,
      kind: v.kind,
      title: v.title || null,
      originalTitle: v.original_title,
      year: v.year,
      plot: v.plot,
      genres: json<string[]>(v.genres, []),
      duration: this.durationOf(v),
      file: { root: v.root, path: v.path },
      size: v.size,
      ...(v.kind === "movie" ? art(v.thumbhash) : {}),
      probe: v.probe_state,
      tracks: {
        container: p?.container ?? null,
        video: p?.video ? { codec: p.video.codec, profile: p.video.profile, width: p.video.width, height: p.video.height, hdr: p.video.hdr, fps: p.video.fps, bitDepth: p.video.bitDepth } : null,
        audio: (p?.audio ?? []).map((a) => ({ index: a.index, codec: a.codec, lang: a.lang, title: a.title, channels: a.channels, default: a.default })),
        subtitles: this.subtitles(v),
      },
      progress: this.#progressView(this.#o.store.progress(v.id, sub)),
    };
    if (v.kind === "episode") {
      const s = this.#o.store.show(v.show!);
      Object.assign(out, { show: v.show, showTitle: s?.title ?? null, season: v.season, episode: v.episode, ...(v.episode_end !== null ? { episodeEnd: v.episode_end } : {}) });
    }
    return out;
  }

  title(viewer: Viewer, id: string) {
    const store = this.#o.store;
    const movie = store.video(id);
    if (movie?.kind === "movie") return this.#itemView(movie, viewer.sub);
    const show = store.show(id);
    if (!show) throw new MediaError("not_found", "找不到这部片子");
    const progress = store.progresses(viewer.sub);
    const seasons = new Map<number, unknown[]>();
    for (const e of store.episodes(id)) {
      const list = seasons.get(e.season ?? 1) ?? [];
      list.push({ id: e.id, episode: e.episode, ...(e.episode_end !== null ? { episodeEnd: e.episode_end } : {}), title: e.title || null, duration: this.durationOf(e), progress: this.#progressView(progress.get(e.id)) });
      seasons.set(e.season ?? 1, list);
    }
    return {
      id: show.id,
      kind: "show",
      title: show.title,
      originalTitle: show.original_title,
      year: show.year,
      plot: show.plot,
      genres: json<string[]>(show.genres, []),
      ...art(show.thumbhash),
      seasons: [...seasons.entries()].sort((a, b) => a[0] - b[0]).map(([season, episodes]) => ({ season, episodes })),
    };
  }

  episode(viewer: Viewer, id: string) {
    const v = this.#o.store.video(id);
    if (!v || v.kind !== "episode") throw new MediaError("not_found", "找不到这一集");
    return this.#itemView(v, viewer.sub);
  }

  // Progress.

  progress(viewer: Viewer, id: string) {
    const v = this.item(id);
    return { progress: this.#progressView(this.#o.store.progress(v.id, viewer.sub)) };
  }

  /// Keeps the account's place (`at` newer than the one kept); seen at 90% of its length, or when it says so.
  setProgress(viewer: Viewer, id: string, body: Record<string, unknown>): { json: unknown; changed: boolean } {
    const v = this.item(id);
    const num = (x: unknown, what: string) => {
      if (typeof x !== "number" || !Number.isFinite(x) || x < 0) throw bad(`${what}无效`);
      return x;
    };
    const position = num(body.position, "位置（position）");
    const at = Math.round(num(body.at, "时间（at）"));
    if (body.done !== undefined && typeof body.done !== "boolean") throw bad("done 只能是 true 或 false");
    const given = body.duration === undefined || body.duration === null ? null : num(body.duration, "时长（duration）");
    const duration = this.durationOf(v) ?? given;
    const done = typeof body.done === "boolean" ? body.done : duration !== null && duration > 0 && position >= duration * 0.9;
    const kept = this.#o.store.setProgress(v.id, viewer.sub, { position, duration, done, at });
    return { json: { progress: this.#progressView(kept.progress) }, changed: kept.changed };
  }

  // Subtitles.

  /// A subtitle of the video as WebVTT: one beside it read through the station and turned here, or one of its own
  /// text tracks made by ffmpeg (kept in the module's folder until the file changes).
  async subtitle(id: string, sub: string): Promise<string> {
    const v = this.item(id);
    const x = /^x(\d+)$/.exec(sub);
    if (x) {
      const s = this.externalSubs(v)[Number(x[1])];
      const actor = this.#actor();
      if (!s || !actor) throw new MediaError("not_found", "没有这个字幕");
      const { bytes } = await readAll(this.#o.link, actor, v.root, join2(v.dir, s.name), SUB_MOST);
      return toVtt(bytes, s.format);
    }
    const m = /^s(\d+)$/.exec(sub);
    const track = m ? this.probeOf(v)?.subtitles.find((t) => t.index === Number(m[1])) : undefined;
    if (!track) throw new MediaError("not_found", "没有这个字幕");
    if (!track.text) throw new MediaError("unsupported", "图形字幕（PGS、DVD）还不支持");
    if (!this.tools.ffmpeg) throw new MediaError("unsupported", "没有 ffmpeg，读不了片子里的字幕");
    const file = await this.fileOf(v);
    if (!file) throw new MediaError("unsupported", "媒体服务读不到这个文件（受保护的文件夹），读不了片子里的字幕");
    const out = join(this.#o.dir, "videos", "subs", `${v.id}-${v.mtime}-${v.size}-${track.index}.vtt`);
    const kept = await readFile(out, "utf8").catch(() => null);
    if (kept !== null) return kept;
    const making = this.#subs.get(out);
    if (making) return making;
    const work = (async () => {
      await mkdir(posix.dirname(out), { recursive: true });
      const tmp = `${out}.${randomBytes(4).toString("hex")}.vtt`;
      try {
        await runFfmpeg(this.tools.ffmpeg!, ["-i", file, "-map", `0:${track.index}`, "-c:s", "webvtt", "-f", "webvtt", tmp], 300_000);
        await rename(tmp, out);
      } finally {
        await rm(tmp, { force: true });
      }
      return readFile(out, "utf8");
    })().finally(() => this.#subs.delete(out));
    this.#subs.set(out, work);
    return work;
  }
}

/// The first picture among a folder's files (by lowercase name) named one of `stems` (jpg, jpeg, png, webp).
function pictureOf(lower: Map<string, DriveEntry>, stems: string[]): DriveEntry | null {
  for (const s of stems) {
    for (const ext of IMAGES) {
      const e = lower.get(`${s.toLowerCase()}.${ext}`);
      if (e) return e;
    }
  }
  return null;
}
