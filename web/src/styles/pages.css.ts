import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";

export const page = style({
  flex: "1", minHeight: "0", overflowY: "auto", padding: "40px 40px 80px",
  "@media": {
    "(max-width: 700px)": {
      padding: "24px 18px 60px",
    },
  },
});
export const pageNarrow = style({});
export const pageHead = style({
  display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: "16px", marginBottom: "28px",
});
export const identity = style({ display: "flex", alignItems: "center", gap: "16px", marginBottom: "28px" });
export const identityText = style({ flex: "1", minWidth: "0" });
export const identityName = style({
  display: "flex", alignItems: "center", gap: "4px", margin: "0", fontSize: vars.textLg, lineHeight: "34px", fontWeight: "650",
});
export const iconBtn = style({
  display: "inline-grid", placeItems: "center", width: "32px", height: "32px", padding: "0", border: "0",
  borderRadius: `calc(12px * ${vars.cornerScale})`, background: "transparent", color: vars.muted, cursor: "pointer",
  flex: "none", transition: `background ${vars.dur} ${vars.easeOut}, color ${vars.dur} ${vars.easeOut}`,
  cornerShape: vars.cornerShape,
  selectors: {
    [`${identityName} &`]: { opacity: ".55" },
    [`${identityName}:hover &`]: { opacity: "1" },
    "&:hover": { background: vars.hover, color: vars.text },
    "&[aria-pressed=\"true\"]": { background: vars.selected, color: vars.text },
  },
});
export const identitySub = style({
  display: "flex", flexWrap: "wrap", alignItems: "center", gap: "6px 14px", margin: "6px 0 0", color: vars.muted,
  fontSize: vars.textSm, lineHeight: "20px",
});
export const section = style({ marginBottom: "28px" });
/**
 * A grey ground, no line round it (its buttons have none either: controls.css.ts), and round corners concentric with the
 * pills in them: a 32px button (16px ends) 25px from the side and, in a row of a title and a line under it (42px), from
 * the top or bottom too (20px + 5px), so 16 + 25px. Its text keeps as far from the edges.
 */
export const card = style({
  borderRadius: "calc(16px + 25px)", padding: "20px 25px", background: `color-mix(in oklab, ${vars.text} 4%, ${vars.canvas})`,
  display: "grid", gap: "14px",
  // Out past the column by its padding: what is in it lines up with what is outside (the section's title, the rows and
  // buttons between cards), on both sides. Not where the page's own padding is less than that.
  marginInline: "-25px",
  "@media": {
    "(max-width: 700px)": { marginInline: "0" },
  },
  selectors: {
    "& + &": { marginTop: "10px" },
  },
});
export const cardRow = style({ display: "flex", alignItems: "center", gap: "12px" });
export const cardRowText = style({ flex: "1", display: "grid", gap: "2px", minWidth: "0", fontSize: vars.textSm });
export const cardActions = style({ display: "flex", justifyContent: "flex-end", gap: "8px" });
export const list = style({});
export const listRow = style({
  display: "flex", alignItems: "center", gap: "12px", minHeight: "52px", padding: "10px 12px",
  borderRadius: vars.rField, cornerShape: vars.cornerShape, fontSize: vars.textSm,
  transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.list },
  },
});
export const listRowText = style({ flex: "1", display: "grid", gap: "2px", minWidth: "0" });
export const listRowTitle = style({
  flex: "1", minWidth: "0", fontWeight: "500", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
  selectors: {
    [`${listRowText} &`]: { flex: "none" },
  },
});
export const mark = style({
  display: "inline-grid", placeItems: "center", flex: "none", borderRadius: `calc(10px * ${vars.cornerScale})`,
  background: vars.paper, color: vars.text, cornerShape: vars.cornerShape,
});
globalStyle(`${pageHead} h1`, { margin: "0", fontSize: vars.textLg, lineHeight: "34px", fontWeight: "650" });
