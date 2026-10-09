import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { segmentedThumb } from "../ui.css.ts";

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
/** Only what it has, for those who may not change it. */
export const shown = style({ display: "grid", flex: "none" });
/** The panel: a menu's; whatever sits in a corner is as round as the panel's corner less its padding. */
export const pick = style({ width: "300px" });
export const panel = style({ display: "flex", flexDirection: "column", gap: "6px" });
const inner = `calc(${vars.rMenu} - 6px)`;
// Not pills: a pill's round end beside the panel's squarer corner leaves a crescent between them. The switch and the
// field take the corner's own shape, less the padding; the switch's thumb, less its own.
export const kinds = style({ alignSelf: "stretch", borderRadius: inner, cornerShape: vars.cornerShape });
globalStyle(`${kinds} ${segmentedThumb}`, { borderRadius: `calc(${inner} - 3px)`, cornerShape: vars.cornerShape });
export const field = style({ width: "100%", height: "32px" });
// Sunk into the panel as the switch's track is (its tint, no line): a white field on the glass stood out in light.
globalStyle(`input${field}${field}`, {
  borderRadius: inner, cornerShape: vars.cornerShape, border: "0", background: `color-mix(in srgb, ${vars.text} 6%, transparent)`,
});
export const grid = style({ display: "grid", gridTemplateColumns: "repeat(8, 1fr)", gap: "2px" });
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
/** Putting up a picture and having none, side by side under the grid, as a menu's rows. */
export const foot = style({ display: "flex", gap: "2px" });
export const footButton = style({
  width: "auto", flex: "1", justifyContent: "center", color: vars.muted, borderRadius: inner,
  selectors: { "&:hover": { background: vars.hover, color: vars.text } },
});
/** The picture it has, in the button that puts up another. */
export const footPicture = style({ width: "18px", height: "18px", objectFit: "cover", borderRadius: "24%", cornerShape: vars.cornerShape });
export const failed = style({ padding: "0 10px 4px" });
