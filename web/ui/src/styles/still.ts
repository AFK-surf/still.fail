// Motion reduced: the page's root says so (motion.ts followMotion), as this device's setting says or, when it says none,
// as the system asks. A rule for it is a selector under STILL (`${STILL} &`), not `@media (prefers-reduced-motion)`,
// which the setting could not change.
//
// It changes how things move, never where they end: every animation and transition takes 1ms, once (global.css.ts),
// the same path to the same end, its end events as they were. A rule here says only what that cannot: a loop's rest
// (`stillLoop`), a flash's time (`stillFlash`), a choreography's waits (`stillAtOnce`). Not `animation: none` or
// `transition: none` for what comes, goes or slides: the 1ms does it, and lands where the full one does.
export const STILL = ":root[data-reduced-motion]";

/**
 * A loop (`infinite`) with motion reduced: still, as `rest` says, over what it is without its animation (its calm
 * point, where it is most of the time; a breath at its breath out). `"turn"`: what turns as it is under way (a spinner,
 * a refresh) goes on turning, slowly, every 2.4s; at 1ms, once, it would stand at another angle each time.
 */
export function stillLoop(rest: "turn"): { animationDuration: string; animationIterationCount: string };
export function stillLoop<P extends object = Record<never, never>>(rest?: P): { animation: string } & P;
export function stillLoop(rest: object | "turn" = {}): object {
  if (rest === "turn") return { animationDuration: "2.4s !important", animationIterationCount: "infinite !important" };
  return { animation: "none !important", ...rest };
}

/**
 * A flash (a tint come and gone, its start and end alike) with motion reduced: in 1ms it would not be seen. `held`
 * (keyframes of its peak alone, keyframes.css.ts) shows for the flash's whole `time`, without fading, then is gone.
 */
export const stillFlash = (held: string, time: string) => ({ animation: `${held} ${time} !important` });

/**
 * A choreography's waits with motion reduced (a stagger; one thing waiting for another's motion, which is 1ms now):
 * none. A wait that is the point (what shows only if it takes a while, a hover's pause) keeps its delay.
 */
export const stillAtOnce = { animationDelay: "0s !important", transitionDelay: "0s !important" };
