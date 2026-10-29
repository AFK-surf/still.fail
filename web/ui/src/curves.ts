// The curves of timed motion, one for each thing a motion can be (motion.ts; the app's apps/mbui/docs/motion.md,
// Curves; mbui's @ui.Ease): kept apart from the motion library so styles can say them too (--ease-move, --ease-leave).

/** The page's --ease-leave: what goes (faded out, shrinking, off the screen). */
export const LEAVE_EASE_CSS = "cubic-bezier(0.4, 0, 1, 1)";

/** Where a move's spring rests: ω·T, its way within 0.2% of its end (the app's Ease.Move, mbui ui/motion.mbt). */
const MOVE_K = 8.5;
const MOVE_END = 1 - (1 + MOVE_K) * Math.exp(-MOVE_K);
/**
 * A move: seen where it was and where it goes, going there (a page pushed or risen, the sidebar, a side panel, a
 * shape, a picture flown open). A critically damped spring's way from rest: no step in its first frame (a curve fast
 * from its start puts a fifth of a long way there at once, then creeps), at its fastest a tenth of the way in.
 */
export const moveEase = (t: number): number => (t <= 0 ? 0 : t >= 1 ? 1 : (1 - (1 + MOVE_K * t) * Math.exp(-MOVE_K * t)) / MOVE_END);
/** The page's --ease-move: moveEase as CSS. */
export const MOVE_EASE_CSS = `linear(${Array.from({ length: 31 }, (_, i) => moveEase(i / 30).toFixed(4)).join(", ")})`;
/** How long a move takes, by how far it goes: near (a row, the composer, a card), a page (pushed, risen, a sheet, a
 * picture, a side panel), far (across the window: the sidebar). */
export const MOVE_NEAR_MS = 450;
export const MOVE_PAGE_MS = 500;
export const MOVE_FAR_MS = 600;
