import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { msgSendingShowKeyframes } from "@stillfail/ui/styles/keyframes.css.ts";
import { msg, msgBubble } from "./conversation.css.ts";
import { quotaChips } from "../components.css.ts";
import { runCardRow } from "../pages/Connect.css.ts";
import { avatar } from "@stillfail/ui/parts.css.ts";
import { chooserItem } from "@stillfail/ui/styles/controls.css.ts";

/** A message on its way says so only if it takes a moment. */
export const msgSending = style({ animation: `${msgSendingShowKeyframes} 0s 0.8s both` });
export const msgMine = style({ display: "grid", justifyItems: "end", gap: "4px" });
export const msgAvatar = style({
  selectors: {
    [`${msg}[data-covered] > &`]: { visibility: "hidden" },
  },
});
export const msgPlain = style({
  whiteSpace: "pre-wrap", overflowWrap: "anywhere", fontFamily: vars.fontText, fontVariantNumeric: "normal", fontSize: vars.textBody, lineHeight: "1.55",
});
export const msgWaiting = style({ display: "inline-flex", alignItems: "center", gap: "5px" });
/** A profile's model pool: a checklist of what it may be used for. */
export const modelPool = style({ display: "grid", gap: "8px" });
export const modelPoolTools = style({ display: "flex", alignItems: "center", gap: "12px" });
export const modelPoolList = style({});
export const modelPoolItem = style({
  display: "flex", alignItems: "center", gap: "8px", height: "30px", padding: "0 8px",
  borderRadius: `calc(8px * ${vars.cornerScale})`, fontSize: vars.textUi, color: vars.muted, cursor: "pointer",
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
/** What the option chosen above it does (Appearance.tsx ArchiveSetting): as a section's words, under its control. */
/** Under a station's name in 设置 › 归档 (pages/Archiving.tsx): how it archives; red where it is set to and cannot. */
export const archivingNote = style({
  fontSize: vars.textMeta, color: vars.muted,
  selectors: { "&[data-bad]": { color: vars.red } },
});
export const appearanceHint = style({ margin: "8px 0 0", fontSize: vars.textMeta, color: vars.muted, maxWidth: "52em" });
export const textButton = style({
  padding: "0", border: "0", background: "none", color: vars.text, font: "inherit", textDecoration: "underline",
  textUnderlineOffset: "2px", cursor: "pointer",
  selectors: {
    [`${runCardRow} > &`]: { flex: "none", fontSize: vars.textUi, color: vars.muted },
  },
});
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
globalStyle(`${msgAvatar} ${avatar}`, { borderRadius: "50% !important", cornerShape: "round" });
