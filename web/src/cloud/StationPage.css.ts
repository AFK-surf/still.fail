import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;

/** The sidebar's stations (StationsNav): adding one over them. */
export const navAdd = style({
  width: "100%", marginBottom: 6, border: 0, font: "inherit", textAlign: "left", cursor: "pointer",
  selectors: { "&:not(:hover)": { background: "none" } },
});
export const navList = style({ display: "grid", gap: 2 });
/** A station's row: two lines, its mark beside the first. */
export const row = style({ alignItems: "flex-start", padding: "7px 10px" });
export const rowMark = style({ flex: "none", display: "grid", placeItems: "center", width: 18, height: 20 });
export const rowText = style({ flex: 1, display: "grid", gap: 1, minWidth: 0 });
export const rowHead = style({ display: "flex", alignItems: "center", gap: 8, minWidth: 0 });
/** Its meters' boxes, a line of them (wrapping in a narrow sidebar). */
export const rowMeters = style({ display: "flex", flexWrap: "wrap", gap: 4, margin: "4px 0 2px" });
// Their edges in their own colour, not the row's muted icons' (Sidebar.css.ts).
globalStyle(`${rowMeters} svg`, { color: "inherit" });
// The words of a small box set by Inter's line sit a pixel high (more so its CJK name): measured, a pixel down centres them.
globalStyle(`${rowMeters} [role="img"] > span`, { top: 1 });
export const rowSub = style({ ...ellipsis, fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted });
/** How it is, at the end of its first line: short, and never cut (its name gives way). */
export const rowState = style({ flex: "none", display: "flex", alignItems: "center", gap: 5, marginLeft: "auto", fontSize: vars.textMeta, color: vars.muted, whiteSpace: "nowrap" });
export const busy = style({ color: vars.accentText });
/** A meter running low, at the row's end: in its level's colour, the one thing there in colour. */
export const low = style({
  selectors: { '&[data-level="amber"]': { color: vars.amber }, '&[data-level="red"]': { color: vars.red } },
});

/** The page's head (as the workspace's): how it is, its dot before it. */
export const status = style({ display: "inline-flex", alignItems: "center", gap: 6 });
export const headActions = style({ display: "flex", alignItems: "center", gap: 8, flex: "none" });
export const warn = style({ display: "grid", gap: 4, marginTop: -20, marginBottom: 28, fontSize: vars.textUi, fontWeight: "500" });
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
