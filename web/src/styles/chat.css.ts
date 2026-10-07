import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";
import { msgSendingShowKeyframes } from "./keyframes.css.ts";
import { msg, msgBubble } from "./conversation.css.ts";
import { avatar } from "../ui.css.ts";
import { quotaChips } from "../components.css.ts";
import { runCardRow } from "../pages/Connect.css.ts";

/**
 * Holds the space of whatever left the bottom (see scroll.ts); the negative margin takes back its gap (the list's
 * `--list-gap`, when it is not the wide screen's 28px).
 */
export const chatFloor = style({ flex: "none", marginTop: "calc(-1 * var(--list-gap, 28px))", padding: "0" });
/** A message on its way says so only if it takes a moment. */
export const msgSending = style({ animation: `${msgSendingShowKeyframes} 0s 0.8s both` });
export const msgMine = style({ display: "grid", justifyItems: "end", gap: "4px" });
export const msgAvatar = style({
  selectors: {
    [`${msg}[data-covered] > &`]: { visibility: "hidden" },
  },
});
export const msgPlain = style({
  whiteSpace: "pre-wrap", overflowWrap: "anywhere", fontSize: vars.textSm, lineHeight: "1.55",
});
export const msgWaiting = style({ display: "inline-flex", alignItems: "center", gap: "5px" });
export const chooser = style({
  display: "inline-flex", alignItems: "center", gap: "5px", height: "28px", padding: "0 8px", border: "0",
  borderRadius: `calc(8px * ${vars.cornerScale})`, background: "none", color: vars.muted, font: "inherit",
  fontSize: vars.textXs, cursor: "pointer", whiteSpace: "nowrap", cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
    "&[data-state=\"open\"]": { background: vars.hover, color: vars.text },
    "a&": { textDecoration: "none", color: vars.accentText },
  },
});
export const chooserMenu = style({});
export const chooserItem = style({ display: "flex", alignItems: "center", gap: "6px" });
export const chooserCheck = style({});
/** A profile's model pool: a checklist of what it may be used for. */
export const modelPool = style({ display: "grid", gap: "8px" });
export const modelPoolTools = style({ display: "flex", alignItems: "center", gap: "12px" });
export const modelPoolList = style({});
export const modelPoolItem = style({
  display: "flex", alignItems: "center", gap: "8px", height: "30px", padding: "0 8px",
  borderRadius: `calc(8px * ${vars.cornerScale})`, fontSize: vars.textSm, color: vars.muted, cursor: "pointer",
  cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover },
    "&[data-on]": { color: vars.text },
  },
});
/** Hints that name another page link to it. */
export const inlineLink = style({
  color: vars.accentText, textDecoration: "underline",
  textDecorationColor: "color-mix(in srgb, currentColor 40%, transparent)", textUnderlineOffset: "2px",
  selectors: {
    "&:hover": { textDecorationColor: "currentColor" },
  },
});
export const appearanceSetting = style({});
export const textButton = style({
  padding: "0", border: "0", background: "none", color: vars.text, font: "inherit", textDecoration: "underline",
  textUnderlineOffset: "2px", cursor: "pointer",
  selectors: {
    [`${runCardRow} > &`]: { flex: "none", fontSize: vars.textSm, color: vars.muted },
  },
});
export const chooserChevron = style({});
/** A bot's picture, as Slack shows it: a rounded square. */
export const botAvatar = style({
  flex: "none", display: "block", borderRadius: `calc(22% * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  objectFit: "cover", background: vars.neutralBg,
});
globalStyle(`${chooserItem} ${quotaChips}`, { marginLeft: "12px" });
globalStyle(`${msgMine} ${msgBubble}`, {
  maxWidth: "min(78%, 560px)", padding: "8px 14px", borderRadius: `calc(18px * ${vars.cornerScale})`,
  background: vars.neutralBg, cornerShape: vars.cornerShape,
});
/**
 * On the wide screen, one's own bubble has a tail at its foot on the right, as a message app's (Cue's): drawn in the bubble's colour by a
 * mask of its shape, out past the bubble's corner.
 */
const tail = "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 14'%3E%3Cpath d='M21.8 0C20 1 19.8 6.4 23.5 12.5C24.3 13.7 23.6 13.9 21.4 13.7C14 13 9 4 0 4C0 4 13 .5 13 .5C15.5 1 21.8 0 21.8 0Z'/%3E%3C/svg%3E\")";
globalStyle(`${msgMine} ${msgBubble}`, { position: "relative" });
globalStyle(`${msgMine} ${msgBubble}::after`, {
  "@media": {
    // The wide screen's: the phone's chat keeps its own look.
    "(min-width: 701px)": {
      content: "\"\"", position: "absolute", right: "-6px", bottom: "0", width: "20px", height: "12px",
      background: "inherit", WebkitMask: `${tail} center / contain no-repeat`, mask: `${tail} center / contain no-repeat`,
      pointerEvents: "none",
    },
  },
});
globalStyle(`${msgAvatar} ${avatar}`, { borderRadius: "50% !important" });
