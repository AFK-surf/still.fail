// Something under way: a small turning ring. Its size where it sits is said there (`${place}${spinner}`).
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";
import { spinKeyframes } from "./keyframes.css.ts";

export const spinner = style({});
globalStyle(spinner, {
  width: "16px", height: "16px", flex: "none", borderRadius: "50%", border: `2px solid ${vars.lineStrong}`,
  borderTopColor: vars.accent, animation: `${spinKeyframes} 0.8s linear infinite`,
});
globalStyle(spinner, {
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animationDuration: "2.4s",
    },
  },
});
