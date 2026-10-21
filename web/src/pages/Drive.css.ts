import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { page as settingsPage, pageHead, pageNarrow } from "../styles/pages.css.ts";
import { neg, outset } from "@stillfail/ui/styles/align.ts";
import { STILL, stillLoop } from "@stillfail/ui/styles/still.ts";

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
globalStyle(`${crumbs} ${crumb} button`, {
  padding: "0", border: "0", background: "none", color: vars.muted, font: "inherit", cursor: "pointer",
  textDecoration: "underline", textDecorationColor: "transparent", textUnderlineOffset: "3px",
});
globalStyle(`${crumbs} ${crumb} button:hover`, { color: vars.text, textDecorationColor: "currentColor" });
/** Under the folder's name: whose it is, what is in it. */
export const headMeta = style({ margin: "0", color: vars.muted, fontSize: vars.textMeta });
export const actions = style({ flex: "none", display: "flex", alignItems: "center", gap: "6px" });
const turn = keyframes({ to: { transform: "rotate(360deg)" } });
/** Pin: in the accent while the folder shown is pinned. */
export const pin = style({ display: "contents" });
globalStyle(`${pin}[data-on] button`, { color: vars.accent });
/** Refresh turns while the folder is read again. */
export const spin = style({ display: "contents" });
globalStyle(`${spin}[data-on] svg`, { animation: `${turn} 900ms linear infinite` });
// With motion reduced, slower, as a spinner (@stillfail/ui spinner.css.ts).
globalStyle(`${STILL} ${spin}[data-on] svg`, stillLoop("turn"));

/** The entries: rows on the page, a row's ground on hover; files dropped on it go into the folder. */
export const list = style({ position: "relative", display: "grid", gap: "2px", minHeight: "200px", borderRadius: vars.rCard, cornerShape: vars.cornerShape, outline: "none" });
// As the settings lists: rows reaching a little past the column, their text in line with the page's.
globalStyle(`${pageNarrow} > ${list}`, { maxWidth: "none", marginLeft: `max(${neg(12)}, calc(50% - 392px))`, marginRight: `max(${neg(12)}, calc(50% - 392px))` });
/** A line about the folders where there are none to show (none lent yet, or none matching). */
export const count = style({ margin: "0 12px 8px", color: vars.muted, fontSize: vars.textMeta });

export const entry = style({
  position: "relative", borderRadius: vars.rField, cornerShape: vars.cornerShape, transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover, &:has([data-state=open])": { background: vars.list },
    // Chosen (a press, the keys), and in columns the folder open on the way to the next column.
    "&:has(> [data-chosen])": { background: vars.selected },
    "&:has(> [data-along])": { background: vars.list },
    "&[data-busy]": { opacity: ".6" },
    // A folder something dragged over it would go into.
    "&[data-drop]": { background: vars.accentBg, boxShadow: `inset 0 0 0 1px ${vars.accent}` },
  },
});
export const row = style({
  display: "grid", gridTemplateColumns: "20px minmax(0, 1fr) 96px 104px 36px", alignItems: "center", columnGap: "12px",
  boxSizing: "border-box", width: "100%", minHeight: "44px", padding: "8px 12px", border: "0", background: "none", color: vars.text,
  textAlign: "left", fontSize: vars.textUi, cursor: "pointer", borderRadius: vars.rField, cornerShape: vars.cornerShape,
  selectors: {
    "span&": { cursor: "default" },
    // What is chosen says where the keys are (its ground): no ring around it besides, as Finder draws none.
    "&:focus-visible": { outline: "none" },
    "&:disabled": { cursor: "default" },
    // In a chat's 文件 tab: narrow, the size alone.
    "&[data-compact]": { gridTemplateColumns: "18px minmax(0, 1fr) auto 28px", columnGap: "10px", minHeight: "36px", padding: "6px 10px" },
    // In a tree: in by its depth, its disclosure before its mark.
    "&[data-tree]": { gridTemplateColumns: "12px 20px minmax(0, 1fr) 96px 104px 36px", columnGap: "8px", paddingLeft: "calc(6px + var(--depth, 0) * 18px)" },
    "&[data-tree][data-compact]": { gridTemplateColumns: "12px 18px minmax(0, 1fr) auto 28px" },

    // A folder lent, or one of the station's to pick: no columns of sizes and times.
    [`${list} > &, [role=dialog] &`]: { gridTemplateColumns: "20px minmax(0, 1fr) 16px", minHeight: "44px" },
    [`${list} > &:hover, [role=dialog] &:hover`]: { background: vars.list },
  },
});
export const icon = style({ color: vars.muted, flex: "none" });
/** A tree's folder: › turning ⌄ as it opens. */
export const disclosure = style({ display: "grid", placeItems: "center", color: vars.muted, transition: `transform ${vars.dur} ${vars.easeOut}`, selectors: { "&[data-open]": { transform: "rotate(90deg)" } } });
export const text = style({ display: "grid", gap: "2px", minWidth: "0" });
export const name = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const meta = style({ color: vars.muted, fontSize: vars.textMeta, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const trouble = style({ color: vars.muted, fontSize: vars.textMeta });
globalStyle(`${trouble} b`, { color: vars.red, fontWeight: "500" });
export const size = style({ color: vars.muted, fontSize: vars.textMeta, textAlign: "right", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" });
export const time = style({ color: vars.muted, fontSize: vars.textMeta, textAlign: "right", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" });
/** How far in from a row's end its buttons sit: their corner is the row's less this (concentric). */
const MORE_IN = 6;
/** The row's …, at its end: shown on hover or the keys (not a click: it would stay on the row pressed), always where nothing hovers. */
export const more = style({
  position: "absolute", right: `${MORE_IN}px`, top: "50%", transform: "translateY(-50%)", display: "flex", alignItems: "center", gap: "2px",
  opacity: "0", transition: `opacity ${vars.dur} ${vars.easeOut}`,
  selectors: {
    [`${entry}:hover &, ${entry}:has(:focus-visible) &, &:has([data-state=open]), &[data-shown], ${entry}[data-busy] &`]: { opacity: "1" },
  },
  "@media": { "(hover: none)": { opacity: "1" } },
});
/** In columns, › on the folder open in the next column alone, where the … is: it gives way to it whenever the … shows. */
export const next = style({
  position: "absolute", right: `${MORE_IN}px`, top: "50%", transform: "translateY(-50%)", display: "grid", placeItems: "center",
  width: "24px", height: "24px", color: vars.muted, pointerEvents: "none", transition: `opacity ${vars.dur} ${vars.easeOut}`,
  selectors: {
    [`${entry}:hover > &, ${entry}:has(:focus-visible) > &, ${entry}[data-state=open] > &, ${entry}:has(${more} [data-state=open]) > &, ${entry}[data-busy] > &`]: { opacity: "0" },
  },
  "@media": { "(hover: none)": { display: "none" } },
});

// Its buttons concentric with the row's corner; a compact row's are smaller, as far in from its top as from its end.
globalStyle(`${more} button`, { borderRadius: `calc(${vars.rField} - ${MORE_IN}px)`, cornerShape: vars.cornerShape });
globalStyle(`${entry}:has([data-compact]) ${more} button`, { width: "24px", height: "24px" });

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
export const picker = style({ display: "grid", gridTemplateColumns: "180px minmax(0, 1fr)", gap: "12px", height: "min(52vh, 420px)", marginBlock: "0", ...outset(8) });
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
/** Why a folder to pick is not lent, under its name: the name keeps its room however narrow the column. */
export const pickNote = style({ color: vars.muted, fontSize: vars.textCaption, fontWeight: "400", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });

/**
 * A file opened: the reader or the player over the whole window, at the top, as a picture's or a PDF's preview is
 * (FilePreview.css.ts, 61): nothing of the app beside it (the folded sidebar's ground was another colour by its bar). In
 * the macOS app its bar's left end is the window's buttons' row: clear of them (`--m-top` for the bar floating in a
 * narrow window, the desktop's docked bar below).
 */
export const opened = style({
  position: "fixed", inset: "0", zIndex: "61", overflow: "hidden", background: vars.canvas,
  selectors: { ':root[data-desktop="inset"]:not([data-fullscreen]) &': { vars: { "--m-top": "30px" } } },
});
export const dark = style({ background: "#000" });
export const openedNote = style({ padding: "40px" });

/** The way a folder is shown, switched (DriveViews.tsx): three icon buttons in a quiet track, the one shown raised. */
export const views = style({ display: "inline-flex", alignItems: "center", gap: "2px", padding: "2px", borderRadius: "999px", background: `color-mix(in srgb, ${vars.text} 6%, transparent)` });
export const viewButton = style({
  display: "grid", placeItems: "center", width: "28px", height: "28px", padding: "0", border: "0", borderRadius: "999px", background: "none",
  color: vars.muted, cursor: "pointer", transition: `background ${vars.dur} ${vars.easeOut}, color ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { color: vars.text },
    "&[data-on]": { background: vars.canvas, color: vars.text, boxShadow: `0 0 2px ${vars.shadow}, 0 0 0 .5px ${vars.line}` },
  },
});
/** A tree's line about a folder not listed (being read, empty, refused): in by its depth, on the line its names start. */
export const treeNote = style({ margin: "0", padding: "8px 10px", paddingLeft: "calc(46px + var(--depth, 0) * 18px)", fontSize: vars.textMeta });
export const treeError = style({ color: vars.red });
/** Columns, a folder each, side by side; more than fit scroll sideways, the last kept in view. */
export const columns = style({ display: "flex", alignItems: "stretch", gap: "6px", minHeight: "0", overflowX: "auto", overscrollBehaviorX: "contain" });
/** A column and its edge, as wide as it is set (DriveViews.tsx ColumnsView). */
export const columnBox = style({ flex: "none", position: "relative", display: "grid", gridTemplateRows: "minmax(0, 1fr)", minHeight: "0" });
export const column = style({
  display: "grid", alignContent: "start", gap: "2px", minWidth: "0", overflowY: "auto", borderRadius: vars.rField, cornerShape: vars.cornerShape,
  selectors: { "&[data-drop]": { background: vars.accentBg } },
});
/** Its edge's line in the middle of the gap to the next column (ui's resizeHandle: the line 3 in, 7 wide); the last's on its own edge. */
export const columnEdge = style({
  selectors: {
    [`${columnBox} > &[data-edge]`]: { right: "-7px" },
    [`${columnBox}:last-child > &[data-edge]`]: { right: "-4px" },
  },
});
/** A name being changed in place, where the name was. */
export const nameField = style({
  minWidth: "0", width: "100%", boxSizing: "border-box", margin: `${neg(3)} 0`, padding: "2px 6px", border: `1px solid ${vars.accent}`, borderRadius: vars.rOption,
  cornerShape: vars.cornerShape, background: vars.canvas, color: vars.text, font: "inherit", outline: "none",
});
/** Over a list, its columns' names, each ordering it. */
export const listHead = style({
  display: "grid", gridTemplateColumns: "20px minmax(0, 1fr) 96px 104px 36px", columnGap: "12px", padding: "0 12px 4px", color: vars.muted, fontSize: vars.textMeta,
});
globalStyle(`${listHead} button`, { display: "inline-flex", alignItems: "center", gap: "4px", padding: "0", border: "0", background: "none", color: "inherit", font: "inherit", cursor: "pointer", textAlign: "left" });
globalStyle(`${listHead} button:nth-of-type(n+2)`, { justifySelf: "end" });
globalStyle(`${listHead} button:hover, ${listHead} button[data-on]`, { color: vars.text });
// On the files' page, columns as tall as the window leaves them: each scrolls on its own.
globalStyle(`${list}[data-view="columns"]`, { display: "block", height: "calc(100dvh - 150px)", minHeight: "240px" });
globalStyle(`${list}[data-view="columns"] > ${columns}`, { height: "100%" });

/** The list, and the preview beside it when it shows (DrivePane.tsx). */
export const withPane = style({ display: "flex", alignItems: "flex-start", gap: "0", minWidth: "0" });
globalStyle(`${withPane} > :first-child`, { flex: "1", minWidth: "0" });
