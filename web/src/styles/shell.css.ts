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
        "&&[data-layout=\"list\"]": { gridTemplateColumns: "minmax(0, 1fr)" },
      },
    },
  },
});
export const main = style({
  position: "relative", minWidth: "0", minHeight: "0", overflow: "hidden", display: "flex", flexDirection: "column",
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
});
export const muted = style({ color: vars.muted });
export const mono = style({ fontFamily: vars.fontMono });
globalStyle(`${gate} h1`, { margin: "8px 0 0", fontSize: vars.textMd });
globalStyle(`${gate} p`, { margin: "0", color: vars.muted, maxWidth: "36em" });
