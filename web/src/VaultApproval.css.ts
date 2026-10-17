import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** On a web page, in place of the rows: where the request is approved, in the options' ground, even room all round. */
export const inClient = style({ gap: "2px", padding: "14px" });
export const inClientTitle = style({ fontSize: vars.textUi, lineHeight: "20px", fontWeight: "500", color: vars.text });
export const inClientDetail = style({ fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted });
