// The sidebar: the brand on top, the chat list (or a settings list) under it, a foot at the bottom. Also the station's,
// the cloud's and the admin console's settings lists, which are drawn with the same rows.
import { fallbackVar, globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { accountTrigger } from "./cloud/workspace.css.ts";
import { iconBtn } from "./styles/pages.css.ts";
import { shell } from "./styles/shell.css.ts";
import { kindIcon, kindMark, resizeHandle } from "./ui.css.ts";

const wide = "(min-width: 701px)";
const narrow = "(max-width: 700px)";
const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;

export const sidebar = style({
  background: vars.sidebar, display: "flex", flexDirection: "column", minHeight: 0, borderRight: `1px solid ${vars.line}`,
  // The sidebar is for going places, not for copying: nothing in it is selected (its fields still are) or dragged off.
  WebkitUserSelect: "none", userSelect: "none",
  "@media": {
    [wide]: {
      position: "relative",
      selectors: { '[data-sidebar="closed"] &': { overflow: "hidden", borderRightColor: "transparent" } },
    },
    // On a narrow screen the sidebar is the page's list: it gives way to the page opened from it.
    [narrow]: { borderRight: 0, selectors: { [`${shell}[data-detail="true"] &`]: { display: "none" } } },
  },
});
globalStyle(`${sidebar} :is(input, textarea)`, { WebkitUserSelect: "text", userSelect: "text" });
globalStyle(`${sidebar} :is(a, img, svg)`, { WebkitUserDrag: "none" });
// Closing or opening, its contents keep their width and are cut, not laid out anew at every step.
globalStyle(`${sidebar} > :not(${resizeHandle})`, { "@media": { [wide]: { minWidth: `calc(${fallbackVar(vars.sidebarW, "240px")} - 1px)` } } });

/** The buddy's drawing starts a little inside the lockup: 16 px puts it on the rows' icons below. */
export const brand = style({
  display: "flex", alignItems: "center", gap: 8, height: 56, padding: "0 16px",
  selectors: {
    // The desktop app has no title bar: the top row holds the window's buttons (apps/desktop/src/main.ts puts them in
    // it), the buddy beside them, and drags the window.
    "[data-desktop] &": { height: 44, paddingLeft: 86, WebkitAppRegion: "drag" },
    // Full screen, the window's buttons are gone.
    "[data-desktop][data-fullscreen] &": { paddingLeft: 16 },
  },
});
/** 云端侧边栏：lockup 在 workspace 切换器上方（always with `brand`, whose desktop top row still wins） */
export const brandCompact = style({ height: 48, padding: "0 16px" });

// Positioned: the rows moving in it are placed by their offsets in it (listMotion.ts).
export const navScroll = style({ position: "relative", flex: 1, minHeight: 0, overflowY: "auto", padding: "4px 8px 12px" });
/** 全部 and 我参与的 side by side on one track; the switch slides it, as its thumb slides. */
export const navSlider = style({ flex: 1, minHeight: 0, overflow: "hidden", display: "flex" });
export const navTrack = style({
  flex: "none", width: "200%", display: "flex", transition: `transform 240ms ${vars.easeOut}`,
  selectors: { "&[data-mine]": { transform: "translateX(-50%)" } },
  "@media": { "(prefers-reduced-motion: reduce)": { transition: "none" } },
});
// Each pane sized by the track alone: otherwise the track's height is its tallest pane's content, and any change in a
// row (the time shown on hover) lays out every row of both lists again, a frame dropped per row passed while scrolling.
globalStyle(`${navTrack} > ${navScroll}`, { flex: "none", width: "50%", contain: "strict" });

export const navFoot = style({ padding: 8, borderTop: `1px solid ${vars.line}` });
export const navFootRow = style({ display: "flex", alignItems: "center", gap: 4 });
globalStyle(`${navFootRow} ${accountTrigger}`, { flex: 1, minWidth: 0 });
globalStyle(`${navFootRow} > ${iconBtn}, ${navFootRow} > * > ${iconBtn}`, { flex: "none" });

export const navHeading = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", margin: "14px 8px 4px",
  fontSize: vars.textXs, lineHeight: "18px", color: vars.muted,
});
export const navEmpty = style({ margin: "16px 10px", fontSize: vars.textSm, color: vars.muted });
export const navError = style({ color: vars.red });

export const navRow = style({
  display: "flex", alignItems: "center", gap: 8, minHeight: 32, padding: "6px 10px", lineHeight: "20px", borderRadius: vars.rNav,
  fontSize: vars.textSm, color: vars.text, transition: `background ${vars.dur} ${vars.easeOut}`, cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover },
    '&[aria-current="page"]': { background: vars.selected },
    // Adjacent sidebar items never touch, so a selected or hovered row stays distinct.
    "& + &": { marginTop: 2 },
    // While the list scrolls, rows passing under the pointer do not light up (each would repaint the list).
    [`${navScroll}[data-scrolling] &`]: { pointerEvents: "none" },
  },
});
globalStyle(`${navRow} svg`, { color: vars.muted, flex: "none" });
export const navText = style(ellipsis);
/** 新建对话, with the filter beside it. */
export const navNew = style({ display: "flex", alignItems: "center", gap: 4, padding: "6px 8px 2px" });
globalStyle(`${navNew} > ${navRow}`, { flex: 1, minWidth: 0 });

// ── a chat's row ──

/** Archiving a chat: a button at the row's top right while it is pointed at, the title making room for it. */
export const navSessionWrap = style({
  position: "relative", borderRadius: vars.rNav, cornerShape: vars.cornerShape,
  selectors: { "& + &": { marginTop: 2 } },
});
export const navSession = style({
  alignItems: "flex-start", paddingTop: 7, paddingBottom: 7, position: "relative",
  selectors: {
    // Pointing at the button is still pointing at the row.
    [`${navSessionWrap}:hover &:not([aria-current="page"])`]: { background: vars.hover },
  },
});

/** Who is in a chat: its agent's mark, or two of them overlapping, with its state at the corner (ChatMark.tsx). */
export const rowPicture = style({
  position: "relative", flex: "none", width: 30, height: 30, marginTop: 4,
  vars: { "--mark-around": vars.sidebar },
  selectors: {
    [`${navSession}[data-offline] &`]: { opacity: 0.5 },
    [`${navSessionWrap}:hover ${navSession}:not([aria-current="page"]) &`]: {
      vars: { "--mark-around": vars.hover, "--mark-under": vars.sidebar },
    },
    [`${navSession}[aria-current="page"] &`]: { vars: { "--mark-around": vars.selected } },
  },
});
export const rowAgent = style({
  position: "absolute", display: "grid", placeItems: "center",
  selectors: {
    [`${rowPicture}[data-count="1"] &`]: { inset: 0 },
    [`${rowPicture}[data-count="2"] &`]: { width: 16, height: 16 },
    [`${rowPicture}[data-count="2"] &:first-child`]: { left: 0, top: 0 },
    [`${rowPicture}[data-count="2"] &:last-child`]: { right: 0, bottom: 0 },
  },
});
/** A station's link coming back: a small turning ring (the global spinner) where the row's mark goes. */
export const rowSpinner = style({ width: 12, height: 12, borderWidth: 1.5 });

export const navSessionText = style({ display: "grid", gap: 2, minWidth: 0, flex: 1 });
export const navSessionHead = style({
  display: "flex", alignItems: "center", gap: 6, minWidth: 0, height: 20, lineHeight: "20px",
  selectors: { [`${navSessionWrap}:hover &`]: { paddingRight: 24 } },
});
export const navSessionTitle = style({
  flex: 1, ...ellipsis,
  selectors: {
    [`${navSession}[data-unread] &`]: { fontWeight: 600, color: vars.text },
    [`${navSession}[data-offline] &`]: { opacity: 0.5 },
  },
});
export const navSessionMeta = style({
  display: "flex", alignItems: "center", gap: 6, fontSize: vars.textXs, color: vars.muted, whiteSpace: "nowrap", overflow: "hidden",
  // Every row is two lines high, message or not, so a row that gains its first message does not grow.
  height: 18, lineHeight: "18px",
  selectors: { [`${navSession}[data-offline] &`]: { opacity: 0.5 } },
});
export const navSessionLast = style({ flex: 1, ...ellipsis, fontSize: vars.textXs, color: vars.muted });
/** When is rarely what one looks for in the list: it shows on hover (and keyboard focus), giving its room to the message otherwise. */
export const navTime = style({
  marginLeft: "auto", flex: "none", color: vars.subtle, fontVariantNumeric: "tabular-nums",
  selectors: {
    [`${navSession} &`]: { display: "none" },
    [`${navSessionWrap}:hover &, ${navSession}:focus-visible &`]: { display: "inline" },
  },
});
/** Where the chat happens (Slack), or that its station is offline or reconnecting: at the title's end. */
export const sessionKind = style({
  display: "inline-grid", flex: "none",
  selectors: {
    [`${navSessionHead} &`]: { width: 14, placeItems: "center" },
    [`${navSession}[data-offline] &`]: { color: vars.subtle },
  },
});
globalStyle(`${sessionKind} ${kindIcon}`, { width: 14, height: 14 });
// The buddy has air around it in its artwork: at 16px it reads as big as the 14px platform marks.
globalStyle(`${sessionKind} ${kindMark}`, { margin: -1 });
/** Archive, beside a row while pointed at: centred on the title line (20px tall, 7px down the row). */
export const rowArchive = style({
  position: "absolute", top: 5, right: 6, width: 24, height: 24, opacity: 0, pointerEvents: "none",
  selectors: { [`${navSessionWrap}:hover &, &:focus-visible`]: { opacity: 1, pointerEvents: "auto" } },
});

/** Stations not working: a row at the top of the sidebar's foot, over the account; its dot says the worst of it. */
export const stationTrouble = style({
  marginBottom: 4, color: vars.text,
  selectors: { '&[data-state="error"]': { color: vars.red } },
});
export const stationTroubleMark = style({ width: 16, flex: "none", display: "grid", placeItems: "center" });
export const stationTroubleText = style({ flex: 1, ...ellipsis });
export const stationTroubleGo = style({ flex: "none", color: vars.muted });
/** What is waited on: quieter than a station down, it is only slow; the row is no link. */
globalStyle(`${stationTrouble}[data-state="slow"]`, { color: vars.muted, cursor: "default" });
globalStyle(`${stationTrouble}[role="status"]:hover`, { background: "transparent" });
export const waitingItems = style({ display: "grid", gap: 6, maxWidth: 320 });
export const waitingItem = style({ display: "grid", gap: 1 });
export const waitingDetail = style({ opacity: 0.7 });
/** Under a page's "loading…": quiet. */
export const statusLine = style({ display: "block", marginTop: 4, fontSize: 12, color: vars.muted });
