import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { btn } from "../styles/controls.css.ts";
import { cardLook } from "../styles/pages.css.ts";

export const name = style({
  padding: "0", border: "0", background: "none", font: "inherit", cursor: "pointer",
  selectors: { "&:hover": { textDecoration: "underline", textUnderlineOffset: "3px" } },
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
  display: "grid", gap: "10px", padding: "14px 16px", ...cardLook,
});
export const cardHead = style({ display: "flex", alignItems: "center", gap: "10px", minWidth: "0" });
export const cardTitle = style({ flex: "1", display: "flex", alignItems: "baseline", gap: "10px", minWidth: "0" });
export const warn = style({
  display: "grid", gap: "4px", marginLeft: "17px", fontSize: vars.textSm, fontWeight: "500",
});
globalStyle(`${warn} [data-level="amber"]`, { color: vars.amber });
globalStyle(`${warn} [data-level="red"]`, { color: vars.red });
export const cardVersions = style({ marginLeft: "17px", selectors: { "&:empty": { display: "none" } } });
export const cardFoot = style({
  display: "flex", flexWrap: "wrap", gap: "0 12px", marginLeft: "17px", fontSize: vars.textXs, color: vars.muted,
});

/** This device's connection to the station: grey figures, coloured only when the core says one is off. How it goes
 * on the left, the rates each way in columns on the right. */
export const net = style({
  display: "flex", alignItems: "center", gap: "14px", marginLeft: "17px",
  fontSize: vars.textSm, color: vars.muted, fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap",
});
globalStyle(`${net} b`, { fontWeight: "500", color: vars.text });
globalStyle(`${net} b[data-level="amber"]`, { color: vars.amber });
globalStyle(`${net} b[data-level="red"]`, { color: vars.red });
/** On the phone's cards: under the rings, the rates pushed to the right. */
export const netStacked = style({ marginLeft: "0", paddingTop: "10px", fontSize: "13px" });
/** How it goes: as wide as it says on the phone, room kept for it on a wide card, so the rates stay put. */
export const netPart = style({ display: "flex", flexDirection: "column", gap: "2px", minWidth: "0", flex: "0 1 14em", selectors: { [`${netStacked} &`]: { flex: "1 1 0" } } });
export const netLine = style({ display: "flex", gap: "8px", minWidth: "0" });
globalStyle(`${netLine} > *:last-child`, { minWidth: "0", overflow: "hidden", textOverflow: "ellipsis" });
/** Each way's latency, in the tip over how it goes: a row a way, the one in use in full colour. */
export const ways = style({ display: "grid", gridTemplateColumns: "auto auto auto", columnGap: "12px", rowGap: "3px", fontVariantNumeric: "tabular-nums" });
export const waysTitle = style({ gridColumn: "1 / -1", opacity: 0.7, marginBottom: "2px" });
export const way = style({ display: "contents", opacity: 0.75, selectors: { "&[data-current]": { opacity: 1, fontWeight: "600" } } });
export const netRates = style({ display: "grid", gridTemplateColumns: "auto 9.5ch minmax(7.5ch, auto)", columnGap: "5px", rowGap: "2px", alignItems: "baseline", flex: "none" });

export const details = style({ display: "grid", gap: "24px" });
export const detailSection = style({ display: "grid", gap: "10px", fontSize: vars.textSm, color: vars.muted, overflowWrap: "anywhere" });
export const detailTitle = style({ margin: "0", fontSize: vars.textBody, fontWeight: "600", color: vars.text });
