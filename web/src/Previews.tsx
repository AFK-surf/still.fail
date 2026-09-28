// The web services opened beside chats, kept for as long as the window is open: moving to another chat or page does
// not close one (nor load it anew); it goes small into the bottom-right corner, still live, and back into its chat's
// side panel when that is in view again. Only closing it (its tab in the chat, or × on the small one) ends it.
//
// A frame loads anew whenever it moves in the document, so every kept one is drawn here, in one layer over the page,
// and never moves in it: the chat's side panel has a slot (PreviewSlot) that only says where the frame should be.
import { useEffect, useLayoutEffect, useRef, useState, useSyncExternalStore } from "react";
import { useHref, useLocation, useNavigate } from "react-router";
import { ServiceFrame, type Restarting } from "./Preview.tsx";
import { useLink } from "./station.tsx";
import { Close, Minus, Web } from "./icons.tsx";
import { Tip } from "./ui.tsx";
import * as css from "./Previews.css.ts";

interface Kept {
  key: string;
  station: string;
  port: number;
  name: string;
  service: string;
  /** Its page of its own (the bar's "open on its own"). */
  external: string;
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

export const previewKey = (station: string, service: string) => `${station}\n${service}`;

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
  return useSyncExternalStore((listener) => { listeners.add(listener); return () => listeners.delete(listener); }, () => kept);
}

/** Where a web service shows in its chat's side panel; opening it keeps it. */
export function PreviewSlot({ station, port, name, service, restarting, draftKey }:
  { station: string; port: number; name: string; service: string; restarting: Restarting | null; draftKey?: string }) {
  const key = previewKey(station, service);
  const external = useHref(useLink()(`/services/${encodeURIComponent(service)}`));
  const { pathname } = useLocation();
  const back = `${pathname}?service=${encodeURIComponent(service)}`;
  const restarts = restarting?.restarts ?? null;
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    keep({ key, station, port, name, service, external, back, restarting: restarts === null ? null : { restarts }, draftKey });
  }, [key, station, port, name, service, external, back, restarts, draftKey]);
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
 * The small ones' cards (their page alone, its bar put away): this big, this far from the window's edges and apart.
 * At rest the latest one shows, the ones behind it an edge each (`peek` apart, `shrink` smaller each, no more than
 * `behind`); pointed at, they are all laid out, in columns up from the corner. Tucked away, only a capsule is there.
 */
const SMALL = { width: 280, height: 176, margin: 16, gap: 12, peek: 7, shrink: 0.06, behind: 2 };
const MOVE = { duration: 280, easing: "cubic-bezier(.2, .8, .2, 1)" };
/** How long the pointer can be off them (crossing the gap between two) before they go back to rest. */
const LINGER = 250;
const TUCKED = "ember.previewsTucked";

interface Box { x: number; y: number; w: number; h: number }
type Mode = "full" | "small" | "hidden";
/** Where a frame is seen: `area`, with its bar (whole) or without it (its page alone). */
interface Seen { area: Box; bar: boolean }
interface Placed { mode: Mode; box: Box; seen: Seen; to: Drawn; layout: string; style: string }
interface Drawn { transform: string; clipPath: string; opacity: string }

/** A small one's page is laid out this wide (as a window's would be), and drawn scaled down: all of it shows. */
const LAID = 800;

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

/** Every kept web service's frame, over the page: on its slot, or small in the corner. Once per window. */
export function Previews() {
  const all = usePreviews();
  const navigate = useNavigate();
  const frames = useRef(new Map<string, HTMLDivElement>());
  const cards = useRef(new Map<string, HTMLDivElement>());
  const placed = useRef(new Map<string, Placed>());
  const capsule = useRef<HTMLButtonElement>(null);
  // The small ones, the latest last.
  const [deck, setDeck] = useState<string[]>([]);
  const order = useRef<string[]>([]);
  // Laid out while pointed at; only a capsule while tucked away.
  const [spread, setSpread] = useState(false);
  const [tucked, setTucked] = useState(() => localStorage.getItem(TUCKED) === "1");
  const state = useRef({ spread, tucked });
  state.current = { spread, tucked };
  const leaving = useRef(0);
  const enter = () => { clearTimeout(leaving.current); setSpread(true); };
  const leave = () => { clearTimeout(leaving.current); leaving.current = window.setTimeout(() => setSpread(false), LINGER); };
  const tuck = (value: boolean) => {
    localStorage.setItem(TUCKED, value ? "1" : "0");
    setTucked(value);
    setSpread(false);
  };
  useEffect(() => {
    for (const key of placed.current.keys()) if (!all.some((k) => k.key === key)) placed.current.delete(key);
    if (!all.length) {
      order.current = [];
      setDeck([]);
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
      const perColumn = Math.max(1, Math.floor((bottom - SMALL.margin + SMALL.gap) / (SMALL.height + SMALL.gap)));
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
          if (spread) {
            const column = Math.floor(i / perColumn), row = i % perColumn;
            shell = { x: right - SMALL.width - column * (SMALL.width + SMALL.gap), y: bottom - SMALL.height - row * (SMALL.height + SMALL.gap), w: SMALL.width, h: SMALL.height };
          } else {
            const d = Math.min(i, SMALL.behind);
            const k = 1 - SMALL.shrink * d;
            shell = { x: right - SMALL.width * (1 + k) / 2, y: bottom - SMALL.height - SMALL.peek * d, w: SMALL.width * k, h: SMALL.height * k };
            seen = !tucked && i <= SMALL.behind;
            // Tucked away: into the capsule.
            if (tucked) shell = { x: right - SMALL.width * 0.3, y: innerHeight - SMALL.margin - SMALL.height * 0.3, w: SMALL.width * 0.3, h: SMALL.height * 0.3 };
          }
          layout = `small ${spread} ${tucked} ${i}`;
          // Laid out as a window of the card's shape (its bar put away): its page reflows to it, and all of it shows.
          const area = shell;
          box = { x: area.x, y: area.y - bar, w: LAID, h: bar + (LAID * area.h) / area.w };
          at = { area, bar: false };
          // Its corners are the card's, at its scale.
          frame.style.setProperty("--scale", String(area.w / LAID));
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
        Object.assign(frame.style, { left: `${box.x}px`, top: `${box.y}px`, width: `${box.w}px`, height: `${box.h}px`, ...to });
        frame.dataset.mode = mode;
        card.dataset.mode = shell && seen ? "small" : "hidden";
        if (shell) Object.assign(card.style, { left: `${shell.x}px`, top: `${shell.y}px`, width: `${shell.w}px`, height: `${shell.h}px` });
        // Going small, back into its chat, laid out or back to rest: it moves there, from where it was.
        const moved = was && was.mode !== "hidden" && mode !== "hidden" && was.layout !== layout;
        if (moved && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
          frame.animate([{ ...draw(box, bar, was.seen, Number(was.to.opacity)) }, { ...to }] as Keyframe[], MOVE);
          if (was.mode === "small" && mode === "small" && shell) {
            const from = was.seen.area;
            card.animate([
              { left: `${from.x}px`, top: `${from.y}px`, width: `${from.w}px`, height: `${from.h}px` },
              { left: `${shell.x}px`, top: `${shell.y}px`, width: `${shell.w}px`, height: `${shell.h}px` },
            ], MOVE);
          }
        }
        placed.current.set(entry.key, { mode, box, seen: at, to, layout, style });
      }
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
          <ServiceFrame station={entry.station} port={entry.port} name={entry.name} external={entry.external} restarting={entry.restarting} draftKey={entry.draftKey} />
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
          <span className={css.actions}>
            {!tucked && (
              <Tip label="收起">
                <button type="button" className={css.action} aria-label="收起成胶囊" onClick={(e) => { e.stopPropagation(); tuck(true); }}>
                  <Minus size={13} strokeWidth={2} />
                </button>
              </Tip>
            )}
            <Tip label="关闭">
              <button type="button" className={css.action} aria-label={`关闭「${entry.name}」`} onClick={(e) => { e.stopPropagation(); closePreview(entry.key); }}>
                <Close size={13} strokeWidth={2} />
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
