import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { pageHead } from "../styles/pages.css.ts";
import { IN, inner } from "@stillfail/ui/styles/align.ts";
import { headText } from "./Drive.css.ts";

/** The files' page: its tabs' bar over what the tab shown shows, each side scrolling on its own. */
export const shell = style({ flex: "1", minHeight: "0", minWidth: "0", display: "flex", flexDirection: "column" });

export const bar = style({
  flex: "none", display: "flex", alignItems: "center", gap: "10px", minHeight: "44px", padding: "6px 12px", boxSizing: "border-box",
  borderBottom: `1px solid ${vars.line}`,
  // On Windows the window's buttons are over its right end (global.css.ts): its buttons stay clear of them.
  selectors: { ':is([data-desktop="overlay"], [data-desktop="custom"]) &': { paddingRight: "calc(var(--window-buttons, 0px) + 12px)" } },
});
/** The groove the tabs share, each an equal part of it (as Safari's compact tabs), drawn as the app's own segmented
 * controls are (Drive.css.ts views): capsules in a capsule, 2 apart, the one shown on the page's ground in it. */
export const tabs = style({
  flex: "1", minWidth: "0", display: "flex", gap: "2px", padding: "2px", borderRadius: "999px",
  background: `color-mix(in srgb, ${vars.text} 6%, transparent)`,
});
export const tabsNone = style({ flex: "1" });
export const tab = style({
  position: "relative", flex: "1 1 0", minWidth: "0", maxWidth: "280px", height: "28px", display: "flex", alignItems: "center",
  borderRadius: "999px", color: vars.muted, transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&[data-on]": { background: vars.canvas, color: vars.text, boxShadow: `0 0 2px ${vars.shadow}, 0 0 0 .5px ${vars.line}` },
    "&:not([data-on]):hover": { background: vars.hover },
  },
});
export const tabName = style({
  flex: "1", minWidth: "0", height: "100%", display: "flex", alignItems: "center", justifyContent: "center", gap: "10px", padding: "0 26px",
  border: "0", background: "none", color: "inherit", font: "inherit", fontSize: vars.textMeta, cursor: "default",
});
/** A side's folder and its station on one baseline, its dot centred on them. */
export const tabPart = style({ minWidth: "0", display: "inline-flex", alignItems: "baseline", gap: "6px" });
export const tabFolder = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontWeight: "500" });
globalStyle(`${tab}:not([data-on]) ${tabFolder}`, { fontWeight: "400" });
export const tabStation = style({ flex: "none", color: vars.subtle, fontSize: vars.textCaption });
/** Between the two sides of a split tab: as far from each as the tab's parts are from each other (its gap). */
export const tabSplit = style({ flex: "none", alignSelf: "center", width: "1px", height: "10px", background: vars.line });
/** Closes a tab: at its left, shown as it is pointed at; a circle 6 in from the tab's ends (8 + 6 = its 14: concentric). */
export const tabClose = style({
  position: "absolute", left: "6px", top: "50%", transform: "translateY(-50%)", display: "grid", placeItems: "center", width: "16px", height: "16px",
  padding: "0", border: "0", borderRadius: "50%", background: "none", color: vars.muted, cursor: "pointer", opacity: "0",
  selectors: { [`${tab}:hover &`]: { opacity: "1" }, "&:hover": { background: vars.hover, color: vars.text } },
});
/** What can be done to the folder in front (Drive.tsx FolderView puts it here), then the tabs' own buttons after a line. */
export const barFolder = style({ flex: "none", display: "flex", alignItems: "center", selectors: { "&:not(:empty)::after": { content: '""', width: "1px", height: "16px", margin: "0 6px 0 10px", background: vars.line } } });
export const barEnd = style({ flex: "none", display: "flex", alignItems: "center", gap: "4px" });
// The bar sits in the row that drags the desktop window (styles/shell.css.ts main): its tabs and buttons are still pressed.
globalStyle(`[data-desktop] ${bar} :is(button, [role="tab"], [role="radio"], [role="radiogroup"])`, { WebkitAppRegion: "no-drag" });
/** A toggle in the accent while it is on (split). */
export const toggle = style({ display: "contents" });
globalStyle(`${toggle}[data-on] button`, { color: vars.accent });

/** A station's colour: one of six, by its place among the workspace's. */
export const dot = style({
  flex: "none", alignSelf: "center", width: "7px", height: "7px", borderRadius: "50%", background: vars.muted,
  selectors: {
    "&[data-tone='0']": { background: vars.accent },
    "&[data-tone='1']": { background: vars.blue },
    "&[data-tone='2']": { background: vars.green },
    "&[data-tone='3']": { background: vars.amber },
    "&[data-tone='4']": { background: vars.red },
    "&[data-tone='5']": { background: vars.muted },
  },
});

export const panes = style({ flex: "1", minHeight: "0", display: "flex" });
/** One side: a folder's page, scrolling by itself; split, the one in front underlined at its top. */
export const pane = style({
  flex: "1 1 0", minWidth: "0",
  selectors: {
    [`${panes}[data-split] > & + &`]: { borderLeft: `1px solid ${vars.line}` },
    [`${panes}[data-split] > &`]: { paddingLeft: "24px", paddingRight: "24px", boxShadow: `inset 0 2px 0 transparent` },
    [`${panes}[data-split] > &[data-front]`]: { boxShadow: `inset 0 2px 0 ${vars.accent}` },
  },
});
// Split, a side is narrow: its folder's name and what can be done to it wrap onto lines of their own.
globalStyle(`${panes}[data-split] ${pageHead}`, { flexWrap: "wrap", rowGap: "8px" });
globalStyle(`${panes}[data-split] ${headText}`, { flex: "1 1 240px" });
export const missing = style({ color: vars.muted, fontSize: vars.textUi });

// ── the transfers ──

export const transfersChip = style({
  display: "inline-flex", alignItems: "center", gap: "6px", height: "28px", padding: "0 10px", border: "0", borderRadius: "999px",
  background: vars.neutralBg, color: vars.muted, font: "inherit", fontSize: vars.textMeta, cursor: "pointer", fontVariantNumeric: "tabular-nums",
  selectors: {
    "&[data-going]": { background: vars.accentBg, color: vars.accentText },
    "&[data-failed]": { background: vars.redBg, color: vars.red },
  },
});
export const transfers = style({ width: "360px", maxWidth: "calc(100vw - 24px)", maxHeight: "min(520px, 70vh)", overflowY: "auto", padding: "8px" });
export const transfersHead = style({ padding: "4px 8px 8px", fontSize: vars.textMeta, fontWeight: "600", color: vars.text });
export const transfer = style({
  display: "grid", gridTemplateColumns: "18px minmax(0, 1fr) auto", gap: "8px", alignItems: "start", padding: "8px",
  borderTop: `1px solid ${vars.line}`, fontSize: vars.textMeta,
});
export const transferMark = style({ display: "grid", placeItems: "center", height: "18px", color: vars.muted, selectors: { [`${transfer}[data-state=done] &`]: { color: vars.green }, [`${transfer}[data-state=failed] &`]: { color: vars.red } } });
export const transferText = style({ minWidth: "0", display: "grid", gap: "4px" });
export const transferTitle = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", color: vars.text });
globalStyle(`${transferTitle} b`, { fontWeight: "500" });
globalStyle(`${transferTitle} span`, { color: vars.muted });
export const transferBar = style({ display: "block", height: "4px", borderRadius: "2px", background: vars.line, overflow: "hidden" });
globalStyle(`${transferBar} > span`, { display: "block", height: "100%", background: vars.accent, transformOrigin: "left", transition: `transform ${vars.dur} ${vars.easeOut}` });
export const transferStatus = style({ color: vars.muted, fontVariantNumeric: "tabular-nums", selectors: { "&[data-failed]": { color: vars.red } } });
export const transferActions = style({ display: "flex", alignItems: "center", gap: "2px" });

// ── a name already there ──

export const clash = style({ display: "grid", gridTemplateColumns: "auto 1fr", gap: "6px 12px", margin: "0", padding: "10px 12px", borderRadius: vars.rField, background: vars.neutralBg, fontSize: vars.textMeta });
globalStyle(`${clash} dt`, { color: vars.muted });
globalStyle(`${clash} dd`, { margin: "0", color: vars.text, fontVariantNumeric: "tabular-nums" });
export const clashNote = style({ margin: "10px 0 0", color: vars.muted, fontSize: vars.textMeta });
export const clashAll = style({ display: "flex", alignItems: "center", gap: "8px", marginTop: "12px", fontSize: vars.textUi, color: vars.text });

// ── 复制到… ──

/** Its rows 6 in from its corners, concentric with them (align.ts `inner`). */
export const copyTo = style({
  display: "grid", gridTemplateColumns: "180px minmax(0, 1fr)", gap: "0", height: "320px", border: `1px solid ${vars.line}`, borderRadius: vars.rField, overflow: "hidden",
  vars: { [IN]: `calc(${vars.rField} - 6px)` },
});
export const copyStations = style({ display: "grid", alignContent: "start", gap: "2px", padding: "6px", borderRight: `1px solid ${vars.line}`, overflowY: "auto" });
export const copyFolders = style({ display: "grid", alignContent: "start", gap: "2px", padding: "6px", overflowY: "auto" });
export const copyRow = style({
  display: "flex", alignItems: "center", gap: "8px", minWidth: "0", padding: "6px 8px", border: "0", borderRadius: inner, background: "none",
  color: vars.text, font: "inherit", fontSize: vars.textUi, textAlign: "left", cursor: "pointer",
  selectors: { "&:hover:not(:disabled)": { background: vars.hover }, "&[data-on]": { background: vars.selected }, "&:disabled": { color: vars.subtle, cursor: "default" } },
});
globalStyle(`${copyRow} > span`, { flex: "1", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${copyRow} > svg`, { flex: "none", color: vars.muted });
globalStyle(`${copyRow} small`, { flex: "none", fontSize: vars.textCaption, color: vars.subtle });
export const copyCrumbs = style({ display: "flex", flexWrap: "wrap", gap: "2px 6px", padding: "2px 8px 8px", fontSize: vars.textMeta });
globalStyle(`${copyCrumbs} button`, { padding: "0", border: "0", background: "none", color: vars.muted, font: "inherit", cursor: "pointer" });
globalStyle(`${copyCrumbs} button + button::before`, { content: "'›'", marginRight: "6px", color: vars.subtle });
globalStyle(`${copyCrumbs} button[data-last]`, { color: vars.text, fontWeight: "500" });
export const copyNote = style({ margin: "8px", color: vars.muted, fontSize: vars.textMeta });
export const copyWhere = style({ flex: "1", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", color: vars.muted, fontSize: vars.textMeta });
