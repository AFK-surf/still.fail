// A file sent in a chat, opened over the page: images to zoom and pan,
// video and audio to play, PDFs drawn by pdf.js, text and code
// highlighted, Markdown rendered, CSV as a table, HTML in a sandbox. Anything
// else says it cannot be shown and offers the download.
import { Dialog as RDialog } from "radix-ui";
import { createContext, useCallback, useContext, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode, type RefObject } from "react";
import { BIG_FILE, useApi, type Api, type Attachment, type FileProgress } from "./api.ts";
import { Check, ChevronLeft, ChevronRight, Close, Copy, Download, Minus, Plus } from "./icons.tsx";
import { placeFiles, Prose } from "./Prose.tsx";
import { isFragment, vizDocument } from "./Viz.tsx";
import { fileLink } from "./Prose.css.ts";
import { useStation } from "./station.tsx";
import { Segmented, Tip } from "./ui.tsx";
import { VideoViewer } from "./VideoViewer.tsx";
import { useImageMarks } from "./annotate/ImageMarks.tsx";
import { useBackClose } from "./backClose.ts";
import { thumbId, viewerFlight } from "./viewerFlight.ts";
import { asPng, standIn } from "./wholeImages.ts";
import { failure, useToast } from "./toast.tsx";
import { animate, reducedMotion, type AnimationPlaybackControls } from "./motion.ts";
import type { PDFDocumentLoadingTask, PDFDocumentProxy, RenderTask } from "pdfjs-dist";
import * as css2 from "./FilePreview.css.ts";
import * as waitingCss from "./styles/waiting.css.ts";
import * as controlsCss from "./styles/controls.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import { t } from "./i18n.ts";

export function fileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

/** The bars over a file (and a video's controls) fade out after the pointer has rested this long. */
export const REST_MS = 2000;
/** A finger has no hover to keep them: they stay longer after a tap. */
export const TAP_REST_MS = 4000;

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

const storedName = (a: Attachment) => a.path.split("/").at(-1)!;

// Files sent never change: each is fetched once per page, and the most recent are kept for a chat opened again.
const blobs = new Map<string, Promise<Blob>>();
const KEEP_BLOBS = 100;

// How far each whole file on its way has come, and who is watching it.
const coming = new Map<string, { got: FileProgress | null; watchers: Set<(got: FileProgress) => void> }>();

const fileId = (station: string, sessionKey: string, file: Attachment, thumb: boolean) => `${station}/${sessionKey}/${file.path}${thumb ? "#thumb" : ""}`;

function fetchFile(api: Api, station: string, sessionKey: string, file: Attachment, thumb = false): Promise<Blob> {
  const id = fileId(station, sessionKey, file, thumb);
  let blob = blobs.get(id);
  if (!blob) {
    // Typed by its name, so the browser plays and shows it whatever the station called it (a thumbnail is typed by the
    // station: it may be a JPEG of a PNG).
    const { type } = kindOf(file.name);
    // A whole file may be big: how far it has come is kept for whoever shows it (thumbnails are small).
    const on = thumb ? null : { got: null as FileProgress | null, watchers: new Set<(got: FileProgress) => void>() };
    if (on) coming.set(id, on);
    blob = api.file(sessionKey, storedName(file), thumb, on ? (got) => { on.got = got; on.watchers.forEach((w) => w(got)); } : undefined, file.size)
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

/** A file as a blob and its URL, fetched from the station once and kept while shown. */
function useFile(sessionKey: string, file: Attachment, enabled: boolean, thumb = false): Loaded {
  const api = useApi();
  const station = useStation();
  const [loaded, setLoaded] = useState<Loaded>({ state: "loading" });
  useEffect(() => {
    if (!enabled) return;
    let u: string | null = null;
    let unstand: (() => void) | null = null;
    let current = true;
    setLoaded({ state: "loading" });
    const promise = fetchFile(api, station.address, sessionKey, file, thumb);
    const on = coming.get(fileId(station.address, sessionKey, file, thumb));
    const watch = (got: FileProgress) => { if (current) setLoaded((l) => (l.state === "loading" ? { state: "loading", got } : l)); };
    if (on) {
      on.watchers.add(watch);
      if (on.got) watch(on.got);
    }
    promise.then((blob) => {
      if (!current) return;
      u = URL.createObjectURL(blob);
      // A thumbnail stands in for the image: copied in the desktop app, the image itself is (wholeImages.ts).
      if (thumb) unstand = standIn(u, () => fetchFile(api, station.address, sessionKey, file));
      setLoaded({ state: "ready", blob, url: u });
    }, (error: unknown) => {
      if (current) setLoaded({ state: "error", message: error instanceof Error ? error.message : String(error) });
    });
    return () => {
      current = false;
      on?.watchers.delete(watch);
      unstand?.();
      if (u) URL.revokeObjectURL(u);
    };
  }, [api, station.address, sessionKey, file.path, enabled, thumb]);
  return loaded;
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
 * The images of the chat a preview is opened from, in the order it shows them (read when needed, so the messages
 * need not be drawn again as it grows): an image opened steps to the one before or after (arrows, ← →, a swipe).
 */
export const Gallery = createContext<(() => Shown[]) | null>(null);

/** A chat's images for its Gallery, as its messages show them: an agent's named in its text first, then those below it. */
export function chatImages(messages: { authorKind?: string; text: string; attachments?: Attachment[] | undefined }[], owner: (file: Attachment) => string | null): Shown[] {
  return messages.flatMap((m) => {
    const { placed, rest } = m.authorKind === "person" ? { placed: new Map<string, Attachment>(), rest: m.attachments ?? [] } : placeFiles(m.text, m.attachments);
    return [...placed.values(), ...rest].flatMap((file) => {
      const sessionKey = isImage(file.name) ? owner(file) : null;
      return sessionKey === null ? [] : [{ sessionKey, file }];
    });
  });
}

/** A file over the whole window, a bar with its name and tools on top; Esc closes it. */
export function FilePreview({ open, onClose, sessionKey, file }: { open: boolean; onClose(): void; sessionKey: string; file: Attachment }) {
  // Closed by hand (its button, Esc, back), it goes back into the chat's thumbnail first (viewerFlight.ts).
  const closing = useRef<((done: () => void) => void) | null>(null);
  const close = () => { const c = closing.current; if (c) c(onClose); else onClose(); };
  useBackClose(open, close);
  return (
    <RDialog.Root open={open} onOpenChange={(o) => { if (!o) close(); }}>
      <RDialog.Portal>
        {open && <Viewer onClose={close} closing={closing} sessionKey={sessionKey} file={file} />}
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

function Viewer({ onClose, closing, ...opened }: { onClose(): void; closing: RefObject<((done: () => void) => void) | null>; sessionKey: string; file: Attachment }) {
  const [{ sessionKey, file }, setShown] = useState<Shown>(opened);
  const gallery = useContext(Gallery);
  const images = isImage(file.name) ? gallery?.() ?? [] : [];
  const at = images.findIndex((i) => i.file.path === file.path);
  const before = at > 0 ? images[at - 1] : undefined;
  const after = at >= 0 ? images[at + 1] : undefined;
  const api = useApi();
  const station = useStation();
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
    if (el && from && !reducedMotion()) run(from, 0, v, (x) => { el.style.transform = `translateX(${x}px)`; });
    else if (el) el.style.transform = "";
  }, [settle, run]);
  /** To the one before (-1) or after (1), going on from where a swipe left it (at `v` px/ms). */
  const go = useCallback((dir: -1 | 1, v = 0) => {
    const to = dir < 0 ? near.current.before : near.current.after;
    if (!to) return back(v);
    const from = settle();
    const el = slide.current;
    if (el && !reducedMotion()) {
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
  useEffect(() => {
    for (const n of [before, after]) if (n) fetchFile(api, station.address, n.sessionKey, n.file).catch(() => {});
  }, [api, station.address, before?.file.path, after?.file.path]);
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
  const loaded = useFile(sessionKey, file, true);
  const known = kindOf(file.name);
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
  const kind = known.kind ?? sniffed;
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
  if (known.kind === "image" && (loaded.state === "ready" || (loaded.state === "loading" && thumb))) {
    body = <ImageViewer key={file.path} url={loaded.state === "ready" ? loaded.url : thumb!} file={file} setControls={setControls} swipe={swipe}
      waiting={loaded.state === "loading"} onMarking={setMarking} onClose={onClose} />;
  } else if (loaded.state === "loading" || (kind === null && loaded.state === "ready")) {
    body = <div className={css2.fpNote}>{loaded.state === "loading" && loaded.got ? <Progress got={loaded.got} size={file.size} /> : <><span className={waitingCss.spinner} aria-hidden="true" />{t("web-main.preview.loading")}</>}</div>;
  }
  else if (loaded.state === "error") body = <div className={css2.fpNote}>{t("web-main.preview.loadFailed", { error: loaded.message })}</div>;
  else {
    const { url, blob } = loaded;
    switch (kind) {
      case "image": body = <ImageViewer key={file.path} url={url} file={file} setControls={setControls} swipe={swipe} onMarking={setMarking} onClose={onClose} />; break;
      case "video": body = <VideoViewer key={file.path} url={url} blob={blob} name={file.name} />; break;
      case "audio": body = <div className={css2.fpAudio}><span className={css2.fpAudioName}>{file.name}</span><audio src={url} controls autoPlay /></div>; break;
      case "pdf": body = <PdfViewer blob={blob} />; break;
      case "markdown": case "csv": case "html": case "code": case "text":
        body = <TextViewer blob={blob} kind={kind} language={known.language} name={file.name} setControls={setControls} onMove={wake} />; break;
      default: body = <div className={css2.fpNote}>{t("web-main.preview.unsupported")}<a className={controlsCss.btn} href={url} download={file.name}><Download size={16} />{t("web-main.preview.download")}</a></div>;
    }
  }
  return (
    <RDialog.Content ref={content} className={css2.fp} data-kind={kind ?? undefined} aria-describedby={undefined} data-awake={awake || coming !== undefined || marking || undefined}
      // A mouse wakes the bars by moving; a finger has no hover, and a tap on the file shows or hides them.
      onPointerMove={(e) => { if (e.pointerType === "mouse") wake(); }}
      onPointerLeave={(e) => { if (e.pointerType !== "mouse") return; clearTimeout(resting.current); if (!onBar.current) setAwake(false); }}
      onPointerDown={(e) => { tapAt.current = { x: e.clientX, y: e.clientY }; }}
      onPointerUp={(e) => {
        const t = tapAt.current;
        if (e.pointerType === "mouse" || !t || Math.hypot(e.clientX - t.x, e.clientY - t.y) > 10 || (e.target as Element).closest("button, a, header")) return;
        if (awake) { clearTimeout(resting.current); setAwake(false); } else wake(TAP_REST_MS);
      }}
      // The page itself takes focus, not its first button: no ring on the close button for a tap or click.
      onOpenAutoFocus={(e) => { e.preventDefault(); (e.currentTarget as HTMLElement | null)?.focus(); }}>
      <header ref={head} className={css2.fpHead} data-floats
        onPointerEnter={(e) => { if (e.pointerType !== "mouse") return; onBar.current = true; clearTimeout(resting.current); setAwake(true); }}
        onPointerLeave={(e) => { if (e.pointerType !== "mouse") return; onBar.current = false; wake(); }}>
        <div className={css2.fpTitle}>
          <Tip label={file.path}><RDialog.Title className={css2.fpName}>{file.name}</RDialog.Title></Tip>
          <span className={css2.fpMeta}>{images.length > 1 && at >= 0 ? `${at + 1} / ${images.length} · ` : ""}{fileSize(file.size)}{kind && KIND_LABEL[kind as PreviewKind] ? ` · ${kindLabel(kind as PreviewKind)}` : ""}</span>
        </div>
        {coming !== undefined && <Progress got={coming} size={file.size} inBar />}
        {controls}
        {kind === "image" && !marking && (loaded.state === "ready"
          ? <CopyImage key={file.path} image={loaded.blob} />
          : <span className={pagesCss.iconBtn} aria-hidden="true" style={{ visibility: "hidden" }}><Copy size={18} /></span>)}
        {marking ? null : loaded.state === "ready"
          ? <Tip label={t("web-main.preview.download")}><a className={pagesCss.iconBtn} href={loaded.url} download={file.name} aria-label={t("web-main.preview.download")}><Download size={18} /></a></Tip>
          // Its place kept until it comes.
          : <span className={pagesCss.iconBtn} aria-hidden="true" style={{ visibility: "hidden" }}><Download size={18} /></span>}
        <Tip label={t("web-main.preview.closeKey")}><RDialog.Close className={pagesCss.iconBtn} aria-label={t("common.close")}><Close size={18} /></RDialog.Close></Tip>
      </header>
      <div className={css2.fpBody}>
        <div ref={slide} className={css2.fpSlide}>
          {body}
          {/* The ones beside it, out of sight until a swipe brings them in. */}
          {known.kind === "image" && !marking && before && <Peek key={before.file.path} shown={before} side={-1} />}
          {known.kind === "image" && !marking && after && <Peek key={after.file.path} shown={after} side={1} />}
        </div>
        {images.length > 1 && at >= 0 && !marking && <>
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
  return <Tip label={label}><button type="button" className={pagesCss.iconBtn} aria-label={label} onClick={copy}>{copied ? <Check size={18} /> : <Copy size={18} />}</button></Tip>;
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

/** A sideways drag of a fitted image: where it has got to (px from where it started), then where and how fast (px/ms) it was let go. */
export interface Swipe { drag(dx: number): void; end(dx: number, vx: number): void }
/** Images stepped through slide this far apart, on this spring. */
const GAP = 24;
const SLIDE = { type: "spring", visualDuration: 0.32, bounce: 0 } as const;

interface View { scale: number; x: number; y: number }
const MAX_SCALE = 16;

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
  const zoom = useZoom(natural, setZoomControls, marksOn ? undefined : swipe);
  const marks = useImageMarks({ url: waiting ? null : url, name: file.name, natural, scale: zoom.scale, pass: zoom.stageProps, onDone: onClose });
  useEffect(() => { setMarksOn(marks.on); onMarking(marks.on); }, [marks.on, onMarking]);
  useEffect(() => () => onMarking(false), [onMarking]);
  useEffect(() => { setControls(marks.on ? marks.bar : <>{zoomControls}{marks.bar}</>); }, [marks.on, marks.bar, zoomControls, setControls]);
  useEffect(() => () => setControls(null), [setControls]);
  return (
    <div ref={zoom.stage} className={css2.fpStage} {...zoom.stageProps}>
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
  const zoom = useZoom(natural, noControls, undefined, false);
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
const noControls = () => {};

/** How much of a file has come, out of its size (the station's, else the one sent with it); a bar that sweeps when neither is known. */
function Progress({ got, size, inBar = false }: { got: FileProgress | null | undefined; size: number; inBar?: boolean }) {
  const total = got?.total ?? (size > 0 ? size : null);
  const part = got && total ? Math.min(1, got.loaded / total) : null;
  return (
    <div className={inBar ? css2.fpHeadProgress : css2.fpProgress} role="progressbar" aria-label={t("web-main.preview.loadingLabel")} aria-valuemin={0} aria-valuemax={100} aria-valuenow={part === null ? undefined : Math.round(part * 100)}>
      <span className={css2.fpProgressText}>{got && total ? <>{t("web-main.preview.loadingLabel")} <b>{fileSize(got.loaded)}</b> / {fileSize(total)}</> : t("web-main.preview.loading")}</span>
      <span className={css2.fpProgressTrack}><span className={css2.fpProgressBar} style={part === null ? undefined : { width: `${part * 100}%` }} data-unknown={part === null || undefined} /></span>
    </div>
  );
}

/**
 * Zooming and panning a picture of `natural` size in a stage (an image, a video's frames): fitted to the window, to
 * zoom (pinch, ctrl/⌘ + wheel, double-click, the bar's buttons, + − 0 1) around the pointer and pan (drag, wheel) when
 * larger than the window. Fitted, one pointer dragging sideways is a `swipe`'s. `place` positions the picture (absolutely, in the stage's centre).
 */
export function useZoom(natural: { w: number; h: number } | null, setControls: (c: ReactNode) => void, swipe?: Swipe, keys = true) {
  const stage = useRef<HTMLDivElement>(null);
  const [box, setBox] = useState<{ w: number; h: number; top: number; bottom: number } | null>(null);
  const [view, setView] = useState<View | null>(null);
  const viewRef = useRef<View | null>(null);
  viewRef.current = view;

  useLayoutEffect(() => {
    const el = stage.current;
    if (!el) return;
    // The bars floating over it (`data-floats`: the preview's head, a video's controls, the marking tools) take their
    // height off its top and bottom: faded or not, the picture stays clear of them.
    const root = el.closest(`.${css2.fp}`) ?? el;
    const measure = () => {
      // Its parent's box, which it fills: its own may be moved and scaled (opening out of a thumbnail, viewerFlight.ts).
      const r = (el.parentElement ?? el).getBoundingClientRect();
      // Where it is in place: stepping through images moves it sideways (the strip; the one beside, a peek's place).
      let slid = 0;
      for (let n = el.parentElement; n && n !== root; n = n.parentElement) {
        const t = getComputedStyle(n).transform;
        if (t !== "none") slid += new DOMMatrixReadOnly(t).m41;
      }
      let top = 0, bottom = 0;
      for (const bar of root.querySelectorAll("[data-floats]")) {
        const b = bar.getBoundingClientRect();
        if (!b.height || b.right <= r.left - slid || b.left >= r.right - slid) continue;
        if (b.top + b.bottom < r.top + r.bottom) top = Math.max(top, b.bottom - r.top);
        else bottom = Math.max(bottom, r.bottom - b.top);
      }
      setBox((was) => {
        const next = { w: el.clientWidth, h: el.clientHeight, top: Math.max(0, Math.round(top)), bottom: Math.max(0, Math.round(bottom)) };
        return was && was.w === next.w && was.h === next.h && was.top === next.top && was.bottom === next.bottom ? was : next;
      });
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    // Bars come and go (the marking tools) and change their size: each is watched as it comes.
    const watch = () => { for (const bar of root.querySelectorAll("[data-floats]")) observer.observe(bar); measure(); };
    watch();
    const coming = new MutationObserver(watch);
    coming.observe(root, { childList: true, subtree: true });
    return () => { observer.disconnect(); coming.disconnect(); };
  }, []);

  // Fitted, it keeps a margin from the window's edges, and a smaller one from the bars.
  const MARGIN = box && box.w < 640 ? 12 : 32;
  const padTop = box?.top ? box.top + MARGIN / 2 : MARGIN, padBottom = box?.bottom ? box.bottom + MARGIN / 2 : MARGIN;
  /** Where a picture smaller than the room between the bars sits: in the middle of it. */
  const centreY = (padTop - padBottom) / 2;
  const fit = natural && box ? Math.min(1, (box.w - 2 * MARGIN) / natural.w, (box.h - padTop - padBottom) / natural.h) : 1;
  const minScale = Math.min(fit, 1) / 2;

  /** Keeps a larger-than-window image covering the window between the bars, a smaller one centred there. */
  const clamp = useCallback((v: View): View => {
    if (!natural || !box) return v;
    const scale = Math.min(MAX_SCALE, Math.max(minScale, v.scale));
    const spareX = Math.max(0, (natural.w * scale - box.w) / 2);
    const h = natural.h * scale, room = box.h - box.top - box.bottom;
    const y = h <= room ? centreY : Math.min(h / 2 - box.h / 2 + box.top, Math.max(box.h / 2 - box.bottom - h / 2, v.y));
    return { scale, x: Math.min(spareX, Math.max(-spareX, v.x)), y };
  }, [natural, box, minScale, centreY]);

  // Fitted when it first shows and whenever the window changes while still fitted.
  const fitted = useRef(true);
  useEffect(() => {
    if (!natural || !box) return;
    if (fitted.current || !viewRef.current) setView({ scale: fit, x: 0, y: centreY });
    else setView((v) => (v ? clamp(v) : v));
  }, [natural, box, fit, centreY, clamp]);

  /** To `scale`, the image's point under (px, py) — relative to the stage's centre — staying put. */
  const zoomTo = useCallback((scale: number, px = 0, py = 0) => {
    const v = viewRef.current;
    if (!v) return;
    const next = Math.min(MAX_SCALE, Math.max(minScale, scale));
    const k = next / v.scale;
    fitted.current = false;
    setView(clamp({ scale: next, x: px - (px - v.x) * k, y: py - (py - v.y) * k }));
  }, [clamp, minScale]);
  const reset = useCallback(() => { fitted.current = true; setView({ scale: fit, x: 0, y: centreY }); }, [fit, centreY]);

  const fromCentre = (clientX: number, clientY: number) => {
    const r = stage.current!.getBoundingClientRect();
    return [clientX - r.left - r.width / 2, clientY - r.top - r.height / 2] as const;
  };

  // The wheel pans (with shift, sideways); only a trackpad's pinch, or the wheel with ctrl or ⌘, zooms. A listener that
  // can stop the page scrolling.
  useEffect(() => {
    const el = stage.current;
    if (!el) return;
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      const v = viewRef.current;
      if (!v) return;
      const unit = e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? el.clientHeight : 1;
      if (e.ctrlKey || e.metaKey) {
        // A trackpad's pinch comes as a wheel with ctrl, in small steps; a mouse wheel's notches are much larger.
        const step = e.deltaY * unit;
        const factor = Math.exp(-step * (e.ctrlKey && Math.abs(step) < 50 ? 0.01 : 0.002));
        zoomTo(v.scale * factor, ...fromCentre(e.clientX, e.clientY));
        return;
      }
      const dx = (e.shiftKey && !e.deltaX ? e.deltaY : e.deltaX) * unit, dy = (e.shiftKey && !e.deltaX ? 0 : e.deltaY) * unit;
      const next = clamp({ ...v, x: v.x - dx, y: v.y - dy });
      if (next.x === v.x && next.y === v.y) return;
      fitted.current = false;
      setView(next);
    };
    el.addEventListener("wheel", onWheel, { passive: false });
    return () => el.removeEventListener("wheel", onWheel);
  }, [zoomTo, clamp]);

  // Drag to pan; two fingers pinch.
  const pointers = useRef(new Map<number, { x: number; y: number }>());
  const gesture = useRef<{ view: View; x: number; y: number; distance: number } | null>(null);
  // A swipe going on: how far it has gone and how fast (px/ms, of its last moves); let go when a second finger comes.
  const swiping = useRef<{ dx: number; at: number; vx: number } | null>(null);
  const letGo = (dx: number, vx: number) => { if (swiping.current) { swiping.current = null; swipe?.end(dx, vx); } };
  const start = () => {
    const points = [...pointers.current.values()];
    const v = viewRef.current;
    if (!v || !points.length) { gesture.current = null; return; }
    const x = points.reduce((s, p) => s + p.x, 0) / points.length, y = points.reduce((s, p) => s + p.y, 0) / points.length;
    const distance = points.length > 1 ? Math.hypot(points[0]!.x - points[1]!.x, points[0]!.y - points[1]!.y) : 0;
    gesture.current = { view: v, x, y, distance };
  };
  const onPointerDown = (e: React.PointerEvent) => {
    if (e.button !== 0) return;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
    letGo(0, 0);
    start();
  };
  const onPointerMove = (e: React.PointerEvent) => {
    if (!pointers.current.has(e.pointerId) || !gesture.current) return;
    pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
    const points = [...pointers.current.values()];
    const g = gesture.current;
    const x = points.reduce((s, p) => s + p.x, 0) / points.length, y = points.reduce((s, p) => s + p.y, 0) / points.length;
    let scale = g.view.scale;
    if (points.length > 1 && g.distance > 0) scale = Math.min(MAX_SCALE, Math.max(minScale, g.view.scale * Math.hypot(points[0]!.x - points[1]!.x, points[0]!.y - points[1]!.y) / g.distance));
    // The point under the gesture's start stays under its centre now.
    const [sx, sy] = fromCentre(g.x, g.y);
    const k = scale / g.view.scale;
    // Fitted, one pointer moves the image sideways to the one before or after it.
    if (swipe && points.length === 1 && g.distance === 0 && g.view.scale <= fit * 1.01) {
      const dx = x - g.x, s = swiping.current;
      if (!s && Math.abs(dx) < 4) return;
      const at = e.timeStamp;
      swiping.current = { dx, at, vx: s && at > s.at ? 0.6 * ((dx - s.dx) / (at - s.at)) + 0.4 * s.vx : 0 };
      swipe.drag(dx);
      return;
    }
    fitted.current = false;
    setView(clamp({ scale, x: sx - (sx - g.view.x) * k + (x - g.x), y: sy - (sy - g.view.y) * k + (y - g.y) }));
  };
  const onPointerUp = (e: React.PointerEvent) => {
    const g = gesture.current, s = swiping.current;
    pointers.current.delete(e.pointerId);
    start();
    // A move that stopped a while ago is no flick.
    if (s && g) letGo(e.type === "pointerup" ? e.clientX - g.x : 0, e.timeStamp - s.at < 80 ? s.vx : 0);
  };
  const onDoubleClick = (e: React.MouseEvent) => {
    const v = viewRef.current;
    if (!v) return;
    if (v.scale > fit * 1.01) reset();
    else zoomTo(Math.max(fit * 2.5, 1), ...fromCentre(e.clientX, e.clientY));
  };

  useEffect(() => {
    if (!keys) return;
    const onKey = (e: KeyboardEvent) => {
      const v = viewRef.current;
      if (!v || e.metaKey || e.ctrlKey || e.altKey) return;
      if (e.key === "+" || e.key === "=") zoomTo(v.scale * 1.25);
      else if (e.key === "-" || e.key === "_") zoomTo(v.scale / 1.25);
      else if (e.key === "0") reset();
      else if (e.key === "1") zoomTo(1);
      else return;
      e.preventDefault();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [zoomTo, reset, keys]);

  const scale = view?.scale ?? fit;
  useEffect(() => {
    setControls(
      <span className={css2.fpZoom}>
        <Tip label={t("web-main.preview.zoomOutKey")}><button type="button" className={pagesCss.iconBtn} aria-label={t("web-main.preview.zoomOut")} disabled={scale <= minScale + 1e-6} onClick={() => zoomTo(scale / 1.25)}><Minus size={18} /></button></Tip>
        <Tip label={t("web-main.preview.fitKey")}><button type="button" className={`${css2.fpToolText} ${css2.fpPercent}`} onClick={reset}>{Math.round(scale * 100)}%</button></Tip>
        <Tip label={t("web-main.preview.zoomInKey")}><button type="button" className={pagesCss.iconBtn} aria-label={t("web-main.preview.zoomIn")} disabled={scale >= MAX_SCALE - 1e-6} onClick={() => zoomTo(scale * 1.25)}><Plus size={18} /></button></Tip>
        <Tip label={t("web-main.preview.actualKey")}><button type="button" className={css2.fpToolText} onClick={() => zoomTo(1)}>1:1</button></Tip>
      </span>,
    );
  }, [scale, minScale, zoomTo, reset, setControls]);
  useEffect(() => () => setControls(null), [setControls]);

  const larger = !!natural && !!box && !!view && (natural.w * view.scale > box.w + 1 || natural.h * view.scale > box.h - box.top - box.bottom + 1);
  return {
    stage, scale,
    stageProps: {
      "data-pan": larger || undefined, "data-zoomed": (view && view.scale > fit * 1.01) || undefined,
      onPointerDown, onPointerMove, onPointerUp, onPointerCancel: onPointerUp, onDoubleClick,
    },
    place: natural && view ? { width: natural.w, height: natural.h, transform: `translate(-50%, -50%) translate(${view.x}px, ${view.y}px) scale(${view.scale})` } : null,
  };
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
        : !doc || width <= 0 ? <div className={css2.fpPlain}><span className={waitingCss.spinner} aria-hidden="true" /></div>
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

/** Put at the end of a previewed HTML file: its frame tells the preview when a mouse moves over it (at most a few times a second). */
const TELL_MOVES = `<script>{let t=0;addEventListener("pointermove",(e)=>{if(e.pointerType!=="mouse"||e.timeStamp-t<200)return;t=e.timeStamp;parent.postMessage({stillfailPreview:"move"},"*")},{capture:true,passive:true})}</script>`;

/** Above this a file shows as plain text, unhighlighted; above the next, only its start. */
const HIGHLIGHT_LIMIT = 256 * 1024;
const SHOW_LIMIT = 2 * 1024 * 1024;
const TABLE_ROWS = 2000;

function TextViewer({ blob, kind, language, name, setControls, onMove }: {
  blob: Blob; kind: PreviewKind; language: string | undefined; name: string; setControls(c: ReactNode): void; onMove(): void;
}) {
  const frame = useRef<HTMLIFrameElement>(null);
  const moved = useRef(onMove);
  moved.current = onMove;
  useEffect(() => {
    const onMessage = (e: MessageEvent) => {
      if (e.source === frame.current?.contentWindow && (e.data as { stillfailPreview?: string } | null)?.stillfailPreview === "move") moved.current();
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
  if (text === null) return <div className={css2.fpNote}><span className={waitingCss.spinner} aria-hidden="true" />{t("web-main.preview.loading")}</div>;
  let content: ReactNode;
  if (kind === "html" && !source) {
    // Its scripts run, but in an origin of its own: nothing of still.fail's is reachable from it.
    // A fragment an agent wrote to be drawn in a message (Viz.tsx) is shown the same way, in still.fail's stylesheet.
    // A mouse moving over it is the frame's, not the preview's: the frame tells, so the bars wake as they do over an image.
    content = <iframe ref={frame} className={`${css2.fpFrame} fp-html`} sandbox="allow-scripts" srcDoc={(isFragment(text) ? vizDocument(text) : text) + TELL_MOVES} title={name} />;
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
