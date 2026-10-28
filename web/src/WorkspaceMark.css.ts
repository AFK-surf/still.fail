import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** A workspace with no mark of its own, before its name: its letter on a tile as the rail's (Rail.css.ts workspaceItem). */
export const letter = style({
  display: "inline-grid", placeItems: "center", flex: "none", lineHeight: "1", fontWeight: 600, color: vars.muted,
  background: vars.hover, borderRadius: `calc(4px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
});
/** Its mark and its name in a line, a little apart; the name cut short where the line is. */
export const named = style({ display: "inline-flex", alignItems: "center", gap: "0.4em", minWidth: 0, verticalAlign: "bottom" });
export const name = style({ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
