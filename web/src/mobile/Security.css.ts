import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** Words on a card, a paragraph each. */
export const mBody = style({ padding: "14px 16px", display: "grid", gap: "12px", fontSize: vars.textBody, lineHeight: vars.leadingBody, color: "var(--m-ink)" });
export const mSub = style({ display: "block", color: "var(--m-subtle)" });
export const mNote = style({ display: "inline-flex", alignItems: "center", gap: "6px", fontSize: vars.textMeta, color: "var(--m-subtle)" });
export const mState = style({ display: "flex", alignItems: "center", gap: "8px", fontWeight: "600" });
export const mDot = style({
  width: "7px", height: "7px", borderRadius: "50%", flex: "none", background: "var(--m-line)",
  selectors: { '&[data-on="true"]': { background: "var(--m-green)" }, '&[data-tone="amber"]': { background: "var(--m-warn)" } },
});
export const mWarn = style({ color: "var(--m-warn-ink)", fontSize: vars.textMeta });
/** Its request did not go: why, in red. */
export const mFailed = style({ color: "var(--m-red)", fontSize: vars.textMeta, lineHeight: vars.leadingMeta });
/** The workspaces a waiting device asks to be let into, in its sheet: their names, as large as its words. */
export const mPlaces = style({ display: "flex", alignItems: "center", gap: "6px 14px", flexWrap: "wrap" });
export const mPlace = style({ display: "inline-flex", alignItems: "center", gap: "6px", fontSize: vars.textBody, fontWeight: "600", color: "var(--m-ink)" });
export const mDevice = style({ paddingLeft: "14px" });
/** The app a member's devices under it are, at their words' start (the row's 16, and their 14 in). */
export const mDeviceApp = style({ padding: "6px 16px 0 30px", fontSize: vars.textMeta, fontWeight: "500", color: "var(--m-subtle)" });
/** What a device's row does (续期, 移除), a line of its own under its words. */
export const mDeviceActs = style({ display: "flex", gap: "20px", paddingTop: "6px" });
export const mCode = style({ fontFamily: vars.fontMono, fontWeight: "600", letterSpacing: "1px", fontSize: vars.textUi, color: "var(--m-ink)" });
export const mBigCode = style({ fontFamily: vars.fontMono, fontSize: vars.textDisplay, lineHeight: "1.3", letterSpacing: "5px", fontWeight: "600", textAlign: "center", color: "var(--m-ink)" });
export const mLead = style({ margin: "0", padding: "4px 24px 0", fontSize: vars.textMeta, lineHeight: vars.leadingMeta, color: "var(--m-subtle)" });
export const mActions = style({ display: "grid", padding: "16px 12px 30px" });
export const mSheet = style({ display: "grid", gap: "12px", padding: "8px 20px 24px" });
export const mSheetTitle = style({ fontSize: vars.textTitle });
export const mWaiting = style({ minHeight: "100%", display: "grid", alignContent: "center", justifyItems: "center", textAlign: "center", gap: "14px", padding: "0 28px", color: "var(--m-ink)" });
export const mWaitingTitle = style({ fontSize: vars.textHeading, lineHeight: vars.leadingHeading });
/** The page's main action, along the bottom of the screen, as wide as it: the page scrolls above it. */
export const mFoot = style({
  flex: "none", padding: "10px 16px calc(10px + var(--safe-bottom))", display: "grid",
  background: "color-mix(in srgb, var(--m-bg) 80%, transparent)", backdropFilter: "blur(24px)",
  boxShadow: "inset 0 0.5px 0 var(--m-line)",
});
globalStyle(`${mFoot} > button`, { height: "46px", borderRadius: "23px", justifyContent: "center", fontSize: `${vars.textBody} !important` });
export const mFootNote = style({ textAlign: "center", fontSize: vars.textMeta, color: "var(--m-subtle)", marginBottom: "8px" });
/** Two answers side by side, as wide as the sheet. */
export const mPair = style({ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px", marginTop: "4px" });
globalStyle(`${mPair} > button`, { height: "46px", borderRadius: "23px", justifyContent: "center" });
/** With mPair: approve over deny, each as wide as the sheet; their words fit in any language (side by side, English
 * ones were cut). */
export const mStack = style({ gridTemplateColumns: "1fr" });
