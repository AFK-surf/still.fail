import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const mMe = style({ display: "flex", alignItems: "center", gap: "14px" });
export const mSignOut = style({
  display: "inline-flex", alignItems: "center", gap: "6px",
  padding: "0", border: "0", background: "none", color: "var(--m-red) !important", fontSize: `${vars.textBody} !important`,
  cursor: "pointer",
  selectors: { "&:disabled": { cursor: "default" } },
});
/** Room before deleting the account, apart from the rest (as leaving a workspace is: WorkspacePage.css.ts). */
export const mGap = style({ height: "18px" });
