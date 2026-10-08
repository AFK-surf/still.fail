import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../../styles/tokens.css.ts";

export const mGrow = style({ flex: "1", minWidth: "0" });
export const mMuted = style({ color: "var(--m-muted)" });
export const mSubtle = style({ color: "var(--m-subtle)" });
export const mAccent = style({ color: "var(--m-accent)" });
export const mRed = style({ color: "var(--m-red)" });
export const mSmall = style({ fontSize: vars.textCaption });
export const mError = style({ fontSize: vars.textMeta, color: "var(--m-red)" });
export const mPad = style({ padding: "0 20px" });
export const mPad18 = style({ padding: "0 18px 30px" });
export const mPadX18 = style({ paddingLeft: "18px", paddingRight: "18px" });
export const mLink = style({
  border: "0", background: "none", padding: "0", color: "var(--m-accent) !important", fontSize: vars.textUi,
  cursor: "pointer",
});
export const mIllus = style({ display: "block", maxWidth: "100%", height: "auto" });
