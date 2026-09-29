// The web services opened beside chats, kept for as long as the window is open: moving to another chat or page does
// not close one (nor load it anew); it goes small into the bottom-right corner, still live, and back into its chat's
// side panel when that is in view again. Only closing it (its tab in the chat, or × on the small one) ends it.
//
// The chat under the small ones makes way for them, as a whole (its messages and composer): whatever of it is marked
// `data-avoid-previews` leaves them the window's side from their left edge on (`--avoid-previews`, its styles).
//
// A visualization an agent posted (Preview.tsx's `file`) is kept and shown the same way.
//
// A frame loads anew whenever it moves in the document, so every kept one is drawn here, in one layer over the page,
// and never moves in it: the chat's side panel has a slot (PreviewSlot) that only says where the frame should be.
import { useEffect, useLayoutEffect, useRef, useState, useSyncExternalStore } from "react";
import { useHref, useLocation, useNavigate } from "react-router";
import { fileService, ServiceFrame, type FileSource, type Restarting } from "./Preview.tsx";
import { useLink } from "./station.tsx";
import { Close, Minus, Web } from "./icons.tsx";
import { Tip } from "./ui.tsx";
import { previewKey, viewportOf } from "./viewport.ts";
import { follower, type Follower } from "./motion.ts";
import * as css from "./Previews.css.ts";

export { previewKey };

interface Kept {
  key: string;
  station: string;
  /** A web service's port, or a visualization's file. */
  port: number | undefined;
  file: FileSource | undefined;
  name: string;
  service: string;
  /** Its page of its own (the bar's "open on its own"); a visualization has none. */
  external: string | undefined;
  /** Its chat, with its tab open: where the small one goes back to. */
  back: string;
  restarting: Restarting | null;
  /** Its chat's draft, where its marks go (annotate/Marks.tsx). */
  draftKey: string | undefined;
}

let kept: Kept[] = [];
/** Where each kept one is shown now: its slot in its chat's side panel, while that is on the page. */
const slots = new Map<string, HTMLElement>();
const listeners = new Set<() => void>();
const changed = () => { for (const listener of listeners) listener(); };

function keep(entry: Kept): void {
  const at = kept.findIndex((k) => k.key === entry.key);
  // In place: the order is the frames' order in the layer, which must not change.
  kept = at < 0 ? [...kept, entry] : kept.map((k, i) => (i === at ? entry : k));
  changed();
}

/** Ends a kept web service: its frame goes. */
export function closePreview(key: string): void {
  if (!kept.some((k) => k.key === key)) return;
  kept = kept.filter((k) => k.key !== key);
  changed();
}

function usePreviews(): Kept[] {
  return useSyncExternalStore((listener) => { listeners.add(listener); return () => listeners.delete(listener); }, () => kept, () => kept);
}

/** Where a web service (or a visualization, `file`) shows in its chat's side panel; opening it keeps it. */
export function PreviewSlot({ station, port, file, name, service: job, restarting, draftKey }:
  { station: string; port?: number; file?: FileSource; name: string; service?: string; restarting: Restarting | null; draftKey?: string }) {
  const service = file ? fileService(file) : job ?? "";
  const key = previewKey(station, service);
  const own = useHref(useLink()(`/services/${encodeURIComponent(service)}`));
  const external = file ? undefined : own;
  const { pathname } = useLocation();
  // Back to its chat, with it open again (Chat.tsx's useAskedFile for a visualization).
  const back = file ? `${pathname}?file=${encodeURIComponent(file.name)}` : `${pathname}?service=${encodeURIComponent(service)}`;
  const restarts = restarting?.restarts ?? null;
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    keep({ key, station, port, file, name, service, external, back, restarting: restarts === null ? null : { restarts }, draftKey });
  }, [key, station, port, file?.session, file?.path, name, service, external, back, restarts, draftKey]); // eslint-disable-line react-hooks/exhaustive-deps
  useLayoutEffect(() => {
    const slot = ref.current!;
    slots.set(key, slot);
    changed();
    return () => {
      if (slots.get(key) === slot) slots.delete(key);
      changed();
    };
  }, [key]);
  return <div ref={ref} className={css.slot} />;
}

/**
 * The small ones' cards (their page alone, its bar put away): this big (unless resized), this far from the window's
 * edges and apart.
 * At rest the latest one shows, the ones behind it an edge each (`peek` apart, `shrink` smaller each, no more than
 * `behind`); pointed at, they are all laid out, in columns up from the corner. Tucked away, only a capsule is there.
 */
const SMALL = { width: 280, height: 176, margin: 16, gap: 12, peek: 7, shrink: 0.06, behind: 2 };
/** How long the pointer can be off them (crossing the gap between two) before they go back to rest. */
const LINGER = 250;
const TUCKED = "stillfail.previewsTucked";
/** The small ones' size, as dragged by their top and left edges; no smaller than MIN, no bigger than the window
 * leaves room for. */
const SIZE = "stillfail.previewsSize";
const MIN = { width: 180, height: 112 };

interface Size { width: number; height: number }
function savedSize(): Size {
  try {
    const { width, height } = JSON.parse(localStorage.getItem(SIZE) ?? "null") ?? {};
    if (typeof width === "number" && typeof height === "number") return { width, height };
  } catch { /* the default */ }
  return { width: SMALL.width, height: SMALL.height };
}
const fit = ({ width, height }: Size): Size => ({
  width: Math.round(Math.max(MIN.width, Math.min(width, innerWidth - 2 * SMALL.margin))),
  height: Math.round(Math.max(MIN.height, Math.min(height, innerHeight - 2 * SMALL.margin))),
});
/** A small one's card: `size`, or, for a page laid out at a size of its own (viewport.ts), as much room in that
 * page's shape (a phone's tall, a desktop's wide), no bigger than the window leaves. */
function shapeOf(key: string, size: Size): Size {
  const box = fit(size);
  const own = viewportOf(key);
  if (!own || own.height === null) return box;
  const ratio = own.width / own.height, area = box.width * box.height;
  const width = Math.sqrt(area * ratio), height = Math.sqrt(area / ratio);
  const k = Math.min(1, (innerWidth - 2 * SMALL.margin) / width, (innerHeight - 2 * SMALL.margin) / height);
  return { width: Math.round(width * k), height: Math.round(height * k) };
}
/** The grip: GAP outside the card's corner, following it (the same shape, GAP more radius), its ends a little short
 * of where the corner meets the straight edges. */
const GRIP = { gap: 5, stroke: 4, trim: 0.26 };
function shapeGrip(svg: SVGSVGElement | null): void {
  const card = svg?.parentElement;
  if (!svg || !card) return;
  const style = getComputedStyle(card);
  const radius = parseFloat(style.borderTopLeftRadius) + GRIP.gap;
  // superellipse(k) is |x|^(2^k) + |y|^(2^k) = 1; round is k = 1.
  const k = /superellipse\(([\d.]+)\)/.exec(style.getPropertyValue("corner-shape"))?.[1];
  const n = 2 ** (k ? Number(k) : 1);
  const pad = GRIP.stroke, size = radius + 2 * pad;
  const points: string[] = [];
  for (let i = 0; i <= 24; i++) {
    const t = (Math.PI / 2) * (GRIP.trim + ((1 - 2 * GRIP.trim) * i) / 24);
    const x = radius * (1 - Math.cos(t) ** (2 / n)), y = radius * (1 - Math.sin(t) ** (2 / n));
    points.push(`${(x + pad).toFixed(2)} ${(y + pad).toFixed(2)}`);
  }
  svg.setAttribute("viewBox", `0 0 ${size} ${size}`);
  Object.assign(svg.style, { top: `${-GRIP.gap - pad}px`, left: `${-GRIP.gap - pad}px`, width: `${size}px`, height: `${size}px` });
  svg.firstElementChild!.setAttribute("d", `M${points.join("L")}`);
}
type Edge = "top" | "left" | "corner";
const EDGES: Edge[] = ["top", "left", "corner"];

interface Box { x: number; y: number; w: number; h: number }
type Mode = "full" | "small" | "hidden";
/** Where a frame is seen: `area`, with its bar (whole) or without it (its page alone). */
interface Seen { area: Box; bar: boolean }
interface Placed { mode: Mode; box: Box; seen: Seen; to: Drawn; layout: string; style: string }
interface Drawn { transform: string; clipPath: string; opacity: string }

/** A small one's page is laid out this wide (as a window's would be; or at its own size, viewport.ts), and drawn
 * scaled down: all of it shows. */
const LAID = 800;

/** What makes way for the small ones: the room it gives them, and where it and their edge were when it last looked. */
const avoiding = new WeakMap<HTMLElement, { room: Follower; right: number; edge: number | null }>();
/** Makes way, in whatever is marked for it, for what is in the corner from `edge` on (none: no room is taken). It moves
 * only as the small ones come, go or change (and not while they are resized: it follows the edge dragged at once); the
 * first time it is seen (a page come in with small ones there), or as it moves or resizes itself (its side panel
 * opening or closing), it takes its room at once: what it shows stays clear of them, instead of running under them
 * and back. */
function avoid(edge: number | null): void {
  const resizing = document.documentElement.dataset.previewResizing !== undefined;
  for (const el of document.querySelectorAll<HTMLElement>("[data-avoid-previews]")) {
    const right = el.getBoundingClientRect().right;
    const room = edge === null ? 0 : Math.max(0, Math.round(right - edge));
    const was = avoiding.get(el);
    if (!was) {
      avoiding.set(el, { room: follower(room, (v) => el.style.setProperty("--avoid-previews", `${v}px`)), right, edge });
      el.style.setProperty("--avoid-previews", `${room}px`);
      continue;
    }
    if (resizing || Math.abs(was.right - right) > 0.5) was.room.jump(room);
    else if (was.edge !== edge) was.room.to(room);
    was.right = right;
    was.edge = edge;
  }
}

/** A frame over `box` (its bar `bar` high), drawn stretched over `seen`'s area. */
function draw(box: Box, bar: number, seen: Seen, opacity = 1): Drawn {
  const top = seen.bar ? 0 : bar;
  const sx = seen.area.w / box.w, sy = seen.area.h / Math.max(1, box.h - top);
  return {
    transform: `translate(${seen.area.x - box.x}px, ${seen.area.y - box.y - top * sy}px) scale(${sx}, ${sy})`,
    clipPath: `inset(${top}px 0px 0px 0px)`,
    opacity: String(opacity),
  };
}

const FRAME = ["x", "y", "w", "h", "top", "opacity"] as const;
const CARD = ["x", "y", "w", "h"] as const;
/** How a frame is drawn as it moves: the area it is seen in and how much of its top (its bar) is cut off, over its
 * `box` (where it is laid out, at once); and its card's place. */
interface Motions {
  el: HTMLDivElement;
  box: Box;
  frame: Record<(typeof FRAME)[number], Follower>;
  card: Record<(typeof CARD)[number], Follower>;
  drawFrame(): void;
  stop(): void;
}
function motionsFor(frame: HTMLDivElement, card: HTMLDivElement): Motions {
  const m: Motions = {
    el: frame,
    box: { x: 0, y: 0, w: 1, h: 1 },
    frame: {} as Motions["frame"],
    card: {} as Motions["card"],
    drawFrame() {
      const { box } = m, f = m.frame;
      const top = f.top.value;
      const sx = f.w.value / box.w, sy = f.h.value / Math.max(1, box.h - top);
      frame.style.transform = `translate(${f.x.value - box.x}px, ${f.y.value - box.y - top * sy}px) scale(${sx}, ${sy})`;
      frame.style.clipPath = `inset(${top}px 0px 0px 0px)`;
      frame.style.opacity = String(f.opacity.value);
    },
    stop() { for (const f of [...Object.values(m.frame), ...Object.values(m.card)]) f.stop(); },
  };
  for (const k of FRAME) m.frame[k] = follower(k === "opacity" ? 1 : 0, () => m.drawFrame());
  const side = { x: "left", y: "top", w: "width", h: "height" } as const;
  for (const k of CARD) m.card[k] = follower(0, (v) => { card.style[side[k]] = `${v}px`; });
  return m;
}

/** Every kept web service's frame, over the page: on its slot, or small in the corner. Once per window. */
export function Previews() {
  const all = usePreviews();
  const navigate = useNavigate();
  const frames = useRef(new Map<string, HTMLDivElement>());
  const cards = useRef(new Map<string, HTMLDivElement>());
  const placed = useRef(new Map<string, Placed>());
  const motions = useRef(new Map<string, Motions>());
  const motionOf = (key: string, frame: HTMLDivElement, card: HTMLDivElement): Motions => {
    let m = motions.current.get(key);
    if (!m || m.el !== frame) {
      m?.stop();
      m = motionsFor(frame, card);
      motions.current.set(key, m);
    }
    return m;
  };
  const capsule = useRef<HTMLButtonElement>(null);
  // The small ones, the latest last.
  const [deck, setDeck] = useState<string[]>([]);
  const order = useRef<string[]>([]);
  // Laid out while pointed at; only a capsule while tucked away.
  const [spread, setSpread] = useState(false);
  const [tucked, setTucked] = useState(() => localStorage.getItem(TUCKED) === "1");
  const state = useRef({ spread, tucked });
  state.current = { spread, tucked };
  const size = useRef(savedSize());
  const leaving = useRef(0);
  const enter = () => { clearTimeout(leaving.current); setSpread(true); };
  const leave = () => { clearTimeout(leaving.current); leaving.current = window.setTimeout(() => setSpread(false), LINGER); };
  const tuck = (value: boolean) => {
    localStorage.setItem(TUCKED, value ? "1" : "0");
    setTucked(value);
    setSpread(false);
  };
  // Dragged by an edge: the corner stays, and the card grows or shrinks towards the pointer, in its shape (its page's,
  // if it has one of its own; else as it was): all of them grow or shrink as much, and their pages only scale.
  const resize = (edge: Edge, key: string) => (e: React.PointerEvent<HTMLDivElement>) => {
    if (e.button !== 0) return;
    e.preventDefault();
    e.stopPropagation();
    const handle = e.currentTarget;
    handle.setPointerCapture(e.pointerId);
    const from = { x: e.clientX, y: e.clientY, ...fit(size.current) };
    const card = shapeOf(key, size.current);
    // No smaller than MIN, no bigger than the window leaves, either way.
    const least = Math.max(MIN.width / from.width, MIN.height / from.height);
    const most = Math.min((innerWidth - 2 * SMALL.margin) / from.width, (innerHeight - 2 * SMALL.margin) / from.height);
    document.documentElement.dataset.previewResizing = edge;
    const move = (m: PointerEvent) => {
      const k = Math.max(edge === "top" ? 0 : (card.width + from.x - m.clientX) / card.width,
        edge === "left" ? 0 : (card.height + from.y - m.clientY) / card.height);
      const to = Math.min(most, Math.max(least, k));
      size.current = { width: Math.round(from.width * to), height: Math.round(from.height * to) };
    };
    const end = () => {
      handle.removeEventListener("pointermove", move);
      handle.removeEventListener("pointerup", end);
      handle.removeEventListener("pointercancel", end);
      delete document.documentElement.dataset.previewResizing;
      localStorage.setItem(SIZE, JSON.stringify(size.current));
    };
    handle.addEventListener("pointermove", move);
    handle.addEventListener("pointerup", end);
    handle.addEventListener("pointercancel", end);
  };
  // Back to the default size.
  const unsize = () => {
    size.current = { width: SMALL.width, height: SMALL.height };
    localStorage.removeItem(SIZE);
  };
  useEffect(() => {
    for (const key of placed.current.keys()) if (!all.some((k) => k.key === key)) placed.current.delete(key);
    for (const [key, m] of motions.current) if (!all.some((k) => k.key === key)) { m.stop(); motions.current.delete(key); }
    if (!all.length) {
      order.current = [];
      setDeck([]);
      avoid(null);
      return;
    }
    let raf = 0;
    // Each frame, as its slot moves (the panel resized, eased in, the page scrolled) or goes.
    const place = () => {
      const modes = new Map<string, Mode>();
      const slotted = new Map<string, DOMRect>();
      for (const entry of all) {
        const slot = slots.get(entry.key)?.getBoundingClientRect();
        if (slot) slotted.set(entry.key, slot);
        modes.set(entry.key, !slot ? "small" : slot.width && slot.height ? "full" : "hidden");
      }
      const small = order.current.filter((k) => modes.get(k) === "small");
      for (const entry of all) if (modes.get(entry.key) === "small" && !small.includes(entry.key)) small.push(entry.key);
      if (small.length !== order.current.length || small.some((k, i) => k !== order.current[i])) {
        order.current = small;
        setDeck(small);
      }
      const { spread, tucked } = state.current;
      const right = innerWidth - SMALL.margin;
      // Over the capsule while tucked away; else from the corner.
      const bottom = innerHeight - SMALL.margin - (tucked && capsule.current ? capsule.current.offsetHeight + SMALL.gap : 0);
      const cardOf = new Map(small.map((k) => [k, shapeOf(k, size.current)]));
      // Laid out: the latest first, in columns up from the corner, each as wide as its widest.
      const laidOut = new Map<string, Box>();
      let column = right, columnWidth = 0, y = bottom;
      for (const key of [...small].reverse()) {
        const { width, height } = cardOf.get(key)!;
        if (y !== bottom && y - height < SMALL.margin) { column -= columnWidth + SMALL.gap; columnWidth = 0; y = bottom; }
        laidOut.set(key, { x: column - width, y: y - height, w: width, h: height });
        y -= height + SMALL.gap;
        columnWidth = Math.max(columnWidth, width);
      }
      for (const entry of all) {
        const frame = frames.current.get(entry.key);
        const card = cards.current.get(entry.key);
        if (!frame || !card) continue;
        const mode = modes.get(entry.key)!;
        const was = placed.current.get(entry.key);
        const slot = slotted.get(entry.key);
        // A small one's bar is put away (Previews.css.ts).
        const bar = mode === "small" ? 0 : frame.querySelector("form")?.offsetHeight ?? 0;
        let box = mode === "full" ? { x: slot!.left, y: slot!.top, w: slot!.width, h: slot!.height }
          : was?.box ?? { x: innerWidth - 640, y: 64, w: 600, h: innerHeight - 96 };
        let at: Seen = { area: box, bar: true };
        let layout: string = mode, shell: Box | null = null, seen = true;
        if (mode === "small") {
          // The latest first: in the corner at rest, the first laid out.
          const i = small.length - 1 - small.indexOf(entry.key);
          const { width, height } = cardOf.get(entry.key)!;
          if (spread) {
            shell = laidOut.get(entry.key)!;
          } else {
            const d = Math.min(i, SMALL.behind);
            const k = 1 - SMALL.shrink * d;
            shell = { x: right - width * (1 + k) / 2, y: bottom - height - SMALL.peek * d, w: width * k, h: height * k };
            seen = !tucked && i <= SMALL.behind;
            // Tucked away: into the capsule.
            if (tucked) shell = { x: right - width * 0.3, y: innerHeight - SMALL.margin - height * 0.3, w: width * 0.3, h: height * 0.3 };
          }
          layout = `small ${spread} ${tucked} ${i}`;
          // Laid out as a window of the card's shape (its bar put away): its page reflows to it, and all of it shows.
          const area = shell;
          const laid = viewportOf(entry.key)?.width ?? LAID;
          box = { x: area.x, y: area.y - bar, w: laid, h: bar + (laid * area.h) / area.w };
          at = { area, bar: false };
          // Its corners are the card's, at its scale.
          frame.style.setProperty("--scale", String(area.w / laid));
          card.dataset.front = String(i === 0);
          // Each page just over its card, the latest's over the rest (as they cross, laid out or put back).
          card.style.zIndex = String(21 - 2 * Math.min(i, 9));
          frame.style.zIndex = String(20 - 2 * Math.min(i, 9));
        } else {
          frame.style.zIndex = "0";
        }
        const to = draw(box, bar, at, seen ? 1 : 0);
        const style = `${mode} ${box.x} ${box.y} ${box.w} ${box.h} ${to.transform} ${to.clipPath} ${to.opacity}`;
        if (style === was?.style) continue;
        Object.assign(frame.style, { left: `${box.x}px`, top: `${box.y}px`, width: `${box.w}px`, height: `${box.h}px` });
        frame.dataset.mode = mode;
        card.dataset.mode = shell && seen ? "small" : "hidden";
        // Going small, back into its chat, laid out or back to rest: it moves there, from where it is (and on to where
        // that goes, if it moves on meanwhile); anything else is taken at once.
        const moved = !!was && was.mode !== "hidden" && mode !== "hidden" && was.layout !== layout;
        const m = motionOf(entry.key, frame, card);
        m.box = box;
        const goal = { x: at.area.x, y: at.area.y, w: at.area.w, h: at.area.h, top: at.bar ? 0 : bar, opacity: seen ? 1 : 0 };
        const going = moved || Object.values(m.frame).some((f) => f.moving);
        for (const k of FRAME) if (going) m.frame[k].to(goal[k]); else m.frame[k].jump(goal[k]);
        m.drawFrame();
        if (shell) {
          const cardGoing = (moved && was!.mode === "small" && mode === "small") || Object.values(m.card).some((f) => f.moving);
          for (const k of CARD) if (cardGoing) m.card[k].to(shell[k]); else m.card[k].jump(shell[k]);
        }
        placed.current.set(entry.key, { mode, box, seen: at, to, layout, style });
      }
      // What the chat keeps free: the small ones at rest (not as they are laid out while pointed at), or the capsule.
      const pill = tucked ? capsule.current?.getBoundingClientRect() : undefined;
      const front = small.length ? cardOf.get(small[small.length - 1]!)! : null;
      avoid(!front ? null : pill ? pill.left - SMALL.margin : tucked ? null : right - front.width - SMALL.margin);
      raf = requestAnimationFrame(place);
    };
    place();
    return () => cancelAnimationFrame(raf);
  }, [all]);
  useEffect(() => () => clearTimeout(leaving.current), []);
  const shown = deck.map((key) => all.find((k) => k.key === key)).filter((k): k is Kept => k !== undefined);
  return (
    <div className={css.layer} data-spread={spread || undefined}>
      {all.map((entry) => (
        <div key={entry.key} ref={(el) => { if (el) frames.current.set(entry.key, el); else frames.current.delete(entry.key); }} className={css.frame} data-mode="hidden">
          <ServiceFrame station={entry.station} port={entry.port} file={entry.file} name={entry.name} service={entry.service} external={entry.external} restarting={entry.restarting} draftKey={entry.draftKey} />
        </div>
      ))}
      {/* Over a small one's page (which lets the pointer through): its name, and a click goes back. */}
      {all.map((entry) => (
        <div key={entry.key} ref={(el) => { if (el) cards.current.set(entry.key, el); else cards.current.delete(entry.key); }} className={css.card} data-mode="hidden"
          role="button" tabIndex={0} aria-label={`回到「${entry.name}」`} onPointerEnter={enter} onPointerLeave={leave}
          onClick={() => navigate(entry.back)} onKeyDown={(e) => { if (e.key === "Enter" && e.target === e.currentTarget) navigate(entry.back); }}>
          <span className={css.name}>
            <span className={css.dot} data-restarting={entry.restarting ? true : undefined} />
            <span className={css.nameText}>{entry.name}</span>
            {!spread && shown.length > 1 && <span className={css.count}>+{shown.length - 1}</span>}
          </span>
          {EDGES.map((edge) => (
            <div key={edge} className={css.edge} data-edge={edge} aria-hidden onPointerDown={resize(edge, entry.key)}
              onClick={(e) => e.stopPropagation()} onDoubleClick={(e) => { e.stopPropagation(); unsize(); }} />
          ))}
          <svg ref={shapeGrip} className={css.grip} aria-hidden><path /></svg>
          <span className={css.actions}>
            {!tucked && (
              <Tip label="收起">
                <button type="button" className={css.action} aria-label="收起成胶囊" onClick={(e) => { e.stopPropagation(); tuck(true); }}>
                  <Minus size={12} strokeWidth={2} />
                </button>
              </Tip>
            )}
            <Tip label="关闭">
              <button type="button" className={css.action} aria-label={`关闭「${entry.name}」`} onClick={(e) => { e.stopPropagation(); closePreview(entry.key); }}>
                <Close size={12} strokeWidth={2} />
              </button>
            </Tip>
          </span>
        </div>
      ))}
      {tucked && shown.length > 0 && (
        <button ref={capsule} type="button" className={css.capsule} onPointerEnter={enter} onPointerLeave={leave} onClick={() => tuck(false)}>
          <Web size={14} strokeWidth={1.75} />
          {shown.length === 1 ? shown[0]!.name : `${shown.length} 个服务`}
        </button>
      )}
    </div>
  );
}
