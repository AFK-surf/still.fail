// What goes between a screen driven and this device (Transfer.tsx): a copy made on the screen the browser would not
// put on this clipboard by itself, offered in a small panel at the top; the files sent to the screen's machine in a small
// panel in a corner (above the phone's foot); a file dragged over the screen, the screen veiled with where it goes.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { IN, PANEL_PAD, PANEL_PILL, centredX, pillInner } from "@stillfail/ui/styles/align.ts";
import { panelCard, popover } from "@stillfail/ui/styles/controls.css.ts";

/** A panel of the viewer's: its corner from the 24 tall pills and circles in its corners (docs/ui-panels.md). */
const pills = { vars: { [IN]: pillInner(PANEL_PAD, PANEL_PILL, vars.cornerScale) } };

/**
 * A copy made on the screen, to put on this device's clipboard with a press: one line, its buttons at its end. Not
 * popped in as a menu is (as the viewer's other panels): it is part of the view, and a panel still scaling is measured
 * smaller than it is (its padding and inner corner read 0.97 of themselves against its corner).
 */
export const copied = style([popover, pills, {
  position: "absolute", zIndex: "4", top: "calc(var(--m-top, 0px) + 64px)", ...centredX,
  display: "flex", alignItems: "center", gap: "6px", maxWidth: "min(520px, calc(100% - 32px))", boxSizing: "border-box",
  color: vars.text, fontSize: vars.textUi, lineHeight: "24px", animation: "none",
  selectors: { "[data-phone] &": { top: "calc(var(--m-top, 0px) + max(12px, var(--safe-top)) + 52px)" } },
}]);
export const copiedText = style({ minWidth: "0", flex: "1 1 auto", paddingInline: "10px 4px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const copiedWhat = style({ color: vars.muted });

/** The files sent to the screen's machine: a panel of rows in the corner, over the picture. */
export const sends = style([popover, panelCard, pills, {
  position: "absolute", zIndex: "4", right: "16px", bottom: "16px", display: "flex", flexDirection: "column", gap: "2px",
  width: "min(400px, calc(100% - 32px))", maxHeight: "min(360px, calc(100% - 96px))", boxSizing: "border-box",
  color: vars.text, fontSize: vars.textUi, lineHeight: "19px", animation: "none",
  selectors: {
    // A phone's: above its foot, across.
    "[data-phone] &": { left: "12px", right: "12px", width: "auto", bottom: "calc(max(12px, var(--safe-bottom)) + 56px)" },
  },
}]);
/** Its head: where they go, and the way to put the panel away in its corner. */
export const sendsHead = style({ display: "flex", alignItems: "center", gap: "6px", minHeight: `${PANEL_PILL}px` });
export const sendsTitle = style({ flex: "1 1 auto", minWidth: "0", paddingInlineStart: "10px", color: vars.muted, fontSize: vars.textMeta, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const sendsList = style({ overscrollBehaviorY: "none", display: "flex", flexDirection: "column", gap: "2px", minHeight: "0", overflowY: "auto" });

/** One file: its name and how it goes (or where it went) under it; what can be done with it at its end. */
export const send = style({
  display: "flex", alignItems: "center", gap: "8px", minHeight: "48px", padding: "6px 0 6px 10px", boxSizing: "border-box",
  // A phone's row: its buttons on a line of their own under the words, so the path has the width; the last row's at
  // the panel's padding, in its corner.
  selectors: { "[data-phone] &": { flexWrap: "wrap", rowGap: "6px", paddingBottom: "0" } },
});
globalStyle(`${send} > svg`, { flex: "none", color: vars.muted });
export const sendWords = style({ display: "grid", gap: "4px", flex: "1 1 0", minWidth: "0" });
export const sendName = style({ fontWeight: "500", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const sendLine = style({ display: "flex", alignItems: "center", gap: "8px", minWidth: "0", color: vars.muted, fontSize: vars.textMeta, lineHeight: "16px" });
/** A path cut at its start, where it is long (its end, the file's name, is what tells it apart): laid out right to left,
 *  its words left to right inside. */
export const sendPath = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", direction: "rtl", textAlign: "left" });
export const sendFailed = style({ minWidth: "0", color: vars.red, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const sendTools = style({
  display: "flex", alignItems: "center", gap: "6px", flex: "none",
  selectors: { "[data-phone] &": { flexBasis: "100%", justifyContent: "flex-end" } },
});
/** How much of it the station has: a thin bar, then the sizes. */
export const bar = style({ position: "relative", flex: "1 1 auto", height: "3px", overflow: "hidden", borderRadius: "999px", background: vars.line });
globalStyle(`${bar} > span`, { position: "absolute", inset: "0", background: vars.accent, transformOrigin: "left", transition: "transform 200ms linear" });
export const sizes = style({ flex: "none", fontVariantNumeric: "tabular-nums" });

/** A file dragged over the screen: the screen veiled, where it will go said in the middle. */
export const veil = style({
  position: "absolute", inset: "0", zIndex: "5", display: "grid", placeContent: "center", justifyItems: "center", gap: "8px",
  pointerEvents: "none", background: `color-mix(in srgb, ${vars.canvas} 78%, transparent)`,
  boxShadow: `inset 0 0 0 2px color-mix(in srgb, ${vars.accent} 60%, transparent)`, color: vars.text, fontSize: vars.textUi,
});
export const veilWhere = style({ color: vars.muted, fontSize: vars.textMeta });
