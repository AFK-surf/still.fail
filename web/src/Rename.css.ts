// A chat's name while it is being changed: the name stays where it was, in its own type, on a light field that fits
// it; a thin line round it says it is being typed in.
import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { bleedX, inLine } from "@stillfail/ui/styles/align.ts";

export const titleInput = style({
  flex: 1, minWidth: 0, width: "100%", height: "24px", ...bleedX(6), ...inLine(4), border: "0",
  borderRadius: `calc(6px * ${vars.cornerScale})`, background: vars.canvas, color: vars.text, font: "inherit", lineHeight: "24px",
  boxShadow: `inset 0 0 0 1px ${vars.lineStrong}`, cornerShape: vars.cornerShape, outline: "none",
  selectors: { "&::placeholder": { color: vars.subtle, fontWeight: 400 } },
});
