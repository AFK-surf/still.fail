// Made by scripts/curves.ts from the app's libs/mbui/src/ui/motion.mbt: do not edit.

/** What comes (Out). */
export const EASE_OUT = [0.2, 0.7, 0.2, 1] as const;
/** What goes (Leave). */
export const EASE_LEAVE = [0.4, 0, 1, 1] as const;
/** Where a move's spring rests: ω·T (Move). */
export const MOVE_K = 7.4;
/** The longest a move takes (move_most_ms). */
export const MOVE_MOST_MS = 500;
