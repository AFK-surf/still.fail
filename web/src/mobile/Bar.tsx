// The phone's bottom bar (the Android app's ui/Bar.kt draws the same): the places of the bar in view, one of the
// device's bars (prefs `bars`, kept whole by the core), floating over the foot of a place's top page.
//
// - A frosted glass, its rim lit; a frosted ball of 68 over the place in view (under its icon, over 令), 6 past the
//   bar on every side. The page's primary action (placeActions.tsx: 令 on a chat page, 对话 已归档; a page's ＋)
//   sits in a notch cut into the bar's top, as far from it all round, the notch's shoulders rounded into the edge;
//   between two pages that have one, only its icon changes; on a page without, it shrinks away and the notch closes.
// - A tap on a place goes there; the ball travels on a spring as quick as the way is long (time ∝ √distance).
// - One stroke: a finger set on the bar and moved any way takes the ball, which keeps to the place a let-go would
//   choose, leaning a quarter of the way toward the finger. With more than one bar, leaving the bar upward opens the
//   panel: the glass grows up into a rectangle, a row per other bar above the bar, and the ball goes on into those
//   rows. The panel snaps as the ball does: open once the finger is a little way above the bar, closed once it comes
//   back below, never resting between (but for a quarter's lean toward the finger), each from where it is; let go on a
//   place: it (in another bar: that bar too); elsewhere, as the finger left it. A bar switch lands untouched.
// - Choosing another bar, the panel closes like a window over a stack of bars: the stack slides down until the chosen
//   bar is where the bar is, what is not chosen goes out at the glass's edges. Nothing fades.
import { springStep } from "@stillfail/ui/spring.ts";
import { useFrameDraw } from "./gesture.ts";
import { useEffect, useId, useLayoutEffect, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import type { ComponentType, ReactNode } from "react";
import { Archive, Chart, Chats, Folder, Im, Ling, Plus, Quota, type IconProps } from "@stillfail/ui/icons.tsx";
import { railLabel } from "../Rail.tsx";
import { prefs, setPrefs, usePrefs } from "../prefs.ts";
import { useChats, useStatus } from "../api.ts";
import { StationGlyph, glyphCounts } from "../StationGlyph.tsx";
import { reducedMotion } from "@stillfail/ui/motion.ts";
import * as css from "./Bar.css.ts";
import { usePlaceActions } from "./placeActions.tsx";
import type { PlaceAction } from "./parts.tsx";
import { t } from "../i18n.ts";

/** The places a bar can hold (the core's BAR_PLACES), and the chats' family: 令 is their primary action. */
export type BarPlace = "chats" | "files" | "stations" | "profiles" | "connects" | "usage" | "archive";
export const BAR_PLACES: BarPlace[] = ["chats", "files", "stations", "profiles", "connects", "usage", "archive"];
export const CHAT_FAMILY: BarPlace[] = ["chats", "archive"];

/** Each place's page, under the workspace (`/w/<id>`): the address a place's top page is at. */
export const PLACE_PATHS: Record<BarPlace, string> = {
  chats: "", files: "/files", stations: "/settings/stations", profiles: "/settings/profiles",
  connects: "/settings/connects", usage: "/settings/usage", archive: "/archive",
};

/** The place a page of the workspace is the top page of, or null. */
export function placeOfPath(path: string, home: string): BarPlace | null {
  const rest = path.replace(/\/$/, "").slice(home.length);
  for (const p of BAR_PLACES) if (PLACE_PATHS[p] === rest) return p;
  return null;
}

const H = 56; // the bar
const R = H / 2;
const C0 = 28; // a place's middle from the bar's end: as far as from its top and foot
const BALL = 68; // the ball: 6 past the bar on every side
const DROP = 56; // 令
const GAP = 6; // between 令 and its notch, all round
const LIFT = 4; // 令's middle above the bar's top
const FILLET = 8; // the notch's shoulders
const ROW = 56; // a bar in the panel: as tall as the bar
const OVER = 20; // room above the panel for its overshoot
const LEAN = 0.25; // how far the held ball leans toward the finger
const SLOT = 90; // a hop of one place: the distance that keeps the spring at tension 300
const ZETA = 0.635;
const friction = (tension: number) => 2 * ZETA * Math.sqrt(tension);

const ICONS: Partial<Record<BarPlace, ComponentType<IconProps>>> = { chats: Chats, files: Folder, profiles: Quota, connects: Im, usage: Chart, archive: Archive };

/** One number on a spring, stepped by the bar's frame loop (Hooke and a damper, the step a frame's time). */
class Spring {
  value: number;
  velocity = 0;
  target: number;
  tension = 300;
  damping = friction(300);
  constructor(start: number) { this.value = start; this.target = start; }
  to(target: number, tension = this.tension, damping = friction(tension)): void { this.target = target; this.tension = tension; this.damping = damping; }
  jump(at: number): void { this.value = at; this.target = at; this.velocity = 0; }
  get moving(): boolean { return this.velocity !== 0 || this.value !== this.target; }
  step(dt: number): void {
    const next = springStep(this.value, this.velocity, this.target, this.tension, this.damping, dt);
    this.value = next.value;
    this.velocity = next.velocity;
    if (Math.abs(this.velocity) < 0.01 && Math.abs(this.value - this.target) < 0.01) this.jump(this.target);
  }
}

/** The cut a notch makes in a top edge at y0: a circle of radius r about (cx, y0 + c), met by the edge through two
 *  fillets. `inner`: from the left shoulder round to the right one; `l`: where it leaves the edge. */
function notchCut(cx: number, y0: number, c: number, r: number, f: number): { inner: string; edge: string; l: number } | null {
  const dy = f - c, reach = (r + f) ** 2 - dy * dy;
  if (c + r <= 0.5 || reach <= 0) return null;
  const xf = Math.sqrt(reach), l = cx - xf, rr = cx + xf;
  const at = (fx: number) => { const vx = cx - fx, vy = c - f, n = Math.hypot(vx, vy); return [fx + f * vx / n, y0 + f + f * vy / n] as const; };
  const [tlx, tly] = at(l), [trx, try_] = at(rr);
  const inner = `A${f} ${f} 0 0 1 ${tlx} ${tly}A${r} ${r} 0 0 0 ${trx} ${try_}A${f} ${f} 0 0 1 ${rr} ${y0}`;
  return { inner, edge: `M${l} ${y0}${inner}`, l };
}

/** The glass's outline: a rounded rectangle from `top` to `bottom`, the notch (if any) cut into its top edge. */
function outline(w: number, top: number, bottom: number, notch: { inner: string; l: number } | null): string {
  return `M0 ${top + R}A${R} ${R} 0 0 1 ${R} ${top}` + (notch ? `L${notch.l} ${top}${notch.inner}` : "")
    + `L${w - R} ${top}A${R} ${R} 0 0 1 ${w} ${top + R}L${w} ${bottom - R}A${R} ${R} 0 0 1 ${w - R} ${bottom}L${R} ${bottom}A${R} ${R} 0 0 1 0 ${bottom - R}Z`;
}

/** The places' middles for n places, k how open the notch is: both ends 28 in, the others between, kept clear of it. */
function centres(w: number, k: number, n: number): number[] {
  const closed = (w - 2 * C0) / 3, open = (w / 2 - (DROP / 2 + GAP) - 6 - (H - 12) / 2) - C0;
  const sp = closed + (open - closed) * k;
  if (n >= 4) return [C0, C0 + sp, w - C0 - sp, w - C0];
  if (n === 3) return [C0, C0 + ((w / 2 - C0) - (w / 2 - C0 - sp) * k), w - C0];
  if (n === 2) return [C0, w - C0];
  return [C0];
}

export interface BottomBarProps {
  scope: string;
  /** The place whose top page is in view (null: another page, as one opened by a link). */
  place: BarPlace | null;
  /** Shown: the top page is a place's top page. Otherwise it goes down out of the way. */
  shown: boolean;
  go: (place: BarPlace) => void;
  /** Told when the panel opens and closes (the shell keeps a page's swipe back out of it). */
  onPanel?: (open: boolean) => void;
}

export function BottomBar({ scope, place, shown, go, onPanel }: BottomBarProps) {
  const bars = useBars();
  const sets = bars.sets as BarPlace[][];
  const cur = Math.min(bars.current, sets.length - 1);
  const items = sets[cur] ?? [];
  const others = useMemo(() => sets.map((_, i) => i).filter((i) => i !== cur), [sets, cur]);

  // What waits: the stations' trouble (the core's, as Home shows them).
  const chats = useChats(scope, false).value;
  const status = useStatus(scope);
  const dots: Partial<Record<BarPlace, "red">> = {};
  if (chats?.trouble) dots.stations = "red";
  const glyph = glyphCounts({ glyph: chats?.glyph });
  // The stations in words (the core's), as the glyph draws them, and what is wrong with them: what Home's corner said.
  const said = (glyph.asleep ? status?.text : undefined) || (chats?.glyph?.label ?? "");
  const stationsSaid = chats?.trouble ? t("web-mobile.home.stationTrouble", { said, trouble: chats.trouble.text }) : t("web-mobile.home.station", { said });
  const labelOf = (key: BarPlace) => (key === "stations" && said ? stationsSaid : railLabel(key));
  // Spring frames do not redraw each icon (especially the station's animated SVG).
  const icons = useMemo(() => ({
    ...Object.fromEntries(Object.entries(ICONS).map(([key, I]) => [key, <I size={28} />])),
    stations: <StationGlyph counts={glyph} size={28} />,
  }) as Partial<Record<BarPlace, ReactNode>>, [glyph.online, glyph.dim, glyph.failing, glyph.working, glyph.asleep, glyph.connecting]);
  const icon = (key: BarPlace) => icons[key];

  const wrap = useRef<HTMLDivElement>(null);
  const [w, setW] = useState(0);
  useLayoutEffect(() => {
    const el = wrap.current;
    if (!el) return;
    const read = () => setW(el.offsetWidth);
    read();
    const o = new ResizeObserver(read);
    o.observe(el);
    return () => o.disconnect();
  }, []);

  // ---- springs, stepped by one frame loop; only the outline changing redraws the bar
  const s = useRef<{ o: Spring; k: Spring; held: Spring; x: Spring; y: Spring } | null>(null);
  s.current ??= { o: new Spring(0), k: new Spring(0), held: new Spring(0), x: new Spring(0), y: new Spring(0) };
  const sp = s.current;
  const [, tick] = useState(0);
  const ball = useRef<HTMLDivElement>(null);
  const drawBall = useRef<() => void>(() => {});
  const drawShape = useRef<() => void>(() => {});
  const swapping = useRef(false);
  const glass = useRef<HTMLDivElement>(null), rowPanel = useRef<HTMLDivElement>(null), actionButton = useRef<HTMLButtonElement>(null);
  const rim = useRef<SVGPathElement>(null), gradient = useRef<SVGLinearGradientElement>(null);
  const shadowInside = useRef<SVGRectElement>(null), shadowShape = useRef<SVGRectElement>(null);
  const tabEls = useRef(new Map<string, HTMLButtonElement>());
  const loop = useRef({ raf: 0, last: 0 });
  // What the panel's spring is to do once it is still (a bar being chosen: chosen). Done at once if cut short: left
  // undone, the bar would stay half switched.
  const panelDone = useRef<(() => void) | null>(null);
  const run = () => {
    if (loop.current.raf) return;
    loop.current.last = performance.now();
    const frame = (now: number) => {
      const dt = Math.max(0, (now - loop.current.last) / 1000);
      loop.current.last = now;
      const all = Object.values(sp);
      // Outline and ball draw directly. Only a changing stack still needs a React commit.
      const reshaping = sp.o.moving || sp.k.moving;
      const instant = reducedMotion();
      for (const spring of all) if (instant) spring.jump(spring.target); else if (spring.moving) spring.step(dt);
      if (!sp.o.moving && panelDone.current) { const done = panelDone.current; panelDone.current = null; done(); }
      drawBall.current();
      if (reshaping) { drawShape.current(); if (swapping.current) tick((n) => n + 1); }
      loop.current.raf = all.some((spring) => spring.moving) ? requestAnimationFrame(frame) : 0;
    };
    loop.current.raf = requestAnimationFrame(frame);
  };
  useEffect(() => () => cancelAnimationFrame(loop.current.raf), []);

  // ---- the panel (only with more than one bar)
  const [open, setOpenState] = useState(false);
  const opened = useRef(open);
  const setOpen = (next: boolean) => { opened.current = next; setOpenState(next); };
  const panel = (next: boolean, then?: () => void, config?: [number, number]) => {
    const before = panelDone.current;
    panelDone.current = then ?? null;
    before?.();
    setOpen(next);
    onPanel?.(next);
    const [tension, damping] = config ?? (next ? [260, 17] : [320, 26]);
    sp.o.to(next ? 1 : 0, tension, damping);
    run();
  };
  // Fewer bars than the panel had rows (one taken away in settings): closed.
  useEffect(() => { if (others.length === 0 && open) panel(false); }, [others.length]); // eslint-disable-line react-hooks/exhaustive-deps
  // Away (a page pushed over the place): closed, the ball let go.
  useEffect(() => { if (!shown) { if (open) panel(false); lost(); } }, [shown]); // eslint-disable-line react-hooks/exhaustive-deps

  const rows = Math.max(1, others.length);
  const PANEL = H + rows * ROW + OVER;
  const rowTop = PANEL - H; // the bar's top, in the panel
  const travel = rowTop - OVER; // how far the glass's top goes up as it opens
  const o = sp.o.value;
  const clipTop = Math.max(0, OVER + travel * (1 - o));
  const barMid = rowTop + R;
  const rowMid = (n: number) => OVER + n * ROW + ROW / 2;
  // How the rows are drawn as the panel is open: faded in from a third open, a little low until open, up with its
  // overshoot past it.
  const rowsLook = (at: number) => ({ alpha: Math.max(0, Math.min(1, (at - 0.35) / 0.65)), dy: (1 - Math.min(1, at)) * 14 - Math.max(0, at - 1) * travel });

  // ---- the notch: open on a page with a primary action, the panel closed; the last one drawn as it goes
  const actions = usePlaceActions();
  const action = (place && actions[place]) || null;
  const drawn = useRef<PlaceAction | null>(null);
  if (action) drawn.current = action;
  const inChats = action !== null && !open;
  // Its place has one (a spring as the place changes); the panel drawn up closes it, as far as it is drawn (the finger's,
  // not a motion of its own).
  sp.k.to(action !== null ? 1 : 0, 300, 30);
  if (!w) sp.k.jump(action !== null ? 1 : 0); // as it is when first drawn, not opened as the page comes
  const k = sp.k.value * (1 - Math.min(1, o * 2));

  const final = centres(w, inChats ? 1 : 0, items.length);
  const now = centres(w, k, items.length);
  const nearest = (xs: number[], x: number, from = 0) => { let best = from; for (let j = from; j < xs.length; j++) if (Math.abs(xs[j]! - x) < Math.abs(xs[best]! - x)) best = j; return best; };

  // ---- the ball
  const [finger, setFinger] = useState<{ x: number; y: number | null } | null>(null);
  sp.held.to(finger ? 1 : 0, 420, 16);
  // The place a let-go would choose: in the bar, or (the panel open) in the row under the finger.
  const cand = (() => {
    if (!finger || !w) return null;
    if (finger.y !== null && finger.y < rowTop - 4 && others.length) {
      const n = Math.max(0, Math.min(others.length - 1, Math.floor((finger.y - OVER) / ROW))), i = others[n]!;
      const xs = centres(w, 0, sets[i]!.length), j = nearest(xs, finger.x);
      return { x: xs[j]!, y: rowMid(n), set: i, key: sets[i]![j]! };
    }
    const j = nearest(final, finger.x);
    return { x: final[j]!, y: barMid, set: cur, key: items[j]! };
  })();
  const ai = place ? items.indexOf(place) : -1;
  const goalX = cand ? cand.x + (finger!.x - cand.x) * LEAN : final[Math.max(0, ai)] ?? C0;
  const goalY = cand ? cand.y + ((finger!.y ?? barMid) - cand.y) * LEAN : barMid;
  // How quick it goes: a held ball follows at 300; sent to a place, as quick as the way is long.
  const sent = useRef({ place, held: false, tension: 300 });
  if (!w || sp.x.target === 0) { sp.x.jump(goalX); sp.y.jump(goalY); }
  if (finger) sent.current.tension = 300;
  else if (sent.current.place !== place || sent.current.held) sent.current.tension = Math.min(700, Math.max(90, 300 * SLOT / Math.max(8, Math.abs(goalX - sp.x.value))));
  sent.current.place = place;
  sent.current.held = !!finger;
  sp.x.to(goalX, sent.current.tension);
  sp.y.to(goalY, 300);
  // Run whenever a target moved this draw.
  useLayoutEffect(() => { if (Object.values(sp).some((spring) => spring.moving)) run(); });

  // ---- choosing another bar: the stack slides down inside the closing glass, the ball riding the place chosen
  const [swap, setSwap] = useState<{ i: number; n: number; from: number; key: BarPlace | null; done?: boolean } | null>(null);
  swapping.current = swap !== null;
  const pickSet = (i: number, key: BarPlace | null) => {
    if (swap) return;
    setSwap({ i, n: others.indexOf(i), from: Math.max(0.2, sp.o.value), key });
    // The place at once, under the glass closing over it: not once that has landed (the user: a delay).
    if (key && key !== place) go(key);
    panel(false, () => {
      setSwap((was) => was && { ...was, done: true });
      setBars(bars.sets as BarPlace[][], i);
    }, [200, 28]);
  };
  // Landed and drawn as the chosen bar: the stack gone (it is where the bar's places are), the ball going on. Away (a page
  // opened over the place as the switch landed, which the place does not take the stead of), it has landed too.
  useLayoutEffect(() => {
    if (swap?.done && cur === swap.i && (!swap.key || place === swap.key || !shown)) {
      setSwap(null);
    }
  });
  const swapAt = swap && w ? (() => {
    const t = Math.max(0, Math.min(1, 1 - o / swap.from));
    const shift = (barMid - rowMid(swap.n)) * t;
    const into = sets[swap.i]!;
    const landsOnChats = swap.key ? !!actions[swap.key] : inChats;
    const from = centres(w, 0, into.length), to = centres(w, landsOnChats ? 1 : 0, into.length);
    // In its first frame the rows as they were drawn (faded in and low by as much as the panel was open, rowsLook), going
    // to what the bar is as it slides: no change of look at the moment a bar is chosen.
    const was = rowsLook(swap.from), dy = was.dy * (1 - t), alpha = was.alpha + (1 - was.alpha) * t;
    return { shift, into, dy, alpha, xs: into.map((_, j) => from[j]! + (to[j]! - from[j]!) * t), y: rowMid(swap.n) + shift + dy };
  })() : null;
  // The ball rides the place chosen: sent there on a stiff spring from where it was, not put there.
  const ballOn = swapAt && swap!.key ? { x: swapAt.xs[swapAt.into.indexOf(swap!.key)]!, y: swapAt.y } : null;
  if (ballOn) { sp.x.to(ballOn.x, 700); sp.y.to(ballOn.y, 700); }

  // ---- the finger
  // `panel`: the finger has the panel: open above a line over the bar, closed below it, leaning a quarter of the way
  // toward the finger (o0 at the finger's start, from its y), as the ball keeps to a place.
  const press = useRef({ x: 0, y: 0, taken: false, panel: false, o0: 0, slid: false, left: 0, top: 0 });
  const UP = 24, DOWN = 16; // the line: crossed upward 24 over the bar's top, back below 16 over it
  type Point = Pick<ReactPointerEvent, "clientX" | "clientY" | "buttons" | "pointerId">;
  const local = (e: Point) => ({ x: e.clientX - press.current.left, y: e.clientY - press.current.top });
  const down = (e: ReactPointerEvent) => {
    moves.cancel();
    const box = wrap.current!.getBoundingClientRect();
    press.current = { x: e.clientX, y: e.clientY, taken: false, panel: sp.o.value > 0.02 || open, o0: sp.o.value, slid: false, left: box.left, top: box.top };
  };
  const moves = useFrameDraw<Point>((e) => {
    // A bar switch landing: it lands untouched; the finger is the finger's once it has.
    if (swap) return;
    const p = press.current;
    if (!p.taken) return;
    const at = local(e), several = others.length > 0;
    if (several) {
      const above = rowTop - at.y;
      if (!p.panel && above > UP) p.panel = true;
      if (p.panel) {
        // Open or closed by the line (a little apart each way, so it does not flicker on it); never in between but
        // for the lean toward the finger.
        const snapped = opened.current ? (above < DOWN ? 0 : 1) : (above > UP ? 1 : 0);
        if ((snapped === 1) !== opened.current) { setOpen(snapped === 1); onPanel?.(snapped === 1); }
        const raw = p.o0 + (p.y - e.clientY - (p.o0 > 0.02 ? 0 : 8)) / travel;
        const lean = Math.max(0, Math.min(1.1, snapped + (raw - snapped) * LEAN));
        const [tension, damping] = snapped ? [260, 17] : [320, 26];
        sp.o.to(lean, tension, damping);
        run();
      }
    }
    setFinger({ x: at.x, y: several && p.panel ? Math.max(rowMid(0), Math.min(barMid, at.y)) : null });
  });
  const move = (e: ReactPointerEvent) => {
    if (swap) return;
    const p = press.current;
    if (!p.taken && e.buttons !== 0 && Math.hypot(e.clientX - p.x, e.clientY - p.y) > 8) {
      p.taken = true;
      wrap.current!.setPointerCapture(e.pointerId);
    }
    if (p.taken) moves.set({ clientX: e.clientX, clientY: e.clientY, buttons: e.buttons, pointerId: e.pointerId });
  };
  const up = (e: ReactPointerEvent) => {
    if (press.current.taken) moves.set({ clientX: e.clientX, clientY: e.clientY, buttons: e.buttons, pointerId: e.pointerId });
    moves.flush();
    if (swap) return;
    const p = press.current;
    if (!p.taken) return;
    p.taken = false;
    p.slid = true;
    setTimeout(() => { p.slid = false; });
    const at = local(e);
    setFinger(null);
    if (p.panel) {
      p.panel = false;
      // Let go on a place in the rows, the panel open: that bar, that place.
      if (opened.current && at.y < rowTop - 4 && sp.o.value >= 0.85) {
        const n = Math.max(0, Math.min(others.length - 1, Math.floor((at.y - OVER) / ROW))), i = others[n]!;
        const xs = centres(w, 0, sets[i]!.length);
        pickSet(i, sets[i]![nearest(xs, at.x)]!);
        return;
      }
      // Elsewhere: as the line left it, without the lean (on the bar, closed, and the place under the finger).
      panel(opened.current);
      if (!opened.current && at.y >= rowTop - 4) { const key = items[nearest(final, at.x)]!; if (key !== place) go(key); }
      return;
    }
    const key = items[nearest(final, at.x)]!;
    if (open) panel(false);
    if (key !== place) go(key);
  };
  // The finger taken from the bar without its lifting (the browser took the gesture): let go of, nothing chosen; the
  // panel as the line left it.
  function lost() {
    moves.cancel();
    const p = press.current;
    p.taken = false;
    setFinger(null);
    if (p.panel) { p.panel = false; panel(open); }
  }
  const tapPlace = (key: BarPlace) => {
    if (press.current.slid) return;
    if (open) panel(false);
    if (key !== place) go(key);
  };

  // ---- drawing
  const r = (DROP / 2 + GAP) * k;
  // 令 and its notch shrink about one middle, which comes up to the bar's edge: the notch closes to nothing, no dent left.
  const cy = -LIFT * k;
  const notch = r > 0.5 && w ? notchCut(w / 2, 0, cy, r, FILLET) : null;
  const notchAt = r > 0.5 && w ? notchCut(w / 2, clipTop, cy, r, FILLET) : null;
  // The glass as tall as what shows of it (a taller frosted layer clipped short was drawn unblurred), the notch cut
  // out by its outline (a mask left the blurred backdrop in the notch).
  const shape = w ? outline(w, 0, PANEL - clipTop, notch) : "";
  const slot = w ? (w - 2 * C0) / 3 : 0;
  const shadowMask = useId().replace(/[^\w-]/g, "");
  const ballShown = ai >= 0 || finger !== null || ballOn !== null;
  const ballStyle = () => {
    const v = sp.x.velocity / 60;
    const stretch = Math.min(36, Math.abs(v) * 1.6);
    const width = BALL + stretch, height = BALL - Math.min(6, stretch * 0.2);
    const left = sp.x.value - BALL / 2 - (v < 0 ? stretch : 0);
    return {
      width: `${width}px`, height: `${height}px`, borderRadius: `${height / 2}px`,
      opacity: ballShown ? "1" : "0",
      transform: `translate3d(${left}px, ${sp.y.value - height / 2}px, 0) scale(${(1 + 0.06 * sp.held.value) * (ballShown ? 1 : 0.6)})`,
    };
  };
  drawBall.current = () => { if (ball.current) Object.assign(ball.current.style, ballStyle()); };
  const lit = cand ? (cand.set === cur ? cand.key : null) : place;
  drawShape.current = () => {
    const o = sp.o.value, k = sp.k.value * (1 - Math.min(1, o * 2));
    const top = Math.max(0, OVER + travel * (1 - o)), cy = -LIFT * k, radius = (DROP / 2 + GAP) * k;
    const cut = radius > 0.5 && w ? notchCut(w / 2, 0, cy, radius, FILLET) : null;
    const edge = radius > 0.5 && w ? notchCut(w / 2, top, cy, radius, FILLET) : null;
    if (glass.current) { glass.current.style.top = `${top}px`; glass.current.style.clipPath = w ? `path("${outline(w, 0, PANEL - top, cut)}")` : ""; }
    gradient.current?.setAttribute("y1", String(top)); gradient.current?.setAttribute("y2", String(top + R));
    for (const el of [shadowInside.current, shadowShape.current]) if (el) { el.setAttribute("y", String(top)); el.setAttribute("height", String(PANEL - top)); }
    rim.current?.setAttribute("d", edge?.edge ?? "");
    if (rowPanel.current) Object.assign(rowPanel.current.style, { opacity: String(swap ? 0 : rowsLook(o).alpha), transform: `translate3d(0, ${rowsLook(o).dy}px, 0)`, pointerEvents: open && o > 0.6 ? "auto" : "none" });
    const xs = centres(w, k, items.length);
    items.forEach((key, j) => { const el = tabEls.current.get(key); if (el) el.style.left = `${xs[j]! - slot / 2}px`; });
    if (actionButton.current) Object.assign(actionButton.current.style, { transform: `translate(-50%, ${cy - DROP / 2}px) scale(${Math.max(0.001, k)})`, opacity: String(Math.min(1, k * 3)), pointerEvents: k > 0.9 && action ? "auto" : "none" });
  };
  useLayoutEffect(() => { drawShape.current(); drawBall.current(); });


  return (
    <>
      {open && <div className={css.mBarScrim} data-bar="scrim" onPointerDown={() => panel(false)} />}
      <div className={css.mBarHost} data-bar="host" data-open={open || undefined} data-away={shown ? undefined : ""} inert={!shown}>
        <div ref={wrap} className={css.mBarWrap}
          style={{ height: PANEL, pointerEvents: open ? "auto" : "none" }}
          onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={lost}
          onLostPointerCapture={() => { if (press.current.taken) lost(); }} onContextMenu={(e) => e.preventDefault()}>
          {w > 0 && (
            <svg className={css.mBarShadow} width={w} height={PANEL} aria-hidden="true">
              <defs>
                <linearGradient ref={gradient} id={`${shadowMask}f`} gradientUnits="userSpaceOnUse" x1={0} y1={clipTop} x2={0} y2={clipTop + R}>
                  <stop offset={0} stopColor="#000" />
                  <stop offset={1} stopColor="#fff" />
                </linearGradient>
                <mask id={shadowMask} maskUnits="userSpaceOnUse" x={-40} y={-40} width={w + 80} height={PANEL + 80}>
                  <rect x={-40} y={-40} width={w + 80} height={PANEL + 80} fill={`url(#${shadowMask}f)`} />
                  <rect ref={shadowInside} x={0} y={clipTop} width={w} height={PANEL - clipTop} rx={R} fill="#000" />
                </mask>
              </defs>
              <g mask={`url(#${shadowMask})`}><rect ref={shadowShape} className={css.mBarShadowShape} x={0} y={clipTop} width={w} height={PANEL - clipTop} rx={R} /></g>
            </svg>
          )}
          {/* Rounded as its outline is, so its lit rim (an inset shadow) runs round the ends too; the outline cuts the notch. */}
          <div ref={glass} className={css.mBarGlass} data-bar="glass" style={{ top: clipTop, borderRadius: R, clipPath: shape ? `path("${shape}")` : undefined }} />
          {w > 0 && others.length > 0 && (
            <div ref={rowPanel} className={css.mBarRows} data-bar="rows" style={{ top: 0, height: rowTop, opacity: swap ? 0 : rowsLook(o).alpha, transform: `translateY(${rowsLook(o).dy}px)`, pointerEvents: open && o > 0.6 ? "auto" : "none" }}>
              {others.map((i, n) => {
                const xs = centres(w, 0, sets[i]!.length);
                return (
                  <div key={i} className={css.mBarSetRow} style={{ top: OVER + n * ROW }} onClick={() => { if (!press.current.slid) pickSet(i, null); }}>
                    {sets[i]!.map((key, j) => (
                      <button key={key} type="button" className={css.mBarPlace} data-place={key} data-set={i} style={{ left: xs[j]! - slot / 2, width: slot }}
                        data-on={(cand ? cand.set === i && cand.key === key : place === key) || undefined} aria-label={railLabel(key)}
                        onClick={(e) => { e.stopPropagation(); if (!press.current.slid) pickSet(i, key); }}>
                        {icon(key)}
                        {dots[key] && <span className={css.mBarDot} data-tone={dots[key]} />}
                      </button>
                    ))}
                  </div>
                );
              })}
            </div>
          )}
          <div className={css.mBarRow} role="tablist" style={{ top: rowTop, pointerEvents: "auto" }}>
            {w > 0 && !swap && items.map((key, j) => (
              <button ref={el => { if (el) tabEls.current.set(key, el); else tabEls.current.delete(key); }} key={key} type="button" role="tab" data-tab={key} aria-selected={place === key} className={css.mBarPlace} style={{ left: now[j]! - slot / 2, width: slot }}
                data-on={lit === key || undefined} aria-label={labelOf(key)} onClick={() => tapPlace(key)}>
                {icon(key)}
                {dots[key] && <span className={css.mBarDot} data-tone={dots[key]} />}
              </button>
            ))}
          </div>
          {w > 0 && <svg className={css.mBarNotchRim} width={w} height={PANEL} aria-hidden="true"><path ref={rim} d={notchAt?.edge ?? ""} /></svg>}
          <button ref={actionButton} type="button" className={css.mBarLing} aria-label={drawn.current?.label ?? t("web-mobile.home.newChat")} data-action={drawn.current?.key}
            style={{ top: rowTop, transform: `translate(-50%, ${cy - DROP / 2}px) scale(${Math.max(0.001, k)})`, opacity: Math.min(1, k * 3), pointerEvents: k > 0.9 && action ? "auto" : "none" }}
            onPointerDown={(e) => e.stopPropagation()} onClick={() => action?.run()}>
            {/* Another icon (令, a ＋) for another page's action pops in, the circle staying; another ＋ is the same icon, still. */}
            <span key={drawn.current && drawn.current.key !== "ling" ? "plus" : "ling"} className={css.mBarAction}>{drawn.current && drawn.current.key !== "ling" ? <Plus size={30} /> : <Ling size={40} />}</span>
          </button>
          {swapAt && (
            <div className={css.mBarStack} data-bar="stack" style={{ top: clipTop, height: PANEL - clipTop, clipPath: `path("${shape}")` }}>
              {others.flatMap((i, n) => i === swap!.i ? [] : sets[i]!.map((key, j) => (
                <span key={`r${i}${key}`} className={css.mBarStackIcon} style={{ left: centres(w, 0, sets[i]!.length)[j]! - 24, top: rowMid(n) + swapAt.shift + swapAt.dy - 24 - clipTop, opacity: swapAt.alpha }}>{icon(key)}</span>
              )))}
              {swapAt.into.map((key, j) => (
                <span key={`in${key}`} className={css.mBarStackIcon} data-on={swap!.key === key || undefined} style={{ left: swapAt.xs[j]! - 24, top: swapAt.y - 24 - clipTop, opacity: swapAt.alpha }}>{icon(key)}</span>
              ))}
              {items.map((key, j) => (
                <span key={`out${key}`} className={css.mBarStackIcon} style={{ left: now[j]! - 24, top: barMid + swapAt.shift - 24 - clipTop }}>{icon(key)}</span>
              ))}
            </div>
          )}
          {w > 0 && (
            <div ref={ball} className={css.mBarBall} data-bar="ball" style={ballStyle()} />
          )}
        </div>
      </div>
    </>
  );
}

/** The bottom bars of the workspace in view (its own; the ones all had before it had its own). */
export function useBars(): { sets: string[][]; current: number } {
  return usePrefs((p) => (p.workspace ? p.barsBy[p.workspace] : undefined) ?? p.bars);
}

/** Says a bar's new places (or a new bar, or one fewer) to the core, whole: the workspace in view's. */
export function setBars(sets: BarPlace[][], current: number): void {
  const whole = { sets, current: Math.max(0, Math.min(current, sets.length - 1)) };
  const ws = prefs().workspace;
  setPrefs(ws ? { barsBy: { [ws]: whole } } : { bars: whole });
}
