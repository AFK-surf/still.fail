import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const mNote = style({
  padding: "8px 20px", fontSize: vars.textMeta, color: "var(--m-muted)",
  selectors: {
    "&[data-error]": { color: "var(--m-red)" },
  },
});
