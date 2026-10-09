import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

/** Its icon in a line of text, before the station's name: on the text's middle, a space's width from the name. */
export const inline = style({ display: "inline-block", verticalAlign: "-0.125em", marginRight: "0.3em" });

// The emoji drawn in an icon's box: as wide and tall as the icon it stands for, centred, not cut.
export const emoji = style({
  display: "inline-grid", placeItems: "center", flex: "none", lineHeight: "1", overflow: "visible",
  fontFamily: "\"Apple Color Emoji\", \"Segoe UI Emoji\", \"Noto Color Emoji\", sans-serif",
});
/**
 * The emoji itself, as wide as it is drawn: some fonts give one more room than it takes (Apple's, at small sizes, draws a
 * 16px emoji at the left of 20px), which centring the room would leave off centre.
 */
export const glyph = style({ display: "inline-block", width: "1em", whiteSpace: "nowrap", textAlign: "left", overflow: "visible" });
/** A picture put up: a rounded square as large as the icon it stands for. */
export const picture = style({ display: "inline-block", flex: "none", objectFit: "cover", borderRadius: "24%", cornerShape: vars.cornerShape });
