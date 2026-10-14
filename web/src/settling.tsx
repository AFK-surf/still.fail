// What goes from under a message (a decision's options, 留着/归档, 忽略) goes in one motion rather than vanishing, as a
// row leaves a list (listMotion.ts): a copy of it where it was shrinks and fades, as the space it took closes.
import { useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { reducedMotion } from "./motion.ts";
import * as css from "./Chat.css.ts";

const CLOSE = { duration: 320, easing: "cubic-bezier(0.2, 0.7, 0.2, 1)" };
/** As a row leaving a list (listMotion.ts LEAVE_MS). */
const LEAVE = { duration: 200, easing: "ease-out" };

const moving = () => !reducedMotion() && document.visibilityState === "visible";

/** The gap its parent's grid or flex puts before it: what a box closing to nothing takes away too. */
const gapBefore = (el: HTMLElement) => {
  const parent = el.parentElement;
  if (!parent || el === parent.firstElementChild) return 0;
  return parseFloat(getComputedStyle(parent).rowGap) || 0;
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
  const { arriving, gone } = to;
  useLayoutEffect(() => {
    if (open) {
      if (!drawnOpen) setDrawnOpen(true);
      return;
    }
    if (!drawnOpen) return;
    const el = box.current;
    leaving.current = null;
    if (el && el.childElementCount > 0 && moving()) {
      const rect = el.getBoundingClientRect();
      leaving.current = { height: rect.height, copy: el.cloneNode(true) as HTMLElement, at: rect };
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
    const end = gone ? { height: "0px", marginTop: `${-gapBefore(el)}px` } : { height: `${now.height}px` };
    const closing = el.animate([{ height: `${was.height}px`, overflow: "clip" }, { ...end, overflow: "clip" }], { ...CLOSE, fill: gone ? "forwards" : "none" });
    if (gone) void closing.finished.then(gone, () => {});
    const { copy } = was;
    copy.removeAttribute("class");
    copy.setAttribute("aria-hidden", "true");
    copy.inert = true;
    Object.assign(copy.style, { position: "absolute", left: "0", top: `${was.at.top - now.top}px`, width: `${was.at.width}px`, pointerEvents: "none", transformOrigin: "50% 0" });
    el.append(copy);
    void copy.animate([{ opacity: 1, transform: "none" }, { opacity: 0, transform: "scale(0.9)" }], { ...LEAVE, fill: "forwards" })
      .finished.then(() => copy.remove(), () => copy.remove());
    // What takes its place comes as what was there has nearly gone, rather than over it.
    if (arriving) el.querySelector<HTMLElement>(`:scope > ${arriving}`)
      ?.animate([{ opacity: 0, transform: "translateY(4px)" }, { opacity: 1, transform: "none" }], { ...CLOSE, duration: 220, delay: 120, fill: "backwards" });
  }, [box, drawnOpen, arriving, gone]);
}

/**
 * `children` while `shown`, under a message: coming after the message is there, they open their space and grow in from
 * a little smaller; going, they leave as useSettling has them, their space closing to nothing. Nothing while not shown.
 */
export function Settles({ shown, children }: { shown: boolean; children: ReactNode }) {
  const box = useRef<HTMLDivElement>(null);
  const [drawn, setDrawn] = useState(shown);
  const [kept, setKept] = useState(shown);
  if (shown && !kept) setKept(true);
  const gone = useRef(() => setKept(false)).current;
  useSettling(box, shown, drawn, setDrawn, { gone });
  const came = useRef(shown);
  useLayoutEffect(() => {
    const el = box.current;
    const was = came.current;
    came.current = shown;
    if (!el) return;
    // Back while going (an answer that failed): at once.
    for (const a of el.getAnimations()) a.cancel();
    if (!shown || was || !moving()) return;
    const height = el.getBoundingClientRect().height;
    el.animate([{ height: "0px", marginTop: `${-gapBefore(el)}px`, overflow: "clip" }, { height: `${height}px`, marginTop: "0px", overflow: "clip" }], CLOSE);
    for (const child of el.children) {
      (child as HTMLElement).animate([{ opacity: 0, transform: "scale(0.9)", transformOrigin: "50% 0" }, { opacity: 1, transform: "none", transformOrigin: "50% 0" }], { ...CLOSE, duration: 280 });
    }
  }, [shown]);
  if (!kept) return null;
  return <div ref={box} className={css.settles}>{(shown || drawn) && children}</div>;
}
