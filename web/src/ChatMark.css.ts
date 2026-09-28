import { style } from "@vanilla-extract/css";
import { spinKeyframes } from "./styles/keyframes.css.ts";

/**
 * A chat's state on its row's picture (ChatMark.tsx), at the corner, over the picture: a gap of the row's ground
 * (`--mark-around`) round it. Three colours, bright in both themes: yellow at work, blue done and not yet read, red to
 * be seen now.
 */
export const chatMark = style({
  position: "absolute", right: -3, bottom: -3, width: 14, height: 14, borderRadius: "50%", boxSizing: "border-box",
  border: "2px solid var(--mark-around)", background: "var(--mark-around)",
  selectors: {
    '&[data-tone="done"]': { background: "#3b82f6" },
    '&[data-tone="alert"]': { background: "#e5484d" },
    // A soft halo, the heaviest of the three: nothing else in the row is this loud.
    '&[data-tone="alert"]::after': {
      content: "\"\"", position: "absolute", inset: -5, borderRadius: "50%", background: "#e5484d", opacity: 0.25,
    },
    // At work: a turning ring with a gap.
    '&[data-tone="busy"]::after': {
      content: "\"\"", position: "absolute", inset: 0, borderRadius: "50%", boxSizing: "border-box",
      border: "2px solid #f2b01e", borderRightColor: "color-mix(in srgb, #f2b01e 25%, transparent)",
      animation: `${spinKeyframes} 1.2s linear infinite`,
    },
  },
  "@media": { "(prefers-reduced-motion: reduce)": { selectors: { '&[data-tone="busy"]::after': { animation: "none" } } } },
});
