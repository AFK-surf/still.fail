import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { glass } from "./styles/glass.ts";
import { fadeInKeyframes, mRiseInKeyframes, popKeyframes } from "./styles/keyframes.css.ts";

/** The bar's button: its icon alone, or with the size the page is laid out at (and how much it is drawn at). */
export const button = style({
  flex: "none", display: "inline-flex", alignItems: "center", justifyContent: "center", gap: "6px", minWidth: "28px",
  height: "28px", padding: "0 7px", border: "0", borderRadius: "999px", background: "none", color: vars.muted,
  font: "inherit", cursor: "pointer",
  transition: `background ${vars.dur} ${vars.easeOut}, color ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover, &[data-state=open]": { background: vars.hover, color: vars.text },
    "&[data-sized]": { padding: "0 10px 0 8px", background: vars.neutralBg, color: vars.text },
    "&[data-sized]:hover, &[data-sized][data-state=open]": { background: vars.hover },
  },
});
globalStyle(`${button} svg`, { flex: "none" });
export const buttonText = style({
  display: "inline-flex", gap: "6px", fontSize: vars.textXs, fontWeight: "500", whiteSpace: "nowrap",
  fontVariantNumeric: "tabular-nums",
});
export const buttonScale = style({ color: vars.muted, fontWeight: "400" });

export const popover = style({
  zIndex: "60", width: "256px", padding: "6px", borderRadius: vars.rMenu, cornerShape: vars.cornerShape,
  ...glass, boxShadow: `0 12px 32px ${vars.shadow}`,
  transformOrigin: "var(--radix-popper-transform-origin, top right)", animation: `${popKeyframes} 140ms ${vars.easeOut}`,
  outline: "none",
});

/** On a touch screen: a sheet from the bottom, over the page dimmed. */
export const sheetShade = style({
  position: "fixed", inset: "0", zIndex: "80", background: vars.overlay, animation: `${fadeInKeyframes} 160ms ${vars.easeOut}`,
});
export const sheet = style({
  position: "fixed", left: "0", right: "0", bottom: "0", zIndex: "81", padding: "8px 12px calc(12px + env(safe-area-inset-bottom))",
  borderRadius: `${vars.rDialog} ${vars.rDialog} 0 0`, cornerShape: vars.cornerShape, ...glass,
  boxShadow: `0 -8px 32px ${vars.shadow}`, outline: "none",
  animation: `${mRiseInKeyframes} 260ms ${vars.easeOut}`,
});
export const sheetGrab = style({
  display: "block", width: "36px", height: "5px", margin: "0 auto 10px", borderRadius: "3px", background: vars.lineStrong,
});
export const sheetTitle = style({ margin: "0 8px 8px", fontSize: vars.textMd, fontWeight: "600" });

export const panel = style({ display: "flex", flexDirection: "column" });
export const option = style({
  display: "flex", alignItems: "center", gap: "8px", width: "100%", height: "34px", padding: "0 10px 0 8px",
  border: "0", borderRadius: vars.rOption, cornerShape: vars.cornerShape, background: "none", color: vars.text,
  font: "inherit", fontSize: vars.textSm, textAlign: "left", cursor: "pointer", outline: "none",
  selectors: {
    "&:hover, &:focus-visible": { background: vars.hover },
    [`${panel}[data-touch] &`]: { height: "46px", fontSize: vars.textBody },
  },
});
export const check = style({ display: "grid", placeItems: "center", width: "16px", flex: "none", color: vars.accent });
export const optionName = style({ flex: "1" });
export const optionNote = style({ color: vars.muted, fontSize: vars.textXs, fontVariantNumeric: "tabular-nums" });
export const sep = style({ height: "1px", margin: "6px 4px", background: vars.line });
export const row = style({
  display: "flex", alignItems: "center", gap: "8px", minHeight: "36px", padding: "0 4px 0 32px",
  selectors: { [`${panel}[data-touch] &`]: { minHeight: "52px" } },
});
export const label = style({ flex: "1", fontSize: vars.textSm, color: vars.text });
export const fields = style({ display: "flex", alignItems: "center", gap: "4px" });
export const field = style({
  width: "52px", height: "28px", padding: "0 6px", border: "0", borderRadius: vars.rField, cornerShape: vars.cornerShape,
  background: vars.neutralBg, color: vars.text, font: "inherit", fontSize: vars.textSm, textAlign: "center",
  fontVariantNumeric: "tabular-nums", outline: "none",
  transition: `box-shadow ${vars.dur} ${vars.easeOut}, background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&::placeholder": { color: vars.subtle },
    "&:focus": { background: vars.canvas, boxShadow: `0 0 0 1.5px ${vars.fieldFocus}` },
    [`${panel}[data-touch] &`]: { width: "68px", height: "38px", fontSize: "16px" },
  },
});
export const times = style({ color: vars.subtle, fontSize: vars.textXs });
export const turn = style({
  display: "grid", placeItems: "center", width: "28px", height: "28px", border: "0", borderRadius: "50%",
  background: "none", color: vars.muted, cursor: "pointer",
  selectors: {
    "&:hover:not(:disabled)": { background: vars.hover, color: vars.text },
    "&:disabled": { opacity: ".35", cursor: "default" },
    [`${panel}[data-touch] &`]: { width: "38px", height: "38px" },
  },
});
/** Zooming: out, how much, in. */
export const zoom = style({ display: "flex", alignItems: "center", gap: "2px" });
export const zoomValue = style({
  minWidth: "42px", textAlign: "center", fontSize: vars.textXs, color: vars.text, fontVariantNumeric: "tabular-nums",
});
/** Back to fitted: a quiet text button. */
export const fit = style({
  height: "26px", padding: "0 10px", border: "0", borderRadius: "999px", background: vars.neutralBg, color: vars.text,
  font: "inherit", fontSize: vars.textXs, cursor: "pointer",
  selectors: {
    "&:hover:not(:disabled)": { background: vars.hover },
    "&:disabled": { color: vars.subtle, cursor: "default", background: "none" },
  },
});
export const hint = style({ margin: "2px 8px 4px 32px", fontSize: vars.textXs, lineHeight: "1.5", color: vars.muted });
/** The bar's turn, beside the size. */
export const turnBar = style({
  flex: "none", display: "grid", placeItems: "center", width: "28px", height: "28px", border: "0", borderRadius: "50%",
  background: "none", color: vars.muted, cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover, color: vars.text } },
});
