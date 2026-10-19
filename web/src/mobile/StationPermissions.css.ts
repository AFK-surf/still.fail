// A station's grants on the phone (StationPermissions.tsx): its software's rows' words (Versions.css.ts).
import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** What wants doing, at the row's end, in words. */
export const mAction = style({
  // The phone's buttons inherit font and colour (./styles/root.css.ts): its own are kept.
  flex: "none", padding: "0", border: "0", background: "none", fontSize: `${vars.textBody} !important`, fontWeight: "500 !important",
  color: "var(--m-accent) !important", cursor: "pointer", whiteSpace: "nowrap",
});
/** Its state: grey, but one not given that the viewer may not ask for. */
export const mState = style({
  flex: "none", fontSize: vars.textMeta, color: "var(--m-muted)", whiteSpace: "nowrap",
  selectors: { "&[data-end=missing]": { color: "var(--m-warn)", fontWeight: "500" } },
});
/** What is unavailable now, under the card. */
/** A grant's line, whole (how one asked for is given at the Mac is not cut short): the ink while its window is up. */
export const mLine = style({
  fontSize: vars.textMeta, color: "var(--m-muted)",
  selectors: { "&[data-asking]": { color: "var(--m-ink)" } },
});
