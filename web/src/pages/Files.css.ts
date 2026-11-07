import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { pageHead } from "../styles/pages.css.ts";

/** The files' page: its tabs' bar over what the tab shown shows, each side scrolling on its own. */
export const shell = style({ flex: "1", minHeight: "0", minWidth: "0", display: "flex", flexDirection: "column" });

export const bar = style({
  flex: "none", display: "flex", alignItems: "center", gap: "10px", minHeight: "44px", padding: "6px 12px", boxSizing: "border-box",
  borderBottom: `1px solid ${vars.line}`,
});
/** The groove the tabs share, each an equal part of it (as Safari's compact tabs), drawn as the app's own segmented
 * controls are (Drive.css.ts views): capsules in a capsule, 2 apart, the one shown on the page's ground in it. */
export const tabs = style({
  flex: "1", minWidth: "0", display: "flex", gap: "2px", padding: "2px", borderRadius: "999px",
  background: `color-mix(in srgb, ${vars.text} 6%, transparent)`,
});
export const tab = style({
  position: "relative", flex: "1 1 0", minWidth: "0", maxWidth: "280px", height: "28px", display: "flex", alignItems: "center",
  borderRadius: "999px", color: vars.muted, transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&[data-on]": { background: vars.canvas, color: vars.text, boxShadow: `0 0 2px ${vars.shadow}, 0 0 0 .5px ${vars.line}` },
    "&:not([data-on]):hover": { background: vars.hover },
  },
});
/** A toggle in the accent while it is on (split). */
export const toggle = style({ display: "contents" });
globalStyle(`${toggle}[data-on] button`, { color: vars.accent });

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
export const missing = style({ color: vars.muted, fontSize: vars.textUi });
export const transfers = style({ width: "360px", maxWidth: "calc(100vw - 24px)", maxHeight: "min(520px, 70vh)", overflowY: "auto", padding: "8px" });
export const transfer = style({
  display: "grid", gridTemplateColumns: "18px minmax(0, 1fr) auto", gap: "8px", alignItems: "start", padding: "8px",
  borderTop: `1px solid ${vars.line}`, fontSize: vars.textMeta,
});
