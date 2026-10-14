import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

/** Words on a card, a paragraph each. */
export const mBody = style({ padding: "14px 16px", display: "grid", gap: "12px", fontSize: vars.textBody, lineHeight: vars.leadingBody, color: "var(--m-ink)" });
export const mSub = style({ display: "block", color: "var(--m-subtle)" });
export const mNote = style({ display: "inline-flex", alignItems: "center", gap: "6px", fontSize: vars.textMeta, color: "var(--m-subtle)" });
export const mState = style({ display: "flex", alignItems: "center", gap: "8px", fontWeight: "600" });
export const mDot = style({
  width: "7px", height: "7px", borderRadius: "50%", flex: "none", background: "var(--m-line)",
  selectors: { '&[data-on="true"]': { background: "var(--m-green)" }, '&[data-tone="amber"]': { background: "var(--m-warn)" } },
});
export const mWarn = style({ color: "var(--m-warn)", fontSize: vars.textMeta });
export const mDevice = style({ paddingLeft: "14px" });
export const mCode = style({ fontFamily: vars.fontMono, fontWeight: "600", letterSpacing: "1px", fontSize: vars.textUi, color: "var(--m-ink)" });
export const mBigCode = style({ fontFamily: vars.fontMono, fontSize: "36px", lineHeight: "48px", letterSpacing: "5px", fontWeight: "600", textAlign: "center", color: "var(--m-ink)" });
export const mLead = style({ margin: "0", padding: "4px 24px 0", fontSize: vars.textMeta, lineHeight: vars.leadingMeta, color: "var(--m-subtle)" });
export const mActions = style({ display: "grid", padding: "16px 12px 30px" });
export const mSheet = style({ display: "grid", gap: "12px", padding: "8px 20px 24px" });
export const mSheetTitle = style({ fontSize: vars.textTitle });
export const mWaiting = style({ minHeight: "100%", display: "grid", alignContent: "center", justifyItems: "center", textAlign: "center", gap: "14px", padding: "0 28px", color: "var(--m-ink)" });
export const mWaitingTitle = style({ fontSize: vars.textHeading, lineHeight: vars.leadingHeading });
