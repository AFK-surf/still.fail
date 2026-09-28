// Scrollbars that float over what scrolls and take no room from it. With a mouse the system's bars are hidden
// (app.css) and one thin thumb per axis, drawn here, shows on the pane under the pointer and on any pane while it
// scrolls, and can be dragged. Touch screens keep the system's own, which already float.

type Axis = "y" | "x";

const HIDE_AFTER = 900;
const MIN_THUMB = 28;
const INSET = 2;
const SIZE = 6;

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
    el.className = "floating-thumb";
    el.dataset.axis = axis;
    el.addEventListener("pointerdown", (e) => drag(axis, e));
    document.body.append(el);
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
      const length = Math.max(MIN_THUMB, (size * size) / content) - INSET * 2;
      const scrolled = axis === "y" ? el.scrollTop : Math.abs(el.scrollLeft);
      const at = INSET + (scrolled / (content - size)) * (size - INSET * 2 - length);
      if (axis === "y") {
        thumb.style.transform = `translate(${left + el.clientWidth - SIZE - INSET}px, ${top + at}px)`;
        thumb.style.height = `${length}px`;
      } else {
        thumb.style.transform = `translate(${left + at}px, ${top + el.clientHeight - SIZE - INSET}px)`;
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
    const length = Math.max(MIN_THUMB, (size * size) / content) - INSET * 2;
    const ratio = (content - size) / Math.max(1, size - INSET * 2 - length);
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
    if (e.target instanceof HTMLElement && e.target.classList.contains("floating-thumb")) return;
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
