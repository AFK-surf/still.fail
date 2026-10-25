import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";
import { litOver } from "./lit.ts";
import { panel, panelGround } from "./glass.ts";
import { popKeyframes } from "./keyframes.css.ts";
import { command, field } from "../parts.css.ts";
import { spinner } from "./spinner.css.ts";
import { PANEL_PAD, TEXT_IN, inner, surface } from "./align.ts";

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
  background: vars.red, borderColor: vars.red, color: "#fff",
  selectors: {
    // A solid ground pointed at: a step towards the page, as the primary's (docs/ui-panels.md 悬停).
    "&:hover:not(:disabled)": { background: `color-mix(in srgb, ${vars.red} 85%, ${vars.canvas})` },
  },
});
/** A solid button's call under way: the ring where its icon goes (14, as everywhere) in its text's colour. */
globalStyle(`:is(${btnPrimary}, ${btnDangerSolid}) ${spinner}`, {
  borderColor: "color-mix(in srgb, currentColor 30%, transparent)", borderTopColor: "currentColor",
});
export const textToggle = style({
  display: "inline-flex", alignItems: "center", gap: "2px", border: "0", background: "none", padding: "2px 4px",
  color: vars.muted, fontSize: vars.textMeta, lineHeight: "18px", cursor: "pointer",
  selectors: {
    "&:hover": { color: vars.text },
  },
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
/**
 * A small panel of words (a card): each block in it stands in by a row's padding (TEXT_IN), and as much above the first
 * and under the last: its words as far from every edge (PANEL_PAD + TEXT_IN), on the line a list's rows' words are. What
 * sits at the panel's padding instead (a row, a group of rows, a foot of buttons) is marked `panelEdge`.
 */
export const panelCard = style({ vars: { "--panel-kind": "card" } });
export const panelEdge = style({});
globalStyle(`${panelCard} > :not(${panelEdge})`, { paddingInline: `${TEXT_IN}px` });
globalStyle(`${panelCard} > :first-child:not(${panelEdge})`, { paddingTop: `${TEXT_IN}px` });
globalStyle(`${panelCard} > :last-child:not(${panelEdge})`, { paddingBottom: `${TEXT_IN}px` });
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
export const steps = style({ margin: "0", paddingLeft: "20px", display: "grid", gap: "8px", fontSize: vars.textUi });
export const verifyOk = style({
  display: "inline-flex", alignItems: "center", gap: "6px", color: vars.green, fontSize: vars.textUi,
});
globalStyle(`${menuItem} svg`, { color: vars.muted, flex: "none" });
globalStyle(`${menuItem}[data-disabled] svg`, { color: vars.subtle });
globalStyle(`${menuItem}[data-danger] svg`, { color: vars.red });
globalStyle(`${steps} li::marker`, { color: vars.muted });
globalStyle(`${steps} li:first-child`, { display: "list-item" });
globalStyle(`${steps} li:first-child ${btn}`, { marginTop: "6px", display: "flex", width: "max-content" });
globalStyle(`${steps} li > ${btn}, ${steps} li > ${command}`, { marginTop: "8px" });
globalStyle(`${steps} li > ${btn}`, { display: "flex", width: "max-content" });
globalStyle(`${steps} li`, { minWidth: "0" });
globalStyle(`${steps} ${command}`, { width: "100%", minWidth: "0" });

/** A choice that opens a menu of what it can be (Chooser): quiet words until pointed at or open. */
export const chooser = style({
  display: "inline-flex", alignItems: "center", gap: "5px", height: "28px", padding: "0 8px", border: "0",
  borderRadius: `calc(8px * ${vars.cornerScale})`, background: "none", color: vars.muted, font: "inherit",
  fontSize: vars.textMeta, cursor: "pointer", whiteSpace: "nowrap", cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
    "&[data-state=\"open\"]": { background: vars.hover, color: vars.text },
    "a&": { textDecoration: "none", color: vars.accentText },
  },
});
export const chooserMenu = style({});
export const chooserItem = style({ display: "flex", alignItems: "center", gap: "6px" });
export const chooserCheck = style({});
/** A check at its row's end (ChooserItem `checkEnd`): pushed there. */
export const chooserCheckEnd = style({ marginLeft: "auto" });
export const chooserChevron = style({});
globalStyle(chooserCheck, { width: "14px", display: "inline-grid", placeItems: "center", flex: "none" });
globalStyle(chooserMenu, { maxHeight: "360px", overflowY: "auto", minWidth: "220px" });
