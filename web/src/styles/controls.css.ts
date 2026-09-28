import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";
import { popKeyframes } from "./keyframes.css.ts";
import { inputRow } from "./additions.css.ts";
import { command, field, skeletonRow } from "../ui.css.ts";
import { newChatStatus } from "../NewChat.css.ts";
import { signIn } from "../pages/Accounts.css.ts";
import { stepActions } from "../pages/Connect.css.ts";

export const btn = style({
  display: "inline-flex", alignItems: "center", justifyContent: "center", gap: "6px", height: "32px",
  padding: "0 16px", borderRadius: "999px", border: `1px solid ${vars.lineStrong}`, background: vars.canvas,
  color: vars.text, fontSize: vars.textSm, fontWeight: "500", whiteSpace: "nowrap", cursor: "pointer",
  transition: `background ${vars.dur} ${vars.easeOut}, border-color ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover:not(:disabled)": { background: vars.hover },
    "&:disabled": { opacity: ".45", cursor: "default" },
    "&[aria-busy=\"true\"]": { cursor: "progress" },
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
    "&:hover:not(:disabled)": { background: `color-mix(in oklch, ${vars.red} 85%, black)` },
  },
});
export const textToggle = style({
  display: "inline-flex", alignItems: "center", gap: "2px", border: "0", background: "none", padding: "2px 4px",
  color: vars.muted, fontSize: vars.textXs, cursor: "pointer",
  selectors: {
    "&:hover": { color: vars.text },
  },
});
export const cardFoot = style({ margin: "0", fontSize: vars.textXs });
export const fieldError = style({ fontSize: vars.textXs, color: vars.red, margin: "0" });
export const input = style({
  width: "100%", minHeight: "36px", padding: "7px 12px", border: `1px solid ${vars.lineStrong}`,
  borderRadius: vars.rField, background: vars.canvas, fontSize: vars.textSm,
  transition: `border-color ${vars.dur} ${vars.easeOut}`, cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { borderColor: vars.fieldHover },
    "&:focus": { outline: "none", borderColor: vars.fieldFocus },
    [`${field}[data-invalid] &`]: { borderColor: vars.red },
    "&::placeholder": { color: vars.subtle },
    [`${inputRow} &`]: { flex: "1" },
  },
});
export const popover = style({
  zIndex: "60", padding: "6px", border: `1px solid ${vars.line}`, borderRadius: vars.rMenu, background: vars.canvas,
  boxShadow: `0 12px 32px ${vars.shadow}`, transformOrigin: "var(--radix-popper-transform-origin, top)",
  animation: `${popKeyframes} 140ms ${vars.easeOut}`, cornerShape: vars.cornerShape,
});
export const menuList = style({ minWidth: "180px" });
export const menuItem = style({
  display: "flex", alignItems: "center", gap: "8px", width: "100%", minHeight: "34px", padding: "7px 10px",
  border: "0", borderRadius: vars.rOption, background: "none", textAlign: "left", fontSize: vars.textSm,
  cursor: "pointer", outline: "none", userSelect: "none", cornerShape: vars.cornerShape,
  selectors: {
    "&[data-highlighted]": { background: vars.hover },
    "&[data-disabled]": { color: vars.subtle, cursor: "default" },
    "&[data-danger]": { color: vars.red },
  },
});
export const menuSep = style({ height: "1px", margin: "6px 4px", background: vars.line });
export const menuLabel = style({ padding: "6px 10px 4px", fontSize: vars.textXs, color: vars.muted });
export const steps = style({
  margin: "0", paddingLeft: "20px", display: "grid", gap: "8px", fontSize: vars.textSm,
  selectors: {
    [`${signIn} &`]: { gap: "14px" },
  },
});
export const verifyOk = style({
  display: "inline-flex", alignItems: "center", gap: "6px", color: vars.green, fontSize: vars.textSm,
});
globalStyle(`${menuItem} svg`, { color: vars.muted, flex: "none" });
globalStyle(`${menuItem}[data-disabled] svg`, { color: vars.subtle });
globalStyle(`${menuItem}[data-danger] svg`, { color: vars.red });
globalStyle(`${steps} li::marker`, { color: vars.muted });
globalStyle(`${steps} li:first-child`, { display: "list-item" });
globalStyle(`${steps} li:first-child ${btn}`, { marginTop: "6px", display: "flex", width: "max-content" });
globalStyle(`${steps} li > ${btn}, ${steps} li > ${inputRow}, ${steps} li > ${command}`, { marginTop: "8px" });
globalStyle(`${steps} li > ${btn}`, { display: "flex", width: "max-content" });
globalStyle(`${steps} ${stepActions}`, { display: "flex", flexWrap: "wrap", gap: "8px", marginTop: "8px" });
globalStyle(`${steps} li`, { minWidth: "0" });
globalStyle(`${steps} ${command}`, { width: "100%", minWidth: "0" });
/** Here rather than with its class: it comes after .steps li > .btn, and wins over it. */
globalStyle(`${skeletonRow} span:first-child`, { width: "80%" });
/** Here rather than with its class: it comes after .steps li > .btn, and wins over it. */
globalStyle(`${skeletonRow} span:last-child`, { width: "45%", height: "8px" });
/** Here rather than with its class: it comes after .field-error, and wins over it. */
globalStyle(newChatStatus, { minHeight: "1.5em", margin: "0", fontSize: vars.textXs, color: vars.muted });
