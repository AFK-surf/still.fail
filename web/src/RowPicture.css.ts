// RowPicture.tsx: who stands beside a chat row's title. The row sets `--mark-around`, its ground: the
// gaps between overlapping pictures are cut in it.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

/** A person, round; who started the chat ringed in ink, a gap of the row's ground between. */
export const face = style({
  // One cell the face's own size: an auto row would grow to the letter's line (18px in a 16px face), off its ring's centre.
  display: "inline-grid", gridTemplate: "100% / 100%", flex: "none", borderRadius: "50%", overflow: "hidden", position: "relative",
  selectors: { "&[data-starter]": { overflow: "visible" } },
});
globalStyle(`${face} > *`, { width: "100% !important", height: "100% !important", borderRadius: "50% !important", display: "grid", placeItems: "center" });
globalStyle(`${face}[data-starter]::after`, {
  // Whole pixels, no half ones to blur: 1px of ground between face and ring, the ring 1px from 1px to 2px out.
  content: "\"\"", position: "absolute", inset: -2, borderRadius: "50%", pointerEvents: "none",
  boxShadow: `inset 0 0 0 1px ${vars.text}`,
});
globalStyle(`${face}[data-starter] > *`, { boxShadow: `0 0 0 1px var(--mark-around)` });
/** Small at the title's end: a row of pictures overlapping a little. */
export const aside = style({ display: "inline-flex", alignItems: "center", flex: "none", paddingLeft: 2 });
globalStyle(`${aside} > * + *`, { marginLeft: -3 });
globalStyle(`${aside} > ${face}:not([data-starter])`, { boxShadow: `0 0 0 1px var(--mark-around)` });
// Who started it on top of the others: its ring whole.
globalStyle(`${aside} > ${face}[data-starter]`, { zIndex: 1, marginRight: 1 });
export const asideAgent = style({ display: "inline-flex", alignItems: "center", gap: 1, minWidth: 16, height: 16, justifyContent: "center", color: vars.muted });
globalStyle(`${asideAgent} + ${asideAgent}`, { marginLeft: 4 });
export const asideMore = style({ marginLeft: "3px !important", fontSize: vars.textLabel, color: vars.muted, fontVariantNumeric: "tabular-nums" });
