import { style } from "@vanilla-extract/css";
import { DIALOG_INNER } from "@stillfail/ui/parts.css.ts";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** A QR code on white whatever the theme (phones read dark on light), its quiet zone the card's own margin. */
export const qr = style({
  display: "block", flex: "none", background: "#fff", borderRadius: DIALOG_INNER, cornerShape: vars.cornerShape,
});
export const dim = style({ opacity: 0.25 });
