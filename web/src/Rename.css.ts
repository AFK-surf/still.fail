// A chat's name while it is being changed: the name stays where it was, in its own type, on a light field that fits
// it; a thin line round it says it is being typed in.
import { globalStyle, style } from "@vanilla-extract/css";
import { pageBarTitle } from "./styles/conversation.css.ts";
import { sessionPage } from "./styles/session.css.ts";
import { vars } from "./styles/tokens.css.ts";

export const titleInput = style({
  flex: 1, minWidth: 0, width: "100%", height: "24px", margin: "-2px -6px", padding: "0 6px", border: "0",
  borderRadius: `calc(6px * ${vars.cornerScale})`, background: vars.canvas, color: vars.text, font: "inherit", lineHeight: "24px",
  boxShadow: `inset 0 0 0 1px ${vars.lineStrong}`, cornerShape: vars.cornerShape, outline: "none",
  selectors: { "&::placeholder": { color: vars.subtle, fontWeight: 400 } },
});
/** In the chat page's bar: as wide as the name in it (the bar's own title, no wider than the title may be). */
export const titleInputBar = style({ height: "28px", lineHeight: "28px", fontSize: vars.textBody, fontWeight: 600 });
/** Over the bar's rule that what follows the title keeps its size: the field fits its text, and gives way to the marks after it. */
globalStyle(`${sessionPage} ${pageBarTitle} > ${titleInputBar}`, {
  flex: "0 1 auto", width: "auto", minWidth: "160px", maxWidth: "42vw", fieldSizing: "content", margin: "-3px -8px", padding: "0 8px",
} as never);
