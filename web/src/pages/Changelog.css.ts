import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

// The changelog: a day's heading, then each change's lines, and under them where it is and whether this app has it
// (grey but for an update that would bring it). No lines between.
export const heading = style({ margin: "18px 10px 4px", fontSize: vars.textMeta, color: vars.muted });
export const change = style({ display: "grid", gap: "2px", padding: "8px 10px" });
export const line = style({ margin: "0", fontSize: vars.textUi, lineHeight: "20px" });
export const meta = style({ display: "flex", flexWrap: "wrap", gap: "0 10px", margin: "0", fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted });
export const note = style({
  selectors: {
    '&[data-has="false"]': { color: vars.accentText },
  },
});

// After an update, at the sidebar's foot: what it brought, put away by its ×.
export const news = style({
  position: "relative", margin: "0 0 6px", borderRadius: vars.rNav, background: vars.hover, cornerShape: vars.cornerShape,
});
export const newsLink = style({
  display: "grid", gap: "2px", padding: "8px 30px 9px 10px", color: vars.text, fontSize: vars.textMeta, lineHeight: "18px",
  borderRadius: "inherit", cornerShape: vars.cornerShape,
  selectors: { "&:hover": { background: vars.selected } },
});
export const newsHead = style({
  display: "flex", alignItems: "center", gap: "6px", marginBottom: "2px", fontSize: vars.textUi, lineHeight: "20px", fontWeight: 500,
});
export const newsLine = style({ color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const newsMore = style({ color: vars.muted });
export const newsClose = style({
  position: "absolute", top: "6px", right: "6px", display: "grid", placeItems: "center", width: "24px", height: "24px",
  border: "0", borderRadius: "8px", color: vars.muted, background: "transparent", cursor: "pointer",
  selectors: { "&:hover": { color: vars.text, background: vars.hover } },
});
