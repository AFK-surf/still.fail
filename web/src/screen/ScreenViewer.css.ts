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
globalStyle(`${cursor} svg`, { display: "block", translate: "-4px -2px", filter: "drop-shadow(0 1px 1px rgba(0, 0, 0, .35))" });

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
  selectors: { "&[aria-pressed=true]": { background: vars.text, color: vars.canvas } },
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

/** The panel's grounds within it: its text's colour, faint, so they show as much on a light panel as on a dark one. */
const tint = (pct: number) => `color-mix(in srgb, ${vars.text} ${pct}%, transparent)`;

/** The screen's panel (ScreenPanel.tsx): a small panel under the bar's tool (docs/ui-panels.md). */
export const panel = style([popover, panelCard, {
  vars: { [IN]: pillInner(PANEL_PAD, PANEL_PILL, vars.cornerScale) },
  zIndex: "1000", display: "grid", gap: "10px", width: "320px", boxSizing: "border-box", color: vars.text, fontSize: vars.textUi,
  animation: "none",
}]);
/** The view's figures, four side by side on a quieter ground: each its value over its name. */
export const tiles = style({
  display: "grid", gridTemplateColumns: "repeat(4, minmax(0, 1fr))", gap: "2px", padding: "8px 4px",
  borderRadius: `var(${IN})`, background: tint(5),
});
export const tile = style({ display: "grid", justifyItems: "center", gap: "2px", minWidth: "0", textAlign: "center" });
globalStyle(`${tile} > b`, {
  maxWidth: "100%", fontSize: vars.textBody, lineHeight: vars.leadingBody, fontWeight: "600", fontVariantNumeric: "tabular-nums",
  overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
globalStyle(`${tile} > span`, { color: vars.muted, fontSize: vars.textCaption, lineHeight: vars.leadingCaption });
/** Under the figures: the picture's size and codec, packets lost. */
export const tilesNote = style({ padding: `0 ${TEXT_IN}px`, color: vars.muted, fontSize: vars.textCaption, lineHeight: vars.leadingCaption, textAlign: "center" });
/** The figures and the line under them. */
export const view = style({ display: "grid", gap: "6px" });
/** A part of the panel under its small name. */
export const section = style({ display: "grid", gap: "6px" });
export const sectionLabel = style({ padding: `0 ${TEXT_IN}px`, color: vars.muted, fontSize: vars.textMeta, lineHeight: vars.leadingMeta });
/** The combos, two a row: the keys as keycaps over what they do. */
export const combos = style({ display: "grid", gridTemplateColumns: "repeat(2, minmax(0, 1fr))", gap: "4px" });
export const combo = style({
  display: "grid", justifyItems: "start", gap: "4px", minWidth: "0", padding: "8px 10px", border: "0",
  borderRadius: `var(${IN})`, background: tint(5), color: vars.text, font: "inherit", textAlign: "left", cursor: "pointer",
  selectors: { "&:hover": { background: tint(9) }, "&:active": { background: tint(13) } },
});
export const keycaps = style({ display: "flex", flexWrap: "wrap", gap: "3px" });
export const keycap = style({
  display: "inline-flex", alignItems: "center", justifyContent: "center", minWidth: "20px", height: "20px", padding: "0 5px", boxSizing: "border-box",
  border: `1px solid ${tint(18)}`, borderBottomWidth: "2px", borderRadius: "4px", background: vars.raised,
  fontFamily: "inherit", fontSize: vars.textCaption, fontWeight: "500", lineHeight: "1",
});
export const comboName = style({ maxWidth: "100%", color: vars.muted, fontSize: vars.textMeta, lineHeight: vars.leadingMeta, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** 全屏, along the foot. */
export const fullRow = style({
  display: "flex", alignItems: "center", justifyContent: "center", gap: "6px", height: "32px", border: "0", lineHeight: "1",
  borderRadius: `var(${IN})`, background: tint(5), color: vars.text, font: "inherit", fontSize: vars.textUi, cursor: "pointer",
  selectors: { "&:hover": { background: tint(9) }, "&:active": { background: tint(13) } },
});
