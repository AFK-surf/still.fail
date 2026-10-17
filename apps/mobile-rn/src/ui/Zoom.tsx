// Zooming and panning a picture in a stage (an image, a video's frames), as web/src/FilePreview.tsx useZoom: fitted
// to the stage with a margin, pinched around the fingers, panned when larger than the stage, a double tap zooms in
// (or back to fitted). Fitted, one finger moving sideways is a `Swipe`'s: to the picture before or after.
import { useMemo, useRef, useSyncExternalStore, type ReactNode } from "react";
import { View, type StyleProp, type ViewStyle } from "react-native";
import { Gesture, GestureDetector, type TouchData } from "react-native-gesture-handler";
import { Easing } from "react-native-reanimated";
import type { Offset, Rect } from "./Pick";

export const MAX_SCALE = 16;

/** A size in whole units (Compose's IntSize). */
export interface IntSize { width: number; height: number }

/** The glide's curve, (.16, 1, .3, 1), as a function of JS (Reanimated keeps its curves as factories). */
const GLIDE = (() => {
  const e = Easing.bezier(0.16, 1, 0.3, 1) as unknown as { factory?: () => (t: number) => number } | ((t: number) => number);
  return typeof e === "function" ? e : e.factory!();
})();

/**
 * Where a picture of `natural` size (its pixels) shows in a stage of `box`. `scale` is the web's: dp per picture
 * pixel (1 = "100%"); `x`, `y` move its centre from the stage's. Here the stage is measured in dp, so `density` is 1
 * (the Android app measures it in px, density px to the dp); what draws the picture follows it (useZoom).
 * `scope` where the Android app takes a CoroutineScope to glide in: given (anything), it glides; none, it jumps.
 */
export class ZoomState {
  #natural: IntSize | null = null;
  #box: IntSize = { width: 0, height: 0 };
  #scale = 1;
  #x = 0;
  #y = 0;
  #fitted = true;
  #animation: number | null = null;
  #version = 0;
  readonly #listeners = new Set<() => void>();

  constructor(private readonly density = 1) {}

  subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  get version() { return this.#version; }
  #changed() { this.#version++; for (const l of [...this.#listeners]) l(); }

  get natural() { return this.#natural; }
  get box() { return this.#box; }
  get scale() { return this.#scale; }
  get x() { return this.#x; }
  get y() { return this.#y; }

  get #margin() { return (this.#box.width < 640 * this.density ? 12 : 32) * this.density; }

  /** Fitted: the whole picture within the stage, never enlarged. */
  get fit(): number {
    const n = this.#natural;
    if (!n) return 1;
    if (this.#box.width === 0 || this.#box.height === 0 || n.width === 0 || n.height === 0) return 1;
    return Math.min(1, Math.min((this.#box.width - 2 * this.#margin) / (n.width * this.density), (this.#box.height - 2 * this.#margin) / (n.height * this.density)));
  }
  get minScale() { return Math.min(this.fit, 1) / 2; }
  get zoomed() { return this.#scale > this.fit * 1.01; }
  /** Larger than the stage: a drag pans it. */
  get larger() {
    const n = this.#natural;
    return n != null && (n.width * this.#scale * this.density > this.#box.width + 1 || n.height * this.#scale * this.density > this.#box.height + 1);
  }
  /** Stage units per picture pixel. */
  get k() { return this.#scale * this.density; }

  fitNatural(size: IntSize | null) {
    if (size === this.#natural || (size && this.#natural && size.width === this.#natural.width && size.height === this.#natural.height)) return;
    this.#natural = size;
    if (this.#fitted) { this.#scale = this.fit; this.#x = 0; this.#y = 0; } else this.#clampNow();
    this.#changed();
  }

  fitBox(size: IntSize) {
    if (size.width === this.#box.width && size.height === this.#box.height) return;
    this.#box = size;
    if (this.#fitted) { this.#scale = this.fit; this.#x = 0; this.#y = 0; } else this.#clampNow();
    this.#changed();
  }

  #clampNow() {
    const n = this.#natural;
    if (!n) return;
    this.#scale = Math.max(this.minScale, Math.min(MAX_SCALE, this.#scale));
    const spareX = Math.max(0, (n.width * this.k - this.#box.width) / 2);
    const spareY = Math.max(0, (n.height * this.k - this.#box.height) / 2);
    this.#x = Math.max(-spareX, Math.min(spareX, this.#x));
    this.#y = Math.max(-spareY, Math.min(spareY, this.#y));
  }

  /** The picture's place on the stage. */
  rect(): Rect | null {
    const n = this.#natural;
    if (!n) return null;
    const w = n.width * this.k;
    const h = n.height * this.k;
    const left = this.#box.width / 2 + this.#x - w / 2;
    const top = this.#box.height / 2 + this.#y - h / 2;
    return { left, top, right: left + w, bottom: top + h };
  }

  /** A point on the stage in the picture's own pixels. */
  toPicture(p: Offset): Offset {
    const r = this.rect();
    if (!r) return { x: 0, y: 0 };
    return { x: (p.x - r.left) / this.k, y: (p.y - r.top) / this.k };
  }

  #cancel() {
    if (this.#animation != null) { cancelAnimationFrame(this.#animation); this.#animation = null; }
  }

  /** By `zoom` around `centroid` (on the stage), and moved by `pan`. */
  transform(centroid: Offset, zoom: number, pan: Offset) {
    this.#cancel();
    const next = Math.max(this.minScale, Math.min(MAX_SCALE, this.#scale * zoom));
    const f = next / this.#scale;
    const px = centroid.x - this.#box.width / 2;
    const py = centroid.y - this.#box.height / 2;
    this.#fitted = false;
    this.#scale = next;
    this.#x = px - (px - this.#x) * f + pan.x;
    this.#y = py - (py - this.#y) * f + pan.y;
    this.#clampNow();
    this.#changed();
  }

  /** To `target`, the picture's point under `at` (on the stage; null: its centre) staying put. */
  zoomTo(target: number, at: Offset | null = null, scope: unknown = null) {
    const next = Math.max(this.minScale, Math.min(MAX_SCALE, target));
    const px = (at?.x ?? this.#box.width / 2) - this.#box.width / 2;
    const py = (at?.y ?? this.#box.height / 2) - this.#box.height / 2;
    const f = next / this.#scale;
    let tx = px - (px - this.#x) * f;
    let ty = py - (py - this.#y) * f;
    const n = this.#natural;
    if (n) {
      const sx = Math.max(0, (n.width * next * this.density - this.#box.width) / 2);
      const sy = Math.max(0, (n.height * next * this.density - this.#box.height) / 2);
      tx = Math.max(-sx, Math.min(sx, tx));
      ty = Math.max(-sy, Math.min(sy, ty));
    }
    this.#fitted = false;
    this.#glide(next, tx, ty, scope);
  }

  reset(scope: unknown = null) {
    this.#glide(this.fit, 0, 0, scope);
    this.#fitted = true;
  }

  #glide(toScale: number, toX: number, toY: number, scope: unknown) {
    this.#cancel();
    if (scope == null) { this.#scale = toScale; this.#x = toX; this.#y = toY; this.#changed(); return; }
    const from = [this.#scale, this.#x, this.#y] as const;
    let start = -1;
    const frame = (now: number) => {
      if (start < 0) start = now;
      const t = GLIDE(Math.min(1, (now - start) / 260));
      this.#scale = from[0] + (toScale - from[0]) * t;
      this.#x = from[1] + (toX - from[1]) * t;
      this.#y = from[2] + (toY - from[2]) * t;
      this.#changed();
      this.#animation = now - start < 260 ? requestAnimationFrame(frame) : null;
    };
    this.#animation = requestAnimationFrame(frame);
  }

  /** A double tap: fitted, in to 2.5× the fitted size (at least 100%) around it; zoomed, back to fitted. */
  doubleTap(at: Offset, scope: unknown) {
    if (this.zoomed) this.reset(scope);
    else this.zoomTo(Math.max(this.fit * 2.5, 1), at, scope);
  }
}

/** The zoom's state, drawn again as it moves (what draws the picture reads scale, x and y). */
export function useZoom(state: ZoomState): ZoomState {
  useSyncExternalStore(state.subscribe, () => state.version);
  return state;
}

/** A finger drawing on the picture (marks): its own while it is the only one; a second one takes it back to pinch. */
export interface Strokes {
  down(at: Offset): void;
  move(at: Offset): void;
  up(): void;
  /** A second finger came: what the first was doing is put back. */
  cancel(): void;
}

/** One finger moving a fitted picture sideways: where it has got to (from where it went down), then where and how fast (per second) it was let go. */
export interface Swipe {
  drag(dx: number): void;
  end(dx: number, vx: number): void;
}

/** Android's touch slop (ViewConfiguration: 8dp). */
const TOUCH_SLOP = 8;

/** A finger's speed across, from its last 100ms (Compose's VelocityTracker, near enough). */
class VelocityTracker {
  readonly #points: { t: number; x: number }[] = [];
  addPosition(t: number, x: number) {
    this.#points.push({ t, x });
    while (this.#points.length > 2 && t - this.#points[0]!.t > 100) this.#points.shift();
  }
  velocity(): number {
    const p = this.#points;
    if (p.length < 2) return 0;
    const dt = p[p.length - 1]!.t - p[0]!.t;
    return dt > 0 ? ((p[p.length - 1]!.x - p[0]!.x) / dt) * 1000 : 0;
  }
}

const centroidOf = (ts: { x: number; y: number }[]) => ({ x: ts.reduce((a, t) => a + t.x, 0) / ts.length, y: ts.reduce((a, t) => a + t.y, 0) / ts.length });

/**
 * The stage's gestures: pinch and pan; a tap (`onTap`) and a double tap; one finger sideways when fitted (`swipe`).
 * With `strokes`, one finger is theirs and double taps are not heard. `swipe` and `strokes` are to stay the same objects
 * while a gesture may be going on (a new one starts the handling over, losing the gesture). Modifier.zoomable there: the
 * stage itself here, what it shows its children.
 */
export function Zoomable({ state, onTap, swipe, strokes, style, children }: { state: ZoomState; scope?: unknown; onTap: () => void; swipe?: Swipe | null; strokes?: Strokes | null; style?: StyleProp<ViewStyle>; children?: ReactNode }) {
  const tap = useRef(onTap);
  tap.current = onTap;
  const gesture = useMemo(() => {
    type G = {
      down: number; start: Offset; multi: boolean; past: boolean; drawing: boolean; pan: Offset; zoom: number;
      last: Offset; swiped: boolean; tracker: VelocityTracker; prev: Map<number, Offset>;
    };
    let g: G | null = null;
    const manual = Gesture.Manual()
      .runOnJS(true)
      .onTouchesDown((e, m) => {
        if (g == null) {
          const d = e.changedTouches[0]!;
          g = { down: d.id, start: { x: d.x, y: d.y }, multi: false, past: false, drawing: false, pan: { x: 0, y: 0 }, zoom: 1, last: { x: d.x, y: d.y }, swiped: false, tracker: new VelocityTracker(), prev: new Map() };
          g.tracker.addPosition(e.eventType ? Date.now() : Date.now(), d.x);
          if (strokes) { strokes.down(g.start); g.drawing = true; m.activate(); }
        }
        for (const t of e.allTouches) g.prev.set(t.id, { x: t.x, y: t.y });
        const pressed = e.allTouches;
        if (pressed.length > 1 && !g.multi) {
          g.multi = true;
          if (g.drawing) { strokes?.cancel(); g.drawing = false; }
          // A second finger pinches: the swipe goes back.
          if (g.swiped) { swipe?.end(0, 0); g.swiped = false; }
        }
      })
      .onTouchesMove((e, m) => {
        if (!g) return;
        const pressed: TouchData[] = e.allTouches;
        const finger = pressed.find((t) => t.id === g!.down);
        if (finger) g.last = { x: finger.x, y: finger.y };
        if (g.drawing) {
          if (finger) strokes?.move({ x: finger.x, y: finger.y });
          for (const t of pressed) g.prev.set(t.id, { x: t.x, y: t.y });
          return;
        }
        // The pinch and the pan of this move: the fingers that were down before it, their spread and their middle.
        const both = pressed.filter((t) => g!.prev.has(t.id));
        let z = 1;
        let p = { x: 0, y: 0 };
        if (both.length > 0) {
          const before = both.map((t) => g!.prev.get(t.id)!);
          const now = both.map((t) => ({ x: t.x, y: t.y }));
          const c0 = centroidOf(before);
          const c1 = centroidOf(now);
          p = { x: c1.x - c0.x, y: c1.y - c0.y };
          if (both.length > 1) {
            const s0 = before.reduce((a, q) => a + Math.hypot(q.x - c0.x, q.y - c0.y), 0) / before.length;
            const s1 = now.reduce((a, q) => a + Math.hypot(q.x - c1.x, q.y - c1.y), 0) / now.length;
            if (s0 > 0 && s1 > 0) z = s1 / s0;
          }
        }
        for (const t of pressed) g.prev.set(t.id, { x: t.x, y: t.y });
        if (!g.past) {
          g.zoom *= z;
          g.pan = { x: g.pan.x + p.x, y: g.pan.y + p.y };
          g.past = Math.abs(1 - g.zoom) * 200 > TOUCH_SLOP || Math.hypot(g.pan.x, g.pan.y) > TOUCH_SLOP;
          if (g.past) m.activate();
        }
        if (g.past) {
          // Fitted and one finger: a swipe, not a pan.
          if (!g.multi && swipe && finger && (g.swiped || (!state.zoomed && !state.larger))) {
            g.swiped = true;
            g.tracker.addPosition(Date.now(), finger.x);
            swipe.drag(finger.x - g.start.x);
          } else state.transform(centroidOf(pressed), z, p);
        }
      })
      .onTouchesUp((e, m) => {
        if (!g) return;
        for (const t of e.changedTouches) g.prev.delete(t.id);
        const up = e.changedTouches.find((t) => t.id === g!.down);
        if (up) g.last = { x: up.x, y: up.y };
        if (e.allTouches.length - e.changedTouches.length > 0 && e.numberOfTouches > 0) return;
        const done = g;
        g = null;
        if (done.drawing) strokes?.up();
        else if (done.swiped) {
          done.tracker.addPosition(Date.now(), done.last.x);
          swipe?.end(done.last.x - done.start.x, done.tracker.velocity());
        }
        m.end();
      })
      .onTouchesCancelled((_e, m) => {
        const done = g;
        g = null;
        if (done?.drawing) strokes?.up();
        else if (done?.swiped) swipe?.end(done.last.x - done.start.x, done.tracker.velocity());
        m.end();
      });
    if (strokes) return manual;
    const double = Gesture.Tap().runOnJS(true).numberOfTaps(2).onEnd((e, ok) => { if (ok) state.doubleTap({ x: e.x, y: e.y }, true); });
    const single = Gesture.Tap().runOnJS(true).onEnd((_e, ok) => { if (ok) tap.current(); });
    return Gesture.Simultaneous(Gesture.Exclusive(double, single), manual);
  }, [state, strokes, swipe]);
  return (
    <GestureDetector gesture={gesture}>
      <View collapsable={false} style={style} onLayout={(e) => state.fitBox({ width: e.nativeEvent.layout.width, height: e.nativeEvent.layout.height })}>
        {children}
      </View>
    </GestureDetector>
  );
}
