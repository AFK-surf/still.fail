import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

export const mMono = style({
  fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: vars.textUi, overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const mProfileNote = style({ padding: "8px 24px", fontSize: vars.textMeta, color: "var(--m-muted)" });
export const mCheckPill = style({ marginLeft: "0", fontSize: vars.textCaption });
export const mDeviceCode = style({
  alignSelf: "flex-start", padding: "8px 14px", borderRadius: "10px", background: "var(--m-chip)",
  fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: vars.textHeading, letterSpacing: "2px",
});
export const mEnvRow = style({
  display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1.3fr) auto", gap: "6px", alignItems: "center",
});
export const mDetails = style({});
globalStyle(`${mDetails} summary`, { fontSize: vars.textMeta, color: "var(--m-muted)", cursor: "pointer", padding: "4px 0" });

/** The profile's allowance: the PC's dials (QuotaBars), inside the card. */
export const mQuotaDials = style({ padding: "16px 16px 14px" });
