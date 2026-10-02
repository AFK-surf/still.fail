import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

export const frequent = style({ width: "100%", display: "flex", flexDirection: "column", alignItems: "center", gap: "8px", padding: "12px 0" });
export const label = style({ fontSize: vars.textXs, color: vars.muted });
export const choices = style({ display: "flex", flexWrap: "wrap", justifyContent: "center", gap: "6px", maxWidth: "100%" });
export const combo = style({
  border: "0", borderRadius: vars.rField, padding: "8px 10px", color: vars.muted, background: vars.hover,
  fontSize: vars.textSm, lineHeight: "18px", cursor: "pointer", maxWidth: "100%", overflowWrap: "anywhere",
  selectors: { '&[aria-pressed="true"]': { background: vars.selected, color: vars.text }, '&:hover': { color: vars.text } },
});
// Match the mobile root's button reset without changing the shared component's structure.
globalStyle(`${frequent} button${combo}`, { fontSize: "13px", lineHeight: "18px" });
