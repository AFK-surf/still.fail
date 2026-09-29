import { style } from "@vanilla-extract/css";
import { spinKeyframes } from "./styles/keyframes.css.ts";

/**
 * A chat's state on its row's picture (ChatMark.tsx), at the corner, over the picture: a gap of the row's ground
 * (`--mark-around`) round it. Three colours, bright in both themes: yellow at work, blue done and not yet read, red to
 * be seen now. The ground may be see-through (a row's hover tint): `--mark-under` is then what it lies on, painted
 * beneath it, so the gap stays solid and the picture does not show through.
 */
export const chatMark = style({
  position: "absolute", right: -3, bottom: -3, width: 14, height: 14, borderRadius: "50%", boxSizing: "border-box",
  border: "2px solid transparent",
  backgroundImage: "linear-gradient(var(--mark-around) 0 0)", backgroundColor: "var(--mark-under, transparent)",
  selectors: {
    '&[data-tone="done"]': {
      backgroundImage: "linear-gradient(#3b82f6 0 0), linear-gradient(var(--mark-around) 0 0)",
      backgroundClip: "padding-box, border-box",
    },
    '&[data-tone="alert"]': {
      backgroundImage: "linear-gradient(#e5484d 0 0), linear-gradient(var(--mark-around) 0 0)",
      backgroundClip: "padding-box, border-box",
    },
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
