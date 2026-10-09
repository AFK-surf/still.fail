import { style } from "@vanilla-extract/css";

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
