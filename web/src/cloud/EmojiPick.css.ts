import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

// The station's icon before its name: a square the size of a line, dashed while it has none.
export const slot = style({
  display: "inline-grid", placeItems: "center", flex: "none", width: "28px", height: "28px", padding: "0",
  border: `1px dashed ${vars.lineStrong}`, borderRadius: vars.rOption, background: "none", color: vars.muted,
  cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&[data-set]": { borderStyle: "solid", borderColor: vars.line, color: vars.text },
    "&:hover": { borderColor: vars.fieldHover, color: vars.text },
    "&:focus-visible": { outline: `2px solid var(--focus, ${vars.accent})`, outlineOffset: "2px" },
    "&:disabled": { cursor: "default" },
  },
});
/** Only what it has, for those who may not change it. */
export const shown = style({ display: "grid", flex: "none" });
/** The panel: a menu's, its corners' cells as round as its own corners less its padding. */
export const pick = style({ width: "268px" });
export const grid = style({ display: "grid", gridTemplateColumns: "repeat(8, 1fr)", gap: "2px" });
export const choice = style({
  aspectRatio: "1", display: "grid", placeItems: "center", padding: "0", border: "0",
  borderRadius: `calc(${vars.rMenu} - 6px)`, background: "none", color: vars.muted, cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
    "&[aria-pressed=true]": { background: vars.hover, color: vars.accent },
    "&:focus-visible": { outline: `2px solid var(--focus, ${vars.accent})`, outlineOffset: "-2px" },
  },
});
/** Having none, under the icons, as a menu's row. */
export const clear = style({ marginTop: "4px", color: vars.muted, borderRadius: `calc(${vars.rMenu} - 6px)` });
