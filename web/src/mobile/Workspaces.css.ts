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

export const mCurrent = style({ margin: "4px 12px 16px", borderRadius: "16px", background: "var(--m-bg)" });
export const mActions = style({ flexShrink: 0, padding: "8px 0 16px" });
