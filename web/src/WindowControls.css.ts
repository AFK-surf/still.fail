import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

export const controls = style({
  position: "fixed", top: 6, right: 12, height: 32, display: "flex", alignItems: "center", gap: 2,
  zIndex: 1000, pointerEvents: "auto", WebkitAppRegion: "no-drag",
  selectors: { "[data-fullscreen] &": { display: "none" } },
});
export const separator = style({ width: 1, height: 16, marginRight: 6, marginLeft: 8, background: vars.line });
export const maximize = style({
  selectors: {
    '&[data-hover="true"]': { background: vars.hover, color: vars.text },
    '&[data-pressed="true"]': { background: vars.selected, color: vars.text },
  },
});
export const close = style({ selectors: { "&:hover": { background: vars.redBg, color: vars.red } } });
