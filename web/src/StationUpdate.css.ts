import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

export const notice = style({
  display: "flex", flexDirection: "column", gap: "3px", padding: "10px 16px", flexShrink: 0,
  fontSize: "12px", lineHeight: "18px", color: vars.muted, background: `var(--m-bg, ${vars.canvas})`,
});
export const title = style({ fontWeight: "500", color: vars.accentText });
