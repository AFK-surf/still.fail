// The sidebar: the brand on top, the chat list (or a settings list) under it, a foot at the bottom. Also the station's,
// the cloud's and the admin console's settings lists, which are drawn with the same rows.
import { fallbackVar, globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { dock, shell } from "./styles/shell.css.ts";
import { outsetStart } from "@stillfail/ui/styles/align.ts";
import { iconBtn } from "@stillfail/ui/styles/page.css.ts";
import { resizeHandle } from "@stillfail/ui/parts.css.ts";

const wide = "(min-width: 701px)";
const narrow = "(max-width: 700px)";

export const sidebar = style({
  background: vars.sidebar, display: "flex", flexDirection: "column", minHeight: 0, position: "relative",
  // The sidebar is for going places, not for copying: nothing in it is selected (its fields still are) or dragged off.
  userSelect: "none",
  "@media": {
    [wide]: {
      selectors: { '[data-sidebar="closed"] &, [data-sidebar-moving] &': { overflow: "hidden" } },
    },
    // On a narrow screen the sidebar is the page's list: it gives way to the page opened from it.
    [narrow]: { selectors: { [`${shell}[data-detail="true"] &`]: { display: "none" } } },
  },
});
// In the block with the rail (shell.css.ts dock): its ground is the block's, its width its own, cut as the block closes.
globalStyle(`${dock} > ${sidebar}`, {
  background: "none", flex: "none", width: fallbackVar(vars.sidebarW, "240px"),
});
// Open, reaching 8 into the rail's 56 (empty there, right of its places): its rows 13 from the rail's ground, as that
// ground is from the window's edge, not 21; its right edge where it was. Closed, after the rail, cut by the bar.
globalStyle(`:root:not([data-sidebar="closed"]) ${dock} > ${sidebar}`, {
  "@media": { [wide]: { ...outsetStart(8), width: `calc(${fallbackVar(vars.sidebarW, "240px")} + 8px)` } },
});
globalStyle(`${sidebar} :is(input, textarea)`, { userSelect: "text" });
globalStyle(`${sidebar} :is(a, img, svg)`, { WebkitUserDrag: "none" });
// Closing or opening, its contents keep their width and are cut, not laid out anew at every step.
globalStyle(`${sidebar} > :not(${resizeHandle})`, { "@media": { [wide]: { minWidth: fallbackVar(vars.sidebarW, "240px") } } });

/** The sidebar's top row: the name, 16 px in, over the rows' icons below. */
export const brand = style({
  display: "flex", alignItems: "center", gap: 8, height: 56, padding: "0 16px",
  "@media": {
    // Beside the rail, nothing is left in it (no name): a margin only. Closed (shown a while over the page, Rail.tsx
    // peekSidebar), none either: its first row level with the rail's first place.
    [wide]: { selectors: {
      ':root [data-rail] &': { height: 8 },
      ':root[data-sidebar="closed"] [data-rail] &': { height: 0 },
    } },
  },
});
/** 云端侧边栏：字标在 workspace 切换器上方（always with `brand`） */
export const brandCompact = style({ height: 48, padding: "0 16px" });

// Positioned: the rows moving in it are placed by their offsets in it. Scroll padding: going to a row
// (keyboard, scrollIntoView) stops clear of the bands, and so does the floating scrollbar (scrollbars.ts).
export const navScroll = style({
  position: "relative", flex: 1, minHeight: 0, overflowY: "auto",
  padding: "calc(var(--nav-top, 0px) + 4px) 8px calc(var(--nav-foot, 0px) + 12px)",
  scrollPaddingTop: "var(--nav-top, 0px)", scrollPaddingBottom: "var(--nav-foot, 0px)",
});
export const navFootRow = style({ display: "flex", alignItems: "center", gap: 4 });
globalStyle(`${navFootRow} > ${iconBtn}, ${navFootRow} > * > ${iconBtn}`, { flex: "none" });

export const navHeading = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", margin: "14px 8px 4px",
  fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted,
});

export const navRow = style({
  display: "flex", alignItems: "center", gap: 8, minHeight: 32, padding: "6px 10px", lineHeight: "20px", borderRadius: vars.rNav,
  fontSize: vars.textUi, color: vars.text, transition: `background ${vars.dur} ${vars.easeOut}`, cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover },
    '&[aria-current="page"]': { background: vars.selected },
    // Clicked, its page on the way: selected already, and the one it leaves no longer.
    '&[data-going="here"]': { background: vars.selected },
    '&[aria-current="page"][data-going="away"]': { background: "none" },
    // Adjacent sidebar items never touch, so a selected or hovered row stays distinct.
    "& + &": { marginTop: 2 },
    // While the list scrolls, rows passing under the pointer do not light up (each would repaint the list).
    [`${navScroll}[data-scrolling] &`]: { pointerEvents: "none" },
  },
});
globalStyle(`${navRow} svg`, { color: vars.muted, flex: "none" });
