import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

// A tab a part, this app's first, under the title.
export const tabsRow = style({ display: "flex", marginBottom: "8px" });
export const tabs = style({ minWidth: "360px" });
globalStyle(`${tabs} > button`, { whiteSpace: "nowrap", padding: "0 14px" });

// The changelog: a day's heading, then each change: its lines, each with its kind before it, the version at the end
// of the first, and under them what is not out yet (in the accent when an update would bring it). No lines between.
export const heading = style({ margin: "20px 10px 2px", fontSize: vars.textMeta, fontWeight: 500, color: vars.muted });
export const change = style({ display: "grid", gap: "4px", padding: "8px 10px", borderRadius: vars.rField, cornerShape: vars.cornerShape });
export const row = style({ display: "grid", gridTemplateColumns: "52px minmax(0, 1fr) auto", alignItems: "baseline", columnGap: "10px" });
export const kind = style({
  justifySelf: "start", padding: "0 6px", borderRadius: "6px", fontSize: vars.textCaption, lineHeight: "18px",
  color: vars.muted, background: vars.neutralBg, whiteSpace: "nowrap",
  selectors: {
    "&:empty": { padding: "0", background: "none" },
    '&[data-kind="new"]': { color: vars.accentText, background: vars.accentBg },
  },
});
export const line = style({ margin: "0", fontSize: vars.textUi, lineHeight: "20px" });
export const version = style({ fontSize: vars.textMeta, color: vars.subtle, fontVariantNumeric: "tabular-nums" });
export const note = style({
  margin: "0 0 0 62px", fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted,
  selectors: { '&[data-has="false"]': { color: vars.accentText } },
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
