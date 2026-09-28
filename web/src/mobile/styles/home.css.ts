import { style } from "@vanilla-extract/css";

export const mNote = style({
  padding: "8px 20px", fontSize: "13px", color: "var(--m-muted)",
  selectors: {
    "&[data-error]": { color: "var(--m-red)" },
  },
});
