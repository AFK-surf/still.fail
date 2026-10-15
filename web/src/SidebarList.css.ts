// The sidebar's lists' own parts (SidebarList.tsx): a row of a station, a folder, a profile, laid out as a chat's.
import { globalStyle, style } from "@vanilla-extract/css";
import { navRow } from "./Sidebar.css.ts";
import { vars } from "./styles/tokens.css.ts";

const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;

/** A list (NavList): as wide as the sidebar. */
export const list = style({ flex: 1 });
/** A row that is a button, as one that is a link (its size and line the row's: no `font` shorthand over them). */
export const button = style({
  width: "100%", textAlign: "left", fontFamily: "inherit", border: 0, background: "none", cursor: "pointer", textDecoration: "none",
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

/**
 * The same row on the phone (NavPhone: a bottom bar place's top page, mobile/; the Android app's PlacePage.kt the same):
 * the screen's width, 22 in on the left and 16 on the right (a chat row's), 10 over and under; the mark's column 16,
 * 8 before the title; its type a size up (the title 16 on a line of 22, what is under it 13, as a chat row's second
 * line); pressed, it darkens as a chat row does.
 */
export const phone = style({
  display: "flex", alignItems: "flex-start", gap: 8, boxSizing: "border-box", minHeight: 0, padding: "10px 16px 10px 22px",
  color: "var(--m-ink)", lineHeight: "22px", WebkitUserSelect: "none", userSelect: "none", WebkitTouchCallout: "none",
  "@media": {
    "(pointer: coarse)": { selectors: { "&:active": { background: "color-mix(in srgb, var(--m-ink) 5%, transparent)" } } },
    "(hover: hover) and (pointer: fine)": { selectors: { "&:hover": { background: "color-mix(in srgb, var(--m-ink) 4%, transparent)" } } },
  },
});
globalStyle(`${phone} ${mark}`, { height: 22, color: "var(--m-muted)" });
globalStyle(`${phone} ${head}`, { height: 22 });
globalStyle(`${phone} ${title}`, { fontSize: vars.textTitle, lineHeight: "22px" });
globalStyle(`${phone} ${end}`, { color: "var(--m-muted)" });
globalStyle(`${phone} ${line}`, { minHeight: 20, lineHeight: "20px", color: "var(--m-muted)" });
/** A section's heading on the phone: as the chats' days are (mobile/parts.tsx SectionHeader). */
export const phoneHeading = style({ display: "flex", alignItems: "flex-end", padding: "14px 20px 6px", color: "var(--m-ink)" });
globalStyle(`${phoneHeading} b`, { fontSize: vars.textBody, fontWeight: 600 });
