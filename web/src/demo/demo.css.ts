// The app as a part of the site's page (site/Site.tsx), not the whole of it: the page scrolls as pages do, and the
// app fills #demo (the page gives it its size), with the type it would have on its own page.
import { globalStyle } from "@vanilla-extract/css";
import { shell } from "../styles/shell.css.ts";
import { vars } from "../styles/tokens.css.ts";

globalStyle("html, body", { height: "auto", overflow: "visible", overscrollBehavior: "auto" });
globalStyle("#demo", {
  // What the app places fixed (the buddy by its logo, overlays) is placed within the demo, not the window.
  position: "relative", overflow: "hidden", textAlign: "left", transform: "translateZ(0)",
  background: vars.canvas, color: vars.text, font: `400 ${vars.textBody}/1.55 ${vars.fontBody}`,
  fontFeatureSettings: "\"cv11\", \"ss01\"", lineBreak: "strict", textWrap: "pretty",
});
globalStyle(`#demo ${shell}`, { height: "100%" });
