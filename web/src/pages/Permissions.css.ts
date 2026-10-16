// The permissions page (Permissions.tsx): a settings card each, its state at the end of its first row.
import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const lead = style({ margin: "6px 0 0", color: vars.muted, fontSize: vars.textUi });
export const muted = style({ color: vars.muted });
export const permission = style({});
export const icon = style({
  flex: "none", display: "grid", placeItems: "center", width: "36px", height: "36px", borderRadius: "50%",
  background: vars.canvas, color: vars.text,
});
// Given in green, refused in red (what is wrong is), not asked yet as plain words.
export const state = style({
  flex: "none", display: "inline-flex", alignItems: "center", gap: "4px", color: vars.muted, fontSize: vars.textMeta, fontWeight: "500",
  selectors: {
    [`${permission}[data-state=granted] &`]: { color: vars.green },
    [`${permission}[data-state=denied] &`]: { color: vars.red },
  },
});
