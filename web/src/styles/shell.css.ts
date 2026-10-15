import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";
import { panel } from "./glass.ts";

export const shell = style({
  position: "relative", display: "grid", gridTemplateColumns: "240px minmax(0, 1fr)", height: ["100vh", "100dvh"],
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
      // The closed bar's shadow, there but clear while open: the same shadow either way, so it eases in (from none it
      // would come at once).
      boxShadow: "0 8px 24px transparent",
      cornerShape: vars.cornerShape,
      // Its margins moved with its column (brand.tsx moveSidebar), the rest eased here.
      transition: ["border-radius", "background-color", "box-shadow"].map((p) => `${p} 380ms ${vars.easeOut}`).join(", "),
      selectors: {
        // Concentric with what is lit in it (the rail's places' ground, its 9 px corner 6 px in from its every edge), and
        // as far from the window's edges as that ground from its own: 6 (its 56 column's other 8 the gutter by the page,
        // where its edge's bar is, Rail.css.ts).
        // Closed, no longer the sidebar but floating over the page: a floating panel's ground (glass.ts panel, as menus
        // and notices), its line (::after, below) and its shadow.
        '[data-sidebar="closed"] &': {
          margin: "6px 8px 6px 6px", borderRadius: `calc(9px * ${vars.cornerScale} + 6px)`,
          // As the sidebar's ground for all in it (the list's frosted bands, the rings round marks), so none shows the
          // old one as it closes.
          vars: { [vars.sidebar]: panel.background },
          boxShadow: `0 8px 24px ${vars.shadow}`,
          // Over the page, its shadow too: under the page's frosted top bar it was blurred into a block that ended at the
          // bar's foot.
          zIndex: 20,
        },
        '[data-desktop="inset"]:not([data-fullscreen])[data-sidebar="closed"] &': { marginTop: 44 },
        // Folded but shown a while (Rail.tsx peekSidebar): the bar reaching over the page as wide as the rail and the
        // sidebar (its margin, eased as the bar's others), the page left where it is.
        '[data-sidebar="closed"][data-sidebar-peek] &': { marginRight: "calc(8px - var(--sidebar-w, 240px))" },
      },
    },
    "(prefers-reduced-motion: reduce)": { transition: "none" },
  },
});

// The closed bar's line, drawn within (a border would take from the rail's 42) and over all in it: an inset shadow is
// under its children, and the sidebar's top row and frosted band, still in it as it closes, covered it.
globalStyle(`${dock}::after`, {
  "@media": {
    "(min-width: 701px)": {
      content: '""', position: "absolute", inset: 0, zIndex: 3, borderRadius: "inherit", cornerShape: "inherit", pointerEvents: "none",
      boxShadow: `inset 0 0 0 1px ${vars.line}`, opacity: 0, transition: `opacity 380ms ${vars.easeOut}`,
    },
  },
});
globalStyle(`[data-sidebar="closed"] ${dock}::after`, { "@media": { "(min-width: 701px)": { opacity: 1 } } });

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
// The window takes a click on a drag region for itself and the page never sees it, so a menu, popover or select left open
// would stay open when the top of the window is clicked. While one is open nothing drags: the click reaches the page and
// closes it like a click anywhere else. Tooltips (data-state "delayed-open"/"instant-open") don't count.
const menuOpen = `:root[data-desktop]:has([data-radix-popper-content-wrapper] > [data-state="open"], [data-radix-select-viewport])`;
globalStyle(`${menuOpen} *, ${menuOpen} *::before, ${menuOpen} *::after`, { WebkitAppRegion: "no-drag !important" as "no-drag" });
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
