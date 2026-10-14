// The rail at the wide screen's left (Rail.tsx): a column of the sidebar's own ground, the places as icons.
import { globalStyle, style } from "@vanilla-extract/css";
import { navFoot, stationRow, stationTrouble } from "./Sidebar.css.ts";
import { vars } from "./styles/tokens.css.ts";

const wide = "(min-width: 701px)";
const narrow = "(max-width: 700px)";

export const rail = style({
  display: "flex", flexDirection: "column", alignItems: "center", gap: 6, padding: "0 0 12px", background: vars.sidebar,
  WebkitUserSelect: "none", userSelect: "none",
  position: "relative", isolation: "isolate",
  selectors: {
    // With the sidebar closed the rail is no band of ground but a long rounded block standing on the page (its ::before),
    // clear of the page's edges and, in the macOS app, under the window's buttons (wider than it).
    '[data-sidebar="closed"] &': { background: vars.canvas },
    '&::before': {
      content: '""', position: "absolute", zIndex: -1, inset: 0, background: vars.sidebar, borderRadius: 0,
      cornerShape: vars.cornerShape, transition: `inset 240ms ${vars.easeOut}, border-radius 240ms ${vars.easeOut}`,
    },
    // Concentric with what is lit in it (the items' 12 px corner, 3 px in from its sides).
    '[data-sidebar="closed"] &::before': { inset: "8px 6px", borderRadius: `calc(12px * ${vars.cornerScale} + 3px)` },
    '[data-desktop="inset"]:not([data-fullscreen])[data-sidebar="closed"] &::before': { top: 44 },
  },
  "@media": { [narrow]: { display: "none" }, "(prefers-reduced-motion: reduce)": { selectors: { "&::before": { transition: "none" } } } },
});
/**
 * Level with the sidebar's top row, the sidebar's opening and closing in it. In the desktop app the row drags the window;
 * on macOS its buttons are in it (main.ts puts them 16 px in, reaching past the rail), and the toggle comes under them.
 */
export const top = style({
  flex: "none", alignSelf: "stretch", display: "flex", alignItems: "center", justifyContent: "center", height: 48, marginBottom: 6,
  // Its height follows the sidebar closing as the rounded block does (rail ::before): the places glide, not jump.
  transition: `height 240ms ${vars.easeOut}`,
  selectors: {
    "[data-desktop] &": { height: 44, WebkitAppRegion: "drag" },
    '[data-desktop="inset"]:not([data-fullscreen]) &': { height: 88, alignItems: "flex-end" },
    // In the closed sidebar's rounded block (rail ::before), clear of its top.
    '[data-sidebar="closed"] &': { height: 56, alignItems: "flex-end" },
    '[data-desktop="inset"]:not([data-fullscreen])[data-sidebar="closed"] &': { height: 94 },
  },
});
globalStyle(`[data-desktop] ${top} > *`, { WebkitAppRegion: "no-drag" });
/** The panel icons are drawn for a panel at the right: turned round for the sidebar at the left. */
export const mirrored = style({ transform: "scaleX(-1)" });
export const grow = style({ flex: 1 });

export const item = style({
  position: "relative", display: "grid", placeItems: "center", width: 38, height: 38, padding: 0, border: 0,
  borderRadius: `calc(12px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: "none", color: vars.muted,
  cursor: "pointer", transition: `background ${vars.dur} ${vars.easeOut}, color ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
    "&[data-on]": { background: vars.selected, color: vars.text },
  },
});
/** 奏, the word, its size the icons' (vars.textTitle is the nearest of the type sizes). */
export const zou = style({ fontSize: vars.textTitle, lineHeight: "20px", fontWeight: 600 });
/** What waits on a place: a small dot on the icon's corner (how many is in its tip), cut out of the rail's ground. */
export const count = style({
  position: "absolute", top: 6, right: 6, width: 8, height: 8, borderRadius: "50%", background: vars.red,
  boxShadow: `0 0 0 2px ${vars.sidebar}`,
});

/** The workspaces to switch to (Rail.tsx RailWorkspaces), each its first letter, the one in view ringed. */
export const workspaces = style({ display: "flex", flexDirection: "column", alignItems: "center", gap: 6, padding: "4px 0" });
export const workspaceItem = style({
  position: "relative", display: "grid", placeItems: "center", width: 30, height: 30, padding: 0, border: 0,
  borderRadius: `calc(9px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: vars.hover, color: vars.muted,
  fontSize: vars.textUi, fontWeight: 600, cursor: "pointer",
  selectors: {
    "&:hover": { color: vars.text },
    "&[data-on]": { background: vars.text, color: vars.sidebar },
  },
});
/** Over the workspaces: making one, another account, invitations (its menu), a dashed square seen as the pointer comes. */
export const workspaceAdd = style({
  position: "relative", display: "grid", placeItems: "center", width: 30, height: 30, padding: 0,
  border: `1.5px dashed ${vars.lineStrong}`, borderRadius: `calc(9px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: "none", color: vars.muted, cursor: "pointer",
  opacity: 0, transition: `opacity ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover, &[data-state=open]": { color: vars.text, borderColor: vars.fieldHover },
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
