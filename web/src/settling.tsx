// What goes from under a message once it is answered or let go (a decision's options, 忽略): what takes its place
// comes in where it was, its room going to the new height by the list's law, on screen as out of sight, together with
// whatever else changes (docs/list-motion.md, 2026-10-30: 「需要系统性设计一下」; no more "only once out of sight").
import { useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { ENTER, ENTER_FROM, GLIDE_EASE, GLIDE_MS, LEAVE, motionMs, play } from "@stillfail/ui/motion.ts";
import * as css from "./Chat.css.ts";
import { after, listPaneOf, listQueue } from "./listQueue.ts";
import { listSizing } from "./virtual/list.tsx";

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

/** `el` as tall as `h` in this very frame, before `a` is under way (the list measures it there), till `a` is over. */
const heldFrom = (el: HTMLElement, a: Animation, h: number) => {
  el.style.height = `${h}px`;
  el.style.overflow = "clip";
  const done = () => { el.style.removeProperty("height"); el.style.removeProperty("overflow"); };
  void a.finished.then(done, done);
};

/** The gap before `el` taken by the item before it as `el` closes, so that both close together. */
const takeGap = (el: HTMLElement) => {
  const gap = gapBefore(el);
  const before = el.previousElementSibling;
  if (!gap || !(before instanceof HTMLElement)) return null;
  return play(before, [{ marginBottom: "0px" }, { marginBottom: `${-gap}px` }], { ...OPEN, fill: "forwards" });
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
 * `box` settling once `open` goes: what takes its place (or nothing, `gone`) at once, its room going from the height it
 * had to the new one by the list's law, as what else changes does (docs/list-motion.md, 2026-10-30: on screen as out
 * of sight; nothing waits to be out of sight). Open again (an answer that failed), it is back at once.
 */
export function useSettling(box: RefObject<HTMLElement | null>, open: boolean, drawnOpen: boolean, setDrawnOpen: (open: boolean) => void,
  to: { gone?: () => void } = {}) {
  const { gone } = to;
  const from = useRef<number | null>(null);
  // (how tall it stood while open, as last laid out: what settles it may change in the same render, its options
  // marked settled, before this sees it)
  const stood = useRef<number | null>(null);
  useLayoutEffect(() => {
    if (open && drawnOpen && box.current) stood.current = box.current.getBoundingClientRect().height;
  });
  useLayoutEffect(() => {
    if (open) {
      if (!drawnOpen) setDrawnOpen(true);
      return;
    }
    if (!drawnOpen) return;
    const el = box.current;
    from.current = el && el.childElementCount > 0 && inSight(el) ? stood.current ?? el.getBoundingClientRect().height : null;
    setDrawnOpen(false);
    gone?.();
  }, [box, open, drawnOpen, setDrawnOpen, gone]);
  // its room from the height it had to the one it has now, what it says now coming in
  useLayoutEffect(() => {
    const was = from.current;
    from.current = null;
    const el = box.current;
    if (drawnOpen || was === null || !el || !el.isConnected) return;
    const now = el.getBoundingClientRect().height;
    if (Math.abs(now - was) < 0.5) return;
    const pane = listPaneOf(el);
    if (pane) listSizing(pane, motionMs(OPEN.duration));
    heldFrom(el, play(el, [{ height: `${was}px`, overflow: "clip" }, { height: `${now}px`, overflow: "clip" }], OPEN), was);
    for (const child of el.children) play(child, [ENTER_FROM, { opacity: 1, transform: "none" }], { ...ENTER, fill: "backwards" });
  }, [box, drawnOpen]);
}

/**
 * `children` while `shown`, under a message: coming after the message is there, they open their space and come in as
 * anything new in the list does (motion.ts ENTER), in their turn; going, they fade where they are, pressed no more,
 * their space closing with them (docs/list-motion.md). Nothing once gone.
 */
export function Settles({ shown, children }: { shown: boolean; children: ReactNode }) {
  const box = useRef<HTMLDivElement>(null);
  const [kept, setKept] = useState(shown);
  if (shown && !kept) setKept(true);
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
    // Going: faded where it is as its room closes by the list's law, with whatever else changes; gone once closed.
    if (!shown) {
      if (!was) return;
      if (!moving() || !inSight(el)) return void setKept(false);
      for (const child of el.children) play(child, [{ opacity: 1 }, { opacity: 0 }], { ...LEAVE, fill: "forwards" });
      const height = el.getBoundingClientRect().height;
      const pane = listPaneOf(el);
      if (pane) listSizing(pane, motionMs(OPEN.duration));
      const closing = play(el, [{ height: `${height}px`, overflow: "clip" }, { height: "0px", overflow: "clip" }], { ...OPEN, fill: "forwards" });
      given.current = takeGap(el);
      const gap = given.current;
      void closing.finished.then(() => { gap?.cancel(); setKept(false); }, () => undefined);
      return;
    }
    if (was || !moving()) return;
    // In its turn among what changes the list's height (listQueue.ts): taking no room till then.
    el.style.display = "none";
    const out = listQueue(el).take(() => {
      el.style.removeProperty("display");
      const height = el.getBoundingClientRect().height;
      const pane = listPaneOf(el);
      if (pane) listSizing(pane, motionMs(OPEN.duration));
      heldFrom(el, play(el, [{ height: "0px", overflow: "clip" }, { height: `${height}px`, overflow: "clip" }], OPEN), 0);
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
  return <div ref={box} className={css.settles}>{children}</div>;
}

/**
 * A line saying something else once what it is about is answered while it shows (`text`), in the same room: what it
 * said fades out (LEAVE), then what it says now fades in (ENTER); nothing moves. `gone`: it has nothing more to say,
 * faded out (LEAVE) where it is, its room kept.
 */
export function SaidInPlace({ text, className, gone = false }: { text: string; className: string; gone?: boolean }) {
  const el = useRef<HTMLParagraphElement>(null);
  const shownOnce = useRef(false);
  useLayoutEffect(() => {
    const first = !shownOnce.current;
    shownOnce.current = true;
    if (!el.current) return;
    if (!gone) return void el.current.style.removeProperty("opacity");
    if (first || !moving()) return void (el.current.style.opacity = "0");
    const out = play(el.current, [{ opacity: 1 }, { opacity: 0 }], { ...LEAVE, fill: "forwards" });
    return () => out.cancel();
  }, [gone]);
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
