import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { iconBtn } from "../styles/pages.css.ts";
import { glass } from "../FilePreview.css.ts";

/** What is drawn on an image: still.fail's accent, as a preview's marks are (literal: the image viewer redefines the theme's). */
export const INK = "oklch(68% .175 39)";

/** Over the image, as big as it and moved with it: the marks, taking the pointer to draw and pick them. */
export const sheet = style({
  position: "absolute", left: "50%", top: "50%", transformOrigin: "center", overflow: "visible",
  pointerEvents: "auto", cursor: "crosshair", touchAction: "none",
  selectors: {
    "&[data-tool=\"text\"]": { cursor: "text" },
    "&[data-tool=\"select\"]": { cursor: "default" },
  },
});

/** A line of text being written where it goes, in the size and colour it will have (`--halo`: its edge). */
export const typing = style({
  width: "100%", height: "100%", boxSizing: "border-box", padding: "0", border: "0", outline: "none",
  background: "none", font: "inherit", fontWeight: "600",
  // The same edge the drawn text has.
  textShadow: "0 0 .12em var(--halo), 0 0 .12em var(--halo), 0 0 .12em var(--halo)",
  selectors: { "&::placeholder": { color: "currentColor", opacity: ".55" } },
});

/** The picked mark: a dashed box round it (none for an arrow), and handles to stretch it by. */
export const hits = style({ pointerEvents: "auto", cursor: "move" });
globalStyle(`${sheet}[data-tool="text"] ${hits}`, { cursor: "text" });
export const pickedBox = style({ fill: "none", stroke: "#fff", opacity: ".85", pointerEvents: "none", mixBlendMode: "difference" });
export const handle = style({ fill: "#fff", stroke: INK, pointerEvents: "auto" });

/** The tools, at the bottom over the image, frosted as the top bar. */
export const toolbar = style({
  ...glass, position: "absolute", zIndex: "3", left: "50%", bottom: "max(16px, env(safe-area-inset-bottom))", transform: "translateX(-50%)",
  display: "flex", alignItems: "center", gap: "2px", height: "44px", padding: "0 6px", boxSizing: "border-box",
  borderRadius: `calc(14px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, color: vars.text, whiteSpace: "nowrap",
  "@media": { "(max-width: 640px)": { bottom: "max(8px, env(safe-area-inset-bottom))", padding: "0 2px" } },
});
export const gap = style({ width: "1px", height: "18px", margin: "0 4px", background: vars.line, flex: "none" });
globalStyle(`${toolbar} ${iconBtn}[aria-pressed="true"]`, { background: vars.selected, color: vars.text });
globalStyle(`${toolbar} ${iconBtn}:disabled`, { opacity: ".35", cursor: "default", background: "none" });
export const swatchWrap = style({ position: "relative", display: "flex" });
export const swatch = style({
  display: "block", width: "16px", height: "16px", borderRadius: "50%", boxShadow: "inset 0 0 0 1.5px rgba(255, 255, 255, .5)",
});
/** The colours, in a row above the tools. */
export const palette = style({
  ...glass, position: "absolute", left: "50%", bottom: "calc(100% + 12px)", transform: "translateX(-50%)", display: "flex",
  gap: "2px", padding: "4px", borderRadius: "999px",
});
export const paletteItem = style({
  width: "32px", height: "32px", display: "grid", placeItems: "center", border: "0", borderRadius: "50%", background: "none",
  cursor: "pointer",
  selectors: {
    "&:hover": { background: vars.hover },
    "&[aria-selected=\"true\"]": { background: vars.selected },
  },
});

/** In the top bar while marking: what to do with the marks. */
export const actions = style({ display: "flex", alignItems: "center", gap: "4px" });
export const cancel = style({
  height: "30px", padding: "0 10px", border: "0", borderRadius: "15px", background: "none", color: vars.muted,
  font: "inherit", fontSize: vars.textXs, cursor: "pointer", flex: "none",
  selectors: { "&:hover": { background: vars.hover, color: vars.text } },
});
export const done = style({
  flex: "none", display: "inline-flex", alignItems: "center", gap: "5px", height: "30px", padding: "0 12px", marginLeft: "4px",
  border: "0", borderRadius: "15px", background: INK, color: "#fff", font: "inherit", fontSize: vars.textXs,
  fontWeight: "600", cursor: "pointer",
  selectors: {
    "&:hover:not(:disabled)": { filter: "brightness(1.08)" },
    "&:disabled": { opacity: ".4", cursor: "default" },
  },
});
export const error = style({ color: vars.red, fontSize: vars.textXs, whiteSpace: "nowrap", padding: "0 6px" });
