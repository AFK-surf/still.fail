import { style } from "@vanilla-extract/css";

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
/** A capsule floating over the list: raised and frosted, as the wide screen's composer (its ground, `--raised`, and shadow). */
export const mFloating = style({
  border: "0", background: "color-mix(in srgb, var(--raised) 72%, transparent)", WebkitBackdropFilter: "blur(20px)",
  backdropFilter: "blur(20px)", boxShadow: "0 1px 3px rgb(0 0 0 / .04)",
});
