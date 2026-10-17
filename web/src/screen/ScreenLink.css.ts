import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** A screen's card in a message: a file's (Chat.css.ts fileCard), over a message's own link colours (styles/conversation.css.ts). */
export const screenCard = style({
  selectors: {
    "&&": { color: vars.text, textDecoration: "none" },
  },
});
/** One its station no longer has: its words as quiet as its line. */
globalStyle(`${screenCard}[data-gone] [data-card]`, { color: vars.muted });
export const screenCardLine = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
