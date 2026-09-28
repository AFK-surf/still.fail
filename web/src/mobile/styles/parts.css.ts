import { globalStyle, style } from "@vanilla-extract/css";

export const mGrow = style({ flex: "1", minWidth: "0" });
export const mMuted = style({ color: "var(--m-muted)" });
export const mSubtle = style({ color: "var(--m-subtle)" });
export const mAccent = style({ color: "var(--m-accent)" });
export const mRed = style({ color: "var(--m-red)" });
export const mSmall = style({ fontSize: "12px" });
export const mError = style({ fontSize: "13px", color: "var(--m-red)" });
export const mPad = style({ padding: "0 20px" });
export const mPad18 = style({ padding: "0 18px 30px" });
export const mPadX18 = style({ paddingLeft: "18px", paddingRight: "18px" });
export const mLink = style({
  border: "0", background: "none", padding: "0", color: "var(--m-accent) !important", fontSize: "14px",
  cursor: "pointer",
});
export const mIllus = style({ display: "block", maxWidth: "100%", height: "auto" });
export const mQuotaWindow = style({ display: "inline-flex", alignItems: "center", gap: "2px" });
globalStyle(`${mQuotaWindow} i`, { fontStyle: "normal", fontSize: "9px", fontWeight: "600", color: "var(--m-subtle)" });
