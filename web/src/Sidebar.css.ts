// The sidebar: the brand on top, the chat list (or a settings list) under it, a foot at the bottom. Also the station's,
// the cloud's and the admin console's settings lists, which are drawn with the same rows.
import { fallbackVar, globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { litOver } from "@stillfail/ui/styles/lit.ts";
import { accountTrigger } from "./cloud/workspace.css.ts";
import { dock, shell } from "./styles/shell.css.ts";
import { kindIcon, kindMark } from "./ui.css.ts";
import { outsetEnd, outsetStart, oversize } from "@stillfail/ui/styles/align.ts";
import { iconBtn } from "@stillfail/ui/styles/page.css.ts";
import { resizeHandle } from "@stillfail/ui/parts.css.ts";
import { STILL, stillAtOnce } from "@stillfail/ui/styles/still.ts";

const wide = "(min-width: 701px)";
const narrow = "(max-width: 700px)";
const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;

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

/** The sidebar's top and foot are frosted bands over the lists, which scroll on under them (glassBands in Sidebar.tsx
 * sets their heights, `--nav-top` and `--nav-foot`, for the lists to start and end clear of them). */
const band = {
  position: "relative", zIndex: 1, flex: "none",
  background: `color-mix(in srgb, ${vars.sidebar} 72%, transparent)`, backdropFilter: "blur(20px)",
  // With the sidebar's ground as it closes to the bar (shell.css.ts dock): moved with it (brand.tsx moveSidebar).
} as const;
export const navTop = style(band);

// Positioned: the rows moving in it are placed by their offsets in it (listMotion.ts). Scroll padding: going to a row
// (keyboard, scrollIntoView) stops clear of the bands, and so does the floating scrollbar (scrollbars.ts).
export const navScroll = style({
  position: "relative", flex: 1, minHeight: 0, overflowY: "auto",
  padding: "calc(var(--nav-top, 0px) + 4px) 8px calc(var(--nav-foot, 0px) + 12px)",
  scrollPaddingTop: "var(--nav-top, 0px)", scrollPaddingBottom: "var(--nav-foot, 0px)",
});
/** 全部, 我参与的, 监控中 and 已归档 side by side on one track; switching slides it from one to another. Under the bands: the
 * whole sidebar's height. */
export const navSlider = style({ position: "absolute", inset: 0, overflow: "hidden", display: "flex" });
export const navTrack = style({
  flex: "none", width: "400%", display: "flex", transition: `transform 240ms ${vars.easeOut}`,
  selectors: {
    "&[data-filter=mine]": { transform: "translateX(-25%)" },
    "&[data-filter=watching]": { transform: "translateX(-50%)" },
    "&[data-filter=archive]": { transform: "translateX(-75%)" },
  },
});
// Each pane sized by the track alone: otherwise the track's height is its tallest pane's content, and any change in a
// row (the time shown on hover) lays out every row of all the lists again, a frame dropped per row passed while scrolling.
globalStyle(`${navTrack} > ${navScroll}`, { flex: "none", width: "25%", contain: "strict" });
// The panes not shown (inert) are not drawn, nor their rows' motions run: drawn, they cost every frame that changed
// anything as much as the one shown (their rings went on turning off to the side). Only while the track rests: sliding
// (data-sliding, Sidebar.tsx), the panes it passes are drawn from its start, and the one it leaves stays a slide's time
// before it goes (it gets inert before the slide starts); the one it goes to shows at once (that has no transition).
globalStyle(`${navTrack}:not([data-sliding]) > ${navScroll}[inert]`, { contentVisibility: "hidden", transition: "content-visibility 0s 240ms allow-discrete" });
globalStyle(`${STILL} ${navTrack}:not([data-sliding]) > ${navScroll}[inert]`, stillAtOnce);
// Not drawn is not stopped: a loop left running in a pane gone hidden (a row's spokes, its waiting dots) cannot go to
// the compositor, so the page is woken for it every frame of the screen (120 a second), and every motion shown is
// worked out again on each of those frames. So they end there, at once, while the pane is still drawn: once it is
// hidden its style is not looked at again, and a rule coming then would never reach them (2026-10-24).
const hiddenPane = `${navTrack}:not([data-sliding]) > ${navScroll}[inert]`;
globalStyle(`${hiddenPane} *, ${hiddenPane} *::before, ${hiddenPane} *::after`, { animation: "none !important" });

export const navFoot = style({ ...band, marginTop: "auto", padding: 8 });
export const navFootRow = style({ display: "flex", alignItems: "center", gap: 4 });
globalStyle(`${navFootRow} ${accountTrigger}`, { flex: 1, minWidth: 0 });
globalStyle(`${navFootRow} > ${iconBtn}, ${navFootRow} > * > ${iconBtn}`, { flex: "none" });

export const navHeading = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", margin: "14px 8px 4px",
  fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted,
});
export const navEmpty = style({ margin: "16px 10px", fontSize: vars.textUi, color: vars.muted });
export const navError = style({ color: vars.red });

export const navRow = style({
  display: "flex", alignItems: "center", gap: 8, minHeight: 32, padding: "6px 10px", lineHeight: "20px", borderRadius: vars.rNav,
  fontSize: vars.textUi, color: vars.text, transition: `background ${vars.dur} ${vars.easeOut}`, cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover },
    '&[aria-current="page"]': { background: vars.selected },
    // Clicked, its page on the way (Sidebar.tsx setGoing): selected already, and the one it leaves no longer.
    '&[data-going="here"]': { background: vars.selected },
    '&[aria-current="page"][data-going="away"]': { background: "none" },
    // Adjacent sidebar items never touch, so a selected or hovered row stays distinct.
    "& + &": { marginTop: 2 },
    // While the list scrolls, rows passing under the pointer do not light up (each would repaint the list).
    [`${navScroll}[data-scrolling] &`]: { pointerEvents: "none" },
  },
});
globalStyle(`${navRow} svg`, { color: vars.muted, flex: "none" });
export const navText = style(ellipsis);
/** The action over a list (SidebarList.tsx NavAction): 新建对话, with the filter beside it; 添加 Station, …. */
export const navNew = style({
  display: "flex", alignItems: "center", gap: 4, padding: "6px 8px 2px",
});
globalStyle(`${navNew} > ${navRow}`, { flex: 1, minWidth: 0 });
/**
 * Folded and shown a while, the bar floats with a corner (shell.css.ts dock: the rail's places' 9 px ground, 6 in): what
 * stands in its top right corner (the lists' filter) is 6 from its top and its side, rounded as the rail's places are,
 * concentric with it; the band ends 6 under it too, not 2 (the lists starting at once under the band).
 */
globalStyle(`[data-sidebar="closed"] ${navNew}`, { paddingRight: 6, paddingBottom: 6 });
globalStyle(`[data-sidebar="closed"] ${navNew} > :last-child:not(${navRow})`, { borderRadius: `calc(9px * ${vars.cornerScale})`, cornerShape: vars.cornerShape });
/** 待处理, under 新建对话 (cloud/workspace.tsx): as inset as it; nothing when there is nothing to do. */
export const navTodo = style({ padding: "2px 8px 8px", selectors: { "&:empty": { display: "none" } } });
/** 新建对话's icon: aligned with the 14px completion check below. */
export const navCompose = style({ transform: "translateX(-1px)" });

// ── a chat's row ──

/** Archiving a chat: a button at the row's bottom right while it is pointed at, in the place of who is in it. */
export const navSessionWrap = style({
  position: "relative", borderRadius: vars.rNav, cornerShape: vars.cornerShape,
  selectors: { "& + &": { marginTop: 2 } },
});
export const navSession = style({
  alignItems: "flex-start", paddingTop: 7, paddingBottom: 7, position: "relative",
  // The row's ground, which gaps round its pictures and marks are cut in (RowPicture.css.ts, ChatMark.css.ts).
  vars: { "--mark-around": vars.sidebar },
  selectors: {
    // Pointing at the button is still pointing at the row.
    [`${navSessionWrap}:hover &:not([aria-current="page"]):not([data-going="here"])`]: { background: vars.hover, vars: { "--mark-around": vars.hover } },
    '&[aria-current="page"], &[data-going="here"]': { vars: { "--mark-around": vars.selected } },
    '&[aria-current="page"][data-going="away"]': { vars: { "--mark-around": vars.sidebar } },
  },
});

/** Who is in a chat, at the second line's end (RowPicture.tsx): gone while the row is pointed at, its time there. */
export const rowAside = style({
  selectors: { [`${navSessionWrap}:hover &`]: { display: "none" } },
});

// One column, as wide as the row leaves it: an auto one grows to a long title's whole length, and the row with it.
export const navSessionText = style({
  display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: 2, minWidth: 0, flex: 1,
});
export const navSessionHead = style({
  display: "flex", alignItems: "center", gap: 6, minWidth: 0, height: 20, lineHeight: "20px",
});
/** The title's mark in a 10px column, the state line's icon (ChatMark.tsx WaitingText `slot`) centred under it; none, no column. */
export const navMarkSlot = style({ display: "flex", flex: "none", width: 10, justifyContent: "center", selectors: { "&:empty": { display: "none" } } });
export const navSessionTitle = style({
  flex: 1, ...ellipsis,
  selectors: {
    [`${navSession}[data-unread] &`]: { fontWeight: 500, color: vars.text },
    // All its pieces of work done or dropped (the core's `settled`), or its station offline: the row stays, its title
    // stepped back to the muted grey. Not faded: at half its ink it was 2.7:1, too faint to read for a row that still
    // opens (docs/ui-panels.md 对比度).
    [`${navSession}:is([data-settled], [data-offline]) &`]: { color: vars.muted },
  },
});
export const navSessionMeta = style({
  display: "flex", alignItems: "center", gap: 6, fontSize: vars.textMeta, color: vars.muted, whiteSpace: "nowrap",
  // Not clipped: the starter's ring (RowPicture.css.ts) stands 2px out of its 16px face, past this 18px line. The last
  // message ellipsizes itself.
  // Every row is two lines high, message or not, so a row that gains its first message does not grow.
  height: 18, lineHeight: "18px",
  // A state line's icon in the mark's column: what follows starts where the title does, the head's gap on.
  vars: { "--lead-gap": "6px" },
  // The time making room for the archive button (rowArchive).
  selectors: { [`${navSessionWrap}:hover &`]: { paddingRight: 24 } },
});
export const navSessionLast = style({
  flex: 1, ...ellipsis, fontSize: vars.textMeta, color: vars.muted,
  // Its turn (something waits on the viewer, ChatMark.tsx WaitingText): in ink.
  // A message that did not go (its row's `unsent`): in red.
  selectors: { "&[data-turn]": { color: vars.text }, "&[data-alert]": { color: vars.red } },
});
/** When is rarely what one looks for in the list: it shows on hover (and keyboard focus), giving its room to the message otherwise. */
export const navTime = style({
  marginLeft: "auto", flex: "none", color: vars.subtle, fontSize: vars.textCaption, fontVariantNumeric: "tabular-nums",
  selectors: {
    [`${navSession} &`]: { display: "none" },
    [`${navSessionWrap}:hover &, ${navSession}:focus-visible &`]: { display: "inline" },
  },
});
/** Where the chat happens (Slack), or that its station is offline or reconnecting: at the title's end. */
export const sessionKind = style({
  display: "inline-grid", flex: "none",
  selectors: {
    // As wide as the agent's mark under it (RowPicture.css.ts asideAgent), so the two are centred on one line.
    [`${navSessionHead} &`]: { width: 16, placeItems: "center" },
    [`${navSession}[data-offline] &`]: { color: vars.subtle },
  },
});
globalStyle(`${sessionKind} ${kindIcon}`, { width: 14, height: 14 });
// A mark has air around it in its artwork: at 16px it reads as big as the 14px platform marks.
globalStyle(`${sessionKind} ${kindMark}`, oversize(1));
/**
 * Archive, beside a row while pointed at: centred on the second line (18px tall, 29px down the row), in the column of
 * who is in the chat (rowAside), which it replaces meanwhile. The title line keeps its marks, the station's in the same
 * column as every other row's.
 */
export const rowArchive = style({
  position: "absolute", top: 26, right: 6, width: 24, height: 24, opacity: 0, pointerEvents: "none",
  selectors: { [`${navSessionWrap}:hover &, &:focus-visible`]: { opacity: 1, pointerEvents: "auto" } },
});

/** Stations not working: a row at the top of the sidebar's foot, over the account; its dot says the worst of it. */
export const stationTrouble = style({ marginBottom: 4, color: vars.text });
export const stationTroubleMark = style({ width: 16, flex: "none", display: "grid", placeItems: "center" });
export const stationTroubleText = style({
  flex: 1, ...ellipsis,
  // Only the words go red: the glyph keeps its ink, a failing station its red dot.
  selectors: { [`${stationTrouble}[data-state="error"] &`]: { color: vars.red } },
});
/** What is waited on: quieter than a station down, it is only slow; the row is no link. */
globalStyle(`${stationTrouble}[data-state="slow"]`, { color: vars.muted });
globalStyle(`${stationTrouble}[role="status"]`, { cursor: "default" });
globalStyle(`${stationTrouble}[role="status"]:hover`, { background: "transparent" });
/** The stations' row and, while down, 重试 at its end (a button, so beside the link, not in it). */
export const stationRow = style({ position: "relative", marginBottom: 4 });
globalStyle(`${stationRow} > ${stationTrouble}`, { marginBottom: 0 });
// Beside the rail, whose glyph says how the stations are (Rail.tsx), the line is there only for what is wrong.
globalStyle(`${stationRow}:not(:has(> ${stationTrouble}[data-state], > * > ${stationTrouble}[data-state]))`, { "@media": { [wide]: { display: "none" } } });
globalStyle(`${stationRow} > ${stationTrouble}[data-retry]`, { paddingRight: 64 });
export const waitingRetry = style({
  flex: "none", height: 22, padding: "0 10px", ...outsetEnd(4), borderRadius: 999, border: 0, cursor: "pointer",
  background: vars.hover, color: vars.text, fontSize: vars.textUi, display: "inline-flex", alignItems: "center", gap: 5,
  selectors: {
    "&:hover:not(:disabled)": litOver,
    "&:disabled": { cursor: "progress" },
    [`${stationRow} > &`]: { position: "absolute", right: 6, top: 5, marginRight: 0 },
  },
});
/** However many there are, within the window: what does not fit scrolls (the tip's own padding is 5px each side). */
export const waitingItems = style({
  display: "grid", gap: 6, maxWidth: 320, maxHeight: "calc(var(--radix-tooltip-content-available-height, 100vh) - 10px)",
  overflowY: "auto",
});
export const waitingItem = style({ display: "grid", gap: 1 });
export const waitingDetail = style({ opacity: 0.7 });
/** Under a page's "loading…": quiet. */
export const statusLine = style({ display: "block", marginTop: 4, fontSize: vars.textMeta, color: vars.muted });

/** The foot's status line: the stations, and the services left up long beside them (cloud/workspace.tsx). */
export const navFootStatus = style({ display: "flex", alignItems: "center", gap: "6px", minWidth: 0, marginBottom: 4, selectors: { "&:empty": { marginBottom: 0 } } });
globalStyle(`${navFootStatus} > :first-child`, { flex: "1", minWidth: 0 });
// The line keeps the gap under it, not the stations' row: with the row's own margin the chip beside it centred 2px low.
globalStyle(`${navFootStatus} > :is(${stationRow}, ${stationTrouble})`, { marginBottom: 0 });
