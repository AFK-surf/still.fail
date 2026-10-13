import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { pageNarrow } from "../styles/pages.css.ts";

export const page = style({ position: "relative" });

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
export const actions = style({ flex: "none", display: "flex", alignItems: "center", gap: "6px" });
const turn = keyframes({ to: { transform: "rotate(360deg)" } });
/** Refresh turns while the folder is read again. */
export const spin = style({ display: "contents" });
globalStyle(`${spin}[data-on] svg`, { animation: `${turn} 900ms linear infinite` });

/** The entries: rows on the page, a row's ground on hover; files dropped on it go into the folder. */
export const list = style({ position: "relative", display: "grid", gap: "2px", minHeight: "200px", borderRadius: vars.rCard, cornerShape: vars.cornerShape });
// As the settings lists: rows reaching a little past the column, their text in line with the page's.
globalStyle(`${pageNarrow} > ${list}`, { maxWidth: "none", marginLeft: "max(-12px, calc(50% - 392px))", marginRight: "max(-12px, calc(50% - 392px))" });
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
    [`${list} > &, [role=dialog] &`]: { gridTemplateColumns: "20px minmax(0, 1fr) 16px", minHeight: "52px" },
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
export const pickerPath = style({ display: "flex", alignItems: "center", gap: "8px", marginBottom: "8px", minWidth: "0" });
globalStyle(`${pickerPath} code`, { minWidth: "0", fontFamily: vars.fontMono, fontSize: vars.textMeta, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", direction: "rtl", textAlign: "left" });
export const pickerList = style({ display: "grid", gap: "2px", height: "min(52vh, 420px)", overflowY: "auto", margin: "0 -8px" });

/** A file opened: the reader or the player fills the pane. */
export const opened = style({ position: "relative", flex: "1", minHeight: "0", overflow: "hidden" });
export const dark = style({ background: "#000" });
export const openedNote = style({ padding: "40px" });
