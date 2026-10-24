// A file sent in a chat, opened over the page: images to zoom and pan,
// video and audio to play, PDFs drawn by pdf.js, text and code
// highlighted, Markdown rendered, CSV as a table, HTML in a sandbox. Anything
// else says it cannot be shown and offers the download.
import { Dialog as RDialog } from "radix-ui";
import { createContext, type ComponentType, useCallback, useContext, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode, type RefObject } from "react";
import { BIG_FILE, useApi, type Api, type Attachment, type FileProgress } from "./api.ts";
import { useTopic, useTopicSelect } from "./core/react.ts";
import { useNarrow } from "./mobile/narrow.ts";
import { DownloadRing, useBarOnScroll, ViewerBar, ViewerDownload } from "@stillfail/ui/viewer/ViewerBar.tsx";
import type { ChatView, DownloadShown, DriveEntry, ImageNear } from "./core/shapes.ts";
import { cancelDownload, saveBlob, startDownload, useDownload } from "./chatDownloads.ts";
import { Check, ChevronLeft, ChevronRight, Close, Copy, Download, File as FileMark, Minus, Plus } from "@stillfail/ui/icons.tsx";
import { Prose } from "./Prose.tsx";
import { FrameHost, isFragment, vizDocument } from "./Viz.tsx";
import { fileLink } from "./Prose.css.ts";
import { useStation } from "./station.tsx";
import { Segmented, Tip, Progress, Spinner, WaitLine } from "./ui.tsx";
import { useImageMarks } from "./annotate/ImageMarks.tsx";
import { useBackClose } from "@stillfail/ui/backClose.ts";
import { thumbId, viewerFlight } from "./viewerFlight.ts";
import { asPng, standIn } from "./wholeImages.ts";
import { failure, useToast } from "@stillfail/ui/toast.tsx";
import { animate, type AnimationPlaybackControls } from "@stillfail/ui/motion.ts";
import type { PDFDocumentLoadingTask, PDFDocumentProxy, RenderTask } from "pdfjs-dist";
import * as css2 from "./FilePreview.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import { t } from "./i18n.ts";
import { fileSize } from "@stillfail/ui/fileSize.ts";
import * as pageCss from "@stillfail/ui/styles/page.css.ts";

export { fileSize };
import { REST_MS, TAP_REST_MS } from "@stillfail/ui/viewer/rest.ts";
import { blobFile } from "@stillfail/ui/viewer/file.ts";
import { MAX_SCALE, useZoom, type Swipe } from "@stillfail/ui/viewer/zoom.ts";
import type { Reader as ReaderOf } from "@stillfail/ui/viewer/Reader.tsx";
import type { Player as PlayerOf } from "@stillfail/ui/viewer/Player.tsx";


// ── what a file is ─────────────────────────────────────────────────────

export type PreviewKind = "image" | "video" | "audio" | "pdf" | "markdown" | "csv" | "html" | "code" | "text";

const MEDIA: Record<string, [PreviewKind, string]> = {
  png: ["image", "image/png"], jpg: ["image", "image/jpeg"], jpeg: ["image", "image/jpeg"], gif: ["image", "image/gif"], webp: ["image", "image/webp"],
  svg: ["image", "image/svg+xml"], avif: ["image", "image/avif"], bmp: ["image", "image/bmp"], ico: ["image", "image/x-icon"],
  mp4: ["video", "video/mp4"], m4v: ["video", "video/mp4"], webm: ["video", "video/webm"], mov: ["video", "video/quicktime"], ogv: ["video", "video/ogg"],
  mp3: ["audio", "audio/mpeg"], m4a: ["audio", "audio/mp4"], aac: ["audio", "audio/aac"], wav: ["audio", "audio/wav"], ogg: ["audio", "audio/ogg"], oga: ["audio", "audio/ogg"], opus: ["audio", "audio/ogg"], flac: ["audio", "audio/flac"],
  pdf: ["pdf", "application/pdf"],
  md: ["markdown", "text/markdown"], markdown: ["markdown", "text/markdown"],
  csv: ["csv", "text/csv"], tsv: ["csv", "text/tab-separated-values"],
  html: ["html", "text/html"], htm: ["html", "text/html"],
};

/** Extensions Shiki knows by another name; the rest are tried as they are. */
const LANGUAGE: Record<string, string> = {
  mjs: "js", cjs: "js", mts: "ts", cts: "ts", h: "c", hh: "cpp", hpp: "cpp", cc: "cpp", cxx: "cpp", kts: "kotlin", yml: "yaml",
  zsh: "bash", sh: "bash", patch: "diff", htm: "html", conf: "ini", cfg: "ini", env: "dotenv", gradle: "groovy", plist: "xml", svg: "xml",
};
const PLAIN = new Set(["txt", "text", "log", "out", "err", "lock"]);
const NAMED: Record<string, string> = { dockerfile: "docker", makefile: "make", "cmakelists.txt": "cmake" };
const CODE = new Set(["ts", "tsx", "js", "jsx", "json", "jsonc", "json5", "py", "rs", "go", "java", "kt", "swift", "c", "cpp", "cs", "rb", "php", "bash", "fish", "ps1",
  "yaml", "toml", "xml", "sql", "css", "scss", "less", "html", "vue", "svelte", "lua", "dart", "diff", "ini", "dotenv", "groovy", "scala", "r", "pl", "ex", "exs",
  "erl", "hs", "ml", "clj", "zig", "nim", "proto", "graphql", "tex", "vim", "nix", "tf", "hcl", "docker", "make", "cmake", "asm", "wasm", "sol", "prisma", "astro"]);

export interface Kind { kind: PreviewKind | null; type: string; language?: string }

/** What a file shows as, by its name; `kind` null: look at its bytes to know. */
export function kindOf(name: string): Kind {
  const lower = name.toLowerCase();
  const named = NAMED[lower];
  if (named) return { kind: "code", type: "text/plain", language: named };
  const dot = lower.lastIndexOf(".");
  const ext = dot > 0 ? lower.slice(dot + 1) : "";
  const media = MEDIA[ext];
  if (media) return { kind: media[0], type: media[1], ...(media[0] === "html" ? { language: "html" } : {}) };
  if (PLAIN.has(ext)) return { kind: "text", type: "text/plain" };
  const language = LANGUAGE[ext] ?? ext;
  if (CODE.has(language)) return { kind: "code", type: "text/plain", language };
  return { kind: null, type: "application/octet-stream" };
}

export const isImage = (name: string) => kindOf(name).kind === "image";

// ── fetching ───────────────────────────────────────────────────────────

/** The name the station keeps a file by (the last part of its path), as its calls take it. */
export const storedName = (a: Attachment) => a.path.split("/").at(-1)!;

// Files sent never change: each is fetched once per page, and the most recent are kept for a chat opened again.
const blobs = new Map<string, Promise<Blob>>();
const KEEP_BLOBS = 100;

/**
 * Each file's blob once here, and the one URL every look at it draws from (`users` of it now): one drawn again (its
 * row made anew as a chat is opened again or scrolled back to) is the same picture, already decoded, from its first
 * frame, not a placeholder until a new URL loads. Kept as many as the blobs; one in use is not let go.
 */
const urls = new Map<string, { blob: Blob; url: string; users: number; unstand: (() => void) | null }>();

/** The URL of `id`'s blob (made the first time), taken by one more user; `whole`: the image a thumbnail stands in for. */
function takeUrl(id: string, blob: Blob, whole: (() => Promise<Blob>) | null): string {
  let kept = urls.get(id);
  if (kept?.blob !== blob) {
    if (kept) letGo(id, kept);
    const url = URL.createObjectURL(blob);
    kept = { blob, url, users: 0, unstand: whole ? standIn(url, whole) : null };
  }
  urls.delete(id);
  urls.set(id, kept);
  kept.users++;
  for (const [other, k] of urls) {
    if (urls.size <= KEEP_BLOBS) break;
    if (k.users === 0) letGo(other, k);
  }
  return kept.url;
}

function letGo(id: string, kept: { url: string; unstand: (() => void) | null }) {
  urls.delete(id);
  kept.unstand?.();
  URL.revokeObjectURL(kept.url);
}

/** One user of `url` gone: it stays for the next look (as long as it is among the kept). */
function dropUrl(id: string, url: string) {
  const kept = urls.get(id);
  if (kept?.url === url) kept.users--;
}

/** Whether `file` is here already, to be drawn at once (as its thumbnail, `thumb`). */
export function fileHere(station: string, sessionKey: string, file: Attachment, thumb: boolean): boolean {
  return urls.has(fileId(station, sessionKey, file, thumb));
}

// How far each whole file on its way has come, and who is watching it.
const coming = new Map<string, { got: FileProgress | null; watchers: Set<(got: FileProgress) => void> }>();

const fileId = (station: string, sessionKey: string, file: Attachment, thumb: boolean) => `${station}/${sessionKey}/${file.path}${thumb ? "#thumb" : ""}`;

/**
 * Where the files a preview shows come from when they are not a chat's (a station's drive, drive/; a published chat,
 * share/): `file` reads one whole (`thumb`: as a list would show it; the same is fine), saying how far it has come.
 * `save`, if given, is how one is downloaded (else a link to its blob: the share page never has one opened as a page).
 */
export interface FileSourceOf {
  file(sessionKey: string, file: Attachment, thumb: boolean, onProgress?: (got: FileProgress) => void): Promise<Blob>;
  save?(file: Attachment, blob: Blob): void;
  /** Its first `length` bytes, where the source can read a part (else the whole is fetched to tell what it is). */
  head?(sessionKey: string, file: Attachment, length: number): Promise<Blob>;
}
export const FileSource = createContext<FileSourceOf | null>(null);

function fetchFile(api: Api, station: string, sessionKey: string, file: Attachment, thumb = false, source: FileSourceOf | null = null): Promise<Blob> {
  const id = fileId(station, sessionKey, file, thumb);
  let blob = blobs.get(id);
  if (!blob) {
    // Typed by its name, so the browser plays and shows it whatever the station called it (a thumbnail is typed by the
    // station: it may be a JPEG of a PNG).
    const { type } = kindOf(file.name);
    // A whole file may be big: how far it has come is kept for whoever shows it (thumbnails are small).
    const on = thumb ? null : { got: null as FileProgress | null, watchers: new Set<(got: FileProgress) => void>() };
    if (on) coming.set(id, on);
    const progress = on ? (got: FileProgress) => { on.got = got; on.watchers.forEach((w) => w(got)); } : undefined;
    blob = (source ? source.file(sessionKey, file, thumb, progress) : api.file(sessionKey, storedName(file), thumb, progress, file.size))
      .then((b) => (!thumb && type !== "application/octet-stream" && b.type !== type ? b.slice(0, b.size, type) : b));
    if (on) void blob.finally(() => coming.delete(id)).catch(() => {});
    // A failure is not kept: the next look tries again.
    blob.catch(() => blobs.delete(id));
    blobs.set(id, blob);
    if (blobs.size > KEEP_BLOBS) blobs.delete(blobs.keys().next().value!);
  }
  return blob;
}

type Loaded = { state: "loading"; got?: FileProgress | null } | { state: "error"; message: string } | { state: "ready"; blob: Blob; url: string };

/** A file as a blob and its URL, fetched from the station once and kept; `again`: asked again after it failed. */
function useFile(sessionKey: string, file: Attachment, enabled: boolean, thumb = false, again = 0): Loaded {
  const api = useApi();
  const station = useStation();
  const source = useContext(FileSource);
  // Here already: ready from the first frame.
  const [loaded, setLoaded] = useState<Loaded>(() => {
    const kept = enabled ? urls.get(fileId(station.address, sessionKey, file, thumb)) : undefined;
    return kept ? { state: "ready", blob: kept.blob, url: kept.url } : { state: "loading" };
  });
  useEffect(() => {
    if (!enabled) return;
    const id = fileId(station.address, sessionKey, file, thumb);
    let u: string | null = null;
    let current = true;
    // A thumbnail stands in for the image: copied in the desktop app, the image itself is (wholeImages.ts).
    const whole = thumb ? () => fetchFile(api, station.address, sessionKey, file, false, source) : null;
    const take = (blob: Blob) => {
      u = takeUrl(id, blob, whole);
      const url = u;
      setLoaded((l) => (l.state === "ready" && l.url === url ? l : { state: "ready", blob, url }));
    };
    const kept = urls.get(id);
    if (kept) {
      take(kept.blob);
      return () => { if (u) dropUrl(id, u); };
    }
    setLoaded({ state: "loading" });
    const promise = fetchFile(api, station.address, sessionKey, file, thumb, source);
    const on = coming.get(id);
    const watch = (got: FileProgress) => { if (current) setLoaded((l) => (l.state === "loading" ? { state: "loading", got } : l)); };
    if (on) {
      on.watchers.add(watch);
      if (on.got) watch(on.got);
    }
    promise.then((blob) => { if (current) take(blob); }, (error: unknown) => {
      if (current) setLoaded({ state: "error", message: error instanceof Error ? error.message : String(error) });
    });
    return () => {
      current = false;
      on?.watchers.delete(watch);
      if (u) dropUrl(id, u);
    };
  }, [api, station.address, sessionKey, file.path, enabled, thumb, source, again]);
  return loaded;
}

/** How many of a file's first bytes tell whether it is text. */
const SNIFF_BYTES = 8192;

/**
 * What a file of no known kind is, by its first bytes only: text, or not (`binary`; also from a station from before
 * parts, which cannot say); `whole` where its source reads no parts (the whole of it is looked at once it comes);
 * null while it is asked.
 */
function useHead(sessionKey: string, file: Attachment, enabled: boolean): "text" | "binary" | "whole" | null {
  const api = useApi();
  const station = useStation();
  const source = useContext(FileSource);
  const [head, setHead] = useState<{ path: string; is: "text" | "binary" | "whole" } | null>(null);
  useEffect(() => {
    if (!enabled) return;
    const kept = blobs.get(fileId(station.address, sessionKey, file, false));
    const read = kept ?? (source ? source.head?.(sessionKey, file, SNIFF_BYTES) : api.fileHead(sessionKey, storedName(file), SNIFF_BYTES));
    if (!read) { setHead({ path: file.path, is: "whole" }); return; }
    let live = true;
    void read.then((blob) => looksLikeText(blob), () => false).then((text) => { if (live) setHead({ path: file.path, is: text ? "text" : "binary" }); });
    return () => { live = false; };
  }, [api, station.address, sessionKey, file.path, enabled, source]); // eslint-disable-line react-hooks/exhaustive-deps
  return enabled && head?.path === file.path ? head.is : null;
}

/** A text file's content, fetched from the station once. */
export function useFileText(sessionKey: string, file: Attachment): { state: "loading" } | { state: "error" } | { state: "ready"; text: string } {
  const loaded = useFile(sessionKey, file, true);
  const [text, setText] = useState<{ blob: Blob; text: string } | null>(null);
  const blob = loaded.state === "ready" ? loaded.blob : null;
  useEffect(() => {
    if (!blob) return;
    let current = true;
    void blob.text().then((t) => { if (current) setText({ blob, text: t }); });
    return () => { current = false; };
  }, [blob]);
  if (loaded.state === "error") return { state: "error" };
  return text && text.blob === blob ? { state: "ready", text: text.text } : { state: "loading" };
}

/** Videos' posters on their way or come, by file: null when the station has none. */
const posters = new Map<string, Promise<Blob | null>>();

/**
 * A video's still for a chat: its poster as the station makes it; where it has none, the video itself as long as it is
 * small (BIG_FILE: its first frame is drawn from it), else none (the chat shows it without, rather than fetch it whole).
 * `url` is a picture's (`poster`) or the video's.
 */
export function useVideoStill(sessionKey: string, file: Attachment, enabled: boolean): { url: string | null; poster: boolean; failed: boolean } {
  const api = useApi();
  const station = useStation();
  const [poster, setPoster] = useState<{ url: string } | "none" | null>(null);
  useEffect(() => {
    if (!enabled) return;
    const id = fileId(station.address, sessionKey, file, false);
    let p = posters.get(id);
    if (!p) {
      p = api.poster(sessionKey, storedName(file)).catch(() => null);
      posters.set(id, p);
    }
    let u: string | null = null;
    let current = true;
    void p.then((blob) => {
      if (!current) return;
      if (blob) setPoster({ url: (u = URL.createObjectURL(blob)) });
      else setPoster("none");
    });
    return () => { current = false; if (u) URL.revokeObjectURL(u); };
  }, [api, station.address, sessionKey, file.path, enabled]); // eslint-disable-line react-hooks/exhaustive-deps
  const small = file.size > 0 && file.size <= BIG_FILE;
  const video = useFileShown(sessionKey, file, enabled && poster === "none" && small, false);
  if (poster !== null && poster !== "none") return { url: poster.url, poster: true, failed: false };
  return { url: video.url, poster: false, failed: video.failed };
}

/** A chat attachment as a blob URL. Images use thumbnails; video stills need the original file. */
export function useFileUrl(sessionKey: string, file: Attachment, enabled: boolean, thumb = true): string | null {
  return useFileShown(sessionKey, file, enabled, thumb).url;
}

/** As useFileUrl, and whether fetching it failed (a chat's image then says so rather than waiting on). */
export function useFileShown(sessionKey: string, file: Attachment, enabled: boolean, thumb = true): { url: string | null; failed: boolean } {
  const loaded = useFile(sessionKey, file, enabled, thumb);
  return { url: loaded.state === "ready" ? loaded.url : null, failed: loaded.state === "error" };
}

/**
 * Whether an element has come near the screen (and stays so once it has): a chat's images are fetched only then, not
 * all as it opens (a chat of screenshots is megabytes, and taking them in held up the page's first frames). Their
 * boxes are sized beforehand, so nothing moves when they come.
 */
export function useNear(ref: RefObject<HTMLElement | null>, watch: boolean): boolean {
  const [near, setNear] = useState(false);
  useEffect(() => {
    const el = ref.current;
    if (!watch || near || !el) return;
    // scrollMargin reaches past the chat list's own edges (rootMargin only past the window's).
    const observer = new IntersectionObserver(([e]) => { if (e?.isIntersecting) setNear(true); }, { rootMargin: "600px 0px", scrollMargin: "600px 0px" } as IntersectionObserverInit);
    observer.observe(el);
    return () => observer.disconnect();
  }, [ref, watch, near]);
  return near;
}

// ── the viewer ─────────────────────────────────────────────────────────

/** A file and the session that keeps it. */
export interface Shown { sessionKey: string; file: Attachment }

/**
 * What an image opened in a preview steps through (arrows, ← →, a swipe): the images of the chat it is opened from (as
 * its `chat` topic names it), of which the core tells those beside the one open (`imageNear`), not the chat's every
 * image; or a folder's (Drive.tsx), read when needed.
 */
export type GalleryOf = { chat: { thread: number } | { session: string } } | { list: () => Shown[] };
export const Gallery = createContext<GalleryOf | null>(null);

/**
 * The reader and the player a text and a sound open in (@stillfail/ui viewer/Reader.tsx, viewer/Player.tsx), as the
 * app has them: told here by the app as it starts (viewer/whole.ts, with what they ask of the page), not imported, so
 * a page that tells none (a published chat's, share/) keeps its own plain viewers.
 */
type Whole = { Reader: typeof ReaderOf; Player: typeof PlayerOf };
let whole: Whole | null = null;
export const setWholeViewers = (viewers: Whole) => { whole = viewers; };

/** Where closing a preview goes back to, by name (a drive's folder: mobile/Drive.tsx DrivePreview); a chat's file's is
 * its chat's title, else 关闭. */
export const PreviewBack = createContext<string | null>(null);

/** A file already on this device (one in the draft, not sent yet): shown as it is, not fetched from the station. */
export interface LocalFile { blob: Blob; url: string }

/** A file over the whole window, a bar with its name and tools on top; Esc closes it. */
export function FilePreview({ open, onClose, sessionKey, file, local }: { open: boolean; onClose(): void; sessionKey: string; file: Attachment; local?: LocalFile | undefined }) {
  // Closed by hand (its button, Esc, back), it goes back into the chat's thumbnail first (viewerFlight.ts).
  const closing = useRef<((done: () => void) => void) | null>(null);
  const close = () => { const c = closing.current; if (c) c(onClose); else onClose(); };
  useBackClose(open, close);
  return (
    <RDialog.Root open={open} onOpenChange={(o) => { if (!o) close(); }}>
      <RDialog.Portal>
        {open && <Viewer onClose={close} closing={closing} sessionKey={sessionKey} file={file} local={local} />}
      </RDialog.Portal>
    </RDialog.Root>
  );
}

/** Words in a message that name one of its files: a link that opens it (just the words when no session can show it). */
export function FileLink({ sessionKey, file, children }: { sessionKey: string | null; file: Attachment; children: ReactNode }) {
  const [open, setOpen] = useState(false);
  if (sessionKey === null) return <>{children}</>;
  return (
    <>
      <button type="button" className={fileLink} onClick={() => setOpen(true)}>{children}</button>
      <FilePreview open={open} onClose={() => setOpen(false)} sessionKey={sessionKey} file={file} />
    </>
  );
}

function Viewer({ onClose, closing, local, ...opened }: { onClose(): void; closing: RefObject<((done: () => void) => void) | null>; sessionKey: string; file: Attachment; local?: LocalFile | undefined }) {
  const [{ sessionKey, file }, setShown] = useState<Shown>(opened);
  const gallery = useContext(Gallery);
  const api = useApi();
  const station = useStation();
  // One in the draft is not among the chat's: it shows alone.
  const steps = isImage(file.name) && !local ? gallery : null;
  const chat = steps && "chat" in steps ? steps.chat : null;
  const told = useTopic<ImageNear>(chat ? { topic: "imageNear", station: station.address, ...chat, path: file.path } : null).value;
  // Each through the session that keeps it (the core says which, `owner`).
  const shown = (f: Attachment | undefined): Shown | undefined => (f?.owner ? { sessionKey: f.owner, file: f } : undefined);
  const list = steps && "list" in steps ? steps.list() : [];
  const listAt = list.findIndex((i) => i.file.path === file.path);
  const { before, after, at, count } = chat
    ? { before: shown(told?.before), after: shown(told?.after), at: told?.index ?? -1, count: told?.count ?? 0 }
    : { before: listAt > 0 ? list[listAt - 1] : undefined, after: listAt >= 0 ? list[listAt + 1] : undefined, at: listAt, count: list.length };
  // The one shown and those beside it move as one strip (GAP apart): a step slides it out to one side and the next in
  // from the other, a swipe carries it under the finger first. The one going is a copy: the real one is the next already.
  const slide = useRef<HTMLDivElement>(null);
  const sliding = useRef<{ runs: AnimationPlaybackControls[]; copy: HTMLElement | null }>({ runs: [], copy: null });
  const arriving = useRef<{ dir: -1 | 1; from: number; v: number } | null>(null);
  const near = useRef({ before, after });
  near.current = { before, after };
  const settle = useCallback(() => {
    const el = slide.current;
    // Where it is now, as the motion left it.
    const t = el ? getComputedStyle(el).transform : "none";
    const x = t === "none" ? 0 : new DOMMatrixReadOnly(t).m41;
    for (const r of sliding.current.runs) r.stop();
    sliding.current.copy?.remove();
    sliding.current = { runs: [], copy: null };
    if (el) el.style.transform = x ? `translateX(${x}px)` : "";
    return x;
  }, []);
  const run = useCallback((from: number, to: number, v: number, draw: (x: number) => void) => {
    draw(from);
    const r = animate(from, to, { ...SLIDE, velocity: v * 1000, onUpdate: draw });
    sliding.current.runs.push(r);
    void r.finished.then(() => {
      if (!sliding.current.runs.includes(r)) return;
      settle();
      if (slide.current) slide.current.style.transform = "";
    }, () => {});
  }, [settle]);
  /** Back to its place, from where a swipe left it (at `v` px/ms). */
  const back = useCallback((v = 0) => {
    const from = settle();
    const el = slide.current;
    if (el && from) run(from, 0, v, (x) => { el.style.transform = `translateX(${x}px)`; });
    else if (el) el.style.transform = "";
  }, [settle, run]);
  /** To the one before (-1) or after (1), going on from where a swipe left it (at `v` px/ms). */
  const go = useCallback((dir: -1 | 1, v = 0) => {
    const to = dir < 0 ? near.current.before : near.current.after;
    if (!to) return back(v);
    const from = settle();
    const el = slide.current;
    if (el) {
      const copy = el.cloneNode(true) as HTMLElement;
      // Only drawn: what finds the picture and the bars finds the real ones.
      for (const n of copy.querySelectorAll("[data-peek]")) n.remove();
      for (const n of copy.querySelectorAll("[data-viewer-picture], [data-floats]")) { n.removeAttribute("data-viewer-picture"); n.removeAttribute("data-floats"); }
      copy.inert = true;
      copy.setAttribute("aria-hidden", "true");
      el.after(copy);
      sliding.current.copy = copy;
      arriving.current = { dir, from, v };
    }
    setShown(to);
  }, [settle, back]);
  useLayoutEffect(() => {
    const a = arriving.current, el = slide.current, copy = sliding.current.copy;
    arriving.current = null;
    if (!a || !el) return;
    const width = el.clientWidth + GAP;
    run(a.from, -a.dir * width, a.v, (x) => {
      if (copy) copy.style.transform = `translateX(${x}px)`;
      el.style.transform = `translateX(${x + a.dir * width}px)`;
    });
  }, [file.path, run]);
  useEffect(() => () => { settle(); }, [settle]);
  const swipe = useMemo<Swipe>(() => ({
    drag(dx) {
      const el = slide.current;
      if (!el) return;
      if (sliding.current.runs.length) settle();
      // Past the first or the last, it gives only a little.
      const none = dx > 0 ? !near.current.before : !near.current.after;
      el.style.transform = `translateX(${none ? dx / 3 : dx}px)`;
    },
    end(dx, vx) {
      const dir = dx > 0 ? -1 : 1;
      const far = Math.abs(dx) > Math.min(80, (slide.current?.clientWidth ?? 0) / 5);
      const flung = Math.abs(vx) > 0.3 && Math.sign(vx) === Math.sign(dx) && Math.abs(dx) > 10;
      if (dx && (far || flung)) go(dir, vx);
      else back(vx);
    },
  }), [settle, go, back]);
  // An image being marked: its bar stays, and it stays the one shown.
  const [marking, setMarking] = useState(false);
  // The neighbours are fetched ahead, so a step shows the next one at once.
  const source = useContext(FileSource);
  useEffect(() => {
    for (const n of [before, after]) if (n) fetchFile(api, station.address, n.sessionKey, n.file, false, source).catch(() => {});
  }, [api, station.address, before?.file.path, after?.file.path, source]);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey || marking) return;
      if (e.key === "ArrowLeft" && before) go(-1);
      else if (e.key === "ArrowRight" && after) go(1);
      else return;
      e.preventDefault();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [before, after, go, marking]);
  // Opened out of the chat's thumbnail of it, closed back into the thumbnail of the one it shows then.
  const content = useRef<HTMLDivElement>(null);
  const [flight] = useState(() => viewerFlight(() => content.current, { stage: css2.fpStage, steps: css2.fpStep }));
  const showing = useRef(file.path);
  showing.current = thumbId(station.address, sessionKey, file.path);
  useLayoutEffect(() => {
    flight.open(showing.current);
    closing.current = (done) => flight.close(showing.current, done);
    return () => { closing.current = null; flight.stop(); };
  }, [flight, closing]);
  const known = kindOf(file.name);
  // A file of no known kind is not fetched to tell what it is: its first bytes are. One that is not text is told of
  // (its name, size and kind) and fetched only when asked to be downloaded.
  const front = useHead(sessionKey, file, known.kind === null && !local);
  const toldOf = !local && known.kind === null && front === "binary";
  // A chat's not here whole yet (told of, or still coming to be shown): downloaded by the core (chatDownloads.ts), on
  // as the preview closes; how far it has come said here.
  const byCore = !local && !source;
  const download = useDownload(station.address, byCore ? sessionKey : null, storedName(file));
  const [asked, setAsked] = useState<{ path: string; tries: number; save: boolean } | null>(null);
  const askedNow = asked?.path === file.path ? asked : null;
  const fetched = useFile(sessionKey, file, !local && (known.kind !== null || front === "text" || front === "whole" || askedNow !== null), false, askedNow?.tries ?? 0);
  const loaded: Loaded = local ? { state: "ready", ...local } : fetched;
  const save = (l: Extract<Loaded, { state: "ready" }>) => { if (source?.save) source.save(file, l.blob); else saveBlob(l.url, file.name); };
  // Asked for and come: downloaded.
  useEffect(() => {
    if (!askedNow?.save || loaded.state !== "ready") return;
    setAsked({ ...askedNow, save: false });
    save(loaded);
  }); // eslint-disable-line react-hooks/exhaustive-deps
  const ask = () => {
    if (loaded.state === "ready") save(loaded);
    else if (byCore) startDownload(station.address, sessionKey, storedName(file), file.size);
    else setAsked({ path: file.path, tries: (askedNow?.tries ?? 0) + (loaded.state === "error" ? 1 : 0), save: true });
  };
  // An image stands in as the chat showed it (its thumbnail, kept) while the whole of it comes.
  const thumb = useFileUrl(sessionKey, file, known.kind === "image" && loaded.state === "loading", true);
  const [sniffed, setSniffed] = useState<PreviewKind | "binary" | null>(null);
  const [controls, setControls] = useState<ReactNode>(null);
  const blob = loaded.state === "ready" ? loaded.blob : null;
  useEffect(() => {
    if (known.kind || !blob) return;
    let live = true;
    void looksLikeText(blob).then((text) => { if (live) setSniffed(text ? "text" : "binary"); });
    return () => { live = false; };
  }, [blob, known.kind]);
  const kind = known.kind ?? (front === "text" ? "text" : front === "binary" ? null : sniffed);
  // An image on its way: its thumbnail stands in, and how far the whole of it has come shows in the bar.
  const coming = known.kind === "image" && loaded.state === "loading" && thumb ? loaded.got : undefined;
  // The bar is as wide as what it holds, and once open it only grows: its buttons stay where they are to be clicked.
  const head = useRef<HTMLElement>(null);
  const widest = useRef(0);
  useLayoutEffect(() => {
    const el = head.current;
    if (!el) return;
    const w = el.getBoundingClientRect().width;
    if (w > widest.current) { widest.current = w; el.style.minWidth = `min(${w}px, 100% - 32px)`; }
  });
  // With a mouse on a wide screen, the bar every file opened has (viewer/ViewerBar.tsx), along the top and always there:
  // the way back named by where it goes. On a phone, the bar floats over the file.
  const docked = !useNarrow();
  const backTo = useContext(PreviewBack);
  const chatTitle = useTopicSelect<ChatView, string | null>(docked && !backTo && sessionKey && !sessionKey.startsWith("drive:") ? { topic: "chat", station: station.address, session: sessionKey } : null, (s) => s.value?.title ?? null);
  const backLabel = backTo ?? chatTitle ?? t("common.close");
  const barOnScroll = useBarOnScroll();
  // The bar floats over the file, and fades when the pointer leaves it or rests a while (not over it, not while it comes).
  const [awake, setAwake] = useState(true);
  const resting = useRef(0);
  const onBar = useRef(false);
  const tapAt = useRef<{ x: number; y: number } | null>(null);
  const wake = useCallback((ms = REST_MS) => {
    setAwake(true);
    clearTimeout(resting.current);
    resting.current = window.setTimeout(() => { if (!onBar.current) setAwake(false); }, ms);
  }, []);
  useEffect(() => { wake(); return () => clearTimeout(resting.current); }, [wake, file.path]);
  let body: ReactNode;
  if (toldOf) {
    const ext = file.name.includes(".") ? file.name.split(".").at(-1)!.toUpperCase() : "";
    body = <div className={css2.fpNote}>
      <FileMark size={44} className={css2.fpFactsMark} />
      <div className={css2.fpFactsName}>{file.name}</div>
      <div>{[fileSize(file.size), ext && ext.length <= 12 ? ext : ""].filter(Boolean).join(" · ")}</div>
      <div>{t("web-main.preview.unsupported")}</div>
      {download?.active ? <DownloadComing download={download} />
        : askedNow && loaded.state === "loading"
        ? (loaded.got ? <FileComing got={loaded.got} size={file.size} /> : <Spinner />)
        : <>
          {download?.state === "failed" && <div className={css2.fpFactsFailed}>{download.statusText}</div>}
          {loaded.state === "error" && <div className={css2.fpFactsFailed}>{t("web-main.preview.loadFailed", { error: loaded.message })}</div>}
          <button type="button" className={`${controlsCss.btn} ${controlsCss.btnPrimary}`} onClick={ask}><Download size={16} />{t("web-main.preview.download")}</button>
        </>}
    </div>;
  } else if (known.kind === "image" && (loaded.state === "ready" || (loaded.state === "loading" && thumb))) {
    body = <ImageViewer key={file.path} url={loaded.state === "ready" ? loaded.url : thumb!} file={file} setControls={setControls} swipe={swipe}
      waiting={loaded.state === "loading"} onMarking={setMarking} onClose={onClose} />;
  } else if (loaded.state === "loading" || (kind === null && loaded.state === "ready") || (known.kind === null && !local && front === null)) {
    body = <div className={css2.fpNote}>{loaded.state === "loading" && loaded.got ? <FileComing got={loaded.got} size={file.size} /> : <WaitLine text={t("common.opening")} />}</div>;
  }
  else if (loaded.state === "error") body = <div className={css2.fpNote}>{t("web-main.preview.loadFailed", { error: loaded.message })}</div>;
  else {
    const { url, blob } = loaded;
    switch (kind) {
      case "image": body = <ImageViewer key={file.path} url={url} file={file} setControls={setControls} swipe={swipe} onMarking={setMarking} onClose={onClose} />; break;
      case "video": body = <video className={css2.fpImage} src={url} controls autoPlay playsInline data-viewer-picture="" />; break;
      case "audio": body = <div className={css2.fpAudio}><span className={css2.fpAudioName}>{file.name}</span><audio src={url} controls autoPlay /></div>; break;
      case "pdf": body = <PdfViewer blob={blob} />; break;
      case "markdown": case "csv": case "html": case "code": case "text":
        body = <TextViewer blob={blob} kind={kind} language={known.language} name={file.name} setControls={setControls} onMove={wake} onEscape={onClose} />; break;
      default: body = <div className={css2.fpNote}>{t("web-main.preview.unsupported")}{source?.save
        ? <button type="button" className={controlsCss.btn} onClick={() => source.save?.(file, blob)}><Download size={16} />{t("web-main.preview.download")}</button>
        : <a className={controlsCss.btn} href={url} download={file.name}><Download size={16} />{t("web-main.preview.download")}</a>}</div>;
    }
  }
  // A text, a film and a song open in the reader and the player, as a station's file does (viewer/Reader.tsx,
  // viewer/Player.tsx), each with the same bar; here they read what this has fetched. The one player is made both to
  // watch and to look closely (a chat's recording of a screen: frame by frame, zoomed, a pixel's colour, a frame saved).
  const saveShown = useRef<(() => void) | undefined>(undefined);
  saveShown.current = loaded.state === "ready" ? () => save(loaded) : undefined;
  const shownFile = useMemo(() => blob && blobFile(blob, { name: file.name, size: file.size, type: blob.type, kind: kind ?? "" }, () => saveShown.current?.()), [blob, file.name, file.size, kind]);
  const Reader = whole?.Reader, Player = whole?.Player;
  const viewer = loaded.state !== "ready" || !shownFile ? null
    : (kind === "markdown" || kind === "text") && Reader
      ? <Reader key={file.path} file={shownFile} markdown={kind === "markdown"} backLabel={backLabel} onBack={onClose} />
      : (kind === "audio" || kind === "video") && Player
        ? <Player key={file.path} file={shownFile} backLabel={backLabel} onBack={onClose} />
        : null;
  if (viewer) {
    return (
      <RDialog.Content ref={content} className={css2.fp} data-kind={kind ?? undefined} data-zoom-root="" aria-describedby={undefined}
        onOpenAutoFocus={(e) => { e.preventDefault(); (e.currentTarget as HTMLElement | null)?.focus(); }}>
        <RDialog.Title className={css2.fpHiddenTitle}>{file.name}</RDialog.Title>
        {viewer}
      </RDialog.Content>
    );
  }
  return (
    <RDialog.Content ref={content} className={css2.fp} data-kind={kind ?? undefined} data-docked={docked || undefined} data-zoom-root="" aria-describedby={undefined} data-awake={awake || coming !== undefined || marking || undefined}
      // A mouse wakes the bars by moving; a finger has no hover, and a tap on the file shows or hides them.
      onPointerMove={(e) => { if (e.pointerType === "mouse") wake(); barOnScroll.onPointerMove(e); }}
      onScrollCapture={barOnScroll.onScroll}
      onPointerLeave={(e) => { if (e.pointerType !== "mouse") return; clearTimeout(resting.current); if (!onBar.current) setAwake(false); }}
      onPointerDown={(e) => { tapAt.current = { x: e.clientX, y: e.clientY }; }}
      onPointerUp={(e) => {
        const t = tapAt.current;
        if (e.pointerType === "mouse" || !t || Math.hypot(e.clientX - t.x, e.clientY - t.y) > 10 || (e.target as Element).closest("button, a, header")) return;
        if (awake) { clearTimeout(resting.current); setAwake(false); } else wake(TAP_REST_MS);
      }}
      // The page itself takes focus, not its first button: no ring on the close button for a tap or click.
      onOpenAutoFocus={(e) => { e.preventDefault(); (e.currentTarget as HTMLElement | null)?.focus(); }}>
      {docked ? (
        <ViewerBar back={{ label: backLabel, onClick: onClose }} title={file.path}
          onHeld={(on) => { onBar.current = on; if (on) { clearTimeout(resting.current); setAwake(true); } else wake(); }}
          // A picture: gone with the rest as the pointer rests (back as it moves); what is read down: as it is read down.
          hidden={kind === "image" ? !(awake || coming !== undefined || marking) : barOnScroll.hidden}
          name={<RDialog.Title asChild><span>{file.name}</span></RDialog.Title>}
          meta={`${count > 1 && at >= 0 ? `${at + 1} / ${count} · ` : ""}${fileSize(file.size)}${kind && KIND_LABEL[kind as PreviewKind] ? ` · ${kindLabel(kind as PreviewKind)}` : ""}`}
          tools={<>
            {coming !== undefined && <FileComing got={coming} size={file.size} inBar />}
            {controls}
            {kind === "image" && !marking && loaded.state === "ready" && <CopyImage key={file.path} image={loaded.blob} />}
            {/* What is here saved at once; a chat's not here whole (told of, or still coming) downloaded by the core, how far
                it has come in its place meanwhile. */}
            {!marking && (download?.active ? <ViewerDownload name={file.name} coming={download.progress} />
              : loaded.state === "ready" ? <ViewerDownload name={file.name} href={source?.save ? undefined : loaded.url} onSave={source?.save ? () => source.save?.(file, loaded.blob) : undefined} />
              : (toldOf || byCore) && <ViewerDownload name={file.name} onSave={ask} />)}
          </>} />
      ) : <header ref={head} className={css2.fpHead} data-floats
        onPointerEnter={(e) => { if (e.pointerType !== "mouse") return; onBar.current = true; clearTimeout(resting.current); setAwake(true); }}
        onPointerLeave={(e) => { if (e.pointerType !== "mouse") return; onBar.current = false; wake(); }}>
        <div className={css2.fpTitle}>
          <Tip label={file.path}><RDialog.Title className={css2.fpName}>{file.name}</RDialog.Title></Tip>
          <span className={css2.fpMeta}>{count > 1 && at >= 0 ? `${at + 1} / ${count} · ` : ""}{fileSize(file.size)}{kind && KIND_LABEL[kind as PreviewKind] ? ` · ${kindLabel(kind as PreviewKind)}` : ""}</span>
        </div>
        {coming !== undefined && <FileComing got={coming} size={file.size} inBar />}
        {controls}
        {kind === "image" && !marking && (loaded.state === "ready"
          ? <CopyImage key={file.path} image={loaded.blob} />
          : <span className={pageCss.iconBtn} aria-hidden="true" style={{ visibility: "hidden" }}><Copy size={18} /></span>)}
        {marking ? null : download?.active
          ? <Tip label={t("web-main.preview.download")}><button type="button" className={pageCss.iconBtn} disabled aria-label={t("web-main.preview.download")}><DownloadRing part={download.progress} /></button></Tip>
          : (toldOf || byCore) && loaded.state !== "ready"
          ? <Tip label={t("web-main.preview.download")}><button type="button" className={pageCss.iconBtn} onClick={ask} disabled={askedNow !== null && loaded.state === "loading"} aria-label={t("web-main.preview.download")}><Download size={18} /></button></Tip>
          : loaded.state === "ready"
          ? <Tip label={t("web-main.preview.download")}>{source?.save
            ? <button type="button" className={pageCss.iconBtn} onClick={() => source.save?.(file, loaded.blob)} aria-label={t("web-main.preview.download")}><Download size={18} /></button>
            : <a className={pageCss.iconBtn} href={loaded.url} download={file.name} aria-label={t("web-main.preview.download")}><Download size={18} /></a>}</Tip>
          // Its place kept until it comes.
          : <span className={pageCss.iconBtn} aria-hidden="true" style={{ visibility: "hidden" }}><Download size={18} /></span>}
        <Tip label={t("web-main.preview.closeKey")}><RDialog.Close className={pageCss.iconBtn} aria-label={t("common.close")}><Close size={18} /></RDialog.Close></Tip>
      </header>}
      <div className={css2.fpBody}>
        <div ref={slide} className={css2.fpSlide}>
          {body}
          {/* The ones beside it, out of sight until a swipe brings them in. */}
          {known.kind === "image" && !marking && before && <Peek key={before.file.path} shown={before} side={-1} />}
          {known.kind === "image" && !marking && after && <Peek key={after.file.path} shown={after} side={1} />}
        </div>
        {count > 1 && at >= 0 && !marking && <>
          <Tip label={t("web-main.preview.prevKey")}><button type="button" className={css2.fpStep} data-side="before" aria-label={t("web-main.preview.prev")} disabled={!before} onClick={() => go(-1)}><ChevronLeft size={22} /></button></Tip>
          <Tip label={t("web-main.preview.nextKey")}><button type="button" className={css2.fpStep} data-side="after" aria-label={t("web-main.preview.next")} disabled={!after} onClick={() => go(1)}><ChevronRight size={22} /></button></Tip>
        </>}
      </div>
    </RDialog.Content>
  );
}

/** The bar's button that puts the image shown (whole, as a PNG) on the clipboard. */
function CopyImage({ image }: { image: Blob }) {
  const [copied, setCopied] = useState(false);
  const toast = useToast();
  const label = copied ? t("common.copied") : t("common.copy");
  const copy = () => {
    // The PNG is handed over still to come: the clipboard is written while the click still counts as the person's (Safari).
    void navigator.clipboard.write([new ClipboardItem({ "image/png": asPng(image) })])
      .then(() => { setCopied(true); setTimeout(() => setCopied(false), 1600); }, (e: unknown) => toast(t("web-main.copyFailed", { error: failure(e) })));
  };
  return <Tip label={label}><button type="button" className={pageCss.iconBtn} aria-label={label} onClick={copy}>{copied ? <Check size={18} /> : <Copy size={18} />}</button></Tip>;
}

/** Text, when its first bytes decode as UTF-8 with no NULs. */
async function looksLikeText(blob: Blob): Promise<boolean> {
  const head = new Uint8Array(await blob.slice(0, 8192).arrayBuffer());
  if (head.includes(0)) return false;
  try {
    // The cut may split a character; leave its last bytes out.
    new TextDecoder("utf-8", { fatal: true }).decode(head.length === 8192 ? head.slice(0, -4) : head);
    return true;
  } catch {
    return false;
  }
}

const KIND_LABEL: Partial<Record<PreviewKind, string>> = { image: "web-main.preview.kind.image", video: "web-main.preview.kind.video", audio: "web-main.preview.kind.audio", pdf: "PDF", markdown: "Markdown", csv: "web-main.preview.kind.csv", html: "web-main.preview.kind.html", code: "web-main.preview.kind.code", text: "web-main.preview.kind.text" };
/** A kind's name: its key's words (PDF and Markdown are their own names). */
const kindLabel = (kind: PreviewKind) => { const k = KIND_LABEL[kind] ?? ""; return k.startsWith("web-main.") ? t(k) : k; };

// ── images: zoom and pan ───────────────────────────────────────────────

/** Images stepped through slide this far apart, on this spring. */
const GAP = 24;
const SLIDE = { type: "spring", visualDuration: 0.32, bounce: 0 } as const;


/**
 * An image fitted to the window, to zoom (pinch, ctrl/⌘ + wheel, double-click,
 * the bar's buttons, + − 0) around the pointer and pan (drag, wheel) when larger
 * than the window. Fitted, a sideways swipe steps to the image before or after.
 */
/**
 * `waiting`: `url` is only the thumbnail, standing in the image's place until the whole of it comes. Once it has, it
 * can be marked (annotate/ImageMarks.tsx): `onMarking` says when, `onClose` closes the preview once its marked image
 * is in the chat's draft.
 */
function ImageViewer({ url, file, setControls, swipe, waiting = false, onMarking, onClose }:
  { url: string; file: Attachment; setControls(c: ReactNode): void; swipe: Swipe; waiting?: boolean; onMarking(on: boolean): void; onClose(): void }) {
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(file.width && file.height ? { w: file.width, h: file.height } : null);
  const [zoomControls, setZoomControls] = useState<ReactNode>(null);
  const [marksOn, setMarksOn] = useState(false);
  const zoom = useZoom(natural, { swipe: marksOn ? undefined : swipe });
  useZoomTools(zoom, setZoomControls);
  const marks = useImageMarks({ url: waiting ? null : url, name: file.name, natural, scale: zoom.scale, pass: zoom.stageProps, onDone: onClose });
  useEffect(() => { setMarksOn(marks.on); onMarking(marks.on); }, [marks.on, onMarking]);
  useEffect(() => () => onMarking(false), [onMarking]);
  useEffect(() => { setControls(marks.on ? marks.bar : <>{zoomControls}{marks.bar}</>); }, [marks.on, marks.bar, zoomControls, setControls]);
  useEffect(() => () => setControls(null), [setControls]);
  // A click with the mouse around the image (not a drag, not while marking) closes the preview; a finger's tap there
  // shows or hides the bars instead (Viewer).
  const pressed = useRef<{ x: number; y: number } | null>(null);
  const onPointerDown = (e: React.PointerEvent) => {
    pressed.current = e.pointerType === "mouse" && e.button === 0 && e.target === e.currentTarget ? { x: e.clientX, y: e.clientY } : null;
    zoom.stageProps.onPointerDown(e);
  };
  const onClick = (e: React.MouseEvent) => {
    const p = pressed.current;
    pressed.current = null;
    if (p && !marks.on && Math.hypot(e.clientX - p.x, e.clientY - p.y) < 4) onClose();
  };
  return (
    <div ref={zoom.stage} className={css2.fpStage} {...zoom.stageProps} data-closes={marks.on ? undefined : ""} onPointerDown={onPointerDown} onClick={onClick}>
      <img className={css2.fpImage} src={url} alt={file.name} draggable={false} data-waiting={waiting || undefined} data-viewer-picture=""
        // A thumbnail's own size is not the image's: it only stands in the image's place.
        onLoad={(e) => { const img = e.currentTarget; if (img.naturalWidth && img.naturalHeight && (!waiting || !natural)) setNatural({ w: img.naturalWidth, h: img.naturalHeight }); }}
        style={zoom.place ?? { visibility: "hidden" }} />
      {marks.sheet(zoom.place)}
      {marks.tools}
    </div>
  );
}

/** An image beside the one shown, fitted as it will be once it is (the strip carries it in with a swipe). */
function Peek({ shown: { sessionKey, file }, side }: { shown: Shown; side: -1 | 1 }) {
  const url = useFileUrl(sessionKey, file, true, false);
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(file.width && file.height ? { w: file.width, h: file.height } : null);
  const zoom = useZoom(natural, { keys: false });
  return (
    <div className={css2.fpPeek} data-peek="" aria-hidden="true" style={{ transform: `translateX(calc(${side} * (100% + ${GAP}px)))` }}>
      <div ref={zoom.stage} className={css2.fpStage}>
        {url && <img className={css2.fpImage} src={url} alt="" draggable={false}
          onLoad={(e) => { const img = e.currentTarget; if (!natural && img.naturalWidth && img.naturalHeight) setNatural({ w: img.naturalWidth, h: img.naturalHeight }); }}
          style={zoom.place ?? { visibility: "hidden" }} />}
      </div>
    </div>
  );
}

/** How much of a file has come, out of its size (the station's, else the one sent with it); a bar that sweeps when neither is known. */
function FileComing({ got, size, inBar = false }: { got: FileProgress | null | undefined; size: number; inBar?: boolean }) {
  const total = got?.total ?? (size > 0 ? size : null);
  const part = got && total ? Math.min(1, got.loaded / total) : null;
  return (
    <div className={inBar ? css2.fpHeadProgress : css2.fpProgress}>
      <span className={css2.fpProgressText}>{got && total ? <>{t("web-main.preview.loadingLabel")} <b>{fileSize(got.loaded)}</b> / {fileSize(total)}</> : t("common.opening")}</span>
      <Progress part={part} label={t("web-main.preview.loadingLabel")} className={css2.fpProgressTrack} />
    </div>
  );
}

/** How far the core has downloaded a file (chatDownloads.ts): its words (正在下载 42% · 18.3 MB) over its bar; called off
 * under it. */
function DownloadComing({ download }: { download: DownloadShown }) {
  return (
    <>
      <div className={css2.fpProgress}>
        <span className={css2.fpProgressText}>{download.statusText}</span>
        <Progress part={download.progress} label={download.statusText} className={css2.fpProgressTrack} />
      </div>
      <button type="button" className={`${controlsCss.btn} ${controlsCss.btnGhost}`} onClick={() => cancelDownload(download.id)}>{t("web-main.file.cancelDownload")}</button>
    </>
  );
}

/** A zoom's tools in the bar: out, how large (to fit), in, its own size. */
function useZoomTools(zoom: ReturnType<typeof useZoom>, setControls: (c: ReactNode) => void) {
  const { scale, minScale, zoomTo, reset } = zoom;
  useEffect(() => {
    setControls(
      <span className={css2.fpZoom}>
        <Tip label={t("web-main.preview.zoomOutKey")}><button type="button" className={pageCss.iconBtn} aria-label={t("web-main.preview.zoomOut")} disabled={scale <= minScale + 1e-6} onClick={() => zoomTo(scale / 1.25)}><Minus size={18} /></button></Tip>
        <Tip label={t("web-main.preview.fitKey")}><button type="button" className={`${css2.fpToolText} ${css2.fpPercent}`} onClick={reset}>{Math.round(scale * 100)}%</button></Tip>
        <Tip label={t("web-main.preview.zoomInKey")}><button type="button" className={pageCss.iconBtn} aria-label={t("web-main.preview.zoomIn")} disabled={scale >= MAX_SCALE - 1e-6} onClick={() => zoomTo(scale * 1.25)}><Plus size={18} /></button></Tip>
        <Tip label={t("web-main.preview.actualKey")}><button type="button" className={css2.fpToolText} onClick={() => zoomTo(1)}>1:1</button></Tip>
      </span>,
    );
  }, [scale, minScale, zoomTo, reset, setControls]);
  useEffect(() => () => setControls(null), [setControls]);
}

// ── PDFs ───────────────────────────────────────────────────────────────

/** Pages drawn by pdf.js (loaded when first needed), each when it scrolls near: the same everywhere, phones included. */
function PdfViewer({ blob }: { blob: Blob }) {
  const [doc, setDoc] = useState<PDFDocumentProxy | null>(null);
  const [error, setError] = useState<string | null>(null);
  const page = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  useEffect(() => {
    let live = true;
    let task: PDFDocumentLoadingTask | null = null;
    void (async () => {
      const [pdfjs, worker] = await Promise.all([import("pdfjs-dist"), import("pdfjs-dist/build/pdf.worker.min.mjs?url")]);
      pdfjs.GlobalWorkerOptions.workerSrc = worker.default;
      const data = new Uint8Array(await blob.arrayBuffer());
      if (!live) return;
      task = pdfjs.getDocument({ data });
      const loaded = await task.promise;
      if (live) setDoc(loaded);
    })().catch((e: unknown) => { if (live) setError(e instanceof Error ? e.message : String(e)); });
    return () => { live = false; void task?.destroy(); };
  }, [blob]);
  useLayoutEffect(() => {
    const el = page.current;
    if (!el) return;
    const measure = () => { const cs = getComputedStyle(el); setWidth(el.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight)); };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    return () => observer.disconnect();
  }, []);
  return (
    <div ref={page} className={`${css2.fpPage} ${css2.fpPdf}`}>
      {error ? <div className={css2.fpPlain}>{t("web-main.preview.pdfFailed", { error })}</div>
        : !doc || width <= 0 ? <div className={css2.fpPlain}><Spinner /></div>
        : Array.from({ length: doc.numPages }, (_, i) => <PdfPage key={i} doc={doc} number={i + 1} width={width} />)}
    </div>
  );
}

function PdfPage({ doc, number, width }: { doc: PDFDocumentProxy; number: number; width: number }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const [size, setSize] = useState<{ w: number; h: number } | null>(null);
  const [near, setNear] = useState(number <= 2);
  useEffect(() => {
    let live = true;
    void doc.getPage(number).then((p) => {
      if (!live) return;
      const v = p.getViewport({ scale: 1 });
      setSize({ w: v.width, h: v.height });
    });
    return () => { live = false; };
  }, [doc, number]);
  useEffect(() => {
    const el = canvas.current;
    if (!el || near) return;
    const observer = new IntersectionObserver(([e]) => { if (e?.isIntersecting) setNear(true); }, { rootMargin: "600px 0px" });
    observer.observe(el);
    return () => observer.disconnect();
  }, [near, size]);
  useEffect(() => {
    const el = canvas.current;
    if (!el || !near || !size || width <= 0) return;
    let task: RenderTask | null = null;
    let live = true;
    void doc.getPage(number).then((p) => {
      if (!live) return;
      const scale = (width / size.w) * Math.min(3, window.devicePixelRatio || 1);
      const viewport = p.getViewport({ scale });
      el.width = Math.floor(viewport.width);
      el.height = Math.floor(viewport.height);
      task = p.render({ canvas: el, canvasContext: el.getContext("2d")!, viewport });
      task.promise.catch(() => {});
    });
    return () => { live = false; task?.cancel(); };
  }, [doc, number, near, size, width]);
  const shown = size ? { width, aspectRatio: `${size.w} / ${size.h}` } : { width, aspectRatio: "210 / 297" };
  return <canvas ref={canvas} className={css2.fpPdfPage} style={shown} aria-label={t("web-main.preview.page", { n: number })} />;
}

// ── text ───────────────────────────────────────────────────────────────

/**
 * Put at the end of a previewed HTML file: its frame tells the preview when a mouse moves over it (at most a few times a
 * second), and Esc pressed in it that the page itself did nothing with (the keys go to the frame once it is clicked in,
 * not to the preview, which would not close).
 */
const TELL = `<script>{let t=0;addEventListener("pointermove",(e)=>{if(e.pointerType!=="mouse"||e.timeStamp-t<200)return;t=e.timeStamp;parent.postMessage({stillfailPreview:"move"},"*")},{capture:true,passive:true});addEventListener("keydown",(e)=>{if(e.key==="Escape"&&!e.defaultPrevented&&!e.isComposing)parent.postMessage({stillfailPreview:"escape"},"*")})}</script>`;

/** Above this a file shows as plain text, unhighlighted; above the next, only its start. */
const HIGHLIGHT_LIMIT = 256 * 1024;
const SHOW_LIMIT = 2 * 1024 * 1024;
const TABLE_ROWS = 2000;

function TextViewer({ blob, kind, language, name, setControls, onMove, onEscape }: {
  blob: Blob; kind: PreviewKind; language: string | undefined; name: string; setControls(c: ReactNode): void; onMove(): void; onEscape(): void;
}) {
  const frame = useRef<HTMLIFrameElement>(null);
  const host = useContext(FrameHost);
  const told = useRef({ move: onMove, escape: onEscape });
  told.current = { move: onMove, escape: onEscape };
  useEffect(() => {
    const onMessage = (e: MessageEvent) => {
      if (e.source !== frame.current?.contentWindow) return;
      const what = (e.data as { stillfailPreview?: string } | null)?.stillfailPreview;
      if (what === "move") told.current.move();
      else if (what === "escape") told.current.escape();
    };
    addEventListener("message", onMessage);
    return () => removeEventListener("message", onMessage);
  }, []);
  const [text, setText] = useState<string | null>(null);
  const cut = blob.size > SHOW_LIMIT;
  const rendered = kind === "markdown" || kind === "csv" || kind === "html";
  const [source, setSource] = useState(false);
  useEffect(() => {
    let live = true;
    void blob.slice(0, SHOW_LIMIT).text().then((t) => { if (live) setText(t); });
    return () => { live = false; };
  }, [blob]);
  useEffect(() => {
    if (!rendered) return;
    setControls(
      <Segmented label={t("web-main.preview.showAs")} value={source ? "source" : "view"} onChange={(v) => setSource(v === "source")}
        options={[{ value: "view", label: t("web-main.preview.rendered") }, { value: "source", label: t("web-main.preview.source") }]} />,
    );
    return () => setControls(null);
  }, [rendered, source, setControls]);
  if (text === null) return <div className={css2.fpNote}><WaitLine text={t("common.opening")} /></div>;
  let content: ReactNode;
  if (kind === "html" && !source) {
    // Its scripts run, but in an origin of its own: nothing of still.fail's is reachable from it.
    // A fragment an agent wrote to be drawn in a message (Viz.tsx) is shown the same way, in still.fail's stylesheet.
    // A mouse moving over it is the frame's, not the preview's: the frame tells, so the bars wake as they do over an image.
    // On a page whose CSP its frames would inherit, from the page's frame host, sandboxed the same (Viz.tsx FrameHost).
    const doc = (isFragment(text) ? vizDocument(text) : text) + TELL;
    const from = host === null ? { srcDoc: doc } : { src: host, onLoad: () => frame.current?.contentWindow?.postMessage({ stillfailVizDocument: doc }, "*") };
    content = <iframe ref={frame} className={`${css2.fpFrame} fp-html`} sandbox="allow-scripts" {...from} title={name} />;
    return <div className={`${css2.fpPage} ${css2.fpPageFrame}`}>{content}</div>;
  }
  if (kind === "markdown" && !source) content = <div className={`${conversationCss.markdown} ${css2.fpMarkdown}`}><Prose>{text}</Prose></div>;
  else if (kind === "csv" && !source) content = <CsvTable text={text} tab={name.toLowerCase().endsWith(".tsv")} />;
  else {
    const lang = kind === "markdown" ? "markdown" : kind === "csv" ? undefined : language;
    const fence = "`".repeat(Math.max(3, ...[...text.matchAll(/`{3,}/g)].map((m) => m[0].length + 1)));
    content = lang && text.length <= HIGHLIGHT_LIMIT
      ? <div className={`${conversationCss.markdown} ${css2.fpCode}`}><Prose>{`${fence}${lang}\n${text}\n${fence}`}</Prose></div>
      : <pre className={css2.fpPlain}>{text}</pre>;
  }
  return (
    <div className={css2.fpPage}>
      {cut && <div className={css2.fpCut}>{t("web-main.preview.cut", { size: fileSize(SHOW_LIMIT) })}</div>}
      {content}
    </div>
  );
}

/** Rows of a CSV (or TSV), quotes and all. */
export function parseCsv(text: string, separator: string, limit = Infinity): string[][] {
  const rows: string[][] = [];
  let row: string[] = [], field = "", quoted = false;
  for (let i = 0; i < text.length && rows.length < limit; i++) {
    const c = text[i]!;
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"' && field === "") quoted = true;
    else if (c === separator) { row.push(field); field = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(field); rows.push(row); row = []; field = "";
    } else field += c;
  }
  if ((field || row.length) && rows.length < limit) { row.push(field); rows.push(row); }
  return rows;
}

function CsvTable({ text, tab }: { text: string; tab: boolean }) {
  const rows = parseCsv(text, tab ? "\t" : ",", TABLE_ROWS + 1);
  const [head, ...body] = rows;
  if (!head) return <pre className={css2.fpPlain}>{text}</pre>;
  const more = body.length > TABLE_ROWS;
  return (
    <>
      <div className={css2.fpTableWrap}>
        <table className={css2.fpTable}>
          <thead><tr><th aria-label={t("web-main.preview.lineNumber")} />{head.map((h, i) => <th key={i}>{h}</th>)}</tr></thead>
          <tbody>{body.slice(0, TABLE_ROWS).map((r, i) => <tr key={i}><td className={css2.fpRow}>{i + 1}</td>{head.map((_, j) => <td key={j}>{r[j] ?? ""}</td>)}</tr>)}</tbody>
        </table>
      </div>
      {more && <div className={css2.fpCut}>{t("web-main.preview.rowsCut", { n: TABLE_ROWS })}</div>}
    </>
  );
}
