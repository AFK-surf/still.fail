// A text file of the drive read as a book (zdrive's reader, in still.fail's look): one column that scrolls, never
// pages; nothing over it until a tap (or, with a mouse, a move) brings the bars: the way back and the file's name at
// the top, at the bottom the chapter, a hairline track with a knob to jump anywhere, and 目录 (its chapters: Markdown's
// headings, a novel's 第X章), 搜索 (in the file, each place marked and stepped through) and 排版 (size, lines, face,
// paper). A plain-text novel hard-wrapped at a fixed width is joined back into its paragraphs; Markdown is never
// reflowed, and is drawn as a chat's is (Prose). Where it was left is kept on this device (`drive.place`) and opened at.
// On a phone the panels are its sheets. With a mouse it is a desktop's: a toolbar always over the text (the way back,
// the name, 目录 · 搜索 · 排版 · 夜间), the panels docked at its right, the arrow keys from chapter to chapter.
import { memo, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { Prose } from "../Prose.tsx";
import * as conversationCss from "../styles/conversation.css.ts";
import { Check, ChevronLeft, ChevronRight, Close, List, Search, Text as TextIcon } from "@stillfail/ui/icons.tsx";
import { useNarrow, useApp, SheetGrab, SheetHead, type MobileApp } from "../mobile/app.tsx";
import { Seg } from "../mobile/parts.tsx";
import { Segmented, Tip } from "../ui.tsx";
import { useDark } from "../theme.ts";
import { REST_MS, TAP_REST_MS } from "../FilePreview.tsx";
import { placeStrokes, strokeLayer } from "../strokes.ts";
import { download, placeAt, readWhole, sizeOf, usePlace, type At, type Got } from "./model.ts";
import { useBarOnScroll, ViewerBar, ViewerDownload, ViewerTool } from "../viewer/ViewerBar.tsx";
import { isHeading, search, type Book, type Chapter } from "./text.ts";
import { LINES, MARGINS, SIZES, setReaderStyle, useReaderStyle, type Paper } from "./readerStyle.ts";
import * as css from "./Reader.css.ts";
import { t } from "../i18n.ts";

/** The most of a file the reader holds (its front, saying so, when it is bigger). */
const MOST = 32 * 1024 * 1024;
const SERIF = "\"Songti SC\", \"STSong\", \"Noto Serif CJK SC\", \"Source Han Serif SC\", \"Noto Serif SC\", serif";
/** The system's own face (PingFang on a Mac, YaHei on Windows), not the app's: a book reads in what the machine reads in. */
const SANS = "system-ui, -apple-system, \"PingFang SC\", \"Hiragino Sans GB\", \"Microsoft YaHei\", \"Noto Sans CJK SC\", sans-serif";

type Loaded = { state: "loading"; got: Got | null } | { state: "error"; message: string } | { state: "ready"; book: Book; cut: boolean };

// The books read lately, while they are the same (their size and time): opened again, at once.
const books = new Map<string, Promise<{ book: Book; cut: boolean }>>();

/** A file read whole as text: one of a station's drive (`at`), read a part at a time, or one here already (`blob`, a
 * chat's file a preview has fetched). */
function loadBook(from: At | Blob, size: number, mtime: number, markdown: boolean, onProgress: (got: Got) => void): Promise<{ book: Book; cut: boolean }> {
  const key = from instanceof Blob ? null : `${from.station}\n${from.root}\n${from.path}\n${size}\n${mtime}`;
  let kept = key === null ? undefined : books.get(key);
  if (!kept) {
    kept = (async () => {
      const blob = from instanceof Blob ? from.slice(0, MOST) : await readWhole(from, size, { max: MOST, onProgress });
      const bytes = await blob.arrayBuffer();
      const cut = size > MOST;
      // Decoded, joined and searched for its chapters off the page's thread.
      const worker = new Worker(new URL("./textWorker.ts", import.meta.url), { type: "module" });
      try {
        return await new Promise<{ book: Book; cut: boolean }>((resolve, reject) => {
          worker.onmessage = (e: MessageEvent<{ book?: Book; error?: string }>) => (e.data.book ? resolve({ book: e.data.book, cut }) : reject(new Error(e.data.error ?? "")));
          worker.onerror = (e) => reject(new Error(e.message));
          worker.postMessage({ bytes, markdown, cut }, [bytes]);
        });
      } finally {
        worker.terminate();
      }
    })();
    if (key === null) return kept;
    kept.catch(() => books.delete(key));
    books.set(key, kept);
    if (books.size > 3) books.delete(books.keys().next().value!);
  }
  return kept;
}

function useBook(from: At | Blob, size: number, mtime: number, markdown: boolean): Loaded {
  const [loaded, setLoaded] = useState<Loaded>({ state: "loading", got: null });
  useEffect(() => {
    let live = true;
    setLoaded({ state: "loading", got: null });
    loadBook(from, size, mtime, markdown, (got) => { if (live) setLoaded({ state: "loading", got }); }).then(
      ({ book, cut }) => { if (live) setLoaded({ state: "ready", book, cut }); },
      (e: unknown) => { if (live) setLoaded({ state: "error", message: e instanceof Error ? e.message : String(e) }); },
    );
    return () => { live = false; };
  }, [from instanceof Blob ? from : `${from.station}\n${from.root}\n${from.path}`, size, mtime, markdown]); // eslint-disable-line react-hooks/exhaustive-deps
  return loaded;
}

/** A line of a book as drawn: where it starts, how much blank leads it (left out: paragraphs are indented by the page). */
interface Line { start: number; end: number; lead: number }
const lineAt = (book: Book, i: number): Line => {
  const start = book.starts[i]!;
  const end = i + 1 < book.starts.length ? book.starts[i + 1]! - 1 : book.text.length;
  let lead = 0;
  while (start + lead < end && " \t　﻿".includes(book.text[start + lead]!)) lead++;
  return { start, end, lead };
};
/** The line `offset` is in. */
function lineOf(book: Book, offset: number): number {
  let lo = 0, hi = book.starts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (book.starts[mid]! <= offset) lo = mid; else hi = mid - 1;
  }
  return lo;
}

/** A piece of the column: lines enough for about this many characters, laid out only near the screen. */
const PIECE = 1500;

/** The text, in pieces the browser lays out only as they come near (content-visibility): a novel's thousands of
 *  paragraphs drawn once, not again as the bars come and go. */
const TextBody = memo(function TextBody({ book }: { book: Book }) {
  const pieces = useMemo(() => {
    const out: number[][] = [];
    let piece: number[] = [], chars = 0;
    for (let i = 0; i < book.starts.length; i++) {
      const line = lineAt(book, i);
      piece.push(i);
      chars += line.end - line.start + 1;
      if (chars >= PIECE) { out.push(piece); piece = []; chars = 0; }
    }
    if (piece.length) out.push(piece);
    return out;
  }, [book]);
  return (
    <>
      {pieces.map((lines, n) => (
        <div key={n} className={css.piece}>
          {lines.map((i) => {
            const line = lineAt(book, i);
            const words = book.text.slice(line.start + line.lead, line.end);
            if (!words.trim()) return <p key={i} data-line={i} className={css.blank} />;
            return <p key={i} data-line={i} data-heading={isHeading(words.trim()) || undefined}>{words}</p>;
          })}
        </div>
      ))}
    </>
  );
});

const MarkdownBody = memo(function MarkdownBody({ text }: { text: string }) {
  return <div className={`${conversationCss.markdown} ${css.markdown}`}><Prose>{text}</Prose></div>;
});

/** What was found and which of it is shown. */
interface Found { query: string; ranges: Range[]; offsets: number[]; at: number }

/** What the panels act on, the same object while the reader is open (a phone's sheet is drawn outside it). */
interface Acts {
  book: () => Book | null;
  /** How far through it is (0 to 1). */
  share: () => number;
  /** The find opened in place of what is open. */
  openFind: () => void;
  chapters: () => { title: string; at: number }[];
  current: () => number;
  goChapter: (i: number) => void;
  find: (query: string) => Found | null;
  show: (found: Found, i: number) => void;
  close: () => void;
}

/**
 * A text read: one of a station's drive (`at`, where it was left kept on this device), or a chat's file a preview has
 * here already (`blob`, `onSave` downloading it).
 */
export function Reader({ at, blob, onSave, name, size, mtime, markdown, backLabel, onBack }: {
  at?: At | undefined; blob?: Blob | undefined; onSave?: (() => void) | undefined;
  name: string; size: number; mtime: number; markdown: boolean; backLabel: string; onBack: () => void;
}) {
  const narrow = useNarrow();
  const app = useAppSafe();
  const style = useReaderStyle();
  const dark = useDark();
  const paper = paperOf(style.paper, dark);
  const loaded = useBook(blob ?? at!, size, mtime, markdown);
  const book = loaded.state === "ready" ? loaded.book : null;
  const place = usePlace(at ?? null);
  // On a wide screen its bar goes as the text is read down, and comes back up with it (or the pointer at the top).
  const barOnScroll = useBarOnScroll();
  const scroller = useRef<HTMLDivElement>(null);
  const column = useRef<HTMLDivElement>(null);
  // Where the top of the screen is in the text (its offset), and so how far through it is.
  const [top, setTop] = useState(0);
  const [bars, setBars] = useState(false);
  const [panel, setPanel] = useState<"contents" | "find" | "layout" | null>(null);
  const [found, setFound] = useState<Found | null>(null);
  // Markdown's chapters are its headings as drawn.
  const [headings, setHeadings] = useState<HTMLElement[]>([]);
  useLayoutEffect(() => {
    if (!book?.markdown || !column.current) return;
    setHeadings([...column.current.querySelectorAll<HTMLElement>("h1, h2, h3")]);
  }, [book]);
  const length = book ? book.text.length : 0;

  /** The offset at the top of the screen (Markdown: its share of the scroll, as an offset). */
  const offsetNow = useCallback((): number => {
    const s = scroller.current, c = column.current;
    if (!s || !c || !book) return 0;
    if (book.markdown) {
      const most = s.scrollHeight - s.clientHeight;
      return most > 0 ? Math.round((s.scrollTop / most) * book.text.length) : 0;
    }
    const edge = s.getBoundingClientRect().top + 8;
    const pieces = c.children;
    let lo = 0, hi = pieces.length - 1;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (pieces[mid]!.getBoundingClientRect().bottom > edge) hi = mid; else lo = mid + 1;
    }
    const piece = pieces[lo];
    if (!piece) return 0;
    for (const p of piece.children) {
      const r = p.getBoundingClientRect();
      if (r.bottom <= edge) continue;
      const line = lineAt(book, Number((p as HTMLElement).dataset.line));
      const share = r.height > 0 ? Math.min(1, Math.max(0, (edge - r.top) / r.height)) : 0;
      return Math.round(line.start + share * (line.end - line.start));
    }
    return lineAt(book, Number((piece.lastElementChild as HTMLElement | null)?.dataset.line ?? 0)).end;
  }, [book]);

  /** The top of the screen to `offset` (Markdown: to that share of it). */
  const jump = useCallback((offset: number) => {
    const s = scroller.current, c = column.current;
    if (!s || !c || !book) return;
    const go = () => {
      if (book.markdown) {
        s.scrollTop = (offset / Math.max(1, book.text.length)) * (s.scrollHeight - s.clientHeight);
        return;
      }
      const i = lineOf(book, offset);
      const p = c.querySelector<HTMLElement>(`[data-line="${i}"]`);
      if (!p) return;
      const line = lineAt(book, i);
      const share = line.end > line.start ? (offset - line.start) / (line.end - line.start) : 0;
      const r = p.getBoundingClientRect();
      s.scrollTop += r.top - s.getBoundingClientRect().top - 8 + share * r.height;
    };
    go();
    // The pieces near it laid out now, as they are: once more where it really is.
    requestAnimationFrame(() => { go(); s.dispatchEvent(new Event("scroll")); });
  }, [book]);

  // Opened where it was left on this device (its share, when the file has changed length since).
  const opened = useRef(false);
  useLayoutEffect(() => {
    if (opened.current || !book || place === undefined) return;
    opened.current = true;
    if (!place) return;
    const where = place.of && place.of !== book.text.length ? (place.at / place.of) * book.text.length : place.at;
    jump(Math.min(where, book.text.length));
  }, [book, place, jump]);

  // Where it is, kept as it is read, and as the reader goes.
  const keep = useRef(0);
  const save = useCallback(() => { if (at && book && opened.current) placeAt(at, offsetNow(), book.text.length); }, [at, book, offsetNow]);
  useEffect(() => () => { clearTimeout(keep.current); save(); }, [save]);
  useEffect(() => {
    const away = () => save();
    addEventListener("pagehide", away);
    document.addEventListener("visibilitychange", away);
    return () => { removeEventListener("pagehide", away); document.removeEventListener("visibilitychange", away); };
  }, [save]);
  const frame = useRef(0);
  const onScroll = () => {
    if (frame.current) return;
    frame.current = requestAnimationFrame(() => {
      frame.current = 0;
      setTop(offsetNow());
      clearTimeout(keep.current);
      keep.current = window.setTimeout(save, 800);
    });
  };

  // ── chapters ──
  const chapters = useMemo<{ title: string; at: number }[]>(() => {
    if (!book) return [];
    if (book.markdown) return headings.map((h, i) => ({ title: h.textContent ?? "", at: i }));
    return book.chapters.map((c: Chapter) => ({ title: c.title, at: c.offset }));
  }, [book, headings]);
  /** The chapter the top of the screen is in (-1: before the first). */
  const current = useMemo(() => {
    if (!book || !chapters.length) return -1;
    if (book.markdown) {
      const s = scroller.current;
      if (!s) return -1;
      const edge = s.getBoundingClientRect().top + 24;
      let n = -1;
      headings.forEach((h, i) => { if (h.getBoundingClientRect().top <= edge) n = i; });
      return n;
    }
    let n = -1;
    for (let i = 0; i < chapters.length && chapters[i]!.at <= top + 1; i++) n = i;
    return n;
  }, [book, chapters, headings, top]);
  const goChapter = useCallback((i: number) => {
    const c = chapters[i];
    if (!c || !book) return;
    if (book.markdown) {
      const h = headings[i], s = scroller.current;
      if (h && s) { s.scrollTop += h.getBoundingClientRect().top - s.getBoundingClientRect().top - 12; s.dispatchEvent(new Event("scroll")); }
    } else jump(c.at);
  }, [chapters, book, headings, jump]);

  // ── finding ──
  const find = useCallback((query: string): Found | null => {
    const c = column.current;
    if (!book || !c || !query) return null;
    const ranges: Range[] = [], offsets: number[] = [];
    if (book.markdown) {
      const walk = document.createTreeWalker(c, NodeFilter.SHOW_TEXT);
      const q = query.toLowerCase();
      let seen = 0;
      for (let n = walk.nextNode(); n && ranges.length < 500; n = walk.nextNode()) {
        const text = (n.nodeValue ?? "").toLowerCase();
        for (let i = text.indexOf(q); i >= 0 && ranges.length < 500; i = text.indexOf(q, i + q.length)) {
          const r = document.createRange();
          r.setStart(n, i);
          r.setEnd(n, i + query.length);
          ranges.push(r);
          offsets.push(seen + i);
        }
        seen += text.length;
      }
    } else {
      for (const offset of search(book.text, query)) {
        const i = lineOf(book, offset);
        const line = lineAt(book, i);
        const p = c.querySelector<HTMLElement>(`[data-line="${i}"]`);
        const node = p?.firstChild;
        if (!node) continue;
        const from = Math.max(0, offset - line.start - line.lead);
        const r = document.createRange();
        r.setStart(node, Math.min(from, node.nodeValue?.length ?? 0));
        r.setEnd(node, Math.min(from + query.length, node.nodeValue?.length ?? 0));
        ranges.push(r);
        offsets.push(offset);
      }
    }
    return { query, ranges, offsets, at: 0 };
  }, [book]);
  const show = useCallback((f: Found, i: number) => {
    const s = scroller.current;
    const r = f.ranges[i];
    setFound({ ...f, at: i });
    if (!s || !r) return;
    const box = r.getBoundingClientRect();
    s.scrollTop += box.top - s.getBoundingClientRect().top - s.clientHeight * 0.32;
    s.dispatchEvent(new Event("scroll"));
  }, []);
  // What was found marked as a chat's find marks it: bold, the one shown with a stroke drawn under it.
  useEffect(() => {
    const marks = (CSS as unknown as { highlights?: Map<string, unknown> }).highlights;
    const H = (globalThis as unknown as { Highlight?: new (...r: Range[]) => unknown }).Highlight;
    if (!found || !marks || !H) return;
    marks.set("find-hit", new H(...found.ranges));
    const one = found.ranges[found.at];
    if (one) marks.set("find-current", new H(one));
    let layer: HTMLElement | null = null;
    const host = one?.startContainer.parentElement?.closest<HTMLElement>("p, li, h1, h2, h3, h4, td, blockquote") ?? null;
    if (one && host) {
      layer = strokeLayer(host);
      layer.dataset.find = "";
      placeStrokes(layer, host, [one], (svg) => { svg.dataset.current = ""; svg.dataset.fresh = ""; });
    }
    return () => { marks.delete("find-hit"); marks.delete("find-current"); layer?.remove(); };
  }, [found]);

  // ── the bars ──
  const resting = useRef(0);
  const onBars = useRef(false);
  const wake = useCallback((ms = REST_MS) => {
    // With a mouse the bars stay.
    if (!narrow) return;
    setBars(true);
    clearTimeout(resting.current);
    // With a mouse they go again once it rests (not over them); with a finger a tap takes them away.
    if (!narrow) resting.current = window.setTimeout(() => { if (!onBars.current) setBars(false); }, ms);
  }, [narrow]);
  useEffect(() => () => clearTimeout(resting.current), []);
  const tapAt = useRef<{ x: number; y: number } | null>(null);
  const onPointerUp = (e: React.PointerEvent) => {
    const at = tapAt.current;
    tapAt.current = null;
    if (!narrow || !at || Math.hypot(e.clientX - at.x, e.clientY - at.y) > 8) return;
    if ((e.target as Element).closest("a, button, input, summary")) return;
    if (!window.getSelection()?.isCollapsed) return;
    if (bars) { clearTimeout(resting.current); setBars(false); } else wake(TAP_REST_MS);
  };

  // ── panels ──
  const acts = useRef<Acts>(null as unknown as Acts);
  acts.current = { book: () => book, share: () => share, openFind: () => open("find"), chapters: () => chapters, current: () => current, goChapter, find, show, close: () => setFound(null) };
  const stable = useMemo<Acts>(() => ({
    book: () => acts.current.book(), share: () => acts.current.share(), openFind: () => acts.current.openFind(), chapters: () => acts.current.chapters(), current: () => acts.current.current(),
    goChapter: (i) => acts.current.goChapter(i), find: (q) => acts.current.find(q), show: (f, i) => acts.current.show(f, i), close: () => acts.current.close(),
  }), []);
  const open = (which: "contents" | "find" | "layout") => {
    if (narrow && app) {
      const sheet = which === "contents" ? { height: 0.72, draggable: true, content: () => <ContentsSheet acts={stable} app={app} /> }
        : which === "find" ? { height: 0.72, draggable: true, content: () => <FindSheet acts={stable} app={app} /> }
        : { height: 0.5, content: () => <LayoutSheet /> };
      app.sheet(sheet);
      return;
    }
    setPanel((p) => (p === which ? null : which));
    clearTimeout(resting.current);
  };
  // ⌘F / Ctrl+F finds in the file, Esc closes what is open over it.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "f" && !narrow) { e.preventDefault(); setPanel("find"); return; }
      // ← → from chapter to chapter (not while words are being typed).
      const typing = (e.target as Element | null)?.closest?.("input, textarea, [contenteditable]");
      if (!narrow && !typing && !e.metaKey && !e.ctrlKey && !e.altKey && (e.key === "ArrowLeft" || e.key === "ArrowRight")) {
        e.preventDefault();
        acts.current.goChapter(acts.current.current() + (e.key === "ArrowLeft" ? -1 : 1));
        return;
      }
      if (e.key === "Escape" && (panel || found)) { e.preventDefault(); if (panel) setPanel(null); else setFound(null); }
    };
    addEventListener("keydown", onKey);
    return () => removeEventListener("keydown", onKey);
  }, [narrow, panel, found]);

  const share = book ? (book.markdown ? shareNow(scroller.current) : length > 0 ? Math.min(1, top / length) : 0) : 0;
  const chapter = current >= 0 ? chapters[current]?.title : undefined;
  const shown = narrow ? bars : true;
  // With a mouse the keys scroll the text at once (space, page down, the arrows up and down).
  useEffect(() => { if (!narrow && book) scroller.current?.focus({ preventScroll: true }); }, [narrow, book]);
  const vars = { "--r-size": `${style.size}px`, "--r-line": style.line, "--r-margin": `${style.margin}px`, fontFamily: style.face === "serif" ? SERIF : SANS } as CSSProperties;

  let body: ReactNode;
  if (loaded.state === "error") body = <div className={css.note}>{t("web-pages.drive.reader.failed", { error: loaded.message })}</div>;
  else if (loaded.state === "loading") {
    body = (
      <div className={css.note}>
        <span>{loaded.got ? t("web-pages.drive.reader.reading", { got: sizeOf(loaded.got.loaded), of: sizeOf(loaded.got.total) }) : t("web-pages.drive.reader.opening")}</span>
        <span className={css.loadTrack}><span style={{ transform: `scaleX(${loaded.got && loaded.got.total ? loaded.got.loaded / loaded.got.total : 0})` }} /></span>
      </div>
    );
  } else if (!loaded.book.text.trim()) body = <div className={css.note}>{t("web-pages.drive.reader.empty")}</div>;
  else body = <>
    {loaded.book.markdown ? <MarkdownBody text={loaded.book.text} /> : <TextBody book={loaded.book} />}
    {loaded.cut && <p className={css.cut}>{t("web-pages.drive.reader.cut", { size: sizeOf(MOST) })}</p>}
  </>;

  return (
    <div className={css.reader} data-paper={paper} data-indent={style.indent || undefined} data-narrow={narrow || undefined} data-bars={shown || undefined} style={vars}
      onPointerMove={(e) => { if (e.pointerType === "mouse" && !narrow) wake(); barOnScroll.onPointerMove(e); }}>
      <div ref={scroller} className={css.scroller} tabIndex={-1} onScroll={(e) => { onScroll(); barOnScroll.onScroll(e); }} data-panel={(!narrow && panel) || undefined}
        onPointerDown={(e) => { tapAt.current = { x: e.clientX, y: e.clientY }; }} onPointerUp={onPointerUp}>
        <div ref={column} className={css.column}>{body}</div>
      </div>
      {/* With the bars away, how far through it is: a hairline along the bottom. */}
      <div className={css.hairline} aria-hidden="true"><span style={{ transform: `scaleX(${share})` }} /></div>
      {!narrow ? (
        <ViewerBar back={{ label: backLabel, onClick: onBack }} name={name} title={at?.path} hidden={barOnScroll.hidden && !panel}
          meta={[book ? [chapter, `${Math.round(share * 100)}%`].filter(Boolean).join(" · ") : null, sizeOf(size)].filter(Boolean).join(" · ")}
          tools={<>
            <ViewerTool label={t("web-pages.drive.reader.contents")} on={panel === "contents"} onClick={() => open("contents")}><List size={18} /></ViewerTool>
            <ViewerTool label={t("web-pages.drive.reader.find")} on={panel === "find"} onClick={() => open("find")}><Search size={18} /></ViewerTool>
            <ViewerTool label={t("web-pages.drive.reader.layout")} on={panel === "layout"} onClick={() => open("layout")}><TextIcon size={18} /></ViewerTool>
            <ViewerDownload name={name} onSave={onSave ?? (() => { if (at) void download(at, { name, size, type: "" }); })} />
          </>} />
      ) : <header className={css.top} data-shown={shown || undefined} inert={!shown}
        onPointerEnter={(e) => { if (e.pointerType === "mouse") { onBars.current = true; clearTimeout(resting.current); } }}
        onPointerLeave={(e) => { if (e.pointerType === "mouse") { onBars.current = false; wake(); } }}>
        <button type="button" className={css.back} onClick={onBack} aria-label={backLabel}><ChevronLeft size={20} /><span>{backLabel}</span></button>
        <span className={css.title}><b>{name}</b>{book && <small>{[chapter, `${Math.round(share * 100)}%`].filter(Boolean).join(" · ")}</small>}</span>
        <span className={css.topEnd}>
          <button type="button" className={css.topButton} aria-label={t("web-pages.drive.reader.find")} data-on={panel === "find" || undefined} onClick={() => open("find")}><Search size={20} /></button>
        </span>
      </header>}
      {found && (
        <div className={css.findStrip} data-bars={shown || undefined}>
          <span className={css.findWords}>{t("web-pages.drive.reader.foundAt", { query: found.query, at: found.ranges.length ? found.at + 1 : 0, n: found.ranges.length })}</span>
          <button type="button" className={css.chip} aria-label={t("web-pages.drive.reader.prevHit")} disabled={found.at <= 0} onClick={() => show(found, found.at - 1)}><ChevronLeft size={16} /></button>
          <button type="button" className={css.chip} aria-label={t("web-pages.drive.reader.nextHit")} disabled={found.at >= found.ranges.length - 1} onClick={() => show(found, found.at + 1)}><ChevronRight size={16} /></button>
          <button type="button" className={css.chip} aria-label={t("common.close")} onClick={() => setFound(null)}><Close size={14} /></button>
        </div>
      )}
      {narrow && <footer className={css.bottom} data-shown={bars || undefined} inert={!bars}
        onPointerEnter={(e) => { if (e.pointerType === "mouse") { onBars.current = true; clearTimeout(resting.current); } }}
        onPointerLeave={(e) => { if (e.pointerType === "mouse") { onBars.current = false; wake(); } }}>
        {chapters.length > 0 && (
          <div className={css.chapterRow}>
            <button type="button" className={css.chip} disabled={current <= 0} onClick={() => goChapter(current - 1)}>{t("web-pages.drive.reader.prevChapter")}</button>
            <span className={css.chapterName}>{chapter ?? chapters[0]!.title}</span>
            <button type="button" className={css.chip} disabled={current >= chapters.length - 1} onClick={() => goChapter(current + 1)}>{t("web-pages.drive.reader.nextChapter")}</button>
          </div>
        )}
        <div className={css.trackRow}>
          <Track share={share} onJump={(f) => { if (book) jump(Math.round(f * book.text.length)); }} />
          <span className={css.percent}>{Math.round(share * 100)}%</span>
        </div>
        <div className={css.tools}>
          <Tool icon={<List size={20} />} label={t("web-pages.drive.reader.contents")} on={panel === "contents"} onClick={() => open("contents")} />
          <Tool icon={<TextIcon size={20} />} label={t("web-pages.drive.reader.layout")} on={panel === "layout"} onClick={() => open("layout")} />
        </div>
      </footer>}
      {!narrow && panel && (
        <aside className={css.panel} onPointerEnter={() => { onBars.current = true; clearTimeout(resting.current); }} onPointerLeave={() => { onBars.current = false; }}>
          <div className={css.panelHead}>
            <b>{t(panel === "contents" ? "web-pages.drive.reader.contents" : panel === "find" ? "web-pages.drive.reader.find" : "web-pages.drive.reader.layout")}</b>
            {panel === "contents" && contentsNote(stable) && <span className={css.headNote}>{contentsNote(stable)}</span>}
            <Tip label={t("common.close")}><button type="button" className={css.chip} aria-label={t("common.close")} onClick={() => setPanel(null)}><Close size={14} /></button></Tip>
          </div>
          {panel === "contents" && <Contents acts={stable} done={() => undefined} />}
          {panel === "find" && <Find acts={stable} done={() => undefined} />}
          {panel === "layout" && <Layout narrow={false} />}
        </aside>
      )}
    </div>
  );
}

/** The phone app, where there is one (the reader is drawn on a phone's page or a desktop's). */
function useAppSafe(): MobileApp | null {
  try { return useApp(); } catch { return null; }
}

const shareNow = (s: HTMLElement | null) => {
  if (!s) return 0;
  const most = s.scrollHeight - s.clientHeight;
  return most > 0 ? Math.min(1, s.scrollTop / most) : 0;
};

function Tool({ icon, label, on, onClick }: { icon: ReactNode; label: string; on: boolean; onClick: () => void }) {
  return <button type="button" className={css.tool} data-on={on || undefined} onClick={onClick}>{icon}<span>{label}</span></button>;
}

/** How far through it is, to drag or tap to a place: the knob follows the finger, the text goes there as it lets go. */
function Track({ share, onJump }: { share: number; onJump: (share: number) => void }) {
  const box = useRef<HTMLDivElement>(null);
  const [drag, setDrag] = useState<number | null>(null);
  const at = (x: number) => {
    const r = box.current!.getBoundingClientRect();
    return Math.min(1, Math.max(0, (x - r.left) / r.width));
  };
  const shown = drag ?? share;
  return (
    <div ref={box} className={css.track} role="slider" aria-label={t("web-pages.drive.reader.where")} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(shown * 100)}
      onPointerDown={(e) => { e.currentTarget.setPointerCapture(e.pointerId); setDrag(at(e.clientX)); }}
      onPointerMove={(e) => { if (drag !== null) setDrag(at(e.clientX)); }}
      onPointerUp={(e) => { if (drag === null) return; const f = at(e.clientX); setDrag(null); onJump(f); }}
      onPointerCancel={() => setDrag(null)}>
      <span className={css.trackLine}><span style={{ transform: `scaleX(${shown})` }} /></span>
      <span className={css.knobRail} style={{ transform: `translateX(${shown * 100}%)` }}><span className={css.knob} data-held={drag !== null || undefined} /></span>
    </div>
  );
}

// ── the panels: a phone's sheets, or beside the text ───────────────────

/** How many chapters, and how far through it is: beside the contents' title. */
const contentsNote = (acts: Acts) => acts.chapters().length ? t("web-pages.drive.reader.contentsNote", { n: acts.chapters().length, read: Math.round(acts.share() * 100) }) : undefined;

function ContentsSheet({ acts, app }: { acts: Acts; app: MobileApp }) {
  const note = contentsNote(acts);
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.drive.reader.contents")} trailing={note ? <span className={css.headNote}>{note}</span> : undefined} />
      <Contents acts={acts} done={() => app.sheet(null)} />
    </>
  );
}

/** The chapters, numbered, the one being read marked; finding in the whole text from its top. */
function Contents({ acts, done }: { acts: Acts; done: () => void }) {
  const chapters = acts.chapters();
  const current = acts.current();
  const list = useRef<HTMLDivElement>(null);
  // Opened at the chapter being read.
  useLayoutEffect(() => { list.current?.querySelector("[data-current]")?.scrollIntoView({ block: "center" }); }, []);
  return (
    <div ref={list} className={css.panelList}>
      <button type="button" className={`${css.panelRow} ${css.findRow}`} onClick={() => acts.openFind()}><Search size={16} /><span>{t("web-pages.drive.reader.findPlaceholder")}</span></button>
      {!chapters.length && <p className={css.panelNote}>{t("web-pages.drive.reader.noChapters")}</p>}
      {chapters.map((c, i) => (
        <button key={i} type="button" className={`${css.panelRow} ${css.chapterLine}`} data-current={i === current || undefined} onClick={() => { acts.goChapter(i); done(); }}>
          <small>{i + 1}</small><span>{c.title}</span>{i === current && <Check size={14} />}
        </button>
      ))}
    </div>
  );
}

function FindSheet({ acts, app }: { acts: Acts; app: MobileApp }) {
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.drive.reader.find")} />
      <Find acts={acts} done={() => app.sheet(null)} />
    </>
  );
}

/** Words to find in the file: each place it is, in a line of its text, to go to. */
function Find({ acts, done }: { acts: Acts; done: () => void }) {
  const [query, setQuery] = useState("");
  const [found, setFound] = useState<Found | null>(null);
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => { input.current?.focus(); }, []);
  useEffect(() => {
    const q = query.trim();
    if (!q) { setFound(null); return; }
    const timer = setTimeout(() => setFound(acts.find(q)), 200);
    return () => clearTimeout(timer);
  }, [query, acts]);
  const book = acts.book();
  const snippet = (f: Found, i: number): ReactNode => {
    const range = f.ranges[i]!;
    const text = book && !book.markdown ? book.text : (range.startContainer.nodeValue ?? "");
    const at = book && !book.markdown ? f.offsets[i]! : range.startOffset;
    const from = Math.max(0, at - 14), to = Math.min(text.length, at + f.query.length + 30);
    return <>{from > 0 && "…"}{text.slice(from, at).replace(/\s+/g, " ")}<b>{text.slice(at, at + f.query.length)}</b>{text.slice(at + f.query.length, to).replace(/\s+/g, " ")}</>;
  };
  return (
    <div className={css.findPanel}>
      <input ref={input} className={css.findInput} value={query} placeholder={t("web-pages.drive.reader.findPlaceholder")} enterKeyHint="search"
        onChange={(e) => setQuery(e.target.value)}
        onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && found?.ranges.length) { acts.show(found, 0); done(); } }} />
      {found && <p className={css.panelNote}>{found.ranges.length ? t("web-pages.drive.reader.foundCount", { n: found.ranges.length }) : t("web-pages.drive.reader.notFound")}</p>}
      <div className={css.panelList}>
        {found?.ranges.slice(0, 200).map((_, i) => (
          <button key={i} type="button" className={css.panelRow} onClick={() => { acts.show(found, i); done(); }}>
            <span className={css.snippet}>{snippet(found, i)}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

function LayoutSheet() {
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.drive.reader.layout")} />
      <div className={css.layoutScroll}><Layout narrow /></div>
    </>
  );
}

/** The papers to pick: the light ones. Night is the app's dark (its theme, 外观), never picked here. */
const PAPERS: Exclude<Paper, "follow">[] = ["white", "green", "grey"];
type Light = "white" | "green" | "grey";
const isLight = (p: Paper): p is Light => p === "white" || p === "green" || p === "grey";

/** The paper shown: night while the app is dark, by day the light paper chosen (white until one is). */
function paperOf(chosen: Paper, dark: boolean): Exclude<Paper, "follow"> {
  return dark ? "night" : isLight(chosen) ? chosen : "white";
}

/** A paper picked: the day's (light) paper. The app's theme (外观) is never changed from here. */
function usePickPaper(): (paper: Exclude<Paper, "follow">) => void {
  return (paper) => setReaderStyle({ paper });
}

/** The paper under the text, its size, its lines' height, the room either side, its face, and whether paragraphs are
 *  indented: each changed as it is picked (`prefs.set {reader: {…}}`, that one setting). */
function Layout({ narrow }: { narrow: boolean }) {
  const style = useReaderStyle();
  const dark = useDark();
  const shownPaper = paperOf(style.paper, dark);
  const pickPaper = usePickPaper();
  const faces = [t("web-pages.drive.reader.serif"), t("web-pages.drive.reader.sans")];
  const indents = [t("web-pages.drive.reader.indent"), t("web-pages.drive.reader.flush")];
  const choose = (label: string, options: string[], at: number, pick: (i: number) => void) => narrow
    ? <Seg options={options} selected={at} onSelect={pick} fill />
    : <Segmented label={label} value={String(at)} onChange={(v) => pick(Number(v))} options={options.map((o, i) => ({ value: String(i), label: o }))} />;
  return (
    <div className={css.layout}>
      <div className={css.layoutBlock}>
        <span className={css.layoutLabel}>{t("web-pages.drive.reader.paper")}</span>
        <span className={css.papers}>
          {PAPERS.map((p) => (
            <button key={p} type="button" className={css.paperSwatch} data-paper={p} data-on={shownPaper === p || undefined} aria-pressed={shownPaper === p} onClick={() => pickPaper(p)}>
              <span aria-hidden="true">{t("web-pages.drive.reader.paperGlyph")}</span>
              <small>{t(`web-pages.drive.reader.paper.${p}`)}</small>
            </button>
          ))}
        </span>
      </div>
      <div className={css.layoutBlock}>
        <span className={css.layoutLabel}>{t("web-pages.drive.reader.size")}</span>
        <span className={css.sizeRow}>
          <button type="button" className={css.sizeKey} aria-label={t("web-pages.drive.reader.less", { what: t("web-pages.drive.reader.size") })} disabled={style.size <= SIZES.min} onClick={() => setReaderStyle({ size: style.size - 1 })}>A−</button>
          <b>{style.size}</b>
          <button type="button" className={css.sizeKey} aria-label={t("web-pages.drive.reader.more", { what: t("web-pages.drive.reader.size") })} disabled={style.size >= SIZES.max} onClick={() => setReaderStyle({ size: style.size + 1 })}>A+</button>
        </span>
      </div>
      <Slider label={t("web-pages.drive.reader.lines")} value={style.line} min={LINES.min} max={LINES.max} step={0.1} shown={(v) => `${Math.round(v * 100)}%`} onChange={(line) => setReaderStyle({ line })} />
      <Slider label={t("web-pages.drive.reader.margin")} value={style.margin} min={MARGINS.min} max={MARGINS.max} step={1} shown={(v) => String(v)} onChange={(margin) => setReaderStyle({ margin })} />
      <div className={css.layoutPair}>
        <div className={css.layoutBlock}>
          <span className={css.layoutLabel}>{t("web-pages.drive.reader.face")}</span>
          {choose(t("web-pages.drive.reader.face"), faces, style.face === "serif" ? 0 : 1, (i) => setReaderStyle({ face: i === 0 ? "serif" : "sans" }))}
        </div>
        <div className={css.layoutBlock}>
          <span className={css.layoutLabel}>{t("web-pages.drive.reader.indentLabel")}</span>
          {choose(t("web-pages.drive.reader.indentLabel"), indents, style.indent ? 0 : 1, (i) => setReaderStyle({ indent: i === 0 }))}
        </div>
      </div>
    </div>
  );
}

/** A value along a hairline with a knob: dragged or tapped; the value kept as the finger lets go. */
function Slider({ label, value, min, max, step, shown, onChange }: { label: string; value: number; min: number; max: number; step: number; shown: (v: number) => string; onChange: (v: number) => void }) {
  const box = useRef<HTMLSpanElement>(null);
  const [drag, setDrag] = useState<number | null>(null);
  const at = (x: number) => {
    const r = box.current!.getBoundingClientRect();
    const v = min + Math.min(1, Math.max(0, (x - r.left) / r.width)) * (max - min);
    return Math.round(Math.round(v / step) * step * 10) / 10;
  };
  const now = drag ?? value;
  const share = (now - min) / (max - min);
  return (
    <div className={css.sliderRow}>
      <span className={css.layoutLabel}>{label}</span>
      <span ref={box} className={css.slider} role="slider" aria-label={label} aria-valuemin={min} aria-valuemax={max} aria-valuenow={now} tabIndex={0}
        onKeyDown={(e) => { if (e.key === "ArrowLeft" || e.key === "ArrowRight") { e.preventDefault(); onChange(Math.min(max, Math.max(min, Math.round((value + (e.key === "ArrowLeft" ? -step : step)) * 10) / 10))); } }}
        onPointerDown={(e) => { e.currentTarget.setPointerCapture(e.pointerId); setDrag(at(e.clientX)); }}
        onPointerMove={(e) => { if (drag !== null) setDrag(at(e.clientX)); }}
        onPointerUp={(e) => { if (drag === null) return; const v = at(e.clientX); setDrag(null); if (v !== value) onChange(v); }}
        onPointerCancel={() => setDrag(null)}>
        <span className={css.sliderLine}><span style={{ transform: `scaleX(${share})` }} /></span>
        <span className={css.knobRail} style={{ transform: `translateX(${share * 100}%)` }}><span className={css.sliderKnob} data-held={drag !== null || undefined} /></span>
      </span>
      <b className={css.sliderValue}>{shown(now)}</b>
    </div>
  );
}
