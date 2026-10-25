import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { composerWrap } from "./styles/cloud.css.ts";
import { composerBox } from "./styles/composer.css.ts";
import { glass } from "@stillfail/ui/styles/glass.ts";

export const newChatSub = style({
  textWrap: "balance", wordBreak: "keep-all", overflowWrap: "anywhere", margin: "0 0 8px", color: vars.muted,
  fontSize: vars.textUi, lineHeight: "20px",
});
export const spentNotice = style({
  margin: "0 0 8px", padding: "8px 12px", borderRadius: `calc(10px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: `color-mix(in srgb, ${vars.amber} 12%, transparent)`, color: vars.text, fontSize: vars.textUi,
});
/** New chat: a centred composer with the choices of where and on what it runs. */
export const newChat = style({
  flex: "1", minHeight: "0", display: "grid", placeItems: "center", padding: "32px", overflowY: "auto",
});
export const newChatInner = style({
  width: "100%", maxWidth: "720px", display: "grid", gap: "10px", justifyItems: "center", textAlign: "center",
});
/**
 * A page with its composer (NewChat.tsx): as tall as the page, the scene and the composer in its middle, what differs by
 * the station and what is picked on it under the composer, from its foot down, as much room under it as over the scene
 * (more where what is under needs it): it comes, goes and changes as another station is picked and moves nothing over it.
 */
export const newChatTall = style({
  alignSelf: "stretch", gridTemplateRows: "1fr auto auto 1fr", gridTemplateAreas: `"." "scene" "composer" "under"`,
});
export const newChatScene = style({ gridArea: "scene", display: "grid", gap: "10px", justifyItems: "center" });
export const newChatUnder = style({ gridArea: "under", alignSelf: "start", display: "grid", gap: "10px", justifyItems: "center", width: "100%" });
export const newChatTitle = style({ margin: "0", fontSize: vars.textHeading, lineHeight: "34px", fontWeight: "600" });
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
 * The composer, a new chat's (roomy) and a chat's (at its foot) alike, as the phone's capsule (the phone's mFloating):
 * frosted and raised, with no line round it, its glass and shadow the phone's; its send a dark disc.
 */
/** Here rather than with its class: it comes after .new-chat-held, and wins over it. */
globalStyle(composerBox, {
  border: "0", ...glass, boxShadow: "0 1px 3px rgb(0 0 0 / .04)",
});
/** The bar over a new chat (its 文件, where a chat's bar has it): over the page, taking none of its room or its pointer. */
export const newChatBar = style({ position: "absolute", top: "0", left: "0", right: "0", zIndex: 1, pointerEvents: "none" });
globalStyle(`${newChatBar} > *`, { pointerEvents: "auto" });
