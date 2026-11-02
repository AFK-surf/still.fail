import { globalStyle } from "@vanilla-extract/css";

const ALPHA = [1, 0.75, 0.55, 0.42, 0.32, 0.25, 0.2, 0.2];
const N = ALPHA.length;
const at = (r: number, deg: number) => {
  const t = (deg * Math.PI) / 180;
  return `${(12 + r * Math.sin(t)).toFixed(3)} ${(12 - r * Math.cos(t)).toFixed(3)}`;
};

/**
 * What is at work (mbui's sf/icons.mbt spokes draws the same): in a 24-unit square, a disc of the colour with two white
 * blades round its middle, each a quarter of a circle 7 out, 3.4 thick with round ends, across from each other, the
 * first from straight up. White on a solid dot, as the other marks are dots: a light ink of fading spokes was not seen
 * at 10px (2026-11-02). Alike every half turn, they go round in eight steps of a sixteenth (`spokesTurn(…, 22.5)`): it
 * steps, it does not turn, a frame for each step, none between (a turning ring drew one for every frame of the screen,
 * 2026-10-19).
 */
const BLADE_R = 7, BLADE_W = 3.4;
const blades = [0, 1].map((i) => `<path d='M${at(BLADE_R, i * 180)}A${BLADE_R} ${BLADE_R} 0 0 1 ${at(BLADE_R, i * 180 + 90)}'/>`).join("");
const spokes = (color: string) => `url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><circle cx='12' cy='12' r='12' fill='${color.replace("#", "%23")}'/><g fill='none' stroke='%23fff' stroke-width='${BLADE_W}' stroke-linecap='round'>${blades}</g></svg>")`;

/**
 * The spokes' step, 10 a second: the root's `data-spoke` (0 to 7, motion.ts stepSpokes) turns every box `spokesTurn`
 * names by `deg` a step (an eighth by default, round in 0.8s). One clock for all: a CSS loop (steps(8) infinite)
 * still had the compositor draw every frame of the screen, 120 a second, for as long as one showed; a step said on the
 * root restyles those boxes alone (a class under `:root[...]`), and their own layer (`will-change`) is only moved, not
 * painted again (2026-10-24). With motion reduced the clock stops and the root says no step: they stand at the first.
 */
export function spokesTurn(selector: string, deg = 45): void {
  for (let step = 1; step < 8; step++) globalStyle(`:root[data-spoke="${step}"] ${selector}`, { rotate: `${step * deg}deg` });
}

/** A box showing the spokes on a disc of `color`; stepping once named to `spokesTurn(…, 22.5)`. */
export const spokesBox = (color: string) => ({
  background: `${spokes(color)} center / 100% no-repeat`, willChange: "rotate",
});

/**
 * The same steps as a ring of eight arcs round an avatar (Android's ui/Spokes.kt drawSegments): in a 24-unit square, a
 * circle 1.5 thick on its edge, each arc 31° of its 45° with round ends (shortened by the half stroke they add), the
 * first straight up. A mask, turned by `spokesTurn`.
 */
const SEG_R = 11.25, SEG_W = 1.5;
const segArcs = ALPHA.map((_, i) => {
  const cap = (SEG_W / 2 / SEG_R) * 180 / Math.PI;
  return `<path d='M${at(SEG_R, i * 45 - 15.5 + cap)}A${SEG_R} ${SEG_R} 0 0 1 ${at(SEG_R, i * 45 + 15.5 - cap)}' stroke-opacity='${ALPHA[(N - i) % N]}'/>`;
}).join("");
export const segments = `url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23000' stroke-width='${SEG_W}' stroke-linecap='round'>${segArcs}</svg>")`;
/** The whole ring, still: what waits. */
export const wholeRing = `url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23000' stroke-width='${SEG_W}'><circle cx='12' cy='12' r='${SEG_R}'/></svg>")`;
