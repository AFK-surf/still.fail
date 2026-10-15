import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { btn } from "../styles/controls.css.ts";
import { cardLook } from "../styles/pages.css.ts";
import { TEXT_IN, inner, innerShape } from "../styles/align.ts";

export const name = style({
  padding: "0", border: "0", background: "none", font: "inherit", cursor: "pointer",
  selectors: { "&:hover": { textDecoration: "underline", textUnderlineOffset: "3px" } },
  fontSize: vars.textBody, fontWeight: "600", color: vars.text, minWidth: "0",
  overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const state = style({ fontSize: vars.textUi, color: vars.muted, whiteSpace: "nowrap" });
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
  display: "grid", gap: "4px", marginLeft: "17px", fontSize: vars.textUi, fontWeight: "500",
});
globalStyle(`${warn} [data-level="amber"]`, { color: vars.amber });
globalStyle(`${warn} [data-level="red"]`, { color: vars.red });
export const cardVersions = style({ marginLeft: "17px", selectors: { "&:empty": { display: "none" } } });
export const cardFoot = style({
  display: "flex", flexWrap: "wrap", gap: "0 12px", marginLeft: "17px", fontSize: vars.textMeta, color: vars.muted,
});

/** This device's connection to the station: grey figures, coloured only when the core says one is off. How it goes
 * on the left, the rates each way in columns on the right. */
export const net = style({
  display: "flex", alignItems: "center", gap: "14px", marginLeft: "17px",
  selectors: { "&[data-flush]": { marginLeft: "0" } },
  fontSize: vars.textUi, color: vars.muted, fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap",
});
globalStyle(`${net} b`, { fontWeight: "500", color: vars.text });
globalStyle(`${net} b[data-level="amber"]`, { color: vars.amber });
globalStyle(`${net} b[data-level="red"]`, { color: vars.red });
/** On the phone's cards: under the rings, the rates pushed to the right. */
export const netStacked = style({ marginLeft: "0", paddingTop: "10px", fontSize: vars.textUi });
/** How it goes: as wide as it says on the phone, room kept for it on a wide card, so the rates stay put. */
export const netPart = style({ display: "flex", flexDirection: "column", gap: "2px", minWidth: "0", flex: "0 1 14em", selectors: { [`${netStacked} &`]: { flex: "1 1 0" } } });
export const netLine = style({ display: "flex", gap: "8px", minWidth: "0" });
globalStyle(`${netLine} > *:last-child`, { minWidth: "0", overflow: "hidden", textOverflow: "ellipsis" });
/** Each way's latency, in the tip over how it goes: a row a way, the one in use in full colour. */
export const ways = style({ display: "grid", gridTemplateColumns: "auto auto auto", columnGap: "12px", rowGap: "3px", fontVariantNumeric: "tabular-nums" });
export const waysTitle = style({ gridColumn: "1 / -1", opacity: 0.7, marginBottom: "2px" });
export const way = style({ display: "contents", opacity: 0.75, selectors: { "&[data-current]": { opacity: 1, fontWeight: "600" } } });
export const netRates = style({ display: "grid", gridTemplateColumns: "auto 9.5ch minmax(7.5ch, auto)", columnGap: "5px", rowGap: "2px", alignItems: "baseline", flex: "none" });

/** The machine on its own page: what it is, what is left of it large, the connection, then the rest a quiet row each. */
export const machine = style({ display: "grid", gap: "16px", justifyItems: "start", minWidth: "0" });
export const machineNote = style({ fontSize: vars.textUi, color: vars.muted });
/** The rest of a machine, as a session's details are written (ChatPage.css.ts sessionDetails): small, a label beside
 * each, the labels quieter. On the phone, a size up. */
export const hostDetails = style({
  display: "grid", gridTemplateColumns: "auto minmax(0, 1fr)", gap: "8px 14px", alignItems: "baseline", margin: "0",
  fontSize: vars.textMeta, lineHeight: vars.leadingMeta, color: vars.muted, overflowWrap: "anywhere",
  selectors: { "&[data-phone]": { fontSize: vars.textUi, lineHeight: vars.leadingUi, gap: "8px 16px" } },
});
globalStyle(`${hostDetails} dt`, { color: vars.subtle });
globalStyle(`${hostDetails} dd`, { margin: "0" });

/** The card over a station's name in a chat's bar (StationPeek). */
export const peek = style({ display: "flex", flexDirection: "column", gap: "8px", minWidth: "0" });
export const peekHead = style({ display: "flex", alignItems: "center", gap: "8px", minWidth: "0" });
export const peekName = style({ flex: "1", fontWeight: "600", color: vars.text, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", minWidth: "0" });
export const peekLine = style({ fontSize: vars.textMeta, color: vars.muted, overflowWrap: "anywhere" });
/** What it is over what it has: a line each. */
export const peekLines = style({ display: "flex", flexDirection: "column", gap: "2px", fontSize: vars.textMeta, color: vars.muted });
/** One fact of a line: kept whole, the line breaking only between facts. */
export const peekPart = style({ whiteSpace: "nowrap" });
/** Its load and its connection: each set off from the one above by room, no line. */
export const peekSection = style({ paddingTop: "4px" });
export const peekNet = style({ display: "grid", gap: "4px", fontSize: vars.textMeta, color: vars.muted, fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" });
globalStyle(`${peekNet} b`, { fontWeight: "500", color: vars.text });
globalStyle(`${peekNet} b[data-level="amber"]`, { color: vars.amber });
globalStyle(`${peekNet} b[data-level="red"]`, { color: vars.red });
export const peekNetHead = style({ display: "flex", gap: "8px", color: vars.text });
/** ↑ and ↓ a row each: arrow, rate, and what went that way pushed to the right. */
export const peekRates = style({ display: "grid", gridTemplateColumns: "auto 1fr auto", columnGap: "8px", rowGap: "2px", alignItems: "baseline" });
/** Its settings, as a row that reads as one to click: the words and a chevron, a tint under it on hover. A row of the
 * card (Hover.css.ts `card`, padded 6 as a menu): at its padding, its words in by its own, its corner the card's less 6. */
export const peekLink = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", padding: `5px ${TEXT_IN}px`,
  borderRadius: inner, cornerShape: innerShape,
  fontSize: vars.textMeta, color: vars.muted, textDecoration: "none",
  selectors: { "&:hover": { color: vars.text, background: vars.hover } },
});

