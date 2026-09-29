// The first screen's motion, from script (the `motion` library, as the app's ../motion.ts): what moves because of
// something else. The page opens with the Chinese, large, which then flies onto the domains' dots as the English grows
// out of them; the two domains lean after the pointer at their own depths, and the buttons are drawn to it. Nothing
// here when the system asks for less motion; the page built to HTML shows everything where it rests.
import { animate } from "motion";
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

  // The page opens with the Chinese, large; then each character flies to its place on a dot and the English grows out
  // of the dots around it, ending as the title rests.
  let stopped = false;
  const running: { stop(): void }[] = [];
  stops.push(() => { stopped = true; for (const r of running) r.stop(); });
  void intro(hero, running, () => stopped);

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

const wait = (s: number) => new Promise((done) => setTimeout(done, s * 1000));

/** The opening: the Chinese slams in, holds, and goes to the dots while the English grows out of them. */
async function intro(hero: HTMLElement, running: { stop(): void }[], stopped: () => boolean): Promise<void> {
  const title = hero.querySelector<HTMLElement>(`.${css.title}`), overlay = hero.querySelector<HTMLElement>(`.${css.intro}`);
  if (!title || !overlay) return;
  const play = <T extends { stop(): void; finished: Promise<unknown> }>(run: T) => { running.push(run); return run.finished.catch(() => {}); };
  const big = [...overlay.querySelectorAll<HTMLElement>(`.${css.introChar}`)];
  // Where each goes: the characters on the dots, in the same order (still.fail's, then youdid.wtf's above and below).
  const small = [...title.querySelectorAll<HTMLElement>(`.${css.dotChar}`)];
  const domains = [...title.querySelectorAll<HTMLElement>("[data-domain]")];

  // 1. The Chinese slams in, a character at a time, each spun and blurred in from far too big and shaking the page as
  //    it lands; a beat between the two lines. The second line (the angrier one) keeps trembling, and its JB hits
  //    hardest.
  const stage = title.parentElement!;
  const shake = (hard: number) => play(animate(stage, { x: [0, -hard, hard * 0.8, -hard * 0.5, hard * 0.25, 0], y: [0, hard * 0.4, -hard * 0.3, 0, 0, 0] }, { duration: 0.28, ease: "easeOut" }));
  for (const line of overlay.querySelectorAll<HTMLElement>(`.${css.introLine}`)) {
    const chars = [...line.querySelectorAll<HTMLElement>(`.${css.introChar}`)];
    for (const [i, c] of chars.entries()) {
      if (stopped()) return;
      const last = i === chars.length - 1, hard = line.dataset.line === "youdid.wtf" && i >= chars.length - 2;
      void play(animate(c, { opacity: [0, 1], scale: [hard ? 4.5 : 3, 1], rotate: [(Math.random() - 0.5) * (hard ? 70 : 40), 0], filter: ["blur(14px)", "blur(0px)"] },
        { type: "spring", visualDuration: 0.26, bounce: 0.45 }));
      setTimeout(() => void shake(hard ? 14 : 5), 170);
      await wait(last ? 0.2 : hard ? 0.24 : 0.14);
    }
    await wait(0.55);
  }
  // Still fuming while it holds.
  const fume = overlay.querySelector<HTMLElement>(`.${css.introLine}[data-line="youdid.wtf"]`)!;
  void play(animate(fume, { x: [0, -2, 2, -1.5, 1.5, 0], rotate: [0, -0.6, 0.6, -0.4, 0.4, 0] }, { duration: 0.4, repeat: 1 }));
  await wait(0.35);
  if (stopped()) return;

  // 2. The English grows out of each dot, and each character flies to its place on it, taking its size and colour.
  title.style.opacity = "1";
  const reveal = domains.map((el) => {
    const dot = el.querySelector<HTMLElement>(`.${css.dot}`)!.getBoundingClientRect(), box = el.getBoundingClientRect();
    const at = `${dot.left - box.left}px ${dot.top - box.top - box.height * 0.08}px`;
    return play(animate(el, { clipPath: [`circle(0px at ${at})`, `circle(${box.width * 1.2}px at ${at})`] }, { duration: 1.1, ease: [0.5, 0, 0.2, 1], delay: 0.35 }))
      .then(() => { el.style.removeProperty("clip-path"); });
  });
  const fly = big.map((b, i) => {
    const to = small[i];
    if (!to) return Promise.resolve();
    const from = b.getBoundingClientRect(), there = to.getBoundingClientRect();
    const x = there.left + there.width / 2 - (from.left + from.width / 2), y = there.top + there.height / 2 - (from.top + from.height / 2);
    return play(animate(b, { x, y, scale: there.height / from.height, rotate: [0, (i % 2 ? 1 : -1) * 360], color: getComputedStyle(to).color, textShadow: "0 0 0 transparent" },
      { duration: 0.9, ease: [0.7, 0, 0.2, 1], delay: (big.length - 1 - i) * 0.035 }));
  });
  await Promise.all(fly);
  if (stopped()) return;
  for (const s of small) s.style.opacity = "1";
  overlay.style.display = "none";
  await Promise.all(reveal);
}
