// The rail at the wide screen's left (Rail.tsx): a column in the sidebar's block (styles/shell.css.ts dock), the places as icons.
import { globalStyle, style } from "@vanilla-extract/css";
import { navFoot, stationRow, stationTrouble } from "./Sidebar.css.ts";
import { floatingThumb } from "./scrollbars.css.ts";
import { dock } from "./styles/shell.css.ts";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { outsetBottom, TEXT_IN } from "@stillfail/ui/styles/align.ts";

const wide = "(min-width: 701px)";
const narrow = "(max-width: 700px)";

export const rail = style({
  // Its last place's ground (30 in 38) as far from its foot as from its sides: 13.
  display: "flex", flexDirection: "column", alignItems: "center", gap: 6, padding: "0 0 9px", flex: "none", width: 56,
  userSelect: "none",
  // A window too short for every place: they scroll (its bar floating, scrollbars.ts), not squashed.
  overflowY: "auto", scrollbarWidth: "none",
  // In the closed bar (shell.css.ts dock), as narrow as it: moved with it (brand.tsx moveSidebar), not by a transition of
  // its own, which starting a frame later and eased apart from the bar's margins shook the places as it went.
  // In the closed bar (42 wide) its places' ground 6 px from its every edge (4 of it within the place), the bar's
  // corner concentric with theirs.
  selectors: { '[data-sidebar="closed"] &': { width: 42, paddingTop: 2, paddingBottom: 2 } },
  "@media": { [narrow]: { display: "none" } },
});
// Each place its own 38 (its ground 30 square), however short the window; a place's slot is display: contents.
globalStyle(`${rail} > *, ${rail} > [data-rail-item] > *`, { flexShrink: 0 });
/**
 * Level with the sidebar's top row (empty: its brand is gone beside the rail). In the closed bar (shell.css.ts dock) no
 * more than a margin; it shrinks with the bar (moved with it, as the rail).
 */
export const top = style({
  // Nothing is in the sidebar's top row either: a margin, as there. Its first place's ground (30) level with the
  // sidebar's first row (新对话, 32 from 14 down there): its middle at 30, 3 above the gap's 6 and its 4 within.
  flex: "none", alignSelf: "stretch", height: 5,
  selectors: {
    // In the closed bar nothing: its places stand as far from its top as from its sides (rail's padding).
    '[data-sidebar="closed"] &': { height: 0, ...outsetBottom(6) },
  },
});
/**
 * The sidebar's edge (Rail.tsx SidebarEdge), as Cue's rail handle: a strip over the sidebar's block's edge,
 * with a short bar at its middle: shown only with the pointer on the strip (not anywhere over the sidebar, nor as the
 * mouse moves), darker pressed.
 */
export const edge = style({
  // On the sidebar's edge, its bar on the line itself; by the closed bar, between it and the page. Moved with the
  // sidebar's column (brand.tsx's toggle).
  position: "absolute", zIndex: 30, top: 0, bottom: 0, left: "calc(56px + var(--sidebar-w, 240px) - 6px)", width: 12,
  padding: 0, border: 0, background: "none",
  cursor: "col-resize", touchAction: "none", outline: "none",
  selectors: {
    // By the page's root, not its own data-closed (set a render later): the sidebar's toggle reads its end in the same
    // frame it closes the sidebar, and moves it there with the column (brand.tsx moveState), not after it, at once.
    // By the closed bar (6 to 48), its bar (4 in, 5 wide) in the gutter to the page (48 to 56): 50 to 55.
    '[data-sidebar="closed"] &': { cursor: "pointer", left: 46 },
    // By the folded sidebar shown a while (shell.css.ts dock): at its edge, pressed to keep it open.
    '[data-sidebar="closed"][data-sidebar-peek] &': { left: "calc(46px + var(--sidebar-w, 240px))" },
    // A page with no sidebar of its own: no edge to open one by.
    "[data-sidebar-none] &": { display: "none" },
    "&::after": {
      // Odd widths on whole pixels, the bar's middle and the line's one (left 6, 1 wide; left 4, 5 wide).
      content: '""', position: "absolute", top: "50%", left: 4, width: 5, height: 24, borderRadius: 999,
      background: vars.lineStrong, opacity: 0, transform: "translateY(-50%)",
      transition: `height 180ms ${vars.easeOut}, opacity 180ms ${vars.easeOut}, background-color 150ms ${vars.easeOut}`,
    },
    // The line itself (the hairline of the other edges, ui.css.ts resizeHandle), on hover and while dragged.
    "&::before": {
      content: '""', position: "absolute", top: 8, bottom: 8, left: 6, width: 1, borderRadius: 999,
      background: `linear-gradient(to bottom, transparent 10%, ${vars.fieldHover} 50%, transparent 90%)`,
      opacity: 0, transition: `opacity 140ms ${vars.easeOut}`,
    },
    "&:not([data-closed]):hover::before, &[data-active]::before": { opacity: 1 },
    "&:hover::after, &:focus-visible::after, &[data-active]::after": { height: 48, opacity: 1 },
    "&:active::after, &[data-active]::after": { background: vars.fieldHover },
  },
  "@media": { [narrow]: { display: "none" } },
});
// A scrollbar in the sidebar (scrollbars.ts) a pixel clear of the edge's line, not on it.
globalStyle(`${dock} *`, { "@media": { [wide]: { scrollPaddingRight: 1 } } });
// In the closed bar (shown a while too) its panes end in its rounded corner: their bars stop short of it (scrollbars.ts
// endOf), not running out past the curve when scrolled to the end. Its foot band, when there is one, is taller.
globalStyle(`:root[data-sidebar="closed"] ${dock} *`, {
  "@media": { [wide]: { scrollPaddingBottom: `max(var(--nav-foot, 0px), calc(9px * ${vars.cornerScale} + 6px))` } },
});
// Its scrollbar gone as the sidebar starts to close (fixed, the bar's clipping does not cut it), not left a moment over
// the closing bar or the page.
globalStyle(`:root[data-sidebar="closed"]:not([data-sidebar-peek]) ${dock} ${floatingThumb}`, { "@media": { [wide]: { visibility: "hidden" } } });
export const grow = style({ flex: 1 });

/**
 * A place: 38 to press, its ground (hovered, lit) as large as a workspace's square (30, the same corner) and drawn
 * under the icon.
 */
export const item = style({
  position: "relative", display: "grid", placeItems: "center", width: 38, height: 38, padding: 0, border: 0,
  background: "none", color: vars.muted, cursor: "pointer", isolation: "isolate",
  transition: `color ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&::before": {
      content: '""', position: "absolute", inset: 4, zIndex: -1, borderRadius: `calc(9px * ${vars.cornerScale})`,
      cornerShape: vars.cornerShape, transition: `background ${vars.dur} ${vars.easeOut}`,
    },
    "&:hover": { color: vars.text },
    "&:hover::before": { background: vars.hover },
    "&[data-on]": { color: vars.text },
    "&[data-on]::before": { background: vars.selected },
    // On the closed bar's floating ground (shell.css.ts dock), raised in dark: lit by the words' colour, as plain a step
    // above it as the selected grey is above the sidebar.
    '[data-sidebar="closed"] &[data-on]::before': { background: `color-mix(in srgb, ${vars.text} 12%, transparent)` },
    // Focused from the keyboard: the ring round its ground, not its 38 (which, the last place, reaches 4 from the
    // block's foot but 9 from its side), as far from the block's edges every way.
    "&:focus-visible": { outline: "none" },
    "&:focus-visible::before": { outline: `2px solid ${vars.fieldFocus}`, outlineOffset: 1 },
  },
});
/** What waits on a place: a small dot on the icon's corner (how many is in its tip), cut out of the rail's ground. */
export const count = style({
  position: "absolute", top: 6, right: 6, width: 8, height: 8, borderRadius: "50%", background: vars.red,
  boxShadow: `0 0 0 2px ${vars.sidebar}`,
});

/**
 * What wants the person in a list of chats (Rail.tsx), as their rows' marks: on its icon's corner, cut out of the rail's
 * ground, only while the sidebar is closed (open, the rows show it); shown a while over the page (peek) it stays. Grown
 * in as the sidebar closes, shrunk away as it opens.
 */
export const listMark = style({
  position: "absolute", top: 3, right: 3, display: "flex", padding: 2, borderRadius: "50%", background: vars.sidebar,
  pointerEvents: "none", transformOrigin: "center", opacity: 1, transform: "scale(1)",
  // Moved with the sidebar (brand.tsx moveSidebar).
  selectors: { ':root:not([data-sidebar="closed"]) &': { opacity: 0, transform: "scale(0.4)" } },
});

/**
 * The workspaces to switch to (Rail.tsx RailWorkspaces), each on a square as large as the places' ground above them: a
 * letter on one of its own, a mark (an icon, an emoji, a picture a little smaller) on nothing. Under the pointer, the
 * places' ground; the one in view, a short bar at its left and no ground (a ground under a mark greyed an icon's colours
 * and showed round a picture).
 */
export const workspaces = style({ display: "flex", flexDirection: "column", alignItems: "center", gap: 6, padding: "4px 0" });
export const workspaceItem = style({
  position: "relative", display: "grid", placeItems: "center", width: 30, height: 30, padding: 0, border: 0,
  borderRadius: `calc(9px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: vars.hover, color: vars.muted,
  fontSize: vars.textUi, fontWeight: 600, cursor: "pointer", transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { color: vars.text },
    "&[data-marked]": { background: "none", color: vars.text },
    "&[data-marked]:hover": { background: vars.hover },
    "&[data-on]": { color: vars.text },
  },
});
// The one in view: a short bar in the margin at its left (inside the closed bar too).
globalStyle(`${workspaceItem}[data-on]::before`, {
  content: "", position: "absolute", left: -6, top: 8, width: 3, height: 14, borderRadius: 2, background: vars.text,
});
// A picture inside the square as an icon is, rounded as the square is.
globalStyle(`${workspaceItem}[data-picture] img`, { borderRadius: `calc(6px * ${vars.cornerScale})`, cornerShape: vars.cornerShape });
/** Over the workspaces: making one, another account, invitations (its menu), a ＋ alone (no frame), seen as the pointer comes. */
export const workspaceAdd = style({
  position: "relative", display: "grid", placeItems: "center", width: 30, height: 30, padding: 0, border: 0,
  borderRadius: `calc(9px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: "none", color: vars.muted, cursor: "pointer",
  opacity: 0, transition: `opacity ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover, &[data-state=open]": { color: vars.text, background: vars.hover },
    // Out of sight until the pointer is over the workspaces (or it is reached by keys, open, or an invitation waits).
    [`${workspaces}:hover &, &:focus-visible, &[data-state=open], &:has([role=img])`]: { opacity: 1 },
  },
  "@media": { "(hover: none)": { opacity: 1 } },
});
export const mark = style({ position: "absolute", top: -4, right: -4, display: "flex", padding: 2, borderRadius: "50%", background: vars.sidebar });

/** What is about the rail: nothing on a narrow screen. */
export const wideOnly = style({ "@media": { [narrow]: { display: "none" } } });
/** What the rail holds, on a narrow screen (no rail there) in the sidebar's foot as before. */
export const narrowOnly = style({ "@media": { [wide]: { display: "none" } } });

/** A station's dot, at the end of its row and of a folder's it lends (SidebarList.tsx NavItem `end`): grey while away. */
export const dot = style({
  width: 6, height: 6, borderRadius: "50%", background: vars.subtle, flex: "none",
  selectors: { "&[data-online]": { background: vars.online } },
});

// ── changing it (Rail.tsx: its menu's 自定义侧边条, or 外观's) ──

/** A place in the rail as it is: nothing of its own in the layout (its menu finds it by `data-rail-item`). */
export const slot = style({ display: "contents" });
// Dragged with ⌘ held (Rail.tsx moves it with the pointer): lifted, over the others.
globalStyle(`${slot}[data-dragged] > *`, { zIndex: 1, cursor: "grabbing", color: vars.text });
globalStyle(`${slot}[data-dragged] > *::before`, { background: vars.selected, boxShadow: `0 6px 16px ${vars.shadow}` });
/** A place while the rail is changed: dragged up or down to where it goes, a − at its corner to take it out. */
export const editing = style({
  position: "relative", borderRadius: `calc(12px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, cursor: "grab", touchAction: "none",
  outline: `1.5px dashed ${vars.lineStrong}`, outlineOffset: -1,
  // Lifted while dragged (Rail.tsx moves it with the pointer).
  transition: `box-shadow ${vars.dur} ${vars.easeOut}`,
  selectors: { "&[data-dragged]": { cursor: "grabbing", background: vars.selected, outlineStyle: "solid", zIndex: 1, boxShadow: `0 6px 16px ${vars.shadow}` } },
});
/** What the place draws, not pressed while it is moved. */
export const still = style({ pointerEvents: "none" });
export const remove = style({
  position: "absolute", top: -5, left: -5, display: "grid", placeItems: "center", width: 18, height: 18, padding: 0, border: 0,
  borderRadius: "50%", background: vars.text, color: vars.sidebar, cursor: "pointer", boxShadow: `0 0 0 2px ${vars.sidebar}`,
  // In the closed bar (42) a place's slot is 2 from the rail's edge, which cuts what stands past it (the rail scrolls in a
  // short window): the − within its slot's corner there, its ring too.
  selectors: { '[data-sidebar="closed"] &': { top: 1, left: 1 } },
});
/** The panel beside the rail of what can be added (ui.tsx Panel* parts), no button: pressing elsewhere ends it. */
export const adder = style({ width: 248, display: "grid", gap: 8 });

// Beside the rail the sidebar's foot has nothing of its own (the switcher and settings are the rail's, the stations' line
// only for what is wrong, and that in the rail's bell when the bell is there): gone when there is nothing in it shown, not
// an empty frosted band under the list.
// (Two :has, side by side: one inside another is not CSS.)
globalStyle(`[data-rail] ${navFoot}:not(:has(:is(a, button):not(${narrowOnly} *, ${stationRow} *))):not(:has(${stationTrouble}[data-state]:not(${narrowOnly} *)))`, {
  "@media": { [wide]: { display: "none" } },
});

// ── 下载客户端 (Rail.tsx RailDownload): on the web only, its panel the site's download card in the app's panel ──

export const download = style({ width: 232, display: "grid", gap: 2 });
/** An app's row: its name, a word on which build, the download arrow at the end; a link, its ground on hover. */
export const downloadRow = style({
  textDecoration: "none",
  selectors: { "&:hover": { background: vars.hover }, "&:focus-visible": { outline: `2px solid ${vars.fieldFocus}`, outlineOffset: -2 } },
});
export const downloadName = style({ fontWeight: 600, marginRight: 6 });
export const downloadNote = style({ color: vars.muted });
/** Android's: the code to scan, on white whatever the theme (it is drawn black on nothing), and what to do with it. */
// The code's white square in by its own padding less than the rows' words, its drawing on their line.
export const downloadScan = style({ display: "flex", alignItems: "center", gap: 10, padding: `8px ${TEXT_IN}px 8px ${TEXT_IN - 5}px`, minHeight: 0 });
export const downloadQr = style({
  width: 72, height: 72, padding: 5, flex: "none", background: "#fff", borderRadius: `calc(8px * ${vars.cornerScale})`,
  cornerShape: vars.cornerShape,
});

/** A place's + in the rail's menu (Rail.tsx), at its row's end: put in the rail and the rail's change begun. */
export const menuAdd = style({
  display: "grid", placeItems: "center", width: 24, height: 24, marginLeft: "auto", padding: 0, border: 0, borderRadius: 999,
  background: "none", color: vars.muted, cursor: "pointer", opacity: 0,
  // Only on its row pointed at (or reached from the keyboard).
  selectors: {
    "[data-highlighted] > &, &:focus-visible": { opacity: 1 },
    "&:hover": { background: vars.hover, color: vars.text },
  },
});
