import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** The field and its colours one over the other (the same box, the same grid cell): the colours under, the text typed in
 *  the field over them, its own letters not drawn; as tall as its lines, so neither scrolls. */
export const stack = style({ display: "grid" });
const layer = {
  gridArea: "1 / 1", margin: 0, fontFamily: vars.fontMono, fontSize: vars.textMeta, lineHeight: "1.6",
  whiteSpace: "pre-wrap", overflowWrap: "anywhere", overflow: "hidden", minHeight: "6.6em",
} as const;
export const field = style({ ...layer, resize: "none", background: "transparent", color: "transparent", caretColor: vars.text, position: "relative" });
export const colours = style({ ...layer, borderColor: "transparent", color: vars.text, pointerEvents: "none" });
export const name = style({ color: vars.blue });
export const value = style({ color: vars.text });
export const comment = style({ color: vars.subtle });
export const other = style({ color: vars.muted });
/** A line that keeps the variables from being saved. */
export const wrong = style({ color: vars.red });
/** What is wrong with the lines, a line each under the field. */
export const problems = style({ display: "grid", gap: "2px", margin: 0, padding: 0, listStyle: "none", fontSize: vars.textMeta });
export const problem = style({ color: vars.muted, selectors: { "&[data-error]": { color: vars.red } } });
