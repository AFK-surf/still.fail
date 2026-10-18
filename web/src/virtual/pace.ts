// The one clock of a list's motion (docs/list-motion.md): everything that moves what shows in it goes by one law
// (@stillfail/ui motion.ts PACE_*), stepped here, in one frame loop, so that however many things change at once, what
// the reader sees is one motion whose speed stays within the law's bounds and never jumps.
//
// The list itself takes every change at once: the pane goes straight to where its anchor says (model.ts), rows stand
// where they are laid out. What is drawn is kept from jumping here: in each frame, how far each row has moved on screen
// for any reason but the reader's own scroll (a message come at the end and the pane gone down to it, the agent's
// activity making way, something closing above) is taken back by drawing the row that far from where it is laid out
// (its CSS `translate`, apart from the `transform` its own motions use), and that distance goes to nothing by the law.
// Every row moved in the same frame goes by the same change (`Wave`: one rate, one start), so rows moved together stay
// together; changes under way add up, each going on from where it is.
//
// What changes size in a row by the law (settling.tsx) joins the frame's change too (`paceWith`): its height and the
// rows around it go together, from the same frame at the same rate, and neither is ever ahead of the other. Rows below
// it that it moves are not moved by it twice (model.ts `closedBefore`).
//
// A row newly made (a message come, the agent's line, a row the pane needs to draw what is held over its edge) is
// drawn as far off as the row before it is (or, the first, the row after it): it comes along with them.
//
// Not glided: what the reader does (their scroll moves what shows with their hand), a list opening or a jump to an item,
// the pane's size changing (everything laid out anew), and what the list takes at once by its nature (a history caught
// up on).
import { paceLeft, paceRate } from "@stillfail/ui/motion.ts";
import type { Virtual } from "./model.ts";

/** One change, set off in one frame: what it moves goes by it together. Starts in the frame after it was made. */
type Wave = { stamp: number; by: number; rate: number; at: number | null };
/** A row's share of a change: how far it was moved by it. */
type Share = { wave: Wave; by: number };
type Row = { el: HTMLElement; y: number; closed: number; shares: Share[]; drawn: number };
type Mover = { wave: Wave; from: number; to: number; set: (value: number) => void; done: () => void };

/** How the list takes what changes now: drawn going there (`glide`), there at once (`once`), or everything where it
 *  is laid out from now (`anew`: a jump, the pane resized, the page hidden). */
export type Take = "glide" | "once" | "anew";

/** How long after the pane's width changed its rows may still come to stand as they wrap now. */
const REWRAP_MS = 200;

const frameTime = () => (document.timeline.currentTime as number | null) ?? performance.now();
const leftOf = (w: Wave, now: number) => (w.at === null ? 1 : paceLeft(w.rate, now - w.at));

const paces = new WeakMap<HTMLElement, Pace>();
/** Told of each frame a list's pane draws its rows off where they are laid out (its scrollbar follows what shows). */
export const paceFrames = new Set<(pane: HTMLElement) => void>();
/** How far what shows in `pane` is drawn below where it is laid out (its rows' offset at its top): as if the pane were
 *  scrolled that much less. */
export function drawnLag(pane: Element): number { return paces.get(pane as HTMLElement)?.lag ?? 0; }

export class Pace {
  private readonly rows = new Map<string, Row>();
  private readonly movers = new Set<Mover>();
  private wave: Wave | null = null;
  private frame = 0;
  /** The time of the frame last drawn. */
  private last = frameTime();
  /** How far the reader scrolled since the rows were last seen; where the pane was then. */
  private scrolled = 0;
  private written = Number.NaN;
  private width = 0;
  private rewrapped = Number.NEGATIVE_INFINITY;
  /** How far rows are drawn off where they are laid out, at most, each way: the list makes rows that far past the pane. */
  private reach = { up: 0, down: 0 };
  /** How far the row at the pane's top is drawn below where it is laid out. */
  lag = 0;

  constructor(private readonly pane: HTMLElement, private readonly model: Virtual, private readonly remake: () => void) {
    paces.set(pane, this);
  }

  /** The reader scrolled the pane by `by`: what shows moves with their hand. */
  scrolledBy(by: number): void { this.scrolled += by; }

  /**
   * The list as it stands now, the pane at `written` (where the browser has it, which may fall short of the model's):
   * each row's move since it was last seen is taken back, to go by the law (or not, by `take`).
   */
  seen(written: number, take: Take): void {
    const { model } = this;
    const layout = model.layout();
    // What the browser left the pane short of, every row shows that much further down.
    const short = layout.scrollTop - written;
    // A pane of another width lays every row out anew (they wrap otherwise): what moves by it is not a move to draw.
    // Only taller or shorter (the composer below it growing or giving up room), what it moves is drawn going.
    // (Its first width, as its pane reports it, is not one of those.)
    if (model.paneWidth !== this.width) {
      if (this.width > 0) { take = "anew"; this.rewrapped = performance.now(); }
      this.width = model.paneWidth;
    }
    if (document.visibilityState !== "visible" || performance.now() - this.rewrapped < REWRAP_MS) take = "anew";
    // Motion reduced: what moves is there at once (not drawn where it was for a frame first).
    if (take === "glide" && !Number.isFinite(paceRate(0))) take = "once";
    const reader = this.scrolled;
    this.scrolled = 0;
    // How far the pane went other than by the reader's hand.
    const went = Number.isNaN(this.written) ? 0 : written - this.written - reader;
    this.written = written;
    if (take === "anew") this.rest();
    const shown: [string, HTMLElement][] = [];
    for (const el of this.pane.children) if (el instanceof HTMLElement && el.dataset.vk !== undefined) shown.push([el.dataset.vk, el]);
    const keys = new Set(shown.map(([key]) => key));
    for (const key of this.rows.keys()) if (!keys.has(key)) this.rows.delete(key);
    // Each row's move on screen, the reader's scroll and what closes above it (it goes along with that) aside.
    const most = model.paneHeight || window.innerHeight;
    const fresh: [number, string, HTMLElement, number, number][] = [];
    let wave: Wave | null = null;
    shown.forEach(([key, el], i) => {
      const off = model.offsetOf(key);
      if (off === undefined) return;
      const y = off + short;
      const closed = model.closedBefore(key);
      const row = this.rows.get(key);
      if (!row) { fresh.push([i, key, el, y, closed]); return; }
      if (row.el !== el) { row.el = el; row.drawn = Number.NaN; }
      const moved = y - row.y + (closed - row.closed) + reader;
      row.y = y;
      row.closed = closed;
      if (take !== "glide" || Math.abs(moved) < 0.5) return;
      // Never drawn further off than a pane's height: from further, it comes in from just past the pane's edge.
      const by = -Math.sign(moved) * Math.min(Math.abs(moved), most);
      wave ??= this.waveNow();
      wave.by = Math.max(wave.by, Math.abs(by));
      row.shares.push({ wave, by });
    });
    // New rows come along with the row before them (the first, with the one after it). None of them there before (the
    // pane gone further than it had rows made: to the end from far up), they come in from past the pane's edge, as far
    // as the pane went.
    for (const [i, key, el, y, closed] of fresh) {
      let near: Row | undefined;
      for (let j = i - 1; j >= 0 && !near; j--) near = this.rows.get(shown[j]![0]);
      for (let j = i + 1; j < shown.length && !near; j++) near = this.rows.get(shown[j]![0]);
      let shares: Share[] = [];
      if (take === "glide" && near) shares = near.shares.map((s) => ({ ...s }));
      else if (take === "glide" && Math.abs(went) >= 0.5) {
        const by = Math.sign(went) * Math.min(Math.abs(went), most);
        wave ??= this.waveNow();
        wave.by = Math.max(wave.by, Math.abs(by));
        shares = [{ wave, by }];
      }
      this.rows.set(key, { el, y, closed, shares, drawn: Number.NaN });
    }
    this.draw(this.last);
  }

  /**
   * A value going from `from` to `to` (a box's height closing) with what else changes in this frame: by the same law,
   * from the same frame, at the same rate. `set` draws it; `finished` once there (or cancelled where it is).
   */
  with(from: number, to: number, set: (value: number) => void): { finished: Promise<void>; cancel(): void } {
    if (!Number.isFinite(paceRate(0))) { set(to); return { finished: Promise.resolve(), cancel() {} }; }
    const wave = this.waveNow();
    wave.by = Math.max(wave.by, Math.abs(from - to));
    let done: () => void = () => {};
    const finished = new Promise<void>((resolve) => { done = resolve; });
    const mover: Mover = { wave, from, to, set, done };
    this.movers.add(mover);
    set(from);
    this.run();
    return { finished, cancel: () => { this.movers.delete(mover); } };
  }

  /** How far `row` is drawn from where it is laid out (what of a move it is still taking back). */
  static drawnOff(row: Element | null | undefined): number {
    const t = row instanceof HTMLElement ? row.style.translate : "";
    return t ? parseFloat(t.split(" ")[1] ?? "0") || 0 : 0;
  }

  /** The list is gone: nothing drawn off any longer. */
  stop(): void {
    cancelAnimationFrame(this.frame);
    this.frame = 0;
    this.rest();
    for (const m of this.movers) { m.set(m.to); m.done(); }
    this.movers.clear();
    paces.delete(this.pane);
  }

  /** This frame's change, made if none is yet (or the last has set out already). */
  private waveNow(): Wave {
    const stamp = frameTime();
    if (!this.wave || this.wave.at !== null || this.wave.stamp !== stamp) this.wave = { stamp, by: 0, rate: 0, at: null };
    return this.wave;
  }

  /** Everything where it is laid out. */
  private rest(): void {
    for (const row of this.rows.values()) row.shares = [];
    for (const m of this.movers) { m.set(m.to); m.done(); }
    this.movers.clear();
    this.draw(this.last);
  }

  /** Each row drawn where it is at `now`, what is done let go of, and the list told how far past the pane to make rows. */
  private draw(now: number): void {
    let up = 0;
    let down = 0;
    let busy = this.movers.size > 0;
    let top = Number.POSITIVE_INFINITY;
    const lag = this.lag;
    this.lag = 0;
    for (const [key, row] of this.rows) {
      let off = 0;
      if (row.shares.length) {
        row.shares = row.shares.filter((s) => { const left = leftOf(s.wave, now); off += s.by * left; return Math.abs(s.by * left) >= 0.05; });
      }
      if (row.shares.length) busy = true;
      if (Math.abs(off) < 0.05) off = 0;
      if (off !== row.drawn) {
        row.el.style.translate = off ? `0 ${off}px` : "";
        row.drawn = off;
      }
      if (row.y + (this.model.sizes.get(key)?.height ?? 0) > 0 && row.y < top) { top = row.y; this.lag = off; }
      if (off > up) up = off;
      if (-off > down) down = -off;
    }
    for (const m of this.movers) {
      const left = leftOf(m.wave, now);
      m.set(m.to + (m.from - m.to) * left);
      if (left === 0 && m.wave.at !== null) { this.movers.delete(m); m.done(); }
    }
    // Rows drawn down past the pane's top (or up past its bottom) are made: only a call for more remakes it now.
    const more = up > this.reach.up + 1 || down > this.reach.down + 1;
    this.reach = { up, down };
    this.model.reach(up, down);
    if (more) queueMicrotask(this.remake);
    if (this.lag !== lag) for (const told of paceFrames) told(this.pane);
    if (busy) this.run();
  }

  /** The frame loop, while anything is under way: changes made since the last frame set out in this one. */
  private run(): void {
    if (this.frame) return;
    const step = (now: number) => {
      this.frame = 0;
      this.last = now;
      const start = (w: Wave) => { if (w.at === null) { w.at = now; w.rate = paceRate(w.by); } };
      for (const row of this.rows.values()) for (const s of row.shares) start(s.wave);
      for (const m of this.movers) start(m.wave);
      this.draw(now);
    };
    this.frame = requestAnimationFrame(step);
  }
}

/**
 * `from` to `to` by the list's law with what else changes in the list `el` is in, from this frame (settling.tsx): see
 * `Pace.with`. Outside a list, by the law alone.
 */
export function paceWith(el: Element, from: number, to: number, set: (value: number) => void): { finished: Promise<void>; cancel(): void } {
  for (let n = el.parentElement; n; n = n.parentElement) {
    const pace = paces.get(n);
    if (pace) return pace.with(from, to, set);
  }
  const rate = paceRate(from - to);
  let at: number | null = null;
  let frame = 0;
  let done: () => void = () => {};
  const finished = new Promise<void>((resolve) => { done = resolve; });
  const step = (now: number) => {
    at ??= now;
    const left = paceLeft(rate, now - at);
    set(to + (from - to) * left);
    if (left === 0) { frame = 0; done(); }
    else frame = requestAnimationFrame(step);
  };
  set(from);
  if (!Number.isFinite(rate)) { set(to); done(); }
  else frame = requestAnimationFrame(step);
  return { finished, cancel() { cancelAnimationFrame(frame); frame = 0; } };
}
