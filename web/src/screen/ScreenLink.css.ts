import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { FILE_CARD_PAD } from "../Chat.css.ts";

/** A screen's card in a message: a file's (Chat.css.ts fileCard), over a message's own link colours (styles/conversation.css.ts). */
export const screenCard = style({
  selectors: {
    "&&": { color: vars.text, textDecoration: "none" },
  },
});
/** One its station no longer has: its words as quiet as its line. */
globalStyle(`${screenCard}[data-gone] [data-card]`, { color: vars.muted });
export const screenCardLine = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });

/** A card with the screen live in it: the picture across its top, edge to edge (the card's corners its), the words under it. */
export const peekCard = style({
  selectors: {
    "&&": { display: "inline-flex", flexDirection: "column", alignItems: "stretch", gap: "0", width: "280px", padding: "0", overflow: "hidden" },
  },
});
export const peek = style({ position: "relative", display: "block", width: "100%", background: vars.hover, overflow: "hidden" });
export const peekPicture = style({
  position: "absolute", inset: "0", width: "100%", height: "100%", objectFit: "cover", objectPosition: "top", opacity: "0",
  selectors: { "&[data-drawn]": { opacity: "1" } },
});
/** Its mark in the middle until a picture comes. */
export const peekMark = style({ position: "absolute", inset: "0", display: "grid", placeItems: "center" });
export const peekText = style({ display: "flex", minWidth: "0", padding: `${FILE_CARD_PAD.y}px 10px ${FILE_CARD_PAD.y}px ${FILE_CARD_PAD.x + 3}px` });
