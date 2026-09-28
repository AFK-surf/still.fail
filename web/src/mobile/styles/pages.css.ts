import { style } from "@vanilla-extract/css";
import { m } from "./root.css.ts";

export const mScreen = style({
  position: "absolute", inset: "0", display: "flex", flexDirection: "column", background: "var(--m-bg)",
});
export const mScroll = style({
  flex: "1", minHeight: "0", overflowY: "auto", overscrollBehavior: "contain", WebkitOverflowScrolling: "touch",
  selectors: {
    [`${mScreen}&`]: { display: "block", paddingBottom: "var(--m-foot)" },
  },
});
/** Frosted glass: a bar at the top of a page over the list running under it, a hairline along its bottom. */
export const mGlass = style({
  background: "color-mix(in srgb, var(--m-bg) 70%, transparent)", WebkitBackdropFilter: "blur(24px)",
  backdropFilter: "blur(24px)", boxShadow: "inset 0 -0.5px 0 var(--m-line)",
});
/** A capsule floating over the list: raised, frosted, with a hairline round it. */
export const mFloating = style({
  background: "color-mix(in srgb, var(--m-surface) 72%, transparent)", WebkitBackdropFilter: "blur(20px)",
  backdropFilter: "blur(20px)", border: "0.5px solid var(--m-line)",
  boxShadow: "0 6px 16px rgba(0, 0, 0, .14), 0 2px 5px rgba(0, 0, 0, .1)",
  selectors: {
    [`:root[data-theme="dark"] ${m} &`]: { background: "color-mix(in srgb, var(--m-surface2) 72%, transparent)" },
  },
  "@media": {
    "(prefers-color-scheme: dark)": {
      selectors: {
        [`:root:not([data-theme="light"]) ${m} &`]: { background: "color-mix(in srgb, var(--m-surface2) 72%, transparent)" },
      },
    },
  },
});
