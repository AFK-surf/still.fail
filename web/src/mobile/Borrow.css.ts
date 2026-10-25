import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** The station another station's model comes from, after its name on its line: its mark, else its name. */
export const mFrom = style({
  display: "inline-flex", alignItems: "center", flex: "none", fontSize: vars.textMeta, fontWeight: 400, color: vars.muted, whiteSpace: "nowrap",
  // (stepped back to the subtle grey, not faded to half: 2.1:1, docs/ui-panels.md 对比度)
  selectors: { "&[data-faded]": { color: vars.subtle } },
});
/** A model not usable here till borrowed: its name faint. */
export const mFaded = style({ color: vars.muted });
/** Over a run settings' button: the model picked is not usable here yet. */
export const mBorrowNote = style({ margin: "0 18px 8px", fontSize: vars.textMeta, color: vars.muted });
