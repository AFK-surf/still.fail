// A file sent in a chat, opened over the page: images to zoom and pan,
// video and audio to play, PDFs drawn by pdf.js, text and code
// highlighted, Markdown rendered, CSV as a table, HTML in a sandbox. Anything
// else says it cannot be shown and offers the download.
import { Dialog as RDialog } from "radix-ui";
import { createContext, useCallback, useContext, useEffect, useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { useApi, type Api, type Attachment } from "./api.ts";
import { ChevronLeft, ChevronRight, Close, Download, Minus, Plus } from "./icons.tsx";
import { placeFiles, Prose } from "./Prose.tsx";
import { fileLink } from "./Prose.css.ts";
import { useStation } from "./station.tsx";
import { Segmented } from "./ui.tsx";
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

function fetchFile(api: Api, station: string, sessionKey: string, file: Attachment, thumb = false): Promise<Blob> {
  const id = `${station}/${sessionKey}/${file.path}${thumb ? "#thumb" : ""}`;
  let blob = blobs.get(id);
  if (!blob) {
    // Typed by its name, so the browser plays and shows it whatever the station called it (a thumbnail is typed by the
    // station: it may be a JPEG of a PNG).
    const { type } = kindOf(file.name);
    blob = api.file(sessionKey, storedName(file), thumb).then((b) => (!thumb && type !== "application/octet-stream" && b.type !== type ? b.slice(0, b.size, type) : b));
    // A failure is not kept: the next look tries again.
    blob.catch(() => blobs.delete(id));
    blobs.set(id, blob);
    if (blobs.size > KEEP_BLOBS) blobs.delete(blobs.keys().next().value!);
  }
  return blob;
}

type Loaded = { state: "loading" } | { state: "error"; message: string } | { state: "ready"; blob: Blob; url: string };

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
    fetchFile(api, station.address, sessionKey, file, thumb).then((blob) => {
      if (!current) return;
      u = URL.createObjectURL(blob);
      setLoaded({ state: "ready", blob, url: u });
    }, (error: unknown) => {
      if (current) setLoaded({ state: "error", message: error instanceof Error ? error.message : String(error) });
    });
    return () => {
      current = false;
      if (u) URL.revokeObjectURL(u);
    };
  }, [api, station.address, sessionKey, file.path, enabled, thumb]);
  return loaded;
}

/** An image as a chat shows it (its thumbnail, where the station keeps one) as a blob URL, fetched once and kept while shown. */
export function useFileUrl(sessionKey: string, file: Attachment, enabled: boolean): string | null {
  const loaded = useFile(sessionKey, file, enabled, true);
  return loaded.state === "ready" ? loaded.url : null;
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
      <button type="button" className={fileLink} title={file.name} onClick={() => setOpen(true)}>{children}</button>
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
  // The neighbours are fetched ahead, so a step shows the next one at once.
  useEffect(() => {
    for (const n of [before, after]) if (n) fetchFile(api, station.address, n.sessionKey, n.file).catch(() => {});
  }, [api, station.address, before?.file.path, after?.file.path]);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey) return;
      if (e.key === "ArrowLeft" && before) step(before);
      else if (e.key === "ArrowRight" && after) step(after);
      else return;
      e.preventDefault();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [before, after, step]);
  const loaded = useFile(sessionKey, file, true);
  const known = kindOf(file.name);
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
  let body: ReactNode;
  if (loaded.state === "loading" || (kind === null && loaded.state === "ready")) body = <div className={css2.fpNote}><span className={waitingCss.spinner} aria-hidden="true" />正在载入…</div>;
  else if (loaded.state === "error") body = <div className={css2.fpNote}>载入失败：{loaded.message}</div>;
  else {
    const { url, blob } = loaded;
    switch (kind) {
      case "image": body = <ImageViewer key={file.path} url={url} file={file} setControls={setControls} onSwipe={(d) => step(d < 0 ? before : after)} />; break;
      case "video": body = <video className={css2.fpVideo} src={url} controls autoPlay playsInline />; break;
      case "audio": body = <div className={css2.fpAudio}><span className={css2.fpAudioName}>{file.name}</span><audio src={url} controls autoPlay /></div>; break;
      case "pdf": body = <PdfViewer blob={blob} />; break;
      case "markdown": case "csv": case "html": case "code": case "text":
        body = <TextViewer blob={blob} kind={kind} language={known.language} name={file.name} setControls={setControls} />; break;
      default: body = <div className={css2.fpNote}>这种文件没法在这里预览<a className={controlsCss.btn} href={url} download={file.name}><Download size={16} />下载</a></div>;
    }
  }
  return (
    <RDialog.Content className={css2.fp} data-kind={kind ?? undefined} aria-describedby={undefined}
      // The page itself takes focus, not its first button: no ring on the close button for a tap or click.
      onOpenAutoFocus={(e) => { e.preventDefault(); (e.currentTarget as HTMLElement | null)?.focus(); }}>
      <header className={css2.fpHead}>
        <div className={css2.fpTitle}>
          <RDialog.Title className={css2.fpName} title={file.path}>{file.name}</RDialog.Title>
          <span className={css2.fpMeta}>{images.length > 1 && at >= 0 ? `${at + 1} / ${images.length} · ` : ""}{fileSize(file.size)}{kind && KIND_LABEL[kind as PreviewKind] ? ` · ${KIND_LABEL[kind as PreviewKind]}` : ""}</span>
        </div>
        <div className={css2.fpTools}>{controls}</div>
        {loaded.state === "ready" && <a className={pagesCss.iconBtn} href={loaded.url} download={file.name} title="下载" aria-label="下载"><Download size={18} /></a>}
        <RDialog.Close className={pagesCss.iconBtn} aria-label="关闭" title="关闭（Esc）"><Close size={18} /></RDialog.Close>
      </header>
      <div className={css2.fpBody}>
        {body}
        {images.length > 1 && at >= 0 && <>
          <button type="button" className={css2.fpStep} data-side="before" aria-label="上一张" title="上一张（←）" disabled={!before} onClick={() => step(before)}><ChevronLeft size={22} /></button>
          <button type="button" className={css2.fpStep} data-side="after" aria-label="下一张" title="下一张（→）" disabled={!after} onClick={() => step(after)}><ChevronRight size={22} /></button>
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
 * An image fitted to the window, to zoom (wheel, pinch, double-click, the
 * bar's buttons, + − 0) around the pointer and drag about when larger than
 * the window. Fitted, a sideways swipe steps to the image before or after.
 */
function ImageViewer({ url, file, setControls, onSwipe }: { url: string; file: Attachment; setControls(c: ReactNode): void; onSwipe(direction: -1 | 1): void }) {
  const stage = useRef<HTMLDivElement>(null);
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(file.width && file.height ? { w: file.width, h: file.height } : null);
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

  // The wheel zooms; it has to be a listener that can stop the page scrolling.
  useEffect(() => {
    const el = stage.current;
    if (!el) return;
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      const v = viewRef.current;
      if (!v) return;
      // A trackpad's pinch comes as a wheel with ctrl, in small steps.
      const step = e.deltaMode === 1 ? e.deltaY * 16 : e.deltaY;
      const factor = Math.exp(-step * (e.ctrlKey ? 0.01 : 0.002));
      zoomTo(v.scale * factor, ...fromCentre(e.clientX, e.clientY));
    };
    el.addEventListener("wheel", onWheel, { passive: false });
    return () => el.removeEventListener("wheel", onWheel);
  }, [zoomTo]);

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
    if (single && e.type === "pointerup" && g.view.scale <= fit * 1.01) {
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
        <button type="button" className={pagesCss.iconBtn} aria-label="缩小" title="缩小（-）" disabled={scale <= minScale + 1e-6} onClick={() => zoomTo(scale / 1.25)}><Minus size={18} /></button>
        <button type="button" className={`${css2.fpToolText} ${css2.fpPercent}`} title="适应窗口（0）" onClick={reset}>{Math.round(scale * 100)}%</button>
        <button type="button" className={pagesCss.iconBtn} aria-label="放大" title="放大（+）" disabled={scale >= MAX_SCALE - 1e-6} onClick={() => zoomTo(scale * 1.25)}><Plus size={18} /></button>
        <button type="button" className={css2.fpToolText} title="原始大小（1）" onClick={() => zoomTo(1)}>1:1</button>
      </span>,
    );
  }, [scale, minScale, zoomTo, reset, setControls]);
  useEffect(() => () => setControls(null), [setControls]);

  const larger = !!natural && !!box && !!view && (natural.w * view.scale > box.w + 1 || natural.h * view.scale > box.h + 1);
  return (
    <div ref={stage} className={css2.fpStage} data-pan={larger || undefined} data-zoomed={(view && view.scale > fit * 1.01) || undefined}
      onPointerDown={onPointerDown} onPointerMove={onPointerMove} onPointerUp={onPointerUp} onPointerCancel={onPointerUp} onDoubleClick={onDoubleClick}>
      <img className={css2.fpImage} src={url} alt={file.name} draggable={false}
        onLoad={(e) => { const img = e.currentTarget; if (img.naturalWidth && img.naturalHeight) setNatural({ w: img.naturalWidth, h: img.naturalHeight }); }}
        style={natural && view ? { width: natural.w, height: natural.h, transform: `translate(-50%, -50%) translate(${view.x}px, ${view.y}px) scale(${view.scale})` } : { visibility: "hidden" }} />
    </div>
  );
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

/** Above this a file shows as plain text, unhighlighted; above the next, only its start. */
const HIGHLIGHT_LIMIT = 256 * 1024;
const SHOW_LIMIT = 2 * 1024 * 1024;
const TABLE_ROWS = 2000;

function TextViewer({ blob, kind, language, name, setControls }: { blob: Blob; kind: PreviewKind; language: string | undefined; name: string; setControls(c: ReactNode): void }) {
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
    content = <iframe className={`${css2.fpFrame} fp-html`} sandbox="allow-scripts" srcDoc={text} title={name} />;
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
