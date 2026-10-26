import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** In a line: as StatusDot is (ui.css.ts). */
export const dot = style({
  width: "7px", height: "7px", borderRadius: "50%", flex: "none",
  selectors: {
    "&[data-via=direct]": { background: vars.online },
    "&[data-via=relay]": { background: vars.amber },
    "&[data-via=offline]": { background: vars.red },
    "&[data-via=waiting]": { background: vars.muted },
  },
});

/** What carries a dot on its corner. */
export const corner = style({ position: "relative" });
/** On the bottom-right corner of what carries it (corner), ringed in the ground's colour, as an agent's badge is. */
export const cornerDot = style([dot, {
  position: "absolute", right: "-3px", bottom: "-3px", width: "10px", height: "10px", boxSizing: "border-box",
  border: `2px solid var(--ring, ${vars.canvas})`, pointerEvents: "none",
}]);
