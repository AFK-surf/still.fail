import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { litOver } from "@stillfail/ui/styles/lit.ts";

export const frequent = style({ width: "100%", display: "flex", flexDirection: "column", alignItems: "center", gap: "8px", padding: "12px 0" });
export const label = style({ fontSize: vars.textMeta, color: vars.muted });
export const choices = style({ display: "flex", flexWrap: "wrap", justifyContent: "center", gap: "6px", maxWidth: "100%" });
export const combo = style({
  border: "0", borderRadius: vars.rField, cornerShape: vars.cornerShape, padding: "8px 10px", color: vars.muted,
  background: vars.hover,
  fontSize: vars.textUi, lineHeight: "18px", cursor: "pointer", maxWidth: "100%", overflowWrap: "anywhere",
  // Pointed at, the ink over its ground, the chosen one's grey too (pressed again, it is unchosen).
  selectors: { '&[aria-pressed="true"]': { background: vars.selected, color: vars.text }, '&:hover': { ...litOver, color: vars.text } },
});
// Match the mobile root's button reset without changing the shared component's structure.
globalStyle(`${frequent} button${combo}`, { fontSize: vars.textUi, lineHeight: "18px", color: vars.muted });
globalStyle(`${frequent} button${combo}[aria-pressed="true"]`, { color: vars.text });
