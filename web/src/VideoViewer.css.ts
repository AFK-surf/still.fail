import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { iconBtn } from "./styles/pages.css.ts";
import { fp, fpHead, fpZoom } from "./FilePreview.css.ts";

/** Dark whatever the theme, as a player: the page's colours, redefined within it. */
const dark = {
  [vars.canvas]: "#111113", [vars.text]: "#f4f4f5", [vars.muted]: "rgba(255, 255, 255, .6)",
  [vars.subtle]: "rgba(255, 255, 255, .35)", [vars.hover]: "rgba(255, 255, 255, .12)", [vars.selected]: "rgba(255, 255, 255, .16)",
  [vars.line]: "rgba(255, 255, 255, .1)", [vars.accent]: "#f4f4f5",
};
/** Frosted glass over the picture. */
const glass = {
  background: "rgba(18, 18, 20, .62)", backdropFilter: "blur(24px) saturate(1.6)", WebkitBackdropFilter: "blur(24px) saturate(1.6)",
  boxShadow: "0 8px 32px rgba(0, 0, 0, .3)",
};

/** The picture, its controls floating over it. */
export const vv = style({ position: "relative", width: "100%", height: "100%", overflow: "hidden", background: "#000", color: vars.text, vars: dark });
export const vvStage = style({ background: "#000" });
export const vvPicture = style({
  position: "absolute", left: "50%", top: "50%", maxWidth: "none", transformOrigin: "center", display: "block",
  selectors: {
    // Zoomed in, each of its pixels a sharp square: a 1px line stays 1px.
    "&[data-pixelated]": { imageRendering: "pixelated" },
  },
});

export const vvBar = style({
  ...glass,
  position: "absolute", zIndex: "2", left: "50%", bottom: "max(16px, env(safe-area-inset-bottom))", width: "min(100% - 32px, 1080px)",
  transform: "translateX(-50%)", display: "grid", padding: "2px 10px 6px", borderRadius: `calc(16px * ${vars.cornerScale})`,
  cornerShape: vars.cornerShape, opacity: "0", pointerEvents: "none", transition: `opacity 320ms ${vars.easeOut}`,
  selectors: {
    "&[data-awake]": { opacity: "1", pointerEvents: "auto", transitionDuration: "120ms" },
  },
  "@media": {
    "(max-width: 640px)": { width: "calc(100% - 16px)", bottom: "max(8px, env(safe-area-inset-bottom))", padding: "2px 4px 4px" },
    "(prefers-reduced-motion: reduce)": { transition: "none" },
  },
});
export const vvRow = style({ display: "flex", alignItems: "center", gap: "12px", minWidth: "0" });
export const vvGroup = style({ flex: "none", display: "flex", alignItems: "center", gap: "2px" });

export const vvInfo = style({
  flex: "1", minWidth: "0", display: "flex", alignItems: "baseline", gap: "16px", overflow: "hidden", whiteSpace: "nowrap",
  fontFamily: vars.fontMono, fontSize: "12px", fontVariantNumeric: "tabular-nums", color: vars.text,
});
export const vvFact = style({
  flex: "none",
  "@media": {
    "(max-width: 640px)": {
      selectors: { "&[data-fact=time], &[data-fact=held], &[data-fact=fps], &[data-fact=note]": { display: "none" } },
    },
  },
});
export const vvNow = style({ fontWeight: "600", color: vars.text });
export const vvDim = style({ color: vars.muted });
/** A pixel's colour and place, beside the pointer. */
export const vvPixel = style({
  ...glass,
  position: "fixed", zIndex: "70", display: "flex", alignItems: "center", gap: "8px", padding: "4px 8px",
  borderRadius: "8px", pointerEvents: "none", color: vars.text, fontFamily: vars.fontMono, fontSize: "12px",
  fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap",
});
export const vvSwatch = style({
  width: "12px", height: "12px", borderRadius: "3px", boxShadow: "inset 0 0 0 1px rgba(255, 255, 255, .3)",
});
export const vvRate = style({
  height: "28px", minWidth: "46px", padding: "0 8px", border: "0", borderRadius: `calc(10px * ${vars.cornerScale})`,
  background: "rgba(255, 255, 255, .1)", color: vars.text, fontFamily: vars.fontMono, fontSize: "12px", fontWeight: "600",
  cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: "rgba(255, 255, 255, .18)" },
  },
});

/** Turning sideways is for phones (a coarse pointer). */
export const vvTurn = style({ "@media": { "(pointer: fine)": { display: "none" } } });

export const vvTimeline = style({
  position: "relative", height: "22px", display: "grid", alignItems: "center", margin: "0 6px", cursor: "pointer",
  touchAction: "none",
});
export const vvTrack = style({
  position: "relative", display: "block", height: "4px", borderRadius: "2px", overflow: "hidden",
  background: "rgba(255, 255, 255, .2)", transition: `height ${vars.dur} ${vars.easeOut}`,
  selectors: {
    [`${vvTimeline}:hover &`]: { height: "6px", borderRadius: "3px" },
  },
});
export const vvPlayed = style({ position: "absolute", inset: "0 auto 0 0", background: vars.text });
export const vvHead = style({
  position: "absolute", top: "50%", width: "12px", height: "12px", borderRadius: "50%", background: vars.text,
  transform: "translate(-50%, -50%)", pointerEvents: "none", boxShadow: "0 1px 4px rgba(0, 0, 0, .35)",
});
globalStyle(`${vv} ${iconBtn}:disabled`, { opacity: ".35", cursor: "default", background: "none" });
/** The picture takes the whole page: the page's bar (its name, download, close) floats over it too, as the player's. */
globalStyle(`${fp}:has(${vv})`, { vars: dark, background: "#000", color: vars.text, gridTemplateRows: "minmax(0, 1fr)" });
globalStyle(`${fp}:has(${vv}) ${fpHead}`, {
  ...glass,
  position: "absolute", zIndex: "3", top: "max(16px, env(safe-area-inset-top))", left: "50%", width: "min(100% - 32px, 1080px)",
  height: "44px", padding: "0 6px 0 16px", transform: "translateX(-50%)", border: "0",
  borderRadius: `calc(14px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  opacity: "0", transition: `opacity 320ms ${vars.easeOut}`,
  "@media": {
    "(max-width: 640px)": { top: "max(8px, env(safe-area-inset-top))", width: "calc(100% - 16px)", padding: "0 2px 0 12px" },
    "(prefers-reduced-motion: reduce)": { transition: "none" },
  },
});
// Shown with the controls, and whenever the pointer or focus is on it (it stays where it is to be clicked, faded).
globalStyle(`${fp}:has(${vvBar}[data-awake]) ${fpHead}, ${fp}:has(${vv}) ${fpHead}:hover, ${fp}:has(${vv}) ${fpHead}:has(:focus-visible)`, {
  opacity: "1", transitionDuration: "120ms",
});
/** On a phone, pinching zooms: its buttons would crowd the frame's facts out. */
globalStyle(`${vv} ${fpZoom}`, { "@media": { "(max-width: 640px)": { display: "none" } } });
