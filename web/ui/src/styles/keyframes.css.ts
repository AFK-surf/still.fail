import { keyframes } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";

export const stillfailKeyframes = keyframes({ "50%": { opacity: ".35" } });
export const popKeyframes = keyframes({ "from": { opacity: "0", transform: "scale(.97)" } });
export const dialogInKeyframes = keyframes({ "from": { opacity: "0", transform: "translate(-50%, -48%) scale(.98)" } });
export const fadeKeyframes = keyframes({ "from": { opacity: "0" } });
export const toastInKeyframes = keyframes({ "from": { opacity: "0", transform: "translateY(8px)" } });
export const splashFloatKeyframes = keyframes({ "50%": { transform: "translateY(-5px)" } });
export const appearKeyframes = keyframes({ "from": { opacity: "0" }, "to": { opacity: "1" } });
export const spinKeyframes = keyframes({ "to": { transform: "rotate(360deg)" } });
/**
 * A chat row's watching radar (ChatMark.css.ts leadSlot): its dot beats, then its arcs light up in turn, inner then outer,
 * a signal going out while they stay where they are; then they dim and rest till the next.
 */
export const leadBeatKeyframes = keyframes({ "0%": { transform: "scale(1)" }, "8%": { transform: "scale(1.35)" }, "22%, 100%": { transform: "scale(1)" } });
export const leadLitKeyframes = keyframes({ "0%": { opacity: ".3" }, "10%": { opacity: "1" }, "32%, 100%": { opacity: ".3" } });
/**
 * A chat row's waiting dots (ChatMark.css.ts leadSlot): one breath, in and out in the first
 * half of the loop, then still until the next, so it rests between breaths rather than going on and on.
 */
export const leadBreatheKeyframes = keyframes({ "0%, 52%, 100%": { opacity: ".35" }, "23%": { opacity: "1" } });
export const pulseKeyframes = keyframes({ "50%": { opacity: ".45" } });
export const jobBreatheKeyframes = keyframes({ "50%": { opacity: ".35" } });
export const jobLiveKeyframes = keyframes({ "0%, 100%": { transform: "scale(.6)", opacity: ".35" }, "50%": { transform: "scale(1.15)", opacity: "0" } });
export const msgSendingShowKeyframes = keyframes({ "from": { visibility: "hidden" }, "to": { visibility: "visible" } });
export const caretKeyframes = keyframes({ "50%": { opacity: "0" } });
export const popInKeyframes = keyframes({ "from": { opacity: "0", transform: "translate(-50%, calc(-100% - 4px))" } });
// Motion: what arrives while you watch eases in; nothing moves on first paint or for reduced motion.
export const enterUpKeyframes = keyframes({ "from": { opacity: "0", transform: "translateY(6px)" }, "to": { opacity: "1", transform: "none" } });
export const fadeInKeyframes = keyframes({ "from": { opacity: "0" }, "to": { opacity: "1" } });
export const nowInKeyframes = keyframes({ "from": { opacity: "0", transform: "translateY(5px)" }, "to": { opacity: "1", transform: "none" } });
export const nowOutKeyframes = keyframes({ "from": { opacity: "1", transform: "none" }, "to": { opacity: "0", transform: "translateY(-5px)" } });
export const emitOutKeyframes = keyframes({ "from": { opacity: "0", transform: "scale(.35)", clipPath: "inset(0 0 100% 0)" }, "35%": { opacity: "1" }, "to": { opacity: "1", transform: "none", clipPath: "inset(0 0 0 0)" } });
/** A message a jump led to (Jobs.css.ts msgFlash, as Android's ChatMotion.flash): the accent's ground round it, 8px past
 *  its words and its avatar out in the margin (`--flash-reach` before it), comes in over 160ms, holds until 900ms, then
 *  fades out until 1700ms. */
const flashGround = (c: string) => `0 0 0 8px ${c}, calc(-1 * var(--flash-reach, 0px)) 0 0 8px ${c}`;
export const msgFlashKeyframes = keyframes({
  "0%": { background: "transparent", boxShadow: flashGround("transparent"), animationTimingFunction: "cubic-bezier(.2, .7, .2, 1)" },
  "9.4%, 53%": { background: vars.accentBg, boxShadow: flashGround(vars.accentBg), animationTimingFunction: "cubic-bezier(.4, 0, .2, 1)" },
  "100%": { background: "transparent", boxShadow: flashGround("transparent") },
});
/** Your words a jump led to: their bubble takes the accent's tint instead, in the same time. */
export const bubbleFlashKeyframes = keyframes({
  "0%": { animationTimingFunction: "cubic-bezier(.2, .7, .2, 1)" },
  "9.4%, 53%": { background: `color-mix(in srgb, ${vars.accent} 20%, ${vars.neutralBg})`, animationTimingFunction: "cubic-bezier(.4, 0, .2, 1)" },
});
/** A quote's passage marked where it was said (global.css.ts [data-passage-marks]): in over 160ms, held until 1400ms,
 *  faded out until 2400ms. */
export const passageFlashKeyframes = keyframes({
  "0%": { opacity: "0", animationTimingFunction: "cubic-bezier(.2, .7, .2, 1)" },
  "6.7%, 58%": { opacity: "1", animationTimingFunction: "cubic-bezier(.4, 0, .2, 1)" },
  "100%": { opacity: "0" },
});
/** A search's stroke under a word it found, drawn in left to right (global.css.ts [data-search-marks]). */
export const searchStrokeKeyframes = keyframes({ to: { strokeDashoffset: "0" } });
export const buddyHopKeyframes = keyframes({ "50%": { transform: "translateY(-9px)" } });
export const msgWaitingInKeyframes = keyframes({ "from": { visibility: "hidden" }, "to": { visibility: "visible" } });
export const mFromRightKeyframes = keyframes({ "from": { transform: "translateX(100%)" }, "to": { transform: "none" } });
// From the left; a page under one swiped back, from where it showed (`--m-under-from`, mobile/app.tsx).
export const mFromLeftKeyframes = keyframes({ "from": { transform: "translateX(var(--m-under-from, -100%))" }, "to": { transform: "none" } });
export const mToLeftKeyframes = keyframes({ "from": { transform: "none" }, "to": { transform: "translateX(-100%)" } });
export const mToRightKeyframes = keyframes({ "from": { transform: "translateX(var(--m-from, 0px))" }, "to": { transform: "translateX(100%)" } });
export const mRiseInKeyframes = keyframes({ "from": { transform: "translateY(100%)" }, "to": { transform: "none" } });
export const mRiseOutKeyframes = keyframes({ "from": { transform: "none" }, "to": { transform: "translateY(100%)" } });
export const mRiseKeyframes = keyframes({ "from": { opacity: "0", transform: "translateY(14px)" }, "to": { opacity: "1", transform: "none" } });
