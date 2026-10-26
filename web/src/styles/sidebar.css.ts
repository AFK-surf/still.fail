import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** 44px above where its line was (it has none now): a 32px button in it sits on whole pixels. */
export const pageBar = style({
  display: "grid", gridTemplateColumns: "1fr auto 1fr", alignItems: "center", height: "45px", padding: "0 12px 1px",
  "@media": {
    "(max-width: 700px)": {
      gridTemplateColumns: "auto minmax(0, 1fr) auto", gap: "8px",
    },
    "(min-width: 701px)": {
      selectors: {
        "[data-sidebar=\"closed\"] &": { paddingLeft: "52px" },
      },
    },
  },
});
