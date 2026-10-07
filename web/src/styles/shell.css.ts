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
      // The sidebar lies on the window; the page beside it is a pane laid into it (main).
      background: vars.window,
      selectors: {
        "[data-sidebar=\"closed\"] &": { gridTemplateColumns: "0px minmax(0, 1fr)" },
      },
    },
  },
});
export const main = style({
  position: "relative", minWidth: "0", minHeight: "0", overflow: "hidden", display: "flex", flexDirection: "column",
  "@media": {
    // A pane laid into the window, after Cue's: inset from its edges, rounded, a hairline and a soft shadow round it.
    // A chat with its side panel open is two panes (session.css.ts), and this one only holds them.
    "(min-width: 701px)": {
      // 8px clear of the sidebar too: its frosted bands would otherwise cover the hairline where they meet.
      margin: "8px", borderRadius: "12px", background: vars.canvas,
      boxShadow: `${vars.paneShadow}, 0 0 0 .5px ${vars.ring}`,
    },
    "(min-width: 1101px)": {
      selectors: {
        "&:has([data-panel=\"true\"])": { background: "none", boxShadow: "none" },
      },
    },
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
});
export const muted = style({ color: vars.muted });
export const mono = style({ fontFamily: vars.fontMono });
globalStyle(`${gate} h1`, { margin: "8px 0 0", fontSize: vars.textMd });
globalStyle(`${gate} p`, { margin: "0", color: vars.muted, maxWidth: "36em" });
