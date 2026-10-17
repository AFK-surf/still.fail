// A screen's picture zoomed on a phone, here only (never sent; as the Android app's remote/ScreenViewer.kt ViewZoom):
// `scale` over its fitted size, moved by `x`, `y` from where it sits fitted, kept within the stage (smaller than it,
// centred; larger, no gap at its edges). Where a finger drives it as a trackpad, the pointer it moves (PadPointer).

export type Box = { left: number; top: number; width: number; height: number };
export type Point = { x: number; y: number };

/** The most a screen is zoomed in, over its fitted size. */
const MAX_ZOOM = 5;

/** Where a frame of `w`×`h` fits whole in a stage of `room`, centred (letterboxed). */
export function fitIn(room: { width: number; height: number }, w: number, h: number): Box {
  if (w <= 0 || h <= 0 || room.width <= 0 || room.height <= 0) return { left: 0, top: 0, width: 0, height: 0 };
  const k = Math.min(room.width / w, room.height / h);
  const width = w * k, height = h * k;
  return { left: (room.width - width) / 2, top: (room.height - height) / 2, width, height };
}

export class Zoom {
  scale = 1;
  x = 0;
  y = 0;

  get zoomed(): boolean { return this.scale > 1.01; }

  /** Where the picture is drawn on the stage, fitted at `fit`. */
  shown(fit: Box): Box {
    return { left: fit.left + this.x, top: fit.top + this.y, width: fit.width * this.scale, height: fit.height * this.scale };
  }

  /** At `next` over `fit`, its top left at `left`, `top` on a stage of `room`, as near as its edges let it be. */
  #put(next: number, left: number, top: number, fit: Box, room: { width: number; height: number }) {
    const place = (want: number, size: number, space: number) => (size <= space ? (space - size) / 2 : Math.min(0, Math.max(space - size, want)));
    this.scale = next;
    this.x = place(left, fit.width * next, room.width) - fit.left;
    this.y = place(top, fit.height * next, room.height) - fit.top;
  }

  /** By `factor` around `focus`, and moved by `pan` (on the stage, px). */
  by(factor: number, focus: Point, pan: Point, fit: Box, room: { width: number; height: number }) {
    if (fit.width <= 0) return;
    const before = this.shown(fit);
    const next = Math.min(MAX_ZOOM, Math.max(1, this.scale * factor));
    const u = { x: (focus.x - before.left) / before.width, y: (focus.y - before.top) / before.height };
    this.#put(next, focus.x - u.x * fit.width * next + pan.x, focus.y - u.y * fit.height * next + pan.y, fit, room);
  }

  pan(d: Point, fit: Box, room: { width: number; height: number }) {
    this.by(1, { x: fit.left + fit.width / 2, y: fit.top + fit.height / 2 }, d, fit, room);
  }

  /** `at` (0..1 of the picture) brought `margin` px within the stage's edges, the picture moved as little as it takes. */
  keep(at: Point, margin: number, fit: Box, room: { width: number; height: number }) {
    const s = this.shown(fit);
    const off = (v: number, space: number) => (space < 2 * margin ? space / 2 - v : v < margin ? margin - v : v > space - margin ? space - margin - v : 0);
    const d = { x: off(s.left + at.x * s.width, room.width), y: off(s.top + at.y * s.height, room.height) };
    if (d.x || d.y) this.pan(d, fit, room);
  }

  reset() { this.scale = 1; this.x = 0; this.y = 0; }
}

/** How long after the finger moved the pointer the station's word on it is taken again (its echo of the moves is behind). */
export const PAD_SETTLE_MS = 600;

/**
 * Where the pointer is as the trackpad moves it (0..1 of the picture), ahead of the station saying so; where the
 * station says it is once the finger has been still a moment.
 */
export class PadPointer {
  x = 0.5;
  y = 0.5;
  #movedAt = -Infinity;

  by(dx: number, dy: number, now: number) {
    this.x = Math.min(1, Math.max(0, this.x + dx));
    this.y = Math.min(1, Math.max(0, this.y + dy));
    this.#movedAt = now;
  }

  follow(cursor: Point | undefined, now: number) {
    if (!cursor || now - this.#movedAt < PAD_SETTLE_MS) return;
    this.x = Math.min(1, Math.max(0, cursor.x));
    this.y = Math.min(1, Math.max(0, cursor.y));
  }
}

/**
 * How far the pointer goes for a finger's move of 1 px, by how fast it moves (px per ms): slowly, less than the finger,
 * to land on something small; fast, further, to cross the screen in a stroke.
 */
export function padGain(pxPerMs: number): number {
  return 0.55 + 1.6 * Math.min(1, Math.max(0, (pxPerMs - 0.1) / 1.4));
}
