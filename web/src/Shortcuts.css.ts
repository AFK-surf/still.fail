// The shortcuts at a glance (⌘/, Shortcuts.tsx). Keys are written as text, quiet, not drawn as key caps.
import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const sheet = style({ display: "grid", gap: "18px" });
export const group = style({ display: "grid", gap: "2px" });
export const groupTitle = style({ margin: "0 0 4px", fontSize: vars.textMeta, fontWeight: "500", color: vars.muted });
export const line = style({
  display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: "16px", padding: "4px 0",
  fontSize: vars.textUi,
});
export const keys = style({ flex: "none", color: vars.muted, fontVariantNumeric: "tabular-nums" });
