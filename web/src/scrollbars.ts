import * as css from "./scrollbars.css.ts";
import { drawnLag, paceFrames } from "./virtual/pace.ts";
// Scrollbars that float over what scrolls and take no room from it. With a mouse the system's bars are hidden
// (styles/global.css.ts) and one thin thumb per axis, drawn here, shows on any pane while it scrolls and while the pointer is
// where the pane's bar runs (along its right edge, or its foot), and can be dragged. Touch screens keep the system's own, which already float.
// A thumb is put beside the pane it is for (in the pane's parent), so it is layered as the pane is: a menu, a popover
// or a dialog over the pane is over its bar too.
// A pane with something floating over its foot (a chat's composer) or its top (the sidebar's frosted bands) says so with
// `scroll-padding-bottom` / `scroll-padding-top`, and its bar stays clear of it; a rounded pane's bar stays clear of its
// corners.

type Axis = "y" | "x";

const HIDE_AFTER = 900;
const MIN_THUMB = 28;
const INSET = 2;
const SIZE = 3;
/** How far in from the pane's edge the pointer brings out its bar. */
const NEAR = 12;

/** A corner's radius in px (one given in % is left as none). */
function radius(value: string): number {
  return value.includes("%") ? 0 : parseFloat(value) || 0;
}
/** How much of the pane's height, at its bottom, the vertical track leaves free: what floats over it there, or the
 * rounding of its corner (a rounded menu's bar stays inside its curve). */
function endOf(el: Element): number {
  if (el === document.scrollingElement) return 0;
  const s = getComputedStyle(el);
  return Math.max(parseFloat(s.scrollPaddingBottom) || 0, radius(s.borderBottomRightRadius));
}
/** How much of it, at its top, the vertical track leaves free. */
function startOf(el: Element): number {
  if (el === document.scrollingElement) return 0;
  const s = getComputedStyle(el);
  return Math.max(parseFloat(s.scrollPaddingTop) || 0, radius(s.borderTopRightRadius));
}
/** How far from the pane's right the vertical thumb stands beyond its inset: what lies along that edge (the
 * sidebar's edge line), said with `scroll-padding-right`. */
function rightOf(el: Element): number {
  if (el === document.scrollingElement) return 0;
  return parseFloat(getComputedStyle(el).scrollPaddingRight) || 0;
}
/** How much of the pane's width the horizontal track leaves free at its left and right: the rounding of those corners. */
function sidesOf(el: Element): [number, number] {
  if (el === document.scrollingElement) return [0, 0];
  const s = getComputedStyle(el);
  return [radius(s.borderBottomLeftRadius), radius(s.borderBottomRightRadius)];
}
/** Where a thumb runs along the pane, and how long it is: always inside the pane (between what floats over its top and
 * foot, and clear of rounded corners, while that leaves room for a thumb, over them in a pane too short for that). */
function trackOf(el: Element, axis: Axis, size: number, content: number): { start: number; track: number; length: number } {
  const [left, right] = axis === "x" ? sidesOf(el) : [0, 0];
  let start = axis === "y" ? startOf(el) : left;
  let track = axis === "y" ? size - start - endOf(el) : size - left - right;
  if (track < MIN_THUMB * 2) { start = 0; track = size; }
  const length = Math.min(track, Math.max(MIN_THUMB, (track * size) / content)) - INSET * 2;
  return { start, track, length };
}

/** The innermost element at or above `from` that scrolls along some axis. */
function scrollerOf(from: EventTarget | null): Element | null {
  for (let el = from instanceof Element ? from : null; el; el = el.parentElement) {
    if (el === document.body || el === document.documentElement) break;
    const y = el.scrollHeight > el.clientHeight;
    const x = el.scrollWidth > el.clientWidth;
    if (!y && !x) continue;
    const style = getComputedStyle(el);
    if ((y && /auto|scroll/.test(style.overflowY)) || (x && /auto|scroll/.test(style.overflowX))) return el;
  }
  const page = document.scrollingElement;
  return page && (page.scrollHeight > page.clientHeight || page.scrollWidth > page.clientWidth) ? page : null;
}

export function startScrollbars(): void {
  if (!window.matchMedia("(pointer: fine)").matches) return;
  document.documentElement.dataset.floatingScrollbars = "";

  /** One pane's pair of thumbs. Two at most are out: the pane under the pointer (at its bar) keeps its own while another pane
   * scrolls by itself (a chat opened from the sidebar going to its foot), rather than giving it up to that one and
   * coming back a moment later. */
  type Bar = { thumbs: Record<Axis, HTMLDivElement>; el: Element | null; resize: ResizeObserver; timer?: ReturnType<typeof setTimeout> };
  /** The pane under the pointer. */
  let hover: Element | null = null;
  /** Whether the pointer is where that pane's bar runs: its bar stays while the pointer does. */
  let near = false;
  /** Where the pointer was last seen over the page: the pane under it is found again when the one it was over is
   * taken out of the page (another chat opened in its place) without the pointer moving. */
  let pointer: { x: number; y: number } | null = null;
  let dragging: { bar: Bar; axis: Axis } | null = null;
  let frame = 0;
  const under = bar();
  const moving = bar();
  // A list drawing its rows on their way: its bar, if out, goes with what shows.
  paceFrames.add((pane) => { if (pane === under.el || pane === moving.el) schedule(); });

  function bar(): Bar {
    const b: Bar = { thumbs: { y: make(() => b, "y"), x: make(() => b, "x") }, el: null, resize: new ResizeObserver(() => schedule()) };
    return b;
  }

  function make(of: () => Bar, axis: Axis): HTMLDivElement {
    const el = document.createElement("div");
    el.className = css.floatingThumb;
    el.dataset.axis = axis;
    el.addEventListener("pointerdown", (e) => drag(of(), axis, e));
    return el;
  }

  function show(b: Bar, el: Element | null) {
    if (el !== b.el) {
      if (b.el) b.resize.unobserve(b.el);
      b.el = el;
      if (el) b.resize.observe(el);
    }
    schedule();
  }

  /** Beside the pane (its parent), the page's own at the end of the body. */
  function place(thumb: HTMLDivElement, el: Element) {
    const host = el === document.scrollingElement || !el.parentElement ? document.body : el.parentElement;
    if (thumb.parentElement !== host) host.append(thumb);
  }

  /** Where a thumb is put, as the viewport has it: its own origin (the viewport's, or a transformed ancestor's) aside. */
  function put(thumb: HTMLDivElement, x: number, y: number) {
    const [tx, ty] = (thumb.dataset.at ?? "0 0").split(" ").map(Number);
    const r = thumb.getBoundingClientRect();
    const ox = r.left - tx!, oy = r.top - ty!;
    thumb.style.transform = `translate(${x - ox}px, ${y - oy}px)`;
    thumb.dataset.at = `${x - ox} ${y - oy}`;
  }

  function schedule() {
    if (!frame) frame = requestAnimationFrame(() => { frame = 0; draw(); });
  }

  /** The bar of a pane scrolled away from the pointer goes HIDE_AFTER its last move; the pointer's, once it has left. */
  function linger(b: Bar) {
    clearTimeout(b.timer);
    b.timer = setTimeout(() => { if (dragging?.bar !== b) show(b, b === under && near ? hover : null); }, HIDE_AFTER);
  }

  /** Whether the pointer is along the pane's right edge or its foot, where its bars run. */
  function nearBar(el: Element): boolean {
    if (!pointer) return false;
    const page = el === document.scrollingElement;
    const r = page ? { left: 0, top: 0, right: el.clientWidth, bottom: el.clientHeight } : el.getBoundingClientRect();
    const right = page ? r.right : r.left + el.clientLeft + el.clientWidth - rightOf(el);
    const bottom = page ? r.bottom : r.top + el.clientTop + el.clientHeight;
    const { x, y } = pointer;
    if (x < r.left || x > r.right || y < r.top || y > r.bottom) return false;
    return (el.scrollHeight > el.clientHeight + 1 && x >= right - NEAR) || (el.scrollWidth > el.clientWidth + 1 && y >= bottom - NEAR);
  }

  /** The pointer's pane brings out its bar while the pointer is at it, and lets it go a moment after it leaves. */
  function follow() {
    const was = near;
    near = !!hover && nearBar(hover);
    if (near) {
      clearTimeout(under.timer);
      // The pane had its bar out as it scrolled: one bar for it, the pointer's.
      if (moving.el === hover) { clearTimeout(moving.timer); show(moving, null); }
      show(under, hover);
    } else if (was) linger(under);
  }

  function draw() {
    if (hover && !hover.isConnected) {
      hover = pointer ? scrollerOf(document.elementFromPoint(pointer.x, pointer.y)) : null;
      near = !!hover && nearBar(hover);
      if (near && hover === moving.el) moving.el = null;
      if (under.el) under.resize.unobserve(under.el);
      under.el = near ? hover : null;
      if (under.el) under.resize.observe(under.el);
    }
    drawBar(under);
    drawBar(moving);
  }

  function drawBar(b: Bar) {
    const el = b.el;
    for (const axis of ["y", "x"] as const) {
      const thumb = b.thumbs[axis];
      const size = axis === "y" ? el?.clientHeight ?? 0 : el?.clientWidth ?? 0;
      const content = axis === "y" ? el?.scrollHeight ?? 0 : el?.scrollWidth ?? 0;
      if (!el || !el.isConnected || content <= size + 1) { delete thumb.dataset.on; continue; }
      const page = el === document.scrollingElement;
      const box = page ? { left: 0, top: 0 } : el.getBoundingClientRect();
      const left = box.left + (page ? 0 : el.clientLeft);
      const top = box.top + (page ? 0 : el.clientTop);
      const { start, track, length } = trackOf(el, axis, size, content);
      // A list's rows still on their way (virtual/pace.ts): where what shows is drawn, not where it is laid out.
      const scrolled = axis === "y" ? el.scrollTop - drawnLag(el) : Math.abs(el.scrollLeft);
      // Pulled past either end (an elastic scroll), the thumb stops at the track's end.
      const at = start + INSET + Math.min(1, Math.max(0, scrolled / (content - size))) * (track - INSET * 2 - length);
      place(thumb, el);
      if (axis === "y") {
        put(thumb, left + el.clientWidth - SIZE - INSET - rightOf(el), top + at);
        thumb.style.height = `${length}px`;
      } else {
        put(thumb, left + at, top + el.clientHeight - SIZE - INSET);
        thumb.style.width = `${length}px`;
      }
      thumb.dataset.on = "";
    }
  }

  function drag(b: Bar, axis: Axis, e: PointerEvent) {
    const el = b.el;
    if (!el || e.button !== 0) return;
    e.preventDefault();
    const thumb = b.thumbs[axis];
    thumb.setPointerCapture(e.pointerId);
    dragging = { bar: b, axis };
    thumb.dataset.drag = "";
    const from = axis === "y" ? e.clientY : e.clientX;
    const start = axis === "y" ? el.scrollTop : el.scrollLeft;
    const size = axis === "y" ? el.clientHeight : el.clientWidth;
    const content = axis === "y" ? el.scrollHeight : el.scrollWidth;
    const { track, length } = trackOf(el, axis, size, content);
    const ratio = (content - size) / Math.max(1, track - INSET * 2 - length);
    const move = (m: PointerEvent) => {
      const to = start + ((axis === "y" ? m.clientY : m.clientX) - from) * ratio;
      if (axis === "y") el.scrollTop = to; else el.scrollLeft = to;
    };
    const end = () => {
      dragging = null;
      delete thumb.dataset.drag;
      thumb.removeEventListener("pointermove", move);
      thumb.removeEventListener("pointerup", end);
      thumb.removeEventListener("pointercancel", end);
      linger(b);
    };
    thumb.addEventListener("pointermove", move);
    thumb.addEventListener("pointerup", end);
    thumb.addEventListener("pointercancel", end);
  }

  // Only when the pointer comes onto another element, never on every move. Which pane it is over is read once the
  // frame is drawn, when what is laid out is up to date: read at once, an element gone from under the pointer (a
  // panel's switch replaced as it opens) laid the page out in the middle of that change.
  let over: EventTarget | null = null;
  let reading = 0;
  document.addEventListener("pointerover", (e) => {
    if (dragging || e.pointerType !== "mouse") return;
    pointer = { x: e.clientX, y: e.clientY };
    if (e.target instanceof HTMLElement && e.target.classList.contains(css.floatingThumb)) return;
    over = e.target;
    if (reading) return;
    reading = requestAnimationFrame(() => setTimeout(() => {
      reading = 0;
      if (dragging) return;
      hover = scrollerOf(over);
      follow();
    }));
  }, { passive: true });
  // Over the pane, whether the pointer has come to its bar is read once a frame.
  let moved = 0;
  document.addEventListener("pointermove", (e) => {
    if (dragging || e.pointerType !== "mouse") return;
    pointer = { x: e.clientX, y: e.clientY };
    if (!hover || moved) return;
    moved = requestAnimationFrame(() => { moved = 0; if (!dragging && hover) follow(); });
  }, { passive: true });
  document.documentElement.addEventListener("pointerleave", () => { hover = null; near = false; pointer = null; linger(under); });
  // Whatever scrolls (a wheel over a pane, a chat following new messages) shows its bar for a moment; the pane under
  // the pointer keeps its own meanwhile.
  document.addEventListener("scroll", (e) => {
    if (dragging) { schedule(); return; }
    const el = e.target instanceof Element ? e.target : document.scrollingElement;
    if (el && el === under.el) { schedule(); if (el !== hover || !near) linger(under); return; }
    show(moving, el);
    linger(moving);
  }, { capture: true, passive: true });
  window.addEventListener("resize", schedule);
}
