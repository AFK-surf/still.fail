import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { buddyHopKeyframes } from "@stillfail/ui/styles/keyframes.css.ts";
import { list, pageNarrow } from "./styles/pages.css.ts";
import { newChat } from "./NewChat.css.ts";
import { pageBar } from "./styles/sidebar.css.ts";
import { neg, outset } from "@stillfail/ui/styles/align.ts";

export const brandLockup = style({ display: "block" });
export const illus = style({
  display: "block", maxWidth: "100%", height: "auto",
  selectors: {
    [`${newChat} &`]: { marginBottom: "4px" },
  },
  "@media": {
    "(max-height: 640px)": {
      selectors: {
        [`${newChat} &`]: { display: "none" },
      },
    },
  },
});
export const sidebarBuddy = style({
  selectors: {
    "[data-sidebar=\"closed\"] &": { left: "14px" },
    "[data-desktop] &": { top: "8px" },
    "[data-desktop=\"inset\"]:not([data-fullscreen])[data-sidebar=\"closed\"] &": { left: "84px" },
  },
  "@media": {
    "(max-width: 700px)": {
      display: "none",
    },
  },
});
/** 更新 beside the buddy (the desktop app): left of it on the open sidebar's edge, right of it at rest by the window's buttons. */
export const sidebarUpdate = style({
  position: "fixed", zIndex: "40", top: "18px", left: "calc(var(--sidebar-w, 240px) - 36px)",
  transform: "translateX(-100%)", height: "22px", padding: "0 9px", border: "0", borderRadius: "999px",
  font: "inherit", fontSize: vars.textMeta, fontWeight: "500", whiteSpace: "nowrap", background: vars.accentBg,
  color: vars.accentText, cursor: "pointer", WebkitAppRegion: "no-drag",
  selectors: {
    "&:hover:not(:disabled)": { filter: "brightness(.96)" },
    "&:disabled": { cursor: "progress" },
    "[data-sidebar=\"closed\"] &": { left: "50px", transform: "none" },
    "[data-desktop] &": { top: "11px" },
    "[data-desktop=\"inset\"]:not([data-fullscreen])[data-sidebar=\"closed\"] &": { left: "120px" },
  },
  "@media": {
    "(max-width: 700px)": {
      display: "none",
    },
  },
});
// Beside the rail (Rail.tsx, a workspace's page), which opens and closes the sidebar: 更新 at the open sidebar's top right,
// or past the window's buttons when it is closed, the page bars making room for what is over them.
const railed = ":root:has([data-rail])";
const wide = "(min-width: 701px)";
globalStyle(`${railed} ${sidebarUpdate}`, { "@media": { [wide]: { left: "calc(56px + var(--sidebar-w, 240px) - 12px)" } } });
globalStyle(`${railed}[data-sidebar="closed"] ${sidebarUpdate}`, { "@media": { [wide]: { left: "68px", transform: "none" } } });
globalStyle(`${railed}[data-desktop="inset"]:not([data-fullscreen])[data-sidebar="closed"] ${sidebarUpdate}`, { "@media": { [wide]: { left: "80px" } } });
globalStyle(`${railed}[data-sidebar="closed"] ${pageBar}`, { "@media": { [wide]: { paddingLeft: "12px" } } });
// The window's buttons reach 12 px past the rail.
globalStyle(`${railed}[data-desktop="inset"]:not([data-fullscreen])[data-sidebar="closed"] ${pageBar}`, { "@media": { [wide]: { paddingLeft: "28px" } } });
globalStyle(`${railed}:has(${sidebarUpdate})[data-sidebar="closed"] ${pageBar}`, { "@media": { [wide]: { paddingLeft: "72px" } } });
globalStyle(`${railed}:has(${sidebarUpdate})[data-desktop="inset"]:not([data-fullscreen])[data-sidebar="closed"] ${pageBar}`, { "@media": { [wide]: { paddingLeft: "84px" } } });
// A folded sidebar shown a while (Rail.tsx peekSidebar): the page moved only as far as its column needs (shell.css.ts
// main), its bar starts past the sidebar's edge.
globalStyle(`${railed}[data-sidebar="closed"][data-sidebar-peek] ${pageBar}`, { "@media": { [wide]: { marginLeft: "max(0px, var(--sidebar-w, 240px) - 8px - var(--peek-shift, 0px))" } } });

export const brandWordmark = style({
  display: "block",
  "@media": {
    "(max-width: 700px)": {
      display: "none",
    },
  },
});
export const brandPhone = style({
  display: "none",
  "@media": {
    "(max-width: 700px)": {
      display: "contents",
    },
  },
});
/** Here rather than with its class: it comes after .illus, and wins over it. */
globalStyle(`${pageNarrow} > *`, { maxWidth: "760px", marginLeft: "auto", marginRight: "auto" });
/** Lists stand on spacing, not frames or rules: their rows' text lines up with the page's, a row's ground shows on hover. */
/** Here rather than with its class: it comes after .page-narrow > *, and wins over it. */
// One column no wider than the page, so a long title is cut short rather than widening its row past it.
globalStyle(list, { listStyle: "none", marginBlock: "0", ...outset(12), padding: "0", display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: "2px" });
/** A list right in a narrow page (not in a section): in the page's column like everything else there, its rows' grounds
 * out past it by their padding. Its own margin above would take the column's centring away (it comes later). */
globalStyle(`${pageNarrow} > ${list}`, { maxWidth: "none", marginLeft: `max(${neg(12)}, calc(50% - 392px))`, marginRight: `max(${neg(12)}, calc(50% - 392px))` });
globalStyle(`${sidebarBuddy}[data-pose="hop"] img`, { animation: `${buddyHopKeyframes} 380ms ${vars.easeOut}` });
globalStyle(`${sidebarBuddy}[data-pose="hop"] img`, {
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none",
    },
  },
});
