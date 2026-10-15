import { keyframes, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

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
// The eye shuts round its middle (its blink: StationGlyph.tsx).
export const glyphEye = style({ transformBox: "fill-box", transformOrigin: "center" });
