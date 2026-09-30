import { style } from "@vanilla-extract/css";

export const mMe = style({ display: "flex", alignItems: "center", gap: "14px" });
/** How things stand, at a row's end before its chevron. */
export const mValue = style({
  display: "inline-flex", alignItems: "center", gap: "6px", flex: "none", maxWidth: "60%", overflow: "hidden",
  fontSize: "14px", color: "var(--m-muted)", whiteSpace: "nowrap", textOverflow: "ellipsis",
});
export const mCheck = style({ flex: "none", color: "var(--m-accent)" });
