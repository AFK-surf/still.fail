// Markdown's own parts that are not in app.css.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

/** A message's file placed in its text: on a line of its own, a little apart from the text around it. */
export const inlineFile = style({ display: "flex", margin: "8px 0" });
globalStyle(`${inlineFile}:first-child`, { marginTop: 0 });
globalStyle(`${inlineFile}:last-child`, { marginBottom: 0 });

/** A link within a sentence to one of the message's files: looks like any link, opens the file. */
export const fileLink = style({
  display: "inline", padding: 0, border: 0, background: "none", font: "inherit", color: vars.blue, cursor: "pointer", textAlign: "inherit",
});
