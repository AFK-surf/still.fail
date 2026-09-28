import { globalStyle, style } from "@vanilla-extract/css";

export const mNewchatScreen = style({ paddingBottom: "var(--m-bottom)", boxSizing: "border-box" });
export const mNewBody = style({
  flex: "1", minHeight: "0", overflowY: "auto", display: "flex", flexDirection: "column", alignItems: "center",
  gap: "6px", padding: "30px 30px 10px", textAlign: "center",
});
export const mNewProblem = style({
  marginTop: "6px !important", fontSize: "13px !important", color: "var(--m-red)",
  selectors: {
    "&[data-wait]": { color: "var(--m-muted)" },
  },
});
export const mNewSpent = style({
  margin: "0 12px", padding: "8px 12px", borderRadius: "12px",
  background: "color-mix(in srgb, var(--m-warn) 12%, transparent)", fontSize: "13px",
});
export const mNewBottom = style({
  display: "flex", flexDirection: "column", gap: "4px", flex: "none", padding: "8px 10px 0",
});
export const mChoosers = style({
  display: "flex", gap: "6px", overflowX: "auto", padding: "6px 2px", scrollbarWidth: "none",
  selectors: {
    "&::-webkit-scrollbar": { display: "none" },
  },
});
export const mChooser = style({
  display: "inline-flex", alignItems: "center", gap: "6px", flex: "none", height: "30px", boxSizing: "border-box",
  padding: "0 11px", borderRadius: "15px", fontSize: "13px !important", whiteSpace: "nowrap", cursor: "pointer",
});
globalStyle(`${mNewBody} h2`, { margin: "6px 0 0", fontSize: "22px", fontWeight: "700" });
globalStyle(`${mNewBody} > p`, { fontSize: "14px" });
