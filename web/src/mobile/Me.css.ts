import { style } from "@vanilla-extract/css";

export const mPadX12 = style({ paddingLeft: "12px", paddingRight: "12px" });
export const mMe = style({ display: "flex", alignItems: "center", gap: "14px" });
export const mSegBlock = style({ paddingBottom: "10px" });
export const mSignOut = style({
  padding: "0", border: "0", background: "none", color: "var(--m-red) !important", fontSize: "15px !important",
  cursor: "pointer",
});
