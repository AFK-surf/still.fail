// Where a preview's page is (Preview.tsx): all of the preview, or — laid out at a size of its own (viewport.ts) — a
// canvas with the page on it. Fitted and centred at first; then moved and zoomed as on a canvas, beyond the preview's
// edges if need be: the ground dragged (or the page, with space held), ⌘/Ctrl + the wheel or a pinch to zoom about the
// pointer, a double click on the ground to fit it again. Its right and bottom edges drag its size; turning it turns it
// on the spot. On a touch screen a toolbar floats over the page: its sizes, turning, and a mode in which a finger moves
// the page and two zoom it (else they are the page's own).
import { useCallback, useEffect, useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { Landscape, Move } from "./icons.tsx";
import { LIMIT, PRESETS, presetOf, setViewport, type Viewport } from "./viewport.ts";
import { dims, useTouch, ViewportSheet, type Zoom } from "./ViewportSize.tsx";
import * as css from "./PreviewStage.css.ts";
import { t } from "./i18n.ts";

/** The page's box in the stage: its top-left, how much it is drawn at, and the size it is laid out at. */
export interface Placed { x: number; y: number; scale: number; width: number; height: number }
interface View { x: number; y: number; scale: number }
/** The stage's room (less its padding, which is where it starts), and whether it is a small one in the corner
 * (Previews.tsx: only fitted). */
interface Room { width: number; height: number; left: number; top: number; small: boolean }

const ZOOM = { min: 0.05, max: 4 };
const clampZoom = (s: number) => Math.max(ZOOM.min, Math.min(ZOOM.max, s));

export interface Stage {
  ref: RefObject<HTMLDivElement | null>;
  viewKey: string | undefined;
  viewport: Viewport | null;
  placed: Placed | null;
  small: boolean;
  zoom: Zoom;
  turn(): void;
  /** Moves the page to `view` (null: fitted). */
  move(view: View | null): void;
  /** Its size is being dragged (the view stays). */
  resizing: RefObject<boolean>;
  /** Where it was drawn just before it was turned (for turning it on the spot). */
  turned: RefObject<{ width: number; height: number } | null>;
  /** A touch screen's toolbar folded away (the bar's size button opens it again). */
  folded: boolean;
  fold(value: boolean): void;
}

export function useStage(viewKey: string | undefined, viewport: Viewport | null): Stage {
  const ref = useRef<HTMLDivElement>(null);
  const [room, setRoom] = useState<Room | null>(null);
  const [view, setView] = useState<View | null>(null);
  const resizing = useRef(false);
  const turned = useRef<{ width: number; height: number } | null>(null);
  const [folded, setFolded] = useState(() => localStorage.getItem(FOLDED) === "1");
  const fold = useCallback((value: boolean) => {
    localStorage.setItem(FOLDED, value ? "1" : "0");
    setFolded(value);
  }, []);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const measure = () => {
      const style = getComputedStyle(el);
      const left = parseFloat(style.paddingLeft) || 0, top = parseFloat(style.paddingTop) || 0;
      const next = {
        width: el.clientWidth - left - (parseFloat(style.paddingRight) || 0), height: el.clientHeight - top - (parseFloat(style.paddingBottom) || 0),
        left, top, small: el.closest("[data-mode=small]") !== null,
      };
      setRoom((was) => (was && (Object.keys(next) as (keyof Room)[]).every((k) => was[k] === next[k]) ? was : next));
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    return () => observer.disconnect();
  }, []);
  // A size chosen (or typed, or turned) is fitted anew; one being dragged keeps where it is.
  const last = useRef(viewport);
  useEffect(() => {
    if (last.current === viewport) return;
    last.current = viewport;
    if (!resizing.current) setView(null);
  }, [viewport]);

  let placed: Placed | null = null;
  if (viewport && room && room.width > 0 && room.height > 0) {
    const fitted = Math.max(ZOOM.min, Math.floor(Math.min(1, room.width / viewport.width, viewport.height === null ? 1 : room.height / viewport.height) * 1000) / 1000);
    const free = view && !room.small ? view : null;
    const scale = free?.scale ?? fitted;
    const width = viewport.width;
    // As high as the preview leaves it, at the scale it fits at (zooming does not lay it out again).
    const height = viewport.height ?? Math.max(LIMIT.min, Math.floor(room.height / fitted));
    placed = {
      x: free ? free.x : Math.round(room.left + Math.max(0, (room.width - width * scale) / 2)),
      y: free ? free.y : Math.round(room.top + Math.max(0, (room.height - height * scale) / 2)),
      scale, width, height,
    };
  }
  const now = useRef({ placed, room });
  now.current = { placed, room };
  const zoomBy = useCallback((factor: number, at?: { x: number; y: number }) => {
    const { placed: p, room: r } = now.current;
    if (!p || !r) return;
    const scale = clampZoom(p.scale * factor);
    const about = at ?? { x: r.left + r.width / 2, y: r.top + r.height / 2 };
    setView({ scale, x: about.x - ((about.x - p.x) * scale) / p.scale, y: about.y - ((about.y - p.y) * scale) / p.scale });
  }, []);
  const fit = useCallback(() => setView(null), []);
  const turn = () => {
    if (!viewKey || viewport?.height == null) return;
    turned.current = placed ? { width: placed.width * placed.scale, height: placed.height * placed.scale } : null;
    setView(null);
    setViewport(viewKey, { width: viewport.height, height: viewport.width });
  };
  return {
    ref, viewKey, viewport, placed, small: room?.small ?? false,
    zoom: { scale: placed?.scale ?? 1, free: view !== null, zoom: zoomBy, fit },
    turn, move: setView, resizing, turned, folded, fold,
  };
}

type Point = { x: number; y: number };
/** Two fingers gone from `was` to `at`: the page (drawn as `from` when they came down) zoomed by how far apart they
 * went, what was under their middle still under it. */
function pinch(from: View, was: Point[], at: Point[]): View {
  const mid = (ps: Point[]) => ({ x: (ps[0]!.x + ps[1]!.x) / 2, y: (ps[0]!.y + ps[1]!.y) / 2 });
  const apart = (ps: Point[]) => Math.hypot(ps[0]!.x - ps[1]!.x, ps[0]!.y - ps[1]!.y) || 1;
  const m0 = mid(was), m1 = mid(at);
  const scale = clampZoom((from.scale * apart(at)) / apart(was));
  return { scale, x: m1.x - ((m0.x - from.x) * scale) / from.scale, y: m1.y - ((m0.y - from.y) * scale) / from.scale };
}

/** The page's corners, as its screen's (at its own size): a phone's round, a tablet's less, a desktop's all but square
 * (a few px however small it is drawn). */
function cornerOf(p: Placed): number {
  if (p.width <= 600) return 44;
  if (p.width < 1024) return 24;
  return 5 / p.scale;
}

/** The page's frame, at `origin`, told apart by `nonce`: told that it is on a canvas, it hands on zooming and two
 * fingers over the page (annotate/frame.ts), which would otherwise be the page's. */
export interface Link { frame: RefObject<HTMLIFrameElement | null>; origin: string | null; nonce: string }

/** The stage: the page (`children`, its frame, which never moves in the document) and what is `over` it (its marks),
 * then whatever else goes over the stage (`after`). */
export function PreviewStage({ stage, link, over, children, after }:
  { stage: Stage; link: Link; over: ReactNode; children: ReactNode; after?: ReactNode }) {
  const { placed, viewKey, viewport } = stage;
  const touch = useTouch();
  const device = useRef<HTMLDivElement>(null);
  const shade = useRef<HTMLDivElement>(null);
  // Moving the page by a finger (a touch screen's mode) or with space held (a pointer's).
  const [moving, setMoving] = useState(false);
  const [space, setSpace] = useState(false);
  const [dragging, setDragging] = useState(false);
  const canvas = placed !== null && !stage.small;
  const now = useRef(placed);
  now.current = placed;

  // Space held while the pointer is over the stage: the page is taken hold of (not clicked) until it is let go.
  useEffect(() => {
    if (!canvas || touch) return;
    const typing = (t: EventTarget | null) => t instanceof HTMLElement && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName));
    const down = (e: KeyboardEvent) => {
      // Over the stage: its page too (the page's frame is hovered then, though its pointer events are the page's).
      if (e.code !== "Space" || !stage.ref.current?.matches(":hover") || typing(e.target)) return;
      e.preventDefault();
      setSpace(true);
    };
    const up = (e: KeyboardEvent) => { if (e.code === "Space") setSpace(false); };
    const off = () => setSpace(false);
    window.addEventListener("keydown", down);
    window.addEventListener("keyup", up);
    window.addEventListener("blur", off);
    return () => { window.removeEventListener("keydown", down); window.removeEventListener("keyup", up); window.removeEventListener("blur", off); };
  }, [canvas, touch, stage.ref]);

  // The wheel over the ground (or the page held): ⌘/Ctrl (a trackpad's pinch says ctrl) zooms about the pointer, else
  // it moves the page.
  const { zoom: zoomBy } = stage.zoom;
  const { move } = stage;
  useEffect(() => {
    const el = stage.ref.current;
    if (!el || !canvas) return;
    const wheel = (e: WheelEvent) => {
      const p = now.current;
      if (!p) return;
      e.preventDefault();
      const r = el.getBoundingClientRect();
      // A wheel's notch (≈100) zooms by about a third; a pinch's small steps as the fingers go.
      const delta = Math.max(-30, Math.min(30, e.deltaMode === 1 ? e.deltaY * 16 : e.deltaY));
      if (e.ctrlKey || e.metaKey) zoomBy(Math.exp(-delta * 0.01), { x: e.clientX - r.left, y: e.clientY - r.top });
      else move({ scale: p.scale, x: p.x - e.deltaX, y: p.y - e.deltaY });
    };
    el.addEventListener("wheel", wheel, { passive: false });
    return () => el.removeEventListener("wheel", wheel);
  }, [stage.ref, canvas, zoomBy, move]);

  // Over the page itself (its frame says so): ⌘/Ctrl and the wheel zoom about the pointer, two fingers pinch.
  const fingers = useRef<{ view: View; at: { x: number; y: number }[] } | null>(null);
  // Once its frame has said where it is, it is there to be told.
  const heard = useRef(false);
  useEffect(() => {
    const { frame, origin, nonce } = link;
    if (!origin) return;
    const tell = () => { if (heard.current) frame.current?.contentWindow?.postMessage({ type: "ember-preview-annotate", canvas }, origin); };
    tell();
    const onMessage = (event: MessageEvent) => {
      if (event.origin !== origin || event.source !== frame.current?.contentWindow || event.data?.nonce !== nonce) return;
      // A page just loaded (or moved): it is told again.
      if (event.data?.type === "ember-preview-at") { heard.current = true; tell(); return; }
      const p = now.current;
      if (event.data?.type !== "ember-preview-gesture" || !canvas || !p) return;
      if (event.data.kind === "space") { setSpace(event.data.down === true); return; }
      const onStage = (at: { x: number; y: number }) => ({ x: p.x + at.x * p.scale, y: p.y + at.y * p.scale });
      if (event.data.kind === "wheel") {
        const delta = Math.max(-30, Math.min(30, event.data.deltaMode === 1 ? event.data.deltaY * 16 : event.data.deltaY));
        zoomBy(Math.exp(-delta * 0.01), onStage(event.data));
      } else if (event.data.kind === "fingers") {
        const at = (event.data.points as { x: number; y: number }[]).map(onStage);
        if (at.length < 2) { fingers.current = null; return; }
        if (!fingers.current) { fingers.current = { view: { x: p.x, y: p.y, scale: p.scale }, at }; return; }
        move(pinch(fingers.current.view, fingers.current.at, at));
      }
    };
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, [link, canvas, zoomBy, move]);

  // One pointer moves the page; two (a pinch) zoom it about between them and move it as they move.
  const pointers = useRef(new Map<number, { x: number; y: number }>());
  const from = useRef<{ view: View; at: { x: number; y: number }[] } | null>(null);
  const begin = () => {
    const p = now.current;
    from.current = p && pointers.current.size ? { view: { x: p.x, y: p.y, scale: p.scale }, at: [...pointers.current.values()] } : null;
  };
  const local = (e: React.PointerEvent) => {
    const r = stage.ref.current!.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  };
  const grab = (ground: boolean) => ({
    onPointerDown: (e: React.PointerEvent<HTMLDivElement>) => {
      if (!canvas || (ground && e.target !== e.currentTarget) || (e.pointerType === "mouse" && e.button !== 0 && e.button !== 1)) return;
      e.preventDefault();
      e.currentTarget.setPointerCapture(e.pointerId);
      pointers.current.set(e.pointerId, local(e));
      begin();
      setDragging(true);
    },
    onPointerMove: (e: React.PointerEvent<HTMLDivElement>) => {
      if (!pointers.current.has(e.pointerId) || !from.current) return;
      pointers.current.set(e.pointerId, local(e));
      const at = [...pointers.current.values()], was = from.current.at, v = from.current.view;
      if (at.length !== was.length) return;
      if (at.length === 1) {
        move({ scale: v.scale, x: v.x + at[0]!.x - was[0]!.x, y: v.y + at[0]!.y - was[0]!.y });
        return;
      }
      move(pinch(v, was, at));
    },
    onPointerUp: (e: React.PointerEvent<HTMLDivElement>) => {
      pointers.current.delete(e.pointerId);
      begin();
      if (!pointers.current.size) setDragging(false);
    },
    onPointerCancel: (e: React.PointerEvent<HTMLDivElement>) => {
      pointers.current.delete(e.pointerId);
      begin();
      if (!pointers.current.size) setDragging(false);
    },
  });

  // Turned: it turns on the spot, from as it was drawn (a quarter turn back, its size as it was) to as it is now.
  useLayoutEffect(() => {
    const was = stage.turned.current;
    if (!was || !placed) return;
    stage.turned.current = null;
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const w = placed.width * placed.scale, h = placed.height * placed.scale;
    const k0 = (was.height / w + was.width / h) / 2;
    const frames = (steps: number) => Array.from({ length: steps + 1 }, (_, i) => {
      const t = i / steps, e = 1 - (1 - t) ** 3;
      const a = (-Math.PI / 2) * (1 - e), k = k0 + (1 - k0) * e;
      // About its middle (its box's origin is its top-left corner).
      const cx = (w * k) / 2, cy = (h * k) / 2;
      const rx = cx * Math.cos(a) - cy * Math.sin(a), ry = cx * Math.sin(a) + cy * Math.cos(a);
      return { offset: t, translate: `${w / 2 - rx}px ${h / 2 - ry}px`, rotate: `${a}rad`, scale: String(k) };
    });
    const timing = { duration: 420, easing: "linear" };
    device.current?.animate(frames(12), timing);
    shade.current?.animate(frames(12), timing);
  }, [placed, stage.turned]);

  const box = placed && { left: placed.x, top: placed.y, width: placed.width * placed.scale, height: placed.height * placed.scale };
  const held = canvas && (space || moving);
  // A touch screen's toolbar, under the stage (a frame's page under it would take its taps).
  const bar = viewKey !== undefined && touch && !stage.small && !stage.folded;
  return (
    <>
    <div ref={stage.ref} className={css.stage} data-sized={placed ? true : undefined} data-dragging={dragging || undefined}
      onDoubleClick={(e) => { if (canvas && e.target === e.currentTarget) stage.zoom.fit(); }} {...grab(true)}>
      {placed && box && <div ref={shade} className={css.shade} style={{ ...box, borderRadius: cornerOf(placed) * placed.scale }} />}
      <div ref={device} className={css.device}
        style={placed ? { left: placed.x, top: placed.y, width: placed.width, height: placed.height, transform: `scale(${placed.scale})`, borderRadius: cornerOf(placed) } : undefined}>
        {children}
      </div>
      {over && <div className={css.over} style={box ?? undefined}>{over}</div>}
      {held && <div className={css.hold} data-dragging={dragging || undefined} {...grab(false)} />}
      {canvas && viewKey && viewport && box && !touch && <Edges stage={stage} box={box} />}
      {after}
    </div>
    {bar && <div className={css.dock} data-sized={placed ? true : undefined}><Toolbar stage={stage} moving={moving && canvas} setMoving={setMoving} /></div>}
    </>
  );
}

/** Widths and heights a dragged edge settles on when it comes near (within SNAP px on the screen): common devices'. */
const WIDTHS = [320, 360, 375, 390, 414, 430, 768, 820, 1024, 1280, 1366, 1440, 1920];
const HEIGHTS = [568, 667, 740, 800, 844, 900, 932, 1024, 1080, 1180];
const SNAP = 6;
type Side = "right" | "bottom" | "corner";

/**
 * The page's right and bottom edges and the corner between them, dragged to size it (its top-left stays where it is,
 * so it may run past the preview's edges), settling on common sizes nearby. While dragged and a moment after any
 * change, its size shows over its bottom edge. A double click goes back to as big as the preview.
 */
function Edges({ stage, box }: { stage: Stage; box: { left: number; top: number; width: number; height: number } }) {
  const viewport = stage.viewport!, placed = stage.placed!, viewKey = stage.viewKey!;
  const [dragging, setDragging] = useState(false);
  const [told, setTold] = useState(false);
  const shown = useRef<string | null>(null);
  const said = `${viewport.width}x${viewport.height}`;
  // A moment after its size changes (chosen, typed, dragged), it says so.
  useEffect(() => {
    if (shown.current === null) { shown.current = said; return; }
    if (shown.current === said) return;
    shown.current = said;
    setTold(true);
    const t = setTimeout(() => setTold(false), 1400);
    return () => clearTimeout(t);
  }, [said]);
  const drag = (side: Side) => (e: React.PointerEvent<HTMLDivElement>) => {
    if (e.button !== 0) return;
    e.preventDefault();
    e.stopPropagation();
    const handle = e.currentTarget;
    handle.setPointerCapture(e.pointerId);
    const from = { x: e.clientX, y: e.clientY, width: placed.width, height: placed.height, scale: placed.scale };
    // Held where it is drawn now, as it grows.
    stage.resizing.current = true;
    stage.move({ x: placed.x, y: placed.y, scale: placed.scale });
    setDragging(true);
    document.documentElement.dataset.viewportResizing = side;
    const near = (value: number, all: number[]) => all.find((n) => Math.abs(n - value) * from.scale < SNAP) ?? Math.round(value);
    const move = (m: PointerEvent) => {
      const width = side === "bottom" ? viewport.width : near(from.width + (m.clientX - from.x) / from.scale, WIDTHS);
      const height = side === "right" ? viewport.height : near(from.height + (m.clientY - from.y) / from.scale, HEIGHTS);
      setViewport(viewKey, { width, height });
    };
    const end = () => {
      handle.removeEventListener("pointermove", move);
      handle.removeEventListener("pointerup", end);
      handle.removeEventListener("pointercancel", end);
      delete document.documentElement.dataset.viewportResizing;
      setDragging(false);
      // After the last change it made has been seen.
      requestAnimationFrame(() => { stage.resizing.current = false; });
    };
    handle.addEventListener("pointermove", move);
    handle.addEventListener("pointerup", end);
    handle.addEventListener("pointercancel", end);
  };
  const preset = presetOf(viewport);
  return (
    <>
      {(["right", "bottom", "corner"] as Side[]).map((side) => (
        <div key={side} className={css.edge} data-side={side} aria-hidden
          style={side === "right" ? { left: box.left + box.width, top: box.top, height: box.height }
            : side === "bottom" ? { left: box.left, top: box.top + box.height, width: box.width }
            : { left: box.left + box.width, top: box.top + box.height }}
          onPointerDown={drag(side)} onDoubleClick={(e) => { e.stopPropagation(); setViewport(viewKey, null); }} />
      ))}
      <div className={css.size} data-shown={dragging || told || undefined} aria-hidden
        style={{ left: box.left + box.width / 2, top: box.top + box.height - 12 }}>
        {preset && <span>{preset}</span>}
        {dims(viewport.width, viewport.height === null ? placed.height : viewport.height)}
        <span>{Math.round(placed.scale * 100)}%</span>
      </div>
    </>
  );
}

const FOLDED = "stillfail.previewToolbarFolded";

/**
 * A touch screen's toolbar, a floating capsule under the page: the sizes (the one chosen marked; "自定义" opens them
 * all in a sheet), turning, moving the page by a finger, and fitting it again once moved. Held down, it folds away,
 * leaving the page all the room (the bar's size button opens it again).
 */
function Toolbar({ stage, moving, setMoving }: { stage: Stage; moving: boolean; setMoving(v: boolean): void }) {
  const { viewKey, viewport } = stage;
  const [sheet, setSheet] = useState(false);
  const press = useRef<{ timer: number; x: number; y: number } | null>(null);
  // Folded by holding it: the tap that ends the hold is not a tap on what it was held on.
  const held = useRef(false);
  const fold = () => { held.current = true; setMoving(false); stage.fold(true); };
  if (!viewKey) return null;
  const set = (v: typeof viewport) => { setMoving(false); setViewport(viewKey, v); };
  const preset = presetOf(viewport);
  const custom = viewport !== null && preset === null;
  const turnable = viewport?.height != null;
  return (
    <div className={css.toolbar}
      onClickCapture={(e) => { if (held.current) { held.current = false; e.preventDefault(); e.stopPropagation(); } }}
      onPointerDown={(e) => {
        held.current = false;
        const at = { x: e.clientX, y: e.clientY };
        press.current = { ...at, timer: window.setTimeout(() => { press.current = null; navigator.vibrate?.(10); fold(); }, 500) };
      }}
      onPointerMove={(e) => {
        if (press.current && Math.hypot(e.clientX - press.current.x, e.clientY - press.current.y) > 8) { clearTimeout(press.current.timer); press.current = null; }
      }}
      onPointerUp={() => { if (press.current) { clearTimeout(press.current.timer); press.current = null; } }}
      onPointerCancel={() => { if (press.current) { clearTimeout(press.current.timer); press.current = null; } }}
      onContextMenu={(e) => e.preventDefault()}>
      <div className={css.chips}>
        <button type="button" className={css.chip} aria-pressed={!viewport} onClick={() => set(null)}>{t("web-main.viewport.fluid")}</button>
        {PRESETS.map((p) => (
          <button key={p.name} type="button" className={css.chip} aria-pressed={preset === p.name}
            onClick={() => set(preset === p.name ? viewport : { width: p.width, height: p.height })}>{p.name}</button>
        ))}
        <button type="button" className={css.chip} aria-pressed={custom} onClick={() => setSheet(true)}>
          {custom ? dims(viewport.width, viewport.height) : t("web-main.viewport.custom")}
        </button>
      </div>
      {viewport && (
        <div className={css.tools}>
          {turnable && <button type="button" className={css.tool} aria-label={t("web-main.viewport.turn")} onClick={stage.turn}><Landscape size={18} strokeWidth={1.75} /></button>}
          <button type="button" className={css.tool} aria-label={t("web-main.viewport.move")} aria-pressed={moving} onClick={() => setMoving(!moving)}><Move size={18} strokeWidth={1.75} /></button>
          {stage.zoom.free && <button type="button" className={css.fitTool} onClick={() => { stage.zoom.fit(); setMoving(false); }}>{t("web-main.viewport.fit")}</button>}
        </div>
      )}
      <ViewportSheet open={sheet} onOpenChange={setSheet} viewKey={viewKey} viewport={viewport} turn={stage.turn} />
    </div>
  );
}
