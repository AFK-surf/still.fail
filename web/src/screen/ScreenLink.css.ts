import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { MESSAGE_FILE_CORNER } from "../Chat.css.ts";

/** A screen's card in a message: a file's (Chat.css.ts fileCard), over a message's own link colours (styles/conversation.css.ts). */
export const screenCard = style({
  selectors: {
    "&&": { color: vars.text, textDecoration: "none" },
  },
});
/** One its station no longer has: its words as quiet as its line. */
globalStyle(`${screenCard}[data-gone] [data-card]`, { color: vars.muted });
export const screenCardLine = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });

/** A card with the screen live in it: the picture 4px in from its top and sides, its corners concentric with the
 * card's (mbui's peek_card), the words under it where a card's are. */
const PEEK_IN = 4;
export const peekCard = style({
  selectors: {
    "&&": {
      display: "inline-flex", flexDirection: "column", alignItems: "stretch", gap: "0", width: "280px",
      padding: `${PEEK_IN}px ${PEEK_IN}px 0`,
    },
  },
});
export const peek = style({
  position: "relative", display: "block", width: "100%", background: vars.hover, overflow: "hidden",
  borderRadius: `calc(${MESSAGE_FILE_CORNER} - ${PEEK_IN}px)`, cornerShape: vars.cornerShape,
});
export const peekPicture = style({
  position: "absolute", inset: "0", width: "100%", height: "100%", objectFit: "cover", objectPosition: "top", opacity: "0",
  selectors: { "&[data-drawn]": { opacity: "1" } },
});
/** Its mark in the middle until a picture comes. */
export const peekMark = style({ position: "absolute", inset: "0", display: "grid", placeItems: "center" });
export const peekText = style({ display: "flex", minWidth: "0", padding: `12px ${20 - PEEK_IN}px 16px` });

/** A station's 共享调试 card (AdbLink.tsx) while this phone is lent there: its phone in the accent. */
export const adbTile = style({ selectors: { "&[data-sharing]": { stroke: vars.accent } } });

/** A card with the way to open it beside the chat: the button at the end of its words, there while the card is pointed
 * at (always, where nothing points). */
export const cardWith = style({ position: "relative", display: "inline-flex", maxWidth: "100%" });
export const side = style({
  position: "absolute", bottom: "9px", right: "8px", display: "grid", placeItems: "center", width: "28px", height: "28px",
  padding: "0", border: "0", borderRadius: vars.rOption, cornerShape: vars.cornerShape, cursor: "pointer", opacity: "0",
  background: vars.raised, color: vars.text, boxShadow: `0 0 0 1px ${vars.line}`,
  transition: `opacity 120ms ${vars.easeOut}`,
  selectors: {
    [`${cardWith}:hover &, &:focus-visible`]: { opacity: "1" },
    "&:hover": { background: vars.hover },
  },
  "@media": { "(hover: none)": { opacity: "1" } },
});
globalStyle(`${cardWith} ${peekText}, ${cardWith} [data-card]:not(${peekCard})`, { paddingRight: "44px" });
