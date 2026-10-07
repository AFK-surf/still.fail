import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { composerWrap } from "./styles/cloud.css.ts";
import { composerBox } from "./styles/composer.css.ts";
import { composerGround } from "./styles/glass.ts";

export const newChatSub = style({
  textWrap: "balance", wordBreak: "keep-all", overflowWrap: "anywhere", margin: "0 0 8px", color: vars.muted,
  fontSize: vars.textSm, lineHeight: "20px",
});
export const spentNotice = style({
  margin: "0 0 8px", padding: "8px 12px", borderRadius: "10px",
  background: `color-mix(in srgb, ${vars.amber} 12%, transparent)`, color: vars.text, fontSize: vars.textSm,
});
/** New chat: a centred composer with the choices of where and on what it runs. */
export const newChat = style({
  flex: "1", minHeight: "0", display: "grid", placeItems: "center", padding: "32px", overflowY: "auto",
});
export const newChatInner = style({
  width: "100%", maxWidth: "720px", display: "grid", gap: "10px", justifyItems: "center", textAlign: "center",
});
/** Where the offer of the machine's sessions hangs, under the status line: it takes no room (NewChat.tsx). */
export const newChatOffer = style({ position: "relative", height: "0", width: "100%" });
globalStyle(`${newChatOffer} > *`, { position: "absolute", top: "0", left: "50%", transform: "translateX(-50%)", whiteSpace: "nowrap" });
export const newChatTitle = style({ margin: "0", fontSize: vars.textLg, lineHeight: "34px", fontWeight: "600" });
export const newChatStatus = style({});
export const newChatHeld = style({ border: `1px solid ${vars.line}` });
/** Here rather than with its class: it comes after .new-chat-held, and wins over it. */
globalStyle(composerBox, {
  display: "flex", alignItems: "flex-end", gap: "8px", padding: "6px 6px 6px 12px",
  // Its corners go from capsule to box with its height (Chat.tsx's Composer), not on their own.
  border: `1px solid ${vars.lineStrong}`, borderRadius: "999px", background: vars.canvas, cursor: "text",
});
/** Centred, except what one writes in: the composer keeps the full width and its text starts on the left. */
globalStyle(`${newChatInner} > ${composerWrap}, ${newChatInner} > form`, { justifySelf: "stretch", textAlign: "left" });
/**
 * The composer, a new chat's (roomy) and a chat's (at its foot) alike, a capsule
 * laid on the pane: its surface, a hairline round it and a soft shadow (glass.ts composerGround); its send a dark disc.
 */
/** Here rather than with its class: it comes after .new-chat-held, and wins over it. */
globalStyle(composerBox, {
  border: "0", ...composerGround,
});
