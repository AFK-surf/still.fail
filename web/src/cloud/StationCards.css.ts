import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { btn } from "../styles/controls.css.ts";

export const name = style({
  fontSize: vars.textBody, fontWeight: "600", color: vars.text, minWidth: "0",
  overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const state = style({ fontSize: vars.textSm, color: vars.muted, whiteSpace: "nowrap" });
/** Agents at work: the one thing of a station's state said in colour. */
export const busy = style({ color: vars.accentText, fontWeight: "500" });
export const ident = style({ color: vars.subtle });
export const mono = style({ fontFamily: vars.fontMono, fontSize: "0.95em" });
export const menu = style({ display: "flex", justifyContent: "flex-end" });
globalStyle(`${menu} ${btn}`, { flex: "none" });

export const cards = style({ display: "grid", gap: "10px" });
export const card = style({
  display: "grid", gap: "10px", padding: "14px 16px", borderRadius: vars.rCard, cornerShape: vars.cornerShape,
  background: vars.list,
});
export const cardHead = style({ display: "flex", alignItems: "center", gap: "10px", minWidth: "0" });
export const cardTitle = style({ flex: "1", display: "flex", alignItems: "baseline", gap: "10px", minWidth: "0" });
export const dials = style({ display: "inline-flex", gap: "14px" });
export const dial = style({
  display: "inline-flex", alignItems: "center", gap: "5px", fontSize: vars.textXs, color: vars.muted,
});
export const dialTrack = style({ fill: "none", strokeWidth: "3", stroke: vars.neutralBg });
export const dialFill = style({
  fill: "none", strokeWidth: "3", stroke: vars.subtle, strokeLinecap: "round",
  selectors: {
    [`${dial}[data-level="amber"] &`]: { stroke: vars.amber },
    [`${dial}[data-level="red"] &`]: { stroke: vars.red },
  },
});
globalStyle(`${dial} text`, { fontSize: "10px", fontWeight: "600", fill: vars.text, fontVariantNumeric: "tabular-nums" });
globalStyle(`${dial}[data-level="amber"] text`, { fill: vars.amber });
globalStyle(`${dial}[data-level="red"] text`, { fill: vars.red });
export const warn = style({
  display: "grid", gap: "4px", marginLeft: "17px", fontSize: vars.textSm, fontWeight: "500",
});
globalStyle(`${warn} [data-level="amber"]`, { color: vars.amber });
globalStyle(`${warn} [data-level="red"]`, { color: vars.red });
export const cardVersions = style({ marginLeft: "17px", selectors: { "&:empty": { display: "none" } } });
export const cardFoot = style({
  display: "flex", flexWrap: "wrap", gap: "0 12px", marginLeft: "17px", fontSize: vars.textXs, color: vars.muted,
});

/** This device's connection to the station: grey figures, coloured only when the core says one is off. */
export const net = style({
  display: "flex", flexWrap: "wrap", alignItems: "center", gap: "2px 14px", marginLeft: "17px",
  fontSize: vars.textSm, color: vars.muted, fontVariantNumeric: "tabular-nums",
});
globalStyle(`${net} b`, { fontWeight: "500", color: vars.text });
globalStyle(`${net} b[data-level="amber"]`, { color: vars.amber });
globalStyle(`${net} b[data-level="red"]`, { color: vars.red });
/** On the phone's cards: its two parts on lines of their own, under the rings. */
export const netStacked = style({ flexDirection: "column", alignItems: "flex-start", gap: "4px", marginLeft: "0", paddingTop: "10px", fontSize: "13px" });
export const netPart = style({ display: "flex", flexWrap: "wrap", alignItems: "center", gap: "2px 14px", minWidth: "0" });
export const spark = style({ marginLeft: "6px", verticalAlign: "middle", fill: "none", stroke: vars.subtle, strokeWidth: "1.3", strokeLinejoin: "round", strokeLinecap: "round" });
globalStyle(`${net} [data-level="amber"] ${spark}`, { stroke: vars.amber });
globalStyle(`${net} [data-level="red"] ${spark}`, { stroke: vars.red });
