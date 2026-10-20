// A station's grants on its page (StationPermissions.tsx): its software's rows' look (Versions.css.ts), nothing pressed
// on the row itself; grey but for what wants doing (a grant to ask for, one not given that the viewer may not ask for).
import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const row = style({ selectors: { "&:hover": { background: "none" } } });
export const mark = style({ width: "36px", height: "36px" });
export const name = style({ fontWeight: "500", color: vars.text });
export const line = style({
  color: vars.muted,
  selectors: { [`${row}[data-end=open] &, ${row}[data-end=waiting] &`]: { color: vars.text } },
});
/** Its state or its button, at the row's end. */
export const end = style({
  display: "inline-flex", alignItems: "center", flex: "none", fontSize: vars.textUi, color: vars.muted, whiteSpace: "nowrap",
  selectors: { [`${row}[data-end=missing] &`]: { color: vars.amber, fontWeight: "500" } },
});
