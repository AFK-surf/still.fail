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
      },
    },
  },
});
export const main = style({
  position: "relative", minWidth: "0", minHeight: "0", overflow: "hidden", display: "flex", flexDirection: "column",
  selectors: {
    // The desktop app has no title bar: the top row of every page drags the window, whether it has a bar (styles/sidebar.css.ts
    // pageBar) or not (a new chat, settings, the archive…). Under the page, so the page still takes the pointer; what is
    // pressed in that row does not drag (below).
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
globalStyle(`[data-desktop] ${main} :is(a, button, input, select, textarea, label, summary, [role="button"], [role="tab"], [role="link"], [role="menuitem"], [tabindex]:not([tabindex="-1"]), [contenteditable])`, {
  WebkitAppRegion: "no-drag",
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
