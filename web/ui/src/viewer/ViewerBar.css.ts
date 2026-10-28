import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import * as controlsCss from "../styles/controls.css.ts";

/** How tall the bar is: as a page's bar (styles/sidebar.css.ts). What is under it starts below it, and goes under it as
 * it is scrolled or as the bar goes. */
export const VIEWER_BAR = 45;

/**
 * Across the top of the file opened, over the whole window: the way back, the name in the middle, the tools. Its
 * ground, ink and line are the file's own (`--viewer-*`), else the page's.
 */
export const bar = style({
  position: "absolute", zIndex: "3", top: "0", left: "0", right: "0", height: `${VIEWER_BAR}px`, boxSizing: "border-box",
  display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(0, auto) minmax(0, 1fr)", alignItems: "center", gap: "16px",
  padding: "0 12px 1px", color: `var(--viewer-ink, ${vars.text})`,
  // Over the file, frosted with its ground: what scrolls under it shows through, softened.
  background: `color-mix(in srgb, var(--viewer-ground, ${vars.canvas}) 82%, transparent)`,
  backdropFilter: "blur(20px) saturate(1.4)", boxShadow: `inset 0 -1px 0 color-mix(in srgb, var(--viewer-line, ${vars.line}) 70%, transparent)`,
  transition: `transform 240ms ${vars.easeOut}, opacity 240ms ${vars.easeOut}`,
  selectors: {
    // Gone up out of the way: the file under it whole.
    "&[data-hidden]": { transform: "translateY(-100%)", opacity: "0", pointerEvents: "none" },
  },
});

/** The way back, with where to. */
export const back = style({
  justifySelf: "start", display: "flex", alignItems: "center", gap: "2px", maxWidth: "100%", height: "32px", padding: "0 10px 0 4px",
  border: "0", borderRadius: vars.rField, cornerShape: vars.cornerShape, background: "none", color: "inherit", fontSize: vars.textUi, cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover } },
});
globalStyle(`${back} > span`, { minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${back} > svg`, { flex: "none" });

// Each line its own leading: the clip that ellipsizes it keeps a descender (the g of "Controlling") whole.
export const center = style({ display: "grid", justifyItems: "center", minWidth: "0" });
export const name = style({ maxWidth: "100%", fontSize: vars.textUi, lineHeight: vars.leadingUi, fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const meta = style({
  maxWidth: "100%", color: `var(--viewer-muted, ${vars.muted})`, fontSize: vars.textCaption, lineHeight: vars.leadingCaption, fontVariantNumeric: "tabular-nums",
  overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const tools = style({ justifySelf: "end", display: "flex", alignItems: "center", gap: "2px", minWidth: "0" });
/** A button in words among the tools (a chat shared as a picture: 复制图片) as tall as they are, 32, level with them. */
globalStyle(`${tools} > ${controlsCss.btn}`, { height: "32px" });
/** A tool: the page's icon button, in the file's quieter ink until pointed at or on. */
export const tool = style({
  color: `var(--viewer-muted, ${vars.muted})`,
  selectors: { "&:hover, &[data-on]": { color: `var(--viewer-ink, ${vars.text})` }, "&[data-on]": { background: vars.selected } },
});
