// A chat's name while it is being changed: an input where the name was, as tall as the text it stands in for.
import { globalStyle, style } from "@vanilla-extract/css";
import { pageBarTitle } from "./styles/conversation.css.ts";
import { sessionPage } from "./styles/session.css.ts";
import { vars } from "./styles/tokens.css.ts";

export const titleInput = style({
  flex: 1, minWidth: 0, width: "100%", margin: "-2px -6px", padding: "1px 5px", border: `1px solid ${vars.fieldFocus}`,
  borderRadius: vars.rField, background: vars.canvas, color: vars.text, font: "inherit", lineHeight: "inherit",
  cornerShape: vars.cornerShape, outline: "none",
});
/** In the chat page's bar: as wide as the title can be there. */
export const titleInputBar = style({ fontSize: vars.textBody, fontWeight: 600 });
/** Over the bar's rule that what follows the title keeps its size: the field gives way to the marks after it. */
globalStyle(`${sessionPage} ${pageBarTitle} > ${titleInputBar}`, { flex: "0 1 420px", maxWidth: "42vw", margin: "-2px 0 -2px -6px" });
