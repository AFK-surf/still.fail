// The shortcuts at a glance (⌘/) and their settings page (Shortcuts.tsx). Keys are written as text, quiet, not drawn as
// key caps.
import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

export const sheet = style({ display: "grid", gap: "18px" });
export const group = style({ display: "grid", gap: "2px" });
export const groupTitle = style({ margin: "0 0 4px", fontSize: vars.textLabel, fontWeight: "500", color: vars.muted });
export const line = style({
  display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: "16px", padding: "4px 0",
  fontSize: vars.textSecondary,
});
export const keys = style({ flex: "none", color: vars.muted, fontVariantNumeric: "tabular-nums" });

export const rows = style({ display: "grid", gap: "2px" });
export const row = style({ display: "flex", alignItems: "center", gap: "8px", minHeight: "40px", fontSize: vars.textSecondary });
export const rowLabel = style({ flex: "1", minWidth: "0" });
export const record = style({
  minWidth: "120px", height: "30px", padding: "0 12px", border: 0, borderRadius: vars.rField, background: vars.hover,
  color: vars.text, fontSize: vars.textSecondary, fontVariantNumeric: "tabular-nums", textAlign: "center", cursor: "pointer", cornerShape: vars.cornerShape,
  transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.selected },
    "&[data-none]": { color: vars.subtle },
    "&[data-recording]": { background: vars.accentBg, color: vars.accentText },
  },
});
