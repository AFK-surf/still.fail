// Files in a chat, as web/src/Chat.tsx shows them: images and video stills side by side at their own proportions
// (known before they load, a ThumbHash likeness standing in), the rest as cards; any of them opens in a full-screen
// preview (FilePreview.tsx).
import { requireOptionalNativeModule } from "expo";
import { Directory, File, Paths } from "expo-file-system";
import * as VideoThumbnails from "expo-video-thumbnails";
import { useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { Image, PixelRatio, Platform, Pressable, StyleSheet, View, type DimensionValue, type StyleProp, type ViewStyle } from "react-native";
import Animated, { Easing, useAnimatedProps, useAnimatedStyle, useSharedValue, withDelay, withRepeat, withTiming, type SharedValue } from "react-native-reanimated";
import Svg, { Circle, Defs, LinearGradient, Path, RadialGradient, Rect, Stop } from "react-native-svg";
import type { Attachment } from "../../../../web/src/core/shapes.ts";
import { CoreError } from "../../../../web/src/core/client.ts";
import { app, type AppState, type ChatOf } from "../AppState";
import type { ByteSource, DiskFile } from "../data/Calls";
import { t } from "../i18n";
import { Icon, Icons } from "../ui/Icon";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";
import { chatInk } from "../ui/ChatInk";
import { fileSize } from "../ui/Controls";
import { ThumbHash } from "../ui/ThumbHash";
import { Spinner } from "../ui/Waiting";
import { DriveCache } from "../data/DriveCache";
import { KeptFiles } from "./KeptFiles";
import { mediaSize, type MediaSize } from "./MediaSize";
import type { Here } from "./Chat";
import { LandingFile } from "./ChatHost";
import { FilePreview, FileViewers, ForgetThumb, useViewerThumb, type Gallery } from "./FilePreview";

// ── what a file is (web/src/FilePreview.tsx kindOf) ─────────────────────

export const PreviewKind = {
  Image: "image", Video: "video", Audio: "audio", Pdf: "pdf", Markdown: "markdown", Csv: "csv", Html: "html", Code: "code", Text: "text",
} as const;
export type PreviewKind = (typeof PreviewKind)[keyof typeof PreviewKind];
/** A kind's name in words (PreviewKind.label). */
export const kindLabel = (kind: PreviewKind) => t("android-chat.kind." + kind);

/** What a file shows as, by its name; `kind` null: look at its bytes to know. */
export interface Kind { kind: PreviewKind | null; type: string; language: string | null }

const MEDIA: Record<string, [PreviewKind, string]> = {
  png: [PreviewKind.Image, "image/png"], jpg: [PreviewKind.Image, "image/jpeg"], jpeg: [PreviewKind.Image, "image/jpeg"],
  gif: [PreviewKind.Image, "image/gif"], webp: [PreviewKind.Image, "image/webp"], svg: [PreviewKind.Image, "image/svg+xml"],
  avif: [PreviewKind.Image, "image/avif"], bmp: [PreviewKind.Image, "image/bmp"], ico: [PreviewKind.Image, "image/x-icon"],
  mp4: [PreviewKind.Video, "video/mp4"], m4v: [PreviewKind.Video, "video/mp4"], webm: [PreviewKind.Video, "video/webm"],
  mov: [PreviewKind.Video, "video/quicktime"], ogv: [PreviewKind.Video, "video/ogg"],
  mp3: [PreviewKind.Audio, "audio/mpeg"], m4a: [PreviewKind.Audio, "audio/mp4"], aac: [PreviewKind.Audio, "audio/aac"],
  wav: [PreviewKind.Audio, "audio/wav"], ogg: [PreviewKind.Audio, "audio/ogg"], oga: [PreviewKind.Audio, "audio/ogg"],
  opus: [PreviewKind.Audio, "audio/ogg"], flac: [PreviewKind.Audio, "audio/flac"],
  pdf: [PreviewKind.Pdf, "application/pdf"],
  md: [PreviewKind.Markdown, "text/markdown"], markdown: [PreviewKind.Markdown, "text/markdown"],
  csv: [PreviewKind.Csv, "text/csv"], tsv: [PreviewKind.Csv, "text/tab-separated-values"],
  html: [PreviewKind.Html, "text/html"], htm: [PreviewKind.Html, "text/html"],
};
/** Extensions known by another name; the rest are tried as they are. */
const LANGUAGE: Record<string, string> = {
  mjs: "js", cjs: "js", mts: "ts", cts: "ts", h: "c", hh: "cpp", hpp: "cpp", cc: "cpp", cxx: "cpp",
  kts: "kotlin", yml: "yaml", zsh: "bash", sh: "bash", patch: "diff", htm: "html", conf: "ini", cfg: "ini",
  env: "dotenv", gradle: "groovy", plist: "xml", svg: "xml",
};
const PLAIN = new Set(["txt", "text", "log", "out", "err", "lock"]);
const NAMED: Record<string, string> = { dockerfile: "docker", makefile: "make", "cmakelists.txt": "cmake" };
const CODE = new Set([
  "ts", "tsx", "js", "jsx", "json", "jsonc", "json5", "py", "rs", "go", "java", "kt", "swift", "c", "cpp", "cs", "rb", "php", "bash", "fish", "ps1",
  "yaml", "toml", "xml", "sql", "css", "scss", "less", "html", "vue", "svelte", "lua", "dart", "diff", "ini", "dotenv", "groovy", "scala", "r", "pl", "ex", "exs",
  "erl", "hs", "ml", "clj", "zig", "nim", "proto", "graphql", "tex", "vim", "nix", "tf", "hcl", "docker", "make", "cmake", "asm", "wasm", "sol", "prisma", "astro",
]);

export function kindOf(name: string): Kind {
  const lower = name.toLowerCase();
  const named = NAMED[lower];
  if (named) return { kind: PreviewKind.Code, type: "text/plain", language: named };
  const dot = lower.lastIndexOf(".");
  const ext = dot > 0 ? lower.substring(dot + 1) : "";
  const media = MEDIA[ext];
  if (media) return { kind: media[0], type: media[1], language: media[0] === PreviewKind.Html ? "html" : null };
  if (PLAIN.has(ext)) return { kind: PreviewKind.Text, type: "text/plain", language: null };
  const language = LANGUAGE[ext] ?? ext;
  if (CODE.has(language)) return { kind: PreviewKind.Code, type: "text/plain", language };
  return { kind: null, type: "application/octet-stream", language: null };
}

export const isImage = (name: string) => kindOf(name).kind === PreviewKind.Image;

// ── fetching ───────────────────────────────────────────────────────────

/**
 * A picture this app shows (the Kotlin's ImageBitmap): a file of its own on the phone's disk (or a data URI), and its
 * size in its own pixels.
 */
export interface Picture { uri: string; width: number; height: number }

/** Bytes so far and the whole size (null when the station does not say). */
export type Got = [loaded: number, total: number | null];

/** A cache that lets the least lately used go once what it holds weighs more than `max` (android.util.LruCache). */
class LruCache<K, V> {
  readonly #map = new Map<K, V>();
  #weight = 0;
  constructor(private readonly max: number, private readonly sizeOf: (key: K, value: V) => number = () => 1) {}
  get(key: K): V | undefined {
    const v = this.#map.get(key);
    if (v === undefined) return undefined;
    this.#map.delete(key);
    this.#map.set(key, v);
    return v;
  }
  put(key: K, value: V) {
    const was = this.#map.get(key);
    if (was !== undefined) { this.#weight -= this.sizeOf(key, was); this.#map.delete(key); }
    this.#map.set(key, value);
    this.#weight += this.sizeOf(key, value);
    while (this.#weight > this.max && this.#map.size > 0) {
      const [k, v] = this.#map.entries().next().value as [K, V];
      this.#map.delete(k);
      this.#weight -= this.sizeOf(k, v);
    }
  }
}

/** A deferred value (Kotlin's Deferred): the promise of it, awaited by however many ask. */
export interface Deferred<T> { await(): Promise<T> }
const deferred = <T,>(p: Promise<T>): Deferred<T> => ({ await: () => p });

/** Over this a file is fetched onto the disk a part at a time (FileData.toDisk), not into memory; web's BIG_FILE. */
export const BIG_FILE = 16 * 1024 * 1024;
/** The most a station from before parts sends (whole). */
const WHOLE_FILE_MAX = 50 * 1024 * 1024;

/** A short, stable name for a long id (a file's name on the disk). */
function hashOf(text: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) { h ^= text.charCodeAt(i); h = Math.imul(h, 0x01000193); }
  return (h >>> 0).toString(16).padStart(8, "0");
}


/** A store of values the screen draws from (Compose's snapshot state): read with `use`, changed with `set`. */
class Watched<T> {
  #value: T;
  readonly #listeners = new Set<() => void>();
  constructor(value: T) { this.#value = value; }
  get value() { return this.#value; }
  set value(v: T) { if (v === this.#value) return; this.#value = v; for (const l of this.#listeners) l(); }
  subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
}
export function useWatched<T>(w: Watched<T>): T {
  return useSyncExternalStore(w.subscribe, () => w.value);
}
export { Watched };

/** A file on the phone's disk as the station's calls write it (Calls.ts DiskFile): appended to, a part at a time. */
export function diskFileOf(file: File): DiskFile {
  return {
    length: async () => (file.exists ? file.size ?? 0 : 0),
    append: async (bytes: Uint8Array) => {
      if (!file.exists) file.create();
      const out = file.open();
      try {
        out.offset = out.size ?? 0;
        out.writeBytes(bytes);
      } finally {
        out.close();
      }
    },
  };
}

/** A file on the phone's disk read as it goes (Calls.ts ByteSource, a java.io.InputStream). */
export function byteSourceOf(file: File): ByteSource {
  const input = file.open();
  input.offset = 0;
  return {
    read: async (into: Uint8Array, offset: number, length: number) => {
      const got = input.readBytes(length);
      if (got.length === 0) return -1;
      into.set(got, offset);
      return got.length;
    },
    skip: async (n: number) => {
      const at = input.offset ?? 0;
      const size = input.size ?? 0;
      const by = Math.max(0, Math.min(n, size - at));
      input.offset = at + by;
      return by;
    },
    close: () => input.close(),
  };
}

/** The directory of the app's cache `name` is kept in, made when it is not there. */
function cacheDir(name: string): Directory {
  const d = new Directory(Paths.cache, name);
  if (!d.exists) d.create({ intermediates: true, idempotent: true });
  return d;
}

/**
 * Files sent never change: each is fetched once (a chat's image as its thumbnail, a whole file when opened), the
 * most recent kept. How far each whole file on its way has come is kept for whoever shows it.
 */
export const FileData = new (class {
  // Bounded as a phone's heap can spare: bytes up to 32 MB (a larger file is fetched again when opened again);
  // pictures are files on the disk, a few hundred of them remembered.
  readonly #kept = new LruCache<string, Uint8Array>(32 * 1024 * 1024, (_, v) => v.length);
  readonly #coming = new Map<string, Deferred<Uint8Array>>();
  /** Files of a drive kept whole on the phone (DriveCache), by id: what `onDisk` hands out rather than write them again. */
  readonly #onPhone = new Map<string, File>();
  readonly #pictures = new LruCache<string, Picture>(512);
  /** Bytes so far and the whole size (null when the station does not say), of whole files on their way. */
  readonly progress = new Watched<ReadonlyMap<string, Got>>(new Map());

  #setProgress(id: string, got: Got | null) {
    const next = new Map(this.progress.value);
    if (got) next.set(id, got); else next.delete(id);
    this.progress.value = next;
  }
  /** How far the whole file `id` has come while it comes (null otherwise), drawn again as it does. */
  useProgress(id: string): Got | null {
    return useSyncExternalStore(this.progress.subscribe, () => this.progress.value.get(id) ?? null);
  }

  id(station: string, key: string, file: Attachment, thumb: boolean) { return `${station}/${key}/${file.path}${thumb ? "#thumb" : ""}`; }

  kept(id: string): Uint8Array | null { return this.#kept.get(id) ?? null; }

  /** Bytes this device already has (a picture in the composer, not sent yet), for the viewer to read as fetched. */
  keep(id: string, bytes: Uint8Array) { this.#kept.put(id, bytes); }

  /** The file (`thumb`: as a chat shows an image), fetched once however many ask. */
  fetch(_app: AppState, station: string, key: string, file: Attachment, thumb: boolean): Deferred<Uint8Array> {
    const id = this.id(station, key, file, thumb);
    const kept = this.#kept.get(id);
    if (kept) return deferred(Promise.resolve(kept));
    const coming = this.#coming.get(id);
    if (coming) return coming;
    const on = thumb ? null : (loaded: number, total: number | null) => { if (this.#coming.has(id)) this.#setProgress(id, [loaded, total]); };
    const got = (async () => {
      try {
        const root = DriveKey.rootOf(key);
        const mtime = DriveKey.mtimeOf(key);
        // A file of a station's drive (the viewer opened from its page): kept on the phone once read (DriveCache),
        // else read from its root, a part at a time.
        if (root !== null && mtime !== null && file.size > 0) {
          const held = await DriveCache.fetch(app.api(station), root, file.path, mtime, file.size, undefined, (loaded: number, total: number) => on?.(loaded, total));
          this.#onPhone.set(id, held.file);
          const bytes = await held.file.bytes();
          this.#kept.put(id, bytes);
          return bytes;
        }
        if (root !== null) {
          const bytes: Uint8Array = await app.api(station).driveBytes(root, file.path, undefined, file.size > 0 ? file.size : Number.MAX_SAFE_INTEGER, (loaded: number, total: number) => on?.(loaded, total));
          this.#kept.put(id, bytes);
          return bytes;
        }
        const bytes = (await app.api(station).file(key, file.path.substring(file.path.lastIndexOf("/") + 1), thumb, on))[1];
        this.#kept.put(id, bytes);
        return bytes;
      } finally {
        this.#coming.delete(id);
        this.#setProgress(id, null);
      }
    })();
    const d = deferred(got);
    this.#coming.set(id, d);
    return d;
  }

  /** The first `length` bytes of the file (all of it when kept already): enough to tell what it is without fetching the whole. */
  async head(_app: AppState, station: string, key: string, file: Attachment, length: number): Promise<Uint8Array> {
    const kept = this.#kept.get(this.id(station, key, file, false));
    if (kept) return kept;
    const root = DriveKey.rootOf(key);
    const mtime = DriveKey.mtimeOf(key);
    if (root !== null && mtime !== null) {
      const head: Uint8Array | null = await DriveCache.head(station, root, file.path, mtime, file.size, length);
      if (head) return head;
    }
    if (root !== null) return (await app.api(station).driveRead(root, file.path, 0, length)).bytes as Uint8Array;
    return app.api(station).fileHead(key, file.path.substring(file.path.lastIndexOf("/") + 1), length);
  }

  /** A picture made from `bytes` (`longest`: the size it is shown at most, as the Kotlin decodes it); kept by `id`. */
  async picture(id: string, bytes: Uint8Array, longest: number): Promise<Picture | null> {
    const tag = `${id}@${longest}`;
    const kept = this.#pictures.get(tag);
    if (kept) return kept;
    const got = await decode(bytes, longest, id);
    if (got) this.#pictures.put(tag, got);
    return got;
  }

  keptPicture(id: string, longest: number): Picture | null { return this.#pictures.get(`${id}@${longest}`) ?? null; }

  /** Pictures sent from here as they were picked (by station and file name), until the station's own are read. */
  readonly #sent = new LruCache<string, Picture>(32);
  keepSent(station: string, path: string, picture: Picture) { this.#sent.put(`${station}\n${path.substring(path.lastIndexOf("/") + 1)}`, picture); }
  sentPicture(station: string, path: string): Picture | null { return this.#sent.get(`${station}\n${path.substring(path.lastIndexOf("/") + 1)}`) ?? null; }
  keepPicture(id: string, longest: number, picture: Picture) { this.#pictures.put(`${id}@${longest}`, picture); }

  readonly #comingToDisk = new Map<string, Deferred<File>>();

  /**
   * A big file (over BIG_FILE) onto the phone's disk a part at a time, never all in memory: what the viewers of a
   * big one read. Fetched once however many ask, and gone on from where it stopped when asked again; its progress as
   * a whole file's. A station from before parts sends it whole, as long as that takes it (WHOLE_FILE_MAX).
   */
  toDisk(_app: AppState, station: string, key: string, file: Attachment): Deferred<File> {
    const id = this.id(station, key, file, false);
    const coming = this.#comingToDisk.get(id);
    if (coming) return coming;
    const heard = (loaded: number, total: number | null) => { if (this.#comingToDisk.has(id)) this.#setProgress(id, [loaded, total]); };
    const got = (async () => {
      try {
        const root = DriveKey.rootOf(key);
        const mtime = DriveKey.mtimeOf(key);
        // A file of a station's drive: kept with the drive's others (DriveCache), by when it changed.
        if (root !== null && mtime !== null) {
          const kept = (await DriveCache.fetch(app.api(station), root, file.path, mtime, file.size, undefined, heard)).file as File;
          this.#onPhone.set(id, kept);
          return kept;
        }
        const done: File = KeptFiles.place(id, file.name, file.size);
        if (done.exists && done.size === file.size) return done;
        const part = new File(done.parentDirectory, done.name + ".part");
        const name = file.path.substring(file.path.lastIndexOf("/") + 1);
        try {
          if (root !== null) await app.api(station).driveToDisk(root, file.path, diskFileOf(part), file.size, heard);
          else await app.api(station).fileToDisk(key, name, diskFileOf(part), file.size, heard);
        } catch (e) {
          if (!(e instanceof CoreError) || e.code !== "unsupported" || file.size > WHOLE_FILE_MAX) throw e;
          return this.onDisk(id, file.name, await app.api(station).file(key, name));
        }
        if (done.exists) done.delete();
        part.move(done);
        return done;
      } finally {
        this.#comingToDisk.delete(id);
        this.#setProgress(id, null);
      }
    })();
    const d = deferred(got);
    this.#comingToDisk.set(id, d);
    return d;
  }

  /**
   * The file on the phone's disk, for what reads a file rather than bytes (the players, the PDF renderer); kept until
   * the person deletes it (settings → files kept, KeptFiles.tsx).
   */
  async onDisk(id: string, name: string, bytes: Uint8Array): Promise<File> {
    const held = this.#onPhone.get(id);
    if (held && held.exists && held.size === bytes.length) return held;
    const file: File = KeptFiles.place(id, name, bytes.length);
    if (!file.exists || file.size !== bytes.length) {
      const part = new File(file.parentDirectory, file.name + ".part");
      if (part.exists) part.delete();
      part.create();
      part.write(bytes);
      if (file.exists) file.delete();
      part.move(file);
    }
    return file;
  }
})();

/** A file's extension by what its first bytes say it is (a picture's file on the disk needs one to be read as one). */
function pictureExt(bytes: Uint8Array): string {
  if (bytes[0] === 0x89 && bytes[1] === 0x50) return "png";
  if (bytes[0] === 0xff && bytes[1] === 0xd8) return "jpg";
  if (bytes[0] === 0x47 && bytes[1] === 0x49) return "gif";
  if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[8] === 0x57) return "webp";
  if (bytes[0] === 0x42 && bytes[1] === 0x4d) return "bmp";
  if (bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70) return "avif";
  return "img";
}

/**
 * A picture from bytes: written to a file of the cache and read for its size by the system's decoder (which, on
 * Android, decodes it at the size it is shown, never the whole of a huge photo in memory: `longest` names the size it
 * is wanted at, as the Kotlin's decode takes it). Null when the bytes are not a picture the system reads.
 */
export async function decode(bytes: Uint8Array, longest: number, id = ""): Promise<Picture | null> {
  if (bytes.length === 0) return null;
  const file = new File(cacheDir("pictures"), `${hashOf(id || String(bytes.length))}-${bytes.length}-${longest}.${pictureExt(bytes)}`);
  try {
    if (!file.exists || file.size !== bytes.length) {
      if (file.exists) file.delete();
      file.create();
      file.write(bytes);
    }
    const { width, height } = await Image.getSize(file.uri);
    if (width <= 0 || height <= 0) return null;
    return { uri: file.uri, width, height };
  } catch {
    return null;
  }
}

/**
 * A file of a station's drive shown by the viewer (drive/DriveScreen.tsx), as the viewer knows files by a session's key:
 * the key names its root and when it last changed instead (a file changed is fetched anew, not taken from what is kept).
 */
export const DriveKey = {
  TAG: "drive\u0001",
  of(root: string, mtime: number) { return `${this.TAG}${mtime}\u0001${root}`; },
  /** When the file a key names last changed; null for a session's key. */
  mtimeOf(key: string): number | null {
    if (!key.startsWith(DriveKey.TAG)) return null;
    const rest = key.substring(DriveKey.TAG.length);
    const at = rest.indexOf("\u0001");
    const n = Number(at >= 0 ? rest.substring(0, at) : rest);
    return Number.isFinite(n) && (at >= 0 ? rest.substring(0, at) : rest) !== "" ? n : null;
  },
  /** The root a key names; null for a session's key. */
  rootOf(key: string): string | null {
    if (!key.startsWith(DriveKey.TAG)) return null;
    const rest = key.substring(DriveKey.TAG.length);
    const at = rest.indexOf("\u0001");
    return at >= 0 ? rest.substring(at + 1) : rest;
  },
};

// ── in the chat ────────────────────────────────────────────────────────

/** A file and the session that keeps it. */
export class Shown {
  constructor(readonly key: string, readonly file: Attachment) {}
}

/** Compose's ripple, as a pressed thing shows it. */
const ripple = (ink: string) => ({ color: withAlpha(ink, 0.1), borderless: false });

/** A message's files, side by side and wrapping (6dp apart); `owner` says which session of the chat keeps each. */
export function Files({ ctx, list, mine = false }: { ctx: Here; list: Attachment[]; mine?: boolean }) {
  const [open, setOpen] = useState<Attachment | null>(null);
  if (list.length === 0) return null;
  const shown = open;
  const key = shown ? ctx.owner(shown) : null;
  return (
    <>
      <Wrap gap={6} end={mine}>
        {/* Each flown into from its tile in the composer, when it was just sent from there (ChatHost.tsx). */}
        {list.map((f) => (
          <LandingFile key={f.path} path={f.path}>
            <FileItem station={ctx.station} sessionKey={ctx.owner(f)} file={f} onOpen={() => setOpen(f)} />
          </LandingFile>
        ))}
      </Wrap>
      {shown && key ? <FilePreview station={ctx.station} sessionKey={key} file={shown} gallery={{ kind: "Chat", of: ctx.of }} onClose={() => setOpen(null)} /> : null}
    </>
  );
}

/** Its children in rows as wide as it may be, `gap` apart, each row from the start (or the end). */
function Wrap({ gap, end, children }: { gap: number; end: boolean; children: ReactNode }) {
  return (
    <View style={{ flexDirection: "row", flexWrap: "wrap", gap, justifyContent: end ? "flex-end" : "flex-start", alignSelf: end ? "flex-end" : "flex-start", maxWidth: "100%" }}>
      {children}
    </View>
  );
}

/**
 * An image of the chat on its own (placed in an agent's text, Prose.tsx): in the box `size` gives it (else its own
 * proportions); a tap opens it in the preview, stepping through the images of the chat `gallery` names.
 */
export function StationImage({ station, sessionKey, file, modifier = null, gallery = null }: { station: string; sessionKey: string; file: Attachment; modifier?: StyleProp<ViewStyle> | null; gallery?: ChatOf | null }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <ChatImage station={station} sessionKey={sessionKey} file={file} size={modifier} onOpen={() => setOpen(true)} />
      {open ? <FilePreview station={station} sessionKey={sessionKey} file={file} gallery={gallery ? { kind: "Chat", of: gallery } : null} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

/** One file of the chat on its own, as a message shows it, opening in the preview (what has no message around it). */
export function StationFile({ station, sessionKey, file }: { station: string; sessionKey: string; file: Attachment }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <FileItem station={station} sessionKey={sessionKey} file={file} onOpen={() => setOpen(true)} />
      {open ? <FilePreview station={station} sessionKey={sessionKey} file={file} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

/**
 * Images and video stills show in a box of their own proportions; other files are a card. Either opens in a preview.
 * An image sent from here before its chat has a session to keep it (a new chat still being made) shows the picture it
 * had in the composer, as web Chat.tsx FileItem does, rather than a card until the session comes.
 */
function FileItem({ station, sessionKey, file, onOpen }: { station: string; sessionKey: string | null; file: Attachment; onOpen: () => void }) {
  const kind = kindOf(file.name).kind;
  if (kind === PreviewKind.Image && (sessionKey !== null || FileData.sentPicture(station, file.path) !== null)) return <ChatImage station={station} sessionKey={sessionKey} file={file} onOpen={onOpen} />;
  if (sessionKey !== null && kind === PreviewKind.Video) return <ChatVideo station={station} sessionKey={sessionKey} file={file} onOpen={onOpen} />;
  return <FileCard name={file.name} size={file.size} onClick={sessionKey !== null ? onOpen : null} />;
}

/**
 * The box an image takes in the chat, known before it loads: its own proportions (sent with it, or read from its
 * ThumbHash) as mediaSize puts them, or a fixed box for images sent before sizes were recorded. A narrower chat shrinks it.
 */
export function imageBox(file: Attachment, least = 16): MediaSize {
  const ratio = ThumbHash.ratio(file.thumbhash ?? null);
  const width = file.width;
  const height = file.height;
  let w: number, h: number;
  if (width != null && height != null && width > 0 && height > 0) { w = width; h = height; }
  else if (ratio != null) { w = Math.round(160 * ratio); h = 160; }
  else return { width: 240, height: 160, fit: null };
  return mediaSize(w, h, least);
}

const IMAGE_RADIUS = 10;
const EaseOut = Easing.bezier(0.16, 1, 0.3, 1);

/** Images already brushed in on this run (station, session and path): shown again, they just show. */
const revealed = new Set<string>();

/** The longest side a chat's thumbnail is wanted at (360dp, in the screen's pixels): the key its picture is kept by. */
export const chatLongest = () => Math.round(360 * PixelRatio.get());

/**
 * An image's box; until it loads, its likeness (or the blots drifting); one that takes a while is brushed in from the top.
 * Without a session (`sessionKey` null) only the picture it was sent with shows, and it does not open yet.
 */
function ChatImage({ station, sessionKey, file, size = null, onOpen }: { station: string; sessionKey: string | null; file: Attachment; size?: StyleProp<ViewStyle> | null; onOpen: () => void }) {
  const C = useC();
  const id = FileData.id(station, sessionKey ?? "", file, true);
  const longest = chatLongest();
  // One sent from here shows the picture it had in the composer until the station's comes (it flies in from there).
  const sent = useMemo(() => FileData.sentPicture(station, file.path), [id]);
  const [image, setImage] = useState<Picture | null>(() => FileData.keptPicture(id, longest) ?? sent);
  const [failed, setFailed] = useState(false);
  const instant = useMemo(() => image !== null || revealed.has(id), [id]);
  const born = useMemo(() => Date.now(), [id]);
  const [reveal, setReveal] = useState(false);
  useEffect(() => {
    setImage(FileData.keptPicture(id, longest) ?? sent);
    setFailed(false);
    if (sessionKey === null || FileData.keptPicture(id, longest) !== null) return;
    let gone = false;
    (async () => {
      try {
        const bytes = await FileData.fetch(app, station, sessionKey, file, true).await();
        const got = await FileData.picture(id, bytes, longest);
        if (gone) return;
        if (got === null) setFailed(sent === null);
        else {
          setReveal(!instant && Date.now() - born >= 150);
          setImage(got);
          revealed.add(id);
        }
      } catch (e) {
        if (!gone && e instanceof CoreError) setFailed(sent === null);
      }
    })();
    return () => { gone = true; };
  }, [id]);
  // What the viewer grows out of and shrinks back into (FilePreview.tsx).
  const thumb = FileViewers.id(station, sessionKey ?? "", file.path);
  const box = imageBox(file);
  // Letterboxed only in its own box (one given it is filled).
  const fit = size === null ? box.fit : null;
  const imageRef = useRef(image);
  imageRef.current = image;
  const viewer = useViewerThumb(thumb, IMAGE_RADIUS, fit != null, true, () => imageRef.current);
  return (
    <>
      <ForgetThumb id={thumb} />
      <MediaBox box={box} size={size} viewer={viewer} background={fit != null && !failed ? "transparent" : C.chip} enabled={sessionKey !== null && (image !== null || failed)} onClick={onOpen}>
        {!instant ? <Waiting hash={file.thumbhash ?? null} loaded={image !== null} still={failed} fit={fit} /> : null}
        {failed ? <Unavailable icon={20} size={null} /> : null}
        {image ? <Revealed image={image} name={file.name} reveal={reveal} scale={fit != null ? "contain" : "cover"} /> : null}
      </MediaBox>
    </>
  );
}

type ViewerThumb = ReturnType<typeof useViewerThumb>;

function MediaBox({ box, size, viewer, background, enabled, onClick, children }: {
  box: MediaSize; size?: StyleProp<ViewStyle> | null; viewer: ViewerThumb; background: string; enabled: boolean; onClick: () => void; children: ReactNode;
}) {
  const C = useC();
  const own: ViewStyle = { maxWidth: box.width, width: "100%" as DimensionValue, aspectRatio: box.width / box.height };
  return (
    <View ref={viewer.ref} collapsable={false} onLayout={viewer.onLayout} style={[size ?? own, viewer.style]}>
      <Smooth radius={IMAGE_RADIUS} style={[StyleSheet.absoluteFill, { backgroundColor: background }]}>
        <Pressable disabled={!enabled} onPress={onClick} android_ripple={ripple(C.ink)} style={StyleSheet.absoluteFill}>
          {children}
        </Pressable>
      </Smooth>
    </View>
  );
}

const AnimatedImage = Animated.createAnimatedComponent(Image);

/** The picture, brushed in from the top when `reveal` (blurred to sharp, from a little larger), else just shown. */
function Revealed({ image, name, reveal, scale }: { image: Picture; name: string; reveal: boolean; scale: "contain" | "cover" }) {
  const C = useC();
  const k = useSharedValue(reveal ? 0 : 1);
  const [h, setH] = useState(0);
  useEffect(() => { if (k.value < 1) k.value = withTiming(1, { duration: 1100, easing: EaseOut }); }, []);
  const grow = useAnimatedStyle(() => ({ transform: [{ scale: k.value < 1 ? 1.04 - 0.04 * k.value : 1 }] }));
  // Blurred to sharp where the system blurs a picture's drawing (Android 12 on, as the Kotlin's RenderEffect).
  const blurs = Platform.OS !== "android" || (Platform.Version as number) >= 31;
  const blur = useAnimatedProps(() => {
    const b = 14 * (1 - k.value);
    return { blurRadius: blurs && k.value < 1 && b > 0.5 ? b : 0 };
  });
  // The web's mask: opaque down to an edge that sweeps from above the box to below it. Drawn here as the box's own
  // ground over the picture below the edge (what a DstIn mask leaves showing there), the edge `solid` → `clear` soft.
  const sweep = useAnimatedStyle(() => {
    const solid = -0.5 * h + 1.5 * h * k.value;
    return { opacity: k.value < 1 ? 1 : 0, transform: [{ translateY: solid }] };
  });
  return (
    <View style={StyleSheet.absoluteFill}>
      <Animated.View style={[StyleSheet.absoluteFill, grow]} onLayout={(e) => setH(e.nativeEvent.layout.height)}>
        <AnimatedImage source={{ uri: image.uri }} accessibilityLabel={name} resizeMode={scale} style={StyleSheet.absoluteFill} animatedProps={blur} />
      </Animated.View>
      {reveal && h > 0 ? (
        <Animated.View pointerEvents="none" style={[{ position: "absolute", left: 0, right: 0, top: 0, height: h * 2.5 }, sweep]}>
          <Svg width="100%" height={h * 0.5}>
            <Defs>
              <LinearGradient id="sweep" x1="0" y1="0" x2="0" y2="1">
                <Stop offset="0" stopColor={C.chip} stopOpacity={0} />
                <Stop offset="1" stopColor={C.chip} stopOpacity={1} />
              </LinearGradient>
            </Defs>
            <Rect x="0" y="0" width="100%" height="100%" fill="url(#sweep)" />
          </Svg>
          <View style={{ height: h * 2, backgroundColor: C.chip }} />
        </Animated.View>
      ) : null}
    </View>
  );
}

/**
 * What an image's box shows until it loads: its ThumbHash drawn, sent with it; else a few warm blots drifting. Fades
 * once it has. Letterboxed, it takes only the image's share of the box (`fit`), centred.
 */
function Waiting({ hash, loaded, still, fit }: { hash: string | null; loaded: boolean; still: boolean; fit: [number, number] | null | undefined }) {
  const C = useC();
  const fade = useSharedValue(1);
  const [gone, setGone] = useState(false);
  useEffect(() => {
    if (!loaded) return;
    fade.value = withDelay(800, withTiming(0, { duration: 300, easing: EaseOut }));
    const done = setTimeout(() => setGone(true), 1100);
    return () => clearTimeout(done);
  }, [loaded]);
  const likeness = useMemo(() => ThumbHash.image(hash), [hash]);
  const faded = useAnimatedStyle(() => ({ opacity: fade.value }));
  if (gone) return null;
  const area: ViewStyle = fit == null ? StyleSheet.absoluteFillObject : { position: "absolute", left: `${(1 - fit[0]) * 50}%`, top: `${(1 - fit[1]) * 50}%`, width: `${fit[0] * 100}%`, height: `${fit[1] * 100}%` };
  return (
    <Animated.View style={[area, { backgroundColor: C.chip, overflow: "hidden" }, faded]}>
      {likeness ? <Image source={likeness} resizeMode="cover" style={StyleSheet.absoluteFill} /> : <Blots still={still} />}
    </Animated.View>
  );
}

const AnimatedCircle = Animated.createAnimatedComponent(Circle);

interface Blot { color: string; x: number; y: number; dx: number; dy: number; scale: number; ms: number }

function Blots({ still }: { still: boolean }) {
  const C = useC();
  const dark = C.dark;
  const blots = useMemo<Blot[]>(() => [
    { color: dark ? "#7C3A22" : "#F6A27E", x: -0.15, y: -0.2, dx: 0.35, dy: 0.25, scale: 1.15, ms: 6000 },
    { color: dark ? "#6A4A22" : "#F1C58C", x: 0.5, y: 0.1, dx: -0.3, dy: 0.2, scale: 0.9, ms: 7000 },
    { color: dark ? "#6B3534" : "#E7A9A1", x: 0.15, y: 0.65, dx: 0.2, dy: -0.3, scale: 1.1, ms: 8000 },
  ], [dark]);
  const [size, setSize] = useState({ width: 0, height: 0 });
  return (
    <View style={StyleSheet.absoluteFill} onLayout={(e) => setSize({ width: e.nativeEvent.layout.width, height: e.nativeEvent.layout.height })}>
      {size.width > 0 ? (
        <Svg width={size.width} height={size.height}>
          <Defs>
            {/* Blurred edges: a radial fall-off rather than a blur filter. */}
            {blots.map((b, i) => (
              <RadialGradient key={i} id={`blot${i}`} cx="50%" cy="50%" r="50%">
                <Stop offset="0" stopColor={b.color} stopOpacity={0.75} />
                <Stop offset="0.55" stopColor={b.color} stopOpacity={0.45} />
                <Stop offset="1" stopColor={b.color} stopOpacity={0} />
              </RadialGradient>
            ))}
          </Defs>
          {blots.map((b, i) => <BlotCircle key={i} blot={b} i={i} still={still} width={size.width} height={size.height} />)}
        </Svg>
      ) : null}
    </View>
  );
}

function BlotCircle({ blot: b, i, still, width, height }: { blot: Blot; i: number; still: boolean; width: number; height: number }) {
  const p = useSharedValue(0);
  useEffect(() => {
    if (still) { p.value = 0; return; }
    p.value = withRepeat(withTiming(1, { duration: b.ms, easing: Easing.bezier(0.42, 0, 0.58, 1) }), -1, true);
  }, [still, b.ms]);
  const side = width * 0.7;
  const props = useAnimatedProps(() => {
    const k = (p as SharedValue<number>).value;
    const s = side * (1 + (b.scale - 1) * k);
    return { cx: width * b.x + side / 2 + side * b.dx * k, cy: height * b.y + side / 2 + side * b.dy * k, r: s * 0.8 };
  });
  return <AnimatedCircle animatedProps={props} fill={`url(#blot${i})`} />;
}

/** Not to be had (fetching it failed): the box stays as it waited, and says so. */
function Unavailable({ icon, size }: { icon: number; size: number | null }) {
  const C = useC();
  return (
    <View style={[StyleSheet.absoluteFill, { backgroundColor: withAlpha(C.chip, 0.7), alignItems: "center", justifyContent: "center", gap: 6 }]}>
      <Icon icon={Icons.Read} size={icon} color={C.muted} />
      <T size={12} color={C.muted}>{t("android-chat.file.noPreview")}</T>
      {size !== null ? <T size={11} color={C.muted}>{fileSize(size)}</T> : null}
    </View>
  );
}

/** A video's frame at `ms` (its first by default), drawn from the file on the disk; null when none can be read. */
export async function frameOf(uri: string, ms = 0): Promise<Picture | null> {
  try {
    const got = await VideoThumbnails.getThumbnailAsync(uri, { time: ms, quality: 1 });
    return { uri: got.uri, width: got.width, height: got.height };
  } catch {
    return null;
  }
}

/** A video's first frame on black, a play mark over it and its name along the bottom; tapped, it plays in the preview. */
function ChatVideo({ station, sessionKey, file, onOpen }: { station: string; sessionKey: string; file: Attachment; onOpen: () => void }) {
  const C = useC();
  const id = FileData.id(station, sessionKey, file, false);
  const [still, setStill] = useState<Picture | null>(() => FileData.keptPicture(`${id}#still`, 0));
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    if (still !== null) return;
    let gone = false;
    (async () => {
      try {
        // The station's poster where it makes one; else the video itself while it is small, its first frame drawn
        // here; a big one shows without (fetched whole only to be drawn from, it would not fit in memory).
        let poster: Uint8Array | null = null;
        try {
          poster = await app.api(station).poster(sessionKey, file.path.substring(file.path.lastIndexOf("/") + 1));
        } catch (e) {
          if (!(e instanceof CoreError)) throw e;
        }
        const drawn = poster ? await decode(poster, 0, `${id}#poster`) : null;
        if (drawn) { FileData.keepPicture(`${id}#still`, 0, drawn); if (!gone) setStill(drawn); return; }
        if (file.size <= 0 || file.size > BIG_FILE) return;
        const bytes = await FileData.fetch(app, station, sessionKey, file, false).await();
        const path = await FileData.onDisk(id, file.name, bytes);
        const frame = await frameOf(path.uri, 0);
        if (gone) return;
        if (frame === null) setFailed(true);
        else { FileData.keepPicture(`${id}#still`, 0, frame); setStill(frame); }
      } catch (e) {
        if (!gone && e instanceof CoreError) setFailed(true);
      }
    })();
    return () => { gone = true; };
  }, [id]);
  const thumb = FileViewers.id(station, sessionKey, file.path);
  const frames = useWatched(FileViewers.frames);
  // Thick enough for the play mark and the name along the bottom.
  const box = imageBox(file, 96);
  const left = frames.get(thumb)?.picture ?? still;
  const leftRef = useRef(left);
  leftRef.current = left;
  const viewer = useViewerThumb(thumb, IMAGE_RADIUS, box.fit != null, true, () => leftRef.current);
  return (
    <>
      <ForgetThumb id={thumb} />
      <MediaBox box={box} viewer={viewer} background={failed ? C.chip : "#000000"} enabled onClick={onOpen}>
        {failed ? (
          <View style={[StyleSheet.absoluteFill, { paddingBottom: 30, alignItems: "center", justifyContent: "center", gap: 8 }]}>
            <Icon icon={Icons.Read} size={24} color={C.muted} />
            <T size={13} color={C.muted}>{t("android-chat.file.noPreview")}</T>
            <T size={11} color={C.muted}>{fileSize(file.size)}</T>
          </View>
        ) : (
          <>
            {/* The frame the viewer was left at, once it has been closed back into here; else the first. */}
            {left ? <Image source={{ uri: left.uri }} accessibilityLabel={file.name} resizeMode={box.fit != null ? "contain" : "cover"} style={StyleSheet.absoluteFill} /> : null}
            {/* The web's "▶" at 20px: a solid triangle. */}
            <View style={{ position: "absolute", left: 0, right: 0, top: 0, bottom: 0, alignItems: "center", justifyContent: "center" }} pointerEvents="none">
              <View style={{ width: 40, height: 40, borderRadius: 20, backgroundColor: withAlpha("#000000", 0.65), alignItems: "center", justifyContent: "center" }}>
                <Svg width={12} height={14} style={{ marginLeft: 2 }}>
                  <Path d="M0 0 L12 7 L0 14 Z" fill="#FFFFFF" />
                </Svg>
              </View>
            </View>
          </>
        )}
        <T
          size={12}
          numberOfLines={1}
          color={failed ? C.ink : "#FFFFFF"}
          // Centred, as in the web's button.
          align="center"
          style={[{ position: "absolute", left: 0, right: 0, bottom: 0 }, failed ? { paddingHorizontal: 12, paddingVertical: 8 } : { backgroundColor: withAlpha("#000000", 0.65), paddingHorizontal: 8, paddingVertical: 6 }]}
        >
          {file.name}
        </T>
      </MediaBox>
    </>
  );
}

/** What puts a file in the phone's Downloads (MediaStore), and installs an APK: the app's own native module. */
interface FilesNative { saveToDownloads(uri: string, name: string, type: string | null): Promise<boolean> }
// NATIVE: a module "StillfailFiles" with saveToDownloads(uri, name, type): the file at `uri` inserted into
// MediaStore.Downloads under `name` (its MIME type when known), as ChatFiles.kt's download does; true once written.
const filesNative = requireOptionalNativeModule<FilesNative>("StillfailFiles");

/**
 * Puts a file in the phone's Downloads: bytes from memory (written to the cache first), or a file on the phone's disk
 * (a big one, never read into memory). `type`: its MIME type, else its name's.
 */
export async function download(name: string, what: Uint8Array | File, type: string | null = null): Promise<boolean> {
  try {
    let from: File;
    if (what instanceof Uint8Array) {
      from = new File(cacheDir("downloads"), `${hashOf(name + Date.now())}-${name.replace(/[\u0000-\u001f/]/g, "_")}`);
      from.create();
      from.write(what);
    } else from = what;
    const known = type ?? kindOf(name).type;
    const ok = (await filesNative?.saveToDownloads(from.uri, name, known !== "application/octet-stream" ? known : null)) ?? false;
    if (what instanceof Uint8Array && from.exists) from.delete();
    return ok;
  } catch {
    return false;
  }
}

/**
 * A file as a card: its kind's mark, its name, and its size (or what it is doing: uploading, failed); `onRemove`
 * takes it out of a draft, `onClick` opens it. `shape`: its Smooth corners.
 */
export function FileCard({ name, size, note = null, busy = false, onRemove = null, shape = 8, onClick = null }: {
  name: string; size: number; note?: string | null; busy?: boolean; onRemove?: (() => void) | null;
  shape?: number | [number, number, number, number]; onClick?: (() => void) | null;
}) {
  const C = useC();
  const ink = chatInk();
  return (
    // The wide screen's neutral ground (web toast.css.ts → fileCard: --neutral-bg), a cool grey, not the page's warm chip.
    <Smooth radius={shape} style={{ width: 236, backgroundColor: ink.neutral }}>
      <Pressable disabled={!onClick} onPress={onClick ?? undefined} android_ripple={onClick ? ripple(C.ink) : undefined}
        style={{ flexDirection: "row", alignItems: "center", gap: 10, paddingHorizontal: 10, paddingVertical: 8 }}>
        {busy ? <Spinner /> : <Icon icon={Icons.Read} size={16} color={C.muted} />}
        <View style={{ flex: 1, minWidth: 0 }}>
          <T size={15} line={20} color={C.ink} numberOfLines={1}>{name}</T>
          {/* Digits all one width: a percentage counting up keeps its place (uploadingText). */}
          <T size={11} line={16} color={note !== null && !busy ? C.red : C.muted} style={{ fontVariant: ["tabular-nums"] }}>{note ?? fileSize(size)}</T>
        </View>
        {onRemove ? (
          <Pressable onPress={onRemove} android_ripple={ripple(C.ink)} style={{ width: 22, height: 22, borderRadius: 11, overflow: "hidden", backgroundColor: withAlpha(C.ink, 0.06), alignItems: "center", justifyContent: "center" }}>
            <Icon icon={Icons.Close} size={12} color={C.muted} />
          </Pressable>
        ) : null}
      </Pressable>
    </Smooth>
  );
}

export type { Gallery };
