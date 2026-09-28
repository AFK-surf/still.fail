import { globalStyle, style } from "@vanilla-extract/css";
import { mGrow } from "./styles/parts.css.ts";

export const mPad20 = style({ padding: "20px" });
export const mBuddy = style({ display: "block", flex: "none" });
export const mStationHead = style({ display: "flex", alignItems: "center", gap: "12px" });
export const mStationName = style({ fontSize: "16px", fontWeight: "700" });
export const mStationSummary = style({ fontSize: "13px", color: "var(--m-muted)" });
export const mStationRings = style({ display: "flex", gap: "14px", paddingTop: "10px" });
export const mRings18 = style({ gap: "18px", padding: "4px 0" });
export const mStationOffline = style({
  display: "flex", flexDirection: "column", alignItems: "center", gap: "4px", paddingTop: "6px", textAlign: "center",
});
export const mStationLine = style({ display: "block", paddingTop: "8px", fontSize: "13px", color: "var(--m-muted)" });
globalStyle(`${mStationHead} ${mGrow}`, { display: "flex", flexDirection: "column" });
