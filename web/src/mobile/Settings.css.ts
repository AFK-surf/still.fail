import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const mMe = style({ display: "flex", alignItems: "center", gap: "14px" });
/** How things stand, at a row's end before its chevron. */
export const mValue = style({
  display: "inline-flex", alignItems: "center", gap: "6px", flex: "none", maxWidth: "60%", overflow: "hidden",
  fontSize: vars.textMeta, color: "var(--m-muted)", whiteSpace: "nowrap", textOverflow: "ellipsis",
});
/** What a choice above it does (the appearance's motion): quiet, under it. */
export const mSegNote = style({ padding: "8px 24px 0", fontSize: vars.textMeta, lineHeight: "1.5", color: "var(--m-muted)" });
