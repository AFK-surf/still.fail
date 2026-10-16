// Files dropped on a chat go into its composer (ChatPage.tsx useChatDrop, Chat.tsx), each card's mark brought there
// from where the file was shown over the chat, by the page's rule for motion: the card is drawn where it ends, at once,
// and its mark is moved back to where the dropped one was shown (in the same frame that one goes), then let go to its
// own place, which does not move meanwhile. The frost over the chat fades first; the marks go once it is half gone.
import { useLayoutEffect, type RefObject } from "react";
import { reducedMotion } from "../motion.ts";

/** Where a dropped file was shown over the chat: its box untilted, and its tilt. */
type From = { box: DOMRect; tilt: number };
/** Where each dropped file was shown, in the drop's order, until the cards it made take them (or it is too late). */
let waiting: From[] = [];
let at = 0;
/** A drop's cards are drawn in the commit after it: what no card took by then is let go. */
const WITHIN_MS = 1000;
const FLIGHT_MS = 380;
/** Off and on its way, then setting down: not the page's ease-out, whose long tail leaves it hanging by its card. */
const FLY = "cubic-bezier(0.4, 0, 0.2, 1)";
/** The frost over the chat fades (ChatPage.css.ts, `frostOut`): the marks set off once it is half gone. */
export const FROST_OUT_MS = 260;
const SET_OFF_MS = FROST_OUT_MS / 2;
/** The composer's ground grows round a card in this long (morph.ts, 260ms): the card's ground and words come in then. */
const CARD_AT_MS = 200;
const CARD_IN_MS = 160;

/** The files shown over the chat are let go: where each one's mark is now. */
export function takeOff(marks: Element[]): void {
  waiting = reducedMotion() ? [] : marks.map((node) => {
    const box = node.getBoundingClientRect();
    const style = getComputedStyle(node);
    const tilt = parseFloat(style.rotate) || 0;
    // Untilted it is as big as it is drawn; tilted, its box is a little bigger round the same middle.
    const w = parseFloat(style.width) || box.width, h = parseFloat(style.height) || box.height;
    return { box: new DOMRect(box.left + (box.width - w) / 2, box.top + (box.height - h) / 2, w, h), tilt };
  });
  at = performance.now();
}

/** A card the drop made: its mark (`mark`), drawn in its place, comes there from where the next dropped file was shown. */
export function useLanding(mark: RefObject<Element | null>): void {
  useLayoutEffect(() => {
    const el = mark.current as (HTMLElement | SVGElement) | null;
    if (!el || !waiting.length || performance.now() - at > WITHIN_MS) return;
    const from = waiting.shift()!;
    const to = el.getBoundingClientRect();
    if (!to.width || !to.height) return;
    // The card is in its place from the first, with no rising in of its own; but for its mark, it shows only once the
    // composer's ground, growing to take it (morph.ts grow), is round it: its ground and its words then come in.
    const card = el.closest<HTMLElement>("[data-card]");
    const shows: Animation[] = [];
    if (card) card.style.animation = "none";
    // (A picture is its own card: it comes whole.)
    if (card && card !== el) {
      const timing = { duration: CARD_IN_MS, delay: CARD_AT_MS, easing: "ease-out", fill: "backwards" } as const;
      shows.push(card.animate([{ backgroundColor: "transparent", boxShadow: "none", borderColor: "transparent" }, {}], timing));
      for (const part of card.children) if (!part.contains(el) && part !== el) shows.push(part.animate([{ opacity: 0 }, { opacity: 1 }], timing));
    }
    // The composer's list of files scrolls (when there are many): it lets the mark in meanwhile.
    const box = el.closest<HTMLElement>("form");
    const clipped: HTMLElement[] = [];
    for (let n = el.parentElement; n && n !== box?.parentElement; n = n.parentElement) {
      const s = getComputedStyle(n);
      if (s.overflowX !== "visible" || s.overflowY !== "visible") clipped.push(n);
    }
    for (const n of clipped) n.style.overflow = "visible";
    // Back to where the dropped one was (its middle on that one's, as big, as tilted), then to its own place, which is
    // fixed: keyframes on its own transform, held at their start until it sets off.
    const dx = from.box.left + from.box.width / 2 - (to.left + to.width / 2);
    const dy = from.box.top + from.box.height / 2 - (to.top + to.height / 2);
    el.style.position = "relative";
    el.style.zIndex = "5";
    const run = el.animate([
      { transform: `translate(${dx}px, ${dy}px) rotate(${from.tilt}deg) scale(${from.box.width / to.width}, ${from.box.height / to.height})` },
      { transform: "none" },
    ], { duration: FLIGHT_MS, delay: SET_OFF_MS, easing: FLY, fill: "backwards" });
    const done = () => {
      for (const n of clipped) n.style.overflow = "";
      el.style.position = "";
      el.style.zIndex = "";
    };
    run.onfinish = done;
    return () => { run.cancel(); for (const a of shows) a.cancel(); done(); };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
}
