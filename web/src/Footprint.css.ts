// How much a station takes (Usage.tsx, and the phone's mobile/Usage.tsx): the disk's bar and its legend, the parts'
// dots, and the wide screen's rows.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

/** The parts' colours, by the tone the core gives each (FootprintSegment.tone). */
export const TONES: Record<string, string> = {
  "chart-1": vars.accent,
  "chart-2": vars.blue,
  "chart-3": vars.green,
  "chart-4": vars.amber,
  "chart-5": `color-mix(in srgb, ${vars.blue} 55%, ${vars.red})`,
  "chart-6": vars.subtle,
  rest: vars.lineStrong,
  free: vars.line,
};

export const total = style({ display: "block", fontSize: "26px", fontWeight: "600", lineHeight: "1.2", fontVariantNumeric: "tabular-nums" });
export const lead = style({ display: "block", color: vars.muted, fontSize: vars.textXs });
export const bar = style({ display: "flex", height: "10px", borderRadius: "5px", overflow: "hidden", margin: "10px 0 8px", background: vars.line });
export const barPiece = style({ height: "100%", flex: "none" });
export const legend = style({ display: "flex", flexWrap: "wrap", gap: "4px 14px", fontSize: vars.textXs, color: vars.muted });
export const legendItem = style({ display: "inline-flex", alignItems: "center", gap: "6px", selectors: { "&[data-level=red]": { color: vars.red }, "&[data-level=amber]": { color: vars.amber } } });
export const dot = style({ width: "8px", height: "8px", borderRadius: "50%", flex: "none" });
export const summary = style({ marginBottom: "28px" });
export const checked = style({ display: "flex", alignItems: "center", gap: "10px", marginTop: "10px", color: vars.muted, fontSize: vars.textXs });

/** The wide screen's lines: a dot (or none), what and a line under it, the size at the end. */
export const rows = style({ display: "grid" });
export const row = style({
  display: "flex", alignItems: "center", gap: "12px", padding: "10px 0", minWidth: "0",
  selectors: { "& + &": { borderTop: `1px solid ${vars.line}` }, "&[data-nested]": { paddingLeft: "20px" } },
});
export const rowText = style({ flex: "1", minWidth: "0", display: "grid", gap: "2px", fontSize: vars.textSm });
export const rowNote = style({ color: vars.muted, fontSize: vars.textXs, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const size = style({ color: vars.muted, fontSize: vars.textSm, fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" });
export const badge = style({ marginLeft: "6px", padding: "0 5px", borderRadius: "4px", background: vars.neutralBg, color: vars.muted, fontSize: "11px", fontWeight: "400" });
export const choices = style({ display: "grid", gap: "8px" });
globalStyle(`${rowText} a`, { color: "inherit", textDecoration: "none" });
globalStyle(`${rowText} a:hover`, { textDecoration: "underline" });
