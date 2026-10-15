import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { muted } from "./styles/shell.css.ts";
import { personLetter } from "./styles/cloud.css.ts";

export const creator = style({
  flex: "none", fontSize: vars.textMeta, color: vars.muted, fontWeight: "400", whiteSpace: "nowrap",
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
  display: "inline-flex", alignItems: "center", gap: "6px", fontSize: vars.textMeta, color: vars.text,
  whiteSpace: "nowrap",
});
export const ownerNone = style({ color: vars.subtle });
export const quota = style({ display: "grid", gap: "10px" });
export const quotaRow = style({
  display: "grid", gridTemplateColumns: "5.5em minmax(80px, 1fr) 3.2em minmax(7em, auto)", alignItems: "center",
  gap: "10px", fontSize: vars.textUi,
});
export const quotaReset = style({ fontSize: vars.textMeta, color: vars.subtle });
/** A window of an allowance, compact: a rounded box, what is left written in it and its edge drawn as far as is left. */
/** The boxes side by side, onto a second line rather than squeezed where the room is narrow (a hover card). */
export const quotaChips = style({ display: "inline-flex", flexWrap: "wrap", alignItems: "center", gap: "6px 8px", flex: "none", minWidth: "0" });
export const quotaChip = style({
  position: "relative", display: "inline-flex", alignItems: "center", flex: "none", whiteSpace: "nowrap", height: "20px", padding: "0 8px",
  overflow: "hidden", borderRadius: `calc(6px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: vars.neutralBg,
  color: vars.green, fontSize: vars.textCaption, fontWeight: "600", lineHeight: "1", fontVariantNumeric: "tabular-nums",
  cursor: "default",
  selectors: {
    "&[data-level=\"amber\"]": { color: vars.amber },
    "&[data-level=\"red\"]": { color: vars.red },
    "&[data-level=\"progress\"]": { color: vars.accent },
    "&[data-small]": { height: "16px", padding: "0 5px", fontSize: vars.textCaption },
  },
});
/** How full: a quiet grey while there is plenty, its level's colour faintly once it runs low (the accent, moving, for a
 * download). */
export const quotaChipFill = style({
  position: "absolute", top: "0", bottom: "0", left: "0", background: vars.muted, opacity: 0.22, pointerEvents: "none",
  selectors: {
    [`${quotaChip}:is([data-level="amber"], [data-level="red"], [data-level="progress"]) > &`]: { background: "currentColor", opacity: 0.2 },
    [`${quotaChip}[data-level="progress"] > &`]: { transition: "width .5s ease-out" },
  },
});
/** Its number quiet while there is plenty; in its colour once it runs low. */
export const quotaChipText = style({
  position: "relative", display: "inline-flex", gap: "5px", color: vars.muted,
  selectors: {
    [`${quotaChip}:is([data-level="amber"], [data-level="red"]) &`]: { color: "currentColor" },
  },
});
export const quotaChipMark = style({ color: vars.muted });
// Its mark and number trimmed to their capitals and figures, so they sit in the middle of the box (as the font sets
// them, lower by the room it keeps above for accents).
globalStyle(`${quotaChipText} > span`, { display: "inline-block", textBoxTrim: "trim-both", textBoxEdge: "cap alphabetic" });
/** A profile's own page: per window its number large, ten cells lit as far as is left, its name and when it refills. */
export const quotaDials = style({
  display: "flex", flexWrap: "wrap", gap: "12px 36px",
  selectors: { "&[data-row]": { display: "grid", gridTemplateColumns: "repeat(3, minmax(0, 1fr))", gap: "12px 16px" } },
});
export const quotaDial = style({
  display: "grid", justifyItems: "start", gap: "2px", minWidth: "96px", color: vars.green,
  selectors: {
    "&[data-level=\"amber\"]": { color: vars.amber },
    "&[data-level=\"red\"]": { color: vars.red },
  },
});
/** Its number quiet (the text's colour) while there is plenty; in its colour once it runs low. */
export const quotaDialNumber = style({
  fontSize: vars.textDisplay, fontWeight: "600", lineHeight: "1.15", letterSpacing: "-0.02em", color: vars.text,
  fontVariantNumeric: "tabular-nums",
  selectors: {
    [`${quotaDial}:is([data-level="amber"], [data-level="red"]) &`]: { color: "currentColor" },
  },
});
export const quotaDialCells = style({ display: "flex", gap: "3px", margin: "4px 0 6px" });
export const quotaDialLabel = style({ fontSize: vars.textUi, fontWeight: "500", color: vars.text });
export const quotaDialReset = style({ fontSize: vars.textMeta, color: vars.muted });
export const quotaNote = style({});
export const peopleStack = style({ display: "inline-flex", alignItems: "center", flex: "none" });
export const peopleMore = style({
  fontSize: vars.textCaption, color: vars.muted, paddingLeft: "6px", boxShadow: "none !important",
});
globalStyle(`${quotaDialNumber} small`, { fontSize: "0.55em", fontWeight: "500", marginLeft: "1px", color: vars.muted });
globalStyle(`${quotaDialCells} i`, { width: "8px", height: "14px", borderRadius: "2px", background: vars.neutralBg });
// Three across a phone: the cells a little narrower, so ten of them fit a third of it.
globalStyle(`${quotaDials}[data-row] ${quotaDial}`, { minWidth: "0" });
globalStyle(`${quotaDials}[data-row] ${quotaDialCells}`, { gap: "2px" });
globalStyle(`${quotaDials}[data-row] ${quotaDialCells} i`, { width: "7px" });
globalStyle(`${quotaDialCells} i[data-on]`, { background: "currentColor" });
globalStyle(`${peopleStack} > :first-child`, { marginLeft: "0" });
globalStyle(`${peopleStack} ${personLetter}`, { width: "16px", height: "16px", fontSize: vars.textCaption });

