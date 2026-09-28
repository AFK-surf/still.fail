import { globalStyle, style } from "@vanilla-extract/css";

export const mMono = style({
  fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: "14px", overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const mProfileNote = style({ padding: "8px 24px", fontSize: "13px", color: "var(--m-muted)" });
export const mCheckPill = style({ marginLeft: "0", fontSize: "12px" });
export const mDeviceCode = style({
  alignSelf: "flex-start", padding: "8px 14px", borderRadius: "10px", background: "var(--m-chip)",
  fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: "22px", letterSpacing: "2px",
});
export const mEnvRow = style({
  display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1.3fr) auto", gap: "6px", alignItems: "center",
});
export const mDetails = style({});
globalStyle(`${mDetails} summary`, { fontSize: "13px", color: "var(--m-muted)", cursor: "pointer", padding: "4px 0" });
