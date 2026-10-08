import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

export const fieldErrorList = style({ fontSize: vars.textLabel, color: vars.red, margin: "0", paddingLeft: "18px" });
export const tokenFields = style({ display: "grid", gap: "12px" });
