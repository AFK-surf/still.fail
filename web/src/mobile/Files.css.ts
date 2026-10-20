import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** A folder's mark, in the accent (dimmed with its station offline, as its row's words are). */
export const mFolder = style({
  display: "grid", placeItems: "center", flex: "none", color: "var(--m-accent)",
  selectors: { "&[data-off]": { opacity: ".45" } },
});
/** The station it is on, at the row's end. */
export const mWhere = style({
  flex: "none", fontSize: vars.textMeta, color: "var(--m-muted)",
  selectors: { "&[data-off]": { opacity: ".6" } },
});
export const mNone = style({ padding: "8px 24px", fontSize: vars.textMeta, color: "var(--m-muted)" });
