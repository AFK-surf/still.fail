// How a list's rows move when the list changes (the sidebar's chats): each row is drawn where it was and goes to where
// it is now (FLIP), carrying on from wherever it had got to; one gone is drawn by a copy that shrinks and fades where it
// was, the rows after it closing over it; one new grows in where it is. A row that overtakes others on its way up (a
// chat with a new message) passes over them on a ground of its own.
import { useLayoutEffect, useRef, useState, type PointerEvent, type RefObject } from "react";
import { animate, motionValue, type AnimationPlaybackControls, type MotionValue } from "motion";
import { MOVE, reducedMotion } from "./motion.ts";
import { vars } from "./styles/tokens.css.ts";

interface Placed { el: HTMLElement; top: number; left: number; width: number; y: MotionValue<number>; run?: AnimationPlaybackControls | undefined }

/** What leaves takes this long; the rest start closing over it a little after it begins to go. */
const LEAVE_MS = 200;
const CLOSE_DELAY = 0.1;

/**
 * Moves the children of `list` marked `data-flip="<key>"` from where they were at the last render to where this one
 * puts them. `list` must be their offset parent (positioned), and the key must stay a row's as it changes.
 */
export function useListMotion(list: RefObject<HTMLElement | null>): void {
  const placed = useRef(new Map<string, Placed>());
  useLayoutEffect(() => {
    const box = list.current;
    if (!box) return;
    const was = placed.current;
    const now = new Map<string, Placed>();
    const els = [...box.querySelectorAll<HTMLElement>(":scope [data-flip]:not([data-leaving])")];
    // Nothing to move from (the list's first rows), or no motion wanted: only where they are is kept.
    const still = was.size === 0 || reducedMotion();
    const gone = [...was.keys()].filter((key) => !els.some((el) => el.dataset.flip === key));
    // Which of the rows there before and now went ahead of others: they pass over the rest.
    const kept = els.map((el) => el.dataset.flip!).filter((key) => was.has(key));
    const before = [...was.keys()].filter((key) => kept.includes(key));
    for (const el of els) {
      const key = el.dataset.flip!;
      const p = was.get(key);
      const at = { top: el.offsetTop, left: el.offsetLeft, width: el.offsetWidth };
      if (!p) {
        const y = motionValue(0);
        const entry: Placed = { el, ...at, y };
        y.on("change", (v) => { entry.el.style.transform = v ? `translateY(${v}px)` : ""; });
        now.set(key, entry);
        if (!still) {
          el.animate([{ opacity: 0, transform: "scale(0.9)" }, { opacity: 1, transform: "none" }],
            { duration: 240, delay: 100, easing: "cubic-bezier(0.2, 0.7, 0.2, 1)", fill: "backwards" });
        }
        continue;
      }
      const from = p.top + p.y.get() - at.top;
      const velocity = p.y.getVelocity();
      const entry: Placed = { ...p, ...at, el };
      now.set(key, entry);
      if (p.el !== el) { p.el.style.transform = ""; p.y.clearListeners(); entry.y.on("change", (v) => { entry.el.style.transform = v ? `translateY(${v}px)` : ""; }); }
      if (still || Math.abs(from) < 0.5) {
        if (p.run || p.el !== el) { p.run?.stop(); entry.run = undefined; entry.y.jump(0); }
        continue;
      }
      p.run?.stop();
      entry.y.jump(from);
      const overtook = before.indexOf(key) > kept.indexOf(key);
      if (overtook) lift(el);
      const run = animate(entry.y, 0, { ...MOVE, velocity, delay: gone.length && !overtook ? CLOSE_DELAY : 0 });
      entry.run = run;
      void run.finished.then(() => { if (entry.run === run) entry.run = undefined; }, () => {});
    }
    for (const key of gone) {
      const p = was.get(key)!;
      p.run?.stop();
      p.y.clearListeners();
      if (!still) leave(box, p);
    }
    placed.current = now;
  });
}

/** A row going up past others: raised over them on a ground like hover's, which fades as it arrives. */
function lift(el: HTMLElement) {
  const ground = `color-mix(in srgb, ${vars.text} 6%, ${vars.sidebar})`;
  el.style.zIndex = "1";
  const run = el.animate(
    [{ backgroundColor: ground }, { backgroundColor: ground, offset: 0.6 }, { backgroundColor: "transparent" }],
    { duration: 480, easing: "linear" },
  );
  void run.finished.then(() => { el.style.zIndex = ""; }, () => {});
}

/** A row gone from the list: a copy of it where it was shrinks and fades, under the rows closing over it. */
function leave(box: HTMLElement, p: Placed) {
  const ghost = p.el.cloneNode(true) as HTMLElement;
  ghost.dataset.leaving = "";
  ghost.setAttribute("aria-hidden", "true");
  ghost.inert = true;
  Object.assign(ghost.style, {
    position: "absolute", top: `${p.top + p.y.get()}px`, left: `${p.left}px`, width: `${p.width}px`, margin: "0",
    transform: "", zIndex: "-1", pointerEvents: "none",
  });
  box.appendChild(ghost);
  const run = ghost.animate([{ opacity: 1, transform: "none" }, { opacity: 0, transform: "scale(0.9)" }], { duration: LEAVE_MS, easing: "ease-out", fill: "forwards" });
  void run.finished.then(() => ghost.remove(), () => ghost.remove());
}

/**
 * `items` (grouped in days) as shown: while `hold` (the pointer over the list), rows keep their places and their days,
 * each with what is new of it, so the row about to be pressed does not move away; ones gone go, new ones come in where
 * they would be, and so do those moved on purpose (`moved`: pinned or let go), to where they go now. Let go, the list
 * is as it is.
 */
export function useHeldOrder<D extends { daysAgo: number; items: I[] }, I>(days: D[], key: (item: I) => string, hold: boolean, moved?: (was: I, now: I) => boolean): D[] {
  const shown = useRef(days);
  if (!hold) {
    shown.current = days;
    return days;
  }
  const fresh = new Map<string, I>();
  for (const day of days) for (const item of day.items) fresh.set(key(item), item);
  const held = new Set<string>();
  const out = shown.current.map((day) => ({
    ...day,
    items: day.items.flatMap((item) => {
      const k = key(item);
      const now = fresh.get(k);
      if (!now || moved?.(item, now)) return [];
      held.add(k);
      return [now];
    }),
  }));
  // New rows go into their own day, where they would be in it (a day not shown yet comes in its place).
  for (const day of days) {
    day.items.forEach((item, i) => {
      if (held.has(key(item))) return;
      let into = out.find((d) => d.daysAgo === day.daysAgo);
      if (!into) {
        into = { ...day, items: [] };
        const at = out.findIndex((d) => d.daysAgo > day.daysAgo);
        out.splice(at < 0 ? out.length : at, 0, into);
      }
      into.items.splice(Math.min(i, into.items.length), 0, item);
    });
  }
  shown.current = out.filter((day) => day.items.length > 0);
  return shown.current;
}

/** Whether a mouse is over what is given the handlers (a touch is not held on to). */
export function usePointerOver(): [boolean, { onPointerEnter: (e: PointerEvent) => void; onPointerLeave: () => void }] {
  const [over, setOver] = useState(false);
  return [over, { onPointerEnter: (e) => { if (e.pointerType === "mouse") setOver(true); }, onPointerLeave: () => setOver(false) }];
}
