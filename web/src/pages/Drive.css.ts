import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { page as settingsPage, pageHead, pageNarrow } from "../styles/pages.css.ts";

/** Not a settings page: its head up by the window's top, its name level with the sidebar's first row, the files close under it. */
export const page = style({ position: "relative", selectors: { [`${settingsPage}&`]: { paddingTop: "12px" } } });
globalStyle(`${page} > ${pageHead}`, { marginBottom: "12px" });
// As wide as the page, up to where a row's name and its size and time still read as one line.
globalStyle(`${page} > *`, { maxWidth: "1120px" });

export const headText = style({ minWidth: "0", display: "grid", gap: "4px" });
globalStyle(`${headText} h1`, { margin: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** Where the folder is: the station, the drive, the folders above it, each a click back to. */
export const crumbs = style({
  display: "flex", alignItems: "center", gap: "4px", flexWrap: "wrap", minWidth: "0", color: vars.muted, fontSize: vars.textMeta,
});
export const crumb = style({ display: "inline-flex", alignItems: "center", gap: "4px" });
globalStyle(`${crumbs} button`, {
  padding: "0", border: "0", background: "none", color: vars.muted, font: "inherit", cursor: "pointer",
  textDecoration: "underline", textDecorationColor: "transparent", textUnderlineOffset: "3px",
});
globalStyle(`${crumbs} button:hover`, { color: vars.text, textDecorationColor: "currentColor" });
/** Under the folder's name: whose it is, what is in it. */
export const headMeta = style({ margin: "0", color: vars.muted, fontSize: vars.textMeta });
export const actions = style({ flex: "none", display: "flex", alignItems: "center", gap: "6px" });
const turn = keyframes({ to: { transform: "rotate(360deg)" } });
/** Refresh turns while the folder is read again. */
export const spin = style({ display: "contents" });
globalStyle(`${spin}[data-on] svg`, { animation: `${turn} 900ms linear infinite` });

/** The entries: rows on the page, a row's ground on hover; files dropped on it go into the folder. */
export const list = style({ position: "relative", display: "grid", gap: "2px", minHeight: "200px", borderRadius: vars.rCard, cornerShape: vars.cornerShape });
// As the settings lists: rows reaching a little past the column, their text in line with the page's.
globalStyle(`${pageNarrow} > ${list}`, { maxWidth: "none", marginLeft: "max(-12px, calc(50% - 392px))", marginRight: "max(-12px, calc(50% - 392px))" });
/** A line about the folders where there are none to show (none lent yet, or none matching). */
export const count = style({ margin: "0 12px 8px", color: vars.muted, fontSize: vars.textMeta });

export const entry = style({
  position: "relative", borderRadius: vars.rField, cornerShape: vars.cornerShape, transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover, &:has([data-state=open])": { background: vars.list },
    "&[data-busy]": { opacity: ".6" },
  },
});
export const row = style({
  display: "grid", gridTemplateColumns: "20px minmax(0, 1fr) 96px 104px 36px", alignItems: "center", columnGap: "12px",
  boxSizing: "border-box", width: "100%", minHeight: "44px", padding: "8px 12px", border: "0", background: "none", color: vars.text,
  textAlign: "left", fontSize: vars.textUi, cursor: "pointer", borderRadius: vars.rField, cornerShape: vars.cornerShape,
  selectors: {
    "span&": { cursor: "default" },
    "&:disabled": { cursor: "default" },
    // A folder lent, or one of the station's to pick: no columns of sizes and times.
    [`${list} > &, [role=dialog] &`]: { gridTemplateColumns: "20px minmax(0, 1fr) 16px", minHeight: "44px" },
    [`${list} > &:hover, [role=dialog] &:hover`]: { background: vars.list },
  },
});
export const icon = style({ color: vars.muted, flex: "none" });
export const text = style({ display: "grid", gap: "2px", minWidth: "0" });
export const name = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const meta = style({ color: vars.muted, fontSize: vars.textMeta, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const trouble = style({ color: vars.muted, fontSize: vars.textMeta });
globalStyle(`${trouble} b`, { color: vars.red, fontWeight: "500" });
export const size = style({ color: vars.muted, fontSize: vars.textMeta, textAlign: "right", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" });
export const time = style({ color: vars.muted, fontSize: vars.textMeta, textAlign: "right", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" });
/** The row's …, at its end: shown on hover (always where nothing hovers). */
export const more = style({
  position: "absolute", right: "6px", top: "50%", transform: "translateY(-50%)", display: "flex", alignItems: "center", gap: "2px",
  opacity: "0", transition: `opacity ${vars.dur} ${vars.easeOut}`,
  selectors: {
    [`${entry}:hover &, ${entry}:focus-within &, &:has([data-state=open]), &[data-shown], ${entry}[data-busy] &`]: { opacity: "1" },
  },
  "@media": { "(hover: none)": { opacity: "1" } },
});

/** Going up: how far it has got, its size, in the size and time columns. */
export const progressCell = style({ gridColumn: "3 / 5", display: "grid", gridTemplateColumns: "minmax(0, 1fr) auto", alignItems: "center", gap: "10px" });
export const progress = style({
  position: "relative", display: "block", height: "2px", borderRadius: "1px", overflow: "hidden", background: `color-mix(in srgb, ${vars.text} 10%, transparent)`,
});
globalStyle(`${progress} > span`, { position: "absolute", inset: "0", background: vars.accent, transformOrigin: "left", transition: "transform 200ms linear" });
export const ask = style({ gridColumn: "3 / 6", display: "flex", alignItems: "center", justifyContent: "flex-end", gap: "4px", color: vars.muted, fontSize: vars.textMeta, paddingRight: "64px" });
export const failed = style({ gridColumn: "3 / 6", color: vars.red, fontSize: vars.textMeta, textAlign: "right", paddingRight: "64px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });

export const problem = style({ display: "grid", justifyItems: "start", gap: "10px", padding: "12px" });
export const empty = style({ display: "grid", justifyItems: "center", gap: "12px", padding: "56px 24px", color: vars.muted, textAlign: "center", fontSize: vars.textUi });
globalStyle(`${empty} p`, { margin: "0" });

/** Files over the list: where they will go, over it. */
export const drop = style({
  position: "absolute", inset: "0", display: "grid", placeContent: "center", justifyItems: "center", gap: "8px", pointerEvents: "none",
  borderRadius: vars.rCard, cornerShape: vars.cornerShape, background: `color-mix(in srgb, ${vars.canvas} 82%, transparent)`,
  boxShadow: `inset 0 0 0 2px color-mix(in srgb, ${vars.accent} 60%, transparent)`, color: vars.text, fontSize: vars.textUi,
});

export const rootsList = style({ display: "grid", gap: "4px", maxHeight: "50vh", overflowY: "auto" });
export const rootLine = style({ display: "grid", gridTemplateColumns: "16px minmax(0, 1fr) auto", alignItems: "center", gap: "12px", padding: "8px 4px" });
/** The way to where the picker is (crumbs), and the filter at its end. */
export const pickerPath = style({ display: "flex", alignItems: "center", gap: "12px", marginBottom: "10px", minWidth: "0", minHeight: "36px", fontSize: vars.textMeta, color: vars.muted });
export const pickerCrumb = style({ display: "inline-flex", alignItems: "center", gap: "2px", flex: "none" });
globalStyle(`${pickerCrumb} button`, { padding: "3px 4px", border: "0", borderRadius: "6px", background: "none", color: "inherit", font: "inherit", cursor: "pointer" });
globalStyle(`${pickerCrumb} button:hover`, { color: vars.text });
globalStyle(`${pickerCrumb} button[data-last]`, { color: vars.text, fontWeight: 600, cursor: "default" });
/** The crumbs take what the filter leaves, and scroll sideways rather than wrap (the deepest kept in view). */
export const pickerCrumbs = style({ display: "flex", alignItems: "center", gap: "2px", minWidth: "0", flex: "1", overflowX: "auto", scrollbarWidth: "none", whiteSpace: "nowrap" });
export const pickerFilter = style({ width: "200px", flex: "none" });
/** A folder the station may not read, opened: why, and where to let it. */
export const pickerShut = style({ display: "grid", justifyItems: "center", alignContent: "center", gap: "12px", height: "100%", padding: "0 24px", color: vars.muted, textAlign: "center", fontSize: vars.textUi, lineHeight: "1.5" });
globalStyle(`${pickerShut} p`, { margin: "0", maxWidth: "380px" });
/** The usual places on the left, the folders where it is on the right. */
export const picker = style({ display: "grid", gridTemplateColumns: "180px minmax(0, 1fr)", gap: "12px", height: "min(52vh, 420px)", margin: "0 -8px" });
export const pickerPlaces = style({ display: "grid", alignContent: "start", gap: "2px", overflowY: "auto" });
export const pickerHead = style({ padding: "4px 8px", fontSize: vars.textCaption, color: vars.muted });
export const pickerList = style({ display: "grid", alignContent: "start", gap: "2px", overflowY: "auto" });
export const pickRow = style({
  display: "grid", gridTemplateColumns: "18px minmax(0, 1fr) auto", alignItems: "center", columnGap: "10px", boxSizing: "border-box", width: "100%",
  minHeight: "40px", padding: "6px 10px", border: "0", background: "none", color: vars.text, textAlign: "left", fontSize: vars.textUi, cursor: "pointer",
  borderRadius: vars.rField, cornerShape: vars.cornerShape,
  selectors: { "&:hover": { background: vars.list }, "&[data-here]": { background: vars.list, fontWeight: 600 } },
});
globalStyle(`${pickRow} > span:last-child:not(:nth-child(2))`, { fontSize: vars.textCaption, whiteSpace: "nowrap" });

/** A file opened: the reader or the player fills the pane. */
export const opened = style({ position: "relative", flex: "1", minHeight: "0", overflow: "hidden" });
export const dark = style({ background: "#000" });
export const openedNote = style({ padding: "40px" });
