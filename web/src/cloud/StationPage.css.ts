import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { CARD_BUTTON, CARD_PAD } from "../styles/pages.css.ts";

const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;

/** A station's row in the sidebar (StationsNav): its meters' boxes, a line of them (wrapping in a narrow sidebar). */
export const rowMeters = style({ display: "flex", flexWrap: "wrap", gap: 4, margin: "4px 0 2px" });
export const busy = style({ color: vars.accentText });
/** A meter running low, at the row's end: in its level's colour, the one thing there in colour. */
export const low = style({
  selectors: { '&[data-level="amber"]': { color: vars.amber }, '&[data-level="red"]': { color: vars.red } },
});

/** The page's head (as the workspace's): how it is, its dot before it. */
export const status = style({ display: "inline-flex", alignItems: "center", gap: 6 });
export const headActions = style({ display: "flex", alignItems: "center", gap: 8, flex: "none" });
export const warn = style({ display: "grid", gap: 4, marginTop: 6, fontSize: vars.textUi, fontWeight: "500" });
globalStyle(`${warn} [data-level="amber"]`, { color: vars.amber });
globalStyle(`${warn} [data-level="red"]`, { color: vars.red });

/** The page's parts to pick from, under its head: as wide as their names, at the column's start. */
export const parts = style({ display: "flex", marginBottom: 24 });
/** What is left of the machine large, then this device's connection to it. */
export const machine = style({ display: "grid", gap: 18, justifyItems: "start", minWidth: 0 });
/** What its agents' processes take, under how this device reaches it: quiet, as the network's labels. */
/** Its 进程: a line on what is counted over the page. */
export const processes = style({ display: "grid", gap: 16, minWidth: 0 });
export const memory = style({ margin: 0, fontSize: vars.textUi, color: vars.muted });
export const note = style({ margin: "10px 0 0", fontSize: vars.textUi, color: vars.muted });
/** A folder lent: its name, then where it is, quiet, cut at the end (the chevron stays). */
export const folder = style({ minHeight: 44 });
export const folderName = style({ flex: "none", fontWeight: "500", maxWidth: "50%", ...ellipsis });
export const folderPath = style({ flex: 1, ...ellipsis, color: vars.muted });
/** The station's variables' field, at the top of a card with a button at its foot: its corners concentric with the card's. */
export const envField = style({ selectors: { "&&": { borderRadius: `calc(${CARD_PAD + CARD_BUTTON / 2}px * ${vars.cornerScale} - ${CARD_PAD}px)` } } });
