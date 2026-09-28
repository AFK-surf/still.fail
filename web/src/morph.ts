// The composer changing shape in one motion, whatever changes it: its text (a capsule becoming a box, Chat.tsx's
// Composer) or its page (a new chat's roomy box becoming a chat's foot, dock.tsx). Both do the same: read how it shows
// just before its layout changes (`shapeOf`), then go from there to how it is laid out now (`morph`) — the box (its
// place and size, as the caller says, and its corners' size and shape) and what it holds (its text and buttons) on one
// timeline, rather than the box moving while what is in it jumps.

/** What moves with the box: its text and its buttons (not the text's unseen measure, Chat.tsx). */
const PARTS = "textarea:not([aria-hidden]), button";

/** How a box shows at a moment: where and how big, its corners, and where each part of it is (on the screen). */
export interface Shape {
  rect: DOMRect;
  /** Its corners' radius as drawn (no more than half its height: a capsule's is its ends'). */
  radius: number;
  /** Their shape (corner-shape: round, or a squircle's superellipse). */
  corner: string;
  parts: Map<Element, DOMRect>;
}

/** How `box` shows now, a move under way included (read mid-way, a change goes on from there). */
export function shapeOf(box: HTMLElement): Shape {
  const style = getComputedStyle(box);
  const rect = box.getBoundingClientRect();
  const parts = new Map<Element, DOMRect>();
  for (const part of box.querySelectorAll(PARTS)) parts.set(part, part.getBoundingClientRect());
  return { rect, radius: Math.min(parseFloat(style.borderTopLeftRadius), rect.height / 2), corner: style.getPropertyValue("corner-shape"), parts };
}

/** Each box's motion under way and who started it, so a new one stops the one before and nothing else. */
const running = new WeakMap<HTMLElement, { by: string; all: Animation[] }>();

/**
 * From `from` (read before its layout changed) to how `box` is laid out now, in `timing`; `by` says who moves it (a
 * page change, its text). `frames` are the box's own start and end (where it is and how big: its height alone, or its
 * place and width too); its corners are added. What it holds is laid out anew at once, in the box as big as it starts:
 * each part goes from where it showed to there, and on with the box. Answers the animations (to hold and let go
 * together).
 */
export function morph(box: HTMLElement, by: string, from: Shape, frames: [Keyframe, Keyframe], timing: KeyframeAnimationOptions): Animation[] {
  stop(box);
  const style = getComputedStyle(box);
  const height = box.getBoundingClientRect().height;
  const all = [box.animate([
    { ...frames[0], borderRadius: `${from.radius}px`, cornerShape: from.corner, overflow: "clip" },
    { ...frames[1], borderRadius: `${Math.min(parseFloat(style.borderTopLeftRadius), height / 2)}px`, cornerShape: style.getPropertyValue("corner-shape"), overflow: "clip" },
  ], timing)];
  // Read with the box at its start: where the new layout puts each part then.
  for (const part of box.querySelectorAll(PARTS)) {
    const was = from.parts.get(part);
    if (!was) continue;
    const now = part.getBoundingClientRect();
    const x = was.left - now.left, y = was.top - now.top;
    if (Math.abs(x) < 0.5 && Math.abs(y) < 0.5) continue;
    all.push(part.animate([{ transform: `translate(${x}px, ${y}px)` }, { transform: "none" }], timing));
  }
  running.set(box, { by, all });
  void all[0]!.finished.then(() => { if (running.get(box)?.all === all) running.delete(box); }, () => {});
  return all;
}

/** Stops `box`'s motion (only what `morph` started on it): it is laid out as it is, to be read or moved anew. */
export function stop(box: HTMLElement): void {
  for (const a of running.get(box)?.all ?? []) a.cancel();
  running.delete(box);
}

/** Who moves `box` now (the `by` of its motion under way), if anyone. */
export function movingBy(box: HTMLElement): string | undefined {
  return running.get(box)?.by;
}

/** The pages' easing, for a motion's timing. */
export function easeOut(): string {
  return getComputedStyle(document.documentElement).getPropertyValue("--ease-out").trim() || "ease-out";
}
