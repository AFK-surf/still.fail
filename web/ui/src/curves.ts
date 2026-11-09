// The curves of timed motion, one for each thing a motion can be (motion.ts; the app's sf/motion.mbt,
// Curves; mbui's @ui.Ease): kept apart from the motion library so styles can say them too (--ease-move, --ease-leave).

import { EASE_LEAVE, EASE_OUT, MOVE_K, MOVE_MOST_MS } from "./curves-data.ts";

/** How long a move across the window takes. */
export const MOVE_FAR_MS = MOVE_MOST_MS;

/** The page's --ease-out: what comes. */
export const OUT_EASE_CSS = `cubic-bezier(${EASE_OUT.join(", ")})`;
/** The page's --ease-leave: what goes (faded out, shrinking, off the screen). */
export const LEAVE_EASE_CSS = `cubic-bezier(${EASE_LEAVE.join(", ")})`;

const MOVE_END = 1 - (1 + MOVE_K) * Math.exp(-MOVE_K);
/**
 * A move: seen where it was and where it goes, going there (a page pushed or risen, the sidebar, a side panel, a
 * shape, a picture flown open). A critically damped spring's way from rest: no step in its first frame (a curve fast
 * from its start puts a fifth of a long way there at once, then creeps), at its fastest a tenth of the way in.
 */
export const moveEase = (t: number): number => (t <= 0 ? 0 : t >= 1 ? 1 : (1 - (1 + MOVE_K * t) * Math.exp(-MOVE_K * t)) / MOVE_END);
/** The page's --ease-move: moveEase as CSS. */
export const MOVE_EASE_CSS = `linear(${Array.from({ length: 31 }, (_, i) => moveEase(i / 30).toFixed(4)).join(", ")})`;
