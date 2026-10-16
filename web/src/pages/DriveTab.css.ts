import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

/** The tab: its trail and buttons over the folder's list, which scrolls. */
export const tab = style({ flex: "1", minHeight: "0", display: "flex", flexDirection: "column" });
/** The way here, and what is done to the folder shown, at its end. */
export const head = style({ flex: "none", display: "flex", alignItems: "center", gap: "8px", padding: "4px 8px 6px 12px", minWidth: "0" });
/** The trail scrolls sideways rather than wraps, the folder shown kept in view. */
export const trail = style({
  display: "flex", alignItems: "center", gap: "2px", flex: "1", minWidth: "0", overflowX: "auto", scrollbarWidth: "none", whiteSpace: "nowrap",
  color: vars.muted, fontSize: vars.textMeta,
});
export const step = style({ display: "inline-flex", alignItems: "center", gap: "2px", flex: "none" });
globalStyle(`${trail} button`, { padding: "3px 4px", border: "0", borderRadius: vars.rOption, cornerShape: vars.cornerShape, background: "none", color: "inherit", font: "inherit", cursor: "pointer" });
globalStyle(`${trail} button:hover`, { color: vars.text });
globalStyle(`${trail} button[data-last]`, { color: vars.text, fontWeight: 600 });
/** The rows, from edge to edge of the tab but for a little room. */
export const list = style({ flex: "1", minHeight: "0", overflowY: "auto", alignContent: "start", padding: "0 8px 8px", borderRadius: "0" });
export const note = style({ margin: "0", padding: "12px 16px" });
/** A station's name over its places (and whether it is away), as the jobs' groups are headed. */
export const group = style({
  display: "flex", alignItems: "baseline", gap: "6px", padding: "8px 10px 4px", color: vars.muted, fontSize: vars.textMeta, fontWeight: "500", minWidth: "0",
});
// Columns fill the tab: each scrolls on its own, narrower than the page's.
globalStyle(`${list}[data-view="columns"]`, { display: "block", overflowY: "hidden" });
globalStyle(`${list}[data-view="columns"] > *`, { height: "100%" });
// Two columns in view at a time: the one open and the one before it.
globalStyle(`${list}[data-view="columns"] > * > *`, { flexBasis: "calc(50% - 3px)" });
