import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** Under the rows where they cannot be pressed here (a web page): where to approve it, quiet. */
export const inApp = style({ margin: "6px 0 0", fontSize: vars.textMeta, lineHeight: "18px", color: vars.subtle });
