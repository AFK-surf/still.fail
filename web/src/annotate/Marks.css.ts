import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { popKeyframes } from "../styles/keyframes.css.ts";
import { iconBtn } from "../styles/pages.css.ts";
import { previewBar } from "../Preview.css.ts";

/** Frosted, as the composer is. */
const glass = {
  background: `color-mix(in srgb, ${vars.raised} 72%, transparent)`, WebkitBackdropFilter: "blur(20px) saturate(1.4)",
  backdropFilter: "blur(20px) saturate(1.4)", boxShadow: `0 1px 3px rgb(0 0 0 / .06), 0 6px 20px ${vars.shadow}`,
} as const;

/** Over the page, as big as it: the marks, following it. Only the pins and bubbles take the pointer. */
export const layer = style({ position: "absolute", inset: "0", overflow: "hidden", pointerEvents: "none" });

/** The element marked: a thin line round it, stronger while its bubble is open. */
export const outline = style({
  position: "absolute", boxSizing: "border-box", borderRadius: "4px",
  boxShadow: `0 0 0 1.5px color-mix(in srgb, ${vars.accent} 55%, transparent)`,
  transition: `box-shadow ${vars.dur} ${vars.easeOut}, background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&[data-open]": { boxShadow: `0 0 0 2px ${vars.accent}`, background: `color-mix(in srgb, ${vars.accent} 8%, transparent)` },
  },
});

/** Its number, in a pin whose point is on the element's top-left corner. */
export const pin = style({
  position: "absolute", transform: "translate(-2px, -22px)", transformOrigin: "2px 22px", pointerEvents: "auto", width: "24px",
  height: "24px", display: "grid", placeItems: "center", padding: "0", border: "2px solid #fff", borderRadius: "12px 12px 12px 3px",
  background: vars.accent, color: "#fff", fontSize: vars.textCaption, fontWeight: "650", fontVariantNumeric: "tabular-nums",
  boxShadow: "0 2px 6px rgb(0 0 0 / .22)", cursor: "pointer", animation: `${popKeyframes} 160ms ${vars.easeOut}`,
  transition: `transform ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover, &[data-open]": { transform: "translate(-2px, -22px) scale(1.12)" },
  },
});

/** What was said about it, one line beside the pin; a click opens it again. */
export const said = style({
  ...glass, position: "absolute", pointerEvents: "auto", height: "26px", padding: "0 10px", border: "0",
  borderRadius: "13px", color: vars.text, font: "inherit", fontSize: vars.textLabel, lineHeight: "26px", whiteSpace: "nowrap",
  overflow: "hidden", textOverflow: "ellipsis", cursor: "pointer", boxSizing: "border-box",
  animation: `${popKeyframes} 140ms ${vars.easeOut}`,
});

/** Saying something about it, beside the pin. */
export const note = style({
  ...glass, position: "absolute", pointerEvents: "auto", width: "280px", height: "36px", display: "flex",
  alignItems: "center", gap: "6px", padding: "0 4px 0 12px", boxSizing: "border-box", borderRadius: "18px",
  animation: `${popKeyframes} 140ms ${vars.easeOut}`,
});
export const noteInput = style({
  flex: "1", minWidth: "0", border: "0", padding: "0", background: "none", color: vars.text, font: "inherit",
  fontSize: vars.textSecondary,
  selectors: { "&:focus": { outline: "none" }, "&::placeholder": { color: vars.muted } },
});
export const noteKey = style({ flex: "none", color: vars.muted, fontSize: vars.textLabel, opacity: ".7" });
export const noteRemove = style({
  flex: "none", width: "28px", height: "28px", display: "grid", placeItems: "center", border: "0", borderRadius: "14px",
  background: "none", color: vars.muted, cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover, color: vars.red } },
});

/** In the bar, in the address's place while marking: what to do or how many, and putting them into the chat. */
export const mode = style({
  flex: "1", minWidth: "0", display: "flex", alignItems: "center", gap: "8px", height: "30px", margin: "0 4px",
  padding: "0 3px 0 12px", borderRadius: "999px", background: `color-mix(in srgb, ${vars.accent} 10%, ${vars.neutralBg})`,
  fontSize: vars.textSecondary, color: vars.text, whiteSpace: "nowrap",
});
export const modeDot = style({
  flex: "none", width: "7px", height: "7px", borderRadius: "50%", background: vars.muted,
  selectors: { "&[data-on]": { background: vars.accent, boxShadow: `0 0 0 3px color-mix(in srgb, ${vars.accent} 22%, transparent)` } },
});
export const modeText = style({ flex: "1", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", fontWeight: "500" });
globalStyle(`${modeText} > span`, { marginLeft: "8px", color: vars.muted, fontWeight: "400" });
export const modeError = style({ flex: "1", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", color: vars.red });
export const modeBtn = style({
  flex: "none", width: "24px", height: "24px", display: "grid", placeItems: "center", border: "0", borderRadius: "12px",
  background: "none", color: vars.muted, cursor: "pointer",
  selectors: { "&:hover:not(:disabled)": { background: vars.hover, color: vars.text } },
});
export const modeSend = style({
  flex: "none", display: "inline-flex", alignItems: "center", gap: "5px", height: "24px", padding: "0 10px",
  border: "0", borderRadius: "12px", background: vars.primary, color: vars.onPrimary, font: "inherit",
  fontSize: vars.textLabel, fontWeight: "500", cursor: "pointer",
  selectors: {
    "&:hover:not(:disabled)": { background: vars.primaryHover },
    "&:disabled": { opacity: ".4", cursor: "default" },
  },
});

/** The bar's 标注 while marking. */
globalStyle(`${previewBar} ${iconBtn}[aria-pressed="true"]`, { background: `color-mix(in srgb, ${vars.accent} 14%, transparent)`, color: vars.accentText });
