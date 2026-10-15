import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { segmentedThumb } from "../ui.css.ts";
import { inner as innerCorner } from "../styles/align.ts";

// The station's mark before its name: a square the size of a line, dashed while it has none; a picture fills it.
export const slot = style({
  display: "inline-grid", placeItems: "center", flex: "none", width: "28px", height: "28px", padding: "0", overflow: "hidden",
  border: `1px dashed ${vars.lineStrong}`, borderRadius: vars.rOption, background: "none", color: vars.muted,
  cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&[data-set]": { borderStyle: "solid", borderColor: vars.line, color: vars.text },
    "&[data-picture]": { border: "0" },
    "&:hover": { borderColor: vars.fieldHover, color: vars.text },
    "&:focus-visible": { outline: `2px solid var(--focus, ${vars.accent})`, outlineOffset: "2px" },
    "&:disabled": { cursor: "default" },
  },
});
/** The square heading a page: filled with the cards' ground, its letter large and muted while it has no mark. */
export const large = style({
  display: "inline-grid", placeItems: "center", flex: "none", width: "56px", height: "56px", padding: "0", overflow: "hidden",
  border: "0", borderRadius: `calc(16px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: `color-mix(in oklab, ${vars.text} 6%, ${vars.canvas})`, color: vars.muted, fontSize: vars.textHeading, fontWeight: "600",
  selectors: {
    "&[data-set]": { color: vars.text },
    "&[data-picture]": { background: "none" },
    "button&": { cursor: "pointer", transition: `box-shadow ${vars.dur} ${vars.easeOut}` },
    "button&:hover": { boxShadow: `inset 0 0 0 1.5px ${vars.fieldHover}` },
    "&:focus-visible": { outline: `2px solid var(--focus, ${vars.accent})`, outlineOffset: "2px" },
    "&:disabled": { cursor: "default" },
  },
});
globalStyle(`${large}[data-picture] img`, { borderRadius: 0 });
/** Only what it has, for those who may not change it. */
export const shown = style({ display: "grid", flex: "none" });
/** The panel: a panel's room (12); whatever sits in a corner is as round as the panel's corner less its padding. */
export const pick = style({ width: "300px" });
export const panel = style({ display: "flex", flexDirection: "column", gap: "6px" });
const inner = innerCorner;
// Not pills: a pill's round end beside the panel's squarer corner leaves a crescent between them. The switch and the
// field take the corner's own shape, less the padding; the switch's thumb, less its own.
export const kinds = style({ alignSelf: "stretch", borderRadius: inner, cornerShape: vars.cornerShape });
globalStyle(`${kinds} ${segmentedThumb}`, { borderRadius: `calc(${inner} - 3px)`, cornerShape: vars.cornerShape });
export const field = style({ width: "100%", height: "32px" });
// A field's line, on the glass itself: a white field on it stood out in light, and with no line it read as no field. The
// settings' dark focus line is too heavy here: hover and focus take the hover's.
globalStyle(`input${field}${field}`, { borderRadius: inner, cornerShape: vars.cornerShape, background: "transparent", borderColor: vars.lineStrong });
globalStyle(`input${field}${field}:hover, input${field}${field}:focus`, { borderColor: vars.fieldHover });
/** Eight to a row; more rows than the panel has room for scroll in it, under the switch and the colours. */
export const grid = style({ display: "grid", gridTemplateColumns: "repeat(8, 1fr)", gap: "2px", maxHeight: "288px", overflowY: "auto", overscrollBehavior: "contain", scrollbarWidth: "thin" });
/** Emoji are pictures: drawn a step above the title's size, as large as the icons look. */
export const emojiGrid = style({ fontSize: `calc(${vars.textTitle} * 1.25)`, lineHeight: "1" });
export const choice = style({
  aspectRatio: "1", display: "grid", placeItems: "center", padding: "0", border: "0",
  borderRadius: inner, background: "none", color: vars.muted, cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
    "&[aria-pressed=true]": { background: vars.hover, color: vars.accent },
    "&:focus-visible": { outline: `2px solid var(--focus, ${vars.accent})`, outlineOffset: "-2px" },
  },
});
// In a colour, every icon is that colour (the grid's), the one it has only on its ground.
globalStyle(`${grid}[data-color] > ${choice}${choice}`, { color: "inherit" });
/** No icon is found by what was typed. */
export const none = style({ margin: "0", padding: "18px 0", textAlign: "center", color: vars.muted, fontSize: vars.textUi });
/** The colours, in a row over the grid: a dot each, the one picked ringed in its own colour. The words' colour is the first. */
export const colors = style({ display: "flex", gap: "2px", padding: "2px 0" });
export const color = style({
  position: "relative", width: "24px", height: "24px", padding: "0", border: "0", borderRadius: "50%", background: "none", color: vars.text, cursor: "pointer",
  "::before": { content: "", position: "absolute", inset: "6px", borderRadius: "50%", background: "currentColor" },
  selectors: {
    "&[aria-pressed=true]": { boxShadow: "inset 0 0 0 2px currentColor" },
    "&:focus-visible": { outline: `2px solid var(--focus, ${vars.accent})`, outlineOffset: "1px" },
  },
});
/** Putting up a picture and having none, side by side under the grid, as a menu's rows. */
export const foot = style({ display: "flex", gap: "2px" });
export const footButton = style({
  width: "auto", flex: "1", justifyContent: "center", color: vars.muted, borderRadius: inner, cornerShape: vars.cornerShape,
  selectors: { "&:hover": { background: vars.hover, color: vars.text } },
});
/** The picture it has, in the button that puts up another. */
export const footPicture = style({ width: "18px", height: "18px", objectFit: "cover", borderRadius: "24%", cornerShape: vars.cornerShape });
export const failed = style({ padding: "0 10px 4px" });
