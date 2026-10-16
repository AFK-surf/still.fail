// What every page has: its icon buttons (IconButton), its titled blocks (Section). Where the app's pages cascade, just
// before them (web/src/styles/index.ts).
import { style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";

export const iconBtn = style({
  display: "inline-grid", placeItems: "center", width: "32px", height: "32px", padding: "0", border: "0",
  borderRadius: `calc(12px * ${vars.cornerScale})`, background: "transparent", color: vars.muted, cursor: "pointer",
  flex: "none", transition: `background ${vars.dur} ${vars.easeOut}, color ${vars.dur} ${vars.easeOut}`,
  cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
    "&[aria-pressed=\"true\"]": { background: vars.selected, color: vars.text },
  },
});
export const section = style({ marginBottom: "28px" });
