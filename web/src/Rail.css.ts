// The rail at the wide screen's left (Rail.tsx): a column in the sidebar's block (styles/shell.css.ts dock), the places as icons.
import { globalStyle, style } from "@vanilla-extract/css";
import { navFoot, stationRow, stationTrouble } from "./Sidebar.css.ts";
import { dock } from "./styles/shell.css.ts";
import { vars } from "./styles/tokens.css.ts";

const wide = "(min-width: 701px)";
const narrow = "(max-width: 700px)";

export const rail = style({
  display: "flex", flexDirection: "column", alignItems: "center", gap: 6, padding: "0 0 12px", flex: "none", width: 56,
  WebkitUserSelect: "none", userSelect: "none",
  // In the closed bar (shell.css.ts dock), as narrow as it, at the same pace.
  transition: `width 380ms ${vars.easeOut}, padding 380ms ${vars.easeOut}`,
  // In the closed bar (42 wide) its places' ground 6 px from its every edge (4 of it within the place), the bar's
  // corner concentric with theirs.
  selectors: { '[data-sidebar="closed"] &': { width: 42, paddingTop: 2, paddingBottom: 2 } },
  "@media": { [narrow]: { display: "none" }, "(prefers-reduced-motion: reduce)": { transition: "none" } },
});
/**
 * Level with the sidebar's top row (empty: its brand is gone beside the rail). In the desktop app the row drags the
 * window; on macOS its buttons are in it (main.ts puts them 16 px in, reaching past the rail). In the closed bar (shell.css.ts
 * dock), which starts under that row, no more than a margin; it shrinks with the bar, as long and eased.
 */
export const top = style({
  flex: "none", alignSelf: "stretch", height: 48, transition: `height 380ms ${vars.easeOut}`,
  selectors: {
    "[data-desktop] &": { height: 44, WebkitAppRegion: "drag" },
    // In the closed bar nothing: its places stand as far from its top as from its sides (rail's padding).
    '[data-sidebar="closed"] &': { height: 0, marginBottom: -6 },
  },
});
/**
 * The sidebar's edge (Rail.tsx SidebarEdge), as Cue's rail handle: a strip over the sidebar's block's edge,
 * with a short bar at its middle: shown as the pointer is over the sidebar, longer on the strip, darker pressed; by the
 * closed bar, shown a second as the mouse moves.
 */
export const edge = style({
  // On the sidebar's edge, its bar on the line itself; by the closed bar, between it and the page. Moved with the
  // sidebar's column (brand.tsx's toggle).
  position: "absolute", zIndex: 30, top: 0, bottom: 0, left: "calc(56px + var(--sidebar-w, 240px) - 6px)", width: 12,
  padding: 0, border: 0, background: "none",
  cursor: "col-resize", touchAction: "none", outline: "none", WebkitAppRegion: "no-drag",
  selectors: {
    "&[data-closed]": { cursor: "pointer", left: 47 },
    "&::after": {
      // Odd widths on whole pixels, the bar's middle and the line's one (left 6, 1 wide; left 4, 5 wide).
      content: '""', position: "absolute", top: "50%", left: 4, width: 5, height: 24, borderRadius: 999,
      background: vars.lineStrong, opacity: 0, transform: "translateY(-50%)",
      transition: `height 180ms cubic-bezier(.16, 1, .3, 1), opacity 180ms cubic-bezier(.16, 1, .3, 1), background-color 150ms ${vars.easeOut}`,
    },
    // The line itself (the hairline of the other edges, ui.css.ts resizeHandle), on hover and while dragged.
    "&::before": {
      content: '""', position: "absolute", top: 8, bottom: 8, left: 6, width: 1, borderRadius: 999,
      background: `linear-gradient(to bottom, transparent 10%, ${vars.fieldHover} 50%, transparent 90%)`,
      opacity: 0, transition: `opacity 140ms ${vars.easeOut}`,
    },
    "&:not([data-closed]):hover::before, &[data-active]::before": { opacity: 1 },
    "&[data-moving]::after": { opacity: 1 },
    "&:hover::after, &:focus-visible::after, &[data-active]::after": { height: 48, opacity: 1 },
    "&:active::after, &[data-active]::after": { background: vars.fieldHover },
  },
  "@media": { [narrow]: { display: "none" }, "(prefers-reduced-motion: reduce)": { selectors: { "&::after": { transition: "none" } } } },
});
// The pointer over the sidebar (its block, before the page): the bar is there to find.
globalStyle(`${dock}:hover ~ ${edge}::after`, { opacity: 1 });
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
  },
});
/** 奏, the word, its size the icons' (vars.textTitle is the nearest of the type sizes). */
export const zou = style({ fontSize: vars.textTitle, lineHeight: "20px", fontWeight: 600 });
/** What waits on a place: a small dot on the icon's corner (how many is in its tip), cut out of the rail's ground. */
export const count = style({
  position: "absolute", top: 6, right: 6, width: 8, height: 8, borderRadius: "50%", background: vars.red,
  boxShadow: `0 0 0 2px ${vars.sidebar}`,
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

/** The places the stations lend (FilesNav): under each station's name, its folders. */
export const station = style({
  display: "flex", alignItems: "center", gap: 6, margin: "14px 10px 4px", fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted,
  selectors: { "&:first-child": { marginTop: 6 } },
});
export const dot = style({
  width: 6, height: 6, borderRadius: "50%", background: vars.subtle, flex: "none",
  selectors: { "&[data-online]": { background: vars.online } },
});

// ── changing it (Rail.tsx: its menu's 自定义侧边条, or 外观's) ──

/** A place in the rail as it is: nothing of its own in the layout (its menu finds it by `data-rail-item`). */
export const slot = style({ display: "contents" });
/** A place while the rail is changed: dragged up or down to where it goes, a − at its corner to take it out. */
export const editing = style({
  position: "relative", borderRadius: `calc(12px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, cursor: "grab", touchAction: "none",
  outline: `1.5px dashed ${vars.lineStrong}`, outlineOffset: -1,
  selectors: { "&[data-dragged]": { cursor: "grabbing", background: vars.selected, outlineStyle: "solid", zIndex: 1 } },
});
/** What the place draws, not pressed while it is moved. */
export const still = style({ pointerEvents: "none" });
export const remove = style({
  position: "absolute", top: -5, left: -5, display: "grid", placeItems: "center", width: 18, height: 18, padding: 0, border: 0,
  borderRadius: "50%", background: vars.text, color: vars.sidebar, cursor: "pointer", boxShadow: `0 0 0 2px ${vars.sidebar}`,
});
/** The panel beside the rail of what can be added (ui.tsx Panel* parts), no button: pressing elsewhere ends it. */
export const adder = style({
  width: 248, display: "grid", gap: 8,
  // More room than a menu: over the popover's own, whichever sheet comes first; its rows concentric with it.
  selectors: { "&[data-side]": { vars: { "--panel-pad": "12px", "--panel-in": `calc(${vars.rMenu} - 12px)` } } },
});
export const zouSmall = style({ fontSize: vars.textBody, lineHeight: "18px", fontWeight: 600 });

// Beside the rail the sidebar's foot has nothing of its own (the switcher and settings are the rail's, the stations' line
// only for what is wrong): gone when there is nothing in it, not an empty frosted band under the list.
// (Two :has, side by side: one inside another is not CSS.)
globalStyle(`[data-rail] ${navFoot}:not(:has(:is(a, button):not(${narrowOnly} *, ${stationRow} *))):not(:has(${stationTrouble}[data-state]))`, {
  "@media": { [wide]: { display: "none" } },
});
