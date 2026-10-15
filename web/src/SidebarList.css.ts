// The sidebar's lists' own parts (SidebarList.tsx): a row of a station, a folder, a profile, laid out as a chat's.
import { style } from "@vanilla-extract/css";
import { navRow } from "./Sidebar.css.ts";
import { vars } from "./styles/tokens.css.ts";

const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;

/** A row that is a button, as one that is a link. */
export const button = style({
  width: "100%", textAlign: "left", font: "inherit", border: 0, background: "none", cursor: "pointer", textDecoration: "none",
});
/** As a chat's row: its mark beside the first line, not between the lines. */
export const item = style({
  paddingTop: 7, paddingBottom: 7,
  selectors: {
    "&:disabled": { cursor: "progress" },
    // Over a sidebar row's centring, whichever's rule comes later.
    [`${navRow}&`]: { alignItems: "flex-start" },
  },
});
/** The mark on the first line, as wide as the action row's icon over the list. */
export const mark = style({ display: "grid", placeItems: "center", flex: "none", width: 16, height: 20 });
export const text = style({ display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: 2, flex: 1, minWidth: 0 });
export const head = style({ display: "flex", alignItems: "center", gap: 8, height: 20, minWidth: 0 });
export const title = style({
  flex: 1, ...ellipsis,
  selectors: { [`${item}[data-away] &`]: { opacity: 0.5 } },
});
/** At the first line's end: short, and never cut (the title gives way). */
export const end = style({
  flex: "none", display: "flex", alignItems: "center", gap: 5, maxWidth: "45%", overflow: "hidden",
  fontSize: vars.textMeta, color: vars.muted, whiteSpace: "nowrap",
});
/** A line under the title. */
export const line = style({
  display: "flex", alignItems: "center", gap: 4, minHeight: 18, lineHeight: "18px", minWidth: 0,
  fontSize: vars.textMeta, color: vars.muted, whiteSpace: "nowrap",
});
/** A line's words that give way first. */
export const fill = style({ flex: 1, ...ellipsis });
