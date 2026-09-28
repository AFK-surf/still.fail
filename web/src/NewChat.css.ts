import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { composerWrap } from "./styles/cloud.css.ts";
import { composerBox } from "./styles/composer.css.ts";

export const newChatSub = style({
  textWrap: "balance", wordBreak: "keep-all", overflowWrap: "anywhere", margin: "0 0 8px", color: vars.muted,
  fontSize: vars.textSm,
});
export const spentNotice = style({
  margin: "0 0 8px", padding: "8px 12px", borderRadius: "10px",
  background: `color-mix(in oklch, ${vars.amber} 12%, transparent)`, color: vars.text, fontSize: vars.textSm,
});
/** New chat: a centred composer with the choices of where and on what it runs. */
export const newChat = style({
  flex: "1", minHeight: "0", display: "grid", placeItems: "center", padding: "32px", overflowY: "auto",
});
export const newChatInner = style({
  width: "100%", maxWidth: "720px", display: "grid", gap: "10px", justifyItems: "center", textAlign: "center",
});
export const newChatTitle = style({ margin: "0", fontSize: vars.textLg, fontWeight: "600" });
export const newChatStatus = style({});
export const newChatHeld = style({ border: `1px solid ${vars.line}` });
/** Here rather than with its class: it comes after .new-chat-held, and wins over it. */
globalStyle(composerBox, {
  display: "flex", alignItems: "flex-end", gap: "8px", padding: "6px 6px 6px 12px",
  border: `1px solid ${vars.lineStrong}`, borderRadius: "999px", background: vars.canvas, cursor: "text",
  transition: `border-radius ${vars.dur} ${vars.easeOut}`,
});
/** Centred, except what one writes in: the composer keeps the full width and its text starts on the left. */
globalStyle(`${newChatInner} > ${composerWrap}, ${newChatInner} > form`, { justifySelf: "stretch", textAlign: "left" });
/**
 * The composer, a new chat's (roomy) and a chat's (at its foot) alike, as the phone's capsule (the phone's mFloating):
 * frosted and raised, with no line round it; its send a dark disc. Thinner and less blurred than the phone's: over a white
 * page and thin text, more of either showed as plain white.
 */
/** Here rather than with its class: it comes after .new-chat-held, and wins over it. */
globalStyle(composerBox, {
  border: "0", background: `color-mix(in oklch, ${vars.canvas} 45%, transparent)`, WebkitBackdropFilter: "blur(10px)",
  backdropFilter: "blur(10px)", boxShadow: "0 6px 16px rgb(0 0 0 / .14), 0 2px 5px rgb(0 0 0 / .1)",
});
