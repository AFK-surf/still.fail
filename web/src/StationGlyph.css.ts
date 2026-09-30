import { keyframes, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

// A blink: the eye stays open most of the time and shuts for a moment.
const blink = keyframes({ "0%, 88%, 100%": { transform: "scaleY(1)" }, "93%": { transform: "scaleY(0.1)" } });

// Ink is the colour it is drawn in (currentColor); only a failing station's dot has its own, red.
export const stationGlyph = style({ display: "block", flex: "none", overflow: "visible" });
export const glyphDot = style({ fill: `var(--m-red, ${vars.red})` });
export const glyphPart = style({ transition: "stroke-opacity 240ms var(--m-standard), opacity 240ms var(--m-standard)" });
export const glyphEye = style({
  transformBox: "fill-box", transformOrigin: "center",
  selectors: { "&[data-blink]": { animation: `${blink} 2.6s ease-in-out infinite` } },
  "@media": { "(prefers-reduced-motion: reduce)": { animation: "none !important" } },
});
