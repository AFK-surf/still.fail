import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
export const stationHead = style({ display: "flex", alignItems: "center", marginRight: 20 });
export const stationName = style({ flex: "1", minWidth: 0 });
// The archive policy: its words, its options (a count each, the chats under it), and the form to change them.
export const policyWords = style({ whiteSpace: "pre-wrap", fontSize: vars.textControl, lineHeight: "1.6" });
export const policyText = style({ resize: "vertical", lineHeight: "1.5" });
export const count = style({ fontSize: vars.textSecondary, color: "var(--m-muted)", fontVariantNumeric: "tabular-nums", flex: "none" });
export const chat = style({ fontSize: vars.textSecondary, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", paddingLeft: 12 });
export const sheetBody = style({ display: "flex", flexDirection: "column", gap: 12, padding: "4px 20px 24px", overflowY: "auto", flex: 1, minHeight: 0 });
export const sheetTools = style({ display: "flex", alignItems: "center", gap: 8, paddingTop: 4 });
