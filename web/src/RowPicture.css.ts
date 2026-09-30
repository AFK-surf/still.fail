// RowPicture.tsx: a chat row's picture and what stands beside its title. The row sets `--mark-around`, its ground: the
// gaps between overlapping pictures are cut in it.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

/** A person, round; who started the chat ringed in ink, a gap of the row's ground between. */
export const face = style({
  display: "inline-grid", flex: "none", borderRadius: "50%", overflow: "hidden", position: "relative",
  selectors: { "&[data-starter]": { overflow: "visible" } },
});
globalStyle(`${face} > *`, { width: "100% !important", height: "100% !important", borderRadius: "50% !important", display: "grid", placeItems: "center" });
globalStyle(`${face}[data-starter]::after`, {
  content: "\"\"", position: "absolute", inset: -2, borderRadius: "50%", pointerEvents: "none",
  boxShadow: `inset 0 0 0 1.5px ${vars.text}`,
});
globalStyle(`${face}[data-starter] > *`, { boxShadow: `0 0 0 1px var(--mark-around)` });
/** One of a picture's cells, placed by Cluster; the one overlapping another cut from it by a gap. */
export const cell = style({ position: "absolute", display: "grid", placeItems: "center", lineHeight: 1 });
globalStyle(`${cell}[data-overlap] > *`, { boxShadow: "0 0 0 1.5px var(--mark-around)", borderRadius: "50%" });
/** How many more than are drawn: a cell of its own, round, quiet. */
export const more = style({
  width: "100%", height: "100%", borderRadius: "50%", display: "grid", placeItems: "center", lineHeight: 1, overflow: "hidden",
  fontWeight: 600, fontVariantNumeric: "tabular-nums", letterSpacing: -0.3,
  background: `color-mix(in srgb, ${vars.text} 10%, var(--mark-around))`, color: vars.muted,
});
/** What does not lead, small at the title's end: a row of pictures overlapping a little. */
export const aside = style({ display: "inline-flex", alignItems: "center", flex: "none", paddingLeft: 2 });
globalStyle(`${aside} > * + *`, { marginLeft: -3 });
globalStyle(`${aside} > ${face}:not([data-starter])`, { boxShadow: `0 0 0 1.5px var(--mark-around)` });
// Who started it on top of the others: its ring whole.
globalStyle(`${aside} > ${face}[data-starter]`, { zIndex: 1, marginRight: 1 });
export const asideAgent = style({ display: "inline-flex", alignItems: "center", gap: 1, minWidth: 16, height: 16, justifyContent: "center", color: vars.muted });
globalStyle(`${asideAgent} + ${asideAgent}`, { marginLeft: 4 });
export const asideMore = style({ marginLeft: "3px !important", fontSize: vars.textXs, color: vars.muted, fontVariantNumeric: "tabular-nums" });
