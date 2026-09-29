import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

/** A station's software in a line: grey, but for a newer version out, an update going on, or one that failed. */
export const versions = style({
  display: "flex", flexWrap: "wrap", alignItems: "baseline", gap: "2px 14px", fontSize: vars.textXs, color: vars.muted,
});
/** One to a line, with the check at the end (a page of its own rather than a card's foot). */
export const rows = style({ flexDirection: "column", alignItems: "flex-start", gap: "8px", fontSize: vars.textSm });
export const item = style({ display: "inline-flex", alignItems: "baseline", gap: "5px", whiteSpace: "nowrap" });
export const version = style({ fontVariantNumeric: "tabular-nums" });
export const newer = style({ color: vars.accentText, fontWeight: "500" });
export const failed = style({ color: vars.red, fontWeight: "500" });
export const action = style({
  padding: "0", border: "0", background: "none", font: "inherit", fontWeight: "500", color: vars.accentText, cursor: "pointer",
  textDecoration: "underline", textUnderlineOffset: "2px",
  selectors: { "&:disabled": { cursor: "default", opacity: "0.6" } },
});
export const check = style([action, { color: vars.muted, fontWeight: "400" }]);
