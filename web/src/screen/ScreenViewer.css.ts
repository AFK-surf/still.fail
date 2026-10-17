// A station's screen seen (and driven) in the app (ScreenViewer.tsx): the picture fitted in the window, letterboxed
// on the app's own ground (light or dark as the app is), and the controls over it as a media viewer's are. With a
// mouse the bar every file opened has (ViewerBar) along the top, gone after a moment at rest; on a phone frosted
// bars above and below the picture, which stays clear of them.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { pictureGlass as glass } from "@stillfail/ui/styles/glass.ts";
import { IN, PANEL_PAD, PANEL_PILL, centred, centredX, pillInner } from "@stillfail/ui/styles/align.ts";
import { panelCard, popover } from "@stillfail/ui/styles/controls.css.ts";

/** The page it is on, over the whole window (as a file opened is: pages/Drive.css.ts opened). */
export const page = style({
  position: "fixed", inset: "0", zIndex: "61", overflow: "hidden", background: vars.canvas,
  selectors: { ':root[data-desktop="inset"]:not([data-fullscreen]) &': { vars: { "--m-top": "30px" } } },
});

/** Phone: the bars' heights and how far from the edges they float. */
const HEAD = 44;
const FOOT = 48;
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
    // On a phone, between its bars: they stay, so they never cover it.
    [`${viewer}[data-phone] &`]: {
      top: `calc(var(--m-top, 0px) + max(${EDGE}px, var(--safe-top)) + ${HEAD + GAP}px)`,
      bottom: `calc(max(${EDGE}px, var(--safe-bottom)) + ${FOOT + GAP}px)`,
      left: "var(--safe-left)", right: "var(--safe-right)",
    },
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
