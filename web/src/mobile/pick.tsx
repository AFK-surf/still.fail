// Picking a passage of a message where it is, in a chat's list on a narrow screen (Chat.tsx): a finger held still on a
// message's words a moment picks the word under it, and sliding on while it is held widens the passage by words (the
// list holds still meanwhile; a finger that moves first scrolls it, as ever). Lifted, the passage has handles at its
// ends to move, and a small bar over it quotes it into the chat's draft, copies it, or takes all of the message. A tap
// anywhere lets go of it, as another page coming over the chat does; scrolling keeps it, its handles and bar following.
// The browser's own selection is off for a finger there (Chat.css.ts): on a phone it fights the list's scrolling and
// brings menus of its own. A mouse selects as ever (../Chat.tsx useSelectionQuote). The Android app's is its
// screens/MessagePick.kt.
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import type { Quote } from "../api.ts";
import { Copy, Quote as QuoteIcon } from "@stillfail/ui/icons.tsx";
import * as conversationCss from "../styles/conversation.css.ts";
import * as chatCss from "../styles/chat.css.ts";
import { hearPageShown, useApp } from "./app.tsx";
import * as css from "./pick.css.ts";
import { t } from "../i18n.ts";

/** How long a finger holds still on a message before it picks rather than scrolls (a link's menu comes after as long). */
export const HOLD = 480;
/** How far a finger may move and still be holding still, or tapping. */
const STILL = 8;
/** The page's custom highlight the picked passage is drawn with (pick.css.ts). */
const HIGHLIGHT = "chat-picked";

/** A stretch of a message's words: offsets in its words' text. */
interface Span { start: number; end: number }
/** What is picked: a passage of the message `ts` (its words found again as the list draws them anew), and whose it is. */
interface Picked { ts: string; span: Span; author: string; role: "agent" | "person" }

/**
 * Picking in the list `list` (its rows the wide screen's: ../Chat.tsx), what is picked quoted by `onQuote`. Answers the
 * handles and the bar, to be drawn beside the list in what it is placed in.
 */
export function usePick(list: RefObject<HTMLElement | null>, onQuote: (quote: Omit<Quote, "comment">) => void): ReactNode {
  const app = useApp();
  const [picked, setPicked] = useState<Picked | null>(null);
  // A finger widening it or moving one of its ends: the bar waits until it lifts.
  const [held, setHeld] = useState(false);
  const start = useRef<HTMLSpanElement>(null);
  const end = useRef<HTMLSpanElement>(null);
  const bar = useRef<HTMLDivElement>(null);
  const paint = useRef<HTMLDivElement>(null);
  const now = useRef({ picked, held });
  now.current = { picked, held };
  const letGo = () => { setPicked(null); setHeld(false); };

  /** The words of the message picked in, as the list draws them now (none while its row is not drawn). */
  const wordsNow = (): HTMLElement | null => {
    const el = list.current, p = now.current.picked;
    const row = el && p ? rowOf(el, p.ts) : null;
    return row ? wordsIn(row) : null;
  };

  // The passage drawn, its handles at its ends and the bar over it, where its words are now. Called as the list
  // scrolls or draws again: what it places, it places itself rather than through a render.
  const place = () => {
    const el = list.current, host = el?.parentElement, p = now.current.picked, registry = highlights();
    const parts = [start.current, end.current, bar.current, paint.current];
    const hide = () => { for (const x of parts) if (x) x.style.visibility = "hidden"; };
    const words = p ? wordsNow() : null;
    if (!el || !host || !p || !words) { registry?.delete(HIGHLIGHT); hide(); return; }
    const range = rangeOf(words, within(p.span, words));
    registry?.set(HIGHLIGHT, new Highlight(range));
    const rects = [...range.getClientRects()].filter((r) => r.width > 0);
    if (rects.length === 0) { hide(); return; }
    const first = rects[0]!, last = rects[rects.length - 1]!;
    // Placed in what the list is placed in; shown only where the list is seen: not under the bar over its top (its
    // scroll padding), nor the composer over its foot (its padding there).
    const base = host.getBoundingClientRect(), box = el.getBoundingClientRect(), style = getComputedStyle(el);
    // Paint the passage with ordinary elements, so it stays visible independently of CSS Highlight support.
    // Clip to the list, and omit parent rectangles duplicated by inline Markdown ranges.
    if (paint.current) {
      paint.current.style.visibility = "";
      paint.current.replaceChildren(...rects.filter((r, i) => !rects.some((q, j) => j !== i && q.left <= r.left && q.right >= r.right && q.top <= r.top && q.bottom >= r.bottom && (q.width > r.width || q.height > r.height || j < i))).map((r) => {
        const mark = document.createElement("span");
        const y = Math.max(r.top, box.top), bottom = Math.min(r.bottom, box.bottom);
        const x = Math.max(r.left, box.left), right = Math.min(r.right, box.right);
        mark.style.cssText = `position:absolute;left:${x - base.left}px;top:${y - base.top}px;width:${Math.max(0, right - x)}px;height:${Math.max(0, bottom - y)}px`;
        return mark;
      }));
    }
    const top = box.top + (parseFloat(style.scrollPaddingTop) || 0), bottom = box.bottom - (parseFloat(style.paddingBottom) || 0);
    const handle = (h: HTMLElement | null, line: DOMRect, x: number) => {
      if (!h) return;
      h.style.visibility = line.top >= top - 1 && line.bottom <= bottom + 1 ? "" : "hidden";
      h.style.left = `${x - base.left}px`;
      h.style.top = `${line.top - base.top}px`;
      h.style.height = `${line.height}px`;
    };
    handle(start.current, first, first.left);
    handle(end.current, last, last.right);
    const b = bar.current;
    if (!b) return;
    const seen = last.bottom > top && first.top < bottom;
    b.style.visibility = seen ? "" : "hidden";
    if (!seen) return;
    const w = b.offsetWidth, h = b.offsetHeight;
    // Over the passage, clear of its start's knob; under it, clear of its end's, when the list's top is too near; over
    // the words in view when the passage fills the list.
    let y = first.top - h - 16;
    if (y < top + 8) y = last.bottom + 16;
    if (y + h > bottom - 8) y = top + 8;
    const centre = rects.length > 1 ? box.left + box.width / 2 : first.left + first.width / 2;
    const x = Math.min(Math.max(centre - w / 2, base.left + 8), base.right - 8 - w);
    b.style.left = `${x - base.left}px`;
    b.style.top = `${y - base.top}px`;
  };
  useLayoutEffect(place);

  // Following the words while something is picked: as the list scrolls, changes its size or draws its rows anew.
  const on = picked !== null;
  useEffect(() => {
    const el = list.current;
    if (!on || !el) return;
    let frame = 0;
    const soon = () => { if (!frame) frame = requestAnimationFrame(() => { frame = 0; place(); }); };
    const sized = new ResizeObserver(soon);
    sized.observe(el);
    const drawn = new MutationObserver(soon);
    drawn.observe(el, { childList: true, subtree: true, characterData: true });
    el.addEventListener("scroll", soon, { passive: true });
    window.addEventListener("resize", soon);
    return () => {
      cancelAnimationFrame(frame);
      sized.disconnect();
      drawn.disconnect();
      el.removeEventListener("scroll", soon);
      window.removeEventListener("resize", soon);
      highlights()?.delete(HIGHLIGHT);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [on, list]);

  // A tap anywhere but on the handles and the bar lets go of it (a press that scrolls, or holds, does not), as another
  // page coming over the chat does.
  useEffect(() => {
    if (!on) return;
    let down: { x: number; y: number; at: number } | null = null;
    const ours = (e: Event) => e.target instanceof Element && e.target.closest("[data-pick]") !== null;
    const onDown = (e: PointerEvent) => { down = ours(e) ? null : { x: e.clientX, y: e.clientY, at: e.timeStamp }; };
    const onUp = (e: PointerEvent) => {
      if (down && e.timeStamp - down.at < HOLD && Math.hypot(e.clientX - down.x, e.clientY - down.y) <= STILL) letGo();
      down = null;
    };
    const onCancel = () => { down = null; };
    const unhear = hearPageShown(letGo);
    document.addEventListener("pointerdown", onDown, true);
    document.addEventListener("pointerup", onUp, true);
    document.addEventListener("pointercancel", onCancel, true);
    return () => {
      unhear();
      document.removeEventListener("pointerdown", onDown, true);
      document.removeEventListener("pointerup", onUp, true);
      document.removeEventListener("pointercancel", onCancel, true);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [on]);

  // A finger held on a message's words: the word under it, then wider as it slides. Touch events rather than pointer
  // ones: only these can keep the list from scrolling once the finger is picking.
  useEffect(() => {
    const el = list.current;
    if (!el) return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let from: { x: number; y: number } | null = null;
    let anchor: Span | null = null;
    let words: HTMLElement | null = null;
    // The click a browser may send as the finger that picked lifts: not a tap on what is under it.
    let swallow = 0;
    const begin = (row: HTMLElement, at: HTMLElement) => {
      const offset = from ? offsetAt(at, from.x, from.y) : null;
      if (offset === null) return;
      words = at;
      anchor = wordAt(at.textContent ?? "", offset);
      navigator.vibrate?.(8);
      setPicked({ ts: row.dataset.ts!, span: anchor, author: row.dataset.author!, role: row.dataset.role === "agent" ? "agent" : "person" });
      setHeld(true);
    };
    const widen = (x: number, y: number) => {
      if (!anchor || !words) return;
      const offset = offsetAt(words, x, y);
      if (offset === null) return;
      const w = wordAt(words.textContent ?? "", offset);
      const span = w.start >= anchor.start ? { start: anchor.start, end: Math.max(anchor.end, w.end) } : { start: w.start, end: anchor.end };
      setPicked((p) => p && { ...p, span });
    };
    const finish = () => {
      clearTimeout(timer);
      if (anchor) { setHeld(false); swallow = performance.now() + 400; }
      anchor = null;
      words = null;
      from = null;
    };
    const onTouchStart = (e: TouchEvent) => {
      finish();
      if (e.touches.length !== 1) return;
      const at = pickable(el, e.target);
      if (!at) return;
      const touch = e.touches[0]!;
      from = { x: touch.clientX, y: touch.clientY };
      timer = setTimeout(() => begin(at.row, at.words), HOLD);
    };
    const onTouchMove = (e: TouchEvent) => {
      const touch = e.touches[0];
      if (!touch || !from) return;
      if (anchor) {
        if (e.cancelable) e.preventDefault();
        widen(touch.clientX, touch.clientY);
      } else if (Math.hypot(touch.clientX - from.x, touch.clientY - from.y) > STILL) {
        clearTimeout(timer);
        from = null;
      }
    };
    const onClick = (e: MouseEvent) => {
      if (performance.now() > swallow) return;
      e.preventDefault();
      e.stopPropagation();
    };
    el.addEventListener("touchstart", onTouchStart, { passive: true });
    el.addEventListener("touchmove", onTouchMove, { passive: false });
    el.addEventListener("touchend", finish);
    el.addEventListener("touchcancel", finish);
    el.addEventListener("click", onClick, true);
    return () => {
      clearTimeout(timer);
      el.removeEventListener("touchstart", onTouchStart);
      el.removeEventListener("touchmove", onTouchMove);
      el.removeEventListener("touchend", finish);
      el.removeEventListener("touchcancel", finish);
      el.removeEventListener("click", onClick, true);
    };
  }, [list]);

  // An end moved by its handle; where the finger is on the handle's line is kept, so the end does not jump to under it.
  const drag = (which: "start" | "end") => (e: React.PointerEvent<HTMLElement>) => {
    e.stopPropagation();
    e.preventDefault();
    const p = now.current.picked;
    if (!p) return;
    const el = e.currentTarget;
    el.setPointerCapture(e.pointerId);
    setHeld(true);
    const box = el.getBoundingClientRect();
    const grab = { x: e.clientX - (box.left + box.width / 2), y: e.clientY - (box.top + box.height / 2) };
    const ends = { ...p.span };
    let moved = false;
    const move = (ev: PointerEvent) => {
      const words = wordsNow();
      if (!words || ev.pointerId !== e.pointerId) return;
      if (!moved && Math.hypot(ev.clientX - e.clientX, ev.clientY - e.clientY) < 3) return;
      moved = true;
      // The handle overlaps the caret being queried; let WebKit hit the words beneath it.
      const handles = [start.current, end.current];
      for (const h of handles) if (h) h.style.pointerEvents = "none";
      let at: number | null;
      try { at = offsetAt(words, ev.clientX - grab.x, ev.clientY - grab.y); }
      finally { for (const h of handles) if (h) h.style.pointerEvents = ""; }
      if (at === null) return;
      // Keep the last valid endpoint when crossing the other handle; forcing a one-code-unit span can split emoji.
      if (which === "start") { if (at >= ends.end) return; ends.start = at; }
      else { if (at <= ends.start) return; ends.end = at; }
      setPicked((q) => q && { ...q, span: { ...ends } });
    };
    const up = () => {
      el.removeEventListener("pointermove", move);
      el.removeEventListener("pointerup", up);
      el.removeEventListener("pointercancel", up);
      el.removeEventListener("lostpointercapture", up);
      setHeld(false);
    };
    el.addEventListener("pointermove", move);
    el.addEventListener("pointerup", up);
    el.addEventListener("pointercancel", up);
    el.addEventListener("lostpointercapture", up);
  };

  if (!picked) return null;
  const text = () => { const words = wordsNow(); return words ? rangeOf(words, within(picked.span, words)).toString() : ""; };
  const quote = () => {
    const said = text().trim();
    if (said) onQuote({ author: picked.author, text: said, ts: picked.ts, role: picked.role });
    letGo();
  };
  const copy = () => {
    navigator.clipboard.writeText(text()).then(() => app.toast(t("web-mobile.annotate.copied")), () => app.toast(t("web-mobile.annotate.copyFailed")));
    letGo();
  };
  const length = (wordsNow()?.textContent ?? "").length;
  const everything = picked.span.start === 0 && picked.span.end >= length;
  return (
    <>
      <div ref={paint} data-pick-paint="" className={css.mPickedPaint} aria-hidden="true" />
      <span ref={start} className={css.mHandle} data-end="start" data-pick="" onPointerDown={drag("start")} />
      <span ref={end} className={css.mHandle} data-end="end" data-pick="" onPointerDown={drag("end")} />
      {!held && (
        <div ref={bar} className={css.mPickBar} data-pick="" onContextMenu={(e) => e.preventDefault()}>
          <button type="button" onClick={quote}><QuoteIcon size={15} />{t("web-main.chat.quote")}</button>
          <button type="button" onClick={copy}><Copy size={15} />{t("common.copy")}</button>
          {!everything && <button type="button" onClick={() => setPicked({ ...picked, span: { start: 0, end: length } })}>{t("web-mobile.annotate.selectAll")}</button>}
        </div>
      )}
    </>
  );
}

// ── messages and places in their words ──────────────────────────────────

/** Where a press would do something of its own rather than pick: a link (its menu: Chat.tsx), a button, a file, a field. */
const OWN = "a, button, input, textarea, select, img, video, audio, iframe, canvas, [role=button]";

/** A message's words in its row: what is picked in (its bubble, its Markdown, its plain text). */
function wordsIn(row: Element): HTMLElement | null {
  return row.querySelector<HTMLElement>(`.${conversationCss.msgBubble}, .${conversationCss.markdown}, .${chatCss.msgPlain}`);
}

/** The row of the message `ts` in the list, as it is drawn now. */
function rowOf(list: HTMLElement, ts: string): HTMLElement | null {
  for (const row of list.querySelectorAll<HTMLElement>("[data-author][data-ts]")) if (row.dataset.ts === ts) return row;
  return null;
}

/**
 * The message whose words a press in the list is on, when it may pick there: a message of someone's with words (not
 * what still.fail says itself, nor one on its way), and not on what does its own thing in them.
 */
function pickable(list: HTMLElement, target: EventTarget | null): { row: HTMLElement; words: HTMLElement } | null {
  const at = target instanceof Element ? target : null;
  const row = at?.closest<HTMLElement>("[data-author][data-ts]");
  if (!at || !row || !list.contains(row)) return null;
  const words = wordsIn(row);
  if (!words || !words.contains(at) || at.closest(OWN) || !(words.textContent ?? "").trim()) return null;
  return { row, words };
}

/** The page's custom highlights (CSS.highlights), where the browser has them. */
function highlights(): Map<string, Highlight> | null {
  return "highlights" in CSS ? (CSS as unknown as { highlights: Map<string, Highlight> }).highlights : null;
}

let segmenter: Intl.Segmenter | undefined;
/**
 * The word at `at` in `text`, or the one just before it (past a line's end, the finger is on what ends it); on a mark,
 * the mark; on spaces (a line break), what is before them.
 */
function wordAt(text: string, at: number): Span {
  segmenter ??= new Intl.Segmenter(undefined, { granularity: "word" });
  const segments = segmenter.segment(text);
  for (const i of [at, at - 1]) {
    const s = i >= 0 ? segments.containing(i) : undefined;
    if (s?.isWordLike) return { start: s.index, end: s.index + s.segment.length };
  }
  let i = Math.min(at, text.length - 1);
  while (i > 0 && /\s/.test(text[i]!)) i--;
  const s = segments.containing(Math.max(0, i));
  return s ? { start: s.index, end: s.index + s.segment.length } : { start: 0, end: text.length };
}

/** `span` within what `root`'s text is now (a message's words may have changed since it was picked). */
function within(span: Span, root: Node): Span {
  const end = Math.min(span.end, (root.textContent ?? "").length);
  return { start: Math.min(span.start, end), end };
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

/** The offset in `root`'s text of the point (x, y) on the screen, or null when it is beside it. */
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
    // Past the words (above, below): their start or their end, whichever is nearer.
    const box = (root as Element).getBoundingClientRect?.();
    if (!box) return null;
    return y < box.top ? 0 : y > box.bottom ? (root.textContent ?? "").length : null;
  }
  const range = document.createRange();
  range.selectNodeContents(root);
  range.setEnd(node, offset);
  return range.toString().length;
}
