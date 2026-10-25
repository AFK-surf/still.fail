import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { litOver } from "@stillfail/ui/styles/lit.ts";
import { buddyHopKeyframes } from "@stillfail/ui/styles/keyframes.css.ts";
import { CARD_PAD, LIST_PAD, ROW_CORNER, list, listCardLook, listRow, pageNarrow } from "./styles/pages.css.ts";
import { newChat } from "./NewChat.css.ts";
import { profileCard } from "./ProfileCard.css.ts";
import { pageBar as onePageBar } from "./styles/sidebar.css.ts";
import { bar as filesBar } from "./pages/Files.css.ts";
import { neg, outset } from "@stillfail/ui/styles/align.ts";
import { STILL } from "@stillfail/ui/styles/still.ts";

// A page's bar, and the files page's over its tabs (Files.tsx), which is in the same place.
const pageBar = `:is(${onePageBar}, ${filesBar})`;

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
    "&:hover:not(:disabled)": litOver,
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
// main), its bar from past the sidebar's edge to the window's, its buttons not moved out of it.
globalStyle(`${railed}[data-sidebar="closed"][data-sidebar-peek] ${pageBar}`, {
  "@media": { [wide]: { marginLeft: "max(0px, var(--sidebar-w, 240px) - 8px - var(--peek-shift, 0px))", marginRight: "var(--peek-shift, 0px)" } },
});

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
/**
 * On a settings page a list is a list card, on every width as the narrow screen's and the app's are (docs/ui-panels.md
 * 页面卡片, 列表卡; the user, 2026-10-26: 「设置感觉很乱」, a wide page's rows were on the page or on cards for no reason):
 * at the column's edges as the page's other cards, its rows' grounds LIST_PAD in, their words CARD_PAD in, their corners
 * concentric with its. Here, after the two above, so it wins over them.
 */
globalStyle(`${pageNarrow} ${list}`, { ...listCardLook, padding: LIST_PAD, marginInline: "0" });
// One right in the page is a block of its own, as far from what follows as a section (page.css.ts section).
globalStyle(`${pageNarrow} > ${list}`, { maxWidth: "760px", marginLeft: "auto", marginRight: "auto", marginBottom: "28px" });
// Its rows: a list's own and a profile's (ProfileCard.tsx, a row of a list but where it stands alone).
globalStyle(`${pageNarrow} ${list} :is(${listRow}, ${profileCard})`, { borderRadius: ROW_CORNER, paddingInline: `${CARD_PAD - LIST_PAD}px` });
globalStyle(`${sidebarBuddy}[data-pose="hop"] img`, { animation: `${buddyHopKeyframes} 380ms ${vars.easeOut}` });
/** The buddy unmoving (rest and push breathe and strain in their SVG, which goes by the system's setting): shown in its
 *  place with motion reduced. */
export const buddyStill = style({});
globalStyle(`${sidebarBuddy} ${buddyStill}`, { display: "none" });
globalStyle(`${STILL} ${sidebarBuddy} img:not(${buddyStill})`, { display: "none" });
globalStyle(`${STILL} ${sidebarBuddy} ${buddyStill}`, { display: "block" });
