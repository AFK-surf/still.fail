import { globalStyle, style } from "@vanilla-extract/css";

export const mSheetScroll = style({
  flex: "1", minHeight: "0", overflowY: "auto", overscrollBehavior: "contain", paddingBottom: "24px",
});
export const mForm = style({ display: "flex", flexDirection: "column", gap: "10px", padding: "0 20px 24px" });
export const mFormLabel = style({ fontSize: "13px", fontWeight: "600" });
export const mFormActions = style({ display: "flex", justifyContent: "flex-end", gap: "8px", paddingTop: "6px" });
globalStyle(`${mForm} > p`, { fontSize: "14px" });
