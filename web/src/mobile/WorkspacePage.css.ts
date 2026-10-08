import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

export const mYou = style({
  display: "inline-block", marginLeft: "6px", padding: "0 6px", borderRadius: "6px", background: "var(--m-accent-bg)",
  color: "var(--m-accent-ink)", fontSize: vars.textCaption, verticalAlign: "1px",
});
/** The name as the title, renamed by a tap. */
export const mRename = style({ cursor: "pointer", WebkitTapHighlightColor: "transparent" });
export const mLead = style({ padding: "0 16px 4px", fontSize: vars.textMeta, color: "var(--m-muted)" });
export const mGap = style({ height: "18px" });
