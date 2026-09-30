import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { muted } from "./styles/shell.css.ts";
import { personLetter } from "./styles/cloud.css.ts";

export const creator = style({
  flex: "none", fontSize: vars.textXs, color: vars.muted, fontWeight: "400", whiteSpace: "nowrap",
});
export const mineFilterBtn = style({
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
    "&[data-state=\"open\"]": { background: vars.hover, color: vars.text },
    "&[data-on]": { color: vars.accentText, background: vars.accentBg },
  },
});
export const mineFilterWide = style({});
export const owner = style({
  display: "inline-flex", alignItems: "center", gap: "6px", fontSize: vars.textXs, color: vars.text,
  whiteSpace: "nowrap",
});
export const ownerNone = style({ color: vars.subtle });
export const quota = style({ display: "grid", gap: "10px" });
export const quotaRow = style({
  display: "grid", gridTemplateColumns: "5.5em minmax(80px, 1fr) 3.2em minmax(7em, auto)", alignItems: "center",
  gap: "10px", fontSize: vars.textSm,
});
export const quotaReset = style({ fontSize: vars.textXs, color: vars.subtle });
/** A window of an allowance, compact: a rounded box, what is left written in it and its edge drawn as far as is left. */
export const quotaChips = style({ display: "inline-flex", alignItems: "center", gap: "4px", flex: "none" });
export const quotaChip = style({
  position: "relative", display: "inline-flex", alignItems: "center", height: "20px", padding: "0 7px",
  overflow: "hidden", borderRadius: `calc(6px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  color: vars.green, fontSize: "11px", fontWeight: "600", lineHeight: "1", fontVariantNumeric: "tabular-nums",
  cursor: "default",
  selectors: {
    "&[data-level=\"amber\"]": { color: vars.amber },
    "&[data-level=\"red\"]": { color: vars.red },
    "&[data-small]": { height: "16px", padding: "0 5px", fontSize: "10px" },
  },
});
export const quotaChipEdge = style({
  position: "absolute", inset: "0", width: "100%", height: "100%", overflow: "visible", pointerEvents: "none",
});
export const quotaChipTrack = style({ stroke: vars.line });
export const quotaChipLeft = style({ stroke: "currentColor", strokeLinecap: "round" });
/** Its number quiet while there is plenty; in its colour once it runs low. */
export const quotaChipText = style({
  position: "relative", display: "inline-flex", gap: "4px", color: vars.muted,
  selectors: {
    [`${quotaChip}:is([data-level="amber"], [data-level="red"]) &`]: { color: "currentColor" },
  },
});
export const quotaChipMark = style({ color: vars.muted });
export const quotaRing = style({
  selectors: {
    "&[data-level=\"amber\"]": { color: vars.amber },
    "&[data-level=\"red\"]": { color: vars.red },
  },
});
export const quotaRingTrack = style({ fill: "none", stroke: vars.neutralBg });
export const quotaRingFill = style({ fill: "none", stroke: "currentColor", strokeLinecap: "round" });
export const quotaRingNumber = style({
  position: "relative", fontSize: "9.5px", fontWeight: "600", color: vars.text, fontVariantNumeric: "tabular-nums",
  letterSpacing: "-0.02em",
});
/** A profile's own page: per window its number large, ten cells lit as far as is left, its name and when it refills. */
export const quotaDials = style({ display: "flex", flexWrap: "wrap", gap: "12px 36px" });
export const quotaDial = style({
  display: "grid", justifyItems: "start", gap: "2px", minWidth: "96px", color: vars.green,
  selectors: {
    "&[data-level=\"amber\"]": { color: vars.amber },
    "&[data-level=\"red\"]": { color: vars.red },
  },
});
/** Its number quiet (the text's colour) while there is plenty; in its colour once it runs low. */
export const quotaDialNumber = style({
  fontSize: "28px", fontWeight: "600", lineHeight: "1.15", letterSpacing: "-0.02em", color: vars.text,
  fontVariantNumeric: "tabular-nums",
  selectors: {
    [`${quotaDial}:is([data-level="amber"], [data-level="red"]) &`]: { color: "currentColor" },
  },
});
export const quotaDialCells = style({ display: "flex", gap: "3px", margin: "4px 0 6px" });
export const quotaDialLabel = style({ fontSize: vars.textSm, fontWeight: "500", color: vars.text });
export const quotaDialReset = style({ fontSize: vars.textXs, color: vars.muted });
export const quotaNote = style({});
export const peopleStack = style({ display: "inline-flex", alignItems: "center", flex: "none" });
export const peopleMore = style({
  fontSize: "10px", color: vars.muted, paddingLeft: "6px", boxShadow: "none !important",
});
export const ring = style({
  display: "inline-flex", alignItems: "center", gap: "4px", fontSize: vars.textXs, color: vars.muted,
});
export const ringTrack = style({ fill: "none", strokeWidth: "3", stroke: vars.line });
export const ringFill = style({
  fill: "none", strokeWidth: "3", stroke: vars.green, strokeLinecap: "round",
  selectors: {
    "&[data-level=\"amber\"]": { stroke: vars.amber },
    "&[data-level=\"red\"]": { stroke: vars.red },
  },
});
globalStyle(`${quotaChipEdge} rect`, {
  x: "1.25px", y: "1.25px", width: "calc(100% - 2.5px)", height: "calc(100% - 2.5px)",
  rx: `calc(6px * ${vars.cornerScale} - 1.25px)`, fill: "none", strokeWidth: "2.5px",
});
globalStyle(`${quotaChip}[data-small] ${quotaChipEdge} rect`, {
  x: "1px", y: "1px", width: "calc(100% - 2px)", height: "calc(100% - 2px)", rx: `calc(6px * ${vars.cornerScale} - 1px)`, strokeWidth: "2px",
});
globalStyle(`${quotaRing} svg`, { position: "absolute", inset: "0" });
globalStyle(`${quotaDialNumber} small`, { fontSize: "0.55em", fontWeight: "500", marginLeft: "1px", color: vars.muted });
globalStyle(`${quotaDialCells} i`, { width: "8px", height: "14px", borderRadius: "2px", background: vars.neutralBg });
globalStyle(`${quotaDialCells} i[data-on]`, { background: "currentColor" });
globalStyle(`${peopleStack} > :first-child`, { marginLeft: "0" });
globalStyle(`${peopleStack} ${personLetter}`, { width: "16px", height: "16px", fontSize: "9px" });
globalStyle(`${ring} svg`, { flex: "none" });
globalStyle(`${ring} text`, {
  fontSize: "9px", fontWeight: "600", fill: vars.text, fontVariantNumeric: "tabular-nums",
});

