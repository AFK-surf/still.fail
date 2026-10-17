// The phone's bottom bar (下方栏), as the prototype agreed with the user has it (session c-1c78bb4403's
// proto/vbar/vbar.jsx `Bar`, frosted only; the Android app's ui/Bar.kt): a floating capsule of the places of one bar; a
// frosted ball over the place shown, which travels on a spring stretched by its speed and goes where a finger takes it;
// the page's primary action standing in a notch cut out of the bar's top (令, a new chat, on the chats' pages; a "+" on
// a page that adds something); with more than one bar, the glass grows upward into a panel of the other bars, one row
// each, snapping open once a finger on the bar is drawn high enough and closed once it comes back down (leaning toward
// the finger, as the ball does to a place), and a bar chosen there slides down into the bar's place. All of it moves on
// springs stepped a frame at a time by one loop (BarModel, on the UI thread: every motion and gesture here is a
// worklet), retargeted by the finger as it goes, nothing playing out on its own.
// Everything is glass over the pages (expo-blur, src/ui/Glass.tsx): the bar's glass, the action and the ball.
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { BackHandler, Pressable, StyleSheet, View, useWindowDimensions } from "react-native";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, {
  Easing,
  runOnJS,
  runOnUI,
  useAnimatedProps,
  useAnimatedReaction,
  useAnimatedStyle,
  useDerivedValue,
  useSharedValue,
  type SharedValue,
} from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Svg, { ClipPath, Defs, Mask, Path, Rect, type PathProps } from "react-native-svg";
import { Frost } from "./Glass";
import { Icon, Icons } from "./Icon";
import type { IconPaths } from "./IconSet";
import { raised as raisedOf, useC, withAlpha } from "./Theme";

// ── geometry (dp) ───────────────────────────────────────────────────────

/** The bar's height. */
export const BAR_TRACK = 56;
/** The ball at rest: this far from the bar's top, foot and ends alike. */
const INSET = 6;
const BALL_REST = BAR_TRACK - INSET * 2;
/** The ball: always a circle this big at rest, so 6 past the bar on every side. */
export const BALL = BAR_TRACK + 12;
/** A place's middle at the bar's ends: the ball at rest as far from the ends as from the top and foot. */
const C0 = INSET + BALL_REST / 2;
const DROP = 56;
const NOTCH_GAP = 6;
/** 令's middle above the bar's top. */
const LIFT = 4;
const FILLET = 8;
/** A row of the panel: as tall as the bar, rows stacked with no gap. */
const ROW = 56;
/** Room above the panel's rows for its overshoot as it opens. */
const OVER = 20;
const RAD = BAR_TRACK / 2;
/** One place over: the distance that keeps the ball's spring at tension 300. */
const SLOT_PX = 90;
const LEAN = 0.25;
const MAX_STRETCH = 36;
/** A finger moved this far is a slide, not a tap. */
const SLOP = 8;
/** Half a dp: the rim's lit edges and hairline (Bar.kt 0.5.dp). */
const HAIR = 0.5;

/** The places' middles on a bar `w` wide holding `n` (four values; past `n` repeated) with the notch `k` open. */
export function barCentres(w: number, k: number, n: number): number[] {
  "worklet";
  const closed = (w - 2 * C0) / 3;
  const open = w / 2 - (DROP / 2 + NOTCH_GAP) - 6 - BALL_REST / 2 - C0;
  const sp = closed + (open - closed) * k;
  if (n >= 4) return [C0, C0 + sp, w - C0 - sp, w - C0];
  if (n === 3) return [C0, C0 + (w / 2 - C0 - (w / 2 - C0 - sp) * k), w - C0, w - C0];
  if (n === 2) return [C0, w - C0, w - C0, w - C0];
  return [C0, C0, C0, C0];
}

/** The panel snaps open once a finger is this far over the bar's top, and closed once it is back under `CLOSES`. */
const OPENS = 24;
const CLOSES = 16;

/**
 * A page's primary action, which the notch holds on a place's top page: `key` tells one from another (the icon swaps
 * between two, the notch staying open), `label` is what a screen reader says, `run` what a tap does (the page's latest).
 */
export class BarAction {
  run: () => void;
  constructor(readonly key: string, readonly label: string, readonly icon: IconPaths, run: () => void) {
    this.run = run;
  }
}

// ── the curves the loop steps by (ui/Motion.ts's, as worklets) ──────────

/** Glides' curves by number, as a shared value holds them: 0 linear, 1 CSS's ease (Ease.Css), 2 Ease.Arrive. */
const LINEAR = 0;
const CSS = 1;
const ARRIVE = 2;
const cssEase = Easing.bezierFn(0.25, 0.1, 0.25, 1);
const arriveEase = Easing.bezierFn(0.2, 0.8, 0.2, 1);
function curve(easing: number, t: number): number {
  "worklet";
  if (easing === CSS) return cssEase(t);
  if (easing === ARRIVE) return arriveEase(t);
  return t;
}
const clamp = (v: number, lo: number, hi: number) => {
  "worklet";
  return Math.min(hi, Math.max(lo, v));
};

// ── the bar's layout ────────────────────────────────────────────────────

/** The bar's layout for what it holds, `w` wide (dp); `notched`: the page shown has an action in the notch. */
interface Geo {
  w: number; sets: string[][]; cur: number; active: string | null; notched: boolean;
  items: string[];
  /** The other bars, in the panel, top to bottom. */
  others: number[];
  multi: boolean;
  panel: number;
  /** The bar's top in the panel's frame. */
  rowTop: number;
  /** How far the glass's top moves from the bar to the open panel. */
  reach: number;
  barMid: number;
  topY: number;
  slot: number;
}

function geoOf(w: number, sets: string[][], cur: number, active: string | null, notched: boolean): Geo {
  "worklet";
  const items = sets[cur] ?? [];
  const others: number[] = [];
  for (let i = 0; i < sets.length; i++) if (i !== cur) others.push(i);
  const rows = Math.max(1, others.length);
  const panel = BAR_TRACK + rows * ROW + OVER;
  const rowTop = panel - BAR_TRACK;
  return {
    w, sets, cur, active, notched, items, others, multi: sets.length > 1, panel, rowTop, reach: rowTop - OVER,
    barMid: rowTop + BAR_TRACK / 2, topY: OVER + ROW / 2, slot: (w - 2 * C0) / 3,
  };
}
const rowMid = (n: number) => {
  "worklet";
  return OVER + n * ROW + ROW / 2;
};
const centres = (g: Geo, k: number, n: number) => {
  "worklet";
  return barCentres(g.w, k, n);
};
/** Where the bar's places will be, notch open on a page with an action, the panel closed. */
const finalOf = (g: Geo, mode: boolean) => {
  "worklet";
  return centres(g, g.notched && !mode ? 1 : 0, g.items.length);
};
function nearest(cs: number[], n: number, x: number): number {
  "worklet";
  let best = 0;
  for (let j = 0; j < n; j++) if (Math.abs(cs[j]! - x) < Math.abs(cs[best]! - x)) best = j;
  return best;
}
/** The row of the panel at `y` (an index into `others`), as the rows lie with the panel open. */
const rowAt = (g: Geo, y: number) => {
  "worklet";
  return clamp(Math.floor((y - OVER) / ROW), 0, Math.max(0, g.others.length - 1));
};

// ── what moves: springs, glides, the ball ──────────────────────────────

/**
 * One number on a spring (react-spring's tension and friction, mass 1), stepped a frame at a time by the bar's loop
 * (BarModel's run), as the web's Spring: no motion of its own that plays out, only what each frame makes of it. `rest`:
 * how near its target (and how slow, ten times that a second) it is still.
 */
interface BarSpring { value: number; velocity: number; target: number; tension: number; friction: number; rest: number }
function barSpring(start: number, tension: number, friction: number, rest = 0.001): BarSpring {
  "worklet";
  return { value: start, velocity: 0, target: start, tension, friction, rest };
}
const springMoving = (s: BarSpring) => {
  "worklet";
  return s.velocity !== 0 || s.value !== s.target;
};
function springTo(s: BarSpring, target: number, tension = s.tension, friction = s.friction) {
  "worklet";
  s.target = target;
  s.tension = tension;
  s.friction = friction;
}
function springStep(s: BarSpring, dt: number) {
  "worklet";
  let x = s.value;
  let v = s.velocity;
  let left = dt;
  // In steps of 4 ms at most: steady however stiff.
  while (left > 0) {
    const h = Math.min(left, 0.004);
    left -= h;
    v += (-s.tension * (x - s.target) - s.friction * v) * h;
    x += v * h;
  }
  if (Math.abs(x - s.target) < s.rest && Math.abs(v) < s.rest * 10) { x = s.target; v = 0; }
  s.value = x;
  s.velocity = v;
}

/** One number gliding to where it is sent over a time on a curve (a CSS transition's way), stepped by the bar's loop. */
interface Glide { value: number; target: number; from: number; t: number; span: number; easing: number }
function glide(start: number): Glide {
  "worklet";
  return { value: start, target: start, from: start, t: 0, span: 0, easing: LINEAR };
}
const glideMoving = (g: Glide) => {
  "worklet";
  return g.value !== g.target;
};
/** Sent to `target` from where it is now, over `ms` (nothing new when that is where it is going already). */
function glideTo(g: Glide, target: number, ms: number, easing: number) {
  "worklet";
  if (target === g.target) return;
  g.from = g.value;
  g.target = target;
  g.t = 0;
  g.span = ms / 1000;
  g.easing = easing;
}
function glideJump(g: Glide, at: number) {
  "worklet";
  g.value = at;
  g.target = at;
}
function glideStep(g: Glide, dt: number) {
  "worklet";
  g.t += dt;
  const p = g.span <= 0 ? 1 : Math.min(1, g.t / g.span);
  g.value = p >= 1 ? g.target : g.from + (g.target - g.from) * curve(g.easing, p);
}

/**
 * Where the ball is (dp in the panel's frame) and how fast it goes, a spring each way toward where it is sent (`goX`,
 * `goY`), stepped a frame at a time (the bar's loop). Where it is sent may change every frame (a finger moving on the
 * bar): it goes on from where it is at the speed it has, toward the new goal. (An animation started over at each move
 * never got past its first frame under a real finger: the ball stayed where it was until the finger stopped.)
 */
interface BallMotion {
  x: number; y: number;
  /** Its speed (dp a second). */
  vx: number; vy: number;
  goX: number; goY: number;
  /** Across, as stiff as the way is short; down and up, 300. Damped as the web's (ZETA 0.635). */
  tension: number;
}
const ballResting = (b: BallMotion) => {
  "worklet";
  return Math.abs(b.goX - b.x) < 0.01 && Math.abs(b.goY - b.y) < 0.01 && Math.abs(b.vx) < 0.01 && Math.abs(b.vy) < 0.01;
};
function ballSnapTo(b: BallMotion, x0: number, y0: number) {
  "worklet";
  b.x = x0; b.y = y0; b.vx = 0; b.vy = 0;
}
function ballStep(b: BallMotion, dt: number) {
  "worklet";
  const cx = 2 * 0.635 * Math.sqrt(b.tension);
  const cy = 2 * 0.635 * Math.sqrt(300);
  let nx = b.x;
  let ny = b.y;
  let left = dt;
  // In steps of 4 ms at most: steady however stiff.
  while (left > 0) {
    const h = Math.min(left, 0.004);
    left -= h;
    b.vx += (-b.tension * (nx - b.goX) - cx * b.vx) * h;
    nx += b.vx * h;
    b.vy += (-300 * (ny - b.goY) - cy * b.vy) * h;
    ny += b.vy * h;
  }
  if (Math.abs(b.goX - nx) < 0.01 && Math.abs(b.vx) < 0.01) { nx = b.goX; b.vx = 0; }
  if (Math.abs(b.goY - ny) < 0.01 && Math.abs(b.vy) < 0.01) { ny = b.goY; b.vy = 0; }
  b.x = nx;
  b.y = ny;
}

/** Where the ball is drawn (dp in the panel's frame): its box, stretched by its speed toward where it goes. */
interface BallBox { left: number; top: number; width: number; height: number }
function ballBox(b: BallMotion, goalX: number, held: number, shown: number): BallBox {
  "worklet";
  const scale = (1 + 0.06 * held) * shown;
  const x = b.x;
  const v = Math.abs(goalX - x) < 0.5 ? 0 : b.vx / 60;
  const stretch = Math.min(MAX_STRETCH, Math.abs(v) * 1.6);
  const w = BALL + stretch;
  const h = BALL - Math.min(6, stretch * 0.2);
  // Its leading edge reaches ahead, toward where it goes.
  const left = x - BALL / 2 - (v < 0 ? stretch : 0);
  const cx = left + w / 2;
  const cy = b.y;
  const sw = w * scale;
  const sh = h * scale;
  return { left: cx - sw / 2, top: cy - sh / 2, width: sw, height: sh };
}

// ── the model ──────────────────────────────────────────────────────────

/** The place a let-go would choose while a finger has the ball: its middle, and which bar and place it is. */
interface Cand { x: number; y: number; set: number; key: string }

/**
 * A bar chosen in the panel, sliding down into the bar's place: which, its row, how open the panel was, the place
 * tapped; `laid`: the bars as they were then, which the stack sliding down is laid out by to its end (the chosen bar is
 * the one in view from the moment it is chosen); the rows' fade and offset then (`alpha`, `drop`) and how lit each place
 * was (`lit`, by slot), which the stack starts from; `still`: chosen from a panel at rest (its first frame is as it was).
 */
interface Swap { i: number; n: number; from: number; key: string | null; laid: Geo; alpha: number; drop: number; lit: Record<string, number>; still: boolean }

/** A place drawn (by its slot, `bar:<place>` or `row:<place>`): how lit it is, and what it is to be lit by. */
interface Tint extends Glide { token: number; row: boolean; key: string; set: number }

/** What the bar is told as it is drawn (BottomBar's parameters, as the loop reads them). */
interface Told {
  w: number; sets: string[][]; cur: number; active: string | null; hasAction: boolean;
  /** Whether a place's page has an action (`notches`), for every place of the bars. */
  notches: Record<string, boolean>;
  shown: boolean;
}

type Said = { tab: string } | { switch: number; key: string | null };

/**
 * What the bar keeps between frames and what its gestures do (vbar.jsx's refs and handlers; the web's mobile/Bar.tsx the
 * same rules): every motion of the bar is a number here (the panel's openness, the notch's, the ball, the bar shown, the
 * notch's icon swapping, the places lit), stepped by one loop a frame at a time while any moves (`run`). The panel
 * snaps, as the ball does to a place: while a finger has it, it is open once the finger is high enough over the bar and
 * closed once it is back down (a little apart, so it does not flicker between), leaning a quarter of the way toward
 * where the finger draws it, on its springs, retargeted at every move from where it is; let go, it stays as the finger
 * left it. What is chosen (a place, a bar) is chosen at the gesture, not once a motion has ended.
 */
interface BarModel {
  /** The panel of the other bars open (or opening, or the finger's). */
  mode: boolean;
  /** How open the panel is: 0 the bar, 1 the panel (past 1 a little as it overshoots or a finger draws it on). */
  o: BarSpring;
  /** The notch as the place has it (open on a page with an action), a spring as the place changes. */
  k: BarSpring;
  /** The ball held by a finger (it grows a little). */
  held: BarSpring;
  /** The bar shown (on a place's top page) or gone down out of the way. */
  vis: Glide;
  ballAlpha: Glide;
  ballScale: Glide;
  /** The notch's icon swapping: one going (`iconWas`, the icons themselves are the component's), how far (0 to 1, 300 ms). */
  iconWas: boolean;
  iconSwap: Glide;
  tints: Record<string, Tint>;
  ball: BallMotion | null;
  /** Where the ball is sent, as drawn (its stretch reads it). */
  goalX: number;
  /** How far the way to a place is, for the ball's stiffness; and the place and slide it was measured for. */
  trip: number;
  tripActive: string | null | undefined;
  tripSliding: boolean;
  width: number;
  /** The finger's place while it has the ball (dp in the panel's frame); its height only once the panel is the finger's. */
  drag: number | null;
  dragY: number | null;
  swap: Swap | null;
  /** The bar chosen that landed last: the stack is drawn where it landed until it is gone from the screen too. */
  swapLast: Swap | null;
  /** Which choice `swap` is (0: none), for what is drawn of it. */
  swapId: number;
  swapSeq: number;
  geo: Geo | null;
  told: Told;
  // The finger: where it went down, whether it has the ball (moved past SLOP) and the panel (`holds`; from `o0`, the
  // panel as open as that when it went down, `fromOpen`: it had it from there, so no slop to take up), which way the
  // panel snaps (`open`). `waits`: it went down as a bar chosen was landing, and is the finger's only once it has.
  dragging: boolean; holds: boolean; fromOpen: boolean; open: boolean; waits: boolean;
  x0: number; y0: number; o0: number;
  /** The touch that is the gesture's, and whether its end was heard. */
  finger: number; ended: boolean;
  /** The loop: running, and the frame before. */
  running: boolean; last: number; frames?: number;
  out: Said[];
}

function makeModel(told: Told, notched: boolean, ballShown: boolean): BarModel {
  return {
    mode: false, o: barSpring(0, 260, 17), k: barSpring(notched ? 1 : 0, 300, 30), held: barSpring(0, 420, 16),
    vis: glide(told.shown ? 1 : 0), ballAlpha: glide(ballShown ? 1 : 0), ballScale: glide(ballShown ? 1 : 0.6),
    iconWas: false, iconSwap: glide(1), tints: {}, ball: null, goalX: 0, trip: SLOT_PX, tripActive: undefined, tripSliding: false,
    width: told.w, drag: null, dragY: null, swap: null, swapLast: null, swapId: 0, swapSeq: 0, geo: null, told,
    dragging: false, holds: false, fromOpen: false, open: false, waits: false, x0: 0, y0: 0, o0: 0, finger: -1, ended: true,
    running: false, last: -1, out: [],
  };
}

/** The notch's openness as drawn: as its place has it, closed as far as the panel is drawn up (fully by half open). */
function kNow(m: BarModel): number {
  "worklet";
  return m.k.value * (1 - clamp(2 * m.o.value, 0, 1));
}

function moving(m: BarModel): boolean {
  "worklet";
  if (springMoving(m.o) || springMoving(m.k) || springMoving(m.held) || glideMoving(m.vis) || glideMoving(m.ballAlpha) || glideMoving(m.ballScale) || glideMoving(m.iconSwap)) return true;
  if (m.iconWas || m.swap != null || (m.ball != null && !ballResting(m.ball))) return true;
  for (const id in m.tints) if (glideMoving(m.tints[id]!)) return true;
  return false;
}

/** What keeps the loop going (a log of a loop that does not end: a value gone NaN never reaches its target). */
function whyMoving(m: BarModel): string {
  "worklet";
  const sp = (n: string, x: BarSpring) => (springMoving(x) ? `${n}=${x.value}->${x.target} ` : "");
  const gl = (n: string, x: Glide) => (glideMoving(x) ? `${n}=${x.value}->${x.target} ` : "");
  let out = sp("o", m.o) + sp("k", m.k) + sp("held", m.held) + gl("vis", m.vis) + gl("ballAlpha", m.ballAlpha) + gl("ballScale", m.ballScale) + gl("iconSwap", m.iconSwap);
  if (m.iconWas) out += "iconWas ";
  if (m.swap != null) out += "swap ";
  if (m.ball != null && !ballResting(m.ball)) out += `ball=${JSON.stringify(m.ball)} `;
  for (const id in m.tints) out += gl(`tint:${id}`, m.tints[id]!);
  return out;
}

/** How far a bar chosen has come down: 0 as the panel was, 1 landed. */
function swapT(m: BarModel, s: Swap): number {
  "worklet";
  return clamp(1 - m.o.value / s.from, 0, 1);
}
/** The stack's rows' look as they come down: from the rows' fade and offset as the bar was chosen, to none. */
function rowAlpha(m: BarModel, s: Swap): number {
  "worklet";
  return s.alpha + (1 - s.alpha) * swapT(m, s);
}
function rowDrop(m: BarModel, s: Swap): number {
  "worklet";
  return s.drop * (1 - swapT(m, s));
}

/** The chosen bar's places' middles and their height (dp in the panel's frame) as it comes down. */
function swapAt(m: BarModel, s: Swap): { xs: number[]; y: number } | null {
  "worklet";
  const sg = s.laid;
  const into = sg.sets[s.i];
  if (into == null) return null;
  const t = swapT(m, s);
  const from = centres(sg, 0, into.length);
  if (t <= 0) return { xs: from, y: rowMid(s.n) };
  const to = centres(sg, kNow(m), into.length);
  // Landed: exactly where the bar's places are drawn.
  if (t >= 1) return { xs: to, y: sg.barMid };
  const xs: number[] = [];
  for (let j = 0; j < into.length; j++) xs.push(from[j]! + (to[j]! - from[j]!) * t);
  return { xs, y: rowMid(s.n) + (sg.barMid - rowMid(s.n)) * t };
}

/** Where the place tapped in a bar chosen is as it comes down (null: none tapped). */
function ride(m: BarModel, s: Swap): { x: number; y: number } | null {
  "worklet";
  const key = s.key;
  if (key == null) return null;
  const j = s.laid.sets[s.i]?.indexOf(key) ?? -1;
  if (j < 0) return null;
  const at = swapAt(m, s);
  if (at == null) return null;
  return { x: at.xs[j]!, y: at.y + rowDrop(m, s) };
}

function step(m: BarModel, dt: number) {
  "worklet";
  const s = m.swap;
  // The frame a bar is chosen from a panel at rest, the stack is drawn as the rows were: it slides from the next.
  if (s != null && s.still) s.still = false;
  else if (springMoving(m.o)) springStep(m.o, dt);
  if (springMoving(m.k)) springStep(m.k, dt);
  if (springMoving(m.held)) springStep(m.held, dt);
  for (const g of [m.vis, m.ballAlpha, m.ballScale, m.iconSwap]) if (glideMoving(g)) glideStep(g, dt);
  for (const id in m.tints) { const g = m.tints[id]!; if (glideMoving(g)) glideStep(g, dt); }
  // Riding a bar chosen: the ball goes on its spring after the place it rides, from wherever it was.
  const b = m.ball;
  if (b != null && s != null) {
    const r = ride(m, s);
    if (r != null) { b.goX = r.x; b.goY = r.y; b.tension = 300; }
  }
  if (b != null && !ballResting(b)) ballStep(b, dt);
  if (m.iconWas && !glideMoving(m.iconSwap)) m.iconWas = false;
  // A bar chosen: landed, the stack is where the bar is, drawn as the bar will be; it goes in this same frame.
  if (s != null && !springMoving(m.o) && m.o.value <= 0) { m.swapLast = s; m.swap = null; m.swapId = 0; }
}

function openPanel(m: BarModel, open: boolean) {
  "worklet";
  m.mode = open;
  // From where it is, at the speed it has.
  if (open) springTo(m.o, 1, 260, 17);
  else springTo(m.o, 0, 320, 26);
}

function down(m: BarModel, p: { x: number; y: number }) {
  "worklet";
  // A bar chosen landing: it lands on its own spring, untouched; the finger is the finger's once it has.
  m.waits = m.swap != null;
  m.dragging = false;
  m.holds = false;
  if (m.waits) return;
  m.x0 = p.x;
  m.y0 = p.y;
  // The panel open, opening or closing: the finger has it from here, not stopping it (it goes on as it was going
  // until the finger moves).
  const o0 = m.o.value;
  m.holds = m.geo?.multi === true && (o0 > 0.02 || (springMoving(m.o) && m.o.target > 0));
  m.fromOpen = m.holds;
  m.open = m.o.target > 0.5;
  if (m.holds) m.mode = true;
  m.o0 = o0;
}

/** One stroke: a finger set on the bar (or the open panel) and moved any way takes the ball; up, the panel. */
function move(m: BarModel, p: { x: number; y: number }): boolean {
  "worklet";
  const g = m.geo;
  if (g == null) return false;
  if (m.waits) {
    if (m.swap != null) return true;
    // Landed, the finger still down: a stroke of its own from here.
    down(m, p);
  }
  if (!m.dragging && Math.hypot(p.x - m.x0, p.y - m.y0) > SLOP) m.dragging = true;
  if (g.multi && (m.holds || m.dragging)) {
    // How open the finger draws it (1 to 1, from where it was).
    const raw = m.o0 + (m.y0 - p.y - (m.fromOpen ? 0 : SLOP)) / g.reach;
    if (!m.holds && raw > 0) { m.holds = true; m.mode = true; }
    if (m.holds) {
      // Open once the finger is 24 over the bar, closed once it is back under 16; a quarter of the way toward where
      // the finger draws it, as the ball leans toward the finger.
      const over = g.rowTop - p.y;
      if (!m.open && over > OPENS) m.open = true;
      else if (m.open && over < CLOSES) m.open = false;
      const snap = m.open ? 1 : 0;
      const goal = clamp(snap + LEAN * (raw - snap), 0, 1.1);
      if (m.open) springTo(m.o, goal, 260, 17);
      else springTo(m.o, goal, 320, 26);
    }
  }
  if (!m.dragging) return m.holds;
  m.drag = p.x;
  // The ball goes on into the rows of the other bars once the finger has the panel open (closed, it keeps to the bar).
  m.dragY = g.multi && m.holds && m.open ? clamp(p.y, g.topY, g.barMid) : null;
  return true;
}

/** How far the rows are from where they rest as the panel opens: a little low, then up with its overshoot. */
function rowsShift(m: BarModel, g: Geo): number {
  "worklet";
  const v = m.o.value;
  return (1 - Math.min(1, v)) * 14 - Math.max(0, v - 1) * g.reach;
}

/** How the rows show as the panel opens: they come in over 0.35 to 1. */
function rowsAlpha(m: BarModel): number {
  "worklet";
  return clamp((m.o.value - 0.35) / 0.65, 0, 1);
}

/**
 * Another bar chosen (and a place in it, when one was tapped): it is the bar, and the place opens, now; the panel
 * closes like a window over a stack of bars, the chosen one sliding down into the bar's place, as the panel's openness
 * goes to 0 from where it is. The stack starts as the rows and the bar were drawn (their fade, offset and how lit each
 * place was), and comes to the bar's look as it lands.
 */
function pick(m: BarModel, i: number, key: string | null) {
  "worklet";
  if (m.swap != null) return;
  const g = m.geo;
  if (g == null) return;
  const n = g.others.indexOf(i);
  if (n < 0) return;
  const lit: Record<string, number> = {};
  for (const id in m.tints) lit[id] = m.tints[id]!.value;
  m.swap = { i, n, from: Math.max(0.2, m.o.value), key, laid: geoOf(g.w, g.sets, g.cur, null, false), alpha: rowsAlpha(m), drop: rowsShift(m, g), lit, still: !springMoving(m.o) };
  m.swapSeq += 1;
  m.swapId = m.swapSeq;
  m.mode = false;
  springTo(m.o, 0, 200, 28);
  m.out.push({ switch: i, key });
}

/**
 * The panel let go: on a place in the rows or above them, the panel open (0.85), that bar and that place (the top row's,
 * above); elsewhere (on the bar, or the panel not yet open) it ends as the finger left it, open or closed, the lean gone
 * (let go on the bar, closed: the place under the finger too).
 */
function letGo(m: BarModel, g: Geo, p: { x: number; y: number }) {
  "worklet";
  // Over the rows, or above the panel (gone up too far: the top row's place the ball keeps to there, as on the web; it
  // was let go open with nothing chosen, and the bar could not be switched).
  const inRows = p.y < g.rowTop - 4 && g.others.length > 0;
  if (inRows && m.o.value >= 0.85) {
    const i = g.others[rowAt(g, p.y)]!;
    const set = g.sets[i]!;
    pick(m, i, set[nearest(centres(g, 0, set.length), set.length, p.x)]!);
    return;
  }
  const j = p.y >= g.rowTop - 4 && g.items.length > 0 ? Math.min(g.items.length - 1, nearest(finalOf(g, m.mode), 4, p.x)) : -1;
  openPanel(m, m.open);
  if (!m.open && j >= 0 && g.items[j] !== g.active) m.out.push({ tab: g.items[j]! });
}

/** The gesture gone without its end being heard: as if let go where it was, nothing chosen. */
function lost(m: BarModel) {
  "worklet";
  m.waits = false;
  m.dragY = null;
  if (m.dragging) { m.dragging = false; m.drag = null; }
  if (m.holds) { m.holds = false; openPanel(m, m.open); }
}

/** A tap (moved less than SLOP): a place on the bar; with the panel open, a row (that bar) or a place in it. */
function tap(m: BarModel, p: { x: number; y: number }): boolean {
  "worklet";
  const g = m.geo;
  if (g == null) return false;
  if (m.mode && p.y < g.rowTop) {
    if (m.o.value <= 0.6 || g.others.length === 0) return false;
    const n = Math.floor((p.y - OVER - rowsShift(m, g)) / ROW);
    if (n < 0 || n >= g.others.length) return false;
    const i = g.others[n]!;
    const set = g.sets[i]!;
    const cs = centres(g, 0, set.length);
    const j = nearest(cs, set.length, p.x);
    pick(m, i, Math.abs(cs[j]! - p.x) <= g.slot / 2 ? set[j]! : null);
    return true;
  }
  // The bar's places only on the bar (not on a panel going, above it).
  if (g.items.length === 0 || p.y < g.rowTop - 4) return false;
  const now = centres(g, kNow(m), g.items.length);
  const j = nearest(now, g.items.length, p.x);
  if (Math.abs(now[j]! - p.x) > g.slot / 2) return false;
  if (m.mode) openPanel(m, false);
  m.out.push({ tab: g.items[j]! });
  return true;
}

function up(m: BarModel, p: { x: number; y: number }) {
  "worklet";
  const g = m.geo;
  if (g == null) { lost(m); return; }
  // Lifted as a bar chosen was landing (or before the finger was its own): nothing.
  if (m.waits) { m.waits = false; return; }
  const had = m.holds;
  m.holds = false;
  if (!m.dragging) {
    // A tap; the panel's and nothing tapped there: it goes on as it was going.
    if (!tap(m, p) && had) m.mode = m.o.target > 0.5;
    return;
  }
  m.dragging = false;
  m.drag = null;
  m.dragY = null;
  if (had) {
    letGo(m, g, p);
    return;
  }
  if (g.items.length === 0) return;
  const j = Math.min(g.items.length - 1, nearest(finalOf(g, m.mode), 4, p.x));
  if (m.mode) openPanel(m, false);
  if (g.items[j] !== g.active) m.out.push({ tab: g.items[j]! });
}

/**
 * What the composition of the bar works out from what it is told and where the finger is (Bar.kt's BottomBar body and
 * its SideEffects): the layout, the place a let-go would choose, where the ball goes and how stiffly, and each place's
 * light. Done after everything that changes any of it (a gesture, what the bar is told, a frame of the loop).
 */
function settleGoals(m: BarModel) {
  "worklet";
  const p = m.told;
  // A bar being chosen with a place in it: the notch already as that place will have it (no action coming up only to go).
  const landsKey = m.swap?.key;
  const landsOn = landsKey != null ? (p.notches[landsKey] ?? false) : null;
  const g = geoOf(p.w, p.sets, p.cur, p.active, landsOn ?? p.hasAction);
  m.geo = g;
  // The notch: open on a page with an action (a spring as the place changes); the panel drawn up closes it as far as it
  // is drawn (kNow), not on its own.
  springTo(m.k, g.notched ? 1 : 0);
  glideTo(m.vis, p.shown ? 1 : 0, p.shown ? 380 : 300, ARRIVE);
  const final = finalOf(g, m.mode);
  const drag = m.drag;
  const dragY = m.dragY;
  // While held, the ball keeps to the place a let-go would choose, leaning a quarter of the way toward the finger.
  let cand: Cand | null = null;
  if (drag != null) {
    if (dragY != null && dragY < g.rowTop - 4 && g.others.length > 0) {
      const n = rowAt(g, dragY);
      const i = g.others[n]!;
      const set = g.sets[i]!;
      const cs = centres(g, 0, set.length);
      const j = nearest(cs, set.length, drag);
      cand = { x: cs[j]!, y: rowMid(n), set: i, key: set[j]! };
    } else if (g.items.length > 0) {
      const j = Math.min(g.items.length - 1, nearest(final, 4, drag));
      cand = { x: final[j]!, y: g.barMid, set: g.cur, key: g.items[j]! };
    }
  }
  const under = cand != null ? (cand.set === g.cur ? cand.key : "") : null;
  const ai = p.active == null ? -1 : g.items.indexOf(p.active);
  const goalX = cand != null && drag != null ? cand.x + (drag - cand.x) * LEAN : final[Math.max(0, ai)]!;
  const goalY = cand != null ? cand.y + ((dragY ?? g.barMid) - cand.y) * LEAN : g.barMid;
  if (m.ball == null) m.ball = { x: goalX, y: goalY, vx: 0, vy: 0, goX: goalX, goY: goalY, tension: 300 };
  const ball = m.ball;
  const sliding = drag != null;
  // Sent to a place, its spring is as stiff as the way is short (one place over: tension 300).
  if (p.active !== m.tripActive || sliding !== m.tripSliding) {
    m.tripActive = p.active;
    m.tripSliding = sliding;
    if (!sliding) m.trip = Math.max(8, Math.abs(goalX - ball.x));
  }
  const tension = sliding ? 300 : clamp((300 * SLOT_PX) / m.trip, 90, 700);
  const swap = m.swap;
  const ballShown = ai >= 0 || sliding || swap?.key != null;
  // Where the ball and its look go: one spring each way toward where it is sent (a goal moved meanwhile, by a finger
  // every frame, changes where it goes on the way), stepped by the bar's loop with the rest.
  // Riding a bar chosen, the bar's loop sends it (after the place it rides).
  if (swap?.key == null) {
    ball.goX = goalX;
    ball.goY = goalY;
    ball.tension = tension;
  }
  m.goalX = goalX;
  // A new width (turned): there at once, not sent across.
  if (m.width !== p.w) { m.width = p.w; ballSnapTo(ball, goalX, ball.y); }
  springTo(m.held, sliding ? 1 : 0);
  glideTo(m.ballAlpha, ballShown ? 1 : 0, 200, CSS);
  glideTo(m.ballScale, ballShown ? 1 : 0.6, 250, CSS);
  // Each place lit as it is the one: the bar's, the place under the finger (or none, the finger on another bar's) or
  // the one shown; a row's, the one a let-go would choose or the one shown.
  for (const id in m.tints) {
    const t = m.tints[id]!;
    const on = t.row ? (cand != null ? cand.set === t.set && cand.key === t.key : p.active === t.key) : (under ?? p.active) === t.key;
    glideTo(t, on ? 1 : 0, 300, CSS);
  }
}

// ── drawing: the outlines ──────────────────────────────────────────────

/** An SVG path being made, as Compose's Path is (moveTo, lineTo, arcTo with Android's angles, close). */
interface P { d: string; empty: boolean }
function moveTo(p: P, x: number, y: number) {
  "worklet";
  p.d += `M${x} ${y}`;
  p.empty = false;
}
function lineTo(p: P, x: number, y: number) {
  "worklet";
  p.d += p.empty ? `M${x} ${y}` : `L${x} ${y}`;
  p.empty = false;
}
/**
 * Android's Path.arcTo(oval, startAngle, sweepAngle, forceMoveTo = false): a line to where the arc starts, then the
 * arc (degrees, clockwise from the right as the screen's y goes down).
 */
function arcTo(p: P, l: number, t: number, r: number, b: number, start: number, sweep: number) {
  "worklet";
  const cx = (l + r) / 2;
  const cy = (t + b) / 2;
  const rx = (r - l) / 2;
  const ry = (b - t) / 2;
  const a0 = (start * Math.PI) / 180;
  lineTo(p, cx + rx * Math.cos(a0), cy + ry * Math.sin(a0));
  // An arc of a whole turn or more is drawn in two halves (one SVG arc cannot end where it starts).
  let left = sweep;
  let at = start;
  while (Math.abs(left) > 0.0001) {
    const part = Math.abs(left) > 180 ? Math.sign(left) * 180 : left;
    const a1 = ((at + part) * Math.PI) / 180;
    p.d += `A${rx} ${ry} 0 0 ${part > 0 ? 1 : 0} ${cx + rx * Math.cos(a1)} ${cy + ry * Math.sin(a1)}`;
    at += part;
    left -= part;
  }
}

/**
 * The cut a notch makes in a top edge at y 0: a circle of radius `r` about (cx, c0), met by the edge through two fillets
 * of radius `f` (each touching the edge and the circle). Adds it to `p` from the edge's left meeting to its right
 * (`alone`: starting there, not along the edge to it), or nothing when there is none (closed); answers whether it did.
 */
function notch(p: P, cx: number, c0: number, r: number, f: number, alone: boolean): boolean {
  "worklet";
  if (r <= 0.5) return false;
  const dy = f - c0;
  const reach = (r + f) * (r + f) - dy * dy;
  if (c0 + r <= 0.5 || reach <= 0) return false;
  const xf = Math.sqrt(reach);
  const l = cx - xf;
  const rr = cx + xf;
  const deg = 180 / Math.PI;
  if (alone) moveTo(p, l, 0);
  else lineTo(p, l, 0);
  // The left fillet, from its top round to where it meets the circle (clockwise).
  const a1 = Math.atan2(c0 - f, cx - l) * deg;
  arcTo(p, l - f, 0, l + f, 2 * f, -90, a1 + 90);
  // The circle, under, from the left meeting to the right (anticlockwise).
  const aL = Math.atan2(f - c0, l - cx) * deg;
  const aR = Math.atan2(f - c0, rr - cx) * deg;
  arcTo(p, cx - r, c0 - r, cx + r, c0 + r, aL, aR - aL);
  // The right fillet, from where it meets the circle up to its top (clockwise).
  const a2 = Math.atan2(c0 - f, cx - rr) * deg;
  let sweep = -90 - a2;
  while (sweep <= 0) sweep += 360;
  while (sweep > 360) sweep -= 360;
  arcTo(p, rr - f, 0, rr + f, 2 * f, a2, sweep);
  return true;
}

/** The rounded bar (or panel) `w`×`h` with the notch cut into its top edge: a circle of radius `r` about (cx, cy). */
function outline(w: number, h: number, cx: number, cy: number, r: number): string {
  "worklet";
  const p: P = { d: "", empty: true };
  const rad = Math.min(RAD, h / 2);
  moveTo(p, 0, rad);
  arcTo(p, 0, 0, 2 * rad, 2 * rad, 180, 90);
  notch(p, cx, cy, r, FILLET, false);
  lineTo(p, w - rad, 0);
  arcTo(p, w - 2 * rad, 0, w, 2 * rad, 270, 90);
  lineTo(p, w, h - rad);
  arcTo(p, w - 2 * rad, h - 2 * rad, w, h, 0, 90);
  lineTo(p, rad, h);
  arcTo(p, 0, h - 2 * rad, 2 * rad, h, 90, 90);
  p.d += "Z";
  return p.d;
}

/** A rounded rectangle `w`×`h` of corner `r` (the ball's stadium, the action's circle). */
function roundRect(w: number, h: number, r: number): string {
  "worklet";
  const q = Math.min(r, w / 2, h / 2);
  return `M${q} 0L${w - q} 0A${q} ${q} 0 0 1 ${w} ${q}L${w} ${h - q}A${q} ${q} 0 0 1 ${w - q} ${h}L${q} ${h}A${q} ${q} 0 0 1 0 ${h - q}L0 ${q}A${q} ${q} 0 0 1 ${q} 0Z`;
}

// What moves with the panel, read where it is drawn.
function clipTop(m: BarModel, g: Geo): number {
  "worklet";
  return Math.max(0, OVER + g.reach * (1 - m.o.value));
}
function notchR(m: BarModel): number {
  "worklet";
  return (DROP / 2 + NOTCH_GAP) * kNow(m);
}
/** The action and its notch shrink about one middle, which comes up to the bar's edge: the notch closes to nothing, no dent left. */
function notchY(m: BarModel): number {
  "worklet";
  return -LIFT * kNow(m);
}

const AnimatedPath = Animated.createAnimatedComponent(Path);

/** A path whose outline is `d`, as it changes frame by frame. */
function APath({ d, ...rest }: Omit<PathProps, "d"> & { d: SharedValue<string> }) {
  const props = useAnimatedProps(() => ({ d: d.value }));
  return <AnimatedPath {...(rest as PathProps)} animatedProps={props} />;
}

let rims = 0;

/**
 * Glass's lit rim, as inset shadows on the web: a hairline all round inside its edge (`edge`), light along its top and
 * left (`lit`) and less along its foot and right (`back`): the outline less itself moved half a dp down and right, and
 * up and left. Drawn over the glass, its outline `d`.
 */
function Rim({ d, edge, lit, back }: { d: SharedValue<string>; edge: number; lit: number; back: number }) {
  const [id] = useState(() => `rim${++rims}`);
  return (
    <Svg width="100%" height="100%" style={StyleSheet.absoluteFill} pointerEvents="none">
      <Defs>
        <ClipPath id={`${id}c`}><APath d={d} /></ClipPath>
        <Mask id={`${id}l`} maskUnits="userSpaceOnUse" x={-50} y={-50} width={5000} height={5000}>
          <Rect x={-50} y={-50} width={5000} height={5000} fill="#fff" />
          <APath d={d} fill="#000" transform={`translate(${HAIR} ${HAIR})`} />
        </Mask>
        <Mask id={`${id}b`} maskUnits="userSpaceOnUse" x={-50} y={-50} width={5000} height={5000}>
          <Rect x={-50} y={-50} width={5000} height={5000} fill="#fff" />
          <APath d={d} fill="#000" transform={`translate(${-HAIR} ${-HAIR})`} />
        </Mask>
      </Defs>
      <APath d={d} fill="none" stroke="#fff" strokeOpacity={edge} strokeWidth={2 * HAIR} clipPath={`url(#${id}c)`} />
      <APath d={d} fill="#fff" fillOpacity={lit} mask={`url(#${id}l)`} />
      <APath d={d} fill="#fff" fillOpacity={back} mask={`url(#${id}b)`} />
    </Svg>
  );
}

/** What of a bar chosen the component draws (the stack sliding down), as the loop chose it. */
interface SwapShot { id: number; i: number; n: number; key: string | null; laid: Geo; lit: Record<string, number> }

let tokens = 0;

/**
 * The bottom bar over the pages. `sets`: the bars (`cur` the one in view); `active`: the place shown (null: none);
 * `action`: its page's primary action, in the notch (null: none, the notch closed); `notches`: whether a place's page
 * has one (a bar chosen with a place in it lands with the notch as that place will have it); `shown`: on a place's top
 * page, with nothing over it. `dots`: a place's status dot and its colour; `icon`: a place's icon in a colour. (`haze`,
 * the Android app's source of what the glass frosts, is the window itself here: the glass blurs what is behind it.)
 */
export function BottomBar({
  sets, cur, active, action, shown, dots, labelOf, notches, icon, onTab, onSwitch,
}: {
  sets: string[][]; cur: number; active: string | null; action: BarAction | null; shown: boolean; haze?: unknown;
  dots: Record<string, string>; labelOf: (key: string) => string; notches: (key: string) => boolean;
  icon: (key: string, tint: string) => ReactNode;
  onTab: (key: string) => void; onSwitch: (i: number, key: string | null) => void;
}) {
  const C = useC();
  const dark = C.dark;
  const insets = useSafeAreaInsets();
  const { width: maxWidth } = useWindowDimensions();
  // 22 in from either side, as from the foot: the ball (6 past the bar) as far from the screen's sides as from its foot.
  const w = maxWidth - 44;
  const notchesOf: Record<string, boolean> = {};
  for (const set of sets) for (const key of set) notchesOf[key] = notches(key);
  const told: Told = { w, sets, cur, active, hasAction: action != null, notches: notchesOf, shown };
  const first = sets[cur] ?? [];
  const [initial] = useState(() => makeModel(told, action != null, active != null && first.includes(active)));
  const model = useSharedValue<BarModel>(initial);

  // The latest of what the bar is told, for what the loop says back.
  const latest = useRef({ onTab, onSwitch });
  latest.current = { onTab, onSwitch };
  const said = (events: Said[]) => {
    for (const e of events) {
      if ("tab" in e) latest.current.onTab(e.tab);
      else latest.current.onSwitch(e.switch, e.key);
    }
  };

  /**
   * The loop: a frame at a time while anything moves, asleep otherwise. (A named worklet: it asks for the next frame
   * for itself.)
   */
  function tick(now: number) {
    "worklet";
    model.modify((m) => {
      "worklet";
      step(m, m.last < 0 ? 1 / 60 : clamp((now - m.last) / 1000, 0, 0.05));
      m.last = now;
      settleGoals(m);
      if (m.out.length > 0) {
        const out = m.out;
        m.out = [];
        runOnJS(said)(out);
      }
      if (moving(m)) {
        m.frames = (m.frames ?? 0) + 1;
        if (m.frames % 600 === 0) runOnJS(console.log)(`stillfail: the bar's loop, ${m.frames} frames on: ${whyMoving(m)}`);
        requestAnimationFrame(tick);
      } else { m.running = false; m.frames = 0; }
      return m;
    }, true);
  }
  /** After a change: the goals worked out again, what was chosen said, and the loop woken if anything moves. */
  const settle = (m: BarModel) => {
    "worklet";
    settleGoals(m);
    if (m.out.length > 0) {
      const out = m.out;
      m.out = [];
      runOnJS(said)(out);
    }
    if (!m.running && moving(m)) {
      m.running = true;
      m.last = -1;
      requestAnimationFrame(tick);
    }
  };
  /** Runs `fn` on the model (on the UI thread), then settles it. */
  const change = (fn: (m: BarModel) => void) => {
    "worklet";
    model.modify((m) => {
      "worklet";
      fn(m);
      settle(m);
      return m;
    }, true);
  };

  // What the bar is told, to the loop (Bar.kt's SideEffects); hidden, nothing of it is open or held.
  const toldKey = JSON.stringify(told);
  useLayoutEffect(() => {
    runOnUI((t: Told) => {
      "worklet";
      change((m) => {
        const was = m.told.shown;
        m.told = t;
        if (was && !t.shown) {
          if (m.mode) openPanel(m, false);
          lost(m);
        }
      });
    })(told);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [toldKey]);

  // What the component draws as the loop has it: the panel open (and its rows out), a bar being chosen, the action out.
  const [mode, setMode] = useState(false);
  const [swap, setSwap] = useState<SwapShot | null>(null);
  const [actionOn, setActionOn] = useState(initial.k.value > 0.9);
  const [actionOut, setActionOut] = useState(initial.k.value > 0.001);
  const [panelOut, setPanelOut] = useState(false);
  const [gone, setGone] = useState(!shown);
  const [iconWasOn, setIconWasOn] = useState(false);
  useAnimatedReaction(() => model.value.mode, (now, was) => { if (now !== was) runOnJS(setMode)(now); });
  useAnimatedReaction(() => model.value.swapId, (now, was) => {
    if (now === was) return;
    const s = model.value.swap;
    runOnJS(setSwap)(now !== 0 && s != null ? { id: now, i: s.i, n: s.n, key: s.key, laid: s.laid, lit: s.lit } : null);
  });
  useAnimatedReaction(() => kNow(model.value) > 0.9, (now, was) => { if (now !== was) runOnJS(setActionOn)(now); });
  useAnimatedReaction(() => kNow(model.value) > 0.001, (now, was) => { if (now !== was) runOnJS(setActionOut)(now); });
  useAnimatedReaction(() => model.value.mode || model.value.o.value > 0.001, (now, was) => { if (now !== was) runOnJS(setPanelOut)(now); });
  useAnimatedReaction(() => model.value.vis.value <= 0, (now, was) => { if (now !== was) runOnJS(setGone)(now); });
  useAnimatedReaction(() => model.value.iconWas, (now, was) => { if (now !== was) runOnJS(setIconWasOn)(now); });

  // The panel open: back closes it.
  const backs = useRef({ shown, mode });
  backs.current = { shown, mode };
  useEffect(() => {
    const sub = BackHandler.addEventListener("hardwareBackPress", () => {
      if (!(backs.current.shown && backs.current.mode)) return false;
      runOnUI(() => {
        "worklet";
        change((m) => openPanel(m, false));
      })();
      return true;
    });
    return () => sub.remove();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // The page's primary action shown in the notch: closing, it keeps the last action's icon as it shrinks. From one
  // action to another with another icon (令 and a "+"): the icon swaps, the circle stays.
  const face = useRef<BarAction | null>(action);
  if (action != null) face.current = action;
  const shownAction = face.current;
  const [icons, setIcons] = useState<{ icon: IconPaths | null; was: IconPaths | null }>({ icon: shownAction?.icon ?? null, was: null });
  useLayoutEffect(() => {
    const next = shownAction?.icon ?? null;
    // Another one swaps in (the circle staying), as it is when the notch is closed (nothing to see).
    if (next == null || next === icons.icon) return;
    if (icons.icon == null || !actionOut) {
      setIcons({ icon: next, was: null });
      runOnUI(() => {
        "worklet";
        change((m) => { m.iconWas = false; glideJump(m.iconSwap, 1); });
      })();
      return;
    }
    setIcons({ icon: next, was: icons.icon });
    runOnUI(() => {
      "worklet";
      change((m) => { m.iconWas = true; glideJump(m.iconSwap, 0); glideTo(m.iconSwap, 1, 300, LINEAR); });
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shownAction?.icon, actionOut]);
  // The one going is gone once its swap is over.
  useEffect(() => { if (!iconWasOn && icons.was != null) setIcons((i) => ({ icon: i.icon, was: null })); }, [iconWasOn, icons.was]);

  const g = geoOf(w, sets, cur, active, action != null);
  const laid = swap?.laid ?? null;
  const idle = dark ? "#D1D5DB" : "#6B7280";
  const lit = dark ? "#FFFFFF" : "#111827";
  const bg = C.bg;
  const raised = raisedOf(C);
  const accent = C.accent;

  const vis = useAnimatedStyle(() => {
    const v = model.value.vis.value;
    return { opacity: v, transform: [{ translateY: (1 - v) * 120 }] };
  });
  const glassBox = useAnimatedStyle(() => {
    const top = clipTop(model.value, g);
    const h = Math.max(1, g.panel - top);
    return { top, height: h, borderRadius: Math.min(RAD, h / 2) };
  });
  const glassD = useDerivedValue(() => {
    const m = model.value;
    const h = Math.max(1, g.panel - clipTop(m, g));
    return outline(w, h, w / 2, notchY(m), notchR(m));
  });
  const notchD = useDerivedValue(() => {
    const m = model.value;
    const p: P = { d: "", empty: true };
    // The notch's own outline alone. (Drawn from the bar's left end along its edge, the half of the stroke below the
    // edge showed: a line over the ball and past the bar's rounded end.)
    if (!notch(p, w / 2, notchY(m), notchR(m), FILLET, true)) return "M0 0";
    return p.d;
  });
  const notchTop = useAnimatedStyle(() => ({ transform: [{ translateY: clipTop(model.value, g) }] }));
  const actionBox = useAnimatedStyle(() => {
    const k = kNow(model.value);
    const s = Math.max(0.001, k);
    return { opacity: Math.min(1, k * 3), transform: [{ translateY: notchY(model.value) }, { scale: s }] };
  });
  const wasLook = useAnimatedStyle(() => {
    const p = cssEase(clamp((model.value.iconSwap.value * 300) / 120, 0, 1));
    return { opacity: 1 - p, transform: [{ scale: 1 - 0.5 * p }] };
  });
  const nowLook = useAnimatedStyle(() => {
    const ms = model.value.iconSwap.value * 300;
    return { opacity: cssEase(clamp((ms - 60) / 180, 0, 1)), transform: [{ scale: 0.5 + 0.5 * arriveEase(clamp((ms - 60) / 240, 0, 1)) }] };
  });
  const ballLook = useAnimatedStyle(() => {
    const m = model.value;
    const b = m.ball;
    if (b == null) return { opacity: 0 };
    const box = ballBox(b, m.goalX, m.held.value, m.ballScale.value);
    return { left: box.left, top: box.top, width: Math.max(1, box.width), height: Math.max(1, box.height), borderRadius: Math.min(box.width, box.height) / 2, opacity: m.ballAlpha.value };
  });
  const ballD = useDerivedValue(() => {
    const m = model.value;
    const b = m.ball;
    if (b == null) return "M0 0";
    const box = ballBox(b, m.goalX, m.held.value, m.ballScale.value);
    return roundRect(Math.max(1, box.width), Math.max(1, box.height), Math.min(box.width, box.height) / 2);
  });
  const actionD = useDerivedValue(() => roundRect(DROP, DROP, DROP / 2));
  const rowsLook = useAnimatedStyle(() => ({ opacity: rowsAlpha(model.value), transform: [{ translateY: rowsShift(model.value, g) }] }));
  const windowBox = useAnimatedStyle(() => {
    const top = clipTop(model.value, g);
    return { top, height: Math.max(0, g.panel - top) };
  });
  const windowInner = useAnimatedStyle(() => ({ transform: [{ translateY: -clipTop(model.value, g) }] }));

  // The glass's gestures: a finger set on it, moved, lifted (or lost), in the panel's frame.
  const gesture = Gesture.Manual()
    .enabled(shown)
    .onTouchesDown((e, manager) => {
      const m = model.value;
      if (!m.ended) return;
      const touch = e.changedTouches[0];
      if (touch == null) return;
      manager.activate();
      change((m) => {
        m.finger = touch.id;
        m.ended = false;
        down(m, { x: touch.x, y: touch.y + clipTop(m, m.geo ?? g) });
      });
    })
    .onTouchesMove((e) => {
      const touch = e.allTouches.find((t) => t.id === model.value.finger);
      if (touch == null) return;
      change((m) => { move(m, { x: touch.x, y: touch.y + clipTop(m, m.geo ?? g) }); });
    })
    .onTouchesUp((e, manager) => {
      const touch = e.changedTouches.find((t) => t.id === model.value.finger);
      if (touch == null) return;
      change((m) => {
        m.ended = true;
        m.finger = -1;
        up(m, { x: touch.x, y: touch.y + clipTop(m, m.geo ?? g) });
      });
      manager.end();
    })
    .onTouchesCancelled((_e, manager) => {
      change((m) => { if (!m.ended) { m.ended = true; m.finger = -1; lost(m); } });
      manager.end();
    })
    .onFinalize(() => {
      change((m) => { if (!m.ended) { m.ended = true; m.finger = -1; lost(m); } });
    });

  const closePanel = () => {
    runOnUI(() => {
      "worklet";
      change((m) => openPanel(m, false));
    })();
  };
  const pickOn = (i: number, key: string | null) => {
    runOnUI((i: number, key: string | null) => {
      "worklet";
      change((m) => pick(m, i, key));
    })(i, key);
  };

  if (gone && !shown) return null;
  const actionTop = g.rowTop - DROP / 2;
  return (
    <View pointerEvents="box-none" style={StyleSheet.absoluteFill}>
      {/* The panel open: a press anywhere else closes it (and does nothing else). */}
      {shown && mode ? <View style={StyleSheet.absoluteFill} onStartShouldSetResponder={() => { closePanel(); return true; }} /> : null}
      <Animated.View pointerEvents="box-none" style={[{ position: "absolute", left: (maxWidth - w) / 2, bottom: 22 + insets.bottom, width: w, height: g.panel }, vis]}>
        {/*
          The shadow of the glass, cast below it and to its sides only: none under it (an outer shadow is not drawn under
          its box), coming in down its rounded ends. (Bar.kt fades it in from nothing at the glass's top; a box shadow
          cannot fade.)
        */}
        <Animated.View
          pointerEvents="none"
          style={[{ position: "absolute", left: 0, width: w, borderRadius: RAD, boxShadow: `0px 4px 12px 0px rgba(0,0,0,${dark ? 0.45 : 0.16})` }, glassBox, { borderRadius: RAD }]}
        />
        {/*
          The glass: exactly as tall as what shows of it, the notch cut out of its tint by its outline. The gestures are
          its. NATIVE: a view that clips what it holds (the blur) to an animated path, the outline with its notch (Bar.kt's
          graphicsLayer clip, and the system's gesture exclusion along it, systemGestureExclusion): here the blur is
          clipped to the rounded glass, so the ring of the notch round the action shows the pages blurred but untinted
          rather than as they are.
        */}
        <GestureDetector gesture={gesture}>
          <Animated.View testID="bar-glass" style={[{ position: "absolute", left: 0, width: w, overflow: "hidden" }, glassBox]}>
            <Frost tint={raised} alpha={0} px={20} style={StyleSheet.absoluteFill} />
            <Svg width="100%" height="100%" style={StyleSheet.absoluteFill} pointerEvents="none">
              <APath d={glassD} fill={withAlpha(raised, 0.72)} />
            </Svg>
            {dark ? <Rim d={glassD} edge={0.14} lit={0.3} back={0.16} /> : <Rim d={glassD} edge={0.35} lit={0.8} back={0.45} />}
          </Animated.View>
        </GestureDetector>
        {/* The notch's edge, lit as the glass's own rim. */}
        <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, notchTop]}>
          <Svg width={w} height={g.panel} pointerEvents="none">
            <Defs>
              <ClipPath id="notchFoot"><Rect x={0} y={0.25} width={w} height={g.panel} /></ClipPath>
            </Defs>
            <APath d={notchD} fill="none" stroke="#fff" strokeOpacity={dark ? 0.22 : 0.7} strokeWidth={1} clipPath="url(#notchFoot)" />
          </Svg>
        </Animated.View>
        {/*
          The page's primary action (令, a new chat; a "+"): accent glass in the notch; it grows out of the bar as the
          notch opens. Closing, it keeps the last action's icon as it shrinks.
        */}
        {actionOut && shownAction != null ? (
          <Animated.View
            testID="bar-action"
            pointerEvents={actionOn && shown && action != null ? "auto" : "none"}
            style={[{ position: "absolute", left: (w - DROP) / 2, top: actionTop, width: DROP, height: DROP, borderRadius: DROP / 2, overflow: "hidden" }, actionBox]}
          >
            <Frost tint={accent} alpha={0.86} px={20} style={StyleSheet.absoluteFill} />
            <Rim d={actionD} edge={0.4} lit={0.75} back={0.4} />
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={action?.label}
              disabled={!(actionOn && shown && action != null)}
              onPress={() => action?.run()}
              android_ripple={{ color: "rgba(255,255,255,0.24)", borderless: false }}
              style={[StyleSheet.absoluteFill, { alignItems: "center", justifyContent: "center" }]}
            >
              {/* Another "+" (文件's to Profile's) is the same icon: nothing moves. */}
              {icons.was != null && iconWasOn ? <ActionIcon icon={icons.was} look={wasLook} /> : null}
              {icons.icon != null ? <ActionIcon icon={icons.icon} look={nowLook} /> : null}
            </Pressable>
          </Animated.View>
        ) : null}
        {/* The ball: under the places (they stay sharp over it), over the action. */}
        <Animated.View
          testID="bar-ball"
          pointerEvents="none"
          style={[{ position: "absolute", overflow: "hidden", boxShadow: dark ? "0px 1px 8px 0px rgba(0,0,0,0.35)" : "0px 1px 8px 0px rgba(55,53,45,0.2)" }, ballLook]}
        >
          {/* The glass's frost and tint under its own (as a blur of the glass looked: the two blurs' as one). */}
          <Frost tint={raised} alpha={0.72} px={24} style={StyleSheet.absoluteFill} />
          <View style={[StyleSheet.absoluteFill, { backgroundColor: withAlpha("#FFFFFF", dark ? 0.12 : 0.42) }]} />
          {dark ? <Rim d={ballD} edge={0.22} lit={0.45} back={0.25} /> : <Rim d={ballD} edge={0.5} lit={0.95} back={0.55} />}
        </Animated.View>
        {/*
          The other bars, above this one, as the panel opens (each a row, every place as far from its row's edges as the
          bar's are from the bar's).
        */}
        {panelOut && swap == null ? (
          <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, rowsLook]}>
            {g.others.map((i, n) => {
              const set = g.sets[i]!;
              const cs = barCentres(w, 0, set.length);
              return set.map((key, j) => (
                <Place
                  key={`row:${i}:${key}`} model={model} change={change} id={`row:${key}`} row set={i} placeKey={key} label={labelOf(key)} active={active}
                  idle={idle} lit={lit} dot={dots[key]} icon={icon} left={cs[j]! - g.slot / 2} top={OVER + n * ROW + 4} slot={g.slot}
                  role="button" onA11y={() => pickOn(i, key)}
                />
              ));
            })}
          </Animated.View>
        ) : null}
        {/* The bar's places, over the ball. */}
        {swap == null
          ? g.items.map((key, j) => (
            <Place
              key={`bar:${key}`} model={model} change={change} id={`bar:${key}`} row={false} set={cur} placeKey={key} label={labelOf(key)} active={active}
              idle={idle} lit={lit} dot={dots[key]} icon={icon} slot={g.slot} top={g.rowTop + 4} at={{ j, n: g.items.length }} w={w}
              role="tab" onA11y={() => onTab(key)}
            />
          ))
          : null}
        {/*
          A bar being chosen: the stack of bars slides down inside the closing glass, the chosen one into the bar's place,
          what is not chosen cut off by the glass's edge. Nothing fades out. It starts as the rows and the bar were drawn
          (the rows' fade and offset, each place as lit as it was), and comes to the bar's look as it lands (the place
          shown lit): landed, it is the bar's places as drawn the next frame, and goes with nothing changing.
        */}
        {swap != null && laid != null ? (
          <Animated.View pointerEvents="none" style={[{ position: "absolute", left: 0, width: w, borderRadius: RAD, overflow: "hidden" }, windowBox]}>
            <Animated.View style={[{ position: "absolute", left: 0, top: 0, width: w, height: g.panel }, windowInner]}>
              {laid.others.map((i, n) => {
                if (i === swap.i) return null;
                const set = laid.sets[i]!;
                const cs = barCentres(laid.w, 0, set.length);
                return set.map((key) => (
                  <Flying key={`f:${i}:${key}`} model={model} placeKey={key} kind={{ row: true, n, x: cs[set.indexOf(key)]! }} from={swap.lit[`row:${key}`] ?? 0} to={null}
                    idle={idle} lit={lit} dot={dots[key]} icon={icon} slot={g.slot} />
                ));
              })}
              {(laid.sets[swap.i] ?? []).map((key, j) => (
                <Flying key={`c:${key}`} model={model} placeKey={key} kind={{ chosen: true, j }} from={swap.lit[`row:${key}`] ?? 0} to={key === active ? 1 : 0}
                  idle={idle} lit={lit} dot={dots[key]} icon={icon} slot={g.slot} />
              ))}
              {laid.items.map((key, j) => (
                <Flying key={`b:${key}`} model={model} placeKey={key} kind={{ bar: true, j, n: laid.items.length }} from={swap.lit[`bar:${key}`] ?? 0} to={null}
                  idle={idle} lit={lit} dot={dots[key]} icon={icon} slot={g.slot} />
              ))}
            </Animated.View>
          </Animated.View>
        ) : null}
      </Animated.View>
    </View>
  );
}

/**
 * A place's icon in a colour from `idle` (0) to `lit` (1): the idle one, the lit one over it as lit as it is (the same
 * lines, so as the two colours mixed).
 */
function PlaceFace({ placeKey, idle, lit, light, dot, icon }: { placeKey: string; idle: string; lit: string; light: ReturnType<typeof useAnimatedStyle>; dot: string | undefined; icon: (key: string, tint: string) => ReactNode }) {
  return (
    <>
      <View style={face.icon}>{icon(placeKey, idle)}</View>
      <Animated.View style={[face.icon, light]}>{icon(placeKey, lit)}</Animated.View>
      {/* Its dot at the icon's top right. */}
      {dot != null ? <View style={[face.dot, { backgroundColor: dot }]} /> : null}
    </>
  );
}

const face = StyleSheet.create({
  icon: { ...StyleSheet.absoluteFillObject, alignItems: "center", justifyContent: "center" },
  dot: { position: "absolute", left: "50%", top: "50%", marginLeft: 13.5 - 3.5, marginTop: -12.5 - 3.5, width: 7, height: 7, borderRadius: 3.5 },
});

/**
 * A place on the bar or in the panel: its icon in the middle of its slot (lit when it is the one, going from one to the
 * other over 300 ms, the bar's loop stepping it), its dot at the icon's top right. On the bar (`at`), it follows the
 * notch as it opens.
 */
function Place({
  model, change, id, row, set, placeKey, label, active, idle, lit, dot, icon, left, top, slot, at, w, role, onA11y,
}: {
  model: SharedValue<BarModel>; change: (fn: (m: BarModel) => void) => void; id: string; row: boolean; set: number; placeKey: string; label: string;
  active: string | null; idle: string; lit: string; dot: string | undefined; icon: (key: string, tint: string) => ReactNode;
  left?: number; top: number; slot: number; at?: { j: number; n: number }; w?: number; role: "tab" | "button"; onA11y: () => void;
}) {
  // As it is when it comes, not lit up as it comes (the loop works out whether it is the one as it is told of it).
  const [start] = useState(() => (active === placeKey ? 1 : 0));
  useEffect(() => {
    const token = ++tokens;
    runOnUI((id: string, token: number, row: boolean, key: string, set: number, start: number) => {
      "worklet";
      change((m) => { m.tints[id] = { ...glide(start), token, row, key, set }; });
    })(id, token, row, placeKey, set, start);
    return () => {
      runOnUI((id: string, token: number) => {
        "worklet";
        change((m) => { if (m.tints[id]?.token === token) delete m.tints[id]; });
      })(id, token);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, row, set, placeKey]);
  const light = useAnimatedStyle(() => ({ opacity: model.value.tints[id]?.value ?? start }));
  const place = useAnimatedStyle(() => {
    if (at == null || w == null) return {};
    return { transform: [{ translateX: barCentres(w, kNow(model.value), at.n)[at.j]! - slot / 2 }] };
  });
  return (
    // Its taps are the glass's (the gestures read where they land): here only what a screen reader says and does.
    <Animated.View
      testID={`bar-place-${placeKey}`}
      pointerEvents="none"
      accessible
      accessibilityLabel={label}
      accessibilityRole={role}
      accessibilityState={{ selected: active === placeKey }}
      accessibilityActions={[{ name: "activate" }]}
      onAccessibilityAction={(e) => { if (e.nativeEvent.actionName === "activate") onA11y(); }}
      style={[{ position: "absolute", left: left ?? 0, top, width: slot, height: 48 }, place]}
    >
      <PlaceFace placeKey={placeKey} idle={idle} lit={lit} light={light} dot={dot} icon={icon} />
    </Animated.View>
  );
}

/**
 * A place's icon as a bar is chosen, its middle where it goes (dp), in a slot as the bar's places are; faded and dropped
 * as the rows were when it comes from them. `kind`: a row not chosen (`row`, its row and its middle), the chosen bar's
 * (`chosen`, its place), the bar left (`bar`); `from` how lit it was, `to` how lit it lands (null: as it was).
 */
function Flying({
  model, placeKey, kind, from, to, idle, lit, dot, icon, slot,
}: {
  model: SharedValue<BarModel>; placeKey: string;
  kind: { row: true; n: number; x: number } | { chosen: true; j: number } | { bar: true; j: number; n: number };
  from: number; to: number | null; idle: string; lit: string; dot: string | undefined; icon: (key: string, tint: string) => ReactNode; slot: number;
}) {
  const look = useAnimatedStyle(() => {
    const m = model.value;
    const s = m.swap ?? m.swapLast;
    if (s == null) return { opacity: 0 };
    const at = swapAt(m, s);
    const shift = at != null ? at.y - rowMid(s.n) : 0;
    let x = 0;
    let y = 0;
    let alpha = 1;
    let drop = 0;
    if ("row" in kind) {
      x = kind.x; y = rowMid(kind.n) + shift; alpha = rowAlpha(m, s); drop = rowDrop(m, s);
    } else if ("chosen" in kind) {
      if (at == null) return { transform: [{ translateX: -slot / 2 }, { translateY: -24 }] };
      x = at.xs[kind.j]!; y = at.y; alpha = rowAlpha(m, s); drop = rowDrop(m, s);
    } else {
      x = barCentres(s.laid.w, kNow(m), kind.n)[kind.j]!; y = s.laid.barMid + shift;
    }
    return { opacity: alpha, transform: [{ translateX: x - slot / 2 }, { translateY: y - 24 + drop }] };
  });
  const light = useAnimatedStyle(() => {
    if (to == null) return { opacity: from };
    const m = model.value;
    const s = m.swap ?? m.swapLast;
    const t = s == null ? 1 : swapT(m, s);
    return { opacity: t >= 1 ? to : t <= 0 ? from : from + (to - from) * t };
  });
  return (
    <Animated.View testID={`bar-flying-${placeKey}`} style={[{ position: "absolute", left: 0, top: 0, width: slot, height: 48 }, look]}>
      <PlaceFace placeKey={placeKey} idle={idle} lit={lit} light={light} dot={dot} icon={icon} />
    </Animated.View>
  );
}

/** The notch's icon, as `look` has it (its swap). */
function ActionIcon({ icon, look }: { icon: IconPaths; look: ReturnType<typeof useAnimatedStyle> }) {
  return (
    <Animated.View testID="bar-action-icon" style={[{ position: "absolute" }, look]}>
      <Icon icon={icon} size={icon === Icons.Ling ? 40 : 30} color="#FFFFFF" />
    </Animated.View>
  );
}
