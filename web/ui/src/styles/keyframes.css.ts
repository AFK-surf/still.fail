import { keyframes } from "@vanilla-extract/css";
export const popKeyframes = keyframes({ "from": { opacity: "0", transform: "scale(.97)" } });
export const dialogInKeyframes = keyframes({ "from": { opacity: "0", transform: "translate(-50%, -48%) scale(.98)" } });
export const fadeKeyframes = keyframes({ "from": { opacity: "0" } });
export const toastInKeyframes = keyframes({ "from": { opacity: "0", transform: "translateY(8px)" } });
export const appearKeyframes = keyframes({ "from": { opacity: "0" }, "to": { opacity: "1" } });
export const spinKeyframes = keyframes({ "to": { transform: "rotate(360deg)" } });
/** A quote's passage marked where it was said (global.css.ts [data-passage-marks]): in over 160ms, held until 1400ms,
 *  faded out until 2400ms. */
export const passageFlashKeyframes = keyframes({
  "0%": { opacity: "0", animationTimingFunction: "cubic-bezier(.2, .7, .2, 1)" },
  "6.7%, 58%": { opacity: "1", animationTimingFunction: "cubic-bezier(.4, 0, 1, 1)" },
  "100%": { opacity: "0" },
});
export const passageFlashHeldKeyframes = keyframes({ "0%, 100%": { opacity: "1" } });
/** A search's stroke under a word it found, drawn in left to right (global.css.ts [data-search-marks]). */
export const searchStrokeKeyframes = keyframes({ to: { strokeDashoffset: "0" } });
/** A found line's stroke (web/src/Marked.tsx) drawn in from its left. */
export const strokeRevealKeyframes = keyframes({ from: { clipPath: "inset(0 100% 0 0)" }, to: { clipPath: "inset(0 0 0 0)" } });
