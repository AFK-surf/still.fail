import { style } from "@vanilla-extract/css";

export const mNavButton = style({
  display: "grid", placeItems: "center", width: "34px", height: "34px", flex: "none", padding: "0", border: "0",
  borderRadius: "50%", background: "none", color: "var(--m-ink)", cursor: "pointer",
});
export const mNavbarNote = style({
  fontSize: "11px", color: "var(--m-muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
