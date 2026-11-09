import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const person = style({ flex: "none", borderRadius: "50%", objectFit: "cover" });
export const personLetter = style({
  display: "inline-grid", placeItems: "center", background: vars.paper, color: vars.text, fontWeight: "600",
  // Its own line box: the page's taller one sets a CJK initial low in the circle.
  lineHeight: "1",
});
