import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { mGrow } from "./styles/parts.css.ts";
import { mHPhase, mSettingText } from "./History.css.ts";

export const mSheetLabel = style({ padding: "6px 20px 2px", fontSize: vars.textMeta, color: "var(--m-muted)" });
export const mSheetNone = style({ padding: "8px 20px", fontSize: vars.textMeta, color: "var(--m-subtle)" });
export const mInvite = style({ display: "flex", alignItems: "center", gap: "8px", padding: "8px 20px" });
globalStyle(`${mInvite} ${mGrow}`, { display: "flex", flexDirection: "column", fontSize: vars.textBody });
globalStyle(`${mInvite} small`, { fontSize: vars.textCaption, color: "var(--m-muted)" });
/** Here rather than with its class: it comes after .m-invite small, and wins over it. */
globalStyle(`${mHPhase} small`, { fontSize: vars.textCaption, color: "var(--m-subtle)" });
/** Here rather than with its class: it comes after .m-invite small, and wins over it. */
globalStyle(`${mSettingText} small`, { fontSize: vars.textCaption });

export const mCurrent = style({ margin: "4px 12px 16px", borderRadius: "16px", background: "var(--m-bg)" });
export const mActions = style({ flexShrink: 0, padding: "8px 0 16px" });
