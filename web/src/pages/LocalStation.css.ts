import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { cardLook } from "../styles/pages.css.ts";

// This machine's station (LocalStation.tsx): a card with whether it runs and its release over what it is, then its
// log and data directory; an installed one behind the app's release says so above it, with the update.
export const card = style({ ...cardLook, display: "grid", gap: "14px", padding: "16px 18px" });
export const head = style({ display: "flex", alignItems: "center", gap: "8px", minWidth: "0" });
export const status = style({ fontWeight: "600", color: vars.text });
export const version = style({ color: vars.muted, fontVariantNumeric: "tabular-nums" });
export const facts = style({
  display: "grid", gridTemplateColumns: "auto minmax(0, 1fr)", gap: "8px 16px", alignItems: "baseline", margin: "0",
  fontSize: vars.textUi, lineHeight: vars.leadingUi, color: vars.text,
});
globalStyle(`${facts} dt`, { color: vars.muted });
globalStyle(`${facts} dd`, { margin: "0", minWidth: "0" });
export const path = style({ fontFamily: vars.fontMono, fontSize: vars.textMeta, overflowWrap: "anywhere" });
export const links = style({ display: "flex", flexWrap: "wrap", gap: "4px", marginLeft: "-8px" });
export const outdated = style({ display: "flex", alignItems: "center", gap: "12px", marginBottom: "20px" });
