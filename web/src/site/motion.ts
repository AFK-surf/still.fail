// The first screen's motion, from script (the `motion` library, as the app's ../motion.ts): what moves because of
// something else. The Chinese on the domains' dots lands a character at a time, the two domains lean after the pointer
// at their own depths, and the buttons are drawn to it. Nothing here when the system asks for less motion; the page
// built to HTML shows everything where it rests.
import { animate, stagger } from "motion";
import { follower, reducedMotion } from "../motion.ts";
import * as css from "./site.css.ts";

/** A spring with some give, for what lands or is let go of. */
const SETTLE = { type: "spring", visualDuration: 0.5, bounce: 0.35 } as const;
/** How far (px) each domain leans after the pointer, the second nearer and so further. */
const DEPTH: Record<string, number> = { "still.fail": 14, "youdid.wtf": 26 };
/** How far out of a button the pointer still draws it, and how much of the way it comes. */
const REACH = 60, PULL = 0.3;

/** Starts the first screen's motion in `hero`; gives back what stops it. */
export function heroMotion(hero: HTMLElement): (() => void) | undefined {
  if (reducedMotion()) return undefined;
  const stops: (() => void)[] = [];

  // The characters land on their dot one after another: the ones above fall onto it, the ones below come up to it.
  for (const words of hero.querySelectorAll<HTMLElement>(`.${css.dotSay}`)) {
    const up = words.dataset.at === "below";
    const run = animate(words.querySelectorAll(`.${css.dotChar}`), { opacity: [0, 1], y: [up ? 28 : -28, 0] },
      { ...SETTLE, delay: stagger(0.07, { startDelay: up ? 1.05 : 0.75, from: up ? "first" : "last" }) });
    stops.push(() => run.stop());
  }

  // The domains lean after the pointer over the first screen, and come back to rest when it leaves.
  const lines = [...hero.querySelectorAll<HTMLElement>("[data-domain]")].map((el) => {
    const depth = DEPTH[el.dataset.domain ?? ""] ?? 16;
    let x = 0, y = 0;
    const draw = () => { el.style.transform = `translate3d(${x}px, ${y}px, 0)`; };
    const fx = follower(0, (v) => { x = v; draw(); }), fy = follower(0, (v) => { y = v; draw(); });
    return { depth, fx, fy };
  });
  const lean = (e: PointerEvent) => {
    const r = hero.getBoundingClientRect();
    const nx = ((e.clientX - r.left) / r.width) * 2 - 1, ny = ((e.clientY - r.top) / r.height) * 2 - 1;
    for (const l of lines) { l.fx.to(nx * l.depth, SETTLE); l.fy.to(ny * l.depth * 0.5, SETTLE); }
  };
  const rest = () => { for (const l of lines) { l.fx.to(0, SETTLE); l.fy.to(0, SETTLE); } };

  // The buttons come part of the way to a pointer near them.
  const buttons = [...hero.querySelectorAll<HTMLElement>("a[data-kind]")].map((el) => {
    let x = 0, y = 0;
    const draw = () => { el.style.translate = `${x}px ${y}px`; };
    return { el, fx: follower(0, (v) => { x = v; draw(); }), fy: follower(0, (v) => { y = v; draw(); }) };
  });
  const draw = (e: PointerEvent) => {
    for (const b of buttons) {
      const r = b.el.getBoundingClientRect();
      const dx = e.clientX - (r.left + r.width / 2), dy = e.clientY - (r.top + r.height / 2);
      const near = Math.abs(dx) < r.width / 2 + REACH && Math.abs(dy) < r.height / 2 + REACH;
      b.fx.to(near ? dx * PULL : 0, SETTLE);
      b.fy.to(near ? dy * PULL : 0, SETTLE);
    }
  };

  // Only a pointer that hovers (a mouse, a pen): on a touch screen nothing leans after a finger.
  if (matchMedia("(hover: hover)").matches) {
    const move = (e: PointerEvent) => { lean(e); draw(e); };
    const leave = () => { rest(); for (const b of buttons) { b.fx.to(0, SETTLE); b.fy.to(0, SETTLE); } };
    hero.addEventListener("pointermove", move);
    hero.addEventListener("pointerleave", leave);
    stops.push(() => { hero.removeEventListener("pointermove", move); hero.removeEventListener("pointerleave", leave); });
  }
  stops.push(() => { for (const f of [...lines, ...buttons]) { f.fx.stop(); f.fy.stop(); } });
  return () => { for (const stop of stops) stop(); };
}
