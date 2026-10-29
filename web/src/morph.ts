// The composer changing shape in one motion, whatever changes it: its text (a capsule becoming a box, Chat.tsx's
// Composer) or its page (a new chat's roomy box becoming a chat's foot, dock.tsx). Both do the same: read how it shows
// just before its layout changes (`shapeOf`), then go from there to how it is laid out now (`morph`) — the box (its
// place and size, as the caller says, and its corners' size and shape) and what it holds (its text and buttons) on one
// timeline, rather than the box moving while what is in it jumps. Both screens' composers do it as they are typed in
// (`useMorph`).

import { useLayoutEffect, useRef, type RefObject } from "react";
import { MOVE_NEAR_MS, play } from "@stillfail/ui/motion.ts";

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
const running = new WeakMap<HTMLElement, { by: string; all: Animation[]; end?: () => void }>();

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
  const radius = Math.min(parseFloat(style.borderTopLeftRadius), height / 2);
  const all = [play(box, [
    { ...frames[0], borderRadius: `${from.radius}px`, cornerShape: from.corner, overflow: "clip" },
    { ...frames[1], borderRadius: `${radius}px`, cornerShape: style.getPropertyValue("corner-shape"), overflow: "clip" },
  ], timing)];
  // Read with the box at its start: where the new layout puts each part then.
  for (const part of box.querySelectorAll(PARTS)) {
    const was = from.parts.get(part);
    if (!was) continue;
    const now = part.getBoundingClientRect();
    const x = was.left - now.left, y = was.top - now.top;
    if (Math.abs(x) < 0.5 && Math.abs(y) < 0.5) continue;
    all.push(play(part, [{ transform: `translate(${x}px, ${y}px)` }, { transform: "none" }], timing));
  }
  running.set(box, { by, all });
  void all[0]!.finished.then(() => { if (running.get(box)?.all === all) running.delete(box); }, () => {});
  return all;
}

/**
 * `box` gone to a new shape in its own place (its text changed: a capsule becoming a box, a file's card come into it):
 * it is laid out as it ends at once, and only its ground (what it is drawn on: its colour, its frost, its shadow, its
 * corners) goes from the shape it had to this one, on a layer of its own under what it holds. Nothing in it is cut by
 * that shape: its text and buttons go from where they showed to their places with the ground; what came into it anew
 * is in its place from the first (a dropped file's mark arrives there, drive/flight.ts), its place not moving.
 */
export function grow(box: HTMLElement, by: string, from: Shape, timing: KeyframeAnimationOptions): Animation[] {
  stop(box);
  const style = getComputedStyle(box);
  const now = box.getBoundingClientRect();
  const radius = Math.min(parseFloat(style.borderTopLeftRadius), now.height / 2);
  const ground = document.createElement("span");
  ground.setAttribute("aria-hidden", "true");
  Object.assign(ground.style, {
    position: "absolute", zIndex: "-1", pointerEvents: "none", inset: "0",
    background: style.background, boxShadow: style.boxShadow, backdropFilter: style.backdropFilter,
    border: style.border, cornerShape: style.getPropertyValue("corner-shape"),
    // At rest (its motion over, before it is taken away) it is the box's ground as it ends.
    borderRadius: `${radius}px`,
  });
  // Its ground drawn by the layer meanwhile, not by the box: the box's own shows nothing.
  const own = { background: box.style.background, boxShadow: box.style.boxShadow, backdropFilter: box.style.backdropFilter, borderColor: box.style.borderColor, isolation: box.style.isolation };
  Object.assign(box.style, { background: "transparent", boxShadow: "none", backdropFilter: "none", borderColor: "transparent", isolation: "isolate" });
  box.prepend(ground);
  const was = from.rect;
  const inset = `${was.top - now.top}px ${now.right - was.right}px ${now.bottom - was.bottom}px ${was.left - now.left}px`;
  const all = [play(ground, [
    { inset, borderRadius: `${from.radius}px` },
    { inset: "0px", borderRadius: `${radius}px` },
  ], timing)];
  for (const part of box.querySelectorAll(PARTS)) {
    const at = from.parts.get(part);
    if (!at) continue;
    const to = part.getBoundingClientRect();
    const x = at.left - to.left, y = at.top - to.top;
    if (Math.abs(x) < 0.5 && Math.abs(y) < 0.5) continue;
    all.push(play(part, [{ transform: `translate(${x}px, ${y}px)` }, { transform: "none" }], timing));
  }
  // Its ground back on the box, the layer gone: when it is there, or at once when it is stopped (a new shape read from
  // the box as it is drawn, not from the box the layer draws for).
  let ended = false;
  const end = () => {
    if (ended) return;
    ended = true;
    ground.remove();
    Object.assign(box.style, own);
  };
  running.set(box, { by, all, end });
  void all[0]!.finished.then(() => { end(); if (running.get(box)?.all === all) running.delete(box); }, () => {});
  return all;
}

/** Stops `box`'s motion (only what `morph` started on it): it is laid out as it is, to be read or moved anew. */
export function stop(box: HTMLElement): void {
  const was = running.get(box);
  for (const a of was?.all ?? []) a.cancel();
  was?.end?.();
  running.delete(box);
}

/** When `box`'s motion under way ends (done or stopped), if it has one. */
export function settling(box: HTMLElement): Promise<unknown> | null {
  return running.get(box)?.all[0]?.finished ?? null;
}

/** Who moves `box` now (the `by` of its motion under way), if anyone. */
export function movingBy(box: HTMLElement): string | undefined {
  return running.get(box)?.by;
}

/** The pages' easing, for a motion's timing. */
export function easeOut(): string {
  return getComputedStyle(document.documentElement).getPropertyValue("--ease-out").trim() || "ease-out";
}

/** The pages' curve for a move (--ease-move: a shape changed, the composer going to another page). */
export function easeMove(): string {
  return getComputedStyle(document.documentElement).getPropertyValue("--ease-move").trim() || "ease-out";
}

/**
 * `box` going to its new shape whenever what it is laid out by (`laidOut`: its text, files…) changes, in one motion: how
 * it shows is read in the render that changes it (the page still shows what was), and it goes from there once that is
 * laid out. Laid out for another page (`page` changing: a new chat's roomy box ⇄ a chat's foot), the page's change
 * moves it (dock.tsx), not this; nor does this cut into that move.
 */
export function useMorph(box: RefObject<HTMLElement | null>, laidOut: string, page: unknown = null): void {
  const shown = useRef({ laidOut, page });
  const from = useRef<Shape | null>(null);
  if (box.current && shown.current.laidOut !== laidOut && !from.current) from.current = shapeOf(box.current);
  useLayoutEffect(() => {
    const el = box.current, was = from.current;
    const paged = shown.current.page !== page;
    from.current = null;
    shown.current = { laidOut, page };
    if (!el || !was || el.hasAttribute("data-send-held") || paged || movingBy(el) === "page") return;
    stop(el);
    const height = el.getBoundingClientRect().height;
    // Its size unchanged (a letter more on the same line), nothing moves.
    if (Math.abs(height - was.rect.height) < 0.5 && was.corner === getComputedStyle(el).getPropertyValue("corner-shape")) return;
    grow(el, "text", was, { duration: MOVE_NEAR_MS, easing: easeMove() });
  }, [laidOut, page]); // eslint-disable-line react-hooks/exhaustive-deps
}
