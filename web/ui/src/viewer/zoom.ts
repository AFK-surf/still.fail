// Zooming and panning a picture in a stage (the preview's images, the player's picture): fitted to the room its bars
// leave, zoomed round the pointer or the fingers, moved when larger than the window.
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";

/** A sideways drag of a fitted image: where it has got to (px from where it started), then where and how fast (px/ms) it was let go. */
export interface Swipe { drag(dx: number): void; end(dx: number, vx: number): void }

interface View { scale: number; x: number; y: number }

/** Zoomed in as far as 16 times its own size. */
export const MAX_SCALE = 16;

export interface ZoomOptions {
  swipe?: Swipe | undefined;
  keys?: boolean;
  margin?: (width: number) => number;
  enlarge?: boolean;
  doubleClick?: boolean;
  floats?: boolean;
}

/**
 * Zooming and panning a picture of `natural` size in a stage (an image, a video's picture): fitted to the window, to
 * zoom (pinch, ctrl/⌘ + wheel, double-click, a bar's buttons, + − 0 1) around the pointer and pan (drag, wheel) when
 * larger than the window. Fitted, one pointer dragging sideways is a `swipe`'s. `place` positions the picture
 * (absolutely, in the stage's centre). `margin`: room kept round it fitted (a picture's: 12 on a phone, 32 wider; a
 * film's none); `enlarge`: fitted larger than its own size (a film's, as players show one); `doubleClick`: a double
 * click zooms (a player's fills the screen instead). The bars over it (`data-floats`, in its `[data-zoom-root]`) take
 * their room off its top and bottom, unless not `floats` (a film's picture under its bars, as players show one).
 */
export function useZoom(natural: { w: number; h: number } | null, { swipe, keys = true, margin, enlarge = false, doubleClick = true, floats = true }: ZoomOptions = {}) {
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
    const root = el.closest("[data-zoom-root]") ?? el;
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
      for (const bar of floats ? root.querySelectorAll("[data-floats]") : []) {
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
  const MARGIN = margin ? margin(box?.w ?? 0) : box && box.w < 640 ? 12 : 32;
  const padTop = box?.top ? box.top + MARGIN / 2 : MARGIN, padBottom = box?.bottom ? box.bottom + MARGIN / 2 : MARGIN;
  /** Where a picture smaller than the room between the bars sits: in the middle of it. */
  const centreY = (padTop - padBottom) / 2;
  const fits = natural && box ? Math.min((box.w - 2 * MARGIN) / natural.w, (box.h - padTop - padBottom) / natural.h) : 1;
  const fit = enlarge ? fits : Math.min(1, fits);
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

  const larger = !!natural && !!box && !!view && (natural.w * view.scale > box.w + 1 || natural.h * view.scale > box.h - box.top - box.bottom + 1);
  const zoomed = !!view && view.scale > fit * 1.01;
  return {
    stage, scale, fit, minScale, zoomed, zoomTo, reset,
    stageProps: {
      "data-pan": larger || undefined, "data-zoomed": zoomed || undefined,
      onPointerDown, onPointerMove, onPointerUp, onPointerCancel: onPointerUp, ...(doubleClick ? { onDoubleClick } : {}),
    },
    place: natural && view ? { width: natural.w, height: natural.h, transform: `translate(-50%, -50%) translate(${view.x}px, ${view.y}px) scale(${view.scale})` } : null,
  };
}
