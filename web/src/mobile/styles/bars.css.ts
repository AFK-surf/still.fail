import { style } from "@vanilla-extract/css";
import { vars } from "../../styles/tokens.css.ts";

export const mNavButton = style({
  display: "grid", placeItems: "center", width: "34px", height: "34px", flex: "none", padding: "0", border: "0",
  borderRadius: "50%", background: "none", color: "var(--m-ink)", cursor: "pointer",
});
export const mNavbarNote = style({
  fontSize: vars.textCaption, color: "var(--m-muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
