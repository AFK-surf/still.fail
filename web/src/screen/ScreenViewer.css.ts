// A station's screen seen (and driven) in the app (ScreenViewer.tsx): the picture fitted in the window, letterboxed
// on the app's own ground (light or dark as the app is), and the controls over it as a media viewer's are. With a
// mouse the bar every file opened has (ViewerBar) along the top, always there, the picture below it; on a phone frosted
// bars above and below the picture, which stays clear of them.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { pictureGlass as glass } from "@stillfail/ui/styles/glass.ts";
import { IN, PANEL_PAD, PANEL_PILL, TEXT_IN, centred, centredX, pillInner } from "@stillfail/ui/styles/align.ts";
import { panelCard, popover } from "@stillfail/ui/styles/controls.css.ts";
import { VIEWER_BAR } from "@stillfail/ui/viewer/ViewerBar.css.ts";

/** The page it is on, over the whole window (as a file opened is: pages/Drive.css.ts opened). */
export const page = style({
  position: "fixed", inset: "0", zIndex: "61", overflow: "hidden", background: vars.canvas,
  selectors: { ':root[data-desktop="inset"]:not([data-fullscreen]) &': { vars: { "--m-top": "30px" } } },
});

/** Phone: the bars' heights and how far from the edges they float. */
const HEAD = 44;
const FOOT = 48;
/** The keys row over the foot while driving (Esc, Tab, the modifiers, the arrows). */
const KEYS = 44;
const EDGE = 12;
const GAP = 8;

export const viewer = style({
  position: "absolute", inset: "0", overflow: "hidden", background: vars.canvas, color: vars.text,
  userSelect: "none", WebkitUserSelect: "none",
});

/** Where the picture is, and where the pointer and fingers are heard (none of the browser's own gestures here). */
export const stage = style({
  position: "absolute", inset: "0", overflow: "hidden", touchAction: "none",
  selectors: {
    // With a mouse, below the bar: what is at the screen's top (its windows' title bars) is never under it.
    [`${viewer}:not([data-phone]) &`]: { top: `${VIEWER_BAR}px` },
    // On a phone, between its bars: they stay, so they never cover it.
    [`${viewer}[data-phone] &`]: {
      top: `calc(var(--m-top, 0px) + max(${EDGE}px, var(--safe-top)) + ${HEAD + GAP}px)`,
      bottom: `calc(max(${EDGE}px, var(--safe-bottom)) + ${FOOT + GAP}px)`,
      left: "var(--safe-left)", right: "var(--safe-right)",
    },
    [`${viewer}[data-phone][data-keys] &`]: { bottom: `calc(max(${EDGE}px, var(--safe-bottom)) + ${FOOT + GAP + KEYS + GAP}px)` },
    // 全屏: the whole window.
    [`${viewer}[data-phone][data-full] &`]: { top: "0", bottom: "0", left: "0", right: "0" },
    // The desktop app's window is dragged by the page's top: not over a screen being driven.
    "[data-desktop] &": { WebkitAppRegion: "no-drag" },
  },
});

/** The picture's box, placed and sized by the page as it fits (ScreenViewer.tsx place): its rect is the frame's. */
export const picture = style({
  position: "absolute", left: "0", top: "0", width: "0", height: "0", visibility: "hidden",
  transition: `opacity 240ms ${vars.easeOut}`,
  selectors: {
    "&[data-shown]": { visibility: "visible" },
    // Over (ended, gone…): the last picture stays, faded under what it says.
    "&[data-faded]": { opacity: ".35" },
  },
});
export const canvas = style({ display: "block", width: "100%", height: "100%" });

/** The station's pointer, where it says it is (none while a mouse here drives: it is that mouse's own). */
export const cursor = style({ position: "absolute", left: "0", top: "0", width: "0", height: "0", pointerEvents: "none" });
globalStyle(`${cursor} svg`, {
  display: "block", width: "var(--pointer, 18px)", height: "var(--pointer, 18px)",
  // The arrow's tip (4, 2 of its 18) on the point, at any size.
  translate: "calc(var(--pointer, 18px) * -4 / 18) calc(var(--pointer, 18px) * -2 / 18)",
  filter: "drop-shadow(0 1px 1px rgba(0, 0, 0, .35))",
});

/** Hears the keys while driving (an IME composes in it, a phone's keyboard comes up for it); never seen. */
export const keys = style({
  position: "absolute", left: "0", bottom: "0", width: "1px", height: "1px", padding: "0", border: "0", opacity: "0",
  resize: "none", overflow: "hidden", pointerEvents: "none", color: "transparent", background: "transparent",
  // A phone zooms into a field with smaller type.
  fontSize: vars.textInput,
});

/** Over, or never seen: what happened and what can be done, a small panel in the middle (docs/ui-panels.md). */
export const note = style([popover, panelCard, {
  vars: { [IN]: pillInner(PANEL_PAD, PANEL_PILL, vars.cornerScale) },
  position: "absolute", zIndex: "3", ...centred, display: "flex", flexDirection: "column", gap: "8px",
  width: "min(320px, calc(100% - 32px))", boxSizing: "border-box", color: vars.text, fontSize: vars.textUi, lineHeight: "19px",
  animation: "none",
}]);
export const noteWords = style({ display: "grid", gap: "4px" });
export const noteTitle = style({ fontWeight: "600" });
export const noteWhy = style({ color: vars.muted, fontSize: vars.textMeta, lineHeight: "17px", overflowWrap: "anywhere" });
/** Its buttons at the panel's padding (panelEdge), the last in its corner, concentric with it. */
export const noteFoot = style({ display: "flex", justifyContent: "flex-end", gap: "6px" });

/** 只看 / 控制 in the desktop's bar: no taller than the bar's other tools need. */
export const mode = style({ display: "flex", flex: "none" });
/** 控制 for a read-only member (or not live): there, but not to be had. */
globalStyle(`${mode} [data-disabled]`, { opacity: ".4", cursor: "default" });

// ── a phone's bars ──

/**
 * The way back, the name and what the core says of the view (只看 or 控制, who else is on it), floating at the top: a
 * pill 6 round what it holds, so the way back (a circle) is concentric with its end.
 */
export const head = style({
  ...glass,
  position: "absolute", zIndex: "3", top: `calc(var(--m-top, 0px) + max(${EDGE}px, var(--safe-top)))`, ...centredX,
  display: "flex", alignItems: "center", gap: "6px", width: "max-content", maxWidth: "calc(100% - 24px)", boxSizing: "border-box",
  height: `${HEAD}px`, padding: "6px", borderRadius: "999px", color: vars.text,
  selectors: { "[data-desktop] &": { WebkitAppRegion: "no-drag" } },
});
export const back = style({
  display: "grid", placeItems: "center", flex: "none", width: "32px", height: "32px", padding: "0", border: "0", borderRadius: "50%",
  background: "none", color: vars.text, cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover } },
});
export const headText = style({ display: "grid", minWidth: "0", paddingInlineEnd: "10px", lineHeight: "1.2" });
globalStyle(`${headText} b`, { fontSize: vars.textUi, fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${headText} small`, { color: vars.muted, fontSize: vars.textCaption, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });

/** 只看 / 控制 and the keyboard, floating at the foot: a pill 6 round the switch and the keyboard, both pills. */
export const foot = style({
  ...glass,
  position: "absolute", zIndex: "3", bottom: `max(${EDGE}px, var(--safe-bottom))`, ...centredX,
  display: "flex", alignItems: "center", gap: "8px", width: "max-content", maxWidth: "calc(100% - 24px)", boxSizing: "border-box", height: `${FOOT}px`, padding: "6px", borderRadius: "999px",
  selectors: { "[data-desktop] &": { WebkitAppRegion: "no-drag" } },
});
/** The keyboard: a circle as tall as the switch beside it. */
export const keyboard = style({
  display: "grid", placeItems: "center", flex: "none", width: "36px", height: "36px", padding: "0", border: "0", borderRadius: "50%",
  background: `color-mix(in srgb, ${vars.text} 6%, transparent)`, color: vars.text, cursor: "pointer",
  selectors: {
    "&[aria-pressed=true]": { background: vars.accent, color: "#fff" },
    "&:disabled": { opacity: ".4", cursor: "default" },
  },
});

/** Someone else driving it, and 接管: in the desktop's bar where 只看/控制 is, in the phone's foot. */
export const takeOverTools = style({ display: "flex", alignItems: "center", gap: "10px", minWidth: "0" });
/** Who drives it now: set apart from the plain line by its dot (someone at work, as a chat's) and its weight. */
export const controllers = style({
  display: "flex", alignItems: "center", gap: "6px", minWidth: "0", color: vars.text, fontSize: vars.textUi, fontWeight: "500",
  selectors: { [`${foot} &`]: { paddingInlineStart: "12px" } },
});
export const controllersDot = style({ flex: "none", width: "8px", height: "8px", borderRadius: "50%", background: vars.amber });
export const controllersText = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const takeOver = style({ flex: "none" });

/**
 * The keys a phone's keyboard has not, floating over the foot while driving: a pill 4 round its keys (pills too), as
 * wide as the screen lets it be, the keys sharing it alike (all of them in sight, as a keyboard's row).
 */
export const keysRow = style({
  ...glass,
  position: "absolute", zIndex: "3", bottom: `calc(max(${EDGE}px, var(--safe-bottom)) + ${FOOT + GAP}px)`, ...centredX,
  display: "flex", alignItems: "center", gap: "4px", width: "calc(100% - 24px)", maxWidth: "480px", boxSizing: "border-box",
  height: `${KEYS}px`, padding: "4px", borderRadius: "999px",
  selectors: { "[data-desktop] &": { WebkitAppRegion: "no-drag" } },
});
export const rowKey = style({
  display: "grid", placeItems: "center", flex: "1 1 0", minWidth: "0", height: "36px", padding: "0", border: "0", borderRadius: "999px",
  background: `color-mix(in srgb, ${vars.text} 6%, transparent)`, color: vars.text, cursor: "pointer",
  fontSize: vars.textMeta, fontWeight: "600", lineHeight: "1", whiteSpace: "nowrap",
  selectors: { "&[aria-pressed=true]": { background: vars.text, color: vars.canvas }, "&:disabled": { opacity: ".4", cursor: "default" } },
});

// ── a phone's 全屏 ──

globalStyle(`${viewer}[data-phone][data-full]`, { background: "#000" });
// The bars folded away: only the corner's button (fullTools) and, while typing, the keys row at the foot.
globalStyle(`${viewer}[data-full] ${head}, ${viewer}[data-full] ${foot}`, { display: "none" });
globalStyle(`${viewer}[data-full] ${keysRow}`, { bottom: `max(${EDGE}px, var(--safe-bottom))` });
/** 全屏's tools, folded into one button over the picture's corner; open, the foot's down from it: a pill 4 round them. */
export const fullTools = style({
  ...glass,
  position: "absolute", zIndex: "4", top: `max(${EDGE}px, var(--safe-top))`, right: `max(${EDGE}px, var(--safe-right))`,
  display: "flex", flexDirection: "column", alignItems: "center", gap: "4px", padding: "4px", borderRadius: "999px",
});

/** A figure of the connection in the bar's line (its round trip, packets lost): amber, then red, as it gets worse. */
export const figure = style({
  selectors: { '&[data-level="amber"]': { color: vars.amber }, '&[data-level="red"]': { color: vars.red } },
});

/** How the view goes, in the bar: the signal mark on its tile and how long it has been seen; pressed, its panel. */
export const netChip = style({
  display: "inline-flex", alignItems: "center", gap: "8px", height: "32px", padding: "0 10px 0 4px", border: "0", borderRadius: "999px",
  background: "none", color: `var(--viewer-muted, ${vars.muted})`, font: "inherit", cursor: "pointer",
  selectors: { "&:hover, &[data-state=open]": { background: vars.hover } },
});
const levels = {
  '&[data-level="ok"]': { color: vars.green }, '&[data-level="amber"]': { color: vars.amber }, '&[data-level="red"]': { color: vars.red },
};
/** The bars on a small tile, coloured as the round trip is. */
export const netMark = style({
  display: "inline-grid", placeItems: "center", width: "24px", height: "24px", borderRadius: "999px",
  background: `color-mix(in srgb, ${vars.text} 8%, transparent)`, color: vars.muted, selectors: levels,
});
export const netTime = style({ fontFamily: vars.fontMono, fontSize: vars.textMeta, fontVariantNumeric: "tabular-nums", letterSpacing: "0.04em" });
/** The view's figures, a small panel of words: the round trip at its head, then groups of a name and its value a line. */
export const netPanel = style([popover, panelCard, {
  zIndex: "1000", display: "grid", gap: "10px", width: "280px", boxSizing: "border-box", color: vars.text, fontSize: vars.textUi,
  lineHeight: vars.leadingUi, animation: "none",
}]);
export const netHead = style({ display: "flex", alignItems: "center", gap: "10px", fontSize: vars.textBody, lineHeight: vars.leadingBody });
globalStyle(`${netHead} > b`, { fontWeight: "600", fontVariantNumeric: "tabular-nums" });
export const netCopy = style({
  justifySelf: "start", padding: "0", border: "0", background: "none", color: vars.muted, font: "inherit", cursor: "pointer",
  selectors: { "&:hover": { color: vars.text } },
});
export const netHeadMark = style({ display: "inline-grid", color: vars.muted, selectors: levels });
export const netRows = style({
  display: "grid", gap: "4px", margin: "0", paddingTop: "10px",
  boxShadow: `inset 0 1px 0 color-mix(in srgb, ${vars.text} 10%, transparent)`,
});
globalStyle(`${netRows} > div`, { display: "grid", gridTemplateColumns: "88px minmax(0, 1fr)", gap: "12px" });
globalStyle(`${netRows} dt`, { color: vars.muted });
globalStyle(`${netRows} dd`, { margin: "0", minWidth: "0", fontVariantNumeric: "tabular-nums", overflowWrap: "anywhere" });

/** 控制中心, in the bar: words beside its mark, as a tool that opens a menu. */
export const centerButton = style({
  display: "inline-flex", alignItems: "center", gap: "6px", height: "32px", padding: "0 10px", border: "0", borderRadius: "999px",
  background: "none", color: `var(--viewer-muted, ${vars.muted})`, font: "inherit", fontSize: vars.textUi, cursor: "pointer",
  selectors: { "&:hover, &[data-state=open]": { background: vars.hover, color: `var(--viewer-ink, ${vars.text})` } },
});
/** Its menu and the menus beside it, above the screen's page. */
export const menu = style({ zIndex: "1000", minWidth: "200px" });
export const menuItem = style({ selectors: { "&[data-state=open]": { background: vars.hover } } });
globalStyle(`${menuItem} > svg`, { flex: "none", color: vars.muted });
globalStyle(`${menuItem}[data-danger] > svg`, { color: "inherit" });
export const menuWords = style({ flex: "1", minWidth: "0", whiteSpace: "nowrap" });
/** What a row says at its end: the size chosen, a size's bounds. */
export const menuEnd = style({ color: vars.muted, fontSize: vars.textMeta, fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" });
export const menuCheck = style({ display: "inline-grid", placeItems: "center", width: "16px", flex: "none" });
/** A combo's keys, as keycaps. */
export const menuKeys = style({ display: "flex", gap: "3px", flex: "none" });
globalStyle(`${menuKeys} > kbd`, {
  display: "inline-flex", alignItems: "center", justifyContent: "center", minWidth: "20px", height: "20px", padding: "0 5px", boxSizing: "border-box",
  border: `1px solid color-mix(in srgb, ${vars.text} 18%, transparent)`, borderBottomWidth: "2px", borderRadius: "4px",
  fontFamily: "inherit", fontSize: vars.textCaption, fontWeight: "500", lineHeight: "1", color: vars.muted,
});

// ── a simulator's buttons, with a mouse ──

/** A column of round buttons by the device's right edge (ScreenViewer.tsx place), as Simulator.app's own are beside it. */
export const device = style({
  position: "absolute", zIndex: "2", display: "flex", flexDirection: "column", gap: "8px",
  selectors: { "[data-desktop] &": { WebkitAppRegion: "no-drag" } },
});
export const deviceButton = style({
  display: "grid", placeItems: "center", width: "40px", height: "40px", padding: "0", border: "0", borderRadius: "50%",
  background: `color-mix(in srgb, ${vars.text} 6%, transparent)`, color: vars.text, cursor: "pointer",
  selectors: {
    "&:hover:not(:disabled)": { background: `color-mix(in srgb, ${vars.text} 11%, transparent)` },
    "&:disabled": { opacity: ".4", cursor: "default" },
  },
});

// ── beside a chat ──

/** Its bar in a tab of a chat's side panel (named by the tab): 只看/控制 at the start, its tools and its own page at the end. */
export const panelBar = style({
  position: "absolute", zIndex: "3", top: "0", left: "0", right: "0", height: `${VIEWER_BAR}px`, boxSizing: "border-box",
  display: "flex", alignItems: "center", justifyContent: "space-between", gap: "8px", padding: "0 8px 1px",
  boxShadow: `inset 0 -1px 0 color-mix(in srgb, ${vars.line} 70%, transparent)`,
});
export const panelTools = style({ display: "flex", alignItems: "center", gap: "2px", minWidth: "0" });
export const panelExpand = style({
  display: "grid", placeItems: "center", flex: "none", width: "32px", height: "32px", padding: "0", border: "0",
  borderRadius: vars.rOption, cornerShape: vars.cornerShape, background: "none", color: vars.muted, cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover, color: vars.text } },
});
/** 控制中心 as its icon alone where the panel is narrow (its words kept for a screen reader). */
globalStyle(`${panelTools} [aria-haspopup="menu"] > span`, {
  position: "absolute", width: "1px", height: "1px", overflow: "hidden", clipPath: "inset(50%)", whiteSpace: "nowrap",
});
