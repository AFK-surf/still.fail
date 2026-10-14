import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

export const mYou = style({
  display: "inline-block", marginLeft: "6px", padding: "0 6px", borderRadius: `calc(6px * ${vars.cornerScale})`,
  cornerShape: vars.cornerShape, background: "var(--m-accent-bg)",
  color: "var(--m-accent-ink)", fontSize: vars.textCaption, verticalAlign: "1px",
});
/** The name as the title, renamed by a tap. */
export const mRename = style({ cursor: "pointer", WebkitTapHighlightColor: "transparent" });
export const mLead = style({ padding: "0 16px 4px", fontSize: vars.textMeta, color: "var(--m-muted)" });
export const mGap = style({ height: "18px" });
/** Its mark at the icon row's end (its letter, muted, while it has none). */
export const mMark = style({ display: "grid", placeItems: "center", minWidth: 28, height: 28, color: "var(--m-muted)", fontWeight: 600 });
