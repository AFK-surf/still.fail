import { keyframes } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";

export const stillfailKeyframes = keyframes({ "50%": { opacity: ".35" } });
export const popKeyframes = keyframes({ "from": { opacity: "0", transform: "scale(.98)", filter: "blur(2px)" } });
export const dialogInKeyframes = keyframes({ "from": { opacity: "0", transform: "translate(-50%, -48%) scale(.98)" } });
export const fadeKeyframes = keyframes({ "from": { opacity: "0" } });
export const toastInKeyframes = keyframes({ "from": { opacity: "0", transform: "translateY(8px)" } });
export const splashFloatKeyframes = keyframes({ "50%": { transform: "translateY(-5px)" } });
export const appearKeyframes = keyframes({ "from": { opacity: "0" }, "to": { opacity: "1" } });
export const spinKeyframes = keyframes({ "to": { transform: "rotate(360deg)" } });
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
export const msgFlashKeyframes = keyframes({ "0%, 60%": { background: vars.accentBg }, "100%": { background: "transparent" } });
/** A search's stroke under a word it found, drawn in left to right (global.css.ts [data-search-marks]). */
export const searchStrokeKeyframes = keyframes({ to: { strokeDashoffset: "0" } });
export const buddyHopKeyframes = keyframes({ "50%": { transform: "translateY(-9px)" } });
export const msgWaitingInKeyframes = keyframes({ "from": { visibility: "hidden" }, "to": { visibility: "visible" } });
export const mFromRightKeyframes = keyframes({ "from": { transform: "translateX(100%)" }, "to": { transform: "none" } });
export const mFromLeftKeyframes = keyframes({ "from": { transform: "translateX(-100%)" }, "to": { transform: "none" } });
export const mToLeftKeyframes = keyframes({ "from": { transform: "none" }, "to": { transform: "translateX(-100%)" } });
export const mToRightKeyframes = keyframes({ "from": { transform: "translateX(var(--m-from, 0px))" }, "to": { transform: "translateX(100%)" } });
export const mRiseInKeyframes = keyframes({ "from": { transform: "translateY(100%)" }, "to": { transform: "none" } });
export const mRiseOutKeyframes = keyframes({ "from": { transform: "none" }, "to": { transform: "translateY(100%)" } });
export const mRiseKeyframes = keyframes({ "from": { opacity: "0", transform: "translateY(14px)" }, "to": { opacity: "1", transform: "none" } });
