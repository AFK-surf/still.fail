import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

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

/** What is left of the machine large, then this device's connection to it. */
export const machine = style({ display: "grid", gap: 18, justifyItems: "start", minWidth: 0 });
/** Its agents, counted as the dials above are written: the number large, what it counts under it. */
export const figures = style({ display: "flex", flexWrap: "wrap", gap: "12px 36px" });
export const figure = style({ display: "grid", justifyItems: "start", gap: 2, minWidth: 96 });
export const figureNumber = style({
  fontSize: vars.textDisplay, fontWeight: "600", lineHeight: "1.15", letterSpacing: "-0.02em", color: vars.text, fontVariantNumeric: "tabular-nums",
  selectors: { "&[data-accent]": { color: vars.accentText } },
});
export const figureLabel = style({ fontSize: vars.textUi, fontWeight: "500", color: vars.text });
export const note = style({ margin: "10px 0 0", fontSize: vars.textUi, color: vars.muted });
/** A folder lent: its name, then where it is, quiet, cut at the end (the chevron stays). */
export const folder = style({ minHeight: 44 });
export const folderName = style({ flex: "none", fontWeight: "500", maxWidth: "50%", ...ellipsis });
export const folderPath = style({ flex: 1, ...ellipsis, color: vars.muted });
