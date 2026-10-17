// What goes from under a message (a decision's options, 留着/归档, 忽略) goes in one motion rather than vanishing, as a
// row leaves a list (listMotion.ts): a copy of it where it was shrinks and fades, as the space it took closes.
//
// The pane it is in follows its end (virtual/list.tsx), and the browser keeps a pane's scroll within what it holds: the
// box is never laid out shorter than it is drawn, not even for a moment to be measured (a pane at its end would be
// pulled up, and put back a frame later). And what it takes in its parent's grid is all taken as it goes, the gap before
// it too (a grid row can't be pulled up into the gap: the item before gives it up instead). The list is told where its
// row is going as it starts (rowHeights.ts), and its pane goes there along with it, by the same law (motion.ts GLIDE_*)
// from the same frame: what is above and what is below move one way each, never there and back.
import { useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { ENTER, ENTER_FROM, GLIDE_EASE, GLIDE_MS, glideValue, LEAVE, LEAVE_TO, play } from "@stillfail/ui/motion.ts";
import * as css from "./Chat.css.ts";
import { closing as rowClosing } from "./rowHeights.ts";

/** Its room opening, by the list's law (motion.ts GLIDE_*), as its pane goes along with it. */
const CLOSE = { duration: GLIDE_MS, easing: GLIDE_EASE };

const moving = () => document.visibilityState === "visible";

/** The gap its parent's grid or flex puts before it: what a box closing to nothing takes away too. */
const gapBefore = (el: HTMLElement) => {
  const parent = el.parentElement;
  if (!parent || el === parent.firstElementChild) return 0;
  return parseFloat(getComputedStyle(parent).rowGap) || 0;
};

/** How tall a box's content stands, laid out under a height held: from its top to its last child's margin's end. */
const contentHeight = (el: HTMLElement) => {
  const last = el.lastElementChild;
  const style = getComputedStyle(el);
  const top = el.getBoundingClientRect().top + el.clientTop + parseFloat(style.paddingTop);
  const end = last ? last.getBoundingClientRect().bottom + (parseFloat(getComputedStyle(last).marginBottom) || 0) : top;
  return Math.max(0, end - top) + parseFloat(style.paddingTop) + parseFloat(style.paddingBottom);
};

/** The gap before `el`, given up by the item before it until then, opening as `el` opens. */
const giveGap = (el: HTMLElement) => {
  const gap = gapBefore(el);
  const before = el.previousElementSibling;
  if (!gap || !(before instanceof HTMLElement)) return null;
  return play(before, [{ marginBottom: `${-gap}px` }, { marginBottom: "0px" }], CLOSE);
};

/**
 * `box` settling once `open` goes: what was there (read on the last commit that drew it, while `drawnOpen`) leaves as a
 * copy, shrinking and fading where it was, as the box closes to what takes its place (`arriving`, a selector of a child:
 * it comes in once the copy has nearly gone), or to nothing at all, the gap before it too, and then `gone`. Open again
 * (an answer that failed), it is back at once. The box is positioned, for the copy.
 */
export function useSettling(box: RefObject<HTMLElement | null>, open: boolean, drawnOpen: boolean, setDrawnOpen: (open: boolean) => void,
  to: { arriving?: string; gone?: () => void } = {}) {
  const leaving = useRef<{ height: number; copy: HTMLElement; at: DOMRect } | null>(null);
  // Closing: stopped and let go of if it opens again (an answer that failed); the item before giving up the gap as the
  // box goes, given back once the box is gone (in the same commit), or back.
  const closing = useRef<{ stop(): void } | null>(null);
  const taken = useRef<HTMLElement | null>(null);
  const { arriving, gone } = to;
  useLayoutEffect(() => {
    if (open) {
      closing.current?.stop();
      if (!drawnOpen) setDrawnOpen(true);
      return;
    }
    if (!drawnOpen) return;
    const el = box.current;
    leaving.current = null;
    if (el && el.childElementCount > 0 && moving()) {
      const rect = el.getBoundingClientRect();
      leaving.current = { height: rect.height, copy: el.cloneNode(true) as HTMLElement, at: rect };
      // Held as tall as it is while what takes its place is drawn in it, and then closed from there.
      Object.assign(el.style, { height: `${rect.height}px`, overflow: "clip" });
    }
    setDrawnOpen(false);
    if (!leaving.current) gone?.();
  }, [box, open, drawnOpen, setDrawnOpen, gone]);
  useLayoutEffect(() => {
    const was = leaving.current;
    const el = box.current;
    if (drawnOpen || !was || !el) return;
    leaving.current = null;
    const now = el.getBoundingClientRect();
    const end = gone ? 0 : contentHeight(el);
    // Going to nothing, the gap before it goes too: the item before draws it in (a grid row is never less than none).
    const gap = gone ? gapBefore(el) : 0;
    const before = gap && el.previousElementSibling instanceof HTMLElement ? el.previousElementSibling : null;
    taken.current = before;
    // The list told where its row is going, as it starts; its pane goes there by the same steps (motion.ts glideValue).
    const told = rowClosing(el, was.height - end + (before ? gap : 0));
    const run = glideValue(was.height, end, (h) => {
      el.style.height = `${h}px`;
      if (before) before.style.marginBottom = `${-gap * (was.height - h) / Math.max(1, was.height - end)}px`;
    });
    const letGo = () => { el.style.removeProperty("height"); el.style.removeProperty("overflow"); };
    closing.current = { stop() { run.cancel(); closing.current = null; told(); letGo(); if (taken.current) { taken.current.style.removeProperty("margin-bottom"); taken.current = null; } } };
    void run.finished.then(() => {
      closing.current = null;
      told();
      // Gone: held at nothing until it is taken away (`gone`), the gap given back then.
      if (gone) gone();
      else letGo();
    });
    const { copy } = was;
    copy.removeAttribute("class");
    copy.removeAttribute("style");
    copy.setAttribute("aria-hidden", "true");
    copy.inert = true;
    Object.assign(copy.style, { position: "absolute", left: "0", top: `${was.at.top - now.top}px`, width: `${was.at.width}px`, pointerEvents: "none", transformOrigin: "50% 0" });
    el.append(copy);
    void play(copy, [{ opacity: 1, transform: "none" }, LEAVE_TO], { ...LEAVE, fill: "forwards" })
      .finished.then(() => copy.remove(), () => copy.remove());
    // What takes its place comes as what was there has nearly gone, rather than over it.
    if (arriving) play(el.querySelector<HTMLElement>(`:scope > ${arriving}`),
      [ENTER_FROM, { opacity: 1, transform: "none" }], { ...ENTER, delay: 120, fill: "backwards" });
  }, [box, drawnOpen, arriving, gone]);
  // Gone (or back): the gap given back to the item before, in the commit that took the box away.
  useLayoutEffect(() => {
    if (!taken.current || (box.current?.isConnected && !drawnOpen)) return;
    taken.current.style.removeProperty("margin-bottom");
    taken.current = null;
  });
}

/**
 * `children` while `shown`, under a message: coming after the message is there, they open their space and come in as
 * anything new in the list does (motion.ts ENTER); going, they leave as useSettling has them, their space closing to
 * nothing. Nothing while not shown.
 */
export function Settles({ shown, children }: { shown: boolean; children: ReactNode }) {
  const box = useRef<HTMLDivElement>(null);
  const [drawn, setDrawn] = useState(shown);
  const [kept, setKept] = useState(shown);
  if (shown && !kept) setKept(true);
  const gone = useRef(() => setKept(false)).current;
  useSettling(box, shown, drawn, setDrawn, { gone });
  const came = useRef(shown);
  const given = useRef<Animation | null>(null);
  useLayoutEffect(() => {
    const el = box.current;
    const was = came.current;
    came.current = shown;
    given.current?.cancel();
    given.current = null;
    if (!el) return;
    // Back while going (an answer that failed): at once.
    for (const a of el.getAnimations()) a.cancel();
    if (!shown || was || !moving()) return;
    const height = el.getBoundingClientRect().height;
    play(el, [{ height: "0px", overflow: "clip" }, { height: `${height}px`, overflow: "clip" }], CLOSE);
    // The gap before it opens with it, given up by the item before until then.
    given.current = giveGap(el);
    for (const child of el.children) {
      play(child, [ENTER_FROM, { opacity: 1, transform: "none" }], { ...ENTER, fill: "backwards" });
    }
  }, [shown]);
  if (!kept) return null;
  return <div ref={box} className={css.settles}>{(shown || drawn) && children}</div>;
}
