import { style } from "@vanilla-extract/css";

/**
 * A phrase that moves to the next line whole (a parenthetical, a sentence after another), and only breaks inside when
 * it is wider than the line.
 */
export const phrase = style({ display: "inline-block" });
