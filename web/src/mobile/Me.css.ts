import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

export const mMe = style({ display: "flex", alignItems: "center", gap: "14px" });
export const mSignOut = style({
  display: "inline-flex", alignItems: "center", gap: "6px",
  padding: "0", border: "0", background: "none", color: "var(--m-red) !important", fontSize: `${vars.textBody} !important`,
  cursor: "pointer",
  selectors: { "&:disabled": { cursor: "default" } },
});
