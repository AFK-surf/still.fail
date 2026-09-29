// The first screen's motion, from script (the `motion` library, as the app's ../motion.ts): what moves because of
// something else. The page opens with the Chinese, large, which then flies onto the domains' dots as the English grows
// out of them; and the two domains lean after the pointer at their own depths. Nothing here when the system asks for
// less motion; the page built to HTML shows everything where it rests.
import { animate } from "motion";
import { follower, reducedMotion } from "../motion.ts";
import * as css from "./site.css.ts";

/** A spring with some give, for what lands or is let go of. */
const SETTLE = { type: "spring", visualDuration: 0.5, bounce: 0.35 } as const;
/** How far (px) each domain leans after the pointer, the second nearer and so further. */
const DEPTH: Record<string, number> = { "still.fail": 14, "youdid.wtf": 26 };

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

  // Only a pointer that hovers (a mouse, a pen): on a touch screen nothing leans after a finger.
  if (matchMedia("(hover: hover)").matches) {
    const move = (e: PointerEvent) => lean(e);
    const leave = rest;
    hero.addEventListener("pointermove", move);
    hero.addEventListener("pointerleave", leave);
    stops.push(() => { hero.removeEventListener("pointermove", move); hero.removeEventListener("pointerleave", leave); });
  }
  stops.push(() => { for (const f of lines) { f.fx.stop(); f.fy.stop(); } });
  return () => { for (const stop of stops) stop(); };
}

const wait = (s: number) => new Promise((done) => setTimeout(done, s * 1000));

/**
 * The opening: the Chinese slams in, holds, and goes to the dots while the English grows out of them. The characters
 * are the very ones on the dots all along: each is drawn first at the size and place it has in the large layout (the
 * unseen intro), then goes to its own; at the end nothing is swapped, only its inline styles let go.
 */
async function intro(hero: HTMLElement, running: { stop(): void }[], stopped: () => boolean): Promise<void> {
  const title = hero.querySelector<HTMLElement>(`.${css.title}`), overlay = hero.querySelector<HTMLElement>(`.${css.intro}`);
  if (!title || !overlay) return;
  const play = <T extends { stop(): void; finished: Promise<unknown> }>(run: T) => { running.push(run); return run.finished.catch(() => {}); };
  // Each glyph on the dots (still.fail's, then youdid.wtf's above and below) and where it stands in the large layout.
  const large = [...overlay.querySelectorAll<HTMLElement>(`.${css.introChar}`)];
  const glyphs = [...title.querySelectorAll<HTMLElement>(`.${css.dotGlyph}`)].map((el, i) => {
    const big = large[i]!, from = big.getBoundingClientRect(), box = el.getBoundingClientRect(), look = getComputedStyle(big);
    // Read now: a computed style is live, and it is about to be drawn large.
    const now = getComputedStyle(el), rest = { fontSize: now.fontSize, fontWeight: now.fontWeight, color: now.color };
    const x = from.left + from.width / 2 - (box.left + box.width / 2), y = from.top + from.height / 2 - (box.top + box.height / 2);
    // Drawn large where the intro has it: its own box stays put, the glyph (centred in it) is moved and sized.
    Object.assign(el.style, { fontSize: look.fontSize, fontWeight: look.fontWeight, color: look.color, textShadow: look.textShadow, translate: `${x}px ${y}px` });
    return { el, line: big.closest<HTMLElement>(`.${css.introLine}`)!, x, y, rest };
  });

  // 1. The Chinese slams in, a character at a time, each spun and blurred in from far too big and shaking the page as
  //    it lands; a beat between the two lines. The second line (the angrier one) keeps trembling, and its JB hits
  //    hardest.
  const stage = title.parentElement!;
  const shake = (hard: number) => play(animate(stage, { x: [0, -hard, hard * 0.8, -hard * 0.5, hard * 0.25, 0], y: [0, hard * 0.4, -hard * 0.3, 0, 0, 0] }, { duration: 0.28, ease: "easeOut" }));
  for (const line of overlay.querySelectorAll<HTMLElement>(`.${css.introLine}`)) {
    const own = glyphs.filter((g) => g.line === line);
    for (const [i, g] of own.entries()) {
      if (stopped()) return;
      const last = i === own.length - 1, hard = line.dataset.line === "youdid.wtf" && i >= own.length - 2;
      void play(animate(g.el, { opacity: [0, 1], scale: [hard ? 4.5 : 3, 1], rotate: [(Math.random() - 0.5) * (hard ? 70 : 40), 0], filter: ["blur(14px)", "blur(0px)"] },
        { type: "spring", visualDuration: 0.26, bounce: 0.45 }));
      setTimeout(() => void shake(hard ? 14 : 5), 170);
      await wait(last ? 0.2 : hard ? 0.24 : 0.14);
    }
    await wait(0.55);
  }
  // Still fuming while it holds.
  const fuming = glyphs.filter((g) => g.line.dataset.line === "youdid.wtf").map((g) => g.el);
  const fume = animate(fuming, { rotate: [0, -3, 3, -2, 2, 0] }, { duration: 0.35 });
  void play(fume);
  await wait(0.4);
  fume.stop();
  if (stopped()) return;

  // 2. The English grows out of each dot, and each character goes to its place on it, taking its size and colour.
  const reveal = [...title.querySelectorAll<HTMLElement>("[data-domain]")].flatMap((line) => {
    const dot = line.querySelector<HTMLElement>(`.${css.dot}`)!.getBoundingClientRect();
    return [...line.querySelectorAll<HTMLElement>(`.${css.word}`)].map((el) => {
      const box = el.getBoundingClientRect(), at = `${dot.left - box.left}px ${dot.top - box.top - box.height * 0.08}px`;
      el.style.clipPath = `circle(0px at ${at})`;
      el.style.opacity = "1";
      const far = Math.hypot(Math.max(Math.abs(dot.left - box.left), Math.abs(box.right - dot.left)), box.height);
      return play(animate(el, { clipPath: `circle(${far}px at ${at})` }, { duration: 1.1, ease: [0.5, 0, 0.2, 1], delay: 0.35 }))
        .then(() => { el.style.removeProperty("clip-path"); });
    });
  });
  // Driven by hand from one number, so that every property arrives together, exactly at its resting value.
  const fly = glyphs.map((g, i) => {
    const from = { size: parseFloat(g.el.style.fontSize), weight: parseFloat(g.el.style.fontWeight), color: rgba(g.el.style.color) };
    const to = { size: parseFloat(g.rest.fontSize), weight: parseFloat(g.rest.fontWeight), color: rgba(g.rest.color) };
    const shadow = g.el.style.textShadow, turn = i % 2 ? 360 : -360;
    return play(animate(0, 1, {
      duration: 0.9, ease: [0.7, 0, 0.2, 1], delay: (glyphs.length - 1 - i) * 0.035,
      onUpdate: (t) => {
        const at = (a: number, b: number) => a + (b - a) * t;
        Object.assign(g.el.style, {
          fontSize: `${at(from.size, to.size)}px`, fontWeight: `${Math.round(at(from.weight, to.weight))}`,
          color: `rgba(${from.color.map((c, k) => (k < 3 ? Math.round(at(c, to.color[k]!)) : at(c, to.color[k]!))).join(", ")})`,
          textShadow: t < 1 && shadow && shadow !== "none" ? shadow.replace(/rgba?\([^)]*\)/, (c) => { const v = rgba(c); return `rgba(${v[0]}, ${v[1]}, ${v[2]}, ${v[3]! * (1 - t)})`; }) : "none",
          translate: `${at(g.x, 0)}px ${at(g.y, 0)}px`, transform: `rotate(${turn * t}deg)`,
        });
      },
    }));
  });
  await Promise.all(fly);
  if (stopped()) return;
  // Where they rest they are drawn as the page draws them: what the motion held, let go of (it held just those values).
  for (const g of glyphs) {
    for (const p of ["font-size", "font-weight", "color", "text-shadow", "translate", "transform", "filter"]) g.el.style.removeProperty(p);
    g.el.style.opacity = "1";
  }
  overlay.style.display = "none";
  await Promise.all(reveal);
  // The demo under it waits for this to start playing (demo/mount.tsx), and for the stage it rises on (site.css.ts).
  await wait(1.4);
  window.dispatchEvent(new Event("ember-site-opened"));
}

/** A computed colour as [r, g, b, a]. */
function rgba(color: string): number[] {
  const v = color.match(/[\d.]+/g)?.map(Number) ?? [0, 0, 0, 1];
  return [v[0] ?? 0, v[1] ?? 0, v[2] ?? 0, v[3] ?? 1];
}
