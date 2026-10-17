// The app's motion (ui/Motion.kt, as the web's motion.ts): one set of curves and springs. CSS cubic-bezier(a, b, c, d)
// is Easing.bezier(a, b, c, d) exactly: `Ease` for Reanimated's withTiming, `EaseFn` the same as plain functions.
import { Easing } from "react-native-reanimated";

export const Ease = {
  /** --ease-out (.2, .7, .2, 1): morph, a list's rows coming in, folding. */
  Out: Easing.bezier(0.2, 0.7, 0.2, 1),
  /** --m-ease (.2, .8, .2, 1): sheets, pages rising, a new chat's first words arriving. */
  Arrive: Easing.bezier(0.2, 0.8, 0.2, 1),
  /** (.6, 0, .2, 1): words sent in an open chat on their way to their row. */
  Flight: Easing.bezier(0.6, 0, 0.2, 1),
  /** --m-standard (.4, 0, .2, 1): pages pushed, the jump-to-latest button, the two lists' switch (FastOutSlowIn). */
  Standard: Easing.bezier(0.4, 0, 0.2, 1),
  /** CSS's keyword ease-out. */
  CssOut: Easing.bezier(0, 0, 0.58, 1),
  /** (0, 0, .2, 1): a segmented control's thumb. */
  Decel: Easing.bezier(0, 0, 0.2, 1),
  /** (.3, 0, .5, 1): what leaves by fading. */
  LeaveFade: Easing.bezier(0.3, 0, 0.5, 1),
  /** CSS's keyword ease (.25, .1, .25, 1). */
  Css: Easing.bezier(0.25, 0.1, 0.25, 1),
};

/**
 * The same curves as plain functions of the time's fraction (0..1 → 0..1), for what is computed by hand (a frame
 * loop, an interpolation): Reanimated's `Easing.bezierFn`, which runs on either thread.
 */
export const EaseFn = {
  Out: Easing.bezierFn(0.2, 0.7, 0.2, 1),
  Arrive: Easing.bezierFn(0.2, 0.8, 0.2, 1),
  Flight: Easing.bezierFn(0.6, 0, 0.2, 1),
  Standard: Easing.bezierFn(0.4, 0, 0.2, 1),
  CssOut: Easing.bezierFn(0, 0, 0.58, 1),
  Decel: Easing.bezierFn(0, 0, 0.2, 1),
  LeaveFade: Easing.bezierFn(0.3, 0, 0.5, 1),
  Css: Easing.bezierFn(0.25, 0.1, 0.25, 1),
};

/**
 * Motion's spring by visual duration (seconds) and bounce, as the Android app's motionSpring: stiffness (2π / 1.2v)²
 * and damping ratio clamp(1 − bounce, .05, 1) at mass 1 (Reanimated's withSpring config).
 */
export function motionSpring(visualDuration: number, bounce = 0) {
  const stiffness = Math.pow((2 * Math.PI) / (1.2 * visualDuration), 2);
  const ratio = Math.min(1, Math.max(0.05, 1 - bounce));
  return { mass: 1, stiffness, damping: 2 * ratio * Math.sqrt(stiffness) };
}

/** motion.ts MOVE: what follows another thing's place (a list's rows, small windows). */
export const MoveSpring = motionSpring(0.28);
/** A sheet let go, from the finger's speed. */
export const SheetSpring = motionSpring(0.32);

/** How long an opening page waits for what the core has on the device (web motion.ts LOCAL_MS). */
export const LOCAL_MS = 100;
