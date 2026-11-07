import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";
import { litOver } from "./lit.ts";
import { panel, panelGround } from "./glass.ts";
import { popKeyframes } from "./keyframes.css.ts";
import { field } from "../parts.css.ts";
import { spinner } from "./spinner.css.ts";
import { PANEL_PAD, TEXT_IN, inner, surface } from "./align.ts";

/** How far in from its end a button's icon sits: the words' 16 less what its drawing leaves of its 16 box (about 3 on
 * still.fail's 24 grid), its ink as far in as the words (sf parts.mbt button, by each icon's own ink). */
const BUTTON_ICON_IN = 13;
export const btn = style({
  display: "inline-flex", alignItems: "center", justifyContent: "center", gap: "6px", height: "36px",
  padding: "0 16px", borderRadius: "999px", border: `1px solid ${vars.lineStrong}`, background: vars.canvas,
  color: vars.text, fontSize: vars.textUi, fontWeight: "500", whiteSpace: "nowrap", cursor: "pointer",
  transition: `background ${vars.dur} ${vars.easeOut}, border-color ${vars.dur} ${vars.easeOut}`,
  selectors: {
    // Its canvas kept under the ink (lit.ts): on a card's grey it is the button it was, a step on.
    "&:hover:not(:disabled)": litOver,
    "&:disabled": { opacity: ".45", cursor: "default" },
    "&[aria-busy=\"true\"]": { cursor: "progress", opacity: ".7" },
    // An icon before the words sits in by less than they do from the other end (BUTTON_ICON_IN): its drawing stops short
    // of its box, so the even padding left it looking farther from its edge.
    "&:has(> svg:first-child)": { paddingLeft: `${BUTTON_ICON_IN}px` },
  },
});
export const btnPrimary = style({
  background: vars.primary, borderColor: vars.primary, color: vars.onPrimary,
  selectors: {
    "&:hover:not(:disabled)": { background: vars.primaryHover, borderColor: vars.primaryHover },
  },
});
export const btnGhost = style({ borderColor: "transparent", background: "transparent" });
// Here, after btn, as the other variants: in ui.css.ts (which cascades before this file) btn's colour won over them.
export const btnDanger = style({ color: vars.red });
export const btnDangerSolid = style({
  // (what is said on it in the primary's: white on the light theme's deep red, the page's ink on the dark one's light
  // red, white on which was 2.5:1)
  background: vars.red, borderColor: vars.red, color: vars.onPrimary,
  selectors: {
    // A solid ground pointed at: a step towards the page, as the primary's (docs/ui-panels.md 悬停).
    "&:hover:not(:disabled)": { background: `color-mix(in srgb, ${vars.red} 85%, ${vars.canvas})` },
  },
});
/** A solid button's call under way: the ring where its icon goes (14, as everywhere) in its text's colour. */
globalStyle(`:is(${btnPrimary}, ${btnDangerSolid}) ${spinner}`, {
  borderColor: "color-mix(in srgb, currentColor 30%, transparent)", borderTopColor: "currentColor",
});
export const cardFoot = style({ margin: "0", fontSize: vars.textMeta });
export const fieldError = style({ fontSize: vars.textMeta, color: vars.red, margin: "0" });
export const input = style({
  width: "100%", minHeight: "36px", padding: "7px 12px", border: `1px solid ${vars.lineStrong}`,
  borderRadius: vars.rField, background: vars.canvas, fontSize: vars.textInput,
  transition: `border-color ${vars.dur} ${vars.easeOut}`, cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { borderColor: vars.fieldHover },
    // A light line that darkens a step when written in, as on hover: a near-black one read as a frame round the field.
    "&:focus": { outline: "none", borderColor: vars.fieldHover },
    [`${field}[data-invalid] &`]: { borderColor: vars.red },
    "&::placeholder": { color: vars.subtle },
  },
});
/** A one-line field is a pill, as the buttons beside it are; a textarea keeps --r-field (its lines in a pill would not sit right). */
globalStyle(`input${input}`, { borderRadius: "999px", paddingLeft: "16px", paddingRight: "16px", cornerShape: "round" });
/**
 * Every small panel (docs/ui-panels.md): menus, selects, popovers, hover cards, the station's cards. One ground, padded
 * PANEL_PAD (6) as far as what has a ground of its own (rows, buttons) stands from its edge, its corner what sits in it
 * (`--panel-in`) and that together. A panel of words (`panelCard`) gives them room of their own; a list's rows carry theirs.
 */
export const popover = style({
  ...surface(PANEL_PAD, `calc(${vars.rMenu} - ${PANEL_PAD}px)`, vars.cornerShape),
  zIndex: "60", ...panel,
  boxShadow: `0 12px 32px ${vars.shadow}`, transformOrigin: "var(--radix-popper-transform-origin, top)",
  animation: `${popKeyframes} 140ms ${vars.easeOut}`, cornerShape: vars.cornerShape,
});
// What stands on it is ringed in its ground (`--ring`: an agent's badge, a station's dot), not the page's.
globalStyle(popover, { vars: { "--ring": panelGround } });
export const menuList = style({ minWidth: "180px" });
export const menuItem = style({
  display: "flex", alignItems: "center", gap: "8px", width: "100%", minHeight: "34px", padding: `7px ${TEXT_IN}px`, lineHeight: "20px",
  border: "0", borderRadius: inner, background: "none", textAlign: "left", fontSize: vars.textUi,
  cursor: "pointer", outline: "none", userSelect: "none", cornerShape: vars.cornerShape,
  selectors: {
    "&[data-highlighted]": { background: vars.hover },
    "&[data-disabled]": { color: vars.subtle, cursor: "default" },
    "&[data-danger]": { color: vars.red },
  },
});
/** The chosen one of a menu's choices: a check at its row's end. */
export const menuCheck = style({ display: "inline-flex", flex: "none", width: "14px", marginLeft: "auto" });
/** What a choice of a menu means, quieter, at its row's end before its check (a pointer's pick: the app's @sf.pick). */
export const menuNote = style({ marginLeft: "auto", paddingLeft: "16px", fontSize: vars.textMeta, color: vars.muted, whiteSpace: "nowrap" });
globalStyle(`${menuNote} + ${menuCheck}`, { marginLeft: "0" });
// A tint of the text rather than the page's line: in dark the panel is lighter than the page, and the line would read
// as a dark groove on it.
export const menuSep = style({ height: "1px", margin: "6px 4px", background: `color-mix(in srgb, ${vars.text} 12%, transparent)` });
export const menuLabel = style({ padding: `6px ${TEXT_IN}px 4px`, fontSize: vars.textMeta, color: vars.muted });
globalStyle(`${menuItem} svg`, { color: vars.muted, flex: "none" });
globalStyle(`${menuItem}[data-disabled] svg`, { color: vars.subtle });
globalStyle(`${menuItem}[data-danger] svg`, { color: vars.red });
