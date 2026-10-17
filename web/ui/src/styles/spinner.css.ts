// Something under way: a small turning ring, in one of two sizes (docs/ui-panels.md「等待」): `spinner` (14) where it
// stands for a button's icon, with `inline` (12) in a line of small text (a row's end, a pill). Where it sits says its
// colour and place, never its size.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";
import { spinKeyframes } from "./keyframes.css.ts";

export const spinner = style({});
globalStyle(spinner, {
  // Inline-block: sized in a line of text too, not only as a flex item.
  display: "inline-block", verticalAlign: "middle", width: "14px", height: "14px", flex: "none", boxSizing: "border-box", borderRadius: "50%", border: `2px solid ${vars.lineStrong}`,
  borderTopColor: vars.accent, animation: `${spinKeyframes} 0.8s linear infinite`,
});
export const inline = style({});
globalStyle(`${spinner}${inline}`, { width: "12px", height: "12px" });
globalStyle(spinner, {
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animationDuration: "2.4s",
    },
  },
});
