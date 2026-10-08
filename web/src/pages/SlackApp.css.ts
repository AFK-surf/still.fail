import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { inputRow } from "../styles/additions.css.ts";
import { sidebarBuddy } from "../brand.css.ts";

export const colorSwatch = style({
  width: "36px", height: "36px", padding: "0", border: `1px solid ${vars.lineStrong}`,
  borderRadius: `calc(10px * ${vars.cornerScale})`, background: "none", cursor: "pointer", flex: "none",
  cornerShape: vars.cornerShape,
  selectors: {
    "&::-webkit-color-swatch-wrapper": { padding: "3px" },
    "&::-webkit-color-swatch": { border: "0", borderRadius: `calc(7px * ${vars.cornerScale})`, cornerShape: vars.cornerShape },
  },
});
export const tokenGuide = style({
  margin: "0", padding: "0", listStyle: "none", counterReset: "guide", display: "grid", gap: "18px",
});
export const appLook = style({
  display: "grid", gridTemplateColumns: "136px 1fr", gap: "16px", alignItems: "stretch",
  "@media": {
    "(max-width: 720px)": {
      gridTemplateColumns: "96px 1fr",
    },
  },
});
export const appAvatar = style({
  width: "136px", height: "136px", flex: "none", padding: "0", border: `1px solid ${vars.line}`,
  borderRadius: `calc(22px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, overflow: "hidden",
  cursor: "pointer", background: vars.neutralBg,
  "@media": {
    "(max-width: 720px)": {
      width: "96px", height: "96px",
    },
  },
});
export const appAvatarEmpty = style({
  display: "grid", placeItems: "center", gap: "4px", height: "100%", fontSize: vars.textMeta, color: vars.muted,
  alignContent: "center",
});
export const appLookMain = style({ flex: "1", minWidth: "0", display: "grid", gap: "8px" });
export const appNameInput = style({ height: "44px", fontSize: vars.textTitle, fontWeight: "600" });
export const appColour = style({ display: "flex", alignItems: "center", gap: "8px", fontSize: vars.textMeta });
export const appColourHex = style({ width: "96px", height: "28px", fontSize: vars.textMeta });
export const avatarPicker = style({
  display: "grid", gridTemplateColumns: "repeat(15, minmax(0, 1fr))", gap: "6px", margin: "16px 0 10px",
  "@media": {
    "(max-width: 720px)": {
      gridTemplateColumns: "repeat(auto-fill, minmax(40px, 1fr))",
    },
  },
});
export const avatarTile = style({
  width: "100%", aspectRatio: "1", height: "auto", padding: "0", border: `1px solid ${vars.line}`,
  borderRadius: `calc(9px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, display: "grid",
  placeItems: "center", cursor: "pointer", overflow: "hidden",
  selectors: {
    "&:hover": { borderColor: vars.fieldHover },
    "&[data-picked]": { outline: `2px solid ${vars.text}`, outlineOffset: "1px" },
  },
});
export const appDesc = style({ height: "34px", fontSize: vars.textUi });
export const appPerms = style({ fontSize: vars.textUi });
export const permSections = style({ display: "grid", gap: "4px", marginTop: "8px" });
export const permAll = style({ marginLeft: "8px" });
/** Names only, three to a line; what each allows shows on hover. */
export const permGrid = style({
  display: "grid", gridTemplateColumns: "repeat(3, minmax(0, 1fr))", gap: "0 8px", margin: "0", padding: "0", listStyle: "none",
  "@media": { "(max-width: 720px)": { gridTemplateColumns: "repeat(2, minmax(0, 1fr))" } },
});
export const appFold = style({ marginTop: "28px", marginBottom: "28px" });
export const appFoldTitle = style({ fontWeight: "600" });
export const appFoldBody = style({ display: "grid", gap: "10px", marginTop: "8px" });
export const appFoldLink = style({ justifySelf: "start", fontSize: vars.textMeta, color: vars.muted });
globalStyle(`${tokenGuide} li::before`, {
  content: "counter(guide)", position: "absolute", left: "0", top: "-1px", width: "24px", height: "24px",
  borderRadius: "50%", display: "grid", placeItems: "center", background: vars.neutralBg, color: vars.muted,
  fontSize: vars.textMeta, fontWeight: "600", fontVariantNumeric: "tabular-nums",
});
globalStyle(`${tokenGuide} li > ${inputRow}`, { marginTop: "6px" });
globalStyle(`${appAvatar} img`, { width: "100%", height: "100%", display: "block" });
globalStyle(`${appColour} ${colorSwatch}`, { width: "28px", height: "28px" });
globalStyle(`${avatarTile} img`, { width: "100%", height: "100%", transform: "scale(1.18)" });
globalStyle(`${avatarTile} img[data-mono]`, { filter: "brightness(0) invert(1)" });
globalStyle(`${appPerms} summary`, { cursor: "pointer", color: vars.muted, padding: "6px 0" });
/** Here rather than with its class: it comes after .app-avatar img, and wins over it. */
globalStyle(`${sidebarBuddy} img`, { display: "block", width: "28px", height: "28px" });
globalStyle(`${appFold} > summary`, {
  display: "flex", alignItems: "baseline", gap: "10px", cursor: "pointer", listStyle: "none", padding: "6px 0",
});
globalStyle(`${appFold} > summary::-webkit-details-marker`, { display: "none" });
globalStyle(`${appFold} > summary::before`, {
  content: "\"›\"", color: vars.muted, transition: `transform 160ms ${vars.easeOut}`, display: "inline-block",
});
globalStyle(`${appFold}[open] > summary::before`, { transform: "rotate(90deg)" });
globalStyle(`${permGrid} input`, { accentColor: vars.accent, margin: "0" });
/** The permission that is always on: its tick where a box would be, not pressable. */
export const permFixed = style({ cursor: "default", selectors: { "&:hover": { background: "none" } } });
globalStyle(`${permFixed} svg`, { flex: "none", color: vars.accent });
