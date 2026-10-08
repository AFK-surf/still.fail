import { style } from "@vanilla-extract/css";

// The emoji drawn in an icon's box: as wide and tall as the icon it stands for, centred, not cut.
export const emoji = style({
  display: "inline-grid", placeItems: "center", flex: "none", lineHeight: "1", overflow: "visible",
  fontFamily: "\"Apple Color Emoji\", \"Segoe UI Emoji\", \"Noto Color Emoji\", sans-serif",
});
