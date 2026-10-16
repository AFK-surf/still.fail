import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

/** How a station is reached (StationLink.tsx): never cut short, its name before it gives way instead. */
export const link = style({
  flex: "none", whiteSpace: "nowrap",
  selectors: {
    "&[data-level=amber]": { color: vars.amber },
    "&[data-level=red]": { color: vars.red },
  },
});
