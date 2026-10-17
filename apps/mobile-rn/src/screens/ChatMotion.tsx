// How a chat's rows move, apart from the list itself (web/src/Chat.tsx → useEmissions, Quotes → jump; their keyframes in
// styles/keyframes.css.ts): an agent's message coming out of its activity's avatar, and a quoted message flashing when a
// quote leads to it. The state is the page's, outside the rows (a row scrolled away and back is drawn anew).
import { createContext, useContext, useEffect, useState, useSyncExternalStore, type ReactNode } from "react";
import { View, type StyleProp, type ViewStyle } from "react-native";
import type { SharedValue } from "react-native-reanimated";
import type { ChatMessage } from "../../../../web/src/core/shapes.ts";
import { Ease } from "../ui/Motion";
import { Smooth } from "../ui/Smooth";
import { STROKE_GAP_MS, STROKE_MS, TextMark } from "../ui/TextMark";
import { useC, withAlpha } from "../ui/Theme";
import type { Follow } from "../ui/Follow";
import type { Box, LayoutCoordinates, Where } from "./ChatHost";

// ── a clock for what is drawn frame by frame (Compose's Animatable, as the JS side runs it) ──

/** An easing as Ease has it (Reanimated's factory) or a plain function: the plain function. */
export type Easing = ((t: number) => number) | { factory: () => (t: number) => number };
export function eased(e: Easing): (t: number) => number {
  return typeof e === "function" ? e : e.factory();
}
const LINEAR = (t: number) => t;

/**
 * A value that moves to where it is sent, frame by frame on the JS side (Compose's Animatable): those drawing by it
 * `subscribe` and are drawn again each frame it changes. A new move cancels the one going (its promise says false).
 */
export class Animatable {
  #value: number;
  #frame: number | null = null;
  #timer: ReturnType<typeof setTimeout> | null = null;
  #done: ((finished: boolean) => void) | null = null;
  readonly #listeners = new Set<() => void>();
  constructor(initial: number) { this.#value = initial; }
  get value() { return this.#value; }
  get isRunning() { return this.#frame != null || this.#timer != null; }
  subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  #set(v: number) { this.#value = v; for (const l of this.#listeners) l(); }
  #stop() {
    if (this.#frame != null) cancelAnimationFrame(this.#frame);
    if (this.#timer != null) clearTimeout(this.#timer);
    this.#frame = null;
    this.#timer = null;
    const done = this.#done;
    this.#done = null;
    done?.(false);
  }
  snapTo(v: number) { this.#stop(); this.#set(v); }
  stop() { this.#stop(); }
  /** Over `duration` ms, `at(t)` its value `t` ms in (a tween, keyframes). */
  run(duration: number, at: (ms: number) => number, delay = 0): Promise<boolean> {
    this.#stop();
    return new Promise((resolve) => {
      this.#done = resolve;
      const begin = () => {
        this.#timer = null;
        let start: number | null = null;
        const step = (now: number) => {
          if (start == null) start = now;
          const ms = now - start;
          if (ms >= duration) {
            this.#frame = null;
            this.#done = null;
            this.#set(at(duration));
            resolve(true);
            return;
          }
          this.#set(at(ms));
          this.#frame = requestAnimationFrame(step);
        };
        this.#frame = requestAnimationFrame(step);
      };
      if (delay > 0) this.#timer = setTimeout(begin, delay);
      else begin();
    });
  }
  /** tween(duration, easing, delay) from where it is to `target`. */
  animateTo(target: number, duration: number, easing: Easing = LINEAR, delay = 0): Promise<boolean> {
    const from = this.#value;
    const e = eased(easing);
    if (duration <= 0) { this.snapTo(target); return Promise.resolve(true); }
    return this.run(duration, (ms) => from + (target - from) * e(Math.min(1, ms / duration)), delay);
  }
}

/** Drawn again each time `a` moves. */
export function useAnimatable(a: Animatable | null | undefined): number {
  return useSyncExternalStore((l) => (a ? a.subscribe(l) : () => undefined), () => a?.value ?? 0);
}

/** Compose's keyframes: (ms, value, easing of the stretch from it) — the value `ms` in. */
function keyframes(frames: [ms: number, value: number, easing?: Easing][]): (ms: number) => number {
  return (ms) => {
    for (let i = 0; i + 1 < frames.length; i++) {
      const [a, va, e] = frames[i]!;
      const [b, vb] = frames[i + 1]!;
      if (ms <= b) return va + (vb - va) * eased(e ?? LINEAR)(b > a ? (ms - a) / (b - a) : 1);
    }
    return frames[frames.length - 1]![1];
  };
}

export const LocalChatMotion = createContext<ChatMotion | null>(null);

/** Where the flying avatar's 18dp face is, in the pane, and how it is scaled about its middle (`sx`, `sy`). */
export class Flying { constructor(readonly at: { x: number; y: number }, readonly sx: number, readonly sy: number) {} }

export enum Pose { Fold = "Fold", Float = "Float", Spit = "Spit", Return = "Return" }
const POSE_MS: Record<Pose, number> = { [Pose.Fold]: 170, [Pose.Float]: 440, [Pose.Spit]: 380, [Pose.Return]: 320 };

/** `from`: on from the same agent's message before it (where its avatar is), dropping on without going home; `fold`:
 *  how much of its folding is left (it folds from when its message begins waiting). */
export class Turn {
  constructor(readonly seq: number, readonly agent: string, readonly pose: Pose, readonly from: { x: number; y: number } | null = null, readonly fold: number = POSE_MS[Pose.Fold]) {}
}

const now = () => performance.now();

/**
 * A message an agent posts while its activity shows comes out of the activity's avatar, one at a time (web
 * useEmissions): the activity folds to its avatar (Fold), the avatar hops to where the message goes (Float: up, slowing,
 * then falling ever faster, stretched, stopping dead there), the message comes out of it as it lands, the avatar
 * flattened by the fall and springing back (Spit), and the avatar goes on down to where the activity now is, which
 * unfolds again (Return). Until its turn a message waits out of the list. With animations off messages just
 * appear, and so do those no one watches come out: arriving while the page is not in front or the reader has scrolled
 * up, and all still waiting when that happens.
 */
export class ChatMotion {
  static readonly Pose = Pose;
  readonly #reduced: boolean;
  readonly #listeners = new Set<() => void>();
  readonly #decided = new Map<number, boolean>();
  readonly #done = new Set<number>();
  /** Waiting messages: seq, agent, and since when (ms; the agent's activity folds from then). */
  readonly #queue: [number, string, number][] = [];
  #copied: string | null = null;
  #current: Turn | null = null;
  #version = 0;
  /** Where the flying avatar was last sent, for which message. */
  #aimed: { x: number; y: number } | null = null;
  #aimedAt = -1;
  /** Where the flying avatar last let a message out (in the pane): where it drops on from to the same agent's next. */
  #landed: { x: number; y: number } | null = null;

  constructor(reduced: boolean) { this.#reduced = reduced; }

  subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  #changed() { this.#version++; for (const l of this.#listeners) l(); }
  /** Bumped as anything here changes (what is drawn by it reads it). */
  get version() { return this.#version; }

  /** Whose avatar the flying copy shows as, while it shows (Chat.tsx Flyer): that activity's own is hidden. */
  get copied() { return this.#copied; }
  set copied(k: string | null) { if (k !== this.#copied) { this.#copied = k; this.#changed(); } }
  /** The clock of the rings round the agents' avatars, one for the chat (Chat.tsx WorkRing): ms into its 6s loop. */
  ring: SharedValue<number> | null = null;
  get current() { return this.#current; }
  #setCurrent(t: Turn | null) { this.#current = t; this.#changed(); }
  /** The current pose's time, 0 to 1, linear: each part eases it as its own keyframes do. */
  readonly clock = new Animatable(0);

  /** Where things are, as last laid out: the list's box (what the flying avatar moves in), each activity's avatar and
   *  row, each message's avatar. Read anew each frame while it flies. */
  where: Where | null = null;
  readonly activityAvatars = new Map<string, LayoutCoordinates>();
  readonly activityRows = new Map<string, LayoutCoordinates>();
  readonly landings = new Map<number, LayoutCoordinates>();

  /** Messages seen for the first time: an agent's, said while the chat shows (the core's `said`), while its activity
   *  shows, waits its turn to come out of it. */
  take(messages: ChatMessage[], showing: Set<string>) {
    for (const m of messages) {
      if (this.#decided.has(m.seq)) continue;
      const agent = m.authorKind === "agent" && !m.mine && !m.system ? m.by.agent ?? null : null;
      const emits = !this.#reduced && this.watched && m.said === true && agent != null && showing.has(agent);
      this.#decided.set(m.seq, emits);
      if (emits) this.#queue.push([m.seq, agent!, now()]);
    }
  }

  /** Whether messages coming in are watched (the page in front, the reader at the end), as last drawn. */
  watched = false;

  /** The first waiting starts, once drawn (not from drawing itself). */
  start() {
    if (this.#current == null && this.#queue.length > 0) this.#nextAfter(null);
  }

  /** Whether a message comes (or came) out of an avatar: it never eases in as others do. */
  emits(seq: number) { return this.#decided.get(seq) === true; }

  /** Waiting its turn (or its avatar still on its way to it): not in the list yet. */
  held(seq: number): boolean {
    if (this.#decided.get(seq) !== true || this.#done.has(seq)) return false;
    const c = this.#current;
    return !(c?.seq === seq && (c.pose === Pose.Spit || c.pose === Pose.Return));
  }

  emitting(seq: number) { const c = this.#current; return c != null && c.seq === seq && c.pose === Pose.Spit; }

  /** Agents whose activity must stay while their messages come out. */
  keeps(): Set<string> {
    const out = new Set<string>();
    for (const q of this.#queue) out.add(q[1]);
    if (this.#current) out.add(this.#current.agent);
    return out;
  }

  /** An agent's activity: folded to its avatar from when its first message begins waiting until its last is out (others'
   *  coming out between do not unfold and fold it again), and whether the avatar is away flying. */
  folded(agent: string): boolean {
    return this.#current?.agent === agent || this.#queue.some((q) => q[1] === agent);
  }
  away(agent: string) { const c = this.#current; return c != null && c.agent === agent && c.pose !== Pose.Fold; }

  #nextAfter(agent: string | null) {
    const next = this.#queue.shift();
    // The same agent's next message goes straight on: its activity is folded already; another's once folded.
    if (!next) { this.#setCurrent(null); return; }
    const left = POSE_MS[Pose.Fold] - Math.trunc(now() - next[2]);
    this.#setCurrent(new Turn(next[0], next[1], next[1] === agent || left <= 0 ? Pose.Float : Pose.Fold, null, Math.max(0, left)));
  }

  #finish(turn: Turn) {
    this.#done.add(turn.seq);
    this.#nextAfter(turn.agent);
  }

  /** Everything waiting or coming out shows at once, where it is. */
  release() {
    if (this.#current == null && this.#queue.length === 0) return;
    for (const q of this.#queue) this.#done.add(q[0]);
    if (this.#current) this.#done.add(this.#current.seq);
    this.#queue.length = 0;
    this.clock.stop();
    this.#setCurrent(null);
  }

  /** Plays the current pose, then moves on to the next (run again as `current` changes). */
  async play(turn: Turn) {
    const attached = (c: LayoutCoordinates | undefined) => c?.view != null;
    const ready = turn.pose === Pose.Fold ? true
      : turn.pose === Pose.Float ? attached(this.activityAvatars.get(turn.agent)) && attached(this.activityRows.get(turn.agent))
      : attached(this.activityAvatars.get(turn.agent));
    if (!ready) return this.#finish(turn);
    this.clock.snapTo(0);
    const ms = turn.pose === Pose.Fold ? turn.fold : turn.pose === Pose.Float && turn.from != null ? DROP_MS : POSE_MS[turn.pose];
    const finished = await this.clock.animateTo(1, ms);
    // Cancelled: the turn moved on (all let out at once) or the page went.
    if (!finished || this.#current !== turn) return;
    // The next pose starts at its own beginning in the frame it takes over: drawn with this one's end (1) for a frame,
    // the avatar would be where the next ends (at home, or at the next message) and blink back.
    this.clock.snapTo(0);
    switch (turn.pose) {
      case Pose.Fold: this.#setCurrent(new Turn(turn.seq, turn.agent, Pose.Float)); break;
      case Pose.Float: this.#setCurrent(new Turn(turn.seq, turn.agent, Pose.Spit)); break;
      case Pose.Spit: {
        const next = this.#queue[0];
        const at = this.#landed;
        // The same agent's next message is waiting: the avatar drops on to it from here, not going home to hop again.
        if (next && next[1] === turn.agent && at != null) {
          this.#queue.shift();
          this.#done.add(turn.seq);
          this.#setCurrent(new Turn(next[0], next[1], Pose.Float, at));
        } else this.#setCurrent(new Turn(turn.seq, turn.agent, Pose.Return));
        break;
      }
      case Pose.Return: this.#finish(turn); break;
    }
  }

  /**
   * Where the flying avatar's 18dp face is, in the pane, or null when none flies: each frame between where it set out
   * and where it is going, both read anew (the message growing moves the one, the activity pushed down the other).
   * Out (web useEmissions → float): thrown up from the avatar, it slows to the top (34dp over the higher end), hangs
   * a moment, then drops ever faster onto the landing, stretched more as it falls; across, it eases in and out.
   * Letting the message out (spit): flattened by the landing (116% wide, 80% high), it springs back (stiffness 520,
   * damping 14, as the web's), with a small swell. Home (return): eased cubic-out.
   */
  flight(): Flying | null {
    const c = this.#current;
    if (c == null || c.pose === Pose.Fold) return null;
    const where = this.where;
    if (!where) return null;
    const at = (l: LayoutCoordinates | undefined): { x: number; y: number } | null => {
      const b: Box | null = l ? where.inPane(l) : null;
      return b ? { x: b.x, y: b.y } : null;
    };
    const avatar = at(this.activityAvatars.get(c.agent));
    if (!avatar) return null;
    // Before the message is in the list: where its avatar will be, the first activity's place (the message comes in
    // there, and the activities move down), 3dp down its row as a message's avatar sits.
    // As it comes in, the message is laid out a frame before its avatar says where it is, and the activity has moved
    // down already: until then, where it was aimed at.
    const known = at(this.landings.get(c.seq));
    const held = this.#aimedAt === c.seq && c.pose !== Pose.Float ? this.#aimed : null;
    // Not in the list yet, the message comes in over all the activities (they are the last things in the chat), not at
    // its own agent's: where the first of them is.
    let first: { x: number; y: number } | null = null;
    for (const r of this.activityRows.values()) { const p = at(r); if (p && (first == null || p.y < first.y)) first = p; }
    const landing = known ?? held ?? (first ? { x: first.x, y: first.y + 3 } : null);
    if (!landing) return null;
    this.#aimed = landing;
    this.#aimedAt = c.seq;
    const t = this.clock.value;
    switch (c.pose) {
      case Pose.Float: {
        // On from the message before it: only the drop.
        const start = c.from ?? avatar;
        const rise = c.from != null ? 0 : RISE;
        const top = c.from != null ? start.y : Math.min(start.y, landing.y) - HOP;
        const up = rise > 0 ? t / rise : 1;
        const down = (t - rise) / (1 - rise);
        const y = t < rise ? start.y + (top - start.y) * (1 - Math.pow(1 - up, 2.5)) : top + (landing.y - top) * Math.pow(down, 2.5);
        const across = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
        const stretch = t < rise ? 0.07 * Math.sin(Math.PI * up) : 0.14 * down * down;
        return new Flying({ x: start.x + (landing.x - start.x) * across, y }, 1 - stretch * 0.6, 1 + stretch);
      }
      case Pose.Spit: {
        this.#landed = landing;
        const k = settle((t * POSE_MS[Pose.Spit]) / 1000);
        const swell = 1 + 0.12 * (t < 0.4 ? smooth(t / 0.4) : t < 0.75 ? 1 - smooth((t - 0.4) / 0.35) : 0);
        return new Flying(landing, swell * (1 + 0.16 * k), swell * (1 - 0.2 * k));
      }
      default: {
        const e = 1 - (1 - t) * (1 - t) * (1 - t);
        return new Flying(lerp(landing, avatar, e), 1, 1);
      }
    }
  }

  // ── a quoted message flashing ──

  /** The list's following, which a jump to a quoted message leaves (the reader's move). (The page's scope a jump runs
   *  in is JS's own: a jump goes on as its row is scrolled away.) */
  follow: Follow | null = null;
  #flashes = 0;

  /**
   * The message a jump last led to, by ts. A quote's passage is marked in its words (`mark`: rounded grounds on its
   * lines, the accent at MARK_LEVEL); a message whose words do not hold it (the mark never `found`), or a jump to a
   * whole message, flashes it instead (`flash`: the accent's ground round the message, your bubble tinted). Either
   * comes in over FLASH_IN_MS, holds, then fades out: a highlight that steps or snaps reads as a flicker.
   */
  #flashed: string | null = null;
  #mark: TextMark | null = null;
  get flashed() { return this.#flashed; }
  get mark() { return this.#mark; }
  readonly flash = new Animatable(0);
  readonly #marking = new Animatable(0);

  /** The message a search opened the chat at, by ts, and its words marked in it (web ::highlight(search-hit)): kept
   *  until the chat is left, not flashed. */
  #foundAt: string | null = null;
  #found: TextMark | null = null;
  get foundAt() { return this.#foundAt; }
  get found() { return this.#found; }

  /** Marks `words` in the message `ts` (drawn once its row is), for as long as the chat shows. */
  markWords(ts: string, words: string[], accent: string) {
    this.#foundAt = ts;
    const m = new TextMark("", accent, words);
    m.level = 0.28;
    this.#found = m;
    this.#changed();
  }

  /** Draws in the strokes under a search's words (TextMark.drawn), once the message is in view. */
  async drawFound() {
    const m = this.#found;
    if (!m) return;
    if (this.#reduced) { m.drawn = Number.MAX_VALUE; this.#changed(); return; }
    const until = STROKE_MS + STROKE_GAP_MS * 12;
    const clock = new Animatable(0);
    const off = clock.subscribe(() => { m.drawn = clock.value; this.#changed(); });
    await clock.animateTo(until, until);
    off();
    m.drawn = Number.MAX_VALUE;
    this.#changed();
  }

  /** Starts marking `passage` in the message `ts` (drawn once its row is); `flash` then plays it out. */
  lead(ts: string, passage: string, accent: string) {
    this.#flashes++;
    this.#flashed = ts;
    this.#mark = new TextMark(passage, accent);
    this.#changed();
  }

  async playFlash() {
    const mine = this.#flashes;
    const m = this.#mark;
    const off = this.#marking.subscribe(() => { if (m) m.level = this.#marking.value; this.#changed(); });
    try {
      this.flash.snapTo(0);
      this.#marking.snapTo(0);
      await Promise.all([
        this.flash.run(1700, keyframes([[0, 0, Ease.Out], [FLASH_IN_MS, 1], [900, 1, Ease.Standard], [1700, 0]])),
        this.#marking.run(2400, keyframes([[0, 0, Ease.Out], [FLASH_IN_MS, MARK_LEVEL], [1400, MARK_LEVEL, Ease.Standard], [2400, 0]])),
      ]);
    } finally {
      off();
      if (this.#flashes === mine) { this.#flashed = null; this.#mark = null; this.#changed(); }
    }
  }
}

/** What a part reads of the chat's motion, drawn again as it changes (its pose, what flashes). */
export function useChatMotion(): ChatMotion | null {
  const motion = useContext(LocalChatMotion);
  useSyncExternalStore((l) => (motion ? motion.subscribe(l) : () => undefined), () => motion?.version ?? 0);
  return motion;
}

/** The accent's ground (web --accent-bg in a chat: oklch(96.5% .025 45), dark oklch(30% .05 40)). */
export function accentBg(): string {
  const C = useC();
  return C.dark ? "#43251A" : "#FFEFE6";
}

/** How long a jump's highlight takes to come in, and how strong a quote's passage is marked. */
const FLASH_IN_MS = 160;
const MARK_LEVEL = 0.24;

/** Whether the message `ts` flashes whole now (a jump led to it, and no passage of it is marked). */
export function flashing(motion: ChatMotion, ts: string | null | undefined): boolean {
  return ts != null && motion.flashed === ts && motion.mark?.found !== true;
}

/** How far a flashing message's ground reaches past it: within the list's 14dp padding, and half the 20dp gap. */
const FLASH_BLEED = { width: 10, height: 8 };

/**
 * A message a jump led to flashing: the accent's ground round it, reaching FLASH_BLEED past its words on each side
 * (into the list's padding and the gap between messages) so they sit inside it rather than against its edge.
 */
export function Flashed({ motion, ts, color, style, children }: { motion: ChatMotion | null; ts: string | null | undefined; color: string; style?: StyleProp<ViewStyle>; children?: ReactNode }) {
  const lit = useAnimatable(motion && ts != null ? motion.flash : null);
  const on = motion != null && flashing(motion, ts);
  return (
    <View style={style}>
      {on && (
        <Smooth
          radius={14}
          pointerEvents="none"
          style={{ position: "absolute", left: -FLASH_BLEED.width, right: -FLASH_BLEED.width, top: -FLASH_BLEED.height, bottom: -FLASH_BLEED.height, backgroundColor: withAlpha(color, lit) }}
        />
      )}
      {children}
    </View>
  );
}

function lerp(a: { x: number; y: number }, b: { x: number; y: number }, t: number) {
  return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t };
}

/** The hop: how high over the higher of its two ends, and the share of its time spent going up. */
const HOP = 34;
const RISE = 0.42;
/** The same agent's next message, waiting as one comes out: the avatar drops on to it, no hop (how long). */
const DROP_MS = 280;

/** What is left, at `s` seconds, of a spring let go from 1 (stiffness 520, damping 14, mass 1: under-damped). */
function settle(s: number): number {
  const w0 = Math.sqrt(520);
  const z = 14 / (2 * w0);
  const wd = w0 * Math.sqrt(1 - z * z);
  return Math.exp(-z * w0 * s) * (Math.cos(wd * s) + ((z * w0) / wd) * Math.sin(wd * s));
}

function smooth(t: number) { return t * t * (3 - 2 * t); }

/**
 * A message coming out of its avatar (web emitOut, 380ms): scale .35 → 1 from 12dp 12dp, unrolling from the top (its
 * top share shown, the web's clip-path inset from the bottom), both --ease-out over the whole; its opacity 0 → 1 by
 * 35% (that stretch eased on its own), as CSS keyframes ease each stretch.
 */
export function EmitOut({ motion, seq, style, children }: { motion: ChatMotion | null; seq: number; style?: StyleProp<ViewStyle>; children?: ReactNode }) {
  const t = useAnimatable(motion && motion.emitting(seq) ? motion.clock : null);
  // Its own height as laid out: the clip is drawn, not laid out (what is under it does not move as it unrolls).
  const [natural, setNatural] = useState<number | null>(null);
  const on = motion != null && motion.emitting(seq);
  const e = eased(Ease.Out)(t);
  const corner = 12;
  // One tree whether it comes out or not: what is in it is not drawn anew as it lands.
  return (
    <View style={[style, on && natural != null ? { height: natural } : null]}>
      <View
        style={on ? {
          position: natural != null ? "absolute" : "relative", left: 0, right: 0, top: 0,
          height: natural != null ? natural * e : undefined,
          overflow: "hidden",
          transformOrigin: [corner, corner, 0],
          transform: [{ scale: 0.35 + 0.65 * e }],
          opacity: t < 0.35 ? eased(Ease.Out)(t / 0.35) : 1,
        } : null}
      >
        <View onLayout={(ev) => setNatural(ev.nativeEvent.layout.height)}>{children}</View>
      </View>
    </View>
  );
}

/** Ticks while `on`: what reads a clock that does not say it moved (Date.now) is drawn again each `ms`. */
export function useTicking(on: boolean, ms: number) {
  const [n, setN] = useState(0);
  useEffect(() => {
    if (!on) return;
    const id = setInterval(() => setN((x) => x + 1), ms);
    return () => clearInterval(id);
  }, [on, ms]);
  return n;
}
