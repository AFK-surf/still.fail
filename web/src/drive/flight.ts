// Files dropped on a chat fly into its composer (ChatPage.tsx useChatDrop, Chat.tsx): what was shown over the chat while
// they were dragged (each one's mark, FileTile) takes off from where it was as the drop lands, and each card the drop
// makes in the composer, drawn there at once, takes one: a copy of the mark goes from where it took off to the card's
// own mark, which shows when it is there (the card is in its place all along; only the copy moves).
import { useLayoutEffect, type RefObject } from "react";
import { EASE_OUT_CSS, reducedMotion } from "../motion.ts";

type Flight = { from: DOMRect; node: Element; source: Element };
/** What took off, in the drop's order, until the cards it made claim it (or it is too late for them to). */
let waiting: Flight[] = [];
let at = 0;
/** A drop's cards are drawn the frame after it: what no card took by then lands nowhere. */
const WITHIN_MS = 1000;
const FLIGHT_MS = 420;

/** The marks shown over the chat take off: each where it is now. */
export function takeOff(marks: Element[]): void {
  // Where each is, untilted: its box as laid out, not the one its tilt takes.
  waiting = reducedMotion() ? [] : marks.map((node) => {
    const box = node.getBoundingClientRect();
    const w = (node as HTMLElement).clientWidth || box.width, h = (node as HTMLElement).clientHeight || box.height;
    return { from: new DOMRect(box.left + (box.width - w) / 2, box.top + (box.height - h) / 2, w, h), node: node.cloneNode(true) as Element, source: node };
  });
  at = performance.now();
}

/** A card the drop made: its mark (`mark`) is where the next one that took off lands. */
export function useLanding(mark: RefObject<Element | null>): void {
  useLayoutEffect(() => {
    const el = mark.current as (HTMLElement | SVGElement) | null;
    if (!el || !waiting.length || performance.now() - at > WITHIN_MS) return;
    const flight = waiting.shift()!;
    const to = el.getBoundingClientRect();
    if (!to.width || !to.height) return;
    const copy = flight.node as HTMLElement | SVGElement;
    Object.assign(copy.style, {
      position: "fixed", left: `${flight.from.left}px`, top: `${flight.from.top}px`, width: `${flight.from.width}px`, height: `${flight.from.height}px`,
      margin: "0", zIndex: "1000", pointerEvents: "none", transformOrigin: "0 0",
    });
    document.body.appendChild(copy);
    el.style.opacity = "0";
    const dx = to.left - flight.from.left, dy = to.top - flight.from.top;
    const sx = to.width / flight.from.width, sy = to.height / flight.from.height;
    // Tilted over the chat (as a stack), straight on its card.
    const tilt = getComputedStyle(flight.source).rotate;
    const run = copy.animate([
      { transform: "none", rotate: tilt === "none" ? "0deg" : tilt },
      { transform: `translate(${dx}px, ${dy}px) scale(${sx}, ${sy})`, rotate: "0deg" },
    ], { duration: FLIGHT_MS, easing: EASE_OUT_CSS, fill: "forwards" });
    const land = () => { copy.remove(); el.style.opacity = ""; };
    run.onfinish = land;
    run.oncancel = land;
    return () => { if (copy.isConnected) run.cancel(); };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
}
