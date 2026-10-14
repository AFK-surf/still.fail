import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";

export const shell = style({
  display: "grid", gridTemplateColumns: "240px minmax(0, 1fr)", height: ["100vh", "100dvh"],
  "@media": {
    "(max-width: 700px)": {
      gridTemplateColumns: "1fr",
    },
    "(min-width: 701px)": {
      gridTemplateColumns: "var(--sidebar-w, 240px) minmax(0, 1fr)",
      selectors: {
        "[data-sidebar=\"closed\"] &": { gridTemplateColumns: "0px minmax(0, 1fr)" },
        // A workspace's: the rail (Rail.tsx) and the sidebar beside it in one block (dock), which closes to the rail.
        "&[data-rail]": { gridTemplateColumns: "calc(56px + var(--sidebar-w, 240px)) minmax(0, 1fr)" },
        "[data-sidebar=\"closed\"] &[data-rail]": { gridTemplateColumns: "56px minmax(0, 1fr)" },
      },
    },
  },
});
/**
 * The rail and the sidebar as one block of the sidebar's ground. The sidebar closing, the block narrows to the rail (its
 * column, styles above, moved by brand.tsx) and stands off the page's edges as a long rounded bar, cutting the sidebar as
 * it goes (the sidebar keeps its width inside); in the macOS app the bar is under the window's buttons. Its margins and
 * corner move as long and eased as the column (motion.ts moveState, 380 ms). On a narrow screen it is nothing of its own.
 */
export const dock = style({
  "@media": {
    "(max-width: 700px)": { display: "contents" },
    "(min-width: 701px)": {
      position: "relative", display: "flex", minWidth: 0, minHeight: 0, overflow: "hidden", background: vars.sidebar, margin: 0, borderRadius: 0,
      cornerShape: vars.cornerShape, transition: `margin 380ms ${vars.easeOut}, border-radius 380ms ${vars.easeOut}`,
      selectors: {
        // Concentric with what is lit in it (the rail's items, their 12 px corner 3 px in from its sides).
        '[data-sidebar="closed"] &': { margin: "8px 6px", borderRadius: `calc(12px * ${vars.cornerScale} + 3px)` },
        '[data-desktop="inset"]:not([data-fullscreen])[data-sidebar="closed"] &': { marginTop: 44 },
      },
    },
    "(prefers-reduced-motion: reduce)": { transition: "none" },
  },
});

export const main = style({
  position: "relative", minWidth: "0", minHeight: "0", overflow: "hidden", display: "flex", flexDirection: "column",
  selectors: {
    // The desktop app has no title bar: the top row of every page drags the window, whether it has a bar (styles/sidebar.css.ts
    // pageBar) or not (a new chat, settings, the archive…). Under the page, so the page still takes the pointer. Nothing
    // in the page's body is no-drag: the window takes the row's area from each such element's whole box, cut by no
    // scroller, so a link in a message scrolled up out of sight would make the bar above it undraggable.
    "[data-desktop] &::before": { content: '""', position: "absolute", zIndex: -1, top: 0, left: 0, right: 0, height: 44, WebkitAppRegion: "drag" },
  },
  "@media": {
    "(max-width: 700px)": {
      selectors: {
        [`${shell}:not([data-detail="true"]) &`]: { display: "none" },
      },
    },
  },
});
export const gate = style({
  height: "100%", display: "grid", placeContent: "center", justifyItems: "center", gap: "8px", padding: "24px",
  textAlign: "center",
  selectors: {
    // A page of its own (signing in, an invitation): in the desktop app, with no title bar, its top drags the window.
    "[data-desktop] &::before": { content: '""', position: "fixed", top: 0, left: 0, right: 0, height: 44, WebkitAppRegion: "drag" },
  },
});
export const muted = style({ color: vars.muted });
export const mono = style({ fontFamily: vars.fontMono });
globalStyle(`${gate} h1`, { margin: "8px 0 0", fontSize: vars.textTitle });
globalStyle(`${gate} p`, { margin: "0", color: vars.muted, maxWidth: "36em" });
