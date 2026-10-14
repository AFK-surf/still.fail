// The rail at the wide screen's left (Rail.tsx): a column of the sidebar's own ground, the places as icons.
import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

const wide = "(min-width: 701px)";
const narrow = "(max-width: 700px)";
/** The rail's width (styles/shell.css.ts puts it in the grid). */
export const RAIL_W = 56;

export const rail = style({
  display: "flex", flexDirection: "column", alignItems: "center", gap: 6, padding: "0 0 12px", background: vars.sidebar,
  WebkitUserSelect: "none", userSelect: "none",
  "@media": { [narrow]: { display: "none" } },
});
/** Level with the sidebar's brand row; in the desktop app, the row the window's buttons are in, which drags it. */
export const top = style({
  flex: "none", height: 48,
  selectors: { "[data-desktop] &": { height: 44, alignSelf: "stretch", WebkitAppRegion: "drag" } },
});
export const grow = style({ flex: 1 });

export const item = style({
  position: "relative", display: "grid", placeItems: "center", width: 38, height: 38, padding: 0, border: 0,
  borderRadius: `calc(12px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: "none", color: vars.muted,
  cursor: "pointer", transition: `background ${vars.dur} ${vars.easeOut}, color ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
    "&[data-on]": { background: vars.selected, color: vars.text },
  },
});
/** 奏, the word, its size the icons' (vars.textTitle is the nearest of the type sizes). */
export const zou = style({ fontSize: vars.textTitle, lineHeight: "20px", fontWeight: 600 });
/** What waits on a place: a count on the icon's corner, cut out of the rail's ground. */
export const count = style({
  position: "absolute", top: 2, right: 0, minWidth: 16, height: 16, padding: "0 4px", boxSizing: "border-box", borderRadius: 8,
  background: vars.red, color: "#fff", fontSize: vars.textCaption, lineHeight: "16px", fontWeight: 600, textAlign: "center",
  fontVariantNumeric: "tabular-nums", boxShadow: `0 0 0 2px ${vars.sidebar}`,
});

/** The workspace in view, its first letter; its menu is the switcher's (cloud/workspace.tsx). */
export const workspace = style({
  position: "relative", display: "grid", placeItems: "center", width: 30, height: 30, marginTop: 4, padding: 0, border: 0,
  borderRadius: `calc(9px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: vars.text, color: vars.sidebar,
  fontSize: vars.textUi, fontWeight: 600, cursor: "pointer",
});
export const mark = style({ position: "absolute", top: -4, right: -4, display: "flex", padding: 2, borderRadius: "50%", background: vars.sidebar });

/** What the rail holds, on a narrow screen (no rail there) in the sidebar's foot as before. */
export const narrowOnly = style({ "@media": { [wide]: { display: "none" } } });

/** The places the stations lend (FilesNav): under each station's name, its folders. */
export const station = style({
  display: "flex", alignItems: "center", gap: 6, margin: "14px 10px 4px", fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted,
  selectors: { "&:first-child": { marginTop: 6 } },
});
export const dot = style({
  width: 6, height: 6, borderRadius: "50%", background: vars.subtle, flex: "none",
  selectors: { "&[data-online]": { background: vars.online } },
});
