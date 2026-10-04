import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

// Layout only: controls, popovers, switches and record text use the shared components.
export const content = style({});
export const note = style({ color: vars.muted, fontSize: vars.textXs, lineHeight: "1.5" });
export const error = style({ color: vars.red, fontSize: vars.textXs, overflowWrap: "anywhere" });
export const bad = style({ color: vars.red });
export const tools = style({ display: "flex", alignItems: "center", gap: 8 });
export const controls = style({ display: "flex", alignItems: "center", justifyContent: "flex-end", gap: 16, flex: "none" });

// The archive policy under a station's rule: its words, then its options in two groups.
export const policy = style({ display: "grid", gap: 12, padding: "4px 12px 16px" });
export const policyHead = style({ display: "flex", alignItems: "center", gap: 8, minHeight: 28 });
export const policyTitle = style({ fontSize: vars.textSm, fontWeight: 600 });
export const policyWords = style({
  margin: 0, padding: "8px 10px", marginInline: -10, fontSize: vars.textSm, lineHeight: "1.6", whiteSpace: "pre-wrap", overflowWrap: "anywhere",
  textAlign: "left", background: "none", border: "none", color: "inherit", font: "inherit", cursor: "pointer",
  borderRadius: vars.rField, cornerShape: vars.cornerShape, transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: { "&:hover:not(:disabled)": { background: vars.list }, "&:disabled": { cursor: "default" } },
});
export const policyText = style({ resize: "vertical", lineHeight: "1.6" });
export const policyGroup = style({ display: "grid", gap: 2, justifyItems: "start" });
export const policyGroupName = style({ fontSize: vars.textXs, color: vars.muted, fontWeight: 600, padding: "4px 0" });
export const option = style({
  display: "flex", alignItems: "baseline", gap: 12, padding: "8px 10px", marginInline: -10, width: "calc(100% + 20px)", textAlign: "left",
  background: "none", border: "none", color: "inherit", font: "inherit", cursor: "pointer", minWidth: 0,
  borderRadius: vars.rField, cornerShape: vars.cornerShape, transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: { "&:hover:not(:disabled)": { background: vars.list }, "&:disabled": { cursor: "default" } },
});
export const optionName = style({ flex: "0 0 120px", fontSize: vars.textSm });
export const optionRubric = style({ flex: "1", minWidth: 0, fontSize: vars.textXs, color: vars.muted, lineHeight: "1.5" });
export const optionCount = style({ flex: "none", minWidth: "2em", textAlign: "right", fontSize: vars.textXs, color: vars.muted, fontVariantNumeric: "tabular-nums" });
export const optionChats = style({ display: "grid", gap: 6, paddingTop: 8, minWidth: 0 });
export const optionChat = style({ fontSize: vars.textSm, color: vars.text, textDecoration: "none", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", selectors: { "&:hover": { textDecoration: "underline" } } });
export const grow = style({ flex: "1" });
export const addOption = style({ alignItems: "center", gap: 6, color: vars.muted, fontSize: vars.textSm });
