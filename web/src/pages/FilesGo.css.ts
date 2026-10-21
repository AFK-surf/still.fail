import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** The station's button at the start of a folder's trail. */
export const switchButton = style({
  display: "inline-flex", alignItems: "center", gap: "5px", height: "22px", padding: "0 7px", border: `1px solid ${vars.line}`,
  borderRadius: vars.rOption, background: vars.raised, color: vars.text, font: "inherit", fontSize: vars.textMeta, fontWeight: "500", cursor: "pointer",
  selectors: { "&:hover, &[data-state=open]": { borderColor: vars.lineStrong } },
});
globalStyle(`${switchButton} svg`, { color: vars.muted });
export const stations = style({ minWidth: "240px" });
export const stationName = style({ flex: "1" });
export const stationMeta = style({ marginLeft: "12px", color: vars.muted, fontSize: vars.textMeta });
export const stationsFoot = style({ padding: "6px 10px 4px", borderTop: `1px solid ${vars.line}`, marginTop: "4px", color: vars.subtle, fontSize: vars.textCaption });

export const goInput = style({ width: "100%", boxSizing: "border-box", fontFamily: vars.fontMono });
export const goWhere = style({ margin: "8px 2px 0", color: vars.muted, fontSize: vars.textMeta, fontFamily: vars.fontMono, overflowWrap: "anywhere" });
export const goList = style({ display: "grid", gap: "2px", marginTop: "10px", maxHeight: "300px", overflowY: "auto" });
export const goRow = style({
  display: "flex", alignItems: "center", gap: "8px", padding: "7px 10px", border: "0", borderRadius: vars.rField, background: "none",
  color: vars.text, font: "inherit", fontSize: vars.textUi, textAlign: "left", cursor: "pointer",
  selectors: { "&[data-on]": { background: vars.selected } },
});
globalStyle(`${goRow} > span`, { flex: "1", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${goRow} > svg`, { flex: "none", color: vars.muted });
globalStyle(`${goRow} kbd`, { flex: "none", padding: "0 5px", borderRadius: "4px", border: `1px solid ${vars.line}`, color: vars.muted, fontSize: vars.textCaption, fontFamily: "inherit" });
/** Under the list: its keys, so no row sits in the dialog's corner. */
export const goKeys = style({ margin: "10px 2px 0", color: vars.subtle, fontSize: vars.textCaption });
