// The sign-in page's look: the app's tokens and ground (global.css.ts), a column in the middle, its button the pill
// every still.fail page has.
import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const page = style({
  minHeight: "100%", display: "grid", placeContent: "center", justifyItems: "center", gap: "8px", padding: "24px",
  textAlign: "center",
});
export const illus = style({ display: "block", maxWidth: "100%", height: "auto" });
export const title = style({ margin: "8px 0 0", fontSize: vars.textTitle, fontWeight: "600" });
export const lead = style({ margin: "0", color: vars.muted, maxWidth: "30em" });
export const actions = style({ display: "flex", flexWrap: "wrap", justifyContent: "center", gap: "8px", marginTop: "4px" });
export const button = style({
  display: "inline-flex", alignItems: "center", height: "36px", padding: "0 16px", borderRadius: "999px", textDecoration: "none", border: `1px solid ${vars.lineStrong}`, background: vars.canvas,
  color: vars.text, fontSize: vars.textUi, fontWeight: "500", cursor: "pointer",
  selectors: { "&[aria-busy=\"true\"]": { cursor: "progress", opacity: ".7" } },
});
export const primary = style({ background: vars.primary, borderColor: vars.primary, color: vars.onPrimary });
