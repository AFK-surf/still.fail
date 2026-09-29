// A file sent in a chat, opened over the page: images to zoom and pan,
// video and audio to play, PDFs drawn by pdf.js, text and code
// highlighted, Markdown rendered, CSV as a table, HTML in a sandbox. Anything
// else says it cannot be shown and offers the download.
import { Dialog as RDialog } from "radix-ui";
import { createContext, useCallback, useContext, useEffect, useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { useApi, type Api, type Attachment, type FileProgress } from "./api.ts";
import { ChevronLeft, ChevronRight, Close, Download, Minus, Plus } from "./icons.tsx";
import { placeFiles, Prose } from "./Prose.tsx";
import { isFragment, vizDocument } from "./Viz.tsx";
import { fileLink } from "./Prose.css.ts";
import { useStation } from "./station.tsx";
import { Segmented, Tip } from "./ui.tsx";
import { VideoViewer } from "./VideoViewer.tsx";
import { useImageMarks } from "./annotate/ImageMarks.tsx";
import { useBackClose } from "./backClose.ts";
import type { PDFDocumentLoadingTask, PDFDocumentProxy, RenderTask } from "pdfjs-dist";
import * as css2 from "./FilePreview.css.ts";
import * as waitingCss from "./styles/waiting.css.ts";
import * as controlsCss from "./styles/controls.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";

export function fileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
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
    blob = api.file(sessionKey, storedName(file), thumb, on ? (got) => { on.got = got; on.watchers.forEach((w) => w(got)); } : undefined)
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
      setLoaded({ state: "ready", blob, url: u });
    }, (error: unknown) => {
      if (current) setLoaded({ state: "error", message: error instanceof Error ? error.message : String(error) });
    });
    return () => {
      current = false;
      on?.watchers.delete(watch);
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
  useBackClose(open, onClose);
  return (
    <RDialog.Root open={open} onOpenChange={(o) => { if (!o) onClose(); }}>
      <RDialog.Portal>
        {open && <Viewer onClose={onClose} sessionKey={sessionKey} file={file} />}
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

function Viewer({ onClose, ...opened }: { onClose(): void; sessionKey: string; file: Attachment }) {
  const [{ sessionKey, file }, setShown] = useState<Shown>(opened);
  const gallery = useContext(Gallery);
  const images = isImage(file.name) ? gallery?.() ?? [] : [];
  const at = images.findIndex((i) => i.file.path === file.path);
  const before = at > 0 ? images[at - 1] : undefined;
  const after = at >= 0 ? images[at + 1] : undefined;
  const api = useApi();
  const station = useStation();
  const step = useCallback((to: Shown | undefined) => { if (to) setShown(to); }, []);
  // An image being marked: its bar stays, and it stays the one shown.
  const [marking, setMarking] = useState(false);
  // The neighbours are fetched ahead, so a step shows the next one at once.
  useEffect(() => {
    for (const n of [before, after]) if (n) fetchFile(api, station.address, n.sessionKey, n.file).catch(() => {});
  }, [api, station.address, before?.file.path, after?.file.path]);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey || marking) return;
      if (e.key === "ArrowLeft" && before) step(before);
      else if (e.key === "ArrowRight" && after) step(after);
      else return;
      e.preventDefault();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [before, after, step, marking]);
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
    body = <ImageViewer key={file.path} url={loaded.state === "ready" ? loaded.url : thumb!} file={file} setControls={setControls} onSwipe={(d) => step(d < 0 ? before : after)}
      waiting={loaded.state === "loading"} onMarking={setMarking} onClose={onClose} />;
  } else if (loaded.state === "loading" || (kind === null && loaded.state === "ready")) {
    body = <div className={css2.fpNote}>{loaded.state === "loading" && loaded.got ? <Progress got={loaded.got} size={file.size} /> : <><span className={waitingCss.spinner} aria-hidden="true" />正在载入…</>}</div>;
  }
  else if (loaded.state === "error") body = <div className={css2.fpNote}>载入失败：{loaded.message}</div>;
  else {
    const { url, blob } = loaded;
    switch (kind) {
      case "image": body = <ImageViewer key={file.path} url={url} file={file} setControls={setControls} onSwipe={(d) => step(d < 0 ? before : after)} onMarking={setMarking} onClose={onClose} />; break;
      case "video": body = <VideoViewer key={file.path} url={url} blob={blob} name={file.name} />; break;
      case "audio": body = <div className={css2.fpAudio}><span className={css2.fpAudioName}>{file.name}</span><audio src={url} controls autoPlay /></div>; break;
      case "pdf": body = <PdfViewer blob={blob} />; break;
      case "markdown": case "csv": case "html": case "code": case "text":
        body = <TextViewer blob={blob} kind={kind} language={known.language} name={file.name} setControls={setControls} onMove={wake} />; break;
      default: body = <div className={css2.fpNote}>这种文件没法在这里预览<a className={controlsCss.btn} href={url} download={file.name}><Download size={16} />下载</a></div>;
    }
  }
  return (
    <RDialog.Content className={css2.fp} data-kind={kind ?? undefined} aria-describedby={undefined} data-awake={awake || coming !== undefined || marking || undefined}
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
      <header ref={head} className={css2.fpHead}
        onPointerEnter={(e) => { if (e.pointerType !== "mouse") return; onBar.current = true; clearTimeout(resting.current); setAwake(true); }}
        onPointerLeave={(e) => { if (e.pointerType !== "mouse") return; onBar.current = false; wake(); }}>
        <div className={css2.fpTitle}>
          <Tip label={file.path}><RDialog.Title className={css2.fpName}>{file.name}</RDialog.Title></Tip>
          <span className={css2.fpMeta}>{images.length > 1 && at >= 0 ? `${at + 1} / ${images.length} · ` : ""}{fileSize(file.size)}{kind && KIND_LABEL[kind as PreviewKind] ? ` · ${KIND_LABEL[kind as PreviewKind]}` : ""}</span>
        </div>
        {coming !== undefined && <Progress got={coming} size={file.size} inBar />}
        {controls}
        {marking ? null : loaded.state === "ready"
          ? <Tip label="下载"><a className={pagesCss.iconBtn} href={loaded.url} download={file.name} aria-label="下载"><Download size={18} /></a></Tip>
          // Its place kept until it comes.
          : <span className={pagesCss.iconBtn} aria-hidden="true" style={{ visibility: "hidden" }}><Download size={18} /></span>}
        <Tip label="关闭（Esc）"><RDialog.Close className={pagesCss.iconBtn} aria-label="关闭"><Close size={18} /></RDialog.Close></Tip>
      </header>
      <div className={css2.fpBody}>
        {body}
        {images.length > 1 && at >= 0 && !marking && <>
          <Tip label="上一张（←）"><button type="button" className={css2.fpStep} data-side="before" aria-label="上一张" disabled={!before} onClick={() => step(before)}><ChevronLeft size={22} /></button></Tip>
          <Tip label="下一张（→）"><button type="button" className={css2.fpStep} data-side="after" aria-label="下一张" disabled={!after} onClick={() => step(after)}><ChevronRight size={22} /></button></Tip>
        </>}
      </div>
    </RDialog.Content>
  );
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

const KIND_LABEL: Partial<Record<PreviewKind, string>> = { image: "图片", video: "视频", audio: "音频", pdf: "PDF", markdown: "Markdown", csv: "表格", html: "网页", code: "代码", text: "文本" };

// ── images: zoom and pan ───────────────────────────────────────────────

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
function ImageViewer({ url, file, setControls, onSwipe, waiting = false, onMarking, onClose }:
  { url: string; file: Attachment; setControls(c: ReactNode): void; onSwipe(direction: -1 | 1): void; waiting?: boolean; onMarking(on: boolean): void; onClose(): void }) {
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(file.width && file.height ? { w: file.width, h: file.height } : null);
  const [zoomControls, setZoomControls] = useState<ReactNode>(null);
  const [marksOn, setMarksOn] = useState(false);
  const zoom = useZoom(natural, setZoomControls, marksOn ? undefined : onSwipe);
  const marks = useImageMarks({ url: waiting ? null : url, name: file.name, natural, scale: zoom.scale, pass: zoom.stageProps, onDone: onClose });
  useEffect(() => { setMarksOn(marks.on); onMarking(marks.on); }, [marks.on, onMarking]);
  useEffect(() => () => onMarking(false), [onMarking]);
  useEffect(() => { setControls(marks.on ? marks.bar : <>{zoomControls}{marks.bar}</>); }, [marks.on, marks.bar, zoomControls, setControls]);
  useEffect(() => () => setControls(null), [setControls]);
  return (
    <div ref={zoom.stage} className={css2.fpStage} {...zoom.stageProps}>
      <img className={css2.fpImage} src={url} alt={file.name} draggable={false} data-waiting={waiting || undefined}
        // A thumbnail's own size is not the image's: it only stands in the image's place.
        onLoad={(e) => { const img = e.currentTarget; if (img.naturalWidth && img.naturalHeight && (!waiting || !natural)) setNatural({ w: img.naturalWidth, h: img.naturalHeight }); }}
        style={zoom.place ?? { visibility: "hidden" }} />
      {marks.sheet(zoom.place)}
      {marks.tools}
    </div>
  );
}

/** How much of a file has come, out of its size (the station's, else the one sent with it); a bar that sweeps when neither is known. */
function Progress({ got, size, inBar = false }: { got: FileProgress | null | undefined; size: number; inBar?: boolean }) {
  const total = got?.total ?? (size > 0 ? size : null);
  const part = got && total ? Math.min(1, got.loaded / total) : null;
  return (
    <div className={inBar ? css2.fpHeadProgress : css2.fpProgress} role="progressbar" aria-label="正在载入" aria-valuemin={0} aria-valuemax={100} aria-valuenow={part === null ? undefined : Math.round(part * 100)}>
      <span className={css2.fpProgressText}>{got && total ? <>正在载入 <b>{fileSize(got.loaded)}</b> / {fileSize(total)}</> : "正在载入…"}</span>
      <span className={css2.fpProgressTrack}><span className={css2.fpProgressBar} style={part === null ? undefined : { width: `${part * 100}%` }} data-unknown={part === null || undefined} /></span>
    </div>
  );
}

/**
 * Zooming and panning a picture of `natural` size in a stage (an image, a video's frames): fitted to the window, to
 * zoom (pinch, ctrl/⌘ + wheel, double-click, the bar's buttons, + − 0 1) around the pointer and pan (drag, wheel) when
 * larger than the window. Fitted, a sideways swipe calls `onSwipe`. `place` positions the picture (absolutely, in the stage's centre).
 */
export function useZoom(natural: { w: number; h: number } | null, setControls: (c: ReactNode) => void, onSwipe?: (direction: -1 | 1) => void) {
  const stage = useRef<HTMLDivElement>(null);
  const [box, setBox] = useState<{ w: number; h: number } | null>(null);
  const [view, setView] = useState<View | null>(null);
  const viewRef = useRef<View | null>(null);
  viewRef.current = view;

  useLayoutEffect(() => {
    const el = stage.current;
    if (!el) return;
    const measure = () => setBox({ w: el.clientWidth, h: el.clientHeight });
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  // Fitted, it keeps a margin from the window's edges.
  const MARGIN = box && box.w < 640 ? 12 : 32;
  const fit = natural && box ? Math.min(1, (box.w - 2 * MARGIN) / natural.w, (box.h - 2 * MARGIN) / natural.h) : 1;
  const minScale = Math.min(fit, 1) / 2;

  /** Keeps a larger-than-window image covering the window, a smaller one centred. */
  const clamp = useCallback((v: View): View => {
    if (!natural || !box) return v;
    const scale = Math.min(MAX_SCALE, Math.max(minScale, v.scale));
    const spareX = Math.max(0, (natural.w * scale - box.w) / 2), spareY = Math.max(0, (natural.h * scale - box.h) / 2);
    return { scale, x: Math.min(spareX, Math.max(-spareX, v.x)), y: Math.min(spareY, Math.max(-spareY, v.y)) };
  }, [natural, box, minScale]);

  // Fitted when it first shows and whenever the window changes while still fitted.
  const fitted = useRef(true);
  useEffect(() => {
    if (!natural || !box) return;
    if (fitted.current || !viewRef.current) setView({ scale: fit, x: 0, y: 0 });
    else setView((v) => (v ? clamp(v) : v));
  }, [natural, box, fit, clamp]);

  /** To `scale`, the image's point under (px, py) — relative to the stage's centre — staying put. */
  const zoomTo = useCallback((scale: number, px = 0, py = 0) => {
    const v = viewRef.current;
    if (!v) return;
    const next = Math.min(MAX_SCALE, Math.max(minScale, scale));
    const k = next / v.scale;
    fitted.current = false;
    setView(clamp({ scale: next, x: px - (px - v.x) * k, y: py - (py - v.y) * k }));
  }, [clamp, minScale]);
  const reset = useCallback(() => { fitted.current = true; setView({ scale: fit, x: 0, y: 0 }); }, [fit]);

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
    fitted.current = false;
    setView(clamp({ scale, x: sx - (sx - g.view.x) * k + (x - g.x), y: sy - (sy - g.view.y) * k + (y - g.y) }));
  };
  const onPointerUp = (e: React.PointerEvent) => {
    const g = gesture.current;
    const single = pointers.current.size === 1 && g && g.distance === 0;
    pointers.current.delete(e.pointerId);
    start();
    // A swipe: one finger, mostly sideways, on an image not zoomed in (zoomed in, a drag pans).
    if (single && onSwipe && e.type === "pointerup" && g.view.scale <= fit * 1.01) {
      const dx = e.clientX - g.x, dy = e.clientY - g.y;
      if (Math.abs(dx) > 60 && Math.abs(dx) > 2 * Math.abs(dy)) onSwipe(dx > 0 ? -1 : 1);
    }
  };
  const onDoubleClick = (e: React.MouseEvent) => {
    const v = viewRef.current;
    if (!v) return;
    if (v.scale > fit * 1.01) reset();
    else zoomTo(Math.max(fit * 2.5, 1), ...fromCentre(e.clientX, e.clientY));
  };

  useEffect(() => {
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
  }, [zoomTo, reset]);

  const scale = view?.scale ?? fit;
  useEffect(() => {
    setControls(
      <span className={css2.fpZoom}>
        <Tip label="缩小（-）"><button type="button" className={pagesCss.iconBtn} aria-label="缩小" disabled={scale <= minScale + 1e-6} onClick={() => zoomTo(scale / 1.25)}><Minus size={18} /></button></Tip>
        <Tip label="适应窗口（0）"><button type="button" className={`${css2.fpToolText} ${css2.fpPercent}`} onClick={reset}>{Math.round(scale * 100)}%</button></Tip>
        <Tip label="放大（+）"><button type="button" className={pagesCss.iconBtn} aria-label="放大" disabled={scale >= MAX_SCALE - 1e-6} onClick={() => zoomTo(scale * 1.25)}><Plus size={18} /></button></Tip>
        <Tip label="原始大小（1）"><button type="button" className={css2.fpToolText} onClick={() => zoomTo(1)}>1:1</button></Tip>
      </span>,
    );
  }, [scale, minScale, zoomTo, reset, setControls]);
  useEffect(() => () => setControls(null), [setControls]);

  const larger = !!natural && !!box && !!view && (natural.w * view.scale > box.w + 1 || natural.h * view.scale > box.h + 1);
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
      {error ? <div className={css2.fpPlain}>这个 PDF 打不开：{error}</div>
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
  return <canvas ref={canvas} className={css2.fpPdfPage} style={shown} aria-label={`第 ${number} 页`} />;
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
      <Segmented label="显示方式" value={source ? "source" : "view"} onChange={(v) => setSource(v === "source")}
        options={[{ value: "view", label: "预览" }, { value: "source", label: "源码" }]} />,
    );
    return () => setControls(null);
  }, [rendered, source, setControls]);
  if (text === null) return <div className={css2.fpNote}><span className={waitingCss.spinner} aria-hidden="true" />正在载入…</div>;
  let content: ReactNode;
  if (kind === "html" && !source) {
    // Its scripts run, but in an origin of its own: nothing of ember's is reachable from it.
    // A fragment an agent wrote to be drawn in a message (Viz.tsx) is shown the same way, in ember's stylesheet.
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
      {cut && <div className={css2.fpCut}>文件较大，只显示前 {fileSize(SHOW_LIMIT)}，完整内容请下载。</div>}
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
          <thead><tr><th aria-label="行号" />{head.map((h, i) => <th key={i}>{h}</th>)}</tr></thead>
          <tbody>{body.slice(0, TABLE_ROWS).map((r, i) => <tr key={i}><td className={css2.fpRow}>{i + 1}</td>{head.map((_, j) => <td key={j}>{r[j] ?? ""}</td>)}</tr>)}</tbody>
        </table>
      </div>
      {more && <div className={css2.fpCut}>只显示前 {TABLE_ROWS} 行，完整内容请下载。</div>}
    </>
  );
}
