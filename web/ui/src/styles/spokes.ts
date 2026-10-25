import { globalStyle } from "@vanilla-extract/css";

/**
 * What is at work (Android's ui/Spokes.kt draws the same): eight spokes in a 24-unit square, each from 4.8 to 9.6 out
 * and 2.9 thick with round ends, the first straight up and the rest clockwise, the leading one whole and those behind
 * it fading. A mask: the box's background is its colour. Turned an eighth at a time (`spokesTurn`), so the lead steps
 * round; it steps, it does not turn: a frame for each step, none between (a turning ring drew one for every frame of
 * the screen, 2026-10-19).
 */
const ALPHA = [1, 0.75, 0.55, 0.42, 0.32, 0.25, 0.2, 0.2];
const N = ALPHA.length;
const lines = ALPHA.map((_, i) => {
  const a = (i * 2 * Math.PI) / N, x = Math.sin(a), y = -Math.cos(a);
  const at = (r: number) => `x1='${(12 + x * r).toFixed(3)}' y1='${(12 + y * r).toFixed(3)}'`;
  return `<line ${at(4.8)} ${at(9.6).replace("x1", "x2").replace("y1", "y2")} stroke-opacity='${ALPHA[(N - i) % N]}'/>`;
}).join("");
export const spokes = `url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' stroke='%23000' stroke-width='2.9' stroke-linecap='round'>${lines}</svg>")`;

/**
 * The spokes' step, 10 a second, round in 0.8s: the root's `data-spoke` (0 to 7, motion.ts stepSpokes) turns every box
 * `spokesTurn` names. One clock for all: a CSS loop (steps(8) infinite) still had the compositor draw every frame of the
 * screen, 120 a second, for as long as one showed; a step said on the root restyles those boxes alone (a class under
 * `:root[...]`), and their own layer (`will-change`) is only moved, not painted again (2026-10-24). With motion reduced
 * the clock stops and the root says no step: they stand at the first.
 */
export function spokesTurn(selector: string): void {
  for (let step = 1; step < 8; step++) globalStyle(`:root[data-spoke="${step}"] ${selector}`, { rotate: `${step * 45}deg` });
}

/** A box of `color` showing the spokes; stepping once named to `spokesTurn`. */
export const spokesBox = (color: string) => ({
  background: color, mask: `${spokes} center / 100% no-repeat`, willChange: "rotate",
});

/**
 * The same steps as a ring of eight arcs round an avatar (Android's ui/Spokes.kt drawSegments): in a 24-unit square, a
 * circle 1.5 thick on its edge, each arc 31° of its 45° with round ends (shortened by the half stroke they add), the
 * first straight up. A mask, turned by `spokesTurn`.
 */
const SEG_R = 11.25, SEG_W = 1.5;
const segArcs = ALPHA.map((_, i) => {
  const cap = (SEG_W / 2 / SEG_R) * 180 / Math.PI;
  const at = (deg: number) => {
    const t = (deg * Math.PI) / 180;
    return `${(12 + SEG_R * Math.sin(t)).toFixed(3)} ${(12 - SEG_R * Math.cos(t)).toFixed(3)}`;
  };
  return `<path d='M${at(i * 45 - 15.5 + cap)}A${SEG_R} ${SEG_R} 0 0 1 ${at(i * 45 + 15.5 - cap)}' stroke-opacity='${ALPHA[(N - i) % N]}'/>`;
}).join("");
export const segments = `url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23000' stroke-width='${SEG_W}' stroke-linecap='round'>${segArcs}</svg>")`;
/** The whole ring, still: what waits. */
export const wholeRing = `url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23000' stroke-width='${SEG_W}'><circle cx='12' cy='12' r='${SEG_R}'/></svg>")`;
