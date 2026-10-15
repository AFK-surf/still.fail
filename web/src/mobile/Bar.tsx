// The phone's bottom bar (the Android app's ui/Bar.kt draws the same): the places of the bar in view, one of the
// device's bars (prefs `bars`, kept whole by the core), floating over the foot of a place's top page.
//
// - A frosted glass, its rim lit; a frosted ball of 68 over the place in view (under its icon, over 令), 6 past the
//   bar on every side. On a chat page (对话, 奏, 已归档) 令 sits in a notch cut into the bar's top, as far from it all
//   round, the notch's shoulders rounded into the edge; elsewhere 令 sinks into the bar and the notch closes.
// - A tap on a place goes there; the ball travels on a spring as quick as the way is long (time ∝ √distance).
// - One stroke: a finger set on the bar and moved any way takes the ball, which keeps to the place a let-go would
//   choose, leaning a quarter of the way toward the finger. With more than one bar, leaving the bar upward opens the
//   panel: the glass grows up into a rectangle, a row per other bar above the bar, and the ball goes on into those
//   rows. Let go on a place: it (in another bar: that bar too). Let go while the panel is still opening: it opens.
// - Choosing another bar, the panel closes like a window over a stack of bars: the stack slides down until the chosen
//   bar is where the bar is, what is not chosen goes out at the glass's edges. Nothing fades.
import { useEffect, useId, useLayoutEffect, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import type { ComponentType } from "react";
import { Archive, Chart, Chats, Folder, Im, Ling, Quota, Zou, type IconProps } from "../icons.tsx";
import { railLabel } from "../Rail.tsx";
import { setPrefs, usePrefs } from "../prefs.ts";
import { useChats, useStatus } from "../api.ts";
import { useWorkspaceMarks } from "../lastChat.ts";
import { StationGlyph, glyphCounts } from "../StationGlyph.tsx";
import { reducedMotion } from "../motion.ts";
import * as css from "./Bar.css.ts";
import { t } from "../i18n.ts";

/** The places a bar can hold (the core's BAR_PLACES), and the chats' family: 令 and its notch are on their pages. */
export type BarPlace = "chats" | "decisions" | "files" | "stations" | "profiles" | "connects" | "usage" | "archive";
export const BAR_PLACES: BarPlace[] = ["chats", "decisions", "files", "stations", "profiles", "connects", "usage", "archive"];
const CHAT_FAMILY: BarPlace[] = ["chats", "decisions", "archive"];

/** Each place's page, under the workspace (`/w/<id>`): the address a place's top page is at. */
export const PLACE_PATHS: Record<BarPlace, string> = {
  chats: "", decisions: "/decisions", files: "/files", stations: "/settings/stations", profiles: "/settings/profiles",
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

const ICONS: Partial<Record<BarPlace, ComponentType<IconProps>>> = { chats: Chats, decisions: Zou, files: Folder, profiles: Quota, connects: Im, usage: Chart, archive: Archive };

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
    this.velocity += (-this.tension * (this.value - this.target) - this.damping * this.velocity) * dt;
    this.value += this.velocity * dt;
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
  newChat: () => void;
  /** Told when the panel opens and closes (the shell keeps a page's swipe back out of it). */
  onPanel?: (open: boolean) => void;
}

export function BottomBar({ scope, place, shown, go, newChat, onPanel }: BottomBarProps) {
  const bars = usePrefs((p) => p.bars);
  const sets = bars.sets as BarPlace[][];
  const cur = Math.min(bars.current, sets.length - 1);
  const items = sets[cur] ?? [];
  const others = useMemo(() => sets.map((_, i) => i).filter((i) => i !== cur), [sets, cur]);

  // What waits: 奏's dot, the stations' trouble (the core's, as Home shows them).
  const marks = useWorkspaceMarks(scope);
  const chats = useChats(scope, false).value;
  const status = useStatus(scope);
  const dots: Partial<Record<BarPlace, "accent" | "red">> = {};
  if ((marks?.workspaces[scope]?.decisions ?? 0) > 0) dots.decisions = "accent";
  if (chats?.trouble) dots.stations = "red";
  const glyph = glyphCounts({ glyph: chats?.glyph }, status?.state === "trouble");
  const icon = (key: BarPlace, size = 28) => {
    if (key === "stations") return <StationGlyph counts={glyph} size={size} />;
    const I = ICONS[key]!;
    return <I size={size} />;
  };

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

  // ---- springs, stepped by one frame loop; the bar is drawn again each frame one of them moves
  const s = useRef<{ o: Spring; k: Spring; held: Spring; x: Spring; y: Spring } | null>(null);
  s.current ??= { o: new Spring(0), k: new Spring(0), held: new Spring(0), x: new Spring(0), y: new Spring(0) };
  const sp = s.current;
  const [, tick] = useState(0);
  const loop = useRef({ raf: 0, last: 0 });
  // What the panel's spring is to do once it is still (a bar being chosen: chosen). Done at once if cut short: left
  // undone, the bar would stay half switched.
  const panelDone = useRef<(() => void) | null>(null);
  const run = () => {
    if (loop.current.raf) return;
    loop.current.last = performance.now();
    const frame = (now: number) => {
      const dt = Math.min(0.032, Math.max(0.001, (now - loop.current.last) / 1000));
      loop.current.last = now;
      const all = Object.values(sp);
      const instant = reducedMotion();
      for (const spring of all) if (instant) spring.jump(spring.target); else if (spring.moving) spring.step(dt);
      if (!sp.o.moving && panelDone.current) { const done = panelDone.current; panelDone.current = null; done(); }
      tick((n) => n + 1);
      loop.current.raf = all.some((spring) => spring.moving) ? requestAnimationFrame(frame) : 0;
    };
    loop.current.raf = requestAnimationFrame(frame);
  };
  useEffect(() => () => cancelAnimationFrame(loop.current.raf), []);

  // ---- the panel (only with more than one bar)
  const [open, setOpenState] = useState(false);
  const panel = (next: boolean, then?: () => void, config?: [number, number]) => {
    const before = panelDone.current;
    panelDone.current = then ?? null;
    before?.();
    setOpenState(next);
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

  // ---- the notch: open on a chat page with the panel closed
  const inChats = place !== null && CHAT_FAMILY.includes(place) && !open;
  sp.k.to(inChats ? 1 : 0, 300, 30);
  if (!w) sp.k.jump(inChats ? 1 : 0); // as it is when first drawn, not opened as the page comes
  const k = sp.k.value;

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
  const pickSet = (i: number, key: BarPlace | null) => {
    if (swap) return;
    setSwap({ i, n: others.indexOf(i), from: Math.max(0.2, sp.o.value), key });
    panel(false, () => {
      setSwap((was) => was && { ...was, done: true });
      setPrefs({ bars: { sets: bars.sets, current: i } });
      if (key && key !== place) go(key);
    }, [200, 28]);
  };
  // Landed and drawn as the chosen bar: the ball put where it is (it was carried there), the stack gone.
  useLayoutEffect(() => {
    if (swap?.done && cur === swap.i && (!swap.key || place === swap.key)) {
      setSwap(null);
      if (ai >= 0) { sp.x.jump(final[ai]!); sp.y.jump(barMid); }
    }
  });
  const swapAt = swap && w ? (() => {
    const t = Math.max(0, Math.min(1, 1 - o / swap.from));
    const shift = (barMid - rowMid(swap.n)) * t;
    const into = sets[swap.i]!;
    const landsOnChats = swap.key ? CHAT_FAMILY.includes(swap.key) : inChats;
    const from = centres(w, 0, into.length), to = centres(w, landsOnChats ? 1 : 0, into.length);
    return { shift, into, xs: into.map((_, j) => from[j]! + (to[j]! - from[j]!) * t), y: rowMid(swap.n) + shift };
  })() : null;
  const ballOn = swapAt && swap!.key ? { x: swapAt.xs[swapAt.into.indexOf(swap!.key)]!, y: swapAt.y } : null;

  // ---- the finger
  const press = useRef({ x: 0, y: 0, taken: false, opening: false, slid: false });
  const local = (e: ReactPointerEvent) => { const b = wrap.current!.getBoundingClientRect(); return { x: e.clientX - b.left, y: e.clientY - b.top }; };
  const finishSwap = () => {
    // A finger down while a bar is being chosen: it is chosen now, then the finger is the finger's.
    if (!panelDone.current) return;
    sp.o.jump(0);
    const done = panelDone.current;
    panelDone.current = null;
    done();
  };
  const down = (e: ReactPointerEvent) => {
    finishSwap();
    press.current = { x: e.clientX, y: e.clientY, taken: false, opening: false, slid: false };
  };
  const move = (e: ReactPointerEvent) => {
    const p = press.current;
    if (!p.taken && e.buttons !== 0 && Math.hypot(e.clientX - p.x, e.clientY - p.y) > 8) {
      p.taken = true;
      wrap.current!.setPointerCapture(e.pointerId);
    }
    if (!p.taken) return;
    const at = local(e), several = others.length > 0;
    if (several && !open && !p.opening && at.y < rowTop - 8) { p.opening = true; panel(true); }
    setFinger({ x: at.x, y: several && (open || p.opening) ? Math.max(rowMid(0), Math.min(barMid, at.y)) : null });
  };
  const up = (e: ReactPointerEvent) => {
    const p = press.current;
    if (!p.taken) return;
    p.taken = false;
    p.slid = true;
    setTimeout(() => { p.slid = false; });
    const at = local(e), isOpen = open || p.opening;
    p.opening = false;
    setFinger(null);
    if (isOpen && at.y < rowTop - 4) {
      // Over the rows before they are where they go: nothing chosen, the panel opens and stays.
      if (sp.o.value < 0.85) return;
      const n = Math.max(0, Math.min(others.length - 1, Math.floor((at.y - OVER) / ROW))), i = others[n]!;
      const xs = centres(w, 0, sets[i]!.length);
      pickSet(i, sets[i]![nearest(xs, at.x)]!);
      return;
    }
    const key = items[nearest(final, at.x)]!;
    if (isOpen) panel(false);
    if (key !== place) go(key);
  };
  // The finger taken from the bar without its lifting (the browser took the gesture): let go of, nothing chosen.
  function lost() {
    press.current.taken = false;
    press.current.opening = false;
    setFinger(null);
  }
  const tapPlace = (key: BarPlace) => {
    if (press.current.slid) return;
    if (open) panel(false);
    if (key !== place) go(key);
  };

  // ---- drawing
  const r = (DROP / 2 + GAP) * k;
  const cy = -LIFT + (1 - k) * 10;
  const notch = r > 0.5 && w ? notchCut(w / 2, 0, cy, r, FILLET) : null;
  const notchAt = r > 0.5 && w ? notchCut(w / 2, clipTop, cy, r, FILLET) : null;
  // The glass as tall as what shows of it (a taller frosted layer clipped short was drawn unblurred), the notch cut
  // out by its outline (a mask left the blurred backdrop in the notch).
  const shape = w ? outline(w, 0, PANEL - clipTop, notch) : "";
  const slot = w ? (w - 2 * C0) / 3 : 0;
  const shadowMask = useId().replace(/[^\w-]/g, "");
  const held = sp.held.value;
  const ballShown = ai >= 0 || finger !== null || ballOn !== null;
  const bx = ballOn?.x ?? sp.x.value, by = ballOn?.y ?? sp.y.value;
  // Stretched along its way by its speed (px a frame), its leading edge ahead; round as it stops.
  const v = ballOn ? 0 : sp.x.velocity / 60;
  const stretch = Math.min(36, Math.abs(v) * 1.6);
  const ballW = BALL + stretch, ballH = BALL - Math.min(6, stretch * 0.2);
  const ballLeft = bx - BALL / 2 - (v < 0 ? stretch : 0);
  const lit = cand ? (cand.set === cur ? cand.key : null) : place;

  return (
    <>
      {open && <div className={css.mBarScrim} data-bar="scrim" onPointerDown={() => panel(false)} />}
      <div className={css.mBarHost} data-bar="host" data-open={open || undefined} data-away={shown ? undefined : ""} inert={!shown}>
        <div ref={wrap} className={css.mBarWrap}
          style={{ height: PANEL, transform: `scaleX(${1 - Math.min(0.05, Math.abs(sp.o.velocity) * 0.008)})`, pointerEvents: open ? "auto" : "none" }}
          onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={lost}
          onLostPointerCapture={() => { if (press.current.taken) lost(); }} onContextMenu={(e) => e.preventDefault()}>
          {w > 0 && (
            <svg className={css.mBarShadow} width={w} height={PANEL} aria-hidden="true">
              <defs>
                <mask id={shadowMask} maskUnits="userSpaceOnUse" x={-40} y={-40} width={w + 80} height={PANEL + 80}>
                  <rect x={-40} y={-40} width={w + 80} height={PANEL + 80} fill="#fff" />
                  <rect x={-40} y={-40} width={w + 80} height={clipTop + R + 40} fill="#000" />
                  <rect x={0} y={clipTop} width={w} height={PANEL - clipTop} rx={R} fill="#000" />
                </mask>
              </defs>
              <g mask={`url(#${shadowMask})`}><rect className={css.mBarShadowShape} x={0} y={clipTop} width={w} height={PANEL - clipTop} rx={R} /></g>
            </svg>
          )}
          <div className={css.mBarGlass} data-bar="glass" style={{ top: clipTop, clipPath: shape ? `path("${shape}")` : undefined }} />
          {w > 0 && others.length > 0 && (
            <div className={css.mBarRows} data-bar="rows" style={{ top: 0, height: rowTop, opacity: swap ? 0 : Math.max(0, Math.min(1, (o - 0.35) / 0.65)), transform: `translateY(${(1 - Math.min(1, o)) * 14 - Math.max(0, o - 1) * travel}px)`, pointerEvents: open && o > 0.6 ? "auto" : "none" }}>
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
              <button key={key} type="button" role="tab" data-tab={key} aria-selected={place === key} className={css.mBarPlace} style={{ left: now[j]! - slot / 2, width: slot }}
                data-on={lit === key || undefined} aria-label={railLabel(key)} onClick={() => tapPlace(key)}>
                {icon(key)}
                {dots[key] && <span className={css.mBarDot} data-tone={dots[key]} />}
              </button>
            ))}
          </div>
          {notchAt && <svg className={css.mBarNotchRim} width={w} height={PANEL} aria-hidden="true"><path d={notchAt.edge} /></svg>}
          <button type="button" className={css.mBarLing} aria-label={t("web-mobile.home.newChat")}
            style={{ top: rowTop, transform: `translate(-50%, ${cy - DROP / 2}px) scale(${Math.max(0.001, k)})`, opacity: Math.min(1, k * 3), pointerEvents: k > 0.9 ? "auto" : "none" }}
            onPointerDown={(e) => e.stopPropagation()} onClick={newChat}><Ling size={40} /></button>
          {swapAt && (
            <div className={css.mBarStack} data-bar="stack" style={{ top: clipTop, height: PANEL - clipTop, clipPath: `path("${shape}")` }}>
              {others.flatMap((i, n) => i === swap!.i ? [] : sets[i]!.map((key, j) => (
                <span key={`r${i}${key}`} className={css.mBarStackIcon} style={{ left: centres(w, 0, sets[i]!.length)[j]! - 24, top: rowMid(n) + swapAt.shift - 24 - clipTop }}>{icon(key)}</span>
              )))}
              {swapAt.into.map((key, j) => (
                <span key={`in${key}`} className={css.mBarStackIcon} data-on={swap!.key === key || undefined} style={{ left: swapAt.xs[j]! - 24, top: swapAt.y - 24 - clipTop }}>{icon(key)}</span>
              ))}
              {items.map((key, j) => (
                <span key={`out${key}`} className={css.mBarStackIcon} style={{ left: now[j]! - 24, top: barMid + swapAt.shift - 24 - clipTop }}>{icon(key)}</span>
              ))}
            </div>
          )}
          {w > 0 && (
            <div className={css.mBarBall} data-bar="ball" style={{
              left: ballOn ? ballOn.x - BALL / 2 : ballLeft, top: by - (ballOn ? BALL : ballH) / 2, width: ballOn ? BALL : ballW, height: ballOn ? BALL : ballH,
              borderRadius: (ballOn ? BALL : ballH) / 2, opacity: ballShown ? 1 : 0, transform: `scale(${(1 + 0.06 * held) * (ballShown ? 1 : 0.6)})`,
            }} />
          )}
        </div>
      </div>
    </>
  );
}

/** Says a bar's new places (or a new bar, or one fewer) to the core, whole. */
export function setBars(sets: BarPlace[][], current: number): void {
  setPrefs({ bars: { sets, current: Math.max(0, Math.min(current, sets.length - 1)) } });
}
