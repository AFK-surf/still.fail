import { style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";

export const runtimeTags = style({});
export const runtimeTag = style({
  display: "inline-flex", alignItems: "center", gap: "3px", padding: "0 5px", height: "17px", borderRadius: "5px",
  background: vars.hover, color: vars.muted, fontSize: "11px", fontWeight: "500",
});
export const spinner = style({});
export const runtimeMark = style({ width: "32px", height: "32px", background: vars.paper });
