import { keyframes, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

// A blink: the eye stays open most of the time and shuts for a moment.
const blink = keyframes({ "0%, 88%, 100%": { transform: "scaleY(1)" }, "93%": { transform: "scaleY(0.1)" } });

// Ink is the colour it is drawn in (currentColor); only a failing station's dot has its own, red.
export const stationGlyph = style({ display: "block", flex: "none", overflow: "visible" });
export const glyphDot = style({ fill: `var(--m-red, ${vars.red})` });
export const glyphPart = style({ transition: "stroke-opacity 240ms var(--m-standard), opacity 240ms var(--m-standard)" });
// A link on its way: its arc breathes between the track and ink (Android ui/StationGlyph.kt the same); halfway, still,
// with motion reduced.
const breathe = keyframes({ "0%, 100%": { strokeOpacity: 0.18 }, "50%": { strokeOpacity: 0.85 } });
export const glyphPulse = style({
  strokeOpacity: 0.5, animation: `${breathe} 1.4s ease-in-out infinite`,
  "@media": { "(prefers-reduced-motion: reduce)": { animation: "none" } },
});
export const glyphEye = style({
  transformBox: "fill-box", transformOrigin: "center",
  selectors: { "&[data-blink]": { animation: `${blink} 2.6s ease-in-out infinite` } },
  "@media": { "(prefers-reduced-motion: reduce)": { animation: "none !important" } },
});
