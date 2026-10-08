// What the badge counts, in the sidebar's foot (Attention.tsx): its entry, and the list it opens.
import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

export const entry = style({ marginBottom: "4px", color: vars.text, width: "100%", border: "0", background: "none", textAlign: "left", font: "inherit", cursor: "pointer" });
export const lead = style({ width: "16px", flex: "none", display: "flex", justifyContent: "center", color: vars.red });
export const count = style({ flex: "1", color: vars.muted, fontVariantNumeric: "tabular-nums" });
export const pill = style({
  minWidth: "18px", height: "18px", padding: "0 5px", borderRadius: "9px", background: vars.red, color: "#fff",
  fontSize: vars.textXs, fontWeight: "600", display: "inline-flex", alignItems: "center", justifyContent: "center", fontVariantNumeric: "tabular-nums",
});

export const panel = style({ width: "340px", maxWidth: "calc(100vw - 24px)", maxHeight: "min(520px, 70vh)", overflowY: "auto", display: "flex", flexDirection: "column" });
export const group = style({ display: "flex", alignItems: "center", gap: "6px", padding: "8px 10px 4px", fontSize: vars.textXs, color: vars.muted, fontWeight: "600" });
export const dot = style({ width: "7px", height: "7px", borderRadius: "50%", flex: "none" });
export const item = style({
  display: "flex", alignItems: "flex-start", gap: "8px", width: "100%", padding: "7px 10px", border: "0", borderRadius: vars.rOption,
  background: "none", color: vars.text, textAlign: "left", font: "inherit", cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: { "&:hover, &:focus-visible": { background: vars.hover, outline: "none" } },
});
export const itemText = style({ flex: "1", minWidth: "0", display: "flex", flexDirection: "column", gap: "1px" });
export const itemTitle = style({ fontSize: vars.textSm, fontWeight: "500", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const itemLine = style({ fontSize: vars.textXs, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const dismiss = style({
  flex: "none", alignSelf: "center", padding: "2px 7px", border: `1px solid ${vars.line}`, borderRadius: vars.rOption, background: "none",
  color: vars.muted, fontSize: vars.textXs, font: "inherit", cursor: "pointer",
  selectors: { "&:hover": { color: vars.text, borderColor: vars.lineStrong } },
});
export const foot = style({ display: "flex", flexDirection: "column", gap: "6px", padding: "8px 10px 4px", fontSize: vars.textXs, color: vars.muted });
export const footLinks = style({ display: "flex", gap: "12px" });
export const link = style({ color: vars.accentText, textDecoration: "none", selectors: { "&:hover": { textDecoration: "underline" } } });
export const empty = style({ padding: "12px 10px", fontSize: vars.textSm, color: vars.muted });
