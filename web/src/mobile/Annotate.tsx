// One message, on a page of its own on a narrow screen (a long press on it in the chat opens it): its words to pick
// passages from and say something about, or to copy. A short hold picks the word under the finger and sliding on
// widens it (the browser's own selection is off: on a phone it fights the page's scrolling and its menus); the ends
// then have handles to move. What is said about each passage goes into the chat's draft as a quote with its comment.
import { useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode, type RefObject } from "react";
import { useParams } from "react-router";
import { useChat, type ChatMessage } from "../api.ts";
import { AgentWords, PersonWords } from "../Chat.tsx";
import { offerToDraft, type DraftQuote } from "../draft.ts";
import { Copy, Edit, Quote as QuoteIcon, Send } from "../icons.tsx";
import { stationBase, useStation } from "../station.tsx";
import { useApp } from "./app.tsx";
import { draftKeyOf } from "./ChatHost.tsx";
import { NavBar } from "./parts.tsx";
import { NoteBox, NoteCard } from "./Notes.tsx";
import * as css from "./Annotate.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as homeCss from "./styles/home.css.ts";
import { t } from "../i18n.ts";

/** A message's page, from the chat `key`'s list. */
export function annotatePath(station: string, key: string, ts: string): string {
  return `${stationBase(station)}/chats/${encodeURIComponent(key)}/messages/${encodeURIComponent(ts)}`;
}

/** How long a finger holds still before it picks rather than scrolls. */
const HOLD = 260;

interface Span { start: number; end: number }
interface Note extends Span { n: number; text: string; comment: string }

export function AnnotateScreen() {
  const app = useApp();
  const station = useStation();
  const { chat = "", ts = "" } = useParams();
  const view = useChat(station.address, { session: chat }).value;
  const m = view?.messages.find((x) => x.ts === ts);
  const author = m ? (m.mine ? t("web-mobile.annotate.you") : m.by.name) : "";
  return (
    <div className={`${pagesCss.mScreen} ${css.mAnnotate}`}>
      <NavBar back={t("web-mobile.nav.chat")} onBack={app.pop} title={t("web-mobile.annotate.title")} sub={m && <span className={barsCss.mNavbarNote}>{author}</span>} />
      {!view ? <p className={homeCss.mNote}>{t("web-mobile.reading")}</p>
        : !m ? <p className={homeCss.mNote}>{t("web-mobile.annotate.notFound")}</p>
        : <Annotating message={m} author={author} draftKey={draftKeyOf(station.address, chat)} />}
    </div>
  );
}

function Annotating({ message: m, author, draftKey }: { message: ChatMessage; author: string; draftKey: string }) {
  const app = useApp();
  const scroller = useRef<HTMLDivElement>(null);
  const sheet = useRef<HTMLDivElement>(null);
  const words = useRef<HTMLDivElement>(null);
  const [picked, setPicked] = useState<Span | null>(null);
  const [notes, setNotes] = useState<Note[]>([]);
  const [editing, setEditing] = useState<number | null>(null);
  const [dragging, setDragging] = useState(false);
  const counter = useRef(0);
  // Laid out again whenever the page's width changes (the places of handles, pins and bubbles are its words').
  const [, setLaidOut] = useState(0);
  useEffect(() => {
    const el = sheet.current;
    if (!el) return;
    const observer = new ResizeObserver(() => setLaidOut((n) => n + 1));
    observer.observe(el);
    return () => observer.disconnect();
  }, []);
  const role = m.authorKind === "agent" ? "agent" : "person";
  const all = () => words.current?.textContent ?? "";

  // The passages drawn over the words: the one being picked, those with notes, the one whose note is open.
  useLayoutEffect(() => {
    const root = words.current;
    const registry = highlights();
    if (!root || !registry) return;
    const make = (spans: Span[]) => new Highlight(...spans.map((s) => rangeOf(root, s)));
    registry.set("annotate-picked", make(picked ? [picked] : []));
    registry.set("annotate-note", make(notes.filter((x) => x.n !== editing)));
    registry.set("annotate-open", make(notes.filter((x) => x.n === editing)));
    return () => { registry.delete("annotate-picked"); registry.delete("annotate-note"); registry.delete("annotate-open"); };
  }, [picked, notes, editing]);

  usePicking(words, { picked, setPicked, setDragging, notes, onNote: (n) => { setPicked(null); setEditing(n); }, onTapAway: () => { setPicked(null); setEditing(null); } });

  const copy = (text: string) => {
    void navigator.clipboard.writeText(text).then(() => app.toast(t("web-mobile.annotate.copied")), () => app.toast(t("web-mobile.annotate.copyFailed")));
  };
  const note = () => {
    if (!picked || !words.current) return;
    const n = ++counter.current;
    const text = rangeOf(words.current, picked).toString().trim();
    setNotes((all) => [...all, { ...picked, n, text, comment: "" }]);
    setPicked(null);
    setEditing(n);
  };
  // A new note shows at the tray's end.
  const tray = useRef<HTMLOListElement>(null);
  const count = notes.length;
  useEffect(() => { tray.current?.scrollTo({ left: tray.current.scrollWidth, behavior: "smooth" }); }, [count]);
  // Back to a note's passage, its box open under it.
  const reveal = (n: number) => {
    const x = notes.find((y) => y.n === n);
    const el = scroller.current, root = words.current;
    setPicked(null);
    setEditing(n);
    if (!x || !el || !root) return;
    const r = rangeOf(root, x).getBoundingClientRect();
    el.scrollTo({ top: el.scrollTop + r.top - el.getBoundingClientRect().top - 96, behavior: "smooth" });
  };
  const remove = (n: number) => { setNotes((all) => all.filter((x) => x.n !== n)); setEditing(null); };
  const send = () => {
    const stamp = Date.now();
    const quote = (text: string, comment: string, n: number): DraftQuote => ({
      id: `note-${m.ts}-${n}-${stamp}`, author, text, comment, ...(m.ts ? { ts: m.ts } : {}), role,
    });
    const quotes = notes.length
      ? [...notes].sort((a, b) => a.start - b.start || a.n - b.n).map((x) => quote(x.text, x.comment.trim(), x.n))
      : [quote(plain(m.text), "", 0)];
    if (!offerToDraft(draftKey, { files: [], quotes })) { app.toast(t("web-mobile.annotate.cannotSend")); return; }
    app.pop();
  };

  // Where things go over the words: relative to the sheet they scroll with.
  const root = words.current;
  const base = sheet.current?.getBoundingClientRect();
  const rectsOf = (span: Span) => (root && base ? [...rangeOf(root, span).getClientRects()].filter((r) => r.width > 0).map((r) => shift(r, base)) : []);
  const pickedRects = picked ? rectsOf(picked) : [];
  const open = notes.find((x) => x.n === editing);
  const openRects = open ? rectsOf(open) : [];
  const width = sheet.current?.clientWidth ?? 0;
  // A place in the sheet that is on a whole pixel of the screen (the sheet itself may be between two).
  const whole = (y: number) => (base ? Math.round(y + base.top) - base.top : Math.round(y));
  const everything = picked !== null && picked.start === 0 && picked.end >= all().length;

  let bar: ReactNode = null;
  if (picked && !dragging && pickedRects.length) {
    const first = pickedRects[0]!, last = pickedRects[pickedRects.length - 1]!;
    // Over the passage; under it when the top of the page is too near.
    const room = base && scroller.current ? first.top + base.top - scroller.current.getBoundingClientRect().top : Infinity;
    const top = room < 60 ? last.bottom + 28 : first.top - 52;
    const x = Math.min(Math.max(pickedRects.length > 1 ? width / 2 : first.left + first.width / 2, 110), width - 110);
    bar = (
      <div className={`${css.mPickBar} ${pagesCss.mFloating}`} style={{ left: x, top }} onPointerDown={(e) => e.stopPropagation()}>
        <button type="button" onClick={note}><Edit size={15} />{t("web-mobile.annotate.title")}</button>
        <button type="button" onClick={() => { copy(root ? rangeOf(root, picked).toString() : ""); setPicked(null); }}><Copy size={15} />{t("common.copy")}</button>
        {!everything && <button type="button" onClick={() => setPicked({ start: 0, end: all().length })}>{t("web-mobile.annotate.selectAll")}</button>}
      </div>
    );
  }

  return (
    <>
      <div className={`${pagesCss.mScroll} ${css.mAnnotateScroll}`} ref={scroller} data-tray={notes.length > 0 || undefined}>
        <div className={css.mSheet} ref={sheet}>
          <div ref={words} className={css.mWords} data-role={role}>
            {m.authorKind === "person" ? <PersonWords text={m.text} /> : <AgentWords text={m.text} />}
          </div>
          {picked && pickedRects.length > 0 && <Handles words={words} rects={pickedRects} picked={picked} setPicked={setPicked} setDragging={setDragging} />}
          {notes.map((x) => {
            // In the margin, beside the passage's first line: never over the words.
            const first = rectsOf(x)[0];
            return first && <button key={x.n} type="button" className={css.mPin} data-open={x.n === editing || undefined} style={{ top: whole(first.top + first.height / 2) - 14 }}
              aria-label={t("web-mobile.notes.label", { n: x.n })} onClick={() => { setPicked(null); setEditing(x.n === editing ? null : x.n); }}>{x.n}</button>;
          })}
          {open && openRects.length > 0 && (
            <NoteBox key={open.n} note={open} style={{ top: openRects[openRects.length - 1]!.bottom + 10 }}
              onComment={(comment) => setNotes((all) => all.map((x) => (x.n === open.n ? { ...x, comment } : x)))}
              onDone={() => setEditing(null)} onRemove={() => remove(open.n)} />
          )}
          {bar}
        </div>
      </div>
      <div className={css.mFoot}>
        {/* The notes as they are made, gathered at the foot (the words may be long): a tap goes back to one. */}
        {notes.length > 0 && (
          <ol className={css.mTray} ref={tray}>
            {notes.map((x) => (
              <li key={x.n}>
                <NoteCard note={x} open={x.n === editing} onClick={() => reveal(x.n)} />
              </li>
            ))}
          </ol>
        )}
        <div className={css.mFootRow}>
          <button type="button" className={`${css.mFootBtn} ${pagesCss.mFloating}`} onClick={() => copy(m.text)}><Copy size={16} />{t("web-mobile.annotate.copyAll")}</button>
          <button type="button" className={`${css.mFootSend} ${pagesCss.mFloating}`} onClick={send}>
            {notes.length ? <><Send size={15} />{t("web-mobile.annotate.toChat", { n: notes.length })}</> : <><QuoteIcon size={15} />{t("web-mobile.annotate.quoteAll")}</>}
          </button>
        </div>
      </div>
    </>
  );
}

function Handles({ words, rects, picked, setPicked, setDragging }: {
  words: RefObject<HTMLDivElement | null>; rects: DOMRect[]; picked: Span; setPicked(span: Span): void; setDragging(on: boolean): void;
}) {
  const first = rects[0]!, last = rects[rects.length - 1]!;
  const drag = (end: "start" | "end") => (e: React.PointerEvent<HTMLElement>) => {
    e.stopPropagation();
    e.preventDefault();
    const root = words.current;
    if (!root) return;
    const el = e.currentTarget;
    el.setPointerCapture(e.pointerId);
    // Where the finger is on the handle, so that the end does not jump to under the finger.
    const box = el.getBoundingClientRect();
    const grab = { x: e.clientX - (end === "start" ? box.right : box.left), y: e.clientY - (end === "start" ? box.top : box.top) };
    const held = { ...picked };
    const lineHalf = (end === "start" ? first.height : last.height) / 2;
    const move = (ev: PointerEvent) => {
      setDragging(true);
      const at = offsetAt(root, ev.clientX - grab.x, ev.clientY - grab.y + (end === "start" ? lineHalf : -lineHalf));
      if (at === null) return;
      if (end === "start") held.start = Math.min(at, held.end - 1);
      else held.end = Math.max(at, held.start + 1);
      setPicked({ ...held });
    };
    const up = () => {
      el.removeEventListener("pointermove", move);
      el.removeEventListener("pointerup", up);
      el.removeEventListener("pointercancel", up);
      setDragging(false);
    };
    el.addEventListener("pointermove", move);
    el.addEventListener("pointerup", up);
    el.addEventListener("pointercancel", up);
  };
  return (
    <>
      <span className={css.mHandle} data-end="start" style={{ left: first.left, top: first.top, height: first.height }} onPointerDown={drag("start")} />
      <span className={css.mHandle} data-end="end" style={{ left: last.right, top: last.top, height: last.height }} onPointerDown={drag("end")} />
    </>
  );
}

/**
 * Picking on the words: a finger holds still a moment for the word under it, then slides to widen it (the page holds
 * its scroll meanwhile); moving at once scrolls. A mouse drags without holding. A tap on a passage with a note opens it;
 * elsewhere, it lets go of what is picked.
 */
function usePicking(words: RefObject<HTMLDivElement | null>, { picked, setPicked, setDragging, notes, onNote, onTapAway }: {
  picked: Span | null; setPicked(span: Span | null): void; setDragging(on: boolean): void; notes: Note[]; onNote(n: number): void; onTapAway(): void;
}) {
  const latest = useRef({ picked, notes, onNote, onTapAway });
  latest.current = { picked, notes, onNote, onTapAway };
  const segmenter = useMemo(() => new Intl.Segmenter(undefined, { granularity: "word" }), []);
  useEffect(() => {
    const root = words.current;
    if (!root) return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let from: { x: number; y: number } | null = null;
    let moved = false;
    let anchor: Span | null = null;
    const wordAt = (at: number): Span => {
      const text = root.textContent ?? "";
      for (const s of segmenter.segment(text)) {
        if (at >= s.index && at < s.index + s.segment.length) {
          // A word as it is; a run of spaces or a mark, only the character.
          return s.isWordLike ? { start: s.index, end: s.index + s.segment.length } : { start: at, end: Math.min(at + 1, text.length) };
        }
      }
      return { start: Math.max(0, text.length - 1), end: text.length };
    };
    const begin = (x: number, y: number) => {
      const at = offsetAt(root, x, y);
      if (at === null) return false;
      anchor = wordAt(at);
      setPicked(anchor);
      setDragging(true);
      return true;
    };
    const extend = (x: number, y: number) => {
      if (!anchor) return;
      const at = offsetAt(root, x, y);
      if (at === null) return;
      const w = wordAt(at);
      setPicked(w.start >= anchor.start ? { start: anchor.start, end: Math.max(anchor.end, w.end) } : { start: w.start, end: anchor.end });
    };
    const finish = () => {
      clearTimeout(timer);
      if (anchor) setDragging(false);
      anchor = null;
      from = null;
    };
    const tap = (x: number, y: number) => {
      const at = offsetAt(root, x, y);
      const { notes, onNote, onTapAway } = latest.current;
      const hit = at === null ? undefined : [...notes].reverse().find((n) => at >= n.start && at < n.end);
      if (hit) onNote(hit.n);
      else onTapAway();
    };

    const onTouchStart = (e: TouchEvent) => {
      if (e.touches.length !== 1) { finish(); return; }
      const t = e.touches[0]!;
      from = { x: t.clientX, y: t.clientY };
      moved = false;
      timer = setTimeout(() => {
        if (from && begin(from.x, from.y)) navigator.vibrate?.(8);
      }, HOLD);
    };
    const onTouchMove = (e: TouchEvent) => {
      const t = e.touches[0];
      if (!t || !from) return;
      if (anchor) {
        e.preventDefault();
        extend(t.clientX, t.clientY);
      } else if (Math.hypot(t.clientX - from.x, t.clientY - from.y) > 8) {
        moved = true;
        clearTimeout(timer);
      }
    };
    const onTouchEnd = (e: TouchEvent) => {
      const was = anchor;
      const start = from;
      finish();
      if (!was && !moved && start) {
        // A tap: its click (a link's) is kept from leaving the page; what it means here is decided now.
        e.preventDefault();
        tap(start.x, start.y);
      }
    };
    const onMouseDown = (e: PointerEvent) => {
      if (e.pointerType !== "mouse" || e.button !== 0) return;
      from = { x: e.clientX, y: e.clientY };
      moved = false;
    };
    const onMouseMove = (e: PointerEvent) => {
      if (e.pointerType !== "mouse" || !from) return;
      if (!anchor && Math.hypot(e.clientX - from.x, e.clientY - from.y) > 4) { moved = true; begin(from.x, from.y); }
      if (anchor) extend(e.clientX, e.clientY);
    };
    const onMouseUp = (e: PointerEvent) => {
      if (e.pointerType !== "mouse" || !from) return;
      const start = from, was = anchor;
      finish();
      if (!was && !moved) tap(start.x, start.y);
    };
    const onClick = (e: MouseEvent) => { if ((e.target as Element).closest("a")) e.preventDefault(); };
    const onMenu = (e: Event) => e.preventDefault();
    root.addEventListener("touchstart", onTouchStart, { passive: true });
    root.addEventListener("touchmove", onTouchMove, { passive: false });
    root.addEventListener("touchend", onTouchEnd, { passive: false });
    root.addEventListener("touchcancel", finish);
    root.addEventListener("pointerdown", onMouseDown);
    window.addEventListener("pointermove", onMouseMove);
    window.addEventListener("pointerup", onMouseUp);
    root.addEventListener("click", onClick);
    root.addEventListener("contextmenu", onMenu);
    return () => {
      clearTimeout(timer);
      root.removeEventListener("touchstart", onTouchStart);
      root.removeEventListener("touchmove", onTouchMove);
      root.removeEventListener("touchend", onTouchEnd);
      root.removeEventListener("touchcancel", finish);
      root.removeEventListener("pointerdown", onMouseDown);
      window.removeEventListener("pointermove", onMouseMove);
      window.removeEventListener("pointerup", onMouseUp);
      root.removeEventListener("click", onClick);
      root.removeEventListener("contextmenu", onMenu);
    };
  }, [words, segmenter, setPicked, setDragging]);
}

// ── places in the words ─────────────────────────────────────────────────

/** The page's custom highlights (CSS.highlights), where the browser has them. */
function highlights(): Map<string, Highlight> | null {
  return "highlights" in CSS ? (CSS as unknown as { highlights: Map<string, Highlight> }).highlights : null;
}

/** The range of `root`'s text from `start` to `end` (offsets in its textContent). */
function rangeOf(root: Node, { start, end }: Span): Range {
  const range = document.createRange();
  range.selectNodeContents(root);
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let at = 0, began = false;
  for (let node = walker.nextNode() as Text | null; node; node = walker.nextNode() as Text | null) {
    const length = node.data.length;
    if (!began && start <= at + length) { range.setStart(node, start - at); began = true; }
    if (began && end <= at + length) { range.setEnd(node, end - at); break; }
    at += length;
  }
  return range;
}

/** The offset in `root`'s text of the point (x, y) on the screen, or null when it is outside it. */
function offsetAt(root: Node, x: number, y: number): number | null {
  const doc = document as Document & { caretPositionFromPoint?(x: number, y: number): { offsetNode: Node; offset: number } | null };
  let node: Node, offset: number;
  const position = doc.caretPositionFromPoint?.(x, y);
  if (position) ({ offsetNode: node, offset } = position);
  else {
    const range = document.caretRangeFromPoint?.(x, y);
    if (!range) return null;
    node = range.startContainer;
    offset = range.startOffset;
  }
  if (!root.contains(node)) {
    // Past the words (above, below, beside): their start or their end, whichever is nearer.
    const box = (root as Element).getBoundingClientRect?.();
    if (!box) return null;
    return y < box.top ? 0 : y > box.bottom ? (root.textContent ?? "").length : null;
  }
  const range = document.createRange();
  range.selectNodeContents(root);
  range.setEnd(node, offset);
  return range.toString().length;
}

/** A rectangle on the screen, as a place in `base`. */
function shift(r: DOMRect, base: DOMRect): DOMRect {
  return new DOMRect(r.left - base.left, r.top - base.top, r.width, r.height);
}

/** A message's words as read, without markdown's marks: what a quote of the whole of it carries. */
function plain(text: string): string {
  return text.replace(/[`*#>]/g, "").replace(/\s+/g, " ").trim();
}
