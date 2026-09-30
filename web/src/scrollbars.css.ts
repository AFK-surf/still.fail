import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

/** No z-index: layered by where it is (beside its pane), over the pane, under what comes after it (menus, dialogs). */
export const floatingThumb = style({
  position: "fixed", left: "0", top: "0", width: "3px", height: "3px", borderRadius: "999px",
  background: `color-mix(in srgb, ${vars.text} 26%, transparent)`, opacity: "0", pointerEvents: "none",
  transition: `opacity 200ms ${vars.easeOut}, background-color 120ms ${vars.easeOut}`,
  selectors: {
    "&[data-on]": { opacity: "1", pointerEvents: "auto" },
    // Easier to catch than it looks: a wider invisible edge around it.
    "&::before": { content: "\"\"", position: "absolute", inset: "-4px" },
    "&:hover": { background: `color-mix(in srgb, ${vars.text} 45%, transparent)` },
    "&[data-drag]": { background: `color-mix(in srgb, ${vars.text} 45%, transparent)` },
  },
});
