import { globalStyle, keyframes, style } from "@vanilla-extract/css";
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
export const quotaLabel = style({ color: vars.muted });
export const quotaReset = style({ fontSize: vars.textXs, color: vars.subtle });
export const quotaTrack = style({
  position: "relative", display: "block", height: "6px", borderRadius: "999px", background: vars.neutralBg,
  overflow: "hidden",
});
export const quotaFill = style({
  position: "absolute", inset: "0 auto 0 0", borderRadius: "999px", background: vars.green,
  selectors: {
    "&[data-level=\"amber\"]": { background: vars.amber },
    "&[data-level=\"red\"]": { background: vars.red },
  },
});
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
export const quotaChipTrack = style({ stroke: vars.lineStrong });
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
  selectors: {
    [`${quotaRing}[data-size="large"] &`]: { fontSize: "17px", letterSpacing: "-0.03em" },
  },
});
/** A profile's own page: a ring per window, larger, with its name and when it refills. */
export const quotaDials = style({ display: "flex", flexWrap: "wrap", gap: "28px" });
export const quotaDial = style({ display: "grid", justifyItems: "center", gap: "4px", minWidth: "88px" });
export const quotaDialLabel = style({ fontSize: vars.textSm, fontWeight: "500" });
export const quotaDialReset = style({ fontSize: vars.textXs, color: vars.muted });
export const quotaNote = style({});
export const peopleStack = style({ display: "inline-flex", alignItems: "center", flex: "none" });
export const peopleMore = style({
  fontSize: "10px", color: vars.muted, paddingLeft: "6px", boxShadow: "none !important",
});
export const device = style({ display: "grid", gap: "14px", containerType: "inline-size" });
/** What the machine is, quieter than how loaded it is: one wrapping line, under the meters. */
export const deviceFacts = style({
  display: "flex", flexWrap: "wrap", gap: "2px 14px", fontSize: vars.textXs, color: vars.muted,
});
/** Its meters in one grid, each row a subgrid of it: bars as long as each other, values in one column. The bars stop
 * growing at a readable length, so the value stays near its label on a wide page. */
export const deviceMeters = style({
  display: "grid", gridTemplateColumns: "auto minmax(80px, 320px) auto minmax(0, auto)", columnGap: "14px", rowGap: "10px",
  justifyContent: "start", alignItems: "center", fontSize: vars.textSm,
});
export const deviceRow = style({ display: "grid", gridColumn: "1 / -1", gridTemplateColumns: "subgrid", alignItems: "center" });
export const deviceValue = style({
  textAlign: "right", fontVariantNumeric: "tabular-nums", fontWeight: "600", fontSize: vars.textSm,
  whiteSpace: "nowrap",
});
/** What a meter is of (the CPU's model, the swap in use), after its value; where the card is narrow, left out. */
export const deviceNote = style({
  fontSize: vars.textXs, color: vars.subtle, whiteSpace: "nowrap",
  "@container": { "(max-width: 520px)": { display: "none" } },
});
/** A meter not read yet: its track, breathing. */
export const deviceWaiting = style({
  animation: `${keyframes({ "50%": { opacity: "0.45" } })} 1.4s ease-in-out infinite`,
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
  x: "0.75px", y: "0.75px", width: "calc(100% - 1.5px)", height: "calc(100% - 1.5px)",
  rx: `calc(6px * ${vars.cornerScale} - 0.75px)`, fill: "none", strokeWidth: "1.5px",
});
globalStyle(`${quotaRing} svg`, { position: "absolute", inset: "0" });
globalStyle(`${quotaDial} ${quotaRing}`, { marginBottom: "4px" });
globalStyle(`${peopleStack} > :first-child`, { marginLeft: "0" });
globalStyle(`${peopleStack} ${personLetter}`, { width: "16px", height: "16px", fontSize: "9px" });
globalStyle(`${ring} svg`, { flex: "none" });
globalStyle(`${ring} text`, {
  fontSize: "9px", fontWeight: "600", fill: vars.text, fontVariantNumeric: "tabular-nums",
});
