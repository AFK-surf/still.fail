import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** How tall the bar is: as a page's bar (styles/sidebar.css.ts), a 32px button in it level with the desktop window's
 * buttons. What is under it starts below it, and goes under it as it is scrolled or as the bar goes. */
export const VIEWER_BAR = 45;

/**
 * Across the top of the file opened, over the whole window: the way back, the name in the middle, the tools. Its
 * ground, ink and line are the file's own (`--viewer-*`), else the page's. In the desktop app it drags the window
 * (but what is pressed in it), clear of the window's buttons: macOS's at its left, Windows' at its right.
 */
export const bar = style({
  position: "absolute", zIndex: "3", top: "0", left: "0", right: "0", height: `${VIEWER_BAR}px`, boxSizing: "border-box",
  display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(0, auto) minmax(0, 1fr)", alignItems: "center", gap: "16px",
  padding: "0 12px 1px", color: `var(--viewer-ink, ${vars.text})`,
  // Over the file, frosted with its ground: what scrolls under it shows through, softened.
  background: `color-mix(in srgb, var(--viewer-ground, ${vars.canvas}) 82%, transparent)`, WebkitBackdropFilter: "blur(20px) saturate(1.4)",
  backdropFilter: "blur(20px) saturate(1.4)", boxShadow: `inset 0 -1px 0 color-mix(in srgb, var(--viewer-line, ${vars.line}) 70%, transparent)`,
  transition: `transform 240ms ${vars.easeOut}, opacity 240ms ${vars.easeOut}`,
  "@media": { "(prefers-reduced-motion: reduce)": { transition: "opacity 160ms linear" } },
  selectors: {
    // Gone up out of the way: the file under it whole.
    "&[data-hidden]": { transform: "translateY(-100%)", opacity: "0", pointerEvents: "none" },
    "[data-desktop] &": { WebkitAppRegion: "drag" },
    ':root[data-desktop="inset"]:not([data-fullscreen]) &': { paddingLeft: "84px" },
    ':is([data-desktop="overlay"], [data-desktop="custom"]) &': { paddingRight: "calc(var(--window-buttons, 0px) + 12px)" },
  },
});
globalStyle(`[data-desktop] ${bar} :is(a, button, input, select, [role="button"], [tabindex])`, { WebkitAppRegion: "no-drag" });

/** The way back, with where to. */
export const back = style({
  justifySelf: "start", display: "flex", alignItems: "center", gap: "2px", maxWidth: "100%", height: "32px", padding: "0 10px 0 4px",
  border: "0", borderRadius: vars.rField, cornerShape: vars.cornerShape, background: "none", color: "inherit", fontSize: vars.textUi, cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover } },
});
globalStyle(`${back} > span`, { minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${back} > svg`, { flex: "none" });

export const center = style({ display: "grid", justifyItems: "center", minWidth: "0", lineHeight: "1.25" });
export const name = style({ maxWidth: "100%", fontSize: vars.textUi, fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const meta = style({
  maxWidth: "100%", color: `var(--viewer-muted, ${vars.muted})`, fontSize: vars.textCaption, fontVariantNumeric: "tabular-nums",
  overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const tools = style({ justifySelf: "end", display: "flex", alignItems: "center", gap: "2px", minWidth: "0" });
/** A tool: the page's icon button, in the file's quieter ink until pointed at or on. */
export const tool = style({
  color: `var(--viewer-muted, ${vars.muted})`,
  selectors: { "&:hover, &[data-on]": { color: `var(--viewer-ink, ${vars.text})` }, "&[data-on]": { background: vars.selected } },
});
