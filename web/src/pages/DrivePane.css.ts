import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** Beside the list: as tall as the room it has, what it shows on top, what the file is under it. */
export const pane = style({
  position: "sticky", top: "0", alignSelf: "start", display: "flex", flexDirection: "column", gap: "12px", width: "300px", flex: "none",
  maxHeight: "calc(100vh - 160px)", padding: "12px", boxSizing: "border-box", borderLeft: `1px solid ${vars.line}`, minWidth: "0",
  selectors: {
    // Under the list: as wide as it, its own height at most half the room.
    "&[data-below]": { position: "static", width: "auto", maxHeight: "50vh", flex: "none", borderLeft: "0", borderTop: `1px solid ${vars.line}` },
  },
});
export const none = style({ margin: "24px 0", color: vars.muted, fontSize: vars.textMeta, textAlign: "center" });
export const body = style({ flex: "1 1 auto", minHeight: "120px", maxHeight: "60vh", overflow: "auto", borderRadius: vars.rField, background: vars.neutralBg, display: "grid" });
export const picture = style({ display: "block", maxWidth: "100%", maxHeight: "100%", margin: "auto", objectFit: "contain" });
export const waiting = style({ minHeight: "160px" });
export const mark = style({
  display: "grid", placeItems: "center", alignContent: "center", gap: "10px", minHeight: "180px", border: "0", background: "none",
  color: vars.muted, font: "inherit", fontSize: vars.textMeta, cursor: "pointer",
});
export const textBox = style({ padding: "10px 12px" });
export const code = style({ margin: "0", fontFamily: vars.fontMono, fontSize: vars.textCaption, lineHeight: "1.55", whiteSpace: "pre-wrap", overflowWrap: "anywhere", color: vars.text });
export const prose = style({ padding: "4px 12px", fontSize: vars.textMeta });
export const more = style({ margin: "8px 0 0", color: vars.subtle, fontSize: vars.textCaption });
export const about = style({ display: "grid", gap: "8px", flex: "none" });
export const name = style({ fontSize: vars.textUi, fontWeight: "600", color: vars.text, overflowWrap: "anywhere" });
export const facts = style({ display: "grid", gridTemplateColumns: "auto minmax(0, 1fr)", gap: "4px 12px", margin: "0", fontSize: vars.textMeta });
export const path = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontFamily: vars.fontMono, fontSize: vars.textCaption });
export const actions = style({ display: "flex", flexWrap: "wrap", gap: "6px" });
globalStyle(`${facts} dt`, { color: vars.muted });
globalStyle(`${facts} dd`, { margin: "0", color: vars.text, minWidth: "0" });
