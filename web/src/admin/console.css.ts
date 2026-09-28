import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { muted } from "../styles/shell.css.ts";
import { listRowTitle } from "../styles/pages.css.ts";

export const chips = style({ display: "flex", flexWrap: "wrap", gap: "6px" });
export const chip = style({
  padding: "3px 10px", borderRadius: "999px", background: vars.neutralBg, fontSize: vars.textXs,
});
export const accountEmail = style({
  fontSize: vars.textXs, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** The admin console: each thing a block on the sidebar's ground, apart by spacing, with no rules between. */
export const adminList = style({
  listStyle: "none", marginTop: "0", marginBottom: "0", padding: "0", display: "grid", gap: "8px",
});
export const adminItem = style({
  display: "grid", gap: "12px", padding: "14px 16px", borderRadius: vars.rCard, background: vars.sidebar,
  fontSize: vars.textSm, cornerShape: vars.cornerShape,
});
export const adminHead = style({ display: "flex", alignItems: "center", gap: "12px", minWidth: "0" });
export const adminMeta = style({ margin: "0", fontSize: vars.textXs });
export const adminGroup = style({ display: "grid", gap: "2px" });
export const adminGroupLabel = style({ marginBottom: "2px", fontSize: vars.textXs, color: vars.muted });
export const adminLine = style({
  display: "flex", alignItems: "center", gap: "8px", minHeight: "28px", padding: "0 10px", borderRadius: vars.rOption,
  background: vars.canvas, cornerShape: vars.cornerShape,
  selectors: {
    "& + &": { marginTop: "2px" },
  },
});
export const adminLineText = style({
  flex: "1", minWidth: "0", display: "flex", alignItems: "baseline", gap: "8px", overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const adminCode = style({ fontSize: vars.textBody, letterSpacing: ".04em" });
export const adminNote = style({ fontWeight: "400", color: vars.muted, overflow: "hidden", textOverflow: "ellipsis" });
export const adminFoot = style({ padding: "8px" });
export const adminAccount = style({
  flex: "1", minWidth: "0", display: "flex", alignItems: "center", gap: "8px", padding: "0 6px",
});
globalStyle(`${adminHead} ${listRowTitle}`, { display: "flex", alignItems: "baseline", gap: "10px" });
globalStyle(`${adminLine} > ${muted}`, { flex: "none", fontSize: vars.textXs });
globalStyle(`${adminLineText} ${muted}`, { fontSize: vars.textXs });
