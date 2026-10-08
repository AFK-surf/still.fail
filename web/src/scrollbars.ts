import * as css from "./scrollbars.css.ts";
// Scrollbars that float over what scrolls and take no room from it. With a mouse the system's bars are hidden
// (styles/global.css.ts) and one thin thumb per axis, drawn here, shows on the pane under the pointer and on any pane while it
// scrolls, and can be dragged. Touch screens keep the system's own, which already float.
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

  const thumbs = { y: make("y"), x: make("x") };
  let active: Element | null = null;
  /** The pane under the pointer: its bar stays while the pointer does. */
  let hover: Element | null = null;
  let dragging: Axis | null = null;
  let hideTimer: ReturnType<typeof setTimeout> | undefined;
  let frame = 0;
  const resize = new ResizeObserver(() => schedule());

  function make(axis: Axis): HTMLDivElement {
    const el = document.createElement("div");
    el.className = css.floatingThumb;
    el.dataset.axis = axis;
    el.addEventListener("pointerdown", (e) => drag(axis, e));
    return el;
  }

  function show(el: Element | null) {
    if (el !== active) {
      if (active) resize.unobserve(active);
      active = el;
      if (el) resize.observe(el);
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

  function linger() {
    clearTimeout(hideTimer);
    hideTimer = setTimeout(() => { if (!dragging) show(hover); }, HIDE_AFTER);
  }

  function draw() {
    const el = active;
    for (const axis of ["y", "x"] as const) {
      const thumb = thumbs[axis];
      const size = axis === "y" ? el?.clientHeight ?? 0 : el?.clientWidth ?? 0;
      const content = axis === "y" ? el?.scrollHeight ?? 0 : el?.scrollWidth ?? 0;
      if (!el || !el.isConnected || content <= size + 1) { delete thumb.dataset.on; continue; }
      const page = el === document.scrollingElement;
      const box = page ? { left: 0, top: 0 } : el.getBoundingClientRect();
      const left = box.left + (page ? 0 : el.clientLeft);
      const top = box.top + (page ? 0 : el.clientTop);
      const { start, track, length } = trackOf(el, axis, size, content);
      const scrolled = axis === "y" ? el.scrollTop : Math.abs(el.scrollLeft);
      // Pulled past either end (an elastic scroll), the thumb stops at the track's end.
      const at = start + INSET + Math.min(1, Math.max(0, scrolled / (content - size))) * (track - INSET * 2 - length);
      place(thumb, el);
      if (axis === "y") {
        put(thumb, left + el.clientWidth - SIZE - INSET, top + at);
        thumb.style.height = `${length}px`;
      } else {
        put(thumb, left + at, top + el.clientHeight - SIZE - INSET);
        thumb.style.width = `${length}px`;
      }
      thumb.dataset.on = "";
    }
  }

  function drag(axis: Axis, e: PointerEvent) {
    const el = active;
    if (!el || e.button !== 0) return;
    e.preventDefault();
    const thumb = thumbs[axis];
    thumb.setPointerCapture(e.pointerId);
    dragging = axis;
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
      linger();
    };
    thumb.addEventListener("pointermove", move);
    thumb.addEventListener("pointerup", end);
    thumb.addEventListener("pointercancel", end);
  }

  // Only when the pointer comes onto another element, never on every move.
  document.addEventListener("pointerover", (e) => {
    if (dragging || e.pointerType !== "mouse") return;
    if (e.target instanceof HTMLElement && e.target.classList.contains(css.floatingThumb)) return;
    hover = scrollerOf(e.target);
    if (hover) { clearTimeout(hideTimer); show(hover); } else linger();
  }, { passive: true });
  document.documentElement.addEventListener("pointerleave", () => { hover = null; linger(); });
  // Whatever scrolls (a wheel over a pane, a chat following new messages) shows its bar for a moment.
  document.addEventListener("scroll", (e) => {
    if (dragging) { schedule(); return; }
    const el = e.target instanceof Element ? e.target : document.scrollingElement;
    show(el);
    if (el !== hover) linger();
  }, { capture: true, passive: true });
  window.addEventListener("resize", schedule);
}
