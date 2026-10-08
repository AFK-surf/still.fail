import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

export const mMe = style({ display: "flex", alignItems: "center", gap: "14px" });
/** How things stand, at a row's end before its chevron. */
export const mValue = style({
  display: "inline-flex", alignItems: "center", gap: "6px", flex: "none", maxWidth: "60%", overflow: "hidden",
  fontSize: vars.textSecondary, color: "var(--m-muted)", whiteSpace: "nowrap", textOverflow: "ellipsis",
});
