import { globalStyle, style } from "@vanilla-extract/css";
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
export const policyHead = style({ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8, minHeight: 36 });
export const policyTitle = style({ fontSize: vars.textSm, fontWeight: 600 });
export const policyWords = style({ margin: 0, fontSize: vars.textSm, lineHeight: "1.6", whiteSpace: "pre-wrap", overflowWrap: "anywhere" });
export const policyText = style({ resize: "vertical", lineHeight: "1.6" });
export const policyGroup = style({ display: "grid", gap: 2, justifyItems: "start" });
export const policyGroupName = style({ fontSize: vars.textXs, color: vars.muted, fontWeight: 600, padding: "4px 0" });
export const option = style({
  display: "flex", alignItems: "baseline", gap: 12, padding: "6px 0", width: "100%", textAlign: "left",
  background: "none", border: "none", color: "inherit", font: "inherit", cursor: "pointer", minWidth: 0,
  selectors: { "&:disabled": { cursor: "default" } },
});
export const optionName = style({ flex: "0 0 120px", fontSize: vars.textSm });
export const optionRubric = style({ flex: "1", minWidth: 0, fontSize: vars.textXs, color: vars.muted, lineHeight: "1.5" });
export const optionCount = style({ flex: "none", minWidth: "2em", textAlign: "right", fontSize: vars.textXs, color: vars.muted, fontVariantNumeric: "tabular-nums" });
globalStyle(`${option}:not(:disabled):hover ${optionName}`, { textDecoration: "underline dotted", textUnderlineOffset: 3 });
export const optionChats = style({ display: "grid", gap: 4, padding: "0 0 8px 132px", justifySelf: "stretch", minWidth: 0 });
export const optionChat = style({ fontSize: vars.textXs, color: vars.text, textDecoration: "none", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", selectors: { "&:hover": { textDecoration: "underline" } } });
export const optionEdit = style({ display: "flex", alignItems: "center", gap: 8, justifySelf: "stretch" });
export const optionNameInput = style({ flex: "0 0 9em" });
export const policyFoot = style({ display: "flex", justifyContent: "flex-end", gap: 8 });
