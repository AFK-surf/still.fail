import { globalStyle, style } from "@vanilla-extract/css";
import { mGrow } from "./styles/parts.css.ts";
import { mHPhase, mSettingText } from "./History.css.ts";

export const mSheetLabel = style({ padding: "6px 20px 2px", fontSize: "13px", color: "var(--m-muted)" });
export const mSheetNone = style({ padding: "8px 20px", fontSize: "14px", color: "var(--m-subtle)" });
export const mInvite = style({ display: "flex", alignItems: "center", gap: "8px", padding: "8px 20px" });
globalStyle(`${mInvite} ${mGrow}`, { display: "flex", flexDirection: "column", fontSize: "15px" });
globalStyle(`${mInvite} small`, { fontSize: "12px", color: "var(--m-muted)" });
/** Here rather than with its class: it comes after .m-invite small, and wins over it. */
globalStyle(`${mHPhase} small`, { fontSize: "12px", color: "var(--m-subtle)" });
/** Here rather than with its class: it comes after .m-invite small, and wins over it. */
globalStyle(`${mSettingText} small`, { fontSize: "12px" });
/** The workspace in use, a soft card over the sheet: its name and what it holds, and the way into its settings. */
export const mCurrent = style({
  display: "flex", alignItems: "center", gap: "12px", boxSizing: "border-box", width: "calc(100% - 24px)", margin: "0 12px 8px",
  padding: "14px 14px 14px 16px", border: "0", borderRadius: "14px", background: "color-mix(in srgb, var(--m-ink) 5%, transparent)",
  color: "var(--m-ink)", textAlign: "left", cursor: "pointer",
});
globalStyle(`${mCurrent} ${mGrow}`, { display: "flex", flexDirection: "column", gap: "2px", minWidth: "0" });
globalStyle(`${mCurrent} b`, { fontSize: "17px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${mCurrent} small`, { fontSize: "13px", color: "var(--m-muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const mCurrentGo = style({ display: "flex", alignItems: "center", gap: "2px", flex: "none", fontSize: "14px", color: "var(--m-muted)" });
