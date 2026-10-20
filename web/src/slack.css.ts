import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const fieldErrorList = style({ fontSize: vars.textMeta, color: vars.red, margin: "0", paddingLeft: "18px" });
export const tokenFields = style({ display: "grid", gap: "12px" });
