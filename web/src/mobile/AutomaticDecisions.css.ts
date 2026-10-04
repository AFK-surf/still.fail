import { style } from "@vanilla-extract/css";
export const stationHead = style({ display: "flex", alignItems: "center", marginRight: 20 });
export const stationName = style({ flex: "1", minWidth: 0 });
// The archive policy: its words, its options (a count each, the chats under it), and the form to change them.
export const policyWords = style({ whiteSpace: "pre-wrap", color: "var(--m-ink)", lineHeight: "1.6" });
export const policyPad = style({ display: "flex", flexDirection: "column", gap: 12, padding: "0 20px" });
export const policyText = style({ resize: "vertical", lineHeight: "1.5" });
export const count = style({ fontSize: 13, color: "var(--m-muted)", fontVariantNumeric: "tabular-nums", flex: "none" });
export const chat = style({ fontSize: 13, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", paddingLeft: 12 });
export const optionEdit = style({ display: "flex", flexDirection: "column", gap: 6 });
export const optionTools = style({ display: "flex", gap: 16 });
