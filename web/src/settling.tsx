// What goes from under a message once it is answered or let go (a decision's options, 忽略) moves nothing in the list
// while it is on screen (docs/list-motion.md; the user, 2026-10-29: after a pick 「全是消息列表高度变化，会导致一些东西
// 挪来挪去」): it stays as it was drawn, its room with it, and goes only once out of sight (scrolled out of its pane, the
// page hidden), at once. The list's height changes only for what comes, which opens in its turn (listQueue.ts).
import { useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { ENTER, ENTER_FROM, GLIDE_EASE, GLIDE_MS, LEAVE, motionMs, play } from "@stillfail/ui/motion.ts";
import * as css from "./Chat.css.ts";
import { after, listPaneOf, listQueue } from "./listQueue.ts";

/** Its room opening, by the list's law (motion.ts GLIDE_*), as its pane goes along with it. */
const OPEN = { duration: GLIDE_MS, easing: GLIDE_EASE };

const moving = () => document.visibilityState === "visible";

/** The gap its parent's grid or flex puts before it: what a box opening from nothing opens too. */
const gapBefore = (el: HTMLElement) => {
  const parent = el.parentElement;
  if (!parent || el === parent.firstElementChild) return 0;
  return parseFloat(getComputedStyle(parent).rowGap) || 0;
};

/** The gap before `el`, given up by the item before it until then, opening as `el` opens. */
const giveGap = (el: HTMLElement) => {
  const gap = gapBefore(el);
  const before = el.previousElementSibling;
  if (!gap || !(before instanceof HTMLElement)) return null;
  return play(before, [{ marginBottom: `${-gap}px` }, { marginBottom: "0px" }], OPEN);
};

/** Whether `el` shows: some of it in its list's pane (or the window), the page in front. */
const inSight = (el: HTMLElement) => {
  if (!moving()) return false;
  const pane = listPaneOf(el);
  const r = el.getBoundingClientRect();
  const v = pane ? pane.getBoundingClientRect() : { top: 0, bottom: window.innerHeight };
  return r.bottom > v.top && r.top < v.bottom;
};

/**
 * `box` settling once `open` goes: on screen it stays as it was drawn (`drawnOpen` kept), nothing moving for it; out of
 * sight (scrolled out of its pane, the page hidden) it is what takes its place at once, or nothing, `gone`. Open again
 * (an answer that failed), it is back at once.
 */
export function useSettling(box: RefObject<HTMLElement | null>, open: boolean, drawnOpen: boolean, setDrawnOpen: (open: boolean) => void,
  to: { gone?: () => void } = {}) {
  const { gone } = to;
  useLayoutEffect(() => {
    if (open) {
      if (!drawnOpen) setDrawnOpen(true);
      return;
    }
    if (!drawnOpen) return;
    const settle = () => { setDrawnOpen(false); gone?.(); };
    const el = box.current;
    if (!el || el.childElementCount === 0 || !inSight(el)) return void settle();
    const sight = new IntersectionObserver((seen) => { if (seen.some((e) => !e.isIntersecting)) settle(); },
      { root: listPaneOf(el) });
    sight.observe(el);
    const hidden = () => { if (!moving()) settle(); };
    document.addEventListener("visibilitychange", hidden);
    return () => { sight.disconnect(); document.removeEventListener("visibilitychange", hidden); };
  }, [box, open, drawnOpen, setDrawnOpen, gone]);
}

/**
 * `children` while `shown`, under a message: coming after the message is there, they open their space and come in as
 * anything new in the list does (motion.ts ENTER), in their turn; going, they fade where they are, pressed no more,
 * their space kept till it is out of sight (useSettling). Nothing while not shown.
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
    for (const a of el.getAnimations({ subtree: true })) a.cancel();
    el.inert = !shown;
    // Going on screen: faded where it is.
    if (!shown) {
      if (was && moving()) for (const child of el.children) play(child, [{ opacity: 1 }, { opacity: 0 }], { ...LEAVE, fill: "forwards" });
      return;
    }
    if (was || !moving()) return;
    // In its turn among what changes the list's height (listQueue.ts): taking no room till then.
    el.style.display = "none";
    const out = listQueue(el).take(() => {
      el.style.removeProperty("display");
      const height = el.getBoundingClientRect().height;
      play(el, [{ height: "0px", overflow: "clip" }, { height: `${height}px`, overflow: "clip" }], OPEN);
      // The gap before it opens with it, given up by the item before until then.
      given.current = giveGap(el);
      for (const child of el.children) {
        play(child, [ENTER_FROM, { opacity: 1, transform: "none" }], { ...ENTER, fill: "backwards" });
      }
      return after(motionMs(OPEN.duration));
    });
    return () => { out(); el.style.removeProperty("display"); };
  }, [shown]);
  if (!kept) return null;
  return <div ref={box} className={css.settles}>{(shown || drawn) && children}</div>;
}

/**
 * A line saying something else once what it is about is answered while it shows (`text`), in the same room: what it
 * said fades out (LEAVE), then what it says now fades in (ENTER); nothing moves.
 */
export function SaidInPlace({ text, className }: { text: string; className: string }) {
  const el = useRef<HTMLParagraphElement>(null);
  const [said, setSaid] = useState(text);
  const changing = useRef(false);
  useLayoutEffect(() => {
    if (text === said || !el.current || !moving()) return void (text !== said && setSaid(text));
    const out = play(el.current, [{ opacity: 1 }, { opacity: 0 }], { ...LEAVE, fill: "forwards" });
    void out.finished.then(() => { changing.current = true; setSaid(text); }, () => undefined);
    return () => out.cancel();
  }, [text, said]);
  useLayoutEffect(() => {
    if (!changing.current) return;
    changing.current = false;
    for (const a of el.current?.getAnimations() ?? []) a.cancel();
    play(el.current, [{ opacity: 0 }, { opacity: 1 }], ENTER);
  }, [said]);
  return <p ref={el} className={className}>{said}</p>;
}
