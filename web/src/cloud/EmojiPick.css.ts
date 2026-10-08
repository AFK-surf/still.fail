import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

// The station's emoji before its name: a square the size of a line, dashed while it has none.
export const slot = style({
  display: "inline-grid", placeItems: "center", flex: "none", width: "28px", height: "28px", padding: "0",
  border: `1px dashed ${vars.lineStrong}`, borderRadius: vars.rOption, background: "none", color: vars.muted,
  fontSize: vars.textTitle, lineHeight: "1", cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&[data-set]": { borderStyle: "solid", borderColor: vars.line },
    "&:hover": { borderColor: vars.fieldHover, color: vars.text },
    "&:focus-visible": { outline: `2px solid var(--focus, ${vars.accent})`, outlineOffset: "2px" },
    "&:disabled": { cursor: "default" },
  },
});
/** Only what it has, for those who may not change it. */
export const shown = style({ flex: "none", fontSize: vars.textTitle, lineHeight: "1" });
export const pick = style({ width: "272px", display: "grid", gap: "8px", padding: "8px" });
export const grid = style({ display: "grid", gridTemplateColumns: "repeat(8, 1fr)", gap: "2px" });
export const choice = style({
  aspectRatio: "1", display: "grid", placeItems: "center", padding: "0", border: "0", borderRadius: vars.rOption,
  background: "none", fontSize: vars.textTitle, lineHeight: "1", cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&:hover, &[aria-pressed=true]": { background: vars.hover },
    "&:focus-visible": { outline: `2px solid var(--focus, ${vars.accent})`, outlineOffset: "-2px" },
  },
});
export const row = style({ display: "flex", alignItems: "center", gap: "6px" });
