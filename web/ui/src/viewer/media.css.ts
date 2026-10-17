// A picture or a video with media controls floating over it (the app's VideoViewer, the drive's Player): frosted
// glass that fades, a timeline, the buttons in its corners.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { pictureGlass as glass } from "../styles/glass.ts";
import { iconBtn } from "../styles/page.css.ts";
import { STILL } from "../styles/still.ts";

/** The picture, its controls floating over it. */
export const vv = style({ position: "relative", width: "100%", height: "100%", overflow: "hidden", background: vars.canvas, color: vars.text });
export const vvStage = style({ background: vars.canvas });
export const vvPicture = style({
  position: "absolute", left: "50%", top: "50%", maxWidth: "none", transformOrigin: "center", display: "block",
  selectors: {
    // Zoomed in, each of its pixels a sharp square: a 1px line stays 1px.
    "&[data-pixelated]": { imageRendering: "pixelated" },
  },
});

export const vvBar = style({
  ...glass,
  position: "absolute", zIndex: "2", left: "50%", bottom: "max(16px, var(--safe-bottom))", width: "min(100% - 32px, 1080px)",
  transform: "translateX(-50%)", display: "grid", padding: "2px 6px 6px", borderRadius: `calc(16px * ${vars.cornerScale})`,
  cornerShape: vars.cornerShape, opacity: "0", pointerEvents: "none", transition: `opacity 320ms ${vars.easeOut}`,
  selectors: {
    "&[data-awake]": { opacity: "1", pointerEvents: "auto", transitionDuration: "120ms" },
    [`${STILL} &`]: { transition: "none" },
  },
  "@media": {
    "(max-width: 640px)": { width: "calc(100% - 16px)", bottom: "max(8px, var(--safe-bottom))", padding: "2px 4px 4px" },
  },
});
export const vvRow = style({ display: "flex", alignItems: "center", gap: "12px", minWidth: "0" });
export const vvGroup = style({ flex: "none", display: "flex", alignItems: "center", gap: "2px" });

export const vvInfo = style({
  flex: "1", minWidth: "0", display: "flex", alignItems: "baseline", gap: "16px", overflow: "hidden", whiteSpace: "nowrap",
  fontFamily: vars.fontMono, fontSize: vars.textMeta, fontVariantNumeric: "tabular-nums", color: vars.text,
});
export const vvFact = style({
  flex: "none",
  "@media": {
    "(max-width: 640px)": {
      selectors: { "&[data-fact=time], &[data-fact=note]": { display: "none" } },
    },
  },
});
export const vvNow = style({ fontWeight: "600", color: vars.text });
export const vvDim = style({ color: vars.muted });
/** A pixel's colour and place, beside the pointer. */
export const vvPixel = style({
  ...glass,
  position: "fixed", zIndex: "70", display: "flex", alignItems: "center", gap: "8px", padding: "4px 8px",
  borderRadius: `calc(8px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, pointerEvents: "none", color: vars.text,
  fontFamily: vars.fontMono, fontSize: vars.textMeta,
  fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap",
});
export const vvSwatch = style({
  width: "12px", height: "12px", borderRadius: "3px", boxShadow: `inset 0 0 0 1px color-mix(in srgb, ${vars.text} 30%, transparent)`,
});
export const vvRate = style({
  height: "28px", minWidth: "46px", padding: "0 8px", border: "0", borderRadius: `calc(10px * ${vars.cornerScale})`,
  background: `color-mix(in srgb, ${vars.text} 10%, transparent)`, color: vars.text, fontFamily: vars.fontMono, fontSize: vars.textMeta, fontWeight: "600",
  cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: `color-mix(in srgb, ${vars.text} 18%, transparent)` },
  },
});

/** Turning sideways is for phones (a coarse pointer). */
export const vvTurn = style({ "@media": { "(pointer: fine)": { display: "none" } } });

export const vvTimeline = style({
  position: "relative", height: "22px", display: "grid", alignItems: "center", margin: "0 10px", cursor: "pointer",
  touchAction: "none",
});
export const vvTrack = style({
  position: "relative", display: "block", height: "4px", borderRadius: "2px", overflow: "hidden",
  background: `color-mix(in srgb, ${vars.text} 20%, transparent)`, transition: `height ${vars.dur} ${vars.easeOut}`,
  selectors: {
    [`${vvTimeline}:hover &`]: { height: "6px", borderRadius: "3px" },
  },
});
export const vvPlayed = style({ position: "absolute", inset: "0", transformOrigin: "left", background: vars.text });
/** As wide as the timeline, slid along it (VideoViewer.tsx): the head at its start is where the video is. */
export const vvHeadRail = style({ position: "absolute", inset: "0", pointerEvents: "none" });
export const vvHead = style({
  position: "absolute", top: "50%", left: "0", width: "12px", height: "12px", borderRadius: "50%", background: vars.text,
  transform: "translate(-50%, -50%)", pointerEvents: "none", boxShadow: "0 1px 4px rgba(0, 0, 0, .35)",
});
globalStyle(`${vv} ${iconBtn}:disabled`, { opacity: ".35", cursor: "default", background: "none" });
/** The bar's buttons at its foot's corners: 6 in from both edges, rounded as the bar less that (concentric). */
globalStyle(`${vvBar} ${iconBtn}`, {
  borderRadius: `calc(16px * ${vars.cornerScale} - 6px)`, cornerShape: vars.cornerShape,
  // On a phone the bar is padded 4: 4 less.
  "@media": { "(max-width: 640px)": { borderRadius: `calc(16px * ${vars.cornerScale} - 4px)` } },
});
